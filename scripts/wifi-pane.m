#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import "control-panel.h"
#import "panel-style.h"
#import "workspace-panels.h"
#import "panel-request.h"
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

// A short-lived, permission-gated adapter for the real system Wi-Fi controls.
// Screen images exist only in memory, solely to conceal native UI creation.
static id value(id element, CFStringRef key) {
    CFTypeRef result=NULL;
    if (!element || AXUIElementCopyAttributeValue((__bridge AXUIElementRef)element,key,&result)!=kAXErrorSuccess) return nil;
    return CFBridgingRelease(result);
}
static NSArray *children(id element) {
    id result=value(element,kAXChildrenAttribute);
    return [result isKindOfClass:NSArray.class] ? result : @[];
}
static NSArray *windows(id application) {
    id result=value(application,kAXWindowsAttribute);
    return [result isKindOfClass:NSArray.class] ? result : @[];
}
static id application(NSString *name) {
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications)
        if ([app.executableURL.lastPathComponent isEqual:name]) {
            AXUIElementRef result=AXUIElementCreateApplication(app.processIdentifier);
            AXUIElementSetMessagingTimeout(result,.75);
            return CFBridgingRelease(result);
        }
    return nil;
}
static NSString *text(id element) {
    for (NSString *key in @[(id)kAXTitleAttribute,(id)kAXDescriptionAttribute,(id)kAXValueAttribute]) {
        id result=value(element,(__bridge CFStringRef)key);
        if ([result isKindOfClass:NSString.class] && [result length] && [result length]<=512) return result;
    }
    return @"";
}
static BOOL safeText(id string, NSUInteger limit) {
    return [string isKindOfClass:NSString.class] && [string length] && [string length]<=limit
        && [string rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound;
}
static id find(id root, NSString *identifier, NSString *role, NSUInteger depth, NSUInteger *budget) {
    if (!*budget || depth>8) return nil; --*budget;
    if ([value(root,kAXIdentifierAttribute) isEqual:identifier] && (!role || [value(root,kAXRoleAttribute) isEqual:role])) return root;
    for (id child in children(root)) { id result=find(child,identifier,role,depth+1,budget); if (result) return result; }
    return nil;
}
static NSDictionary *descriptor(id element) {
    NSString *role=value(element,kAXRoleAttribute), *identifier=value(element,kAXIdentifierAttribute);
    identifier=[identifier isKindOfClass:NSString.class] ? identifier : @"";
    NSString *kind=nil,*label=nil;
    if ([role isEqual:@"AXCheckBox"]) {
        if ([identifier isEqual:@"wifi-header"]) { kind=@"power"; label=@"Wi-Fi"; }
        else if ([identifier hasPrefix:@"wifi-network-"]) {
            label=[identifier substringFromIndex:13];
            if (!safeText(label,32) || [label lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>32) return nil;
            kind=@"network";
        }
    } else if ([@[@"AXButton",@"AXDisclosureTriangle",@"AXHeading"] containsObject:role]) {
        label=text(element);
        kind=[role isEqual:@"AXHeading"] ? @"section" : [role isEqual:@"AXDisclosureTriangle"] ? @"disclosure" : @"button";
    }
    if (!kind || !safeText(label,512)) return nil;
    return @{@"kind":kind,@"text":label,@"role":role,@"identifier":identifier,
             @"selected":@((BOOL)([kind isEqual:@"disclosure"] ? [value(element,kAXValueAttribute) boolValue] : [value(element,kAXValueAttribute) integerValue]==1)),
             @"enabled":@((BOOL)(![value(element,kAXEnabledAttribute) isEqual:@NO]))};
}
static void collect(id root, NSMutableArray *rows, NSUInteger depth, NSUInteger *budget) {
    if (!*budget || depth>8 || rows.count>=96) return; --*budget;
    NSString *role=value(root,kAXRoleAttribute);
    // Never read credential controls or their contents.
    if ([@[@"AXTextField",@"AXTextArea",@"AXSecureTextField"] containsObject:role]) return;
    NSDictionary *row=descriptor(root);
    if (row) [rows addObject:row];
    if (row && ![row[@"kind"] isEqual:@"section"]) return;
    for (id child in children(root)) collect(child,rows,depth+1,budget);
}
static id findAction(id root, NSDictionary *selector, NSUInteger depth, NSUInteger *budget) {
    if (!*budget || depth>8) return nil; --*budget;
    NSDictionary *row=descriptor(root);
    if (row && ![row[@"kind"] isEqual:@"section"]) {
        BOOL same=YES;
        for (NSString *key in @[@"role",@"identifier",@"text",@"selected"])
            if (![row[key] isEqual:selector[key]]) same=NO;
        if (same && [row[@"enabled"] boolValue]) return root;
    }
    NSString *role=value(root,kAXRoleAttribute);
    if ([@[@"AXTextField",@"AXTextArea",@"AXSecureTextField"] containsObject:role]) return nil;
    for (id child in children(root)) { id result=findAction(child,selector,depth+1,budget); if (result) return result; }
    return nil;
}
static void pump(double duration) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:duration]];
}
static NSArray<NSPanel *> *covers;
static BOOL beginCover(void) {
    if (!CGPreflightScreenCaptureAccess() || !NSScreen.screens.count || NSScreen.screens.count>8) return NO;
    if (@available(macOS 15.2,*)) {
        // Capture every screen before presenting any cover, so extending a
        // desktop does not disable the adapter or capture one of our covers.
        NSMutableArray *prepared=NSMutableArray.new;
        for (NSScreen *screen in NSScreen.screens) {
            CGDirectDisplayID display=[screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            __block CGImageRef snapshot=NULL; __block BOOL complete=NO,abandoned=NO;
            [SCScreenshotManager captureImageInRect:CGDisplayBounds(display) completionHandler:^(CGImageRef image,__unused NSError *error) {
                CGImageRef retained=image ? CGImageRetain(image) : NULL;
                dispatch_async(dispatch_get_main_queue(),^{if (abandoned) {if (retained) CGImageRelease(retained);return;} snapshot=retained;complete=YES;});
            }];
            CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+2;
            while (!complete && CFAbsoluteTimeGetCurrent()<deadline) pump(.005);
            if (!snapshot) {abandoned=YES;return NO;}
            NSPanel *cover=[[NSPanel alloc] initWithContentRect:screen.frame styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
            cover.level=NSScreenSaverWindowLevel;cover.animationBehavior=NSWindowAnimationBehaviorNone;
            cover.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorCanJoinAllApplications|NSWindowCollectionBehaviorTransient|NSWindowCollectionBehaviorIgnoresCycle;
            cover.opaque=YES;cover.backgroundColor=NSColor.blackColor;cover.hasShadow=NO;
            cover.hidesOnDeactivate=NO;cover.ignoresMouseEvents=YES;
            NSImageView *view=[[NSImageView alloc] initWithFrame:NSMakeRect(0,0,screen.frame.size.width,screen.frame.size.height)];
            view.image=[[NSImage alloc] initWithCGImage:snapshot size:screen.frame.size];view.imageScaling=NSImageScaleAxesIndependently;
            cover.contentView=view;CGImageRelease(snapshot);[prepared addObject:cover];
        }
        covers=prepared.copy;
        for (NSPanel *cover in covers) {[cover orderFrontRegardless];[cover display];}
        [CATransaction flush];pump(.04);return YES;
    }
    return NO;
}
static void endCover(void) {
    for (NSPanel *cover in covers) {[cover orderOut:nil];cover.contentView=nil;}
    covers=nil;
}
// Display discovery conceals only Apple's UI with a live, filtered stream.
// Our controls are excluded from capture and remain above it, fully interactive.
@interface DisplayCover : NSObject <SCStreamOutput>
@property SCStream *stream;
@property NSPanel *panel;
@property AVSampleBufferDisplayLayer *video;
@property BOOL active;
@property NSUInteger frames;
@end
@implementation DisplayCover
- (void)stream:(__unused SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    if (type!=SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sample)) return;
    CFArrayRef attachments=CMSampleBufferGetSampleAttachmentsArray(sample,false);
    if (!attachments || !CFArrayGetCount(attachments)) return;
    NSDictionary *info=(__bridge NSDictionary *)CFArrayGetValueAtIndex(attachments,0);
    if ([info[SCStreamFrameInfoStatus] integerValue]!=SCFrameStatusComplete) return;
    // The renderer is thread-safe; no per-frame main-queue backlog or image copy.
    @synchronized(self) {
        if (!self.active || !self.video.sampleBufferRenderer.readyForMoreMediaData) return;
        CFDictionarySetValue((CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments,0),kCMSampleAttachmentKey_DisplayImmediately,kCFBooleanTrue);
        [self.video.sampleBufferRenderer enqueueSampleBuffer:sample];self.frames++;
    }
}
@end
static DisplayCover *displayCover;
static NSUInteger lastDisplayFrames;
static NSString *displayCoverID;
static void displayCoverNotify(NSString *action,NSString *request) {
    if (!displayCoverID) return;
    NSMutableDictionary *info=@{@"cover":displayCoverID}.mutableCopy;
    if (request) info[@"request"]=request;
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"local.dotfiles.desktop.panels" object:action userInfo:info deliverImmediately:YES];
}
static void endDisplayCover(void) {
    DisplayCover *output=displayCover;
    @synchronized(output) {output.active=NO;lastDisplayFrames=output.frames;}
    [output.panel orderOut:nil];
    [output.stream stopCaptureWithCompletionHandler:^(__unused NSError *error) {}];
    [output.stream removeStreamOutput:output type:SCStreamOutputTypeScreen error:nil];
    displayCoverNotify(@"display-cover-end",nil);
    displayCover=nil;displayCoverID=nil;
}
static BOOL beginDisplayCover(id item,NSString *request) {
    if (@available(macOS 14.4,*)) {
    if (!CGPreflightScreenCaptureAccess()) return NO;
    __block SCShareableContent *content=nil;__block BOOL finished=NO;
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *value,__unused NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{content=value;finished=YES;});
    }];
    CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+2;
    while(!finished && CFAbsoluteTimeGetCurrent()<deadline)pump(.005);
    if(!content)return NO;
    CGPoint position=CGPointZero;id raw=value(item,kAXPositionAttribute);
    if(raw && CFGetTypeID((__bridge CFTypeRef)raw)==AXValueGetTypeID())AXValueGetValue((__bridge AXValueRef)raw,kAXValueCGPointType,&position);
    SCDisplay *display=nil;
    for(SCDisplay *candidate in content.displays)if(CGRectContainsPoint(candidate.frame,position)){display=candidate;break;}
    if(!display)for(SCDisplay *candidate in content.displays)if(candidate.displayID==CGMainDisplayID()){display=candidate;break;}
    NSScreen *screen=nil;for(NSScreen *candidate in NSScreen.screens)if([candidate.deviceDescription[@"NSScreenNumber"] unsignedIntValue]==display.displayID){screen=candidate;break;}
    if(!screen || !display)return NO;
    NSMutableArray *excluded=NSMutableArray.new;
    pid_t nativePID=0,menuPID=0;
    id native=application(@"ControlCenter"),menu=application(@"MenuBarAgent");
    if(native)AXUIElementGetPid((__bridge AXUIElementRef)native,&nativePID);
    if(menu)AXUIElementGetPid((__bridge AXUIElementRef)menu,&menuPID);
    for(SCRunningApplication *app in content.applications)
        if(app.processID==getpid() || app.processID==nativePID || app.processID==menuPID || [app.bundleIdentifier isEqual:@"local.dotfiles.wifi-pane"])[excluded addObject:app];
    SCContentFilter *filter=[[SCContentFilter alloc] initWithDisplay:display excludingApplications:excluded exceptingWindows:@[]];
    SCStreamConfiguration *config=SCStreamConfiguration.new;
    config.width=screen.frame.size.width*screen.backingScaleFactor;config.height=screen.frame.size.height*screen.backingScaleFactor;
    config.minimumFrameInterval=CMTimeMake(1,60);config.queueDepth=3;config.showsCursor=NO;config.capturesAudio=NO;
    DisplayCover *output=DisplayCover.new;output.active=YES;
    output.panel=[[NSPanel alloc] initWithContentRect:screen.frame styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    output.panel.level=CGWindowLevelForKey(kCGPopUpMenuWindowLevelKey)+1;
    DFPanelPrepare(output.panel);
    output.panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorCanJoinAllApplications|NSWindowCollectionBehaviorTransient|NSWindowCollectionBehaviorIgnoresCycle;
    output.panel.ignoresMouseEvents=YES;output.panel.hasShadow=NO;output.panel.opaque=YES;
    output.video=AVSampleBufferDisplayLayer.new;output.video.frame=NSMakeRect(0,0,screen.frame.size.width,screen.frame.size.height);output.video.videoGravity=AVLayerVideoGravityResize;
    NSView *view=[[NSView alloc] initWithFrame:output.video.frame];view.wantsLayer=YES;view.layer=output.video;output.panel.contentView=view;
    output.stream=[[SCStream alloc] initWithFilter:filter configuration:config delegate:nil];
    if(![output.stream addStreamOutput:output type:SCStreamOutputTypeScreen sampleHandlerQueue:dispatch_queue_create("local.dotfiles.display.frames",DISPATCH_QUEUE_SERIAL) error:nil])return NO;
    displayCover=output;displayCoverID=NSUUID.UUID.UUIDString;
    __block BOOL started=NO;__block BOOL failed=NO;
    [output.stream startCaptureWithCompletionHandler:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{started=YES;failed=error!=nil;});}];
    deadline=CFAbsoluteTimeGetCurrent()+2;
    while((!started || !output.video.readyForDisplay) && !failed && CFAbsoluteTimeGetCurrent()<deadline)pump(.005);
    if(!started || failed || !output.video.readyForDisplay){endDisplayCover();return NO;}
    displayCoverNotify(@"display-cover-begin",request);pump(.04);
    [output.panel orderFrontRegardless];[CATransaction flush];return YES;
    }
    return NO;
}
static NSString *stateDirectory(void) {
    NSString *root=NSProcessInfo.processInfo.environment[@"XDG_STATE_HOME"];
    if (!root.length) root=[NSHomeDirectory() stringByAppendingPathComponent:@".local/state"];
    return [root stringByAppendingPathComponent:@"dotfiles/desktop"];
}
static NSDictionary *readJSON(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path];
    id result=data.length<131072 ? [NSJSONSerialization JSONObjectWithData:data ?: NSData.data options:0 error:nil] : nil;
    return [result isKindOfClass:NSDictionary.class] ? result : @{};
}
static int runPanelUI(BOOL workspaceMode) {
    NSString *directory=stateDirectory(),*bar=[directory stringByAppendingPathComponent:@"bar"];
    [NSFileManager.defaultManager createDirectoryAtPath:bar withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    int lock=open([[bar stringByAppendingPathComponent:@"panel-ui.lock"] fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if (lock<0) return 1;
    // A running instance can render the newer request without opening a
    // duplicate window. If it is exiting, acquire its lock and replace it.
    CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+2;
    while (flock(lock,LOCK_EX|LOCK_NB)!=0) {
        if (workspaceMode) [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"local.dotfiles.desktop.workspace" object:@"show" userInfo:nil deliverImmediately:YES];
        else DFControlsNotify(@"show");pump(.05);
        NSDictionary *status=readJSON([bar stringByAppendingPathComponent:workspaceMode ? @"workspace-status.json" : @"panel-ui-status.json"]);
        NSDictionary *document=readJSON([bar stringByAppendingPathComponent:workspaceMode ? @"workspace-request.json" : @"native-panel.json"]);
        if ([status[@"request"] isEqual:document[@"request"]] && [status[@"visible"] boolValue]
            && NSDate.date.timeIntervalSince1970-[status[@"updated"] doubleValue]<1) {close(lock);return 0;}
        if (CFAbsoluteTimeGetCurrent()>deadline) {close(lock);return 1;}
    }
    alarm(0);
    DFControlsAppearance([directory stringByAppendingPathComponent:@"appearance.json"]);
    DFControlsInitialize(directory);DFWorkspaceInitialize(directory);
    DFControlsSetWillShow(^{DFWorkspaceHide();});
    if (workspaceMode) DFWorkspaceShow();else DFControlsNotify(@"show");
    __block double lastVisible=NSProcessInfo.processInfo.systemUptime;
    __block BOOL seen=NO;
    __block double lastReport=0;
    __block double nextAppearance=0;
    __block NSData *lastAppearance=nil;
    __block BOOL lastControlVisible=NO,lastWorkspaceVisible=NO;
    id observer=[NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){DFControlsSpaceChanged();DFWorkspaceHide();}];
    NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:.033 repeats:YES block:^(__unused NSTimer *timer) {
        double now=NSProcessInfo.processInfo.systemUptime;
        if (now>=nextAppearance) {
            nextAppearance=now+.5;
            NSString *path=[directory stringByAppendingPathComponent:@"appearance.json"];
            NSData *appearance=[NSData dataWithContentsOfFile:path];
            if (![appearance isEqual:lastAppearance]) {lastAppearance=appearance;DFControlsAppearance(path);DFWorkspaceRefreshAppearance();}
        }
        DFControlsTick(now,NSEvent.mouseLocation);
        DFWorkspaceTick(now,NSEvent.mouseLocation);
        NSMutableDictionary *status=DFControlsStatus().mutableCopy;
        status[@"updated"]=@(NSDate.date.timeIntervalSince1970);status[@"pid"]=@(getpid());status[@"healthy"]=@YES;
        BOOL controlVisible=[status[@"visible"] boolValue],workspaceVisible=[DFWorkspaceStatus()[@"visible"] boolValue];
        if (now-lastReport>=.2 || lastControlVisible!=controlVisible || lastWorkspaceVisible!=workspaceVisible) {
        lastControlVisible=controlVisible;lastWorkspaceVisible=workspaceVisible;
        lastReport=now;
        NSData *data=[NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
        NSString *temporary=[bar stringByAppendingPathComponent:[@".panel-status-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        int fd=open(temporary.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);
        if (fd>=0) {BOOL written=write(fd,data.bytes,data.length)==(ssize_t)data.length;close(fd);
            if (written) rename(temporary.fileSystemRepresentation,[[bar stringByAppendingPathComponent:@"panel-ui-status.json"] fileSystemRepresentation]);unlink(temporary.fileSystemRepresentation);}
        NSMutableDictionary *workspace=DFWorkspaceStatus().mutableCopy;
        workspace[@"updated"]=status[@"updated"];workspace[@"pid"]=@(getpid());
        NSData *workspaceData=[NSJSONSerialization dataWithJSONObject:workspace options:0 error:nil];
        NSString *workspaceTemporary=[bar stringByAppendingPathComponent:[@".workspace-status-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        int workspaceFD=open(workspaceTemporary.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);
        if (workspaceFD>=0) {BOOL written=write(workspaceFD,workspaceData.bytes,workspaceData.length)==(ssize_t)workspaceData.length;close(workspaceFD);
            if (written) rename(workspaceTemporary.fileSystemRepresentation,[[bar stringByAppendingPathComponent:@"workspace-status.json"] fileSystemRepresentation]);unlink(workspaceTemporary.fileSystemRepresentation);}
        }
        if ([status[@"visible"] boolValue] || [DFWorkspaceStatus()[@"visible"] boolValue]) {seen=YES;lastVisible=now;}
        if (now-lastVisible>(seen ? .4 : 2)) {[NSApp stop:nil];[NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];}
    }];
    [NSApp run];[timer invalidate];[NSWorkspace.sharedWorkspace.notificationCenter removeObserver:observer];
    DFControlsHide();DFWorkspaceHide();close(lock);return 0;
}
static NSDictionary *accessStatus(void) {
    BOOL supported=NO;if (@available(macOS 15.2,*)) supported=NSScreen.screens.count>0 && NSScreen.screens.count<=8;
    return @{@"accessibility":@((BOOL)AXIsProcessTrusted()),@"screen_capture":@((BOOL)CGPreflightScreenCaptureAccess()),@"supported":@(supported)};
}
static BOOL nativeVisible(pid_t owner) {
    NSArray *info=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly,kCGNullWindowID));
    for (NSDictionary *window in info) {
        if ([window[(id)kCGWindowOwnerPID] intValue]!=owner || [window[(id)kCGWindowAlpha] doubleValue]<=0) continue;
        CGRect bounds;CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)window[(id)kCGWindowBounds],&bounds);
        if (bounds.size.width>100 && CGRectIntersectsRect(bounds,CGDisplayBounds(CGMainDisplayID()))) return YES;
    }
    return NO;
}
static id disclosure(id root, NSUInteger depth, NSUInteger *budget) {
    if (!*budget || depth>8) return nil;--*budget;
    if ([value(root,kAXRoleAttribute) isEqual:@"AXDisclosureTriangle"]) return root;
    NSString *role=value(root,kAXRoleAttribute);
    if ([@[@"AXTextField",@"AXTextArea",@"AXSecureTextField"] containsObject:role]) return nil;
    for (id child in children(root)) {id result=disclosure(child,depth+1,budget);if(result)return result;}
    return nil;
}
static BOOL expandPanel(id panel, BOOL expanded) {
    NSUInteger budget=256;id target=disclosure(panel,0,&budget);
    if (!target || [value(target,kAXValueAttribute) boolValue]==expanded) return YES;
    if (AXUIElementPerformAction((__bridge AXUIElementRef)target,kAXPressAction)!=kAXErrorSuccess) return NO;
    CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+1.5;
    while (CFAbsoluteTimeGetCurrent()<deadline) {
        id observed=value(target,kAXValueAttribute);
        if (observed && [observed boolValue]==expanded) {pump(.06);return YES;}
        pump(.02);
    }
    return NO;
}
static NSDictionary *query(NSDictionary *selector, BOOL expanded) {
    NSDictionary *access=accessStatus();
    if (![access[@"accessibility"] boolValue] || ![access[@"screen_capture"] boolValue] || ![access[@"supported"] boolValue]) return @{@"error":@"access_unavailable"};
    id center=application(@"ControlCenter"),menu=application(@"MenuBarAgent");
    if (!center || windows(center).count) return @{@"error":@"native_panel_busy"};
    NSUInteger budget=160;
    id item=find(menu,@"com.apple.menuextra.wifi",nil,0,&budget);
    if (!item) { budget=160;item=find(center,@"com.apple.menuextra.wifi",nil,0,&budget); }
    if (!item || !beginCover()) return @{@"error":@"cover_unavailable"};
    NSString *inputRequest=nil;
    if (selector || expanded) {
        NSString *bar=[stateDirectory() stringByAppendingPathComponent:@"bar"];
        NSDictionary *document=readJSON([bar stringByAppendingPathComponent:@"native-panel.json"]);
        NSDictionary *status=readJSON([bar stringByAppendingPathComponent:@"panel-ui-status.json"]);
        if ([document[@"name"] isEqual:@"wifi"] && [status[@"visible"] boolValue]
            && [document[@"request"] isEqual:status[@"request"]]
            && NSDate.date.timeIntervalSince1970-[status[@"updated"] doubleValue]<1) {
            inputRequest=document[@"request"];
            DFControlsNotifyRequest(@"passthrough",inputRequest);
            CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+.6;
            do {pump(.02);status=readJSON([bar stringByAppendingPathComponent:@"panel-ui-status.json"]);}
            while (![status[@"input_passthrough"] boolValue] && CFAbsoluteTimeGetCurrent()<deadline);
            if (![status[@"input_passthrough"] boolValue]) {
                DFControlsNotifyRequest(@"resume",inputRequest);pump(.03);endCover();
                return @{@"error":@"input_unavailable"};
            }
        }
    }
    id panel=nil;BOOL opened=NO,handoff=NO;NSString *failure=nil;
    NSMutableArray *rows=NSMutableArray.new;
    @try {
        opened=AXUIElementPerformAction((__bridge AXUIElementRef)item,kAXPressAction)==kAXErrorSuccess;
        CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+2;
        while (opened && !panel && CFAbsoluteTimeGetCurrent()<deadline) {
            for (id window in windows(center)) {
                budget=160;if (find(window,@"wifi-header",nil,0,&budget)) {panel=window;break;}
            }
            if (!panel) pump(.01);
        }
        if (!panel) failure=@"native_panel_unavailable";
        if (panel && ![selector[@"kind"] isEqual:@"power"] && !expandPanel(panel,expanded)) failure=@"action_no_change";
        if (panel && selector && !failure) {
            budget=256;id target=findAction(panel,selector,0,&budget);
            if (!target) failure=@"option_changed";
            else if (AXUIElementPerformAction((__bridge AXUIElementRef)target,kAXPressAction)!=kAXErrorSuccess) failure=@"action_failed";
            else {
                // Native disclosure/radio state is asynchronous. Wait for
                // observable state rather than returning a premature snapshot.
                if ([@[@"disclosure",@"power"] containsObject:selector[@"kind"]]) {
                    CFAbsoluteTime changedDeadline=CFAbsoluteTimeGetCurrent()+1.5;
                    while (CFAbsoluteTimeGetCurrent()<changedDeadline) {
                        id observed=value(target,kAXValueAttribute);
                        if (observed && [observed boolValue]!=[selector[@"selected"] boolValue]) break;
                        pump(.02);
                    }
                    id after=value(target,kAXValueAttribute);
                    if (!after || [after boolValue]==[selector[@"selected"] boolValue]) failure=@"action_no_change";
                    else pump(.06);
                } else pump(.4);
                handoff=[selector[@"kind"] isEqual:@"button"];
                if ([selector[@"kind"] isEqual:@"network"]) {
                    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications)
                        if ([app.executableURL.lastPathComponent isEqual:@"WiFiAgent"] && nativeVisible(app.processIdentifier)) handoff=YES;
                }
                for (id window in windows(center)) if ([value(window,kAXModalAttribute) boolValue]) handoff=YES;
            }
        }
        if (panel && !failure) {budget=256;collect(panel,rows,0,&budget);}
    } @finally {
        // Closing must finish before the cover is removed, not just before
        // AXPress returns. Otherwise the native closing animation can flash.
        if (opened && panel && !handoff) {
            budget=160;
            if (find(panel,@"wifi-header",nil,0,&budget)) AXUIElementPerformAction((__bridge AXUIElementRef)item,kAXPressAction);
        }
        pid_t owner=0;AXUIElementGetPid((__bridge AXUIElementRef)center,&owner);
        CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+1.5;
        while (!handoff && owner && nativeVisible(owner) && CFAbsoluteTimeGetCurrent()<deadline) pump(.01);
        DFControlsNotifyRequest(@"resume",inputRequest);pump(.03);
        endCover();
    }
    if (failure) return @{@"error":failure};
    return @{@"sampled":@(NSDate.date.timeIntervalSince1970),@"rows":rows,@"handoff":@(handoff)};
}
// Display discovery uses the same signed, memory-only native UI adapter as
// Wi-Fi. Only observed native device/toggle rows may become literal actions.
static NSDictionary *displayDescriptor(id element, NSString *page) {
    NSString *role=value(element,kAXRoleAttribute),*identifier=value(element,kAXIdentifierAttribute);
    if (![identifier isKindOfClass:NSString.class]) identifier=@"";
    NSString *label=nil,*kind=nil;
    NSDictionary *toggles=@{@"display-setting-dark-mode":@"Dark Mode",@"display-setting-night-shift":@"Night Shift",@"display-setting-true-tone":@"True Tone"};
    if ([page isEqual:@"display"] && [role isEqual:@"AXCheckBox"] && toggles[identifier]) {kind=@"toggle";label=toggles[identifier];}
    else if ([page isEqual:@"mirroring"] && [role isEqual:@"AXCheckBox"] && [identifier hasPrefix:@"screen-mirroring-device-"]) {kind=@"device";label=text(element);}
    else if ([page isEqual:@"mirroring"] && [role isEqual:@"AXButton"] && [identifier isEqual:@"screen-mirroring-preferences"]) {kind=@"settings";label=text(element);}
    if (!kind || !safeText(label,512)) return nil;
    return @{@"kind":kind,@"text":label,@"page":page,@"role":role,@"identifier":identifier,
             @"selected":@((BOOL)([value(element,kAXValueAttribute) integerValue]==1)),@"enabled":@((BOOL)(![value(element,kAXEnabledAttribute) isEqual:@NO]))};
}
static void displayCollect(id root,NSString *page,NSMutableArray *rows,NSUInteger depth,NSUInteger *budget) {
    if (!*budget || depth>8 || rows.count>=32) return;--*budget;
    NSString *role=value(root,kAXRoleAttribute);
    if ([@[@"AXTextField",@"AXTextArea",@"AXSecureTextField"] containsObject:role]) return;
    NSDictionary *row=displayDescriptor(root,page);if(row){[rows addObject:row];return;}
    for(id child in children(root))displayCollect(child,page,rows,depth+1,budget);
}
static id displayFindAction(id root,NSDictionary *selector,NSUInteger depth,NSUInteger *budget) {
    if(!*budget || depth>8)return nil;--*budget;
    if([@[@"AXTextField",@"AXTextArea",@"AXSecureTextField"] containsObject:value(root,kAXRoleAttribute)])return nil;
    NSDictionary *row=displayDescriptor(root,selector[@"page"]);
    if(row){BOOL same=[row[@"enabled"] boolValue];for(NSString *key in @[@"kind",@"text",@"page",@"role",@"identifier",@"selected"])if(![row[key] isEqual:selector[key]])same=NO;if(same)return root;}
    for(id child in children(root)){id found=displayFindAction(child,selector,depth+1,budget);if(found)return found;}
    return nil;
}
static id displayWindowItem(id center,NSString *identifier) {
    // Never spend the bounded traversal budget in Control Center's unrelated
    // menu-bar proxy before reaching the actual popup window.
    for(id window in windows(center)){NSUInteger budget=256;id found=find(window,identifier,nil,0,&budget);if(found)return found;}
    return nil;
}
static NSString *displayFailureStage;
static id displayPage(id center,id item,NSString *page) {
    displayFailureStage=@"overview_action";
    if(AXUIElementPerformAction((__bridge AXUIElementRef)item,kAXPressAction)!=kAXErrorSuccess)return nil;
    pump(.3);displayFailureStage=@"module_lookup";
    NSString *identifier=[page isEqual:@"display"] ? @"controlcenter-display" : @"controlcenter-screen-mirroring";
    id module=nil;CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+1.5;
    do {module=displayWindowItem(center,identifier);if(!module)pump(.01);}while(!module && CFAbsoluteTimeGetCurrent()<deadline);
    if(!module)return nil;
    NSString *action=(id)kAXPressAction;
    {
        CFArrayRef raw=NULL;
        if(AXUIElementCopyActionNames((__bridge AXUIElementRef)module,&raw)==kAXErrorSuccess){
            NSArray *actions=CFBridgingRelease(raw);
            for(NSString *candidate in actions)if([candidate hasPrefix:@"Name:show details\n"]){action=candidate;break;}
        }
    }
    displayFailureStage=@"module_action";
    if(AXUIElementPerformAction((__bridge AXUIElementRef)module,(__bridge CFStringRef)action)!=kAXErrorSuccess)return nil;
    pump(.2);displayFailureStage=@"detail_lookup";
    NSString *marker=[page isEqual:@"display"] ? @"display-setting-dark-mode" : @"screen-mirroring-preferences";
    deadline=CFAbsoluteTimeGetCurrent()+2;
    do {for(id window in windows(center)){NSUInteger budget=256;if(find(window,marker,nil,0,&budget))return window;}pump(.01);}while(CFAbsoluteTimeGetCurrent()<deadline);
    return nil;
}
static void displayClose(id center,__unused id item) {
    // Dismiss only known pages opened by this transaction. Escape targets the
    // ControlCenter process directly, never the foreground application.
    for(NSUInteger attempt=0;attempt<3 && windows(center).count;attempt++){
        BOOL owned=NO;
        for(NSString *marker in @[@"controlcenter-display",@"display-setting-dark-mode",@"screen-mirroring-header"]){
            if(displayWindowItem(center,marker)){owned=YES;break;}
        }
        if(!owned)break;
        pid_t target=0;AXUIElementGetPid((__bridge AXUIElementRef)center,&target);
        if(!target)break;
        CGEventRef down=CGEventCreateKeyboardEvent(NULL,53,true),up=CGEventCreateKeyboardEvent(NULL,53,false);
        if(down && up){CGEventPostToPid(target,down);CGEventPostToPid(target,up);}
        if(down)CFRelease(down);if(up)CFRelease(up);
        pump(.25);
    }
    pid_t owner=0;AXUIElementGetPid((__bridge AXUIElementRef)center,&owner);
    CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+1;
    while(owner && nativeVisible(owner) && CFAbsoluteTimeGetCurrent()<deadline)pump(.01);
    pump(.08);
}
static NSArray *connectedDisplays(void) {
    CGDirectDisplayID ids[32];uint32_t count=0;NSMutableArray *result=NSMutableArray.new;
    if(CGGetOnlineDisplayList(32,ids,&count)!=kCGErrorSuccess)return result;
    for(uint32_t i=0;i<count && i<32;i++){
        CGDirectDisplayID display=ids[i];if(!CGDisplayIsActive(display) && !CGDisplayIsInMirrorSet(display))continue;
        NSString *name=CGDisplayIsBuiltin(display) ? @"Built-in display" : @"External display";
        for(NSScreen *screen in NSScreen.screens)if([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue]==display)name=screen.localizedName;
        CGDisplayModeRef mode=CGDisplayCopyDisplayMode(display);
        NSString *modeName=CGDisplayMirrorsDisplay(display)!=kCGNullDirectDisplay ? @"Mirroring" : CGDisplayIsInMirrorSet(display) ? @"Mirror source" : CGDisplayIsMain(display) ? @"Main display" : @"Extended display";
        NSMutableDictionary *row=@{@"name":name,@"mode":modeName,@"width":@(CGDisplayPixelsWide(display)),@"height":@(CGDisplayPixelsHigh(display))}.mutableCopy;
        if(mode){double refresh=CGDisplayModeGetRefreshRate(mode);if(isfinite(refresh)&&refresh>0)row[@"refresh"]=@(refresh);CGDisplayModeRelease(mode);}
        [result addObject:row];if(result.count==8)break;
    }
    return result;
}
static NSDictionary *displayQuery(NSDictionary *selector) {
    NSDictionary *access=accessStatus();
    if(![access[@"accessibility"] boolValue]||![access[@"screen_capture"] boolValue]||![access[@"supported"] boolValue])return @{@"error":@"access_unavailable"};
    id center=application(@"ControlCenter"),menu=application(@"MenuBarAgent");
    if(!center || windows(center).count)return @{@"error":@"native_panel_busy"};
    NSUInteger budget=256;id item=find(menu,@"com.apple.menuextra.controlcenter",nil,0,&budget);
    if(!item){budget=256;item=find(center,@"com.apple.menuextra.controlcenter",nil,0,&budget);}
    NSString *bar=[stateDirectory() stringByAppendingPathComponent:@"bar"];
    NSDictionary *current=readJSON([bar stringByAppendingPathComponent:@"native-panel.json"]);
    NSString *request=[current[@"name"] isEqual:@"brightness"] ? current[@"request"] : nil;
    if(!item || !beginDisplayCover(item,request))return @{@"error":@"cover_unavailable"};
    if(!DFNativeUIBegin(stateDirectory(),displayCoverID)){endDisplayCover();return @{@"error":@"native_panel_busy"};}
    NSMutableArray *rows=NSMutableArray.new;NSString *failure=nil,*inputRequest=nil;BOOL handoff=NO;
    @try {
        if(selector){
            NSString *bar=[stateDirectory() stringByAppendingPathComponent:@"bar"];
            NSDictionary *document=readJSON([bar stringByAppendingPathComponent:@"native-panel.json"]),*status=readJSON([bar stringByAppendingPathComponent:@"panel-ui-status.json"]);
            if([document[@"name"] isEqual:@"brightness"] && [status[@"visible"] boolValue] && [document[@"request"] isEqual:status[@"request"]] && NSDate.date.timeIntervalSince1970-[status[@"updated"] doubleValue]<1){
                inputRequest=document[@"request"];DFControlsNotifyRequest(@"passthrough",inputRequest);
                CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+.6;
                do{pump(.02);status=readJSON([bar stringByAppendingPathComponent:@"panel-ui-status.json"]);}while(![status[@"input_passthrough"] boolValue] && CFAbsoluteTimeGetCurrent()<deadline);
                if(![status[@"input_passthrough"] boolValue])failure=@"input_unavailable";
            }
            id panel=failure ? nil : displayPage(center,item,selector[@"page"]);
            if(!panel && !failure)failure=@"native_panel_unavailable";
            if(panel){budget=256;id target=displayFindAction(panel,selector,0,&budget);
                if(!target)failure=@"option_changed";
                else if(AXUIElementPerformAction((__bridge AXUIElementRef)target,kAXPressAction)!=kAXErrorSuccess)failure=@"action_failed";
                else if([selector[@"kind"] isEqual:@"toggle"]){
                    CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+1.5;
                    while(CFAbsoluteTimeGetCurrent()<deadline && [value(target,kAXValueAttribute) boolValue]==[selector[@"selected"] boolValue])pump(.02);
                    if([value(target,kAXValueAttribute) boolValue]==[selector[@"selected"] boolValue])failure=@"action_no_change";
                }else{
                    // macOS owns pairing, permission and content/mirror/extend
                    // confirmation. Never dismiss or cover a required chooser.
                    handoff=YES;pump(.3);
                }
            }
            if(!handoff)displayClose(center,item);
        }
        if(!failure && !handoff){
            for(NSString *page in @[@"mirroring",@"display"]){
                id panel=displayPage(center,item,page);
                if(!panel){failure=[page isEqual:@"display"] ? @"native_display_unavailable" : @"native_mirroring_unavailable";displayClose(center,item);continue;}
                // The footer is a real ready control; the header can precede
                // asynchronously populated choices by several frames.
                if([page isEqual:@"mirroring"])pump(.5);
                NSUInteger before=rows.count;budget=256;displayCollect(panel,page,rows,0,&budget);
                BOOL ready=NO;for(NSUInteger i=before;i<rows.count;i++)if([rows[i][@"kind"] isEqual:[page isEqual:@"mirroring"] ? @"settings" : @"toggle"]){ready=YES;break;}
                if(!ready)failure=@"native_panel_unavailable";
                displayClose(center,item);
                if(windows(center).count){failure=@"native_panel_busy";break;}
            }
        }
    }@finally{
        if(!handoff)displayClose(center,item);
        DFControlsNotifyRequest(@"resume",inputRequest);pump(.03);DFNativeUIEnd(stateDirectory(),displayCoverID);endDisplayCover();
    }
    if(failure && !rows.count)return @{@"error":failure,@"stage":displayFailureStage ?: @"action"};
    return @{@"sampled":@(NSDate.date.timeIntervalSince1970),@"rows":rows,@"screens":connectedDisplays(),@"handoff":@(handoff),@"partial":@((BOOL)(failure!=nil)),@"presentation_frames":@(lastDisplayFrames)};
}

int main(int argc,const char **argv) { @autoreleasepool {
    [NSApplication.sharedApplication setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSString *mode=argc>1 ? [NSString stringWithUTF8String:argv[1]] : @"--status";
    BOOL expanded=argc>2 && strcmp(argv[argc-1],"--expanded")==0;
    if ([mode isEqual:@"--ui"]) return runPanelUI(NO);
    if ([mode isEqual:@"--workspace-ui"]) return runPanelUI(YES);
    if ([mode isEqual:@"--workspace-hide"]) {DFWorkspaceCancelAll(stateDirectory());return 0;}
    if ([mode isEqual:@"--workspace-self-test"]) return DFWorkspaceSelfTest();
    if ([mode isEqual:@"--ui-hide"]) {DFControlsNotify(@"hide");return 0;}
    alarm([mode isEqual:@"--request-access"] ? 90 : 12);
    NSDictionary *result=nil;
    if ([mode isEqual:@"--status"]) result=accessStatus();
    else if ([mode isEqual:@"--request-access"]) {
        // Stage the OS dialogs. An unconfirmed Accessibility request must not
        // be followed immediately by a second protected permission request.
        if (!AXIsProcessTrusted())
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
        else if (!CGPreflightScreenCaptureAccess()) CGRequestScreenCaptureAccess();
        result=accessStatus();
    } else if ([mode isEqual:@"--display-snapshot"] && argc==2) result=displayQuery(nil);
    else if ([mode isEqual:@"--display-action"] && argc==3 && strlen(argv[2])<=4096) {
        NSData *data=[[NSString stringWithUTF8String:argv[2]] dataUsingEncoding:NSUTF8StringEncoding];
        id selector=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        BOOL valid=[selector isKindOfClass:NSDictionary.class];
        if(valid)valid=[@[@"toggle",@"device",@"settings"] containsObject:selector[@"kind"]]
            && [@[@"display",@"mirroring"] containsObject:selector[@"page"]] && safeText(selector[@"text"],512)
            && [selector[@"identifier"] isKindOfClass:NSString.class] && [selector[@"role"] isKindOfClass:NSString.class]
            && [selector[@"selected"] isKindOfClass:NSNumber.class];
        result=valid ? displayQuery(selector) : @{@"error":@"invalid_action"};
    }
    else if ([mode isEqual:@"--snapshot"] && (argc==2 || (argc==3 && expanded))) result=query(nil,expanded);
    else if ([mode isEqual:@"--action"] && (argc==3 || (argc==4 && expanded)) && strlen(argv[2])<=4096) {
        NSData *data=[[NSString stringWithUTF8String:argv[2]] dataUsingEncoding:NSUTF8StringEncoding];
        id selector=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        BOOL valid=[selector isKindOfClass:NSDictionary.class];
        if (valid) valid=[@[@"power",@"network",@"disclosure",@"button"] containsObject:selector[@"kind"]]
            && safeText(selector[@"text"],512) && [selector[@"role"] isKindOfClass:NSString.class]
            && [selector[@"identifier"] isKindOfClass:NSString.class] && [selector[@"selected"] isKindOfClass:NSNumber.class];
        result=valid ? query(selector,expanded) : @{@"error":@"invalid_action"};
    } else result=@{@"error":@"invalid_mode"};
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);
    return result[@"error"] ? 1 : 0;
} }
