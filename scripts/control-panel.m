#import "control-panel.h"
#import "calendar-panel.h"
#import "app-menu.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

static NSPanel *controlPanel;
static NSString *controlDirectory;
static NSRect controlAnchor;
static double controlAway;
static BOOL controlBusy;
static NSDictionary *controlDocument, *controlPalette;
static NSString *dismissedRequest;
static BOOL colorsChanged;
static NSString *const controlNotification=@"local.dotfiles.desktop.controls";
static const CGFloat panelWidth=380;

static NSString *controlPython(BOOL (^executable)(NSString *)) {
    // Homebrew's versioned formula provides python3.14, not necessarily python3.
    for (NSString *path in @[@"/opt/homebrew/bin/python3.14",@"/usr/local/bin/python3.14",
                             @"/opt/homebrew/bin/python3",@"/usr/local/bin/python3",@"/usr/bin/python3"])
        if (executable(path)) return path;
    return nil;
}
static NSString *installedPython(void) {
    return controlPython(^BOOL(NSString *path) { return [NSFileManager.defaultManager isExecutableFileAtPath:path]; });
}

static NSString *panelSymbol(NSString *name) {
    return @{@"weather":@"cloud.sun.fill", @"cpu":@"cpu", @"gpu":@"square.3.layers.3d",
             @"memory":@"memorychip", @"battery":@"battery.100percent", @"volume":@"speaker.wave.2.fill",
             @"brightness":@"sun.max.fill", @"wifi":@"wifi", @"bluetooth":@"antenna.radiowaves.left.and.right",
             @"alerts":@"bell.badge.fill"}[name] ?: @"circle";
}
static NSString *weatherSymbol(NSString *condition) {
    return @{@"clear":@"sun.max.fill", @"night":@"moon.stars.fill", @"cloudy":@"cloud.fill",
             @"rain":@"cloud.rain.fill", @"snow":@"cloud.snow.fill", @"storm":@"cloud.bolt.rain.fill",
             @"fog":@"cloud.fog.fill"}[condition];
}
static BOOL statPanel(NSDictionary *document) {
    return [@[@"cpu",@"gpu",@"memory",@"battery"] containsObject:document[@"name"]];
}

