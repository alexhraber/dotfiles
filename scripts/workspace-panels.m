#import "workspace-panels.h"
#import "control-panel.h"
#import "panel-style.h"
#import <ApplicationServices/ApplicationServices.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdatomic.h>

// Window references, titles and thumbnail pixels are session memory only.
static NSString *workspaceDirectory,*workspaceRequest,*workspaceKind;
static NSPanel *workspacePanel;
static NSRect workspaceAnchor;
static _Atomic(NSUInteger) generation;
static NSUInteger focusCount;
static dispatch_queue_t windowQueue;
static double awaySince;
static NSMutableArray<NSMutableDictionary *> *windowEntries;
static NSArray<NSDictionary *> *applicationEntries,*filteredApplications;
static NSUInteger selectedApplication;
static NSScrollView *windowScroll;
static NSMutableArray<NSButton *> *windowButtons;
static NSTextField *searchField;
static id mouseMonitor,keyMonitor;
static BOOL capturePending;
static NSString *workspaceError;
static NSUInteger scannedWindows,scannedRoles,scannedFrames;
static AXError scanError;

static id attribute(id element,CFStringRef key) {
    CFTypeRef result=NULL;
    if (!element || AXUIElementCopyAttributeValue((__bridge AXUIElementRef)element,key,&result)!=kAXErrorSuccess) return nil;
    return CFBridgingRelease(result);
}
static NSArray *appWindows(id root) {
    id result=attribute(root,kAXWindowsAttribute);
    return [result isKindOfClass:NSArray.class] ? result : @[];
}
static BOOL windowRect(id element,CGRect *rect) {
    id position=attribute(element,kAXPositionAttribute),size=attribute(element,kAXSizeAttribute);
    CGPoint point;CGSize dimensions;
    if (!position || !size || CFGetTypeID((__bridge CFTypeRef)position)!=AXValueGetTypeID()
        || CFGetTypeID((__bridge CFTypeRef)size)!=AXValueGetTypeID()
        || !AXValueGetValue((__bridge AXValueRef)position,kAXValueCGPointType,&point)
        || !AXValueGetValue((__bridge AXValueRef)size,kAXValueCGSizeType,&dimensions)
        || !isfinite(point.x) || !isfinite(point.y) || !isfinite(dimensions.width) || !isfinite(dimensions.height)
        || dimensions.width<80 || dimensions.height<60) return NO;
    *rect=CGRectMake(point.x,point.y,dimensions.width,dimensions.height);return YES;
}
static BOOL sameRect(CGRect a,CGRect b) {
    return fabs(a.origin.x-b.origin.x)<3 && fabs(a.origin.y-b.origin.y)<3
        && fabs(a.size.width-b.size.width)<3 && fabs(a.size.height-b.size.height)<3;
}
static NSRect placePreview(NSRect screen,NSRect anchor,CGFloat width,CGFloat height) {
    width=MIN(width,screen.size.width-24);height=MIN(height,screen.size.height-100);
    return NSMakeRect(MAX(NSMinX(screen)+12,MIN(NSMidX(anchor)-width/2,NSMaxX(screen)-width-12)),
        MAX(NSMinY(screen)+100,MIN(NSMaxY(anchor)+12,NSMaxY(screen)-height-12)),width,height);
}
static NSTextField *label(NSView *view,NSString *text,NSRect frame,CGFloat size,BOOL strong,unsigned color) {
    NSTextField *field=[NSTextField labelWithString:text ?: @""];
    field.frame=frame;field.font=[NSFont systemFontOfSize:size weight:strong ? NSFontWeightSemibold : NSFontWeightRegular];
    field.textColor=DFPanelColor(color);field.lineBreakMode=NSLineBreakByTruncatingTail;
    field.tag=color;[view addSubview:field];return field;
}
@interface WorkspaceSurface : NSView
@end
@implementation WorkspaceSurface
- (BOOL)isFlipped {return YES;}
- (void)drawRect:(__unused NSRect)rect {
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:16 yRadius:16];
    [DFPanelColor(0x11151d) setFill];[shape fill];[DFPanelColor(0x2a3447) setStroke];shape.lineWidth=1;[shape stroke];
    [[DFPanelColor(0xb8a6ff) colorWithAlphaComponent:.65] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(24,0,24,2) xRadius:1 yRadius:1] fill];
}
@end
@interface WorkspacePanel : NSPanel
@end
@implementation WorkspacePanel
- (BOOL)canBecomeKeyWindow {return [workspaceKind isEqual:@"launcher"];}
- (void)keyDown:(NSEvent *)event {if (event.keyCode==53) DFWorkspaceHide();else [super keyDown:event];}
@end
static WorkspaceSurface *surface;
static void createPanel(void) {
    if (workspacePanel) return;
    workspacePanel=[[WorkspacePanel alloc] initWithContentRect:NSMakeRect(0,0,500,240)
        styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    DFPanelPrepare(workspacePanel);
    workspacePanel.level=CGWindowLevelForKey(kCGStatusWindowLevelKey)+3;
    workspacePanel.opaque=NO;workspacePanel.backgroundColor=NSColor.clearColor;workspacePanel.hasShadow=YES;
    surface=[[WorkspaceSurface alloc] initWithFrame:workspacePanel.contentView.bounds];workspacePanel.contentView=surface;
}
static void clearSurface(void) {
    for (NSView *view in surface.subviews.copy) [view removeFromSuperview];
    windowScroll=nil;windowButtons=nil;searchField=nil;
}
static void focusWindow(NSDictionary *entry) {
    NSRunningApplication *app=entry[@"app"];id window=entry[@"window"];
    pid_t pid=0;
    if (app.terminated || AXUIElementGetPid((__bridge AXUIElementRef)window,&pid)!=kAXErrorSuccess || pid!=app.processIdentifier) return;
    id root=CFBridgingRelease(AXUIElementCreateApplication(pid));AXUIElementSetMessagingTimeout((__bridge AXUIElementRef)root,.25);
    BOOL found=NO;for (id current in appWindows(root)) if (CFEqual((__bridge CFTypeRef)current,(__bridge CFTypeRef)window)) {found=YES;break;}
    if (!found) {workspaceError=@"window_closed";return;}
    [app unhide];
    if ([attribute(window,kAXMinimizedAttribute) boolValue])
        AXUIElementSetAttributeValue((__bridge AXUIElementRef)window,kAXMinimizedAttribute,kCFBooleanFalse);
    [app activateWithOptions:0];
    AXUIElementSetAttributeValue((__bridge AXUIElementRef)window,kAXMainAttribute,kCFBooleanTrue);
    AXError result=AXUIElementPerformAction((__bridge AXUIElementRef)window,kAXRaiseAction);
    if (result==kAXErrorSuccess) {focusCount++;DFWorkspaceHide();}
    else workspaceError=@"focus_unavailable";
}
@interface WindowCard : DFPanelButton
@property NSMutableDictionary *entry;
@end
@implementation WindowCard
- (BOOL)isFlipped {return YES;}
- (void)drawRect:(__unused NSRect)rect {
    NSRect imageRect=NSMakeRect(8,8,self.bounds.size.width-16,126);
    NSBezierPath *clip=[NSBezierPath bezierPathWithRoundedRect:imageRect xRadius:9 yRadius:9];
    [NSGraphicsContext saveGraphicsState];[clip addClip];
    [[DFPanelColor(0x202735) colorWithAlphaComponent:.45] setFill];NSRectFill(imageRect);
    NSImage *image=self.entry[@"image"];
    if (image) {
        CGFloat scale=MIN(imageRect.size.width/image.size.width,imageRect.size.height/image.size.height);
        NSRect fitted=NSMakeRect(NSMidX(imageRect)-image.size.width*scale/2,NSMidY(imageRect)-image.size.height*scale/2,image.size.width*scale,image.size.height*scale);
        [image drawInRect:fitted fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    } else {
        NSImage *icon=[self.entry[@"app"] icon];
        [icon drawInRect:NSMakeRect(NSMidX(imageRect)-24,NSMidY(imageRect)-24,48,48) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:.8 respectFlipped:YES hints:nil];
    }
    [NSGraphicsContext restoreGraphicsState];
    NSMutableParagraphStyle *paragraph=NSMutableParagraphStyle.new;paragraph.lineBreakMode=NSLineBreakByTruncatingTail;
    [self.entry[@"title"] drawInRect:NSMakeRect(10,143,self.bounds.size.width-20,17) withAttributes:
        @{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium],NSForegroundColorAttributeName:DFPanelColor(0xe6edf7),NSParagraphStyleAttributeName:paragraph}];
    NSString *detail=self.hovered ? @"Open window" : [self.entry[@"minimized"] boolValue] ? @"Minimized"
        : [self.entry[@"fullscreen"] boolValue] ? @"Full screen" : @"Window";
    [detail drawAtPoint:NSMakePoint(10,165) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName:DFPanelColor(self.hovered ? 0xb8a6ff : 0x94a3b8)}];
}
- (void)choose:(__unused id)sender {focusWindow(self.entry);}
@end
static void renderDock(NSRunningApplication *app,NSMutableArray *entries) {
    windowEntries=entries;
    createPanel();clearSurface();
    NSScreen *screen=NSScreen.mainScreen;
    for (NSScreen *candidate in NSScreen.screens) if (NSIntersectsRect(candidate.frame,workspaceAnchor)) {screen=candidate;break;}
    CGFloat cardWidth=220,width=MIN(screen.frame.size.width-32,MIN(4,windowEntries.count)*cardWidth+32);
    [workspacePanel setFrame:placePreview(screen.frame,workspaceAnchor,width,256) display:NO];surface.frame=workspacePanel.contentView.bounds;
    label(surface,app.localizedName,NSMakeRect(24,15,width-120,22),14,YES,0xe6edf7);
    label(surface,[NSString stringWithFormat:@"%lu %@",(unsigned long)windowEntries.count,windowEntries.count==1 ? @"window" : @"windows"],NSMakeRect(width-102,19,86,18),10,NO,0x94a3b8);
    windowScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(12,48,width-24,198)];
    windowScroll.drawsBackground=NO;windowScroll.hasHorizontalScroller=YES;windowScroll.autohidesScrollers=YES;
    windowScroll.scrollerStyle=NSScrollerStyleOverlay;
    NSView *content=[[NSView alloc] initWithFrame:NSMakeRect(0,0,windowEntries.count*cardWidth,190)];
    windowButtons=NSMutableArray.new;
    for (NSUInteger i=0;i<windowEntries.count;i++) {
        WindowCard *button=[[WindowCard alloc] initWithFrame:NSMakeRect(i*cardWidth,0,cardWidth-8,190)];button.entry=windowEntries[i];
        button.target=button;button.action=@selector(choose:);button.accessibilityLabel=windowEntries[i][@"title"];
        button.toolTip=windowEntries[i][@"title"];[content addSubview:button];[windowButtons addObject:button];
    }
    windowScroll.documentView=content;[surface addSubview:windowScroll];DFPanelPresent(workspacePanel);
    if (!CGPreflightScreenCaptureAccess()) return;
    NSUInteger current=generation;
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:NO completionHandler:^(SCShareableContent *shareable,__unused NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{
            if (generation!=current || !workspacePanel.visible) return;
            for (NSMutableDictionary *entry in windowEntries) {
                NSMutableArray *matches=NSMutableArray.new;CGRect bounds=[entry[@"bounds"] rectValue];
                for (SCWindow *window in shareable.windows) {
                    if (window.owningApplication.processID!=app.processIdentifier || window.windowLayer!=0 || !sameRect(bounds,window.frame)) continue;
                    if (window.title.length && ![window.title isEqual:entry[@"title"]]) continue;
                    [matches addObject:window];
                }
                if (matches.count==1) entry[@"capture"]=matches.firstObject;
            }
        });
    }];
}
static void showDock(NSDictionary *request) {
    NSRunningApplication *app=[NSRunningApplication runningApplicationWithProcessIdentifier:[request[@"pid"] intValue]];
    if (!app || app.terminated || app.activationPolicy!=NSApplicationActivationPolicyRegular || !AXIsProcessTrusted()) return;
    createPanel();clearSurface();NSScreen *screen=NSScreen.mainScreen;
    for (NSScreen *candidate in NSScreen.screens) if (NSIntersectsRect(candidate.frame,workspaceAnchor)) {screen=candidate;break;}
    [workspacePanel setFrame:placePreview(screen.frame,workspaceAnchor,320,256) display:NO];surface.frame=workspacePanel.contentView.bounds;
    label(surface,app.localizedName,NSMakeRect(24,18,272,22),14,YES,0xe6edf7);
    label(surface,@"Reading windows…",NSMakeRect(24,64,272,24),12,NO,0x94a3b8);DFPanelPresent(workspacePanel);
    NSUInteger current=generation;
    dispatch_async(windowQueue,^{
        if (generation!=current) return;
        id root=CFBridgingRelease(AXUIElementCreateApplication(app.processIdentifier));
        AXUIElementSetMessagingTimeout((__bridge AXUIElementRef)root,.12);
        NSMutableArray *entries=NSMutableArray.new;double deadline=NSProcessInfo.processInfo.systemUptime+1.5;
        // A just-launched AppKit app can initially expose an empty AX window
        // list while its accessibility tree initializes. Retry only this read;
        // never retry a window action, and keep the whole scan bounded.
        CFTypeRef windowList=NULL;
        AXError readError=AXUIElementCopyAttributeValue((__bridge AXUIElementRef)root,kAXWindowsAttribute,&windowList);
        id value=CFBridgingRelease(windowList);
        NSArray *windows=[value isKindOfClass:NSArray.class] ? value : @[];
        for (NSUInteger attempt=0;!windows.count && attempt<4 && generation==current
             && NSProcessInfo.processInfo.systemUptime<deadline;attempt++) {
            [NSThread sleepForTimeInterval:.05];windows=appWindows(root);
        }
        if (windows.count) readError=kAXErrorSuccess;
        NSUInteger roles=0,frames=0;
        for (id window in windows) {
            if (entries.count>=32 || generation!=current || NSProcessInfo.processInfo.systemUptime>deadline) break;
            AXUIElementSetMessagingTimeout((__bridge AXUIElementRef)window,.12);
            if (![attribute(window,kAXRoleAttribute) isEqual:@"AXWindow"]) continue;
            roles++;
            CGRect bounds;if (!windowRect(window,&bounds)) continue;
            frames++;
            id title=attribute(window,kAXTitleAttribute);
            if (![title isKindOfClass:NSString.class] || ![title length]) title=app.localizedName ?: @"Window";
            if ([title length]>256) title=[title substringToIndex:256];
            [entries addObject:[@{@"window":window,@"app":app,@"title":title,@"bounds":[NSValue valueWithRect:NSRectFromCGRect(bounds)],
                @"minimized":@([attribute(window,kAXMinimizedAttribute) boolValue]),
                @"fullscreen":@([attribute(window,CFSTR("AXFullScreen")) boolValue])} mutableCopy]];
        }
        dispatch_async(dispatch_get_main_queue(),^{
            if (generation!=current || !workspacePanel.visible) return;
            scannedWindows=windows.count;scannedRoles=roles;scannedFrames=frames;scanError=readError;
            if (readError!=kAXErrorSuccess) workspaceError=@"window_list_unavailable";
            if (entries.count) renderDock(app,entries);
            else {
                clearSurface();label(surface,app.localizedName,NSMakeRect(24,18,272,22),14,YES,0xe6edf7);
                label(surface,readError==kAXErrorSuccess ? @"No windows to preview" : @"Window previews unavailable",NSMakeRect(24,64,272,24),12,NO,0x94a3b8);
                label(surface,@"Click its dock icon to open the app.",NSMakeRect(24,96,272,24),11,NO,0x94a3b8);
            }
        });
    });
}

