#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <signal.h>
#include <sys/file.h>
#include <fcntl.h>
#include <sys/stat.h>

// Local, reversible SkyLight calls used by yabai's menubar_opacity:
// https://github.com/asmvik/yabai/blob/master/src/misc/extern.h
// No injection, root access, event tap, cursor warping, or SIP changes.
static int (*mainConnection)(void);
static CGError (*setAlpha)(int, double, double, float);
static void (*setOverride)(int, int, bool);
static NSString *barPath;
static BOOL visible = NO, healthy = NO;
static double awaySince = 0, nextHealth = 0;
static volatile sig_atomic_t stopping = 0;
static dispatch_queue_t barQueue;
static BOOL healthPending = NO, dockPresented = NO, dockMenuOpen = NO;
static NSUInteger barRevision = 0, dockRevision = 0;
static BOOL missionControl = NO;
static double missionControlSince = 0, nextMissionCheck = 0;
static BOOL setVisible(BOOL show);
static NSColor *panelColor, *borderColor, *inkColor, *accentColor, *secondaryColor, *hoverColor;
static NSString *appearancePath, *themeName;
static volatile sig_atomic_t appearanceChanged = 0;
static void appearanceSignal(__unused int sig) { appearanceChanged=1; }

static NSColor *hexColor(NSString *hex) {
    unsigned long long value=0;
    if (![hex isKindOfClass:NSString.class] || hex.length!=6 || ![[NSScanner scannerWithString:hex] scanHexLongLong:&value]) return nil;
    return [NSColor colorWithCalibratedRed:((value>>16)&255)/255.0
        green:((value>>8)&255)/255.0 blue:(value&255)/255.0 alpha:1];
}
static void loadAppearance(void) {
    NSData *data = appearancePath ? [NSData dataWithContentsOfFile:appearancePath] : nil;
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *palette = [value isKindOfClass:NSDictionary.class] ? value : @{};
    panelColor = hexColor(palette[@"surface"]) ?: hexColor(@"132630");
    borderColor = hexColor(palette[@"border"]) ?: hexColor(@"355361");
    inkColor = hexColor(palette[@"foreground"]) ?: hexColor(@"E8F5F7");
    accentColor = hexColor(palette[@"accent"]) ?: hexColor(@"80D9D1");
    secondaryColor = hexColor(palette[@"secondary"]) ?: hexColor(@"E4B98A");
    hoverColor = hexColor(palette[@"highlight"]) ?: hexColor(@"294956");
    themeName = [palette[@"name"] isKindOfClass:NSString.class] ? palette[@"name"] : @"tidal";
}

// Apple Silicon brightness SPI; symbol signatures follow nriley/brightness.
// This controls only the built-in panel, leaving external-display policy alone.
static int brightnessCommand(const char *setting) {
    void *library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
    int (*get)(CGDirectDisplayID,float *) = library ? dlsym(library,"DisplayServicesGetBrightness") : NULL;
    int (*set)(CGDirectDisplayID,float) = library ? dlsym(library,"DisplayServicesSetBrightness") : NULL;
    CGDirectDisplayID displays[16]; uint32_t count=0;
    if (!get || !set || CGGetOnlineDisplayList(16,displays,&count)!=kCGErrorSuccess) return 1;
    for (uint32_t i=0; i<count; i++) {
        if (!CGDisplayIsBuiltin(displays[i])) continue;
        if (setting) {
            char *end = NULL;
            float value = strtof(setting,&end);
            if (!end || end==setting || *end || !isfinite(value) || value<0 || value>100) return 64;
            if (set(displays[i],value/100)!=0) return 1;
        }
        float value=0;
        if (get(displays[i],&value)!=0 || !isfinite(value)) return 1;
        printf("%.0f\n",value*100); return 0;
    }
    fputs("Built-in brightness unavailable.\n",stderr); return 1;
}