void DFControlsAppearance(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path];
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *palette=[value isKindOfClass:NSDictionary.class] ? value : @{};
    if (![palette isEqual:controlPalette]) { controlPalette=palette; colorsChanged=YES; }
}
NSColor *DFPanelColor(unsigned fallback) {
    NSString *key=@{@(0x11151d):@"popup", @(0x2a3447):@"border", @(0xe6edf7):@"foreground",
                     @(0x94a3b8):@"muted", @(0x42c7ff):@"secondary", @(0x7c5cff):@"selection",
                     @(0xb8a6ff):@"accent", @(0x58657a):@"muted", @(0x202735):@"highlight"}[@(fallback)];
    NSString *hex=controlPalette[key ?: @""];
    unsigned rgb=fallback;
    if ([hex isKindOfClass:NSString.class] && hex.length==6) {
        NSScanner *scanner=[NSScanner scannerWithString:hex]; unsigned value;
        if ([scanner scanHexInt:&value] && scanner.isAtEnd) rgb=value;
    }
    return [NSColor colorWithSRGBRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
}

static BOOL validDocument(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return NO;
    NSArray *names=@[@"weather",@"volume",@"brightness",@"wifi",@"bluetooth",@"alerts",@"battery",@"cpu",@"gpu",@"memory"];
    if (![names containsObject:value[@"name"]] || ![value[@"revision"] isKindOfClass:NSString.class]
        || ![value[@"request"] isKindOfClass:NSString.class] || [value[@"request"] length]>64) return NO;
    NSArray *rows=value[@"rows"];
    if (![rows isKindOfClass:NSArray.class] || !rows.count || rows.count>14) return NO;
    for (id row in rows) if (![row isKindOfClass:NSDictionary.class] || ![row[@"text"] isKindOfClass:NSString.class]
        || [row[@"text"] length]>512 || ![row[@"action"] isKindOfClass:NSNumber.class]) return NO;
    id slider=value[@"slider"];
    if (slider && (![slider isKindOfClass:NSNumber.class] || !isfinite([slider doubleValue]) || [slider doubleValue]<0 || [slider doubleValue]>100
        || ![@[@"volume",@"brightness"] containsObject:value[@"name"]])) return NO;
    NSArray *history=value[@"history"];
    if (history && (![history isKindOfClass:NSArray.class] || history.count>60)) return NO;
    for (id sample in history) if (![sample isKindOfClass:NSNumber.class] || !isfinite([sample doubleValue]) || [sample doubleValue]<0 || [sample doubleValue]>1) return NO;
    id subtitle=value[@"subtitle"], meter=value[@"meter"], forecast=value[@"forecast"];
    if (subtitle && (![subtitle isKindOfClass:NSString.class] || [subtitle length]>160)) return NO;
    if (meter && (![meter isKindOfClass:NSNumber.class] || !isfinite([meter doubleValue]) || [meter doubleValue]<0 || [meter doubleValue]>1 || !statPanel(value))) return NO;
    if (forecast && (![value[@"name"] isEqual:@"weather"] || ![forecast isKindOfClass:NSArray.class] || [forecast count]>6)) return NO;
    for (id hour in forecast) {
        if (![hour isKindOfClass:NSDictionary.class]) return NO;
        for (NSString *key in @[@"hour",@"temperature",@"condition",@"precipitation"])
            if (![hour[key] isKindOfClass:NSString.class] || [hour[key] length]>16) return NO;
        if (!weatherSymbol(hour[@"condition"])) return NO;
    }
    return YES;
}
static NSDictionary *readDocument(void) {
    NSString *path=[controlDirectory stringByAppendingPathComponent:@"bar/native-panel.json"];
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);
    if (fd<0) return nil;
    struct stat status;
    BOOL safe=fstat(fd,&status)==0 && S_ISREG(status.st_mode) && status.st_uid==getuid()
        && (status.st_mode&0077)==0 && status.st_size>0 && status.st_size<32768;
    NSData *data=safe ? [[[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES] readDataToEndOfFile] : nil;
    if (!safe) close(fd);
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return validDocument(value) ? value : nil;
}

@interface ControlSurface : NSView
@end
@implementation ControlSurface
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(__unused NSRect)dirty {
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,0.5,0.5) xRadius:16 yRadius:16];
    [DFPanelColor(0x11151d) setFill]; [shape fill]; [DFPanelColor(0x2a3447) setStroke]; shape.lineWidth=1; [shape stroke];
    // A short accent rule gives every panel the same restrained signature.
    [[DFPanelColor(0xb8a6ff) colorWithAlphaComponent:0.65] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(24,0,42,2) xRadius:1 yRadius:1] fill];
}
@end

@interface ControlDocument : NSView
@end
@implementation ControlDocument
- (BOOL)isFlipped { return YES; }
@end

@interface ControlRow : NSButton
@property BOOL hovered;
@end
@implementation ControlRow
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas.copy) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(__unused NSEvent *)event { self.hovered=YES; self.needsDisplay=YES; }
- (void)mouseExited:(__unused NSEvent *)event { self.hovered=NO; self.needsDisplay=YES; }
- (void)drawRect:(__unused NSRect)dirty {
    if (self.hovered || self.highlighted) {
        [DFPanelColor(0x202735) setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,0,1) xRadius:9 yRadius:9] fill];
    }
    NSDictionary *style=@{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium], NSForegroundColorAttributeName:DFPanelColor(0xb8a6ff)};
    NSString *text=self.title;
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new]; paragraph.lineBreakMode=NSLineBreakByTruncatingTail;
    NSMutableDictionary *attributes=style.mutableCopy; attributes[NSParagraphStyleAttributeName]=paragraph;
    [[DFPanelColor(0xb8a6ff) colorWithAlphaComponent:0.09] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(8,6,24,24) xRadius:7 yRadius:7] fill];
    NSString *glyph=[text hasPrefix:@"●"] ? @"●" : @"›";
    [glyph drawAtPoint:NSMakePoint(15,9) withAttributes:style];
    if ([text hasPrefix:@"● "] || [text hasPrefix:@"○ "]) text=[text substringFromIndex:2];
    [text drawInRect:NSMakeRect(42,9,self.bounds.size.width-70,18) withAttributes:attributes];
    [@"›" drawAtPoint:NSMakePoint(self.bounds.size.width-21,7) withAttributes:style];
}
@end

