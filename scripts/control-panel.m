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
    [text drawInRect:NSMakeRect(10,9,self.bounds.size.width-38,18) withAttributes:attributes];
    [@"›" drawAtPoint:NSMakePoint(self.bounds.size.width-21,7) withAttributes:style];
}
@end

@interface ControlGraph : NSView
@property NSArray<NSNumber *> *samples;
@end
@implementation ControlGraph
- (void)drawRect:(__unused NSRect)dirty {
    NSRect area=NSInsetRect(self.bounds,2,6);
    [DFPanelColor(0x2a3447) setStroke];
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
static CGFloat rowHeight(NSDictionary *row) {
    return ![row[@"action"] boolValue] && ([[row[@"text"] componentsSeparatedByString:@" · "] count]>2 || [row[@"text"] length]>44) ? 52 : 36;
}
static CGFloat rowsHeight(NSArray *rows) {
    CGFloat height=0; for (NSUInteger i=1;i<rows.count;i++) height+=rowHeight(rows[i]); return height;
}
static void runControl(NSString *kind, NSString *argument) {
    if (controlBusy || !controlDocument) return;
    NSString *python=@"/opt/homebrew/bin/python3";
    if (![NSFileManager.defaultManager isExecutableFileAtPath:python]) return;
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
    text(self,[hero.firstObject uppercaseString],NSMakeRect(22,18,306,16),10,DFPanelColor(0x94a3b8),NSFontWeightSemibold);
    text(self,hero.count>1 ? [[hero subarrayWithRange:NSMakeRange(1,hero.count-1)] componentsJoinedByString:@" · "] : title,
         NSMakeRect(22,38,306,34),24,DFPanelColor(0xe6edf7),NSFontWeightSemibold);
    CGFloat y=82;
    if (controlDocument[@"slider"]) {
        NSSlider *slider=[NSSlider sliderWithValue:[controlDocument[@"slider"] doubleValue] minValue:0 maxValue:100 target:self action:@selector(slid:)];
        slider.frame=NSMakeRect(22,y,306,26); slider.continuous=NO; slider.controlSize=NSControlSizeRegular;
        [self addSubview:slider]; y+=42;
    }
    if ([controlDocument[@"history"] count]) {
        ControlGraph *graph=[[ControlGraph alloc] initWithFrame:NSMakeRect(22,y,306,60)]; graph.samples=controlDocument[@"history"]; [self addSubview:graph]; y+=72;
    }
    CGFloat contentHeight=MAX(1,rowsHeight(rows));
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(12,y,326,MIN(contentHeight,360))];
    scroll.drawsBackground=NO; scroll.hasVerticalScroller=YES; scroll.autohidesScrollers=YES; scroll.scrollerStyle=NSScrollerStyleOverlay; scroll.borderType=NSNoBorder;
    // The document is flipped, but has no second surface behind the rows.
    NSView *document=[[ControlDocument alloc] initWithFrame:NSMakeRect(0,0,326,contentHeight)];
    CGFloat rowY=0;
    for (NSUInteger i=1;i<rows.count;i++) {
        NSDictionary *row=rows[i]; CGFloat height=rowHeight(row); NSRect rect=NSMakeRect(0,rowY,326,height-2); rowY+=height;
        if ([row[@"action"] boolValue]) {
            ControlRow *button=[[ControlRow alloc] initWithFrame:rect]; button.title=row[@"text"]; button.bordered=NO; button.tag=i;
            button.target=self; button.action=@selector(clicked:); [document addSubview:button];
        } else {
            NSArray *parts=[row[@"text"] componentsSeparatedByString:@" · "];
            text(document,parts.firstObject,NSMakeRect(10,rect.origin.y+9,parts.count>1 ? 142 : 304,18),12,DFPanelColor(0x94a3b8),NSFontWeightRegular);
            if (parts.count>1) {
                NSTextField *value=[NSTextField labelWithString:[[parts subarrayWithRange:NSMakeRange(1,parts.count-1)] componentsJoinedByString:@" · "]];
                value.frame=NSMakeRect(136,rect.origin.y+9,178,height-12); value.alignment=NSTextAlignmentRight;
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
        controlPanel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,350,200) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        controlPanel.level=CGWindowLevelForKey(kCGStatusWindowLevelKey)+2;
        controlPanel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorStationary;
        controlPanel.opaque=NO; controlPanel.backgroundColor=NSColor.clearColor; controlPanel.hasShadow=YES; controlPanel.hidesOnDeactivate=NO;
        controlView=[[ControlView alloc] initWithFrame:NSMakeRect(0,0,350,200)]; controlPanel.contentView=controlView;
    }
    CGFloat height=82+(document[@"slider"] ? 42 : 0)+([document[@"history"] count] ? 72 : 0)+MIN(rowsHeight(document[@"rows"]),360)+16;
    NSPoint pointer=NSEvent.mouseLocation; NSScreen *screen=NSScreen.mainScreen;
    for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(pointer,candidate.frame)) screen=candidate;
    NSRect frame=screen.frame; CGFloat top=NSMaxY(frame)-screen.safeAreaInsets.top-44;
    CGFloat x=same ? controlPanel.frame.origin.x : MAX(NSMinX(frame)+12,MIN(pointer.x-175,NSMaxX(frame)-362));
    if (!same) controlAnchor=NSMakeRect(pointer.x-44,top,88,NSMaxY(frame)-top);
    [controlPanel setFrame:NSMakeRect(x,MAX(NSMinY(frame)+12,top-height),350,height) display:NO];
    controlView.frame=NSMakeRect(0,0,350,height); [controlView render]; controlAway=0; [controlPanel orderFrontRegardless];
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
NSDictionary *DFControlsStatus(void) { return @{@"visible":@(controlPanel.visible),@"name":controlDocument[@"name"] ?: @""}; }
int DFControlsSelfTest(void) {
    NSDictionary *valid=@{@"name":@"volume",@"revision":@"1",@"request":@"1",@"rows":@[@{@"text":@"Sound",@"action":@NO}],@"slider":@50};
    if (!validDocument(valid)) return 1;
    for (NSString *key in @[@"name",@"rows",@"slider",@"history"]) {
        NSMutableDictionary *bad=valid.mutableCopy; bad[key]=@"invalid"; if (validDocument(bad)) return 1;
    }
    NSMutableDictionary *bad=valid.mutableCopy; bad[@"slider"]=@101; if (validDocument(bad)) return 1;
    puts("Native control payload: types, panel allowlist, slider bounds and malformed history passed."); return 0;
}
BOOL DFControlsPreview(NSString *path) {
    // A deterministic UI fixture, never personal device or account data.
    controlDocument=@{@"name":@"cpu",@"revision":@"preview",@"rows":@[@{@"text":@"CPU · 24%",@"action":@NO},@{@"text":@"Temperature · 113°F",@"action":@NO},@{@"text":@"Power · 8.4 W",@"action":@NO},@{@"text":@"Fan 1 · 0 RPM",@"action":@NO}],@"history":@[@0.12,@0.18,@0.15,@0.32,@0.25,@0.38,@0.22,@0.24]};
    controlView=[[ControlView alloc] initWithFrame:NSMakeRect(0,0,350,278)]; [controlView render];
    NSBitmapImageRep *bitmap=[controlView bitmapImageRepForCachingDisplayInRect:controlView.bounds];
    [controlView cacheDisplayInRect:controlView.bounds toBitmapImageRep:bitmap];
    return [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}