// Fisheye layout expands neighboring slots instead of overlapping icons.
// The same rectangles are used for painting and hit testing.
static NSRect dockRects(CGFloat width, NSUInteger count, CGFloat pointer, CGFloat zoom, NSRect *rects) {
    if (!count) return NSZeroRect;
    CGFloat available = MAX(1, width - 40);
    CGFloat base = MIN(40, available / count * 0.76);
    CGFloat gap = MIN(12, available / count - base);
    CGFloat original = count * base + (count-1) * gap;
    CGFloat start = (width-original)/2;
    CGFloat sizes[count], sum = 0;
    for (NSUInteger i=0; i<count; i++) {
        CGFloat distance = pointer-(start+i*(base+gap)+base/2);
        sizes[i] = base + 22 * zoom * exp(-(distance*distance)/(2*72*72));
        sum += sizes[i];
    }
    CGFloat shrink = MIN(1, MAX(1, available-(count-1)*gap)/sum);
    sum *= shrink;
    CGFloat total = sum+(count-1)*gap, x=(width-total)/2;
    for (NSUInteger i=0; i<count; i++) {
        CGFloat size = sizes[i]*shrink;
        rects[i] = NSMakeRect(x, 20, size, size);
        x += size+gap;
    }
    return NSMakeRect((width-total)/2-16, 6, total+32, 66);
}

static int layoutSelfTest(void) {
    for (NSUInteger count=1; count<=40; count++) for (int width=800; width<=2200; width+=200)
        for (int point=0; point<=width; point+=37) {
            NSRect rects[count];
            NSRect shelf = dockRects(width,count,point,1,rects);
            if (NSMinX(shelf)<0 || NSMaxX(shelf)>width) return 1;
            for (NSUInteger i=0; i<count; i++)
                if (NSMinX(rects[i])<0 || NSMaxX(rects[i])>width ||
                    (i && NSMaxX(rects[i-1])>=NSMinX(rects[i]))) return 1;
        }
    puts("Dock geometry: bounds, non-overlap, and narrow-display cases passed.");
    return 0;
}

@interface DockView : NSView
@property NSArray<NSRunningApplication *> *apps;
@property NSDictionary<NSNumber *, NSNumber *> *counts;
@property CGFloat hover;
@property CGFloat smoothedHover;
@property CGFloat zoom;
@property NSTimeInterval hoveredSince;
@property NSInteger hoveredIndex;
@property NSVisualEffectView *glass;
- (void)step;
@end

