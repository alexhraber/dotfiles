#import "app-menu.h"
#import "control-panel.h"
#import "calendar-panel.h"
#import "panel-style.h"
#import "panel-request.h"
#import <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>

// AX objects and all menu titles stay in memory. Read/press the owning app's
// real menu; never emulate a menu command with a keystroke or shell snippet.
static NSString *const menuNotification=@"local.dotfiles.desktop.app-menu";
static NSString *menuBarTool;
static dispatch_queue_t menuQueue;
static NSArray *topMenus=@[];
static pid_t menuPID;
static BOOL menuReading;
static BOOL menuWasVisible;
static NSString *lastMenuApplication;
static pid_t lastMenuPID;
static double nextMenuRead;
static NSUInteger menuRevision;
static NSRect menuAnchor;
static NSMutableArray<NSPanel *> *menuPanels;
static NSInteger openMenuIndex=-1;
static id menuMouseMonitor, menuKeyMonitor, menuLocalMonitor;

typedef NS_ENUM(NSInteger, AppleAction) {
    AppleAbout=1, AppleSettings, AppleStore, AppleInformation, AppleForceQuit,
    AppleSleep, AppleRestart, AppleShutdown, AppleLock, AppleLogout, AppleLauncher
};
static NSString *appleBundle(NSInteger action) {
    return @{@(AppleAbout):@"com.apple.AboutThisMacLauncher", @(AppleSettings):@"com.apple.systempreferences",
             @(AppleStore):@"com.apple.AppStore", @(AppleInformation):@"com.apple.SystemProfiler"}[@(action)];
}
static AEEventID applePowerEvent(NSInteger action) {
    switch (action) {
        case AppleSleep: return kAESleep;
        case AppleRestart: return kAEShowRestartDialog;
        case AppleShutdown: return kAEShowShutdownDialog;
        case AppleLogout: return kAELogOut;
        default: return 0;
    }
}
static int (*screenLock(void))(void) {
    static void *library; static int (*function)(void); static dispatch_once_t once;
    dispatch_once(&once,^{
        library=dlopen("/System/Library/PrivateFrameworks/login.framework/login",RTLD_LAZY|RTLD_LOCAL);
        if (library) function=dlsym(library,"SACLockScreenImmediate");
    });
    return function;
}
static NSURL *appleApplication(NSInteger action) {
    NSString *bundle=appleBundle(action);
    NSURL *url=bundle ? [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bundle] : nil;
    // About This Mac can be absent from the LaunchServices index until first use.
    if (!url && action==AppleAbout) {
        NSString *path=@"/System/Library/CoreServices/Applications/About This Mac.app";
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) url=[NSURL fileURLWithPath:path];
    }
    return url;
}
static void appleError(NSString *message) {
    NSAlert *alert=[NSAlert new]; alert.messageText=message; [alert addButtonWithTitle:@"OK"];
    alert.window.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;
    [NSApp activate]; [alert runModal];
}
static void forceQuitChooser(void) {
    NSMutableArray<NSRunningApplication *> *apps=[NSMutableArray array];
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications)
        if (app.activationPolicy==NSApplicationActivationPolicyRegular && !app.terminated
            && app.processIdentifier!=NSProcessInfo.processInfo.processIdentifier) [apps addObject:app];
    [apps sortUsingComparator:^NSComparisonResult(NSRunningApplication *a, NSRunningApplication *b) {
        return [a.localizedName ?: @"" localizedCaseInsensitiveCompare:b.localizedName ?: @""];
    }];
    if (!apps.count) return;
    NSAlert *alert=[NSAlert new]; alert.messageText=@"Force Quit Applications";
    alert.informativeText=@"Choose an app. Unsaved changes in that app may be lost.";
    [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Force Quit"];
    NSPopUpButton *picker=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,300,28) pullsDown:NO];
    for (NSRunningApplication *app in apps) {
        [picker addItemWithTitle:app.localizedName ?: @"Application"];
        NSImage *icon=app.icon.copy; icon.size=NSMakeSize(16,16); picker.lastItem.image=icon;
    }
    alert.accessoryView=picker;
    alert.window.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;
    [NSApp activate];
    if ([alert runModal]!=NSAlertSecondButtonReturn) return;
    NSInteger index=picker.indexOfSelectedItem;
    if (index<0 || index>=(NSInteger)apps.count) return;
    NSRunningApplication *app=apps[index];
    if (!app.terminated && ![app forceTerminate]) appleError(@"This app could not be force quit.");
}
static void runAppleAction(NSInteger action) {
    if (action==AppleLauncher) {
        NSString *state=NSProcessInfo.processInfo.environment[@"XDG_STATE_HOME"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@".local/state"];
        NSPoint pointer=NSEvent.mouseLocation;
        DFWorkspaceRequest([state stringByAppendingPathComponent:@"dotfiles/desktop"],@"launcher",0,NSMakeRect(pointer.x,pointer.y,1,1));return;
    }
    NSURL *url=appleApplication(action);
    if (url) {
        [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:NSWorkspaceOpenConfiguration.configuration completionHandler:^(__unused NSRunningApplication *app,NSError *error) {
            if (error) dispatch_async(dispatch_get_main_queue(),^{ appleError(@"This system application could not be opened."); });
        }];
        return;
    }
    if (action==AppleForceQuit) { forceQuitChooser(); return; }
    if (action==AppleLock) {
        int (*lock)(void)=screenLock();
        if (!lock || lock()!=0) appleError(@"Lock Screen is unavailable on this macOS version.");
        return;
    }
    AEEventID eventID=applePowerEvent(action);
    if (!eventID) return;
    // Request the OS's confirmation dialogs; never send immediate restart,
    // shutdown or forced-logout events. This runs only after an explicit click.
    NSAppleEventDescriptor *target=[NSAppleEventDescriptor descriptorWithBundleIdentifier:@"com.apple.loginwindow"];
    NSAppleEventDescriptor *event=[NSAppleEventDescriptor appleEventWithEventClass:kCoreEventClass eventID:eventID targetDescriptor:target returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    [NSApp activate]; NSError *error=nil;
    [event sendEventWithOptions:NSAppleEventSendNoReply|NSAppleEventSendCanInteract|NSAppleEventSendCanSwitchLayer timeout:2 error:&error];
    if (error) appleError(@"The system action could not be opened. Check macOS Automation permissions for Desktop Controls.");
}

static NSArray *appleEntries(void) {
    return @[@[@"About This Mac",@(AppleAbout)], @[@"Search Applications…",@(AppleLauncher)], @[@"System Settings…",@(AppleSettings)], @[@"App Store…",@(AppleStore)],
             @[@"",@0], @[@"System Information…",@(AppleInformation)], @[@"Force Quit…",@(AppleForceQuit)],
             @[@"",@0], @[@"Sleep",@(AppleSleep)], @[@"Restart…",@(AppleRestart)], @[@"Shut Down…",@(AppleShutdown)],
             @[@"",@0], @[@"Lock Screen",@(AppleLock)], @[@"Log Out…",@(AppleLogout)]];
}
static BOOL validAppleAction(NSInteger action) { return action>=AppleAbout && action<=AppleLauncher; }
static NSArray *appleRows(void) {
    NSMutableArray *rows=[NSMutableArray array];
    for (NSArray *entry in appleEntries()) {
        NSInteger action=[entry[1] integerValue];
        BOOL enabled=validAppleAction(action) && (appleBundle(action) ? appleApplication(action)!=nil : action!=AppleLock || screenLock()!=NULL);
        [rows addObject:@{@"title":entry[0],@"apple_action":@(action),@"enabled":@(enabled),@"submenu":@NO}];
    }
    return rows;
}

static id attribute(id element, CFStringRef name) {
    CFTypeRef value=NULL;
    if (!element || AXUIElementCopyAttributeValue((__bridge AXUIElementRef)element,name,&value)!=kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}
static NSArray *children(id element) {
    id value=attribute(element,kAXChildrenAttribute);
    return [value isKindOfClass:NSArray.class] ? value : @[];
}
static NSString *title(id element) {
    id value=attribute(element,kAXTitleAttribute);
    return [value isKindOfClass:NSString.class] ? value : @"";
}
static NSArray *entries(id element) {
    NSArray *items=children(element);
    if (items.count==1 && [attribute(items.firstObject,kAXRoleAttribute) isEqual:(__bridge NSString *)kAXMenuRole]) items=children(items.firstObject);
    return items.count>100 ? [items subarrayWithRange:NSMakeRange(0,100)] : items;
}
static BOOL canInvoke(pid_t expected, pid_t active, BOOL enabled, BOOL submenu) {
    return expected>0 && expected==active && enabled && !submenu;
}
static BOOL menuIndex(NSString *value, NSInteger *index) {
    if (!value.length || value.length>2 || [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound) return NO;
    NSInteger number=value.integerValue; if (number<0 || number>1) return NO;
    *index=number; return YES;
}
// Apple remains its own button. Keep every other top-level menu, including
// the app's own menu, in its original order and with its original AX object.
static NSArray *applicationMenus(NSArray *menus) {
    return menus.count>1 ? [menus subarrayWithRange:NSMakeRange(1,menus.count-1)] : @[];
}
static NSArray *readMenus(pid_t pid) {
    if (!AXIsProcessTrusted() || pid<=0) return @[];
    id application=CFBridgingRelease(AXUIElementCreateApplication(pid));
    AXUIElementSetMessagingTimeout((__bridge AXUIElementRef)application,0.15);
    return children(attribute(application,kAXMenuBarAttribute));
}

@interface MenuSurface : NSView
@end
@interface MenuPanel : NSPanel
@end
@implementation MenuPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode==53) DFMenusHide(); else [super keyDown:event];
}
@end
@implementation MenuSurface
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(__unused NSRect)dirty {
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,0.5,0.5) xRadius:13 yRadius:13];
    [DFPanelColor(0x11151d) setFill]; [shape fill]; [DFPanelColor(0x2a3447) setStroke]; [shape stroke];
}
@end
@interface MenuDocument : NSView
@end
@implementation MenuDocument
- (BOOL)isFlipped { return YES; }
@end

