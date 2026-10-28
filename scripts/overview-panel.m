#import "overview-panel.h"
#import "panel-style.h"
#import "control-panel.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <unistd.h>

// Read-only SkyLight metadata, also used by yabai (src/misc/extern.h).
// Switching uses the user's existing horizontal Space shortcuts, with readback.
static int (*connectionID)(void);
static CFArrayRef (*copyDisplays)(int);
static CFArrayRef (*copyWindowSpaces)(int,int,CFArrayRef);
static NSPanel *panel;
static NSArray<NSMutableDictionary *> *spaces;
static NSMutableArray<NSButton *> *cards;
static NSString *displayIdentifier,*overviewError;
static NSArray<NSDictionary *> *displayGroups;
static NSTextField *feedback;
static dispatch_block_t afterSwitch;
static NSUInteger revision,selection,images;
static BOOL capturePending,switching;
static double openedAt;
static id outsideMonitor;

static NSArray *displays(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        void *lib=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY);
        if(lib){connectionID=dlsym(lib,"SLSMainConnectionID");copyDisplays=dlsym(lib,"SLSCopyManagedDisplaySpaces");copyWindowSpaces=dlsym(lib,"SLSCopySpacesForWindows");}
    });
    return connectionID && copyDisplays ? CFBridgingRelease(copyDisplays(connectionID())) : @[];
}
static NSDictionary *displayNamed(NSString *identifier) {
    for(NSDictionary *display in displays())if([display[@"Display Identifier"] isEqual:identifier])return display;
    return nil;
}
static NSInteger spaceIndex(NSArray *list,NSNumber *identifier) {
    for(NSUInteger i=0;i<list.count;i++)if([list[i][@"ManagedSpaceID"] isEqual:identifier])return (NSInteger)i;
    return NSNotFound;
}
static BOOL includeSpace(NSDictionary *space,NSSet *occupied) {
    return [space[@"fullscreen"] boolValue] || [occupied containsObject:space[@"ManagedSpaceID"]];
}
static NSRect cardFrame(NSUInteger index,NSUInteger columns,CGFloat width) {
    CGFloat cardWidth=(width-56-(columns-1)*16)/columns;
    return NSMakeRect(28+(index%columns)*(cardWidth+16),80+(index/columns)*204,cardWidth,188);
}
static void failOverview(NSString *code,NSString *message) {
    switching=NO;afterSwitch=nil;overviewError=code;feedback.stringValue=message;
    [panel orderFrontRegardless];[panel makeKeyWindow];
}
static id axValue(id element,CFStringRef key) {
    CFTypeRef value=NULL;if(!element || AXUIElementCopyAttributeValue((__bridge AXUIElementRef)element,key,&value)!=kAXErrorSuccess)return nil;
    return CFBridgingRelease(value);
}
static id exactAXWindow(NSDictionary *entry) {
    NSRunningApplication *app=entry[@"app"];if(!app || app.terminated || !entry[@"window_id"])return nil;
    AXError (*windowID)(AXUIElementRef,CGWindowID *)=dlsym(RTLD_DEFAULT,"_AXUIElementGetWindow");if(!windowID)return nil;
    id root=CFBridgingRelease(AXUIElementCreateApplication(app.processIdentifier));AXUIElementSetMessagingTimeout((__bridge AXUIElementRef)root,.15);
    id list=axValue(root,kAXWindowsAttribute);if(![list isKindOfClass:NSArray.class])return nil;
    for(id window in list){CGWindowID identifier=0;if(windowID((__bridge AXUIElementRef)window,&identifier)==kAXErrorSuccess && identifier==[entry[@"window_id"] unsignedIntValue])return window;}
    return nil;
}
static NSScreen *screenNamed(NSString *identifier) {
    for(NSScreen *screen in NSScreen.screens){CGDirectDisplayID display=[screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(display);
        NSString *name=uuid ? CFBridgingRelease(CFUUIDCreateString(NULL,uuid)) : nil;if(uuid)CFRelease(uuid);if([name isEqual:identifier])return screen;}
    return nil;
}
static void redrawSelection(void) {for(NSButton *card in cards)card.needsDisplay=YES;}
static void chooseSpace(NSUInteger index);
static void moveWindowToScreen(NSDictionary *entry,NSScreen *screen);
static void beginEntrySwitch(NSDictionary *entry,dispatch_block_t completion);
@interface OverviewPanel : NSPanel
@end
@implementation OverviewPanel
- (BOOL)canBecomeKeyWindow {return YES;}
- (void)keyDown:(NSEvent *)event {
    if(event.keyCode==53){DFOverviewHide();return;}
    if(!spaces.count || switching)return;
    if(event.keyCode==36 || event.keyCode==76){chooseSpace(selection);return;}
    NSInteger delta=0;
    if(event.keyCode==123)delta=-1;else if(event.keyCode==124)delta=1;
    else if(event.keyCode==125)delta=MIN(3,spaces.count);else if(event.keyCode==126)delta=-(NSInteger)MIN(3,spaces.count);
    else if(event.characters.length==1){NSInteger digit=event.characters.integerValue;if(digit>0 && digit<=9 && (NSUInteger)digit<=spaces.count){chooseSpace(digit-1);return;}}
    if(delta){selection=(selection+spaces.count+delta)%spaces.count;redrawSelection();}
}
@end
@interface OverviewSurface : NSView
@end
@implementation OverviewSurface
- (BOOL)isFlipped {return YES;}
- (BOOL)acceptsFirstResponder {return YES;}
- (void)keyDown:(NSEvent *)event {[self.window keyDown:event];}
- (void)drawRect:(__unused NSRect)rect {
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:22 yRadius:22];
    [DFPanelColor(0x11151d) setFill];[shape fill];[DFPanelColor(0x2a3447) setStroke];[shape stroke];
}
@end
@interface SpaceCard : DFPanelButton <NSDraggingSource>
@property NSUInteger index;
@end
@implementation SpaceCard
- (BOOL)isFlipped {return YES;}
- (void)drawRect:(__unused NSRect)rect {
    if(self.index>=spaces.count)return;
    NSDictionary *entry=spaces[self.index];NSRect bounds=NSInsetRect(self.bounds,1,1);
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:12 yRadius:12];
    [DFPanelColor(0x202735) setFill];[shape fill];
    [DFPanelColor(self.index==selection || self.hovered ? 0xb8a6ff : 0x2a3447) setStroke];shape.lineWidth=self.index==selection ? 2 : 1;[shape stroke];
    NSRect preview=NSMakeRect(10,10,bounds.size.width-18,126);
    NSImage *image=entry[@"image"],*icon=[entry[@"app"] icon];
    [NSGraphicsContext saveGraphicsState];[[NSBezierPath bezierPathWithRoundedRect:preview xRadius:8 yRadius:8] addClip];
    if(image){CGFloat scale=MIN(preview.size.width/image.size.width,preview.size.height/image.size.height);
        [image drawInRect:NSMakeRect(NSMidX(preview)-image.size.width*scale/2,NSMidY(preview)-image.size.height*scale/2,image.size.width*scale,image.size.height*scale) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];}
    else if(icon)[icon drawInRect:NSMakeRect(NSMidX(preview)-24,NSMidY(preview)-24,48,48) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    else {NSImage *symbol=[NSImage imageWithSystemSymbolName:@"rectangle.on.rectangle" accessibilityDescription:@"Desktop"];
        [symbol drawInRect:NSMakeRect(NSMidX(preview)-20,NSMidY(preview)-16,40,32)];}
    [NSGraphicsContext restoreGraphicsState];
    NSMutableParagraphStyle *style=NSMutableParagraphStyle.new;style.lineBreakMode=NSLineBreakByTruncatingTail;
    [entry[@"title"] drawInRect:NSMakeRect(12,143,bounds.size.width-24,18) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:DFPanelColor(0xe6edf7),NSParagraphStyleAttributeName:style}];
    NSString *detail=[entry[@"desktop"] stringByAppendingString:[entry[@"current"] boolValue] ? @" · current" : @""];
    [[NSString stringWithFormat:@"%lu   %@",(unsigned long)self.index+1,detail] drawAtPoint:NSMakePoint(12,166) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10],NSForegroundColorAttributeName:DFPanelColor(0x94a3b8)}];
}
- (void)choose:(__unused id)sender {chooseSpace(self.index);}
- (void)mouseDown:(NSEvent *)event {
    if(self.index>=spaces.count)return;NSPoint start=event.locationInWindow;
    while(YES){NSEvent *next=[self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged|NSEventMaskLeftMouseUp];if(!next)return;
        if(next.type==NSEventTypeLeftMouseUp){chooseSpace(self.index);return;}
        if(hypot(next.locationInWindow.x-start.x,next.locationInWindow.y-start.y)<6)continue;
        if(!spaces[self.index][@"window_id"])return;
        NSPasteboardItem *item=NSPasteboardItem.new;[item setString:[NSString stringWithFormat:@"%lu:%lu",(unsigned long)revision,(unsigned long)self.index] forType:@"local.dotfiles.desktop.window"];
        NSDraggingItem *drag=[[NSDraggingItem alloc] initWithPasteboardWriter:item];NSImage *icon=[spaces[self.index][@"app"] icon] ?: [NSImage imageWithSystemSymbolName:@"macwindow" accessibilityDescription:nil];
        NSPoint point=[self convertPoint:next.locationInWindow fromView:nil];[drag setDraggingFrame:NSMakeRect(point.x-24,point.y-24,48,48) contents:icon];
        [self beginDraggingSessionWithItems:@[drag] event:next source:self];return;
    }
}
- (NSDragOperation)draggingSession:(__unused NSDraggingSession *)session sourceOperationMaskForDraggingContext:(__unused NSDraggingContext)context {return NSDragOperationMove;}
- (void)moveMenu:(NSMenuItem *)item {if([item.representedObject[@"revision"] unsignedIntegerValue]==revision)moveWindowToScreen(item.representedObject[@"entry"],item.representedObject[@"screen"]);}
- (NSMenu *)menuForEvent:(__unused NSEvent *)event {
    if(self.index>=spaces.count)return nil;NSDictionary *entry=spaces[self.index];NSMenu *menu=NSMenu.new;
    for(NSDictionary *group in displayGroups)if(![group[@"identifier"] isEqual:entry[@"display"]]){
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:[@"Move to " stringByAppendingString:group[@"name"]] action:@selector(moveMenu:) keyEquivalent:@""];item.target=self;
        item.representedObject=@{@"entry":entry,@"screen":group[@"screen"],@"revision":@(revision)};[menu addItem:item];
    }
    if(!menu.itemArray.count){NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:@"Connect another display to move this window" action:nil keyEquivalent:@""];item.enabled=NO;[menu addItem:item];}return menu;
}
@end
@interface DisplayDropZone : NSView <NSDraggingDestination>
@property NSScreen *targetScreen;
@property NSString *titleText;
@property BOOL highlighted;
@end
@implementation DisplayDropZone
- (instancetype)initWithFrame:(NSRect)frame {self=[super initWithFrame:frame];if(self)[self registerForDraggedTypes:@[@"local.dotfiles.desktop.window"]];return self;}
- (BOOL)isFlipped {return YES;}
- (void)drawRect:(__unused NSRect)rect {
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:10 yRadius:10];[DFPanelColor(self.highlighted ? 0x29313b : 0x202735) setFill];[shape fill];[DFPanelColor(self.highlighted ? 0xb8a6ff : 0x2a3447) setStroke];[shape stroke];
    NSMutableParagraphStyle *style=NSMutableParagraphStyle.new;style.lineBreakMode=NSLineBreakByTruncatingTail;
    [self.titleText drawInRect:NSInsetRect(self.bounds,12,12) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:DFPanelColor(0xe6edf7),NSParagraphStyleAttributeName:style}];
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {if(![sender.draggingSource isKindOfClass:SpaceCard.class])return NSDragOperationNone;self.highlighted=YES;self.needsDisplay=YES;return NSDragOperationMove;}
- (void)draggingExited:(__unused id<NSDraggingInfo>)sender {self.highlighted=NO;self.needsDisplay=YES;}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {return [sender.draggingSource isKindOfClass:SpaceCard.class];}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    self.highlighted=NO;self.needsDisplay=YES;SpaceCard *card=sender.draggingSource;if(![card isKindOfClass:SpaceCard.class] || card.index>=spaces.count)return NO;
    NSString *token=[sender.draggingPasteboard stringForType:@"local.dotfiles.desktop.window"];
    if(![token isEqual:[NSString stringWithFormat:@"%lu:%lu",(unsigned long)revision,(unsigned long)card.index]])return NO;
    moveWindowToScreen(spaces[card.index],self.targetScreen);return YES;
}
@end
@interface OverviewActions : NSObject
- (void)close:(id)sender;
- (void)displayControls:(id)sender;
@end
@implementation OverviewActions
- (void)close:(__unused id)sender {DFOverviewHide();}
- (void)displayControls:(__unused id)sender {
    DFOverviewHide();NSTask *task=NSTask.new;NSString *python=[NSFileManager.defaultManager isExecutableFileAtPath:@"/opt/homebrew/bin/python3"] ? @"/opt/homebrew/bin/python3" : @"/usr/bin/python3";
    task.executableURL=[NSURL fileURLWithPath:python];NSString *config=NSProcessInfo.processInfo.environment[@"XDG_CONFIG_HOME"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@".config"];
    task.arguments=@[@"-B",[config stringByAppendingPathComponent:@"sketchybar/plugins/controls.py"],@"click",@"brightness"];task.standardOutput=NSFileHandle.fileHandleWithNullDevice;task.standardError=NSFileHandle.fileHandleWithNullDevice;[task launchAndReturnError:nil];
}
@end
static OverviewActions *actions;
static void heading(NSView *view,NSString *text,NSRect frame,CGFloat size,unsigned color) {
    NSTextField *field=[NSTextField labelWithString:text];field.frame=frame;field.font=[NSFont systemFontOfSize:size weight:NSFontWeightMedium];field.textColor=DFPanelColor(color);[view addSubview:field];
}
static void switchStep(NSNumber *target,NSString *display,NSUInteger attempt,NSUInteger token) {
    if(token!=revision || !switching)return;
    NSDictionary *live=displayNamed(display);NSArray *list=live[@"Spaces"];
    NSInteger from=spaceIndex(list,live[@"Current Space"][@"ManagedSpaceID"]),to=spaceIndex(list,target);
    if(from==to && from!=NSNotFound){dispatch_block_t completion=afterSwitch;afterSwitch=nil;if(completion)completion();else DFOverviewHide();return;}
    if(from==NSNotFound || to==NSNotFound || attempt>=32 || !AXIsProcessTrusted()){
        failOverview(@"switch_unavailable",@"Could not reach that workspace. Your windows have not been moved.");return;
    }
    BOOL right=to>from;
    NSDictionary *hotkeys=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("AppleSymbolicHotKeys"),CFSTR("com.apple.symbolichotkeys")));
    NSDictionary *binding=hotkeys[right ? @"81" : @"79"];
    if(binding[@"enabled"] && ![binding[@"enabled"] boolValue]){failOverview(@"space_shortcut_disabled",@"Horizontal desktop switching is disabled in your keyboard settings.");return;}
    NSArray *parameters=binding[@"value"][@"parameters"];
    CGKeyCode key=right ? 124 : 123;CGEventFlags flags=kCGEventFlagMaskControl|kCGEventFlagMaskSecondaryFn|kCGEventFlagMaskNumericPad;
    if(parameters.count==3){key=[parameters[1] unsignedShortValue];flags=[parameters[2] unsignedLongLongValue]|kCGEventFlagMaskSecondaryFn|kCGEventFlagMaskNumericPad;}
    if(key>127){failOverview(@"space_shortcut_unavailable",@"The configured desktop shortcut is unavailable.");return;}
    // macOS 27 normalizes arrow flags against actual modifier state. Send a
    // complete chord, and always release only modifiers synthesized here.
    CGEventSourceRef source=CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventFlags held=CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState),added=0;
    CGKeyCode codes[]={59,56,58,55};CGEventFlags masks[]={kCGEventFlagMaskControl,kCGEventFlagMaskShift,kCGEventFlagMaskAlternate,kCGEventFlagMaskCommand};
    for(NSUInteger i=0;i<4;i++)if((flags&masks[i]) && !(held&masks[i])){
        added|=masks[i];CGEventRef event=CGEventCreateKeyboardEvent(source,codes[i],true);
        if(event){CGEventSetFlags(event,held|added);CGEventPost(kCGHIDEventTap,event);CFRelease(event);usleep(12000);}
    }
    CGEventRef down=CGEventCreateKeyboardEvent(source,key,true),up=CGEventCreateKeyboardEvent(source,key,false);
    if(down && up){CGEventSetFlags(down,flags);CGEventSetFlags(up,flags);CGEventPost(kCGHIDEventTap,down);CGEventPost(kCGHIDEventTap,up);}
    if(down)CFRelease(down);if(up)CFRelease(up);usleep(12000);
    for(NSInteger i=3;i>=0;i--)if(added&masks[i]){added&=~masks[i];CGEventRef event=CGEventCreateKeyboardEvent(source,codes[i],false);if(event){CGEventSetFlags(event,held|added);CGEventPost(kCGHIDEventTap,event);CFRelease(event);}}
    if(source)CFRelease(source);
    NSNumber *before=live[@"Current Space"][@"ManagedSpaceID"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,600*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(token!=revision)return;
        if([displayNamed(display)[@"Current Space"][@"ManagedSpaceID"] isEqual:before]){failOverview(@"switch_no_progress",@"The desktop switch did not complete. Try your horizontal swipe, then reopen this view.");return;}
        switchStep(target,display,attempt+1,token);
    });
}
static void beginEntrySwitch(NSDictionary *entry,dispatch_block_t completion) {
    NSNumber *target=entry[@"ManagedSpaceID"];NSString *display=entry[@"display"];
    if(spaceIndex(displayNamed(display)[@"Spaces"],target)==NSNotFound){failOverview(@"space_closed",@"That workspace has closed. Reopen the overview to refresh.");return;}
    switching=YES;afterSwitch=completion;[panel orderOut:nil];
    if(![display isEqual:displayIdentifier]){
        id window=exactAXWindow(entry);
        if(!window){failOverview(@"focus_unavailable",@"Activate that display first, then choose its workspace.");return;}
        NSRunningApplication *app=entry[@"app"];[app unhide];AXUIElementSetAttributeValue((__bridge AXUIElementRef)window,kAXMainAttribute,kCFBooleanTrue);AXUIElementPerformAction((__bridge AXUIElementRef)window,kAXRaiseAction);[app activateWithOptions:0];
        NSUInteger token=revision;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            if(token!=revision)return;
            if([displayNamed(display)[@"Current Space"][@"ManagedSpaceID"] isEqual:target])switchStep(target,display,0,token);
            else failOverview(@"focus_unavailable",@"Activate that display first, then choose its workspace.");
        });return;
    }
    switchStep(target,display,0,revision);
}
static void chooseSpace(NSUInteger index) {
    if(index>=spaces.count || switching)return;NSDictionary *entry=spaces[index];
    beginEntrySwitch(entry,^{id window=exactAXWindow(entry);if(window){NSRunningApplication *app=entry[@"app"];[app unhide];AXUIElementSetAttributeValue((__bridge AXUIElementRef)window,kAXMainAttribute,kCFBooleanTrue);AXUIElementPerformAction((__bridge AXUIElementRef)window,kAXRaiseAction);[app activateWithOptions:0];}DFOverviewHide();});
}
static BOOL setAX(id window,CFStringRef key,CFTypeRef value) {return AXUIElementSetAttributeValue((__bridge AXUIElementRef)window,key,value)==kAXErrorSuccess;}
static BOOL waitFullscreen(id window,BOOL expected,double timeout) {
    double end=NSProcessInfo.processInfo.systemUptime+timeout;
    do{if([axValue(window,CFSTR("AXFullScreen")) boolValue]==expected)return YES;[NSThread sleepForTimeInterval:.04];}while(NSProcessInfo.processInfo.systemUptime<end);return NO;
}
static CGRect destinationRect(CGRect screen,CGSize original) {
    CGFloat width=MIN(MAX(160,original.width),MAX(160,screen.size.width-80));
    CGFloat height=MIN(MAX(100,original.height),MAX(100,screen.size.height-128));
    return CGRectMake(CGRectGetMidX(screen)-width/2,CGRectGetMinY(screen)+64,width,height);
}
static void moveWindowToScreen(NSDictionary *entry,NSScreen *screen) {
    if(switching)return;
    if(!AXIsProcessTrusted() || !entry[@"window_id"]){failOverview(@"move_unavailable",@"This window cannot be moved right now.");return;}
    CGDirectDisplayID target=[screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];BOOL connected=NO;
    for(NSScreen *live in NSScreen.screens)if([live.deviceDescription[@"NSScreenNumber"] unsignedIntValue]==target)connected=YES;
    if(!connected){failOverview(@"display_disconnected",@"That display disconnected. Reopen the overview to refresh.");return;}
    if([screenNamed(entry[@"display"]).deviceDescription[@"NSScreenNumber"] unsignedIntValue]==target)return;
    CGRect bounds=CGDisplayBounds(target);
    beginEntrySwitch(entry,^{
        id window=exactAXWindow(entry);if(!window){failOverview(@"window_unavailable",@"The selected window is no longer available.");return;}
        NSUInteger token=revision;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            BOOL fullscreen=[axValue(window,CFSTR("AXFullScreen")) boolValue],success=YES;
            id originalPosition=axValue(window,kAXPositionAttribute),originalSize=axValue(window,kAXSizeAttribute);
            if(fullscreen)success=setAX(window,CFSTR("AXFullScreen"),kCFBooleanFalse) && waitFullscreen(window,NO,3);
            if(success){
                CGSize natural=CGSizeMake(bounds.size.width*.7,bounds.size.height*.7);id currentSize=axValue(window,kAXSizeAttribute);
                if(currentSize && CFGetTypeID((__bridge CFTypeRef)currentSize)==AXValueGetTypeID())AXValueGetValue((__bridge AXValueRef)currentSize,kAXValueCGSizeType,&natural);
                CGRect destination=destinationRect(bounds,natural);CGPoint position=destination.origin;CGSize size=destination.size;
                AXValueRef point=AXValueCreate(kAXValueCGPointType,&position),dimensions=AXValueCreate(kAXValueCGSizeType,&size);
                // Clamp to the destination before moving, then assert position again.
                setAX(window,kAXSizeAttribute,dimensions);success=setAX(window,kAXPositionAttribute,point);CFRelease(point);CFRelease(dimensions);
                [NSThread sleepForTimeInterval:.12];CGPoint actual=CGPointZero;id value=axValue(window,kAXPositionAttribute);
                success=success && value && CFGetTypeID((__bridge CFTypeRef)value)==AXValueGetTypeID() && AXValueGetValue((__bridge AXValueRef)value,kAXValueCGPointType,&actual) && CGRectContainsPoint(bounds,actual);
            }
            if(!success){if(originalSize)setAX(window,kAXSizeAttribute,(__bridge CFTypeRef)originalSize);if(originalPosition)setAX(window,kAXPositionAttribute,(__bridge CFTypeRef)originalPosition);}
            if(fullscreen){BOOL restored=setAX(window,CFSTR("AXFullScreen"),kCFBooleanTrue) && waitFullscreen(window,YES,3);success=success && restored;}
            dispatch_async(dispatch_get_main_queue(),^{if(token!=revision)return;if(success)DFOverviewHide();else failOverview(@"move_failed",@"The app could not complete the move. Check the window and try again.");});
        });
    });
}
void DFOverviewShow(void) {
    if(panel.visible){DFOverviewHide();return;}
    DFOverviewHide();NSArray *inventory=displays();
    NSScreen *screen=NSScreen.mainScreen;for(NSScreen *candidate in NSScreen.screens)if(NSPointInRect(NSEvent.mouseLocation,candidate.frame)){screen=candidate;break;}
    CGDirectDisplayID did=[screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
    CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(did);NSString *name=uuid ? CFBridgingRelease(CFUUIDCreateString(NULL,uuid)) : nil;if(uuid)CFRelease(uuid);
    displayIdentifier=name;NSMutableArray *entries=NSMutableArray.new,*groups=NSMutableArray.new;
    NSArray *windows=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll,kCGNullWindowID));
    NSMutableDictionary *occupants=NSMutableDictionary.new;NSMutableSet *occupied=NSMutableSet.new;
    for(NSDictionary *window in windows){
        if([window[(id)kCGWindowLayer] intValue]!=0)continue;
        NSRunningApplication *app=[NSRunningApplication runningApplicationWithProcessIdentifier:[window[(id)kCGWindowOwnerPID] intValue]];
        if(!app || app.activationPolicy!=NSApplicationActivationPolicyRegular || app.processIdentifier==getpid())continue;
        CGRect bounds;if(!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)window[(id)kCGWindowBounds],&bounds) || bounds.size.width<80 || bounds.size.height<60)continue;
        if(copyWindowSpaces){NSArray *membership=CFBridgingRelease(copyWindowSpaces(connectionID(),7,(__bridge CFArrayRef)@[window[(id)kCGWindowNumber]]));
            for(NSNumber *sid in membership){if(!occupants[sid])occupants[sid]=NSMutableArray.new;[occupants[sid] addObject:window];[occupied addObject:sid];}}
    }
    for(NSDictionary *display in inventory){
        NSString *identifier=display[@"Display Identifier"];NSScreen *connected=screenNamed(identifier);if(!connected && inventory.count==1)connected=screen;
        if(!connected || !identifier)continue;
        NSMutableArray *indexes=NSMutableArray.new;NSUInteger desktop=0;
        for(NSDictionary *space in display[@"Spaces"]){
            if(entries.count>=96)break;
            NSNumber *sid=space[@"ManagedSpaceID"];if(![sid isKindOfClass:NSNumber.class])continue;
            BOOL fullscreen=[space[@"type"] intValue]!=0;if(!fullscreen)desktop++;
            if(copyWindowSpaces && !includeSpace(@{@"ManagedSpaceID":sid,@"fullscreen":@(fullscreen)},occupied))continue;
            NSArray *members=fullscreen ? @[@{}] : occupants[sid] ?: @[@{}];
            for(NSDictionary *window in members){
                if(entries.count>=96)break;
                pid_t pid=fullscreen ? [space[@"pid"] intValue] : [window[(id)kCGWindowOwnerPID] intValue];
                NSRunningApplication *app=[NSRunningApplication runningApplicationWithProcessIdentifier:pid];
                NSString *title=window[(id)kCGWindowName];
                if(fullscreen){NSArray *tiles=space[@"TileLayoutManager"][@"TileSpaces"];title=tiles.firstObject[@"name"];}
                if(![title isKindOfClass:NSString.class] || !title.length)title=app.localizedName ?: @"Desktop";
                if(title.length>180)title=[title substringToIndex:180];
                NSMutableDictionary *entry=[@{@"ManagedSpaceID":sid,@"title":title,@"fullscreen":@(fullscreen),@"display":identifier,
                    @"desktop":fullscreen ? @"Full screen" : [NSString stringWithFormat:@"Desktop %lu",(unsigned long)desktop],
                    @"current":@([sid isEqual:display[@"Current Space"][@"ManagedSpaceID"]])} mutableCopy];
                if(app)entry[@"app"]=app;NSNumber *wid=fullscreen ? space[@"fs_wid"] : window[(id)kCGWindowNumber];if(wid)entry[@"window_id"]=wid;
                [indexes addObject:@(entries.count)];[entries addObject:entry];
            }
        }
        [groups addObject:@{@"identifier":identifier,@"screen":connected,@"name":connected.localizedName ?: @"Display",@"indexes":indexes}];
    }
    [groups sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){CGFloat x=[a[@"screen"] frame].origin.x,y=[b[@"screen"] frame].origin.x;return x<y ? NSOrderedAscending : x>y ? NSOrderedDescending : NSOrderedSame;}];
    spaces=entries;displayGroups=groups;selection=0;for(NSUInteger i=0;i<spaces.count;i++)if([spaces[i][@"current"] boolValue] && [spaces[i][@"display"] isEqual:displayIdentifier]){selection=i;break;}
    if(!panel){panel=[[OverviewPanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];DFPanelPrepare(panel);
        panel.collectionBehavior|=NSWindowCollectionBehaviorCanJoinAllApplications;panel.becomesKeyOnlyIfNeeded=NO;
        panel.level=CGWindowLevelForKey(kCGStatusWindowLevelKey)+4;panel.opaque=NO;panel.backgroundColor=NSColor.clearColor;panel.hasShadow=YES;}
    NSUInteger columns=3;CGFloat width=MIN(1120,screen.frame.size.width-64),contentHeight=0;
    for(NSDictionary *group in displayGroups)contentHeight+=72+MAX(1,ceil([group[@"indexes"] count]/3.0))*204;
    CGFloat height=MIN(screen.frame.size.height-100,MAX(350,contentHeight+126));
    [panel setFrame:NSMakeRect(NSMidX(screen.frame)-width/2,NSMidY(screen.frame)-height/2,width,height) display:NO];
    OverviewSurface *view=[[OverviewSurface alloc] initWithFrame:NSMakeRect(0,0,width,height)];panel.contentView=view;
    heading(view,@"Workspaces",NSMakeRect(28,22,width-240,30),24,0xe6edf7);
    heading(view,@"Drag a window to a display header to move it. Right-click a card for Move to…",NSMakeRect(29,54,width-58,18),11,0x94a3b8);
    if(!actions)actions=OverviewActions.new;
    NSButton *displayButton=[NSButton buttonWithTitle:@"Display controls…" target:actions action:@selector(displayControls:)];displayButton.frame=NSMakeRect(width-268,26,140,28);displayButton.bezelStyle=NSBezelStyleRounded;[view addSubview:displayButton];
    NSButton *close=[NSButton buttonWithTitle:@"Close  ×" target:actions action:@selector(close:)];close.frame=NSMakeRect(width-112,26,88,28);close.bezelStyle=NSBezelStyleRounded;[view addSubview:close];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,80,width,height-122)];scroll.drawsBackground=NO;scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;
    OverviewSurface *content=[[OverviewSurface alloc] initWithFrame:NSMakeRect(0,0,width,MAX(contentHeight,height-122))];cards=NSMutableArray.new;
    // Card array preserves stable flat indexing even when monitor sections reorder.
    for(NSUInteger i=0;i<spaces.count;i++)[cards addObject:(id)NSNull.null];
    CGFloat y=0;
    for(NSDictionary *group in displayGroups){
        DisplayDropZone *zone=[[DisplayDropZone alloc] initWithFrame:NSMakeRect(28,y+8,width-56,44)];zone.targetScreen=group[@"screen"];
        NSScreen *target=group[@"screen"];zone.titleText=[NSString stringWithFormat:@"%@   ·   %.0f × %.0f%@   ·   Drop here to move",group[@"name"],target.frame.size.width,target.frame.size.height,target==NSScreen.mainScreen ? @"   ·   Main" : @""];
        [content addSubview:zone];NSArray *indexes=group[@"indexes"];
        for(NSUInteger n=0;n<indexes.count;n++){NSUInteger i=[indexes[n] unsignedIntegerValue];NSRect frame=cardFrame(n,columns,width);frame.origin.y+=y-16;
            SpaceCard *card=[[SpaceCard alloc] initWithFrame:frame];card.index=i;card.target=card;card.action=@selector(choose:);card.accessibilityLabel=spaces[i][@"title"];[content addSubview:card];cards[i]=card;}
        if(!indexes.count)heading(content,@"No open windows — empty desktops are hidden. Drop a window here to use this display.",NSMakeRect(40,y+82,width-80,30),12,0x94a3b8);
        y+=72+MAX(1,ceil(indexes.count/3.0))*204;
    }
    if(!displayGroups.count){overviewError=@"spaces_unavailable";heading(content,@"Display map is unavailable. Close and retry.",NSMakeRect(28,30,width-56,24),14,0x94a3b8);}
    scroll.documentView=content;[view addSubview:scroll];
    feedback=[NSTextField labelWithString:@"← →  Select    Return  Switch    1–9  Jump    Esc / three-finger down  Close"];
    feedback.frame=NSMakeRect(28,height-30,width-56,18);feedback.font=[NSFont systemFontOfSize:11];feedback.textColor=DFPanelColor(0x94a3b8);[view addSubview:feedback];
    openedAt=NSProcessInfo.processInfo.systemUptime;DFPanelPresent(panel);
    NSUInteger focusToken=revision;
    dispatch_async(dispatch_get_main_queue(),^{
        if(focusToken!=revision || !panel.visible)return;
        [panel makeKeyAndOrderFront:nil];[panel makeFirstResponder:panel.contentView];
    });
    outsideMonitor=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown handler:^(__unused NSEvent *event){if(!NSPointInRect(NSEvent.mouseLocation,panel.frame))DFOverviewHide();}];
    if(!CGPreflightScreenCaptureAccess())return;
    NSUInteger token=revision;
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:NO completionHandler:^(SCShareableContent *content,__unused NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(token!=revision || !panel.visible)return;
            for(NSMutableDictionary *entry in spaces){
                for(SCWindow *window in content.windows){
                    if(window.windowLayer!=0 || window.frame.size.width<80 || window.frame.size.height<60 || window.owningApplication.processID==getpid())continue;
                    BOOL matches=[entry[@"window_id"] unsignedIntValue]==window.windowID;
                    if(!entry[@"window_id"] && copyWindowSpaces){NSArray *membership=CFBridgingRelease(copyWindowSpaces(connectionID(),7,(__bridge CFArrayRef)@[@(window.windowID)]));matches=[membership containsObject:entry[@"ManagedSpaceID"]];}
                    if(matches){entry[@"capture"]=window;NSRunningApplication *app=[NSRunningApplication runningApplicationWithProcessIdentifier:window.owningApplication.processID];if(app)entry[@"app"]=app;break;}
                }
            }redrawSelection();
        });
    }];
}
void DFOverviewHide(void) {
    revision++;[panel orderOut:nil];panel.contentView=nil;spaces=nil;cards=nil;displayGroups=nil;feedback=nil;afterSwitch=nil;images=0;capturePending=NO;switching=NO;overviewError=nil;selection=0;
    if(outsideMonitor){[NSEvent removeMonitor:outsideMonitor];outsideMonitor=nil;}
}
void DFOverviewKeyCode(unsigned short code) {
    if(!panel.visible && !switching)return;
    unsigned short digits[]={18,19,20,21,23,22,26,28,25};NSString *characters=@"";
    for(NSUInteger i=0;i<9;i++)if(code==digits[i])characters=[NSString stringWithFormat:@"%lu",(unsigned long)i+1];
    NSEvent *event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:panel.windowNumber context:nil characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
    [panel keyDown:event];
}
void DFOverviewTick(void) {
    if(!panel.visible)return;
    if(NSProcessInfo.processInfo.systemUptime-openedAt>120){DFOverviewHide();return;}
    if(capturePending)return;
    for(NSUInteger i=0;i<spaces.count;i++){
        NSMutableDictionary *entry=spaces[i];SCWindow *window=entry[@"capture"];if(!window || entry[@"attempted"])continue;
        entry[@"attempted"]=@YES;capturePending=YES;NSUInteger token=revision;
        SCStreamConfiguration *config=SCStreamConfiguration.new;CGFloat scale=MIN(1,MIN(560/window.frame.size.width,280/window.frame.size.height));
        config.width=MAX(1,lround(window.frame.size.width*scale));config.height=MAX(1,lround(window.frame.size.height*scale));config.showsCursor=NO;
        [SCScreenshotManager captureImageWithFilter:[[SCContentFilter alloc] initWithDesktopIndependentWindow:window] configuration:config completionHandler:^(CGImageRef image,__unused NSError *error){
            NSImage *thumbnail=image ? [[NSImage alloc] initWithCGImage:image size:NSZeroSize] : nil;
            dispatch_async(dispatch_get_main_queue(),^{if(token!=revision)return;capturePending=NO;if(thumbnail){entry[@"image"]=thumbnail;images++;}redrawSelection();});
        }];break;
    }
}
NSDictionary *DFOverviewStatus(void) {
    return @{@"key":@(panel.keyWindow),@"selected":@(selection),@"visible":@(panel.visible || switching),@"spaces":@(spaces.count),@"displays":@(displayGroups.count),@"thumbnails":@(images),@"switching":@(switching),@"error":overviewError ?: @""};
}
int DFOverviewSelfTest(void) {
    if(includeSpace(@{@"ManagedSpaceID":@1,@"fullscreen":@NO},[NSSet set])
       || !includeSpace(@{@"ManagedSpaceID":@1,@"fullscreen":@NO},[NSSet setWithObject:@1])
       || !includeSpace(@{@"ManagedSpaceID":@1,@"fullscreen":@YES},[NSSet set]))return 1;
    NSArray *list=@[@{@"ManagedSpaceID":@19},@{@"ManagedSpaceID":@42},@{@"ManagedSpaceID":@7}];
    if(spaceIndex(list,@42)!=1 || spaceIndex(list,@6)!=NSNotFound || spaceIndex(@[],@42)!=NSNotFound)return 1;
    for(NSUInteger columns=1;columns<=3;columns++)for(NSUInteger i=0;i<48;i++){
        NSRect rect=cardFrame(i,columns,800);if(NSMinX(rect)<28 || NSMaxX(rect)>772.01 || rect.size.width<1)return 1;
    }
    for(NSValue *value in @[[NSValue valueWithRect:NSMakeRect(-1920,0,1920,1080)], [NSValue valueWithRect:NSMakeRect(0,-1080,1920,1080)], [NSValue valueWithRect:NSMakeRect(2056,0,1280,720)]]){
        CGRect display=NSRectToCGRect(value.rectValue),destination=destinationRect(display,CGSizeMake(2400,1800));
        if(!CGRectContainsRect(display,destination))return 1;
    }
    CGRect retained=destinationRect(CGRectMake(-1920,0,1920,1080),CGSizeMake(640,480));if(retained.size.width!=640 || retained.size.height!=480)return 1;
    puts("Overview: Space identity, empty Desktop filtering, grid and multi-monitor move geometry passed.");return 0;
}
