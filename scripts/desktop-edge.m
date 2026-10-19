#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ApplicationServices/ApplicationServices.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <EventKit/EventKit.h>
#import "calendar-panel.h"
#import "control-panel.h"
#import "app-menu.h"
#import "panel-request.h"
#include <dlfcn.h>
#include <signal.h>
#include <sys/file.h>
#include <fcntl.h>
#include <sys/stat.h>

// Local, reversible SkyLight calls used by yabai's menubar_opacity:
// https://github.com/asmvik/yabai/blob/master/src/misc/extern.h
// No injection, root access, cursor warping, or SIP changes. A separate
// Dock-only mouse-motion tap blocks its bottom-edge reveal gesture.
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
static CFMachPortRef nativeDockTap;
static CFRunLoopSourceRef nativeDockSource;
static pid_t nativeDockPID;
static CGRect dockDisplays[16];
static uint32_t dockDisplayCount;
static NSUInteger nativeDockBlocked;
static SCDynamicStoreRef networkStore;
static CFRunLoopSourceRef networkSource;
static double missionControlSince = 0, nextMissionCheck = 0;
static BOOL setVisible(BOOL show);
static NSString *appearancePath, *themeName;
static NSString *desktopDirectory;
static pid_t previewCandidate,previewRequested;
static double previewSince;
static volatile sig_atomic_t appearanceChanged = 0;
static NSDictionary *controlsAccessStatus(void) {
    return @{@"accessibility":[NSNumber numberWithBool:AXIsProcessTrusted()],
             @"calendar":[NSNumber numberWithBool:[EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent]==EKAuthorizationStatusFullAccess]};
}
static int accessStatusSelfTest(void) {
    for (NSNumber *value in controlsAccessStatus().allValues)
        if (CFGetTypeID((__bridge CFTypeRef)value)!=CFBooleanGetTypeID()) return 1;
    return 0;
}
static void appearanceSignal(__unused int sig) { appearanceChanged=1; }

static void loadAppearance(void) {
    if (appearancePath) DFControlsAppearance(appearancePath);
    NSData *data = appearancePath ? [NSData dataWithContentsOfFile:appearancePath] : nil;
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *palette = [value isKindOfClass:NSDictionary.class] ? value : @{};
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
        // A 40pt resting icon peaks at 77.5pt (previously 62pt).
        sizes[i] = base + base * 0.9375 * zoom * exp(-(distance*distance)/(2*72*72));
        sum += sizes[i];
    }
    CGFloat shrink = MIN(1, MAX(1, available-(count-1)*gap)/sum);
    sum *= shrink;
    CGFloat total = sum+(count-1)*gap, x=(width-total)/2;
    for (NSUInteger i=0; i<count; i++) {
        CGFloat size = sizes[i]*shrink;
        rects[i] = NSMakeRect(x, 0, size, size);
        x += size+gap;
    }
    return NSMakeRect((width-total)/2-16, 0, total+32, 84);
}

static NSRect dockFrame(NSRect screen, NSUInteger count) {
    CGFloat width = MIN(screen.size.width-28, count*52+132);
    return NSMakeRect(NSMidX(screen)-width/2, NSMinY(screen), width, 116);
}

static NSRect dockRevealRect(NSRect screen, NSUInteger count) {
    if (!count) return NSZeroRect;
    NSRect frame = dockFrame(screen,count), rects[count];
    NSRect footprint = dockRects(frame.size.width,count,-1,0,rects);
    // Reveal where the resting icons will be, without intercepting app clicks.
    footprint.size.height = 44;
    return NSOffsetRect(footprint,frame.origin.x,frame.origin.y);
}