@interface ControlGraph : NSView
@property NSArray<NSNumber *> *samples;
@end
@implementation ControlGraph
- (void)drawRect:(__unused NSRect)dirty {
    NSRect area=NSMakeRect(0,18,self.bounds.size.width-2,self.bounds.size.height-24);
    [[DFPanelColor(0x2a3447) colorWithAlphaComponent:0.6] setStroke];
    for (NSInteger i=0;i<3;i++) { CGFloat y=NSMinY(area)+i*area.size.height/2;
        NSBezierPath *line=[NSBezierPath bezierPath]; [line moveToPoint:NSMakePoint(NSMinX(area),y)]; [line lineToPoint:NSMakePoint(NSMaxX(area),y)]; line.lineWidth=0.5; [line stroke]; }
    if (self.samples.count<2) return;
    NSBezierPath *line=[NSBezierPath bezierPath];
    for (NSUInteger i=0;i<self.samples.count;i++) {
        NSPoint point=NSMakePoint(NSMinX(area)+i*area.size.width/(self.samples.count-1), NSMinY(area)+self.samples[i].doubleValue*area.size.height);
        if (!i) [line moveToPoint:point]; else [line lineToPoint:point];
    }
    NSBezierPath *fill=line.copy; [fill lineToPoint:NSMakePoint(NSMaxX(area),NSMinY(area))]; [fill lineToPoint:area.origin]; [fill closePath];
    [[DFPanelColor(0x42c7ff) colorWithAlphaComponent:0.10] setFill]; [fill fill];
    [DFPanelColor(0x42c7ff) setStroke]; line.lineWidth=1.8; [line stroke];
    NSPoint latest=NSMakePoint(NSMaxX(area),NSMinY(area)+self.samples.lastObject.doubleValue*area.size.height);
    [DFPanelColor(0x42c7ff) setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(latest.x-2.5,latest.y-2.5,5,5)] fill];
    NSDictionary *caption=@{NSFontAttributeName:[NSFont systemFontOfSize:9 weight:NSFontWeightMedium],NSForegroundColorAttributeName:DFPanelColor(0x94a3b8)};
    [@"RECENT UTILIZATION" drawAtPoint:NSMakePoint(0,2) withAttributes:caption];
    [@"0–100%" drawAtPoint:NSMakePoint(NSMaxX(area)-42,2) withAttributes:caption];
}
@end

@interface ControlTile : NSView
@end
@implementation ControlTile
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(__unused NSRect)dirty {
    [[DFPanelColor(0x202735) colorWithAlphaComponent:0.55] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,0.5,0.5) xRadius:11 yRadius:11] fill];
}
@end

@interface ControlMeter : NSView
@property double value;
@end
@implementation ControlMeter
- (void)drawRect:(__unused NSRect)dirty {
    [DFPanelColor(0x202735) setFill]; [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:3 yRadius:3] fill];
    if (self.value>0) {
        NSRect fill=self.bounds; fill.size.width*=self.value;
        [DFPanelColor(0xb8a6ff) setFill]; [[NSBezierPath bezierPathWithRoundedRect:fill xRadius:3 yRadius:3] fill];
    }
}
@end

