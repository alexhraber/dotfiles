#import "app-menu.h"
#import "control-panel.h"
#import "calendar-panel.h"
#import <ApplicationServices/ApplicationServices.h>

// AX objects and all menu titles stay in memory. Read/press the owning app's
// real menu; never emulate a menu command with a keystroke or shell snippet.
static NSString *const menuNotification=@"local.dotfiles.desktop.app-menu";
static NSString *menuBarTool;
static dispatch_queue_t menuQueue;
static NSArray *topMenus=@[];
static pid_t menuPID;
static BOOL menuReading;
static BOOL menuWasVisible;
static NSArray *lastMenuLabels;
static pid_t lastMenuPID;
static double nextMenuRead, menuAway;
static NSUInteger menuRevision;
static NSRect menuAnchor;
static NSMutableArray<NSPanel *> *menuPanels;

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
    NSInteger number=value.integerValue; if (number<0 || number>13) return NO;
    *index=number; return YES;
}

@interface MenuSurface : NSView
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

@interface MenuRow : NSButton
@property id element;
@property pid_t pid;
@property NSUInteger depth;
@property BOOL submenu;
@property BOOL hovered;
@property NSString *shortcut;
@property NSString *mark;
@end
static void showEntries(NSArray *items, NSString *heading, NSUInteger depth, NSPoint origin);
static NSArray *menuRows(NSArray *items);
static void dismissAfter(NSUInteger depth) {
    while (menuPanels.count>depth) { [menuPanels.lastObject orderOut:nil]; [menuPanels removeLastObject]; }
}
@implementation MenuRow
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas.copy) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
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
    if (self.hovered && self.enabled) {
        [DFPanelColor(0x202735) setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,2,1) xRadius:7 yRadius:7] fill];
    }
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
    if (!self.submenu || self.depth>=3 || NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=self.pid) return;
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
    NSPanel *panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,310,100) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
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
        row.shortcut=item[@"shortcut"]; row.mark=item[@"mark"];
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
    surface.frame=NSMakeRect(0,0,310,height); [menuPanels addObject:panel]; [panel orderFrontRegardless];
}
static void updateBar(NSArray *menus, pid_t pid, BOOL force) {
    NSMutableArray *args=[NSMutableArray array];
    NSString *application=[NSRunningApplication runningApplicationWithProcessIdentifier:pid].localizedName ?: @"Application";
    [args addObjectsFromArray:@[@"--set",@"front_app",[@"label=" stringByAppendingString:application],[@"icon.background.image=app." stringByAppendingString:application]]];
    NSMutableArray *labels=[NSMutableArray array];
    for (NSUInteger i=0;i<12;i++) {
        NSUInteger index=i+2; NSString *name=[NSString stringWithFormat:@"app_menu.%lu",(unsigned long)i];
        NSString *label=i==11 && menus.count>14 ? @"More" : index<menus.count ? title(menus[index]) : @"";
        [labels addObject:label];
        [args addObjectsFromArray:@[@"--set",name,[NSString stringWithFormat:@"drawing=%@",label.length ? @"on" : @"off"],[@"label=" stringByAppendingString:label]]];
    }
    if (NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid) return;
    if (force || pid!=lastMenuPID || ![lastMenuLabels isEqual:labels]) {
        NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:menuBarTool]; task.arguments=args;
        task.standardOutput=NSFileHandle.fileHandleWithNullDevice; task.standardError=NSFileHandle.fileHandleWithNullDevice;
        if ([task launchAndReturnError:nil]) { [task waitUntilExit]; if (!task.terminationStatus) { lastMenuLabels=labels; lastMenuPID=pid; } }
    }
    dispatch_async(dispatch_get_main_queue(),^{
        if (NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid) return;
        topMenus=menus; menuPID=pid;
    });
}
void DFMenusInitialize(NSString *sketchybar) {
    menuBarTool=sketchybar; menuQueue=dispatch_queue_create("local.dotfiles.desktop.menus",DISPATCH_QUEUE_SERIAL); menuPanels=[NSMutableArray array];
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:menuNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if ([note.object isEqual:@"hide"]) { DFMenusHide(); return; }
        if ([note.object isEqual:@"access"]) {
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES}); return;
        }
        NSInteger index; if (!menuIndex(note.object,&index)) return;
        DFCalendarHide(); DFControlsHide(); DFMenusHide();
        NSPoint pointer=NSEvent.mouseLocation; NSScreen *screen=NSScreen.mainScreen;
        for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(pointer,candidate.frame)) screen=candidate;
        CGFloat top=NSMaxY(screen.frame)-screen.safeAreaInsets.top-44;
        menuAnchor=NSMakeRect(pointer.x-44,top,88,NSMaxY(screen.frame)-top);
        NSPoint origin=NSMakePoint(pointer.x-16,top); pid_t pid=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
        if (!AXIsProcessTrusted() || pid!=menuPID || index>=(NSInteger)topMenus.count) {
            showEntries(@[],index==0 ? @"Apple" : @"Application menu",0,origin); nextMenuRead=0; return;
        }
        NSArray *menus=topMenus; id element=menus[index]; NSUInteger revision=++menuRevision;
        dispatch_async(menuQueue,^{
            BOOL overflow=index==13 && menus.count>14;
            NSArray *items=menuRows(overflow ? [menus subarrayWithRange:NSMakeRange(13,menus.count-13)] : entries(element));
            NSString *heading=overflow ? @"More menus" : index==0 ? @"Apple" : title(element);
            dispatch_async(dispatch_get_main_queue(),^{
                if (revision==menuRevision && NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier==pid && NSPointInRect(NSEvent.mouseLocation,menuAnchor)) showEntries(items,heading,0,origin);
            });
        });
    }];
}
void DFMenusNotify(NSString *command) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:menuNotification object:command userInfo:nil deliverImmediately:YES];
}
void DFMenusHide(void) { ++menuRevision; dismissAfter(0); menuAway=0; }
BOOL DFMenusContainsPointer(NSPoint pointer) {
    if (!menuPanels.count) return NO;
    if (NSPointInRect(pointer,menuAnchor)) return YES;
    for (NSPanel *panel in menuPanels) if (NSPointInRect(pointer,NSInsetRect(panel.frame,-6,-6))) return YES;
    return NO;
}
void DFMenusTick(double now, NSPoint pointer, BOOL barVisible) {
    BOOL revealed=barVisible && !menuWasVisible; menuWasVisible=barVisible;
    if (menuPanels.count) {
        if (DFMenusContainsPointer(pointer)) menuAway=0;
        else if (!menuAway) menuAway=now;
        else if (now-menuAway>0.32) DFMenusHide();
    }
    pid_t pid=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    if (pid!=menuPID && menuPanels.count) DFMenusHide();
    if (pid!=menuPID || revealed) nextMenuRead=0;
    if (!barVisible || menuReading || now<nextMenuRead) return;
    nextMenuRead=now+1; menuReading=YES;
    dispatch_async(menuQueue,^{
        NSArray *menus=@[];
        if (AXIsProcessTrusted()) {
            id application=CFBridgingRelease(AXUIElementCreateApplication(pid));
            AXUIElementSetMessagingTimeout((__bridge AXUIElementRef)application,0.15);
            menus=children(attribute(application,kAXMenuBarAttribute));
        }
        updateBar(menus,pid,revealed);
        dispatch_async(dispatch_get_main_queue(),^{ menuReading=NO; });
    });
}
NSDictionary *DFMenusStatus(void) { return @{@"accessibility":@(AXIsProcessTrusted()),@"visible":@(menuPanels.count>0),@"menus":@(topMenus.count)}; }
int DFMenusSelfTest(void) {
    NSInteger index=-1;
    if (!menuIndex(@"0",&index) || index!=0 || !menuIndex(@"13",&index) || menuIndex(@"14",&index) || menuIndex(@"-1",&index) || menuIndex(@"1;open",&index)) return 1;
    if (!canInvoke(42,42,YES,NO) || canInvoke(42,43,YES,NO) || canInvoke(42,42,NO,NO) || canInvoke(42,42,YES,YES) || canInvoke(0,0,YES,NO)) return 1;
    puts("Application menu guards: index bounds, current app, disabled items and submenu dispatch passed."); return 0;
}
