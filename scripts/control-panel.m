#import "control-panel.h"
#import "panel-style.h"
#import "calendar-panel.h"
#import "app-menu.h"
#import "panel-request.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

static NSPanel *controlPanel;
static NSString *controlDirectory;
static NSRect controlAnchor;
static NSRect controlItemAnchor;
static double controlAway;
static BOOL controlBusy;
static NSUInteger controlButtons;
static BOOL renderPending;
static double passthroughUntil, displayCoverUntil;
static NSString *displayCoverToken;
static NSDictionary *controlDocument, *controlPalette;
static NSString *dismissedRequest;
static NSString *controlDismissal;
static BOOL colorsChanged;
static void (^controlWillShow)(void);
void DFControlsSetWillShow(void (^callback)(void)) {controlWillShow=[callback copy];}
#ifndef DF_CONTROL_NOTIFICATION
#define DF_CONTROL_NOTIFICATION "local.dotfiles.desktop.controls"
#endif
static NSString *const controlNotification=@DF_CONTROL_NOTIFICATION;
static CGFloat panelWidth(NSDictionary *document) {
    return [document[@"name"] isEqual:@"weather"] ? 380 :
        [@[@"cpu",@"gpu",@"memory",@"battery"] containsObject:document[@"name"]] ? 344 : 320;
}
static NSRect panelFrame(NSRect screen, NSRect anchor, CGFloat width, CGFloat height) {
    width=MIN(width,screen.size.width-24);
    CGFloat top=MIN(NSMinY(anchor)-8,NSMaxY(screen)-12);
    height=MIN(height,MAX(48,top-NSMinY(screen)-12));
    return NSMakeRect(MAX(NSMinX(screen)+12,MIN(NSMaxX(anchor)-width,NSMaxX(screen)-width-12)),
                      MAX(NSMinY(screen)+12,top-height),width,height);
}
static BOOL outsidePress(NSUInteger previous, NSUInteger current, NSPoint point, NSRect panel, NSRect bridge) {
    return current && !previous && !NSPointInRect(point,panel) && !NSPointInRect(point,bridge);
}

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
             @"brightness":@"display", @"wifi":@"wifi", @"bluetooth":@"antenna.radiowaves.left.and.right",
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
    for (NSDictionary *row in rows) {
        for (NSString *key in @[@"detail",@"hint"])
            if (row[key] && (![row[key] isKindOfClass:NSString.class] || [row[key] length]>160)) return NO;
        for (NSString *key in @[@"selected",@"section"])
            if (row[key] && ![row[key] isKindOfClass:NSNumber.class]) return NO;
    }
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
    id daily=value[@"daily"];
    if (daily && (![value[@"name"] isEqual:@"weather"] || ![daily isKindOfClass:NSArray.class] || [daily count]>6)) return NO;
    for (id day in daily) {
        if (![day isKindOfClass:NSDictionary.class]) return NO;
        for (NSString *key in @[@"day",@"date",@"high",@"low",@"condition"])
            if (![day[key] isKindOfClass:NSString.class] || [day[key] length]>16) return NO;
        if (!weatherSymbol(day[@"condition"])) return NO;
    }
    id pinned=value[@"pinned"], anchors=value[@"anchors"];
    if (pinned && (![pinned isKindOfClass:NSNumber.class] || ![@[@NO,@YES] containsObject:pinned])) return NO;
    if (anchors && (![anchors isKindOfClass:NSArray.class] || [anchors count]>8)) return NO;
    for (id anchor in anchors) {
        if (![anchor isKindOfClass:NSDictionary.class]) return NO;
        for (NSString *key in @[@"x",@"y",@"width",@"height"])
            if (![anchor[key] isKindOfClass:NSNumber.class] || !isfinite([anchor[key] doubleValue]) || fabs([anchor[key] doubleValue])>100000) return NO;
        if ([anchor[@"width"] doubleValue]<=0 || [anchor[@"width"] doubleValue]>1024 || [anchor[@"height"] doubleValue]<=0 || [anchor[@"height"] doubleValue]>256) return NO;
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
@property CGFloat anchorX;
@end
@implementation ControlSurface
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(__unused NSRect)dirty {
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,0.5,0.5) xRadius:16 yRadius:16];
    [DFPanelColor(0x11151d) setFill]; [shape fill]; [DFPanelColor(0x2a3447) setStroke]; shape.lineWidth=1; [shape stroke];
    // A short accent rule gives every panel the same restrained signature.
    [[DFPanelColor(0xb8a6ff) colorWithAlphaComponent:0.65] setFill];
    CGFloat center=MAX(22,MIN(self.anchorX ?: self.bounds.size.width-32,self.bounds.size.width-22));
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(center-12,0,24,2) xRadius:1 yRadius:1] fill];
}
@end

@interface ControlDocument : NSView
@end
@implementation ControlDocument
- (BOOL)isFlipped { return YES; }
@end