static CGFloat settle(CGFloat value, CGFloat target, double elapsed, double response, CGFloat tolerance) {
    CGFloat next=value+(target-value)*(1-exp(-elapsed/response));
    return fabs(target-next)<tolerance ? target : next;
}
static BOOL nativeDockRevealPoint(CGPoint point, const CGRect *screens, NSUInteger count) {
    for (NSUInteger i=0;i<count;i++) {
        CGRect screen=screens[i];
        if (point.x<CGRectGetMinX(screen) || point.x>=CGRectGetMaxX(screen)
            || point.y<CGRectGetMaxY(screen)-2 || point.y>CGRectGetMaxY(screen)+1) continue;
        CGPoint below=CGPointMake(point.x,CGRectGetMaxY(screen)+1);
        for (NSUInteger j=0;j<count;j++) if (j!=i && CGRectContainsPoint(screens[j],below)) return NO;
        return YES;
    }
    return NO;
}
static void releaseNativeDockGuard(void) {
    if (nativeDockSource) { CFRunLoopRemoveSource(CFRunLoopGetMain(),nativeDockSource,kCFRunLoopCommonModes); CFRelease(nativeDockSource); nativeDockSource=NULL; }
    if (nativeDockTap) { CFMachPortInvalidate(nativeDockTap); CFRelease(nativeDockTap); nativeDockTap=NULL; }
    nativeDockPID=0;
}
static CGEventRef nativeDockMotion(__unused CGEventTapProxy proxy, CGEventType type, CGEventRef event, __unused void *context) {
    if (type==kCGEventTapDisabledByTimeout) { if (nativeDockTap) CGEventTapEnable(nativeDockTap,true); return event; }
    // This tap sees only motion routed to Dock. No key, button, wheel or
    // drag events are subscribed; cursor motion in other apps is untouched.
    if (type==kCGEventMouseMoved && healthy && !missionControl && nativeDockRevealPoint(CGEventGetLocation(event),dockDisplays,dockDisplayCount)) {
        nativeDockBlocked++; return NULL;
    }
    return event;
}
static void ensureNativeDockGuard(void) {
    CGDirectDisplayID identifiers[16]; uint32_t count=0;
    if (CGGetActiveDisplayList(16,identifiers,&count)==kCGErrorSuccess) {
        dockDisplayCount=count;
        for (uint32_t i=0;i<count;i++) dockDisplays[i]=CGDisplayBounds(identifiers[i]);
    }
    pid_t pid=[[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"].firstObject processIdentifier];
    if (!AXIsProcessTrusted() || !pid) { releaseNativeDockGuard(); return; }
    if (nativeDockTap && nativeDockPID==pid) return;
    releaseNativeDockGuard();
    nativeDockTap=CGEventTapCreateForPid(pid,kCGHeadInsertEventTap,kCGEventTapOptionDefault,CGEventMaskBit(kCGEventMouseMoved),nativeDockMotion,NULL);
    if (!nativeDockTap) return;
    nativeDockPID=pid; nativeDockSource=CFMachPortCreateRunLoopSource(NULL,nativeDockTap,0);
    CFRunLoopAddSource(CFRunLoopGetMain(),nativeDockSource,kCFRunLoopCommonModes);
}

static int layoutSelfTest(void) {
    for (NSUInteger count=1; count<=40; count++) for (int width=800; width<=2200; width+=200)
        for (int point=0; point<=width; point+=37) {
            NSRect rects[count];
            NSRect shelf = dockRects(width,count,point,1,rects);
            if (NSMinX(shelf)<0 || NSMaxX(shelf)>width) return 1;
            for (NSUInteger i=0; i<count; i++)
                if (NSMinX(rects[i])<0 || NSMaxX(rects[i])>width || NSMinY(rects[i])!=0 ||
                    NSMaxY(rects[i])>116 ||
                    (i && NSMaxX(rects[i-1])>=NSMinX(rects[i]))) return 1;
        }
    NSRect icon[1];
    dockRects(800,1,400,0,icon);
    if (fabs(icon[0].size.width-40)>0.001) return 1;
    dockRects(800,1,400,1,icon);
    if (fabs(icon[0].size.width-62*1.25)>0.001) return 1;
    for (int offset=-1200; offset<=1200; offset+=1200) {
        NSRect screen = NSMakeRect(offset,offset,1440,900);
        NSRect frame = dockFrame(screen,3), reveal = dockRevealRect(screen,3), rects[3];
        dockRects(frame.size.width,3,-1,0,rects);
        for (NSUInteger i=0; i<3; i++) {
            NSPoint center = NSMakePoint(frame.origin.x+NSMidX(rects[i]),frame.origin.y+NSMidY(rects[i]));
            if (!NSPointInRect(center,reveal) || NSMinY(frame)!=NSMinY(screen)) return 1;
        }
        if (NSPointInRect(NSMakePoint(NSMidX(reveal),NSMaxY(reveal)+1),reveal)) return 1;
    }
    CGFloat reference=0;
    for (int rate=30;rate<=120;rate*=2) {
        CGFloat value=0;
        for (int i=0;i<rate/10;i++) value=settle(value,1,1.0/rate,0.067,0.00001);
        if (rate==30) reference=value;
        else if (fabs(value-reference)>0.00001) return 1;
        for (int i=rate/10;i<rate;i++) value=settle(value,1,1.0/rate,0.067,0.00001);
        if (value!=1) return 1;
    }
    puts("Dock geometry: bottom alignment, reveal footprint, 25% larger peak, bounds and non-overlap passed.");
    puts("Dock motion: elapsed-time smoothing is frame-rate independent and settles exactly.");
    CGRect screens[]={CGRectMake(0,0,1440,900),CGRectMake(0,900,1440,900)};
    if (nativeDockRevealPoint(CGPointMake(500,899),screens,2)
        || !nativeDockRevealPoint(CGPointMake(500,1799),screens,2)
        || nativeDockRevealPoint(CGPointMake(500,1750),screens,2)
        || nativeDockRevealPoint(CGPointMake(-10,1799),screens,2)) return 1;
    puts("Dock reveal guard: outer bottom edge only; connected-screen seams and other pointer positions pass.");
    return 0;
}

// Mission Control/Space strips change WindowServer levels across OS releases.
// Require Dock ownership and display-sized geometry, not a single magic level.
static BOOL overviewWindow(NSDictionary *window,NSArray<NSValue *> *screens) {
    NSInteger level=[window[(id)kCGWindowLayer] integerValue];CGRect bounds;
    if (![window[(id)kCGWindowOwnerName] isEqual:@"Dock"] || level<18 || level>24
        || (window[(id)kCGWindowAlpha] && [window[(id)kCGWindowAlpha] doubleValue]<=.01)
        || !CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)window[(id)kCGWindowBounds],&bounds)) return NO;
    for (NSValue *value in screens) {
        CGRect screen=NSRectToCGRect(value.rectValue),intersection=CGRectIntersection(screen,bounds);
        if (CGRectIsNull(intersection) || intersection.size.width<screen.size.width*.8) continue;
        BOOL large=intersection.size.height>screen.size.height*.4;
        BOOL strip=intersection.size.height>=100 && intersection.size.height<screen.size.height*.35
            && fabs(CGRectGetMinY(intersection)-CGRectGetMinY(screen))<=36;
        if (large || strip) return YES;
    }
    return NO;
}
static int overviewSelfTest(void) {
    NSArray *screens=@[[NSValue valueWithRect:NSMakeRect(0,0,1440,900)]];
    NSMutableDictionary *window=[@{(id)kCGWindowOwnerName:@"Dock",(id)kCGWindowLayer:@20,
        (id)kCGWindowBounds:CFBridgingRelease(CGRectCreateDictionaryRepresentation(CGRectMake(0,0,1440,900)))} mutableCopy];
    if (!overviewWindow(window,screens)) return 1;
    for (NSNumber *level in @[@18,@19,@20,@21]) {window[(id)kCGWindowLayer]=level;if (!overviewWindow(window,screens)) return 1;}
    window[(id)kCGWindowBounds]=CFBridgingRelease(CGRectCreateDictionaryRepresentation(CGRectMake(0,0,1440,140)));
    if (!overviewWindow(window,screens)) return 1;
    window[(id)kCGWindowBounds]=CFBridgingRelease(CGRectCreateDictionaryRepresentation(CGRectMake(0,800,1440,100)));
    if (overviewWindow(window,screens)) return 1;
    window[(id)kCGWindowBounds]=CFBridgingRelease(CGRectCreateDictionaryRepresentation(CGRectMake(0,0,1440,900)));
    window[(id)kCGWindowOwnerName]=@"Other App";if (overviewWindow(window,screens)) return 1;
    window[(id)kCGWindowOwnerName]=@"Dock";window[(id)kCGWindowAlpha]=@0;if (overviewWindow(window,screens)) return 1;
    puts("Overview detection: modern/legacy Dock overlays and Space strips; native dock/other apps/transparent windows excluded.");return 0;
}