@interface MenuRow : DFPanelButton
@property id element;
@property pid_t pid;
@property NSUInteger depth;
@property BOOL submenu;
@property NSInteger appleAction;
@property NSString *shortcut;
@property NSString *mark;
@end
static void showEntries(NSArray *items, NSString *heading, NSUInteger depth, NSPoint origin);
static NSArray *menuRows(NSArray *items);
static void dismissAfter(NSUInteger depth) {
    while (menuPanels.count>depth) { [menuPanels.lastObject orderOut:nil]; [menuPanels removeLastObject]; }
}
@implementation MenuRow
- (void)mouseEntered:(__unused NSEvent *)event {
    self.hovered=YES; self.needsDisplay=YES;
    if (!self.enabled) return;
    NSUInteger revision=++menuRevision;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,180*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if (self.hovered && menuRevision==revision && self.window.visible) [self expand];
    });
}
- (void)mouseExited:(__unused NSEvent *)event { self.hovered=NO; self.needsDisplay=YES; }
- (void)drawRect:(__unused NSRect)dirty {
    NSColor *color=DFPanelColor(self.enabled ? 0xe6edf7 : 0x94a3b8);
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new]; paragraph.lineBreakMode=NSLineBreakByTruncatingTail;
    NSDictionary *style=@{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium],NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:paragraph};
    [self.title drawInRect:NSMakeRect(24,8,self.bounds.size.width-104,18) withAttributes:style];
    [self.mark ?: @"" drawAtPoint:NSMakePoint(8,8) withAttributes:style];
    NSString *trailing=self.submenu ? @"›" : self.shortcut ?: @"";
    NSSize size=[trailing sizeWithAttributes:style];
    [trailing drawAtPoint:NSMakePoint(self.bounds.size.width-size.width-12,8) withAttributes:style];
}
- (void)expand {
    dismissAfter(self.depth+1);
    if (!self.submenu || self.depth>=4 || NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=self.pid) return;
    NSRect row=[self.window convertRectToScreen:[self convertRect:self.bounds toView:nil]];
    NSUInteger revision=++menuRevision; id element=self.element; pid_t pid=self.pid;
    dispatch_async(menuQueue,^{
        NSArray *items=menuRows(entries(element));
        dispatch_async(dispatch_get_main_queue(),^{
            if (revision!=menuRevision || !self.window.visible || NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid) return;
            showEntries(items,self.title,self.depth+1,NSMakePoint(NSMaxX(self.window.frame)-3,NSMaxY(row)+8));
        });
    });
}
- (void)invoke:(__unused id)sender {
    if (self.appleAction) {
        if (!self.enabled || !self.window.visible || !validAppleAction(self.appleAction)) return;
        NSInteger action=self.appleAction; DFMenusHide(); runAppleAction(action); return;
    }
    if (self.tag==1) {
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
        return;
    }
    if (self.submenu) { [self expand]; return; }
    pid_t pid=self.pid; id element=self.element;
    if (!canInvoke(pid,NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier,self.enabled,self.submenu)) return;
    DFMenusHide();
    dispatch_async(menuQueue,^{
        if (NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid) return;
        // Press exactly once: timeout may mean a modal action is already running.
        AXUIElementPerformAction((__bridge AXUIElementRef)element,kAXPressAction);
    });
}
@end