@interface ControlRow : DFPanelButton
@property BOOL selected;
@property NSString *detail;
@property NSString *hint;
@end
@implementation ControlRow
- (void)drawRect:(__unused NSRect)dirty {
    if (self.highlighted) {
        [DFPanelColor(0x202735) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,2,1) xRadius:7 yRadius:7] fill];
    }
    NSDictionary *style=@{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium], NSForegroundColorAttributeName:DFPanelColor(0xe6edf7)};
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new]; paragraph.lineBreakMode=NSLineBreakByTruncatingTail;
    NSMutableDictionary *attributes=style.mutableCopy; attributes[NSParagraphStyleAttributeName]=paragraph;
    NSString *detail=self.hovered && self.hint.length ? self.hint : self.detail ?: @"";
    NSDictionary *detailStyle=@{NSFontAttributeName:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium], NSForegroundColorAttributeName:DFPanelColor(self.hovered || self.selected ? 0xb8a6ff : 0x94a3b8)};
    CGFloat trailing=detail.length ? MIN(100,[detail sizeWithAttributes:detailStyle].width+12) : 0;
    [self.title drawInRect:NSMakeRect(24,8,self.bounds.size.width-36-trailing,18) withAttributes:attributes];
    if (self.selected) [@"✓" drawAtPoint:NSMakePoint(8,8) withAttributes:style];
    if (detail.length) [detail drawInRect:NSMakeRect(self.bounds.size.width-trailing,9,trailing-8,16) withAttributes:detailStyle];
}
@end

@interface HeaderPower : ControlRow
@end
@implementation HeaderPower
- (void)drawRect:(__unused NSRect)dirty {
    NSDictionary *attributes=@{NSFontAttributeName:[NSFont systemFontOfSize:20 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName:DFPanelColor(self.hovered || self.highlighted ? 0xb8a6ff : 0xe6edf7)};
    CGFloat width=[self.title sizeWithAttributes:attributes].width;
    if (self.hovered || self.highlighted) {
        [DFPanelColor(0x202735) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(self.bounds.size.width-width-16,2,width+16,30) xRadius:7 yRadius:7] fill];
    }
    [self.title drawInRect:NSMakeRect(self.bounds.size.width-width-6,4,width+2,28) withAttributes:attributes];
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

// Native inactive-window drawing can desaturate trackFillColor. Paint only the
// track ourselves; NSSliderCell retains its native knob, input and accessibility.
@interface ControlSliderCell : NSSliderCell
@end
@implementation ControlSliderCell
- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped {
    NSRect track=NSMakeRect(NSMinX(rect),NSMidY(rect)-2,rect.size.width,4);
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:track xRadius:2 yRadius:2];
    [DFPanelColor(0x202735) setFill];[shape fill];
    double range=self.maxValue-self.minValue;
    double fraction=range>0 ? MAX(0,MIN(1,(self.doubleValue-self.minValue)/range)) : 0;
    if (fraction<=0) return;
    NSRect knob=[self knobRectFlipped:flipped];
    BOOL reversed=self.controlView.userInterfaceLayoutDirection==NSUserInterfaceLayoutDirectionRightToLeft;
    CGFloat end=fraction>=1 ? (reversed ? NSMinX(track) : NSMaxX(track)) :
        NSIsEmptyRect(knob) ? NSMinX(track)+track.size.width*(reversed ? 1-fraction : fraction) : NSMidX(knob);
    end=MAX(NSMinX(track),MIN(NSMaxX(track),end));
    NSRect fill=track;fill.origin.x=reversed ? end : NSMinX(track);
    fill.size.width=reversed ? NSMaxX(track)-end : end-NSMinX(track);
    [NSGraphicsContext saveGraphicsState];[shape addClip];
    [DFPanelColor(0xb8a6ff) setFill];NSRectFill(fill);[NSGraphicsContext restoreGraphicsState];
}
@end

