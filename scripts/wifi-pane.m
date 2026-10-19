#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <QuartzCore/QuartzCore.h>
#import "control-panel.h"
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
static NSPanel *cover;
static BOOL beginCover(void) {
    if (!CGPreflightScreenCaptureAccess() || NSScreen.screens.count!=1) return NO;
    if (@available(macOS 15.2,*)) {
        __block CGImageRef snapshot=NULL; __block BOOL complete=NO,abandoned=NO;
        [SCScreenshotManager captureImageInRect:CGDisplayBounds(CGMainDisplayID()) completionHandler:^(CGImageRef image,__unused NSError *error) {
            CGImageRef retained=image ? CGImageRetain(image) : NULL;
            dispatch_async(dispatch_get_main_queue(),^{if (abandoned) {if (retained) CGImageRelease(retained);return;} snapshot=retained;complete=YES;});
        }];
        CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+2;
        while (!complete && CFAbsoluteTimeGetCurrent()<deadline) pump(.005);
        if (!snapshot) {abandoned=YES;return NO;}
        NSScreen *screen=NSScreen.screens.firstObject;
        cover=[[NSPanel alloc] initWithContentRect:screen.frame styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        cover.level=NSScreenSaverWindowLevel; cover.animationBehavior=NSWindowAnimationBehaviorNone;
        cover.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorCanJoinAllApplications|NSWindowCollectionBehaviorTransient|NSWindowCollectionBehaviorIgnoresCycle;
        cover.opaque=YES;cover.backgroundColor=NSColor.blackColor;cover.hasShadow=NO;
        cover.hidesOnDeactivate=NO;cover.ignoresMouseEvents=YES;
        NSImageView *view=[[NSImageView alloc] initWithFrame:NSMakeRect(0,0,screen.frame.size.width,screen.frame.size.height)];
        view.image=[[NSImage alloc] initWithCGImage:snapshot size:screen.frame.size];view.imageScaling=NSImageScaleAxesIndependently;
        cover.contentView=view;CGImageRelease(snapshot);
        [cover orderFrontRegardless];[cover display];[CATransaction flush];pump(.04);
        return cover.visible;
    }
    return NO;
}
static void endCover(void) {
    [cover orderOut:nil];cover.contentView=nil;cover=nil;
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
static int runPanelUI(void) {
    NSString *directory=stateDirectory(),*bar=[directory stringByAppendingPathComponent:@"bar"];
    [NSFileManager.defaultManager createDirectoryAtPath:bar withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    int lock=open([[bar stringByAppendingPathComponent:@"panel-ui.lock"] fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if (lock<0) return 1;
    // A running instance can render the newer request without opening a
    // duplicate window. If it is exiting, acquire its lock and replace it.
    CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+2;
    while (flock(lock,LOCK_EX|LOCK_NB)!=0) {
        DFControlsNotify(@"show");pump(.05);
        NSDictionary *status=readJSON([bar stringByAppendingPathComponent:@"panel-ui-status.json"]);
        NSDictionary *document=readJSON([bar stringByAppendingPathComponent:@"native-panel.json"]);
        if ([status[@"request"] isEqual:document[@"request"]] && [status[@"visible"] boolValue]
            && NSDate.date.timeIntervalSince1970-[status[@"updated"] doubleValue]<1) {close(lock);return 0;}
        if (CFAbsoluteTimeGetCurrent()>deadline) {close(lock);return 1;}
    }
    alarm(0);
    DFControlsAppearance([directory stringByAppendingPathComponent:@"appearance.json"]);
    DFControlsInitialize(directory);DFControlsNotify(@"show");
    __block double lastVisible=NSProcessInfo.processInfo.systemUptime;
    __block BOOL seen=NO;
    __block double lastReport=0;
    id observer=[NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){DFControlsHide();}];
    NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:.033 repeats:YES block:^(__unused NSTimer *timer) {
        double now=NSProcessInfo.processInfo.systemUptime;
        DFControlsTick(now,NSEvent.mouseLocation);
        NSMutableDictionary *status=DFControlsStatus().mutableCopy;
        status[@"updated"]=@(NSDate.date.timeIntervalSince1970);status[@"pid"]=@(getpid());status[@"healthy"]=@YES;
        if (now-lastReport>=.2 || ![status[@"visible"] boolValue]) {
        lastReport=now;
        NSData *data=[NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
        NSString *temporary=[bar stringByAppendingPathComponent:[@".panel-status-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        int fd=open(temporary.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);
        if (fd>=0) {BOOL written=write(fd,data.bytes,data.length)==(ssize_t)data.length;close(fd);
            if (written) rename(temporary.fileSystemRepresentation,[[bar stringByAppendingPathComponent:@"panel-ui-status.json"] fileSystemRepresentation]);unlink(temporary.fileSystemRepresentation);}
        }
        if ([status[@"visible"] boolValue]) {seen=YES;lastVisible=now;}
        if (now-lastVisible>(seen ? .4 : 2)) {[NSApp stop:nil];[NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];}
    }];
    [NSApp run];[timer invalidate];[NSWorkspace.sharedWorkspace.notificationCenter removeObserver:observer];
    DFControlsHide();close(lock);return 0;
}
static NSDictionary *accessStatus(void) {
    BOOL supported=NO;if (@available(macOS 15.2,*)) supported=NSScreen.screens.count==1;
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
int main(int argc,const char **argv) { @autoreleasepool {
    [NSApplication.sharedApplication setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSString *mode=argc>1 ? [NSString stringWithUTF8String:argv[1]] : @"--status";
    BOOL expanded=argc>2 && strcmp(argv[argc-1],"--expanded")==0;
    if ([mode isEqual:@"--ui"]) return runPanelUI();
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
    } else if ([mode isEqual:@"--snapshot"] && (argc==2 || (argc==3 && expanded))) result=query(nil,expanded);
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