@interface ControlView : ControlSurface
- (void)render;
- (void)clicked:(NSButton *)sender;
- (void)slid:(NSSlider *)sender;
@end
static ControlView *controlView;
static void text(NSView *parent, NSString *value, NSRect rect, CGFloat size, NSColor *color, NSFontWeight weight) {
    NSTextField *label=[NSTextField labelWithString:value]; label.frame=rect; label.textColor=color;
    label.font=[NSFont systemFontOfSize:size weight:weight]; label.lineBreakMode=NSLineBreakByTruncatingTail;
    [parent addSubview:label];
}
static void symbol(NSView *parent, NSString *name, NSRect rect, NSColor *color) {
    NSImageView *image=[[NSImageView alloc] initWithFrame:rect];
    image.image=[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    image.contentTintColor=color; image.imageScaling=NSImageScaleProportionallyUpOrDown; [parent addSubview:image];
}
static CGFloat rowHeight(NSDictionary *row) {
    return ![row[@"action"] boolValue] && ([[row[@"text"] componentsSeparatedByString:@" · "] count]>2 || [row[@"text"] length]>44) ? 52 : 36;
}
static CGFloat rowsHeight(NSArray *rows) {
    CGFloat height=0; for (NSUInteger i=1;i<rows.count;i++) height+=rowHeight(rows[i]); return height;
}
static CGFloat bodyHeight(NSDictionary *document) {
    NSUInteger count=[document[@"rows"] count]-1;
    CGFloat height=statPanel(document) ? ceil(count/2.0)*74 : rowsHeight(document[@"rows"]);
    NSArray *rows=document[@"rows"];
    if ([document[@"name"] isEqual:@"weather"] && rows.count>2 && [rows[2][@"text"] isEqual:document[@"subtitle"]]) height-=rowHeight(rows[2]);
    return height;
}
static CGFloat headerHeight(NSDictionary *document) {
    return 110+(document[@"slider"] ? 54 : 0)+([document[@"history"] count] ? 96 : 0)
        +(document[@"meter"] ? 18 : 0)+([document[@"forecast"] count] ? 108 : 0);
}
static void runControl(NSString *kind, NSString *argument) {
    if (controlBusy || !controlDocument) return;
    NSString *python=installedPython();
    if (!python) return;
    NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:python];
    NSString *script=[NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar/plugins/controls.py"];
    task.arguments=@[@"-B",script,kind,controlDocument[@"name"],argument,controlDocument[@"revision"]];
    NSMutableDictionary *environment=NSProcessInfo.processInfo.environment.mutableCopy;
    environment[@"PATH"]=@"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"; task.environment=environment;
    task.standardInput=NSFileHandle.fileHandleWithNullDevice; task.standardOutput=NSFileHandle.fileHandleWithNullDevice; task.standardError=NSFileHandle.fileHandleWithNullDevice;
    task.terminationHandler=^(__unused NSTask *finished) { dispatch_async(dispatch_get_main_queue(),^{ controlBusy=NO; }); };
    controlBusy=[task launchAndReturnError:nil];
}
@implementation ControlView
- (void)clicked:(NSButton *)sender { runControl(@"native-action",[@(sender.tag) stringValue]); }
- (void)slid:(NSSlider *)sender { runControl(@"native-slider",[NSString stringWithFormat:@"%.0f",sender.doubleValue]); }
- (void)render {
    for (NSView *view in self.subviews.copy) [view removeFromSuperview];
    NSArray *rows=controlDocument[@"rows"];
    NSString *title=rows.firstObject[@"text"];
    NSArray *hero=[title componentsSeparatedByString:@" · "];
    symbol(self,panelSymbol(controlDocument[@"name"]),NSMakeRect(24,20,16,16),DFPanelColor(0xb8a6ff));
    text(self,[hero.firstObject uppercaseString],NSMakeRect(48,21,230,16),10,DFPanelColor(0x94a3b8),NSFontWeightSemibold);
    text(self,hero.count>1 ? [[hero subarrayWithRange:NSMakeRange(1,hero.count-1)] componentsJoinedByString:@" · "] : title,
         NSMakeRect(22,42,336,40),30,DFPanelColor(0xe6edf7),NSFontWeightSemibold);
    NSString *subtitle=controlDocument[@"subtitle"];
    if (!subtitle.length) subtitle=@{@"volume":@"Output level & devices", @"brightness":@"Built-in display",
        @"wifi":@"Wireless connection", @"bluetooth":@"Paired devices", @"battery":@"Power & battery health",
        @"alerts":@"Notifications & system health", @"weather":@"Local forecast"}[controlDocument[@"name"]] ?: @"";
    text(self,subtitle,NSMakeRect(24,84,332,17),11,DFPanelColor(0x94a3b8),NSFontWeightRegular);
    CGFloat y=110;
    if (controlDocument[@"meter"]) {
        ControlMeter *meter=[[ControlMeter alloc] initWithFrame:NSMakeRect(24,y,332,5)];
        meter.value=[controlDocument[@"meter"] doubleValue]; [self addSubview:meter]; y+=18;
    }
    if (controlDocument[@"slider"]) {
        NSSlider *slider=[NSSlider sliderWithValue:[controlDocument[@"slider"] doubleValue] minValue:0 maxValue:100 target:self action:@selector(slid:)];
        slider.frame=NSMakeRect(22,y,336,26); slider.continuous=NO; slider.controlSize=NSControlSizeRegular;
        slider.trackFillColor=DFPanelColor(0xb8a6ff);
        slider.accessibilityLabel=[controlDocument[@"name"] isEqual:@"volume"] ? @"Output volume" : @"Display brightness";
        [self addSubview:slider];
        text(self,@"0%",NSMakeRect(24,y+29,40,14),9,DFPanelColor(0x94a3b8),NSFontWeightMedium);
        text(self,@"100%",NSMakeRect(326,y+29,34,14),9,DFPanelColor(0x94a3b8),NSFontWeightMedium); y+=54;
    }
    if ([controlDocument[@"history"] count]) {
        ControlGraph *graph=[[ControlGraph alloc] initWithFrame:NSMakeRect(24,y,332,82)]; graph.samples=controlDocument[@"history"]; [self addSubview:graph]; y+=96;
    }
    NSArray *forecast=controlDocument[@"forecast"];
    if (forecast.count) {
        CGFloat width=(332-5*4)/6.0;
        for (NSUInteger i=0;i<forecast.count;i++) {
            NSDictionary *hour=forecast[i];
            ControlTile *tile=[[ControlTile alloc] initWithFrame:NSMakeRect(24+i*(width+4),y,width,94)];
            text(tile,hour[@"hour"],NSMakeRect(7,8,width-10,14),10,DFPanelColor(0x94a3b8),NSFontWeightMedium);
            symbol(tile,weatherSymbol(hour[@"condition"]),NSMakeRect((width-20)/2,27,20,20),DFPanelColor(0x42c7ff));
            text(tile,hour[@"temperature"],NSMakeRect(6,52,width-8,18),12,DFPanelColor(0xe6edf7),NSFontWeightSemibold);
            text(tile,hour[@"precipitation"],NSMakeRect(8,75,width-10,12),9,DFPanelColor(0x42c7ff),NSFontWeightMedium);
            [self addSubview:tile];
        }
        y+=108;
    }
    CGFloat contentHeight=MAX(1,bodyHeight(controlDocument));
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(12,y,356,MIN(contentHeight,360))];
    scroll.drawsBackground=NO; scroll.hasVerticalScroller=YES; scroll.autohidesScrollers=YES; scroll.scrollerStyle=NSScrollerStyleOverlay; scroll.borderType=NSNoBorder;
    // The document is flipped, but has no second surface behind the rows.
    NSView *document=[[ControlDocument alloc] initWithFrame:NSMakeRect(0,0,356,contentHeight)];
    CGFloat rowY=0;
    for (NSUInteger i=1;i<rows.count;i++) {
        if ([controlDocument[@"name"] isEqual:@"weather"] && i==2 && [rows[i][@"text"] isEqual:controlDocument[@"subtitle"]]) continue;
        NSDictionary *row=rows[i]; CGFloat height=rowHeight(row); NSRect rect=NSMakeRect(0,rowY,356,height-2); rowY+=height;
        if ([row[@"action"] boolValue]) {
            ControlRow *button=[[ControlRow alloc] initWithFrame:rect]; button.title=row[@"text"]; button.bordered=NO; button.tag=i;
            button.target=self; button.action=@selector(clicked:); [document addSubview:button];
        } else if (statPanel(controlDocument)) {
            NSUInteger index=i-1;
            NSArray *parts=[row[@"text"] componentsSeparatedByString:@" · "];
            ControlTile *tile=[[ControlTile alloc] initWithFrame:NSMakeRect(10+(index%2)*172,(index/2)*74,164,66)];
            text(tile,parts.count>1 ? parts.firstObject : @"STATUS",NSMakeRect(12,9,140,14),10,DFPanelColor(0x94a3b8),NSFontWeightMedium);
            NSString *value=parts.count>1 ? [[parts subarrayWithRange:NSMakeRange(1,parts.count-1)] componentsJoinedByString:@" · "] : parts.firstObject;
            text(tile,value,NSMakeRect(12,29,140,24),16,DFPanelColor(0xe6edf7),NSFontWeightSemibold);
            [document addSubview:tile];
        } else {
            NSArray *parts=[row[@"text"] componentsSeparatedByString:@" · "];
            text(document,parts.firstObject,NSMakeRect(10,rect.origin.y+9,parts.count>1 ? 142 : 334,18),12,DFPanelColor(0x94a3b8),NSFontWeightRegular);
            if (parts.count>1) {
                NSTextField *value=[NSTextField labelWithString:[[parts subarrayWithRange:NSMakeRange(1,parts.count-1)] componentsJoinedByString:@" · "]];
                value.frame=NSMakeRect(146,rect.origin.y+9,198,height-12); value.alignment=NSTextAlignmentRight;
                value.font=[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium]; value.textColor=DFPanelColor(0xe6edf7);
                value.lineBreakMode=NSLineBreakByWordWrapping; value.maximumNumberOfLines=2; [document addSubview:value];
            }
        }
    }
    scroll.documentView=document; [self addSubview:scroll];
    self.needsDisplay=YES;
}
@end