@interface ControlView : ControlSurface
@property NSString *documentName;
@property NSString *callbackName;
@property NSString *callbackRevision;
- (void)render;
- (void)clicked:(NSButton *)sender;
- (void)slid:(NSSlider *)sender;
@end
static ControlView *controlView;
static NSTextField *text(NSView *parent, NSString *value, NSRect rect, CGFloat size, NSColor *color, NSFontWeight weight) {
    NSTextField *label=[NSTextField labelWithString:value]; label.frame=rect; label.textColor=color;
    label.font=[NSFont systemFontOfSize:size weight:weight]; label.lineBreakMode=NSLineBreakByTruncatingTail;
    [parent addSubview:label]; return label;
}
static void symbol(NSView *parent, NSString *name, NSRect rect, NSColor *color) {
    NSImageView *image=[[NSImageView alloc] initWithFrame:rect];
    image.image=[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    image.contentTintColor=color; image.imageScaling=NSImageScaleProportionallyUpOrDown; [parent addSubview:image];
}
static CGFloat rowHeight(NSDictionary *row) {
    return ![row[@"action"] boolValue] && ([row[@"detail"] length] || [[row[@"text"] componentsSeparatedByString:@" · "] count]>2 || [row[@"text"] length]>44) ? 52 : 36;
}
static CGFloat rowsHeight(NSArray *rows) {
    CGFloat height=0; for (NSUInteger i=1;i<rows.count;i++) height+=rowHeight(rows[i]); return height;
}
static CGFloat bodyHeight(NSDictionary *document) {
    NSUInteger count=[document[@"rows"] count]-1;
    CGFloat height=statPanel(document) ? ceil(count/2.0)*64 : rowsHeight(document[@"rows"]);
    NSArray *rows=document[@"rows"];
    if ([document[@"name"] isEqual:@"weather"] && rows.count>2 && [rows[2][@"text"] isEqual:document[@"subtitle"]]) height-=rowHeight(rows[2]);
    // Stable discovery target while preserving scrolling for long device lists.
    return [document[@"name"] isEqual:@"brightness"] ? MAX(336,height) : height;
}
static CGFloat headerHeight(NSDictionary *document) {
    if ([document[@"name"] isEqual:@"weather"]) return 110+([document[@"forecast"] count] ? 108 : 0)+([document[@"daily"] count] ? 124 : 0);
    return 74+(document[@"slider"] ? 48 : 0)+([document[@"history"] count] ? 88 : 0)
        +(document[@"meter"] ? 14 : 0)+([document[@"forecast"] count] ? 100 : 0);
}
static void runControl(NSString *kind, NSString *argument, NSString *name, NSString *revision) {
    if (controlBusy || !controlDocument) return;
    NSString *python=installedPython();
    if (!python) return;
    NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:python];
    NSString *script=[NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar/plugins/controls.py"];
    task.arguments=@[@"-B",script,kind,name,argument,revision];
    NSMutableDictionary *environment=NSProcessInfo.processInfo.environment.mutableCopy;
    environment[@"PATH"]=@"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"; task.environment=environment;
    task.standardInput=NSFileHandle.fileHandleWithNullDevice; task.standardOutput=NSFileHandle.fileHandleWithNullDevice; task.standardError=NSFileHandle.fileHandleWithNullDevice;
    task.terminationHandler=^(__unused NSTask *finished) { dispatch_async(dispatch_get_main_queue(),^{ controlBusy=NO; }); };
    controlBusy=[task launchAndReturnError:nil];
}
@implementation ControlView
- (void)clicked:(NSButton *)sender { runControl(@"native-action",[@(sender.tag) stringValue],self.callbackName,self.callbackRevision); }
- (void)slid:(NSSlider *)sender { runControl(@"native-slider",[NSString stringWithFormat:@"%.0f",sender.doubleValue],self.callbackName,self.callbackRevision); }
- (void)render {
    self.callbackName=controlDocument[@"name"];self.callbackRevision=controlDocument[@"revision"];
    CGFloat oldScroll=0;
    if ([self.documentName isEqual:controlDocument[@"name"]])
        for (NSView *view in self.subviews) if ([view isKindOfClass:NSScrollView.class]) oldScroll=[(NSScrollView *)view contentView].bounds.origin.y;
    self.documentName=controlDocument[@"name"];
    for (NSView *view in self.subviews.copy) [view removeFromSuperview];
    BOOL isWeather=[controlDocument[@"name"] isEqual:@"weather"];
    CGFloat width=self.bounds.size.width, contentWidth=width-(isWeather ? 48 : 40), documentWidth=width-24;
    NSArray *rows=controlDocument[@"rows"];
    NSString *title=rows.firstObject[@"text"];
    NSArray *hero=[title componentsSeparatedByString:@" · "];
    if (isWeather) {
        symbol(self,panelSymbol(@"weather"),NSMakeRect(24,20,16,16),DFPanelColor(0xb8a6ff));
        text(self,[hero.firstObject uppercaseString],NSMakeRect(48,21,230,16),10,DFPanelColor(0x94a3b8),NSFontWeightSemibold);
        text(self,hero.count>1 ? [[hero subarrayWithRange:NSMakeRange(1,hero.count-1)] componentsJoinedByString:@" · "] : title,
             NSMakeRect(22,42,336,40),30,DFPanelColor(0xe6edf7),NSFontWeightSemibold);
    } else {
    symbol(self,panelSymbol(controlDocument[@"name"]),NSMakeRect(20,20,18,18),DFPanelColor(0xb8a6ff));
    text(self,[hero.firstObject uppercaseString],NSMakeRect(46,22,width-222,18),11,DFPanelColor(0x94a3b8),NSFontWeightSemibold);
    NSString *primaryTitle=hero.count>1 ? [[hero subarrayWithRange:NSMakeRange(1,hero.count-1)] componentsJoinedByString:@" · "] : @"";
    if ([@[@"bluetooth",@"wifi"] containsObject:controlDocument[@"name"]] && [rows.firstObject[@"action"] boolValue]) {
        HeaderPower *power=[[HeaderPower alloc] initWithFrame:NSMakeRect(width-174,14,154,34)];
        power.showsHover=NO;
        power.title=primaryTitle;power.tag=0;power.target=self;power.action=@selector(clicked:);
        power.toolTip=[primaryTitle isEqual:@"On"] ? @"Turn off" : @"Turn on";
        power.accessibilityLabel=[NSString stringWithFormat:@"%@: %@",hero.firstObject,power.toolTip];
        [self addSubview:power];
    } else {
    NSTextField *primary=text(self,primaryTitle,
         NSMakeRect(width-174,14,154,34),statPanel(controlDocument) || [controlDocument[@"name"] isEqual:@"weather"] ? 24 : 20,DFPanelColor(0xe6edf7),NSFontWeightSemibold);
    primary.alignment=NSTextAlignmentRight;
    }
    }
    NSString *subtitle=controlDocument[@"subtitle"];
    if (!subtitle.length) subtitle=@{@"volume":@"Output level & devices", @"brightness":@"Built-in display",
        @"wifi":@"Wireless connection", @"bluetooth":@"Paired devices", @"battery":@"Power & battery health",
        @"alerts":@"Notifications & system health", @"weather":@"Local forecast"}[controlDocument[@"name"]] ?: @"";
    BOOL pinned=[controlDocument[@"pinned"] boolValue];
    text(self,subtitle,NSMakeRect(isWeather ? 24 : 20,isWeather ? 84 : 49,contentWidth-(pinned ? 24 : 0),17),isWeather ? 11 : 10.5,DFPanelColor(0x94a3b8),NSFontWeightRegular);
    if (pinned) symbol(self,@"pin.fill",NSMakeRect(width-34,isWeather ? 84 : 49,12,12),DFPanelColor(0xb8a6ff));
    CGFloat y=isWeather ? 110 : 74;
    if (controlDocument[@"meter"]) {
        ControlMeter *meter=[[ControlMeter alloc] initWithFrame:NSMakeRect(20,y,contentWidth,4)];
        meter.value=[controlDocument[@"meter"] doubleValue]; [self addSubview:meter]; y+=14;
    }
    if (controlDocument[@"slider"]) {
        NSSlider *slider=[[NSSlider alloc] initWithFrame:NSMakeRect(18,y,contentWidth+4,24)];
        slider.cell=ControlSliderCell.new;slider.minValue=0;slider.maxValue=100;
        slider.doubleValue=[controlDocument[@"slider"] doubleValue];slider.target=self;slider.action=@selector(slid:);
        slider.continuous=NO; slider.controlSize=NSControlSizeRegular;
        slider.trackFillColor=DFPanelColor(0xb8a6ff);
        slider.accessibilityLabel=[controlDocument[@"name"] isEqual:@"volume"] ? @"Output volume" : @"Display brightness";
        [self addSubview:slider];
        text(self,@"0%",NSMakeRect(20,y+27,40,14),9,DFPanelColor(0x94a3b8),NSFontWeightMedium);
        text(self,@"100%",NSMakeRect(width-54,y+27,34,14),9,DFPanelColor(0x94a3b8),NSFontWeightMedium); y+=48;
    }
    if ([controlDocument[@"history"] count]) {
        ControlGraph *graph=[[ControlGraph alloc] initWithFrame:NSMakeRect(20,y,contentWidth,74)]; graph.samples=controlDocument[@"history"]; [self addSubview:graph]; y+=88;
    }
    NSArray *forecast=controlDocument[@"forecast"];
    if (forecast.count) {
        CGFloat width=(contentWidth-5*4)/6.0;
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
    NSArray *daily=controlDocument[@"daily"];
    if (daily.count) {
        text(self,@"NEXT 6 DAYS · HIGH / LOW",NSMakeRect(24,y,332,14),9,DFPanelColor(0x94a3b8),NSFontWeightSemibold);
        CGFloat tileWidth=(332-5*4)/6.0;
        for (NSUInteger i=0;i<daily.count;i++) {
            NSDictionary *day=daily[i];
            ControlTile *tile=[[ControlTile alloc] initWithFrame:NSMakeRect(24+i*(tileWidth+4),y+22,tileWidth,94)];
            text(tile,day[@"day"],NSMakeRect(7,8,tileWidth-10,14),10,DFPanelColor(0x94a3b8),NSFontWeightMedium);
            symbol(tile,weatherSymbol(day[@"condition"]),NSMakeRect((tileWidth-20)/2,27,20,20),DFPanelColor(0x42c7ff));
            text(tile,day[@"high"],NSMakeRect(6,52,tileWidth-8,18),12,DFPanelColor(0xe6edf7),NSFontWeightSemibold);
            text(tile,day[@"low"],NSMakeRect(8,75,tileWidth-10,12),9,DFPanelColor(0x94a3b8),NSFontWeightMedium);
            [self addSubview:tile];
        }
        y+=124;
    }
    CGFloat contentHeight=MAX(1,bodyHeight(controlDocument));
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(12,y,documentWidth,MIN(contentHeight,MAX(24,self.bounds.size.height-y-16)))];
    scroll.drawsBackground=NO; scroll.hasVerticalScroller=YES; scroll.autohidesScrollers=YES; scroll.scrollerStyle=NSScrollerStyleOverlay; scroll.borderType=NSNoBorder;
    // The document is flipped, but has no second surface behind the rows.
    NSView *document=[[ControlDocument alloc] initWithFrame:NSMakeRect(0,0,documentWidth,contentHeight)];
    CGFloat rowY=0;
    for (NSUInteger i=1;i<rows.count;i++) {
        if ([controlDocument[@"name"] isEqual:@"weather"] && i==2 && [rows[i][@"text"] isEqual:controlDocument[@"subtitle"]]) continue;
        NSDictionary *row=rows[i]; CGFloat height=rowHeight(row); NSRect rect=NSMakeRect(0,rowY,documentWidth,height-2); rowY+=height;
        if ([row[@"action"] boolValue]) {
            ControlRow *button=[[ControlRow alloc] initWithFrame:rect]; button.title=row[@"text"]; button.bordered=NO; button.tag=i;
            button.toolTip=button.title;
            button.detail=row[@"detail"]; button.hint=row[@"hint"]; button.selected=[row[@"selected"] boolValue];
            button.accessibilityLabel=[@[button.title,button.detail ?: @"",button.hint ?: @""] componentsJoinedByString:@", "];
            button.target=self; button.action=@selector(clicked:); [document addSubview:button];
        } else if ([row[@"section"] boolValue]) {
            text(document,[row[@"text"] uppercaseString],NSMakeRect(24,rect.origin.y+10,documentWidth-36,16),9,DFPanelColor(0x94a3b8),NSFontWeightSemibold);
        } else if ([row[@"detail"] length]) {
            text(document,row[@"text"],NSMakeRect(24,rect.origin.y+6,documentWidth-36,18),12,DFPanelColor(0xe6edf7),NSFontWeightMedium);
            text(document,row[@"detail"],NSMakeRect(24,rect.origin.y+27,documentWidth-36,16),10,DFPanelColor(0x94a3b8),NSFontWeightRegular);
        } else if (statPanel(controlDocument)) {
            NSUInteger index=i-1;
            NSArray *parts=[row[@"text"] componentsSeparatedByString:@" · "];
            CGFloat tileWidth=(documentWidth-28)/2;
            ControlTile *tile=[[ControlTile alloc] initWithFrame:NSMakeRect(10+(index%2)*(tileWidth+8),(index/2)*64,tileWidth,56)];
            text(tile,parts.count>1 ? parts.firstObject : @"STATUS",NSMakeRect(10,7,tileWidth-20,14),10,DFPanelColor(0x94a3b8),NSFontWeightMedium);
            NSString *value=parts.count>1 ? [[parts subarrayWithRange:NSMakeRange(1,parts.count-1)] componentsJoinedByString:@" · "] : parts.firstObject;
            text(tile,value,NSMakeRect(10,26,tileWidth-20,24),15,DFPanelColor(0xe6edf7),NSFontWeightSemibold);
            [document addSubview:tile];
        } else {
            NSArray *parts=[row[@"text"] componentsSeparatedByString:@" · "];
            CGFloat labelWidth=floor((documentWidth-24)*0.4);
            text(document,parts.firstObject,NSMakeRect(10,rect.origin.y+9,parts.count>1 ? labelWidth : documentWidth-20,18),12,DFPanelColor(0x94a3b8),NSFontWeightRegular);
            if (parts.count>1) {
                NSTextField *value=[NSTextField labelWithString:[[parts subarrayWithRange:NSMakeRange(1,parts.count-1)] componentsJoinedByString:@" · "]];
                value.frame=NSMakeRect(labelWidth+12,rect.origin.y+9,documentWidth-labelWidth-24,height-12); value.alignment=NSTextAlignmentRight;
                value.font=[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium]; value.textColor=DFPanelColor(0xe6edf7);
                value.lineBreakMode=NSLineBreakByWordWrapping; value.maximumNumberOfLines=2; [document addSubview:value];
            }
        }
    }
    scroll.documentView=document; [self addSubview:scroll];
    [scroll.contentView scrollToPoint:NSMakePoint(0,MIN(oldScroll,MAX(0,contentHeight-scroll.frame.size.height)))]; [scroll reflectScrolledClipView:scroll.contentView];
    self.needsDisplay=YES;
}
@end

@interface ControlPanel : NSPanel
@end
@implementation ControlPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode==53) DFControlsHide(); else [super keyDown:event];
}
@end