@implementation DockView
- (BOOL)isOpaque { return NO; }
- (NSInteger)indexAt:(NSPoint)point {
    NSUInteger count = self.apps.count;
    if (!count) return -1;
    NSRect rects[count];
    dockRects(self.bounds.size.width,count,self.smoothedHover,self.zoom,rects);
    for (NSUInteger i=0; i<count; i++)
        if (NSPointInRect(point,NSInsetRect(rects[i],-6,-10))) return i;
    return -1;
}
- (void)step {
    CGFloat desired = self.hover < 0 ? 0 : 1;
    self.zoom = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion
        ? desired : self.zoom+(desired-self.zoom)*0.22;
    if (self.hover >= 0) {
        if (self.smoothedHover < 0) self.smoothedHover = self.hover;
        else self.smoothedHover += (self.hover-self.smoothedHover)*0.3;
    }
    NSInteger hovered = self.hover < 0 ? -1 : [self indexAt:NSMakePoint(self.hover,40)];
    if (hovered != self.hoveredIndex) {
        self.hoveredIndex = hovered;
        self.hoveredSince = NSProcessInfo.processInfo.systemUptime;
    }
    [self setNeedsDisplay:YES];
}
- (void)drawRect:(__unused NSRect)dirty {
    NSUInteger count = self.apps.count;
    if (!count) return;
    NSRect rects[count];
    NSRect shelf = dockRects(self.bounds.size.width,count,self.smoothedHover,self.zoom,rects);
    self.glass.frame = shelf;
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:shelf xRadius:24 yRadius:24];
    BOOL solid = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency;
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[panelColor colorWithAlphaComponent:solid ? 1 : 0.9]
        endingColor:[panelColor colorWithAlphaComponent:solid ? 1 : 0.65]];
    [gradient drawInBezierPath:background angle:90];
    [[borderColor colorWithAlphaComponent:0.75] setStroke];
    [background setLineWidth:1]; [background stroke];
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    for (NSUInteger i = 0; i < self.apps.count; i++) {
        NSRunningApplication *app = self.apps[i];
        NSRect icon = rects[i];
        CGFloat center = NSMidX(icon), size = icon.size.width, bottom = icon.origin.y;
        NSInteger count = [self.counts[@(app.processIdentifier)] integerValue];
        if (self.hoveredIndex == (NSInteger)i && self.zoom>0.2) {
            [[hoverColor colorWithAlphaComponent:0.38*self.zoom] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(icon,-3,-3) xRadius:13 yRadius:13] fill];
        }
        [NSGraphicsContext.currentContext setImageInterpolation:NSImageInterpolationHigh];
        [app.icon drawInRect:icon
                   fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:app.hidden ? 0.6 : 1
             respectFlipped:NO hints:nil];
        if (front.processIdentifier == app.processIdentifier) {
            [secondaryColor setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(center-6,10,12,3) xRadius:1.5 yRadius:1.5] fill];
        }
        if (count > 1) {
            NSString *badge = [NSString stringWithFormat:@"%ld", (long)count];
            NSDictionary *attributes = @{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightSemibold],
                NSForegroundColorAttributeName:inkColor};
            CGFloat badgeWidth=MAX(14,[badge sizeWithAttributes:attributes].width+7);
            NSRect rect = NSMakeRect(center + size/2 - 10, bottom-1, badgeWidth, 13);
            [hoverColor setFill];
            [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:6 yRadius:6] fill];
            [badge drawAtPoint:NSMakePoint(NSMidX(rect)-[badge sizeWithAttributes:attributes].width/2, bottom+1)
               withAttributes:attributes];
        }
        if (self.hoveredIndex == (NSInteger)i && self.zoom>0.8 &&
            NSProcessInfo.processInfo.systemUptime-self.hoveredSince>0.18) {
            NSDictionary *attributes = @{NSFontAttributeName:[NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName:inkColor};
            NSString *name = app.localizedName ?: @"App";
            NSSize text = [name sizeWithAttributes:attributes];
            CGFloat x = MAX(10, MIN(center-text.width/2, self.bounds.size.width-text.width-10));
            NSRect pill = NSMakeRect(x-8,88,text.width+16,22);
            [[panelColor colorWithAlphaComponent:0.97] setFill];
            NSBezierPath *label = [NSBezierPath bezierPathWithRoundedRect:pill xRadius:8 yRadius:8];
            [label fill];
            [[accentColor colorWithAlphaComponent:0.35] setStroke]; [label stroke];
            [name drawAtPoint:NSMakePoint(x,92) withAttributes:attributes];
        }
    }
}
- (void)mouseDown:(NSEvent *)event {
    NSInteger index = [self indexAt:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index >= 0) [self.apps[index] activateWithOptions:0];
}
- (void)dockAction:(NSMenuItem *)item {
    NSRunningApplication *app = item.representedObject;
    if (item.tag == 1) [app hide];
    else if (item.tag == 2) [app terminate];
    else {
        [app activateWithOptions:0];
        int (*notify)(CFStringRef, int) = dlsym(RTLD_DEFAULT, "CoreDockSendNotification");
        if (notify) notify(CFSTR("com.apple.expose.front.awake"), 0);
    }
}
- (void)rightMouseDown:(NSEvent *)event {
    NSInteger index = [self indexAt:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index < 0) return;
    NSRunningApplication *app = self.apps[index];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:app.localizedName ?: @"App"];
    for (NSUInteger i = 0; i < 3; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@[@"Show windows", @"Hide", @"Quit"][i]
            action:@selector(dockAction:) keyEquivalent:@""];
        item.target = self; item.tag = i; item.representedObject = app;
        [menu addItem:item];
    }
    dockMenuOpen = YES;
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
    dockMenuOpen = NO;
}
@end

static NSPanel *dockPanel;
static DockView *dockView;
static double dockAway = 0, nextApps = 0, dockEdgeSince = 0;
static NSTimer *dockAnimationTimer;