static NSString *shortcut(id element) {
    NSString *character=attribute(element,kAXMenuItemCmdCharAttribute);
    if (![character isKindOfClass:NSString.class] || !character.length) return @"";
    NSNumber *modifiers=attribute(element,kAXMenuItemCmdModifiersAttribute);
    if (![modifiers isKindOfClass:NSNumber.class]) return @"";
    unsigned flags=modifiers.unsignedIntValue;
    return [NSString stringWithFormat:@"%@%@%@%@%@",flags&kAXMenuItemModifierControl ? @"⌃" : @"",flags&kAXMenuItemModifierOption ? @"⌥" : @"",flags&kAXMenuItemModifierShift ? @"⇧" : @"",flags&kAXMenuItemModifierNoCommand ? @"" : @"⌘",character.uppercaseString];
}
static NSArray *menuRows(NSArray *items) {
    NSMutableArray *rows=[NSMutableArray array];
    double started=NSProcessInfo.processInfo.systemUptime;
    for (id element in items) {
        if (NSProcessInfo.processInfo.systemUptime-started>1) break;
        NSString *name=title(element);
        id mark=attribute(element,kAXMenuItemMarkCharAttribute);
        [rows addObject:@{@"element":element,@"title":name,@"enabled":@(![attribute(element,kAXEnabledAttribute) isEqual:@NO]),
                          @"submenu":@(children(element).count>0),@"shortcut":shortcut(element),@"mark":[mark isKindOfClass:NSString.class] ? mark : @""}];
    }
    return rows;
}
static void showEntries(NSArray *items, NSString *heading, NSUInteger depth, NSPoint origin) {
    dismissAfter(depth);
    NSPanel *panel=[[MenuPanel alloc] initWithContentRect:NSMakeRect(0,0,310,100) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    panel.level=CGWindowLevelForKey(kCGStatusWindowLevelKey)+3;
    panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorStationary;
    panel.opaque=NO; panel.backgroundColor=NSColor.clearColor; panel.hasShadow=YES; panel.hidesOnDeactivate=NO;
    MenuSurface *surface=[[MenuSurface alloc] initWithFrame:NSMakeRect(0,0,310,100)]; panel.contentView=surface;
    NSTextField *label=[NSTextField labelWithString:heading]; label.frame=NSMakeRect(16,12,278,18);
    label.textColor=DFPanelColor(0x94a3b8); label.font=[NSFont systemFontOfSize:10 weight:NSFontWeightSemibold]; [surface addSubview:label];
    MenuDocument *document=[[MenuDocument alloc] initWithFrame:NSMakeRect(0,0,294,1)]; CGFloat y=0;
    for (NSDictionary *item in items) {
        NSString *name=item[@"title"];
        if (!name.length) {
            NSView *line=[[NSView alloc] initWithFrame:NSMakeRect(12,y+4,270,1)]; line.wantsLayer=YES;
            line.layer.backgroundColor=DFPanelColor(0x2a3447).CGColor; [document addSubview:line]; y+=9; continue;
        }
        MenuRow *row=[[MenuRow alloc] initWithFrame:NSMakeRect(0,y,294,32)]; row.title=name; row.element=item[@"element"]; row.pid=menuPID; row.depth=depth;
        row.enabled=[item[@"enabled"] boolValue]; row.submenu=[item[@"submenu"] boolValue];
        row.shortcut=item[@"shortcut"]; row.mark=item[@"mark"]; row.appleAction=[item[@"apple_action"] integerValue];
        row.bordered=NO; row.target=row; row.action=@selector(invoke:); [document addSubview:row]; y+=32;
    }
    if (!items.count) {
        MenuRow *row=[[MenuRow alloc] initWithFrame:NSMakeRect(0,0,294,38)]; row.bordered=NO;
        row.title=AXIsProcessTrusted() ? @"This menu is unavailable" : @"Enable Accessibility…";
        row.enabled=!AXIsProcessTrusted(); row.tag=1; row.target=row; row.action=@selector(invoke:); [document addSubview:row]; y=38;
    }
    document.frame=NSMakeRect(0,0,294,y);
    CGFloat height=MIN(y,480)+48;
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(8,36,294,height-44)]; scroll.drawsBackground=NO;
    scroll.hasVerticalScroller=YES; scroll.autohidesScrollers=YES; scroll.scrollerStyle=NSScrollerStyleOverlay; scroll.documentView=document; [surface addSubview:scroll];
    NSScreen *screen=NSScreen.mainScreen; for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(NSEvent.mouseLocation,candidate.frame)) screen=candidate;
    CGFloat x=origin.x; if (x+310>NSMaxX(screen.frame)-12) x=depth ? NSMinX(menuPanels.lastObject.frame)-307 : NSMaxX(screen.frame)-322;
    [panel setFrame:NSMakeRect(MAX(NSMinX(screen.frame)+12,x),MAX(NSMinY(screen.frame)+12,origin.y-height),310,height) display:NO];
    surface.frame=NSMakeRect(0,0,310,height); [menuPanels addObject:panel]; DFPanelPrepare(panel);DFPanelPresent(panel);
    if (!depth) [panel makeKeyWindow];
}
static void updateBar(NSArray *menus, pid_t pid, BOOL force) {
    NSMutableArray *args=[NSMutableArray array];
    NSString *application=[NSRunningApplication runningApplicationWithProcessIdentifier:pid].localizedName ?: @"Application";
    [args addObjectsFromArray:@[@"--set",@"front_app",[@"label=" stringByAppendingString:application],[@"icon.background.image=app." stringByAppendingString:application]]];
    if (NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid) return;
    if (force || pid!=lastMenuPID || ![lastMenuApplication isEqual:application]) {
        NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:menuBarTool]; task.arguments=args;
        task.standardOutput=NSFileHandle.fileHandleWithNullDevice; task.standardError=NSFileHandle.fileHandleWithNullDevice;
        if ([task launchAndReturnError:nil]) { [task waitUntilExit]; if (!task.terminationStatus) { lastMenuApplication=application; lastMenuPID=pid; } }
    }
    dispatch_async(dispatch_get_main_queue(),^{
        if (NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid) return;
        topMenus=menus; menuPID=pid;
    });
}
static BOOL pointerInMenu(NSPoint pointer) {
    if (NSPointInRect(pointer,menuAnchor)) return YES;
    for (NSPanel *panel in menuPanels) if (NSPointInRect(pointer,NSInsetRect(panel.frame,-6,-6))) return YES;
    return NO;
}
static void dismissForEvent(NSEvent *event) {
    if (!menuPanels.count) return;
    if ((event.type==NSEventTypeKeyDown && event.keyCode==53)
        || (event.type!=NSEventTypeKeyDown && !pointerInMenu(NSEvent.mouseLocation))) DFMenusHide();
}
void DFMenusInitialize(NSString *sketchybar) {
    menuBarTool=sketchybar; menuQueue=dispatch_queue_create("local.dotfiles.desktop.menus",DISPATCH_QUEUE_SERIAL); menuPanels=[NSMutableArray array];
    menuMouseMonitor=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown handler:^(NSEvent *event) { dismissForEvent(event); }];
    // Escape is scoped to an open menu. Key monitoring uses the same local
    // Accessibility consent as the AX menus; it never installs a shortcut.
    menuKeyMonitor=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^(NSEvent *event) { dismissForEvent(event); }];
    menuLocalMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown|NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) { dismissForEvent(event); return event; }];
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:menuNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if ([note.object isEqual:@"hide"]) { DFMenusHide(); return; }
        if ([note.object isEqual:@"access"]) {
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES}); return;
        }
        NSInteger index; if (!menuIndex(note.object,&index)) return;
        if (index==openMenuIndex && menuPanels.count) { DFMenusHide(); return; }
        DFCalendarHide(); DFControlsHide(); DFMenusHide(); openMenuIndex=index;
        NSPoint pointer=NSEvent.mouseLocation; NSScreen *screen=NSScreen.mainScreen;
        for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(pointer,candidate.frame)) screen=candidate;
        CGFloat top=NSMaxY(screen.frame)-52;
        menuAnchor=NSMakeRect(pointer.x-44,top,88,NSMaxY(screen.frame)-top);
        NSPoint origin=NSMakePoint(pointer.x-16,top); pid_t pid=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
        menuPID=pid;
        if (index==0) {
            // SketchyBar is explicitly at y=4 with a maximum 40-point height;
            // its menu sits beneath that bar, not beneath the notch safe area.
            origin.y=NSMaxY(screen.frame)-52;
            showEntries(appleRows(),@"Apple",0,origin); return;
        }
        NSString *application=NSWorkspace.sharedWorkspace.frontmostApplication.localizedName ?: @"Application";
        menuPID=pid;
        if (!AXIsProcessTrusted()) {
            showEntries(@[],application,0,origin); return;
        }
        NSUInteger revision=++menuRevision;
        dispatch_async(menuQueue,^{
            // Read at click time: the menu may have changed since the bar was
            // revealed. Root entries always expand, even for lazy AX children.
            NSArray *menus=readMenus(pid);
            NSMutableArray *items=[NSMutableArray array];
            for (NSDictionary *item in menuRows(applicationMenus(menus))) {
                NSMutableDictionary *row=item.mutableCopy; row[@"submenu"]=@YES;
                [items addObject:row];
            }
            dispatch_async(dispatch_get_main_queue(),^{
                if (revision!=menuRevision || NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid) return;
                topMenus=menus; menuPID=pid; showEntries(items,application,0,origin);
            });
        });
    }];
}
void DFMenusNotify(NSString *command) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:menuNotification object:command userInfo:nil deliverImmediately:YES];
}
void DFMenusHide(void) { ++menuRevision; dismissAfter(0); openMenuIndex=-1; }
BOOL DFMenusContainsPointer(__unused NSPoint pointer) {
    // A click-open menu keeps the bar revealed until selection, outside click,
    // Escape or an application change, rather than disappearing on pointer exit.
    return menuPanels.count>0;
}
void DFMenusTick(double now, __unused NSPoint pointer, BOOL barVisible) {
    BOOL revealed=barVisible && !menuWasVisible; menuWasVisible=barVisible;
    pid_t pid=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    if (pid!=menuPID && menuPanels.count) DFMenusHide();
    if (pid!=menuPID || revealed) nextMenuRead=0;
    if (!barVisible || menuReading || now<nextMenuRead) return;
    nextMenuRead=now+1; menuReading=YES;
    dispatch_async(menuQueue,^{
        NSArray *menus=readMenus(pid);
        updateBar(menus,pid,revealed);
        dispatch_async(dispatch_get_main_queue(),^{ menuReading=NO; });
    });
}
NSDictionary *DFMenusStatus(void) { return @{@"accessibility":@(AXIsProcessTrusted()),@"visible":@(menuPanels.count>0),@"menus":@(topMenus.count),@"apple_items":@(appleEntries().count-3)}; }
int DFMenusSelfTest(void) {
    NSInteger index=-1;
    if (!menuIndex(@"0",&index) || index!=0 || !menuIndex(@"1",&index) || index!=1 || menuIndex(@"2",&index) || menuIndex(@"13",&index) || menuIndex(@"-1",&index) || menuIndex(@"1;open",&index)) return 1;
    NSArray *fixture=@[@"Apple",@"App",@"File",@"Edit",@"View",@"Window",@"Help"];
    if (![applicationMenus(fixture) isEqual:@[@"App",@"File",@"Edit",@"View",@"Window",@"Help"]]
        || applicationMenus(@[]).count || applicationMenus(@[@"Apple"]).count) return 1;
    NSMutableArray *many=[fixture mutableCopy]; for (NSUInteger i=0;i<20;i++) [many addObject:@(i)];
    if (applicationMenus(many).count!=many.count-1 || applicationMenus(many).lastObject!=many.lastObject) return 1;
    if (!canInvoke(42,42,YES,NO) || canInvoke(42,43,YES,NO) || canInvoke(42,42,NO,NO) || canInvoke(42,42,YES,YES) || canInvoke(0,0,YES,NO)) return 1;
    if (!validAppleAction(AppleAbout) || !validAppleAction(AppleLogout) || !validAppleAction(AppleLauncher) || validAppleAction(0) || validAppleAction(AppleLauncher+1)) return 1;
    if (appleEntries().count!=14 || ![appleBundle(AppleAbout) isEqual:@"com.apple.AboutThisMacLauncher"] || ![appleBundle(AppleSettings) isEqual:@"com.apple.systempreferences"] || appleBundle(-1) || applePowerEvent(AppleLauncher)) return 1;
    if (applePowerEvent(AppleRestart)!=kAEShowRestartDialog || applePowerEvent(AppleShutdown)!=kAEShowShutdownDialog
        || applePowerEvent(AppleLogout)!=kAELogOut || applePowerEvent(AppleSettings) || applePowerEvent(-1)) return 1;
    if (applePowerEvent(AppleRestart)==kAERestart || applePowerEvent(AppleShutdown)==kAEShutDown || applePowerEvent(AppleLogout)==kAEReallyLogOut) return 1;
    puts("Menu guards: nested app menu ordering, complete heading inventory, app ownership, themed Apple fixed-action entries, fixed application targets and confirmation-only session actions passed."); return 0;
}