static NSInteger applicationScore(NSString *name,NSString *query) {
    NSString *normalized=[name stringByFoldingWithOptions:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch locale:NSLocale.currentLocale];
    normalized=normalized.lowercaseString;query=[query stringByFoldingWithOptions:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch locale:NSLocale.currentLocale].lowercaseString;
    for (NSString *word in [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet])
        if (word.length && ![normalized containsString:word]) return -1;
    return !query.length ? 2 : [normalized hasPrefix:query] ? 0 : 1;
}
@interface ApplicationRow : DFPanelButton
@property NSDictionary *entry;
@property BOOL chosen;
@end
static void chooseApplication(NSDictionary *entry) {
    NSURL *url=entry[@"url"];if (![url.pathExtension.lowercaseString isEqual:@"app"]) return;
    NSWorkspaceOpenConfiguration *configuration=NSWorkspaceOpenConfiguration.configuration;
    configuration.activates=YES;configuration.createsNewApplicationInstance=NO;configuration.addsToRecentItems=NO;
    NSUInteger current=generation;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:configuration completionHandler:^(__unused NSRunningApplication *app,NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{
            if (generation!=current) return;
            if (error) workspaceError=@"launch_unavailable";else DFWorkspaceHide();
        });
    }];
}
@implementation ApplicationRow
- (BOOL)isFlipped {return YES;}
- (void)drawRect:(__unused NSRect)rect {
    if (self.chosen && !self.hovered) {
        [[DFPanelColor(0x202735) colorWithAlphaComponent:.7] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:7 yRadius:7] fill];
    }
    NSImage *icon=[NSWorkspace.sharedWorkspace iconForFile:[self.entry[@"url"] path]];
    [icon drawInRect:NSMakeRect(12,8,24,24) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    [self.entry[@"name"] drawAtPoint:NSMakePoint(48,12) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium],NSForegroundColorAttributeName:DFPanelColor(0xe6edf7)}];
    if (self.hovered || self.chosen) [@"Open" drawAtPoint:NSMakePoint(self.bounds.size.width-50,14) withAttributes:
        @{NSFontAttributeName:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium],NSForegroundColorAttributeName:DFPanelColor(0xb8a6ff)}];
}
- (void)choose:(__unused id)sender {chooseApplication(self.entry);}
@end
@interface ApplicationSearch : NSObject<NSTextFieldDelegate>
@end
static ApplicationSearch *searchDelegate;
static void renderApplications(BOOL preserveSelection) {
    if (!searchField) return;
    NSString *query=[searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *matches=NSMutableArray.new;
    for (NSDictionary *entry in applicationEntries) if (applicationScore(entry[@"name"],query)>=0) [matches addObject:entry];
    [matches sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        NSInteger first=applicationScore(a[@"name"],query),second=applicationScore(b[@"name"],query);
        return first==second ? [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]] : first<second ? NSOrderedAscending : NSOrderedDescending;
    }];
    filteredApplications=[matches subarrayWithRange:NSMakeRange(0,MIN(8,matches.count))];
    // Keep the search's top edge fixed while removing unused result space.
    CGFloat height=126+MAX((NSUInteger)1,filteredApplications.count)*42;
    NSRect frame=workspacePanel.frame;frame.origin.y+=frame.size.height-height;frame.size.height=height;
    [workspacePanel setFrame:frame display:NO];surface.frame=workspacePanel.contentView.bounds;
    for (NSView *view in surface.subviews) if ([view.identifier isEqual:@"launcher-footer"])
        view.frame=NSMakeRect(24,height-24,472,16);
    selectedApplication=preserveSelection && filteredApplications.count ? MIN(selectedApplication,filteredApplications.count-1) : 0;
    for (NSView *view in surface.subviews.copy) if (view.tag==701) [view removeFromSuperview];
    for (NSUInteger i=0;i<filteredApplications.count;i++) {
        ApplicationRow *row=[[ApplicationRow alloc] initWithFrame:NSMakeRect(12,94+i*42,496,40)];row.tag=701;
        row.entry=filteredApplications[i];row.chosen=i==selectedApplication;row.target=row;row.action=@selector(choose:);
        row.accessibilityLabel=row.entry[@"name"];[surface addSubview:row];
    }
    if (!filteredApplications.count) {
        NSTextField *empty=label(surface,applicationEntries ? @"No matching applications" : @"Finding applications…",NSMakeRect(24,106,470,30),12,NO,0x94a3b8);empty.tag=701;
    }
}
@implementation ApplicationSearch
- (void)controlTextDidChange:(__unused NSNotification *)notification {renderApplications(NO);}
- (BOOL)control:(__unused NSControl *)control textView:(__unused NSTextView *)view doCommandBySelector:(SEL)selector {
    if (selector==@selector(cancelOperation:)) {DFWorkspaceHide();return YES;}
    if (selector==@selector(insertNewline:)) {if (filteredApplications.count) chooseApplication(filteredApplications[selectedApplication]);return YES;}
    if (selector==@selector(moveDown:) || selector==@selector(moveUp:)) {
        if (filteredApplications.count) {
            NSInteger delta=selector==@selector(moveDown:) ? 1 : -1;
            selectedApplication=(selectedApplication+filteredApplications.count+delta)%filteredApplications.count;renderApplications(YES);
        }
        return YES;
    }
    return NO;
}
@end
static NSArray *discoverApplications(void) {
    NSMutableDictionary *found=NSMutableDictionary.new;
    NSArray *roots=@[@"/Applications",[NSHomeDirectory() stringByAppendingPathComponent:@"Applications"],@"/System/Applications",@"/System/Applications/Utilities"];
    for (NSString *root in roots) {
        NSArray *urls=[NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:root] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
        for (NSURL *url in urls) {
            if (![url.pathExtension.lowercaseString isEqual:@"app"] || found.count>=512) continue;
            NSBundle *bundle=[NSBundle bundleWithURL:url];NSString *name=bundle.infoDictionary[@"CFBundleDisplayName"] ?: bundle.infoDictionary[@"CFBundleName"] ?: url.lastPathComponent.stringByDeletingPathExtension;
            if (![name isKindOfClass:NSString.class] || !name.length || name.length>128) continue;
            NSString *key=bundle.bundleIdentifier ?: url.path;
            if (!found[key]) found[key]=@{@"name":name,@"url":url};
        }
    }
    return found.allValues;
}
static void showLauncher(void) {
    createPanel();clearSurface();windowEntries=nil;filteredApplications=nil;selectedApplication=0;
    NSScreen *screen=NSScreen.mainScreen;NSPoint pointer=NSEvent.mouseLocation;
    for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(pointer,candidate.frame)) {screen=candidate;break;}
    NSRect frame=NSMakeRect(NSMidX(screen.visibleFrame)-260,NSMidY(screen.visibleFrame)-190,520,462);
    [workspacePanel setFrame:frame display:NO];surface.frame=workspacePanel.contentView.bounds;
    label(surface,@"APPLICATIONS",NSMakeRect(24,16,470,18),10,YES,0x94a3b8);
    searchField=[[NSTextField alloc] initWithFrame:NSMakeRect(24,42,472,34)];searchField.font=[NSFont systemFontOfSize:22 weight:NSFontWeightMedium];
    searchField.textColor=DFPanelColor(0xe6edf7);searchField.tag=0xe6edf7;searchField.backgroundColor=NSColor.clearColor;
    searchField.drawsBackground=NO;searchField.bordered=NO;searchField.focusRingType=NSFocusRingTypeNone;
    searchField.placeholderAttributedString=[[NSAttributedString alloc] initWithString:@"Search applications" attributes:@{NSForegroundColorAttributeName:DFPanelColor(0x94a3b8)}];
    searchField.accessibilityLabel=@"Search applications";
    if (!searchDelegate) searchDelegate=ApplicationSearch.new;
    searchField.delegate=searchDelegate;[surface addSubview:searchField];
    label(surface,@"↑ ↓  Choose     Return  Open     Esc  Close",NSMakeRect(24,438,472,16),10,NO,0x94a3b8).identifier=@"launcher-footer";
    renderApplications(NO);DFPanelPresent(workspacePanel);[workspacePanel makeKeyWindow];[workspacePanel makeFirstResponder:searchField];
    NSTextView *editor=(NSTextView *)[workspacePanel fieldEditor:YES forObject:searchField];
    editor.insertionPointColor=DFPanelColor(0xb8a6ff);editor.selectedTextAttributes=@{NSBackgroundColorAttributeName:DFPanelColor(0x7c5cff),NSForegroundColorAttributeName:DFPanelColor(0xe6edf7)};
    NSUInteger current=generation;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSArray *entries=discoverApplications();
        dispatch_async(dispatch_get_main_queue(),^{if (generation==current && workspacePanel.visible) {applicationEntries=entries;renderApplications(NO);}});
    });
}
static NSDictionary *readRequest(void) {
    NSString *path=[workspaceDirectory stringByAppendingPathComponent:@"bar/workspace-request.json"];
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);if (fd<0) return nil;
    struct stat status;BOOL safe=fstat(fd,&status)==0 && S_ISREG(status.st_mode) && status.st_uid==getuid()
        && !(status.st_mode&0077) && status.st_size>0 && status.st_size<4096;
    NSData *data=safe ? [[[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES] readDataToEndOfFile] : nil;if (!safe) close(fd);
    id request=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![request isKindOfClass:NSDictionary.class] || ![request[@"request"] isKindOfClass:NSString.class]
        || ![request[@"request"] length] || [request[@"request"] length]>64 || ![@[@"dock",@"launcher"] containsObject:request[@"kind"]]
        || ![request[@"updated"] isKindOfClass:NSNumber.class] || ![request[@"pid"] isKindOfClass:NSNumber.class]
        || ([request[@"kind"] isEqual:@"dock"] && ([request[@"pid"] longLongValue]<=0 || [request[@"pid"] longLongValue]>INT_MAX))
        || ![request[@"anchor"] isKindOfClass:NSArray.class] || [request[@"anchor"] count]!=4) return nil;
    double age=NSDate.date.timeIntervalSince1970-[request[@"updated"] doubleValue];
    if (!isfinite(age) || age<0 || age>3) return nil;
    for (id number in request[@"anchor"]) if (![number isKindOfClass:NSNumber.class] || !isfinite([number doubleValue]) || fabs([number doubleValue])>100000) return nil;
    return request;
}
void DFWorkspaceShow(void) {
    NSDictionary *request=readRequest();if (!request || [request[@"request"] isEqual:workspaceRequest]) return;
    DFWorkspaceHide();DFControlsHide();workspaceRequest=request[@"request"];workspaceKind=request[@"kind"];
    NSArray *a=request[@"anchor"];workspaceAnchor=NSMakeRect([a[0] doubleValue],[a[1] doubleValue],[a[2] doubleValue],[a[3] doubleValue]);
    if ([workspaceKind isEqual:@"dock"]) showDock(request);else showLauncher();
}
void DFWorkspaceHide(void) {
    generation++;[workspacePanel orderOut:nil];windowEntries=nil;windowButtons=nil;windowScroll=nil;
    filteredApplications=nil;searchField=nil;capturePending=NO;awaySince=0;workspaceError=nil;
    scannedWindows=0;scannedRoles=0;scannedFrames=0;scanError=kAXErrorSuccess;
    clearSurface();
}
void DFWorkspaceInitialize(NSString *directory) {
    workspaceDirectory=directory;
    windowQueue=dispatch_queue_create("local.dotfiles.desktop.window-list",DISPATCH_QUEUE_SERIAL);
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:@"local.dotfiles.desktop.workspace" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if ([note.object isEqual:@"show"]) DFWorkspaceShow();else if ([note.object isEqual:@"hide"]) DFWorkspaceHide();
    }];
    mouseMonitor=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown handler:^(__unused NSEvent *event) {
        if (workspacePanel.visible && !NSPointInRect(NSEvent.mouseLocation,workspacePanel.frame) && !NSPointInRect(NSEvent.mouseLocation,workspaceAnchor)) DFWorkspaceHide();
    }];
    keyMonitor=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^(NSEvent *event) {if (event.keyCode==53) DFWorkspaceHide();}];
}
void DFWorkspaceTick(double now,NSPoint pointer) {
    if (!workspacePanel.visible) return;
    if ([workspaceKind isEqual:@"dock"]) {
        NSRect bridge=NSUnionRect(workspaceAnchor,NSMakeRect(workspaceAnchor.origin.x,NSMinY(workspacePanel.frame)-12,workspaceAnchor.size.width,24));
        if (NSPointInRect(pointer,NSInsetRect(workspacePanel.frame,-6,-6)) || NSPointInRect(pointer,NSInsetRect(bridge,-8,-8))) awaySince=0;
        else {if (!awaySince) awaySince=now;if (now-awaySince>.32) {DFWorkspaceHide();return;}}
        if (capturePending) return;
        NSRect visible=windowScroll.contentView.bounds;
        for (NSUInteger i=0;i<windowEntries.count;i++) {
            NSMutableDictionary *entry=windowEntries[i];NSButton *button=windowButtons[i];
            if (!NSIntersectsRect(button.frame,visible)) {
                if (entry[@"image"]) {[entry removeObjectForKey:@"image"];[entry removeObjectForKey:@"attempted"];}
                continue;
            }
            SCWindow *window=entry[@"capture"];
            if (!window || entry[@"image"] || [entry[@"attempted"] boolValue] || [entry[@"minimized"] boolValue]) continue;
            capturePending=YES;entry[@"attempted"]=@YES;NSUInteger current=generation;
            CGFloat scale=MIN(1,MIN(440/MAX(1,window.frame.size.width),280/MAX(1,window.frame.size.height)));
            SCStreamConfiguration *configuration=SCStreamConfiguration.new;
            configuration.width=MAX(1,lround(window.frame.size.width*scale));configuration.height=MAX(1,lround(window.frame.size.height*scale));configuration.showsCursor=NO;
            SCContentFilter *filter=[[SCContentFilter alloc] initWithDesktopIndependentWindow:window];
            [SCScreenshotManager captureImageWithFilter:filter configuration:configuration completionHandler:^(CGImageRef image,__unused NSError *error) {
                NSImage *thumbnail=image ? [[NSImage alloc] initWithCGImage:image size:NSZeroSize] : nil;
                dispatch_async(dispatch_get_main_queue(),^{
                    if (generation!=current || !workspacePanel.visible) return;
                    capturePending=NO;if (thumbnail) entry[@"image"]=thumbnail;button.needsDisplay=YES;
                });
            }];break;
        }
    }
}
static void restyle(NSView *view) {
    if ([view isKindOfClass:NSTextField.class] && view.tag>1000)
        ((NSTextField *)view).textColor=DFPanelColor((unsigned)view.tag);
    view.needsDisplay=YES;for (NSView *child in view.subviews) restyle(child);
}
void DFWorkspaceRefreshAppearance(void) {
    restyle(surface);
    if (searchField) searchField.placeholderAttributedString=[[NSAttributedString alloc] initWithString:@"Search applications" attributes:@{NSForegroundColorAttributeName:DFPanelColor(0x94a3b8)}];
}
NSDictionary *DFWorkspaceStatus(void) {
    NSUInteger thumbnails=0;for (NSDictionary *entry in windowEntries) if (entry[@"image"]) thumbnails++;
    NSRect f=workspacePanel.frame;
    return @{@"visible":@(workspacePanel.visible),@"kind":workspaceKind ?: @"",@"request":workspaceRequest ?: @"",
        @"frame":@[@(f.origin.x),@(f.origin.y),@(f.size.width),@(f.size.height)],@"windows":@(windowEntries.count),
        @"thumbnails":@(thumbnails),@"focus_count":@(focusCount),@"applications":@(applicationEntries.count),
        @"key":@(workspacePanel.keyWindow),@"matches":@(filteredApplications.count),@"query_length":@(searchField.stringValue.length),@"error":workspaceError ?: @"",
        @"scan":@{@"listed":@(scannedWindows),@"roles":@(scannedRoles),@"frames":@(scannedFrames),@"error":@(scanError)}};
}
int DFWorkspaceSelfTest(void) {
    if (!sameRect(CGRectMake(0,0,300,200),CGRectMake(1,2,301,201)) || sameRect(CGRectMake(0,0,300,200),CGRectMake(10,0,300,200))) return 1;
    for (int x=-1200;x<=1200;x+=1200) {
        NSRect screen=NSMakeRect(x,0,1440,900),anchor=NSMakeRect(x+40,0,60,80);
        NSRect frame=placePreview(screen,anchor,912,256);
        if (NSMinX(frame)<NSMinX(screen)+12 || NSMaxX(frame)>NSMaxX(screen)-12 || NSMinY(frame)<100 || NSMaxY(frame)>NSMaxY(screen)-12) return 1;
    }
    if (applicationScore(@"System Settings",@"sys set")<0 || applicationScore(@"Ghostty",@"gh")!=0
        || applicationScore(@"Safari",@"gh")!=-1 || applicationScore(@"Éditeur",@"edit")!=0) return 1;
    puts("Workspace panels: bounded preview placement, window geometry and application matching passed.");return 0;
}