static BOOL missionControlWindow(void) {
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly,kCGNullWindowID));
    for (NSDictionary *window in windows)
        if ([window[(id)kCGWindowOwnerName] isEqual:@"Dock"] && [window[(id)kCGWindowLayer] intValue]==18)
            return YES;
    return NO;
}
static void enterMissionControl(void) {
    missionControl=YES; missionControlSince=NSProcessInfo.processInfo.systemUptime;
    dockPresented=NO; dockRevision++; dockEdgeSince=0;
    [dockPanel orderOut:nil]; [dockAnimationTimer invalidate]; dockAnimationTimer=nil;
    if (visible) setVisible(NO);
}
typedef void ConnectionNotification(uint32_t, void *, size_t, void *, int);
static void connectionEvent(uint32_t type,__unused void *data,__unused size_t length,
                            __unused void *context,__unused int cid) {
    if (type==1204) dispatch_async(dispatch_get_main_queue(),^{ enterMissionControl(); });
}

static void refreshApps(void) {
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
    for (NSDictionary *window in windows) {
        CGRect bounds;
        if ([window[(id)kCGWindowLayer] intValue] != 0
            || !CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)window[(id)kCGWindowBounds], &bounds)
            || bounds.size.width < 80 || bounds.size.height < 60) continue;
        NSNumber *pid = window[(id)kCGWindowOwnerPID];
        counts[pid] = @([counts[pid] integerValue] + 1);
    }
    NSArray *running = [NSWorkspace.sharedWorkspace.runningApplications filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(NSRunningApplication *app, __unused NSDictionary *bindings) {
            return app.activationPolicy == NSApplicationActivationPolicyRegular && !app.terminated
                && (![app.bundleIdentifier isEqual:@"com.apple.finder"] || [counts[@(app.processIdentifier)] intValue] > 0);
        }]];
    // Keep order stable as applications activate; append newly opened applications.
    NSMutableArray *ordered = [NSMutableArray array];
    for (NSRunningApplication *old in dockView.apps)
        if ([running containsObject:old]) [ordered addObject:old];
    for (NSRunningApplication *app in running)
        if (![ordered containsObject:app]) [ordered addObject:app];
    dockView.apps = ordered;
    dockView.counts = counts;
}

static void dockTick(double now, NSPoint pointer) {
    if (now >= nextApps) { nextApps = now + (dockPresented ? 0.5 : 3); refreshApps(); }
    NSScreen *target = nil;
    for (NSScreen *screen in NSScreen.screens) {
        CGFloat half = MIN(screen.frame.size.width-28, dockView.apps.count*52+64)/2;
        if (pointer.x >= NSMinX(screen.frame) && pointer.x < NSMaxX(screen.frame)
            && fabs(pointer.x-NSMidX(screen.frame))<=half
            && pointer.y >= NSMinY(screen.frame) && pointer.y <= NSMinY(screen.frame)+3) target = screen;
    }
    if (target && dockView.apps.count && !dockPresented) {
        if (missionControlWindow()) { enterMissionControl(); return; }
        if (!dockEdgeSince) dockEdgeSince = now;
        if (now-dockEdgeSince<0.08) return;
        CGFloat width = MIN(target.frame.size.width-28, dockView.apps.count*52+132);
        NSRect end = NSMakeRect(NSMidX(target.frame)-width/2, NSMinY(target.frame)+6, width, 116);
        [dockPanel setFrame:NSOffsetRect(end,0,-8) display:NO];
        dockPanel.alphaValue = 0;
        [dockPanel orderFrontRegardless];
        dockPresented = YES; dockRevision++; dockAway = 0;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : 0.16;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [dockPanel.animator setFrame:end display:YES];
            [dockPanel.animator setAlphaValue:1];
        } completionHandler:nil];
        [dockAnimationTimer invalidate];
        dockAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60 repeats:YES block:^(__unused NSTimer *timer) {
            if (!dockPanel.visible) return;
            NSPoint mouse = NSEvent.mouseLocation;
            dockView.hover = NSPointInRect(mouse,NSInsetRect(dockPanel.frame,-6,-6))
                ? mouse.x-NSMinX(dockPanel.frame) : -1;
            [dockView step];
        }];
        [NSRunLoop.mainRunLoop addTimer:dockAnimationTimer forMode:NSRunLoopCommonModes];
    } else if (!target) {
        dockEdgeSince = 0;
    }
    if (!dockPresented) return;
    NSRect rects[MAX(1,dockView.apps.count)];
    NSRect shelf = dockRects(dockPanel.frame.size.width,dockView.apps.count,dockView.smoothedHover,dockView.zoom,rects);
    NSRect active = NSOffsetRect(NSInsetRect(shelf,-12,-10),NSMinX(dockPanel.frame),NSMinY(dockPanel.frame));
    active.size.height = 116;
    BOOL inside = NSPointInRect(pointer,active) || target!=nil;
    dockPanel.ignoresMouseEvents = !inside;
    if (inside || dockMenuOpen) dockAway = 0;
    else {
        if (!dockAway) dockAway = now;
        if (now-dockAway > 0.32) {
            dockPresented = NO; dockAway = 0;
            NSUInteger revision = ++dockRevision;
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : 0.14;
                [dockPanel.animator setAlphaValue:0];
            } completionHandler:^{
                if (revision != dockRevision || dockPresented) return;
                [dockPanel orderOut:nil];
                [dockAnimationTimer invalidate]; dockAnimationTimer = nil;
            }];
        }
    }
    dockView.hover = NSPointInRect(pointer, active) ? pointer.x-NSMinX(dockPanel.frame) : -1;
    [dockView setNeedsDisplay:YES];
}