static NSWorkspaceOpenConfiguration *dockOpenConfiguration(void) {
    NSWorkspaceOpenConfiguration *configuration=NSWorkspaceOpenConfiguration.configuration;
    configuration.activates=YES; configuration.createsNewApplicationInstance=NO;
    configuration.addsToRecentItems=NO; return configuration;
}
static int dockOpenSelfTest(void) {
    NSWorkspaceOpenConfiguration *configuration=dockOpenConfiguration();
    return !configuration.activates || configuration.createsNewApplicationInstance || configuration.addsToRecentItems;
}
static void reopenDockApp(NSRunningApplication *app) {
    if (app.terminated) return;
    NSURL *url=app.bundleURL;
    if (!url) { [app activateWithOptions:NSApplicationActivateAllWindows]; return; }
    // Opening the existing bundle delivers normal reopen behavior, including
    // restoring/recreating a window. It does not launch a second app instance.
    [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:dockOpenConfiguration() completionHandler:^(__unused NSRunningApplication *opened,NSError *error) {
        if (error) dispatch_async(dispatch_get_main_queue(),^{ [app activateWithOptions:NSApplicationActivateAllWindows]; });
    }];
}

@interface DockView : NSView
@property NSArray<NSRunningApplication *> *apps;
@property CGFloat hover;
@property CGFloat smoothedHover;
@property CGFloat zoom;
@property double lastStep;
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
        if (NSPointInRect(point,rects[i])) return i;
    return -1;
}
- (void)step {
    double now=CACurrentMediaTime(), elapsed=self.lastStep ? MIN(0.1,now-self.lastStep) : 1.0/60;
    self.lastStep=now;
    CGFloat previousZoom=self.zoom, previousHover=self.smoothedHover;
    CGFloat desired = self.hover < 0 ? 0 : 1;
    self.zoom = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion
        ? desired : settle(self.zoom,desired,elapsed,0.067,0.001);
    if (self.hover >= 0) {
        if (self.smoothedHover < 0) self.smoothedHover = self.hover;
        else self.smoothedHover = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion
            ? self.hover : settle(self.smoothedHover,self.hover,elapsed,0.047,0.05);
    }
    if (self.zoom!=previousZoom || self.smoothedHover!=previousHover) [self setNeedsDisplay:YES];
}
- (void)drawRect:(__unused NSRect)dirty {
    NSRectFillUsingOperation(self.bounds,NSCompositingOperationClear);
    NSUInteger count = self.apps.count;
    if (!count) return;
    NSRect rects[count];
    dockRects(self.bounds.size.width,count,self.smoothedHover,self.zoom,rects);
    [NSGraphicsContext.currentContext setImageInterpolation:NSImageInterpolationHigh];
    for (NSUInteger i=0; i<count; i++) {
        NSRunningApplication *app = self.apps[i];
        [app.icon drawInRect:rects[i]
                   fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:app.hidden ? 0.6 : 1
             respectFlipped:NO hints:nil];
    }
}
- (void)mouseDown:(NSEvent *)event {
    NSInteger index = [self indexAt:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index >= 0) reopenDockApp(self.apps[index]);
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
    NSMutableArray *screens=NSMutableArray.new;
    for (NSScreen *screen in NSScreen.screens) {
        CGDirectDisplayID display=[screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        [screens addObject:[NSValue valueWithRect:NSRectFromCGRect(CGDisplayBounds(display))]];
    }
    pid_t dock=[[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"].firstObject processIdentifier];
    for (NSDictionary *window in windows)
        if ([window[(id)kCGWindowOwnerPID] intValue]==dock && overviewWindow(window,screens))
            return YES;
    return NO;
}
static void enterMissionControl(void) {
    DFCalendarHide();DFControlsHide();DFMenusHide();DFWorkspaceCancelAll(desktopDirectory);
    missionControl=YES; missionControlSince=NSProcessInfo.processInfo.systemUptime;
    dockPresented=NO; dockRevision++; dockEdgeSince=0;
    [dockPanel orderOut:nil]; [dockAnimationTimer invalidate]; dockAnimationTimer=nil;
    previewCandidate=0;previewRequested=0;previewSince=0;
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
    [dockView setNeedsDisplay:YES];
}

static void dockTick(double now, NSPoint pointer) {
    if (now >= nextApps) { nextApps = now + (dockPresented ? 0.5 : 3); refreshApps(); }
    NSScreen *target = nil;
    for (NSScreen *screen in NSScreen.screens) {
        if (NSPointInRect(pointer,dockRevealRect(screen.frame,dockView.apps.count))) target = screen;
    }
    if (target && dockView.apps.count && !dockPresented) {
        if (missionControlWindow()) { enterMissionControl(); return; }
        if (!dockEdgeSince) dockEdgeSince = now;
        if (now-dockEdgeSince<0.08) return;
        NSRect end = dockFrame(target.frame,dockView.apps.count);
        dockView.hover = pointer.x-NSMinX(end);
        dockView.smoothedHover = dockView.hover;
        dockView.zoom = 0;
        dockView.lastStep=0;
        [dockPanel setFrame:NSOffsetRect(end,0,-8) display:NO];
        dockPanel.alphaValue = 0;
        [dockPanel orderFrontRegardless];
        dockPresented = YES; dockRevision++; dockAway = 0;
        previewCandidate=0;previewRequested=0;previewSince=0;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : 0.16;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [dockPanel.animator setFrame:end display:YES];
            [dockPanel.animator setAlphaValue:1];
        } completionHandler:nil];
        [dockAnimationTimer invalidate];
        NSInteger frameRate=MAX(30,MIN(120,target.maximumFramesPerSecond));
        dockAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/frameRate repeats:YES block:^(__unused NSTimer *timer) {
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
    active.size.height = 92;
    NSDictionary *workspace=DFWorkspaceReadStatus(desktopDirectory);
    NSArray *workspaceFrame=workspace[@"frame"];
    NSRect preview=workspaceFrame.count==4 ? NSMakeRect([workspaceFrame[0] doubleValue],[workspaceFrame[1] doubleValue],[workspaceFrame[2] doubleValue],[workspaceFrame[3] doubleValue]) : NSZeroRect;
    BOOL previewVisible=[workspace[@"visible"] boolValue] && [workspace[@"kind"] isEqual:@"dock"];
    BOOL inside = NSPointInRect(pointer,active) || target!=nil || (previewVisible && NSPointInRect(pointer,NSInsetRect(preview,-8,-8)));
    NSPoint local = NSMakePoint(pointer.x-NSMinX(dockPanel.frame),pointer.y-NSMinY(dockPanel.frame));
    dockPanel.ignoresMouseEvents = !dockMenuOpen && [dockView indexAt:local]<0;
    NSInteger index=[dockView indexAt:local];
    if (index>=0 && !dockMenuOpen && NSPointInRect(pointer,active)) {
        pid_t candidate=dockView.apps[index].processIdentifier;
        if (previewCandidate!=candidate) {previewCandidate=candidate;previewSince=now;}
        if (candidate!=previewRequested && now-previewSince>=.28) {
            NSRect anchor=NSOffsetRect(rects[index],dockPanel.frame.origin.x,dockPanel.frame.origin.y);
            DFCalendarHide();DFControlsHide();DFMenusHide();
            if (DFWorkspaceRequest(desktopDirectory,@"dock",candidate,anchor)) previewRequested=candidate;
        }
    } else if (!inside) {
        previewCandidate=0;previewSince=0;
        if (previewRequested) {DFWorkspaceCancel(desktopDirectory);previewRequested=0;}
    }
    if (inside || dockMenuOpen) dockAway = 0;
    else {
        if (!dockAway) dockAway = now;
        if (now-dockAway > 0.32) {
            dockPresented = NO; dockAway = 0;
            DFWorkspaceCancel(desktopDirectory);previewRequested=0;previewCandidate=0;
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
static void releaseNetworkObserver(void) {
    if (networkSource) { CFRunLoopRemoveSource(CFRunLoopGetMain(),networkSource,kCFRunLoopCommonModes); CFRelease(networkSource); networkSource=NULL; }
    if (networkStore) { CFRelease(networkStore); networkStore=NULL; }
}
static void restore(void) { releaseNetworkObserver(); releaseNativeDockGuard(); if (setAlpha) nativeMenu(NO); }

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

static void networkChanged(__unused SCDynamicStoreRef store,__unused CFArrayRef changed,__unused void *context) {
    if (!healthy) return;
    // No SSIDs or values are read or forwarded. The backend refreshes only
    // an already-open Wi-Fi pane; hidden panes stay hidden.
    dispatch_async(barQueue,^{ bar(@[@"--trigger",@"desktop_network_changed"]); });
}
static void observeNetwork(void) {
    networkStore=SCDynamicStoreCreate(NULL,CFSTR("Desktop Controls link changes"),networkChanged,NULL);
    if (!networkStore) return;
    NSArray *patterns=@[@"State:/Network/Interface/[^/]+/(Link|IPv4|IPv6)",@"State:/Network/Global/(IPv4|IPv6)"];
    if (!SCDynamicStoreSetNotificationKeys(networkStore,NULL,(__bridge CFArrayRef)patterns)) { releaseNetworkObserver(); return; }
    networkSource=SCDynamicStoreCreateRunLoopSource(NULL,networkStore,0);
    if (!networkSource) { releaseNetworkObserver(); return; }
    CFRunLoopAddSource(CFRunLoopGetMain(),networkSource,kCFRunLoopCommonModes);
}

static BOOL setVisible(BOOL show) {
    visible = show;
    NSUInteger revision = ++barRevision;
    NSMutableArray *args = [NSMutableArray array];
    if (!show) {
        DFCalendarHide();
        DFControlsHide();
        DFMenusHide();
        [args addObjectsFromArray:@[@"--trigger",@"desktop_concealed"]];
        for (NSString *name in @[@"clock", @"weather", @"volume", @"brightness", @"wifi", @"bluetooth", @"alerts", @"battery",
                                 @"cpu", @"gpu", @"memory", @"front_app"])
            [args addObjectsFromArray:@[@"--set", name, @"popup.drawing=off", @"background.drawing=off"]];
    }
    if (show) {
        // Keep anchors stationary: sliding the whole bar also moves its
        // popups and races hover events while the pointer is already inside.
        [args addObjectsFromArray:@[@"--bar", @"y_offset=4", @"hidden=off"]];
        [args addObjectsFromArray:@[@"--trigger", @"desktop_revealed"]];
    } else {
        [args addObjectsFromArray:@[@"--bar", @"hidden=on"]];
    }
    dispatch_async(barQueue, ^{
        __block BOOL current=NO;
        dispatch_sync(dispatch_get_main_queue(),^{current=revision==barRevision;});
        if (!current) return;
        BOOL ok = bar(args) != nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok && revision==barRevision) { healthy=NO; nativeMenu(NO); }
        });
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
                if (!healthy) { releaseNativeDockGuard(); nativeMenu(NO); visible=NO; return; }
                if (![state[@"hidden"] isEqual:visible ? @"off" : @"on"]) setVisible(visible);
                if (!nativeMenu(YES)) { healthy=NO; releaseNativeDockGuard(); nativeMenu(NO); }
                else ensureNativeDockGuard();
            });
        });
    }
    NSPoint pointer = NSEvent.mouseLocation;
    if (!missionControl && now>=nextMissionCheck) {
        nextMissionCheck=now+((visible || dockPresented) ? .1 : .25);
        if (missionControlWindow()) enterMissionControl();
    }
    DFCalendarTick(now,pointer);
    DFControlsTick(now,pointer);
    DFMenusTick(now,pointer,visible);
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
    } else if (visible && !inside && !insideBarWindow(pointer) && !DFCalendarContainsPointer(pointer) && !DFControlsContainsPointer(pointer) && !DFMenusContainsPointer(pointer)) {
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
    if (argc==2 && strcmp(argv[1],"--overview-status")==0) {
        [NSApplication sharedApplication];printf("{\"overview\":%s}\n",missionControlWindow() ? "true" : "false");return 0;
    }
    if (argc==2 && (strcmp(argv[1],"--access-status")==0 || strcmp(argv[1],"--request-access")==0)) {
        [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (strcmp(argv[1],"--request-access")==0) {
            if (!AXIsProcessTrusted()) AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
            else if ([EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent]!=EKAuthorizationStatusFullAccess) {
                EKEventStore *store=EKEventStore.new;__block BOOL finished=NO;
                [store requestFullAccessToEventsWithCompletion:^(__unused BOOL granted,__unused NSError *error) {
                    dispatch_async(dispatch_get_main_queue(),^{finished=YES;});
                }];
                double deadline=NSProcessInfo.processInfo.systemUptime+85;
                while (!finished && NSProcessInfo.processInfo.systemUptime<deadline)
                    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
            }
        }
        NSDictionary *status=controlsAccessStatus();
        NSData *json=[NSJSONSerialization dataWithJSONObject:status options:0 error:nil];fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);return 0;
    }
    if (argc==2 && strcmp(argv[1],"--self-test")==0) return layoutSelfTest() || dockOpenSelfTest() || overviewSelfTest() || accessStatusSelfTest() || DFCalendarSelfTest() || DFControlsSelfTest() || DFMenusSelfTest();
    if (argc==2 && strcmp(argv[1],"--launcher")==0) {
        NSString *state=NSProcessInfo.processInfo.environment[@"XDG_STATE_HOME"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@".local/state"];
        NSPoint pointer=NSEvent.mouseLocation;
        return DFWorkspaceRequest([state stringByAppendingPathComponent:@"dotfiles/desktop"],@"launcher",0,NSMakeRect(pointer.x,pointer.y,1,1)) ? 0 : 1;
    }
    if (argc==3 && strcmp(argv[1],"--app-menu")==0) { DFMenusNotify([NSString stringWithUTF8String:argv[2]]); return 0; }
    if (argc==2 && (strcmp(argv[1],"--controls")==0 || strcmp(argv[1],"--controls-hide")==0)) {
        DFControlsNotify(strcmp(argv[1],"--controls")==0 ? @"show" : @"hide"); return 0;
    }
    if ((argc==3 || argc==4) && strcmp(argv[1],"--controls-preview")==0) {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        return DFControlsPreview([NSString stringWithUTF8String:argv[2]],argc==4 ? [NSString stringWithUTF8String:argv[3]] : @"cpu") ? 0 : 1;
    }
    if (argc==2 && (strcmp(argv[1],"--calendar")==0 || strcmp(argv[1],"--calendar-hide")==0 || strcmp(argv[1],"--calendar-access")==0)) {
        DFCalendarNotify(strcmp(argv[1],"--calendar")==0 ? @"show" : strcmp(argv[1],"--calendar-hide")==0 ? @"hide" : @"access");
        return 0;
    }
    if (argc==3 && strcmp(argv[1],"--calendar-preview")==0) {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        return DFCalendarPreview([NSString stringWithUTF8String:argv[2]]) ? 0 : 1;
    }
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
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    if (!preview) {
        NSString *directory=[[NSString stringWithUTF8String:argv[3]] stringByDeletingLastPathComponent];
        desktopDirectory=directory;
        DFCalendarInitialize(directory); DFControlsInitialize(directory);
        DFMenusInitialize(barPath);
    }
    barQueue = dispatch_queue_create("local.dotfiles.desktop.bar",DISPATCH_QUEUE_SERIAL);
    observeNetwork();
    dockPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 300, 116)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered defer:NO];
    dockPanel.level = CGWindowLevelForKey(kCGStatusWindowLevelKey) + 1;
    dockPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
        | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary
        | NSWindowCollectionBehaviorIgnoresCycle;
    dockPanel.opaque = NO; dockPanel.backgroundColor = NSColor.clearColor;
    dockPanel.hasShadow = NO; dockPanel.hidesOnDeactivate = NO;
    dockView = [[DockView alloc] initWithFrame:dockPanel.contentView.bounds];
    dockView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    dockView.hover = -1; dockView.smoothedHover = -1;
    dockView.apps = @[];
    dockPanel.contentView = dockView;
    if (preview) {
        refreshApps();
        [dockPanel setFrame:NSMakeRect(0, 0, dockView.apps.count*52+132, 116) display:NO];
        dockView.hover = 150; dockView.smoothedHover=150; dockView.zoom=1;
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
            usingBlock:^(NSNotification *note) {
                nextHealth=0;DFCalendarHide();DFControlsHide();DFMenusHide();
                if ([note.name isEqual:NSWorkspaceActiveSpaceDidChangeNotification] || [note.name isEqual:NSWorkspaceDidWakeNotification]) {
                    DFWorkspaceCancelAll(desktopDirectory);dockRevision++;dockPresented=NO;dockAway=0;dockEdgeSince=0;
                    previewCandidate=0;previewRequested=0;previewSince=0;
                    [dockPanel orderOut:nil];[dockAnimationTimer invalidate];dockAnimationTimer=nil;
                    setVisible(NO);
                }
            }];
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
                    @"native_dock_guard": @(nativeDockTap && CGEventTapIsEnabled(nativeDockTap)),
                    @"native_dock_blocked": @(nativeDockBlocked),
                    @"network_events": @(networkSource!=NULL),
                    @"mission_control": @(missionControl),
                    @"calendar": DFCalendarStatus(),
                    @"controls": DFControlsStatus(),
                    @"app_menus": DFMenusStatus(),
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