static void showControls(void) {
    NSDictionary *document=readDocument(); if (!document) return;
    if ([document[@"request"] isEqual:dismissedRequest]) return;
    BOOL same=[controlDocument[@"name"] isEqual:document[@"name"]] && controlPanel.visible;
    controlDocument=document; DFCalendarHide(); DFMenusHide();
    if (!controlPanel) {
        controlPanel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,panelWidth,200) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        controlPanel.level=CGWindowLevelForKey(kCGStatusWindowLevelKey)+2;
        controlPanel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorStationary;
        controlPanel.opaque=NO; controlPanel.backgroundColor=NSColor.clearColor; controlPanel.hasShadow=YES; controlPanel.hidesOnDeactivate=NO;
        controlView=[[ControlView alloc] initWithFrame:NSMakeRect(0,0,panelWidth,200)]; controlPanel.contentView=controlView;
    }
    CGFloat height=headerHeight(document)+MIN(bodyHeight(document),360)+16;
    NSPoint pointer=NSEvent.mouseLocation; NSScreen *screen=NSScreen.mainScreen;
    for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(pointer,candidate.frame)) screen=candidate;
    NSRect frame=screen.frame; CGFloat top=NSMaxY(frame)-screen.safeAreaInsets.top-44;
    CGFloat x=same ? controlPanel.frame.origin.x : MAX(NSMinX(frame)+12,MIN(pointer.x-panelWidth/2,NSMaxX(frame)-panelWidth-12));
    if (!same) controlAnchor=NSMakeRect(pointer.x-44,top,88,NSMaxY(frame)-top);
    [controlPanel setFrame:NSMakeRect(x,MAX(NSMinY(frame)+12,top-height),panelWidth,height) display:NO];
    controlView.frame=NSMakeRect(0,0,panelWidth,height); [controlView render]; controlAway=0; [controlPanel orderFrontRegardless];
}
void DFControlsInitialize(NSString *directory) {
    controlDirectory=directory;
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:controlNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if ([note.object isEqual:@"show"]) showControls(); else if ([note.object isEqual:@"hide"]) DFControlsHide();
    }];
}
void DFControlsNotify(NSString *action) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:controlNotification object:action userInfo:nil deliverImmediately:YES];
}
void DFControlsHide(void) { if (controlPanel.visible) dismissedRequest=controlDocument[@"request"]; [controlPanel orderOut:nil]; controlAway=0; }
BOOL DFControlsContainsPointer(NSPoint pointer) {
    return controlPanel.visible && (NSPointInRect(pointer,NSInsetRect(controlPanel.frame,-4,-4)) || NSPointInRect(pointer,controlAnchor));
}
void DFControlsTick(double now, NSPoint pointer) {
    if (colorsChanged) { colorsChanged=NO; DFCalendarAppearance(); if (controlPanel.visible) [controlView render]; DFMenusHide(); }
    if (!controlPanel.visible) return;
    if (DFControlsContainsPointer(pointer)) controlAway=0;
    else if (!controlAway) controlAway=now;
    else if (now-controlAway>0.32) DFControlsHide();
}
NSDictionary *DFControlsStatus(void) { return @{@"visible":@(controlPanel.visible),@"name":controlDocument[@"name"] ?: @"",@"backend_available":@(installedPython()!=nil)}; }
int DFControlsSelfTest(void) {
    NSString *python=controlPython(^BOOL(NSString *path) { return [path hasSuffix:@"python3.14"]; });
    if (![python isEqual:@"/opt/homebrew/bin/python3.14"]) return 1;
    python=controlPython(^BOOL(NSString *path) { return [path hasPrefix:@"/usr/local/"]; });
    if (![python isEqual:@"/usr/local/bin/python3.14"]) return 1;
    if (controlPython(^BOOL(__unused NSString *path) { return NO; })) return 1;
    NSDictionary *valid=@{@"name":@"volume",@"revision":@"1",@"request":@"1",@"rows":@[@{@"text":@"Sound",@"action":@NO}],@"slider":@50};
    if (!validDocument(valid)) return 1;
    for (NSString *key in @[@"name",@"rows",@"slider",@"history"]) {
        NSMutableDictionary *bad=valid.mutableCopy; bad[key]=@"invalid"; if (validDocument(bad)) return 1;
    }
    NSMutableDictionary *bad=valid.mutableCopy; bad[@"slider"]=@101; if (validDocument(bad)) return 1;
    for (id value in @[@(-0.1),@1.1,@(NAN),@"50"]) {
        bad=@{@"name":@"cpu",@"revision":@"1",@"request":@"1",@"rows":valid[@"rows"],@"meter":value}.mutableCopy;
        if (validDocument(bad)) return 1;
    }
    bad=valid.mutableCopy; bad[@"subtitle"]=@50; if (validDocument(bad)) return 1;
    NSDictionary *hour=@{@"hour":@"10am",@"temperature":@"50°F",@"condition":@"clear",@"precipitation":@"0%"};
    NSMutableDictionary *weather=@{@"name":@"weather",@"revision":@"1",@"request":@"1",@"rows":valid[@"rows"],@"forecast":@[hour]}.mutableCopy;
    if (!validDocument(weather)) return 1;
    for (id value in @[@"invalid",@[@"invalid"],@[hour,hour,hour,hour,hour,hour,hour]]) {
        weather[@"forecast"]=value; if (validDocument(weather)) return 1;
    }
    bad=hour.mutableCopy; bad[@"condition"]=@"arbitrary.symbol";
    weather[@"forecast"]=@[bad]; if (validDocument(weather)) return 1;
    puts("Native control payload: types, allowlists, bounded sliders/meters, malformed history and forecast cards passed."); return 0;
}
BOOL DFControlsPreview(NSString *path, NSString *kind) {
    // A deterministic UI fixture, never personal device or account data.
    NSDictionary *fixtures=@{
        @"cpu":@[@"CPU · 24%",@"Temperature · 113°F",@"Power · 8.4 W",@"System power · 21.8 W",@"Fan 1 · 0 RPM"],
        @"gpu":@[@"GPU · 38%",@"Temperature · 109°F",@"Power · 12.6 W",@"System power · 29.4 W",@"Fan 1 · 0 RPM"],
        @"memory":@[@"Memory · 18.2 GiB",@"Used · 18.20 GiB",@"Total · 64.00 GiB",@"Swap used · 0.00 GiB",@"Swap capacity · 0.00 GiB"],
        @"battery":@[@"Battery · 84%",@"State · Charging",@"Estimate · 1:22 remaining",@"Cycles · 142",@"Temperature · 88°F"],
        @"weather":@[@"Weather · 54°F",@"Mitchell, OR · 97750",@"Partly cloudy",@"Wind · W 5 to 10 mph",@"Precipitation · 10%",@"Tonight · 41°F · Mostly clear",@"Saturday · 62°F · Sunny",@"NWS · updated 4 min ago",@"Refresh forecast"],
        @"volume":@[@"Sound · 42%",@"Mute",@"● MacBook Pro Speakers",@"○ Studio Display"],
        @"brightness":@[@"Display · 68%",@"Built-in display brightness"],
        @"wifi":@[@"Wi-Fi · On",@"Turn Wi-Fi off",@"Address · 192.0.2.24",@"Studio network",@"Native Wi-Fi controls"],
        @"bluetooth":@[@"Bluetooth · On",@"Turn Bluetooth off",@"● Headphones",@"○ Keyboard"],
        @"alerts":@[@"Notifications · Quick controls",@"Notification Center",@"Focus / Control Center",@"System health",@"All clear"]};
    NSArray *labels=fixtures[kind]; if (!labels) return NO;
    NSMutableArray *rows=NSMutableArray.new;
    for (NSUInteger i=0;i<labels.count;i++) {
        BOOL action=i>0 && (([kind isEqual:@"volume"] || [kind isEqual:@"bluetooth"])
            || ([kind isEqual:@"wifi"] && (i==1 || i==4)) || ([kind isEqual:@"alerts"] && i<3)
            || ([kind isEqual:@"weather"] && i==labels.count-1));
        [rows addObject:@{@"text":labels[i],@"action":@(action)}];
    }
    NSMutableDictionary *fixture=@{@"name":kind,@"revision":@"preview",@"request":@"preview",@"rows":rows}.mutableCopy;
    if ([@[@"cpu",@"gpu",@"memory"] containsObject:kind]) {
        NSNumber *load=[kind isEqual:@"gpu"] ? @0.38 : [kind isEqual:@"memory"] ? @0.284375 : @0.24;
        fixture[@"history"]=@[@0.12,@0.18,@0.15,@0.32,@0.25,@0.38,@0.22,load];
        fixture[@"meter"]=load;
        fixture[@"subtitle"]=[kind isEqual:@"memory"] ? @"Unified memory" : @"Apple Silicon · utilization";
    }
    if ([kind isEqual:@"battery"]) fixture[@"meter"]=@0.84;
    if ([kind isEqual:@"volume"] || [kind isEqual:@"brightness"]) fixture[@"slider"]=[kind isEqual:@"volume"] ? @42 : @68;
    if ([kind isEqual:@"weather"]) {
        fixture[@"subtitle"]=@"Partly cloudy";
        NSMutableArray *hours=NSMutableArray.new;
        for (NSUInteger i=0;i<6;i++) [hours addObject:@{@"hour":@[@"10am",@"11am",@"12pm",@"1pm",@"2pm",@"3pm"][i],
            @"temperature":@[@"54°F",@"56°F",@"59°F",@"61°F",@"62°F",@"60°F"][i],
            @"condition":i<2 ? @"cloudy" : @"clear",@"precipitation":i<2 ? @"10%" : @"0%"}];
        fixture[@"forecast"]=hours;
    }
    if (!validDocument(fixture)) return NO;
    controlDocument=fixture;
    CGFloat height=headerHeight(fixture)+MIN(bodyHeight(fixture),360)+16;
    controlView=[[ControlView alloc] initWithFrame:NSMakeRect(0,0,panelWidth,height)]; [controlView render];
    NSBitmapImageRep *bitmap=[controlView bitmapImageRepForCachingDisplayInRect:controlView.bounds];
    [controlView cacheDisplayInRect:controlView.bounds toBitmapImageRep:bitmap];
    return [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}