static BOOL insideBarWindow(NSPoint pointer) {
    // Popup geometry is owned by SketchyBar. Reading window bounds needs no
    // screen recording and keeps the bar open while interacting with a popup.
    CGPoint point = CGPointMake(pointer.x, NSMaxY(NSScreen.screens.firstObject.frame)-pointer.y);
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (NSDictionary *window in windows) {
        NSString *owner = window[(id)kCGWindowOwnerName];
        if (![owner.lowercaseString isEqual:@"sketchybar"]) continue;
        CGRect bounds;
        if (CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)window[(id)kCGWindowBounds], &bounds)
            && CGRectContainsPoint(CGRectInset(bounds, -4, -4), point)) return YES;
    }
    return NO;
}

static void stop(int sig) { stopping = sig; }
static BOOL nativeMenu(BOOL hide) {
    if (setOverride) setOverride(mainConnection(), 0, hide);
    return setAlpha(mainConnection(), 0, 1, hide ? 0 : 1) == kCGErrorSuccess;
}
static void restore(void) { if (setAlpha) nativeMenu(NO); }

// Only called on transitions and for a five-second health check.
static NSDictionary *bar(NSArray<NSString *> *args) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:barPath];
    task.arguments = args;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil]) return nil;
    // SketchyBar's CLI is bounded by its own Mach IPC timeout.
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) return nil;
    if ([args.firstObject isEqual:@"--query"]) {
        id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        return [result isKindOfClass:NSDictionary.class] ? result : nil;
    }
    return @{};
}

static BOOL setVisible(BOOL show) {
    visible = show;
    NSUInteger revision = ++barRevision;
    NSMutableArray *args = [NSMutableArray array];
    if (!show) {
        [args addObjectsFromArray:@[@"--trigger",@"desktop_concealed"]];
        for (NSString *name in @[@"clock", @"weather", @"volume", @"brightness", @"wifi", @"bluetooth", @"alerts", @"battery",
                                 @"cpu", @"gpu", @"memory", @"front_app"])
            [args addObjectsFromArray:@[@"--set", name, @"popup.drawing=off", @"background.drawing=off"]];
    }
    BOOL motion = !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (show) {
        [args addObjectsFromArray:@[@"--bar", motion ? @"y_offset=-48" : @"y_offset=6", @"hidden=off"]];
        if (motion) [args addObjectsFromArray:@[@"--animate", @"tanh", @"10", @"--bar", @"y_offset=6"]];
        [args addObjectsFromArray:@[@"--trigger", @"desktop_revealed"]];
    } else {
        [args addObjectsFromArray:motion ? @[@"--animate", @"tanh", @"9", @"--bar", @"y_offset=-48"]
                                        : @[@"--bar", @"hidden=on"]];
    }
    dispatch_async(barQueue, ^{
        BOOL ok = bar(args) != nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok && revision==barRevision) { healthy=NO; nativeMenu(NO); }
        });
    });
    if (!show && motion) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,180*NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{
            if (visible || revision!=barRevision) return;
            dispatch_async(barQueue, ^{ bar(@[@"--bar",@"hidden=on"]); });
        });
    return YES;
}