static NSDictionary *renderIdentity(NSDictionary *document) {
    NSMutableDictionary *identity=document.mutableCopy;
    for (NSString *key in @[@"revision",@"request",@"anchors"]) [identity removeObjectForKey:key];
    return identity;
}
static void showControls(void) {
    NSDictionary *document=readDocument(); if (!document) return;
    if ([document[@"request"] isEqual:dismissedRequest]) return;
    if (controlWillShow) controlWillShow();
    if (![document[@"request"] isEqual:controlDocument[@"request"]]) controlPanel.ignoresMouseEvents=NO;
    controlDismissal=@"";
    BOOL same=[controlDocument[@"name"] isEqual:document[@"name"]] && controlPanel.visible;
    BOOL redraw=!same || ![renderIdentity(controlDocument) isEqual:renderIdentity(document)];
    controlDocument=document; DFCalendarHide(); DFMenusHide();
    CGFloat width=panelWidth(document);
    if (!controlPanel) {
        controlPanel=[[ControlPanel alloc] initWithContentRect:NSMakeRect(0,0,width,200) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        controlPanel.level=CGWindowLevelForKey(kCGStatusWindowLevelKey)+2;
        controlPanel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorStationary;
        controlPanel.opaque=NO; controlPanel.backgroundColor=NSColor.clearColor; controlPanel.hasShadow=YES; controlPanel.hidesOnDeactivate=NO;
        controlView=[[ControlView alloc] initWithFrame:NSMakeRect(0,0,width,200)]; controlPanel.contentView=controlView;
    }
    controlPanel.level=displayCoverToken ? CGWindowLevelForKey(kCGPopUpMenuWindowLevelKey)+2 : CGWindowLevelForKey(kCGStatusWindowLevelKey)+2;
    NSPoint pointer=NSEvent.mouseLocation; NSScreen *screen=same ? controlPanel.screen : NSScreen.mainScreen;
    if (!screen) screen=NSScreen.mainScreen;
    if (!same) for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(pointer,candidate.frame)) screen=candidate;
    NSRect screenFrame=screen.frame;
    NSRect anchor=same ? controlItemAnchor : NSMakeRect(pointer.x-44,NSMaxY(screenFrame)-screen.safeAreaInsets.top-36,88,32);
    if (!same) {
        CGFloat distance=CGFLOAT_MAX, mainTop=NSMaxY(NSScreen.screens.firstObject.frame);
        for (NSDictionary *value in document[@"anchors"]) {
            NSRect candidate=NSMakeRect([value[@"x"] doubleValue],mainTop-[value[@"y"] doubleValue]-[value[@"height"] doubleValue],
                                       [value[@"width"] doubleValue],[value[@"height"] doubleValue]);
            if (!NSPointInRect(NSMakePoint(NSMidX(candidate),NSMidY(candidate)),screenFrame)) continue;
            CGFloat delta=fabs(NSMidX(candidate)-pointer.x);
            if (delta<distance) { anchor=candidate; distance=delta; }
        }
    }
    controlItemAnchor=anchor;
    CGFloat height=headerHeight(document)+MIN(bodyHeight(document),336)+16;
    NSRect frame=panelFrame(screenFrame,anchor,width,height);
    controlAnchor=NSMakeRect(NSMinX(anchor)-6,NSMaxY(frame),anchor.size.width+12,MAX(1,NSMaxY(anchor)-NSMaxY(frame)));
    if (!NSEqualRects(frame,controlPanel.frame)) { [controlPanel setFrame:frame display:NO]; redraw=YES; }
    controlView.frame=NSMakeRect(0,0,frame.size.width,frame.size.height);
    controlView.anchorX=NSMidX(anchor)-frame.origin.x;
    BOOL tracking=same && (NSEvent.pressedMouseButtons&1) && NSPointInRect(pointer,frame);
    if (redraw && !tracking) [controlView render];
    renderPending=redraw && tracking;
    controlAway=0; controlButtons=NSEvent.pressedMouseButtons;
    if (!same) DFPanelPresent(controlPanel);
    if ([document[@"pinned"] boolValue]) [controlPanel makeKeyWindow];
}
void DFControlsInitialize(NSString *directory) {
    controlDirectory=directory;
    // A replacement UI server must remain above an already-running live cover.
    // The lease is private, live-process-bound and expires without its producer.
    if ([controlNotification isEqual:@"local.dotfiles.desktop.panels"]) {
        displayCoverToken=DFNativeUIActiveToken(directory);
        if (displayCoverToken) displayCoverUntil=NSProcessInfo.processInfo.systemUptime+12;
    }
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:controlNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        NSString *cover=note.userInfo[@"cover"];
        if ([note.object isEqual:@"display-cover-begin"] || [note.object isEqual:@"display-cover-end"]) {
            if (![cover isKindOfClass:NSString.class] || cover.length>64) return;
            if ([note.object isEqual:@"display-cover-begin"]) {
                if (![note.userInfo[@"request"] isEqual:controlDocument[@"request"]]) return;
                displayCoverToken=cover;displayCoverUntil=NSProcessInfo.processInfo.systemUptime+12;
            } else if ([cover isEqual:displayCoverToken]) {displayCoverToken=nil;displayCoverUntil=0;}
            controlPanel.level=displayCoverToken ? CGWindowLevelForKey(kCGPopUpMenuWindowLevelKey)+2 : CGWindowLevelForKey(kCGStatusWindowLevelKey)+2;
            return;
        }
        NSString *request=note.userInfo[@"request"];
        if (request && ![request isEqual:controlDocument[@"request"]]) return;
        if ([note.object isEqual:@"show"]) showControls(); else if ([note.object isEqual:@"hide"]) {controlDismissal=@"request";DFControlsHide();}
        else if ([note.object isEqual:@"passthrough"] && [@[@"wifi",@"brightness"] containsObject:controlDocument[@"name"]]) {controlPanel.ignoresMouseEvents=YES;passthroughUntil=NSProcessInfo.processInfo.systemUptime+8;}
        else if ([note.object isEqual:@"resume"]) {controlPanel.ignoresMouseEvents=NO;passthroughUntil=0;}
    }];
}
void DFControlsNotify(NSString *action) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:controlNotification object:action userInfo:nil deliverImmediately:YES];
}
void DFControlsNotifyRequest(NSString *action, NSString *request) {
    if (!request.length) return;
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:controlNotification object:action userInfo:@{@"request":request} deliverImmediately:YES];
}
static void acknowledgeDismissal(NSString *request) {
    if (!request.length) return;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"request":request} options:0 error:nil];
    NSString *directory=[controlDirectory stringByAppendingPathComponent:@"bar"];
    NSString *temporary=[directory stringByAppendingPathComponent:[@".dismiss-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    int fd=open(temporary.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if (fd<0) return;
    BOOL written=write(fd,data.bytes,data.length)==(ssize_t)data.length;
    close(fd);
    if (written) rename(temporary.fileSystemRepresentation,[directory stringByAppendingPathComponent:@"native-dismissed.json"].fileSystemRepresentation);
    unlink(temporary.fileSystemRepresentation);
}
void DFControlsHide(void) {
    // AppKit can hide a panel before the Space-change callback arrives.
    // Acknowledge the pinned request even when it has already become invisible.
    if (controlDocument) {
        dismissedRequest=controlDocument[@"request"];
        if ([controlDocument[@"pinned"] boolValue]) acknowledgeDismissal(dismissedRequest);
    }
    [controlPanel orderOut:nil]; controlPanel.ignoresMouseEvents=NO; controlAway=0; renderPending=NO;
}
void DFControlsSpaceChanged(void) {controlDismissal=@"space_changed";DFControlsHide();}
BOOL DFControlsContainsPointer(NSPoint pointer) {
    return controlPanel.visible && ([controlDocument[@"pinned"] boolValue] || NSPointInRect(pointer,NSInsetRect(controlPanel.frame,-4,-4)) || NSPointInRect(pointer,controlAnchor));
}
void DFControlsTick(double now, NSPoint pointer) {
    if (displayCoverToken && NSProcessInfo.processInfo.systemUptime>displayCoverUntil) {
        displayCoverToken=nil;displayCoverUntil=0;controlPanel.level=CGWindowLevelForKey(kCGStatusWindowLevelKey)+2;
    }
    if (controlPanel.ignoresMouseEvents && NSProcessInfo.processInfo.systemUptime>passthroughUntil) controlPanel.ignoresMouseEvents=NO;
    if (colorsChanged) { colorsChanged=NO; DFCalendarAppearance(); if (controlPanel.visible) [controlView render]; DFMenusHide(); }
    if (!controlPanel.visible) return;
    NSUInteger buttons=NSEvent.pressedMouseButtons;
    if (renderPending && !(buttons&1)) { renderPending=NO; [controlView render]; }
    if ([controlDocument[@"pinned"] boolValue]) {
        if (outsidePress(controlButtons,buttons,pointer,controlPanel.frame,controlAnchor)) {controlDismissal=@"outside_click";DFControlsHide();}
        controlButtons=buttons; return;
    }
    if (DFControlsContainsPointer(pointer)) controlAway=0;
    else if (!controlAway) controlAway=now;
    else if (now-controlAway>0.32) {controlDismissal=@"pointer_exit";DFControlsHide();}
}
NSDictionary *DFControlsStatus(void) {
    NSRect frame=controlPanel.frame;
    return @{@"visible":@(controlPanel.visible),@"dismissal":controlDismissal ?: @"",@"display_cover":@((BOOL)(displayCoverToken!=nil)),@"level":@(controlPanel.level),@"input_passthrough":@(controlPanel.ignoresMouseEvents),@"name":controlDocument[@"name"] ?: @"",@"request":controlDocument[@"request"] ?: @"",@"backend_available":@(installedPython()!=nil),
             @"pinned":@([controlDocument[@"pinned"] boolValue]),@"frame":@[@(frame.origin.x),@(frame.origin.y),@(frame.size.width),@(frame.size.height)]};
}
int DFControlsSelfTest(void) {
    // A panel hidden by AppKit still needs to release its backend pin.
    NSString *savedDirectory=controlDirectory; NSDictionary *savedDocument=controlDocument;
    NSString *savedDismissed=dismissedRequest;
    char *temporary=strdup([[NSTemporaryDirectory() stringByAppendingPathComponent:@"dotfiles-controls-test-XXXXXX"] fileSystemRepresentation]);
    if (!mkdtemp(temporary)) { free(temporary); return 1; }
    controlDirectory=[NSString stringWithUTF8String:temporary]; free(temporary);
    NSString *barDirectory=[controlDirectory stringByAppendingPathComponent:@"bar"];
    [NSFileManager.defaultManager createDirectoryAtPath:barDirectory withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil];
    controlDocument=@{@"request":@"hidden-pin",@"pinned":@YES}; DFControlsHide();
    NSData *ack=[NSData dataWithContentsOfFile:[barDirectory stringByAppendingPathComponent:@"native-dismissed.json"]];
    NSDictionary *dismissal=ack ? [NSJSONSerialization JSONObjectWithData:ack options:0 error:nil] : nil;
    BOOL released=[dismissal[@"request"] isEqual:@"hidden-pin"];
    controlDocument=@{@"request":@"hover",@"pinned":@NO}; DFControlsHide();
    BOOL kept=[ack isEqual:[NSData dataWithContentsOfFile:[barDirectory stringByAppendingPathComponent:@"native-dismissed.json"]]];
    [NSFileManager.defaultManager removeItemAtPath:controlDirectory error:nil];
    controlDirectory=savedDirectory; controlDocument=savedDocument; dismissedRequest=savedDismissed;
    if (!released || !kept) return 1;
    for (int offset=-1440;offset<=1440;offset+=1440) for (int edge=0;edge<3;edge++) {
        NSRect screen=NSMakeRect(offset,offset,1440,900), anchor=NSMakeRect(offset+edge*700,offset+860,60,30);
        NSRect frame=panelFrame(screen,anchor,344,320);
        if (NSMinX(frame)<NSMinX(screen)+12 || NSMaxX(frame)>NSMaxX(screen)-12 || NSMinY(frame)<NSMinY(screen)+12 || fabs(NSMaxY(frame)-(NSMinY(anchor)-8))>0.001) return 1;
    }
    NSRect panel=NSMakeRect(100,100,320,250), bridge=NSMakeRect(380,350,40,40);
    if (!outsidePress(0,1,NSMakePoint(0,0),panel,bridge) || outsidePress(1,1,NSMakePoint(0,0),panel,bridge)
        || outsidePress(0,1,NSMakePoint(120,120),panel,bridge) || outsidePress(0,1,NSMakePoint(400,370),panel,bridge)) return 1;
    if (panelWidth(@{@"name":@"weather"})!=380 || panelWidth(@{@"name":@"cpu"})!=344 || panelWidth(@{@"name":@"volume"})!=320) return 1;
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
    NSDictionary *day=@{@"day":@"Sat",@"date":@"2026-10-17",@"high":@"62°F",@"low":@"41°F",@"condition":@"clear"};
    weather=@{@"name":@"weather",@"revision":@"1",@"request":@"1",@"rows":valid[@"rows"],@"daily":@[day]}.mutableCopy;
    if (!validDocument(weather)) return 1;
    weather[@"daily"]=@[day,day,day,day,day,day,day]; if (validDocument(weather)) return 1;
    bad=valid.mutableCopy; bad[@"pinned"]=@0.5; if (validDocument(bad)) return 1;
    bad=valid.mutableCopy; bad[@"anchors"]=@[@{@"x":@1,@"y":@(NAN),@"width":@50,@"height":@40}]; if (validDocument(bad)) return 1;
    bad[@"anchors"]=@[@{@"x":@1,@"y":@4,@"width":@(-1),@"height":@40}]; if (validDocument(bad)) return 1;
    puts("Native controls: payload bounds, forecast rows, anchored placement, compact widths, hidden-pin acknowledgement and outside-click guards passed."); return 0;
}
BOOL DFControlsPreview(NSString *path, NSString *kind) {
    // A deterministic UI fixture, never personal device or account data.
    NSDictionary *fixtures=@{
        @"cpu":@[@"CPU · 24%",@"Temperature · 113°F",@"Power · 8.4 W",@"System power · 21.8 W",@"Fan 1 · 0 RPM"],
        @"gpu":@[@"GPU · 38%",@"Temperature · 109°F",@"Power · 12.6 W",@"System power · 29.4 W",@"Fan 1 · 0 RPM"],
        @"memory":@[@"Memory · 18.2 GiB",@"Used · 18.20 GiB",@"Total · 64.00 GiB",@"Swap used · 0.00 GiB",@"Swap capacity · 0.00 GiB"],
        @"battery":@[@"Battery · 84%",@"State · Charging",@"Estimate · 1:22 remaining",@"Cycles · 142",@"Temperature · 88°F"],
        @"weather":@[@"Weather · 54°F",@"Mitchell, OR · 97750",@"Partly cloudy",@"Wind · W 5 to 10 mph",@"Precipitation · 10%",@"NWS · updated 4 min ago",@"Refresh forecast"],
        @"volume":@[@"Sound · 42%",@"Mute",@"Output devices",@"MacBook Pro Speakers",@"Studio Display"],
        @"brightness":@[@"Display · 68%",@"Built-in display brightness"],
        @"wifi":@[@"Wi-Fi · Connected",@"Current network · Shown in Wi-Fi controls",@"Address · 192.0.2.24",@"Available networks & connection…",@"Turn Wi-Fi off"],
        @"bluetooth":@[@"Bluetooth · On",@"Turn Bluetooth off",@"Disconnect Headphones",@"Connect Keyboard"],
        @"alerts":@[@"Notifications · Quick controls",@"Notification Center",@"Focus / Control Center",@"System health",@"All clear"]};
    NSArray *labels=fixtures[kind]; if (!labels) return NO;
    NSMutableArray *rows=NSMutableArray.new;
    for (NSUInteger i=0;i<labels.count;i++) {
        BOOL action=i>0 && (([kind isEqual:@"volume"] || [kind isEqual:@"bluetooth"])
            || ([kind isEqual:@"wifi"] && i>=3) || ([kind isEqual:@"alerts"] && i<3)
            || ([kind isEqual:@"weather"] && i==labels.count-1));
        NSMutableDictionary *row=@{@"text":labels[i],@"action":@(action)}.mutableCopy;
        if ([kind isEqual:@"volume"]) {
            if (i==2) { row[@"action"]=@NO; row[@"section"]=@YES; }
            if (i>=3) { row[@"selected"]=@(i==3); row[@"detail"]=i==3 ? @"Current output" : @""; row[@"hint"]=@"Use output"; }
        } else if ([kind isEqual:@"bluetooth"] && i>=2) {
            row[@"text"]=i==2 ? @"Headphones" : @"Keyboard"; row[@"selected"]=@(i==2);
            row[@"detail"]=i==2 ? @"Connected" : @"Not connected"; row[@"hint"]=i==2 ? @"Disconnect" : @"Connect";
        }
        [rows addObject:row];
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
        NSMutableArray *days=NSMutableArray.new;
        for (NSUInteger i=0;i<6;i++) [days addObject:@{@"day":@[@"Sat",@"Sun",@"Mon",@"Tue",@"Wed",@"Thu"][i],
            @"date":[NSString stringWithFormat:@"2026-10-%lu",(unsigned long)i+17],
            @"high":@[@"62°F",@"59°F",@"55°F",@"58°F",@"61°F",@"63°F"][i],
            @"low":@[@"41°F",@"39°F",@"38°F",@"40°F",@"42°F",@"43°F"][i],
            @"condition":@[@"clear",@"cloudy",@"rain",@"cloudy",@"clear",@"clear"][i]}];
        fixture[@"daily"]=days;
    }
    if (!validDocument(fixture)) return NO;
    controlDocument=fixture;
    CGFloat height=headerHeight(fixture)+MIN(bodyHeight(fixture),360)+16;
    controlView=[[ControlView alloc] initWithFrame:NSMakeRect(0,0,panelWidth(fixture),height)]; [controlView render];
    NSBitmapImageRep *bitmap=[controlView bitmapImageRepForCachingDisplayInRect:controlView.bounds];
    [controlView cacheDisplayInRect:controlView.bounds toBitmapImageRep:bitmap];
    return [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}