static void tick(void) {
    if (stopping) { restore(); exit(0); }
    if (appearanceChanged) { appearanceChanged=0; loadAppearance(); [dockView setNeedsDisplay:YES]; }
    double now = NSProcessInfo.processInfo.systemUptime;
    if (now >= nextHealth && !healthPending) {
        nextHealth = now + 5;
        healthPending = YES;
        dispatch_async(barQueue, ^{
            NSDictionary *state = bar(@[@"--query",@"bar"]);
            dispatch_async(dispatch_get_main_queue(), ^{
                healthPending=NO;
                loadAppearance();
                healthy = state && [state[@"position"] isEqual:@"top"]
                    && [state[@"show_in_fullscreen"] isEqual:@"on"];
                if (!healthy) { nativeMenu(NO); visible=NO; return; }
                if (![state[@"hidden"] isEqual:visible ? @"off" : @"on"]) setVisible(visible);
                if (!nativeMenu(YES)) { healthy=NO; nativeMenu(NO); }
            });
        });
    }
    NSPoint pointer = NSEvent.mouseLocation;
    if (missionControl) {
        if (now-missionControlSince>0.5 && now>=nextMissionCheck) {
            nextMissionCheck=now+0.15;
            if (!missionControlWindow()) { missionControl=NO; nextHealth=0; }
        }
        return;
    }
    dockTick(now, pointer);
    if (!healthy) return;
    BOOL edge = NO, inside = NO;
    for (NSScreen *screen in NSScreen.screens) {
        NSRect frame = screen.frame;
        if (pointer.x < NSMinX(frame) || pointer.x >= NSMaxX(frame)) continue;
        CGFloat distance = NSMaxY(frame) - pointer.y;
        if (distance >= 0 && distance <= 3) edge = YES;
        // Includes bar, notch, and a little exit hysteresis.
        if (distance >= 0 && distance <= 58) inside = YES;
    }
    if (!visible && edge) {
        if (missionControlWindow()) { enterMissionControl(); return; }
        if (!setVisible(YES)) { healthy = NO; nativeMenu(NO); }
        awaySince = 0;
    } else if (visible && !inside && !insideBarWindow(pointer)) {
        if (!awaySince) awaySince = now;
        if (now - awaySince >= 0.32) {
            if (!setVisible(NO)) { healthy = NO; nativeMenu(NO); }
            awaySince = 0;
        }
    } else {
        awaySince = 0;
    }
}

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc==2 && strcmp(argv[1],"--self-test")==0) return layoutSelfTest();
    if ((argc==2 || argc==3) && strcmp(argv[1],"--brightness")==0)
        return brightnessCommand(argc==3 ? argv[2] : NULL);
    void *library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    if (!library) { fputs("SkyLight unavailable. Native menu unchanged.\n", stderr); return 1; }
    mainConnection = dlsym(library, "SLSMainConnectionID");
    setAlpha = dlsym(library, "SLSSetMenuBarInsetAndAlpha");
    setOverride = dlsym(library, "SLSSetMenuBarVisibilityOverrideOnDisplay");
    if (!mainConnection || !setAlpha) { fputs("Menu API unavailable. Native menu unchanged.\n", stderr); return 1; }
    if (argc == 2 && strcmp(argv[1], "--restore") == 0) return nativeMenu(NO) ? 0 : 1;
    BOOL preview = (argc == 3 || argc == 4) && strcmp(argv[1], "--preview") == 0;
    if (argc != 4 && !preview) {
        fputs("Usage: desktop-edge /path/to/sketchybar /private/lock /private/status.json\n", stderr);
        return 64;
    }
    if (!preview) {
        int lock = open(argv[2], O_CREAT | O_RDWR, 0600);
        if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB) != 0) return 1;
        barPath = [NSString stringWithUTF8String:argv[1]];
    }
    appearancePath = preview ? (argc==4 ? [NSString stringWithUTF8String:argv[3]] : nil)
        : [[[NSString stringWithUTF8String:argv[3]] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"appearance.json"];
    loadAppearance();
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    barQueue = dispatch_queue_create("local.dotfiles.desktop.bar",DISPATCH_QUEUE_SERIAL);
    dockPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 300, 116)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered defer:NO];
    dockPanel.level = CGWindowLevelForKey(kCGStatusWindowLevelKey) + 1;
    dockPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
        | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary
        | NSWindowCollectionBehaviorIgnoresCycle;
    dockPanel.opaque = NO; dockPanel.backgroundColor = NSColor.clearColor;
    dockPanel.hasShadow = YES; dockPanel.hidesOnDeactivate = NO;
    NSView *container = [[NSView alloc] initWithFrame:dockPanel.contentView.bounds];
    NSVisualEffectView *glass = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    glass.material = NSVisualEffectMaterialHUDWindow;
    glass.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    glass.state = NSVisualEffectStateActive;
    glass.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    glass.wantsLayer = YES; glass.layer.cornerRadius=24; glass.layer.masksToBounds=YES;
    [container addSubview:glass];
    dockView = [[DockView alloc] initWithFrame:container.bounds];
    dockView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    dockView.hover = -1; dockView.smoothedHover = -1; dockView.hoveredIndex = -1;
    dockView.apps = @[]; dockView.counts = @{}; dockView.glass=glass;
    [container addSubview:dockView];
    dockPanel.contentView = container;
    if (preview) {
        refreshApps();
        [dockPanel setFrame:NSMakeRect(0, 0, dockView.apps.count*52+132, 116) display:NO];
        dockView.hover = 150; dockView.smoothedHover=150; dockView.zoom=1;
        dockView.hoveredIndex=[dockView indexAt:NSMakePoint(150,40)]; dockView.hoveredSince=0;
        NSBitmapImageRep *bitmap = [dockView bitmapImageRepForCachingDisplayInRect:dockView.bounds];
        [dockView cacheDisplayInRect:dockView.bounds toBitmapImageRep:bitmap];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES] ? 0 : 1;
    }
    atexit(restore);
    CGError (*observe)(int,ConnectionNotification *,uint32_t,void *) =
        dlsym(library,"SLSRegisterConnectionNotifyProc");
    if (observe) observe(mainConnection(),connectionEvent,1204,NULL);
    signal(SIGTERM, stop); signal(SIGINT, stop); signal(SIGHUP, stop);
    signal(SIGUSR1, appearanceSignal);
    NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSString *name in @[NSWorkspaceDidLaunchApplicationNotification,NSWorkspaceDidTerminateApplicationNotification,
                             NSWorkspaceDidHideApplicationNotification,NSWorkspaceDidUnhideApplicationNotification])
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) { nextApps=0; }];
    for (NSString *name in @[NSWorkspaceActiveSpaceDidChangeNotification,
                             NSWorkspaceDidWakeNotification,
                             NSWorkspaceDidActivateApplicationNotification]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) { nextHealth = 0; }];
    }
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidChangeScreenParametersNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { nextHealth = 0; }];
    NSString *statusPath = [NSString stringWithUTF8String:argv[3]];
    __block int count = 0;
    NSTimer *poll = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(__unused NSTimer *timer) {
        @autoreleasepool {
            tick();
            if (++count % 20 == 0) {
                NSDictionary *state = @{@"healthy": @(healthy), @"visible": @(visible),
                    @"dock_visible": @(dockPanel.visible), @"open_apps": @(dockView.apps.count),
                    @"mission_control": @(missionControl),
                    @"theme": themeName,
                    @"pid": @(getpid()), @"updated": @([NSDate.date timeIntervalSince1970])};
                NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
                [data writeToFile:statusPath atomically:YES];
                chmod(statusPath.fileSystemRepresentation, 0600);
            }
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:poll forMode:NSRunLoopCommonModes];
    tick();
    [NSApp run];
    return 0;
} }
