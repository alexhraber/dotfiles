#import "calendar-panel.h"
#import "control-panel.h"
#import "app-menu.h"
#import "panel-style.h"
#import <EventKit/EventKit.h>
#import <QuartzCore/QuartzCore.h>
#include <sys/stat.h>

static NSString *const calendarNotification = @"local.dotfiles.desktop.calendar";
static NSPanel *calendarPanel;
static NSRect calendarAnchor;
static double calendarAway;
static BOOL calendarMenuOpen, calendarRequestPending;
static NSString *calendarDirectory;

static NSColor *ink(unsigned rgb) {
    return DFPanelColor(rgb);
}
static NSDate *monthStart(NSCalendar *calendar, NSDate *date) {
    NSDateComponents *parts = [calendar components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:date];
    parts.day=1; parts.hour=12;
    return [calendar dateFromComponents:parts];
}
static NSDate *gridStart(NSCalendar *calendar, NSDate *month) {
    NSInteger offset = [calendar component:NSCalendarUnitWeekday fromDate:month]-1;
    return [calendar dateByAddingUnit:NSCalendarUnitDay value:-offset toDate:month options:0];
}
static NSString *formatted(NSDate *date, NSString *pattern) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = NSLocale.currentLocale; formatter.dateFormat=pattern;
    return [formatter stringFromDate:date];
}

@interface CalendarSurface : NSView
@end
@implementation CalendarSurface
- (BOOL)isFlipped { return YES; }
@end

@interface CalendarButton : NSButton
@property BOOL selectedDay;
@property BOOL today;
@property BOOL outsideMonth;
@property BOOL eventDay;
@property NSDate *date;
@end
@implementation CalendarButton
- (void)drawRect:(__unused NSRect)dirty {
    NSRect bounds=NSInsetRect(self.bounds,3,2);
    if (self.selectedDay) {
        [ink(0x7c5cff) setFill]; [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:9 yRadius:9] fill];
    } else if (self.today) {
        [ink(0x42c7ff) setStroke];
        NSBezierPath *ring=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds,0.5,0.5) xRadius:9 yRadius:9];
        ring.lineWidth=1; [ring stroke];
    }
    NSColor *color = self.selectedDay ? NSColor.whiteColor : self.outsideMonth ? ink(0x58657a) : ink(0xe6edf7);
    NSDictionary *style=@{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium],NSForegroundColorAttributeName:color};
    NSSize size=[self.title sizeWithAttributes:style];
    [self.title drawAtPoint:NSMakePoint((self.bounds.size.width-size.width)/2,(self.bounds.size.height-size.height)/2) withAttributes:style];
    if (self.eventDay) {
        [(self.selectedDay ? NSColor.whiteColor : ink(0x42c7ff)) setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(self.bounds)-1.5,NSMaxY(self.bounds)-6,3,3)] fill];
    }
}
@end

@interface CalendarView : CalendarSurface
@property NSCalendar *calendar;
@property NSDate *month;
@property NSDate *selected;
@property NSTextField *heading;
@property NSTextField *dayHeading;
@property NSTextField *status;
@property NSScrollView *agenda;
@property NSButton *connection;
@property NSButton *sources;
@property NSArray<CalendarButton *> *days;
@property NSArray<EKEvent *> *events;
@property NSArray<EKCalendar *> *calendars;
@property NSSet<NSString *> *enabledIDs;
@property EKEventStore *store;
@property dispatch_queue_t eventQueue;
@property NSUInteger revision;
- (void)refresh;
- (void)connect:(id)sender;
@end
static CalendarView *calendarView;

static NSTextField *label(NSView *parent, NSString *text, NSRect frame, CGFloat size, NSColor *color) {
    NSTextField *view=[NSTextField labelWithString:text];
    view.frame=frame; view.font=[NSFont systemFontOfSize:size]; view.textColor=color;
    view.lineBreakMode=NSLineBreakByTruncatingTail;
    for (NSNumber *role in @[@(0xe6edf7),@(0x94a3b8),@(0x42c7ff)]) if ([color isEqual:ink(role.unsignedIntValue)]) view.tag=role.integerValue;
    [parent addSubview:view]; return view;
}
static NSButton *button(NSView *parent, NSString *title, NSRect frame, id target, SEL action) {
    NSButton *view=[NSButton buttonWithTitle:title target:target action:action];
    view.frame=frame; view.bordered=NO; view.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    view.contentTintColor=ink(0xe6edf7); view.tag=0xe6edf7; [parent addSubview:view]; return view;
}

@implementation CalendarView
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    self.wantsLayer=YES; self.layer.backgroundColor=ink(0x11151d).CGColor;
    self.layer.cornerRadius=16; self.layer.borderWidth=1; self.layer.borderColor=ink(0x2a3447).CGColor;
    self.calendar=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    self.selected=[self.calendar startOfDayForDate:NSDate.date]; self.month=monthStart(self.calendar,self.selected);
    self.events=@[]; self.calendars=@[];
    self.store=[EKEventStore new]; self.eventQueue=dispatch_queue_create("local.dotfiles.desktop.calendar.events",DISPATCH_QUEUE_SERIAL);
    NSData *settings=[NSData dataWithContentsOfFile:[calendarDirectory stringByAppendingPathComponent:@"calendar.json"]];
    id saved=settings ? [NSJSONSerialization JSONObjectWithData:settings options:0 error:nil] : nil;
    if ([saved isKindOfClass:NSDictionary.class] && [saved[@"enabled_ids"] isKindOfClass:NSArray.class])
        self.enabledIDs=[NSSet setWithArray:saved[@"enabled_ids"]];
    self.heading=label(self,@"",NSMakeRect(20,18,180,25),18,ink(0xe6edf7));
    self.heading.font=[NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    button(self,@"‹",NSMakeRect(210,16,28,30),self,@selector(previous:));
    button(self,@"›",NSMakeRect(294,16,28,30),self,@selector(next:));
    NSButton *today=button(self,@"Today",NSMakeRect(254,20,43,24),self,@selector(today:));
    today.font=[NSFont systemFontOfSize:10 weight:NSFontWeightMedium]; today.contentTintColor=ink(0x42c7ff); today.tag=0x42c7ff;
    NSArray *weekdays=@[@"S",@"M",@"T",@"W",@"T",@"F",@"S"];
    NSMutableArray *days=[NSMutableArray array];
    for (NSUInteger column=0; column<7; column++) {
        NSTextField *day=label(self,weekdays[column],NSMakeRect(20+column*43,58,42,18),10,ink(0x42c7ff));
        day.alignment=NSTextAlignmentCenter;
    }
    for (NSUInteger i=0; i<42; i++) {
        CalendarButton *day=[[CalendarButton alloc] initWithFrame:NSMakeRect(20+(i%7)*43,80+(i/7)*32,42,32)];
        day.bordered=NO; day.target=self; day.action=@selector(selectDay:); day.tag=i;
        [self addSubview:day]; [days addObject:day];
    }
    self.days=days;
    NSView *divider=[[NSView alloc] initWithFrame:NSMakeRect(20,286,300,1)];
    divider.wantsLayer=YES; divider.layer.backgroundColor=ink(0x2a3447).CGColor; [self addSubview:divider];
    divider.identifier=@"divider";
    self.dayHeading=label(self,@"",NSMakeRect(20,302,300,23),14,ink(0xe6edf7));
    self.dayHeading.font=[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    self.agenda=[[NSScrollView alloc] initWithFrame:NSMakeRect(16,336,308,142)];
    self.agenda.drawsBackground=NO; self.agenda.hasVerticalScroller=YES; self.agenda.autohidesScrollers=YES;
    [self addSubview:self.agenda];
    self.connection=button(self,@"Connect your calendar",NSMakeRect(20,410,300,34),self,@selector(connect:));
    self.connection.contentTintColor=ink(0x42c7ff);
    self.connection.tag=0x42c7ff;
    self.status=label(self,@"",NSMakeRect(20,496,205,24),10,ink(0x94a3b8));
    self.sources=button(self,@"Calendars…",NSMakeRect(232,492,92,28),self,@selector(chooseCalendars:));
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(storeChanged:) name:EKEventStoreChangedNotification object:self.store];
    return self;
}
- (void)previous:(__unused id)sender { self.month=[self.calendar dateByAddingUnit:NSCalendarUnitMonth value:-1 toDate:self.month options:0]; self.selected=[self.calendar startOfDayForDate:self.month]; [self refresh]; }
- (void)next:(__unused id)sender { self.month=[self.calendar dateByAddingUnit:NSCalendarUnitMonth value:1 toDate:self.month options:0]; self.selected=[self.calendar startOfDayForDate:self.month]; [self refresh]; }
- (void)today:(__unused id)sender { self.selected=[self.calendar startOfDayForDate:NSDate.date]; self.month=monthStart(self.calendar,self.selected); [self refresh]; }
- (void)selectDay:(CalendarButton *)sender { self.selected=[self.calendar startOfDayForDate:sender.date]; self.month=monthStart(self.calendar,self.selected); [self refresh]; }
- (void)storeChanged:(__unused NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(),^{ if (calendarPanel.visible) [self refresh]; });
}
- (void)refresh {
    self.heading.stringValue=formatted(self.month,@"MMMM yyyy");
    self.dayHeading.stringValue=formatted(self.selected,@"EEEE, MMMM d");
    NSDate *start=gridStart(self.calendar,self.month);
    for (NSUInteger i=0; i<42; i++) {
        CalendarButton *day=self.days[i]; day.date=[self.calendar dateByAddingUnit:NSCalendarUnitDay value:i toDate:start options:0];
        day.title=formatted(day.date,@"d"); day.selectedDay=[self.calendar isDate:day.date inSameDayAsDate:self.selected];
        day.today=[self.calendar isDateInToday:day.date];
        day.outsideMonth=[self.calendar component:NSCalendarUnitMonth fromDate:day.date]!=[self.calendar component:NSCalendarUnitMonth fromDate:self.month];
        day.eventDay=NO; [day setNeedsDisplay:YES];
        day.accessibilityLabel=formatted(day.date,@"EEEE, MMMM d, yyyy");
    }
    EKAuthorizationStatus access=[EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];
    self.sources.hidden=access!=EKAuthorizationStatusFullAccess;
    self.connection.hidden=access==EKAuthorizationStatusFullAccess;
    self.status.stringValue=calendarRequestPending ? @"Waiting for macOS permission…" : @"Google Calendar sync stays on this Mac";
    if (access!=EKAuthorizationStatusFullAccess) {
        NSString *message=access==EKAuthorizationStatusNotDetermined ? @"Connect your synced calendar to see your agenda." : @"Calendar access is off. Enable it to show your agenda.";
        self.connection.title=access==EKAuthorizationStatusNotDetermined ? @"Allow calendar access" : @"Calendar permissions";
        CalendarSurface *empty=[[CalendarSurface alloc] initWithFrame:NSMakeRect(0,0,300,120)];
        label(empty,message,NSMakeRect(4,12,294,45),12,ink(0x94a3b8)); self.agenda.documentView=empty;
        return;
    }
    NSUInteger revision=++self.revision;
    NSSet *enabled=self.enabledIDs;
    NSDate *end=[self.calendar dateByAddingUnit:NSCalendarUnitDay value:42 toDate:start options:0];
    dispatch_async(self.eventQueue,^{
        NSArray<EKCalendar *> *calendars=[self.store calendarsForEntityType:EKEntityTypeEvent];
        NSArray *selected=enabled ? [calendars filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(EKCalendar *item,__unused NSDictionary *bindings) {
            return [enabled containsObject:item.calendarIdentifier];
        }]] : calendars;
        NSArray<EKEvent *> *events=selected.count ? [self.store eventsMatchingPredicate:[self.store predicateForEventsWithStartDate:start endDate:end calendars:selected]] : @[];
        events=[events sortedArrayUsingComparator:^NSComparisonResult(EKEvent *a,EKEvent *b) { return [a.startDate compare:b.startDate]; }];
        dispatch_async(dispatch_get_main_queue(),^{
            if (revision!=self.revision) return;
            self.calendars=calendars; self.events=events;
            self.status.stringValue=[NSString stringWithFormat:@"%lu synced calendar%@",(unsigned long)selected.count,selected.count==1 ? @"" : @"s"];
            self.connection.hidden=calendars.count>0;
            self.connection.title=@"Add Google account";
            for (CalendarButton *day in self.days) {
                NSDate *dayStart=[self.calendar startOfDayForDate:day.date];
                NSDate *dayEnd=[self.calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:dayStart options:0];
                day.eventDay=[events indexOfObjectPassingTest:^BOOL(EKEvent *event,__unused NSUInteger index,__unused BOOL *stop) {
                    return event.status!=EKEventStatusCanceled && [event.startDate compare:dayEnd]==NSOrderedAscending && [event.endDate compare:dayStart]==NSOrderedDescending;
                }]!=NSNotFound;
                [day setNeedsDisplay:YES];
            }
            [self renderAgenda];
        });
    });
}
- (void)renderAgenda {
    NSDate *end=[self.calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:self.selected options:0];
    NSMutableArray<EKEvent *> *selected=[NSMutableArray array];
    for (EKEvent *event in self.events)
        if (event.status!=EKEventStatusCanceled && [event.startDate compare:end]==NSOrderedAscending && [event.endDate compare:self.selected]==NSOrderedDescending) [selected addObject:event];
    CalendarSurface *content=[[CalendarSurface alloc] initWithFrame:NSMakeRect(0,0,300,MAX(120,selected.count*58))];
    if (!selected.count) label(content,self.calendars.count ? @"No events on this day" : @"Add Google in macOS Internet Accounts.",NSMakeRect(4,12,294,44),12,ink(0x94a3b8));
    for (NSUInteger i=0; i<selected.count; i++) {
        EKEvent *event=selected[i]; CGFloat y=i*58;
        NSView *stripe=[[NSView alloc] initWithFrame:NSMakeRect(4,y+6,3,40)];
        stripe.wantsLayer=YES; stripe.layer.cornerRadius=1.5;
        stripe.layer.backgroundColor=event.calendar.CGColor ?: ink(0x7c5cff).CGColor; [content addSubview:stripe];
        NSTextField *title=label(content,event.title.length ? event.title : @"Untitled event",NSMakeRect(17,y+4,274,22),12,ink(0xe6edf7));
        title.font=[NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        NSString *time=event.allDay ? @"All day" : [NSString stringWithFormat:@"%@ – %@",formatted(event.startDate,@"h:mm a"),formatted(event.endDate,@"h:mm a")];
        label(content,[NSString stringWithFormat:@"%@  ·  %@",time,event.calendar.title ?: @"Calendar"],NSMakeRect(17,y+27,274,18),10,ink(0x94a3b8));
    }
    self.agenda.documentView=content;
}
- (void)connect:(__unused id)sender {
    EKAuthorizationStatus access=[EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];
    if (access==EKAuthorizationStatusNotDetermined) {
        calendarRequestPending=YES; [self refresh];
        [self.store requestFullAccessToEventsWithCompletion:^(__unused BOOL granted,__unused NSError *error) {
            dispatch_async(dispatch_get_main_queue(),^{ calendarRequestPending=NO; [self refresh]; });
        }];
    } else {
        NSString *url=access==EKAuthorizationStatusFullAccess ? @"x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension" : @"x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars";
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:url]];
    }
}
- (void)chooseCalendars:(id)sender {
    NSMenu *menu=[[NSMenu alloc] initWithTitle:@"Calendars"];
    for (EKCalendar *calendar in self.calendars) {
        NSString *title=[NSString stringWithFormat:@"%@ · %@",calendar.source.title,calendar.title];
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:@selector(toggleCalendar:) keyEquivalent:@""];
        item.target=self; item.representedObject=calendar.calendarIdentifier;
        item.state=(!self.enabledIDs || [self.enabledIDs containsObject:calendar.calendarIdentifier]) ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *add=[[NSMenuItem alloc] initWithTitle:@"Add Google account…" action:@selector(connect:) keyEquivalent:@""];
    add.target=self; [menu addItem:add];
    calendarMenuOpen=YES; [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,0) inView:sender]; calendarMenuOpen=NO;
}
- (void)toggleCalendar:(NSMenuItem *)sender {
    NSMutableSet *enabled=self.enabledIDs ? [self.enabledIDs mutableCopy] : [NSMutableSet setWithArray:[self.calendars valueForKey:@"calendarIdentifier"]];
    if ([enabled containsObject:sender.representedObject]) [enabled removeObject:sender.representedObject]; else [enabled addObject:sender.representedObject];
    self.enabledIDs=enabled;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"enabled_ids":enabled.allObjects} options:0 error:nil];
    NSString *path=[calendarDirectory stringByAppendingPathComponent:@"calendar.json"];
    [data writeToFile:path atomically:YES]; chmod(path.fileSystemRepresentation,0600);
    [self refresh];
}
@end

static void createCalendar(void) {
    if (calendarPanel) return;
    calendarPanel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,340,536)
        styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    calendarPanel.level=CGWindowLevelForKey(kCGStatusWindowLevelKey)+2;
    calendarPanel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorStationary;
    calendarPanel.opaque=NO; calendarPanel.backgroundColor=NSColor.clearColor; calendarPanel.hasShadow=YES;
    calendarPanel.hidesOnDeactivate=NO;
    calendarView=[[CalendarView alloc] initWithFrame:NSMakeRect(0,0,340,536)]; calendarPanel.contentView=calendarView;
}
static void restyle(NSView *view) {
    if ([view.identifier isEqual:@"divider"]) view.layer.backgroundColor=ink(0x2a3447).CGColor;
    if (view.tag>0xffff) {
        NSColor *color=ink((unsigned)view.tag);
        if ([view isKindOfClass:NSTextField.class]) ((NSTextField *)view).textColor=color;
        else if ([view isKindOfClass:NSButton.class]) ((NSButton *)view).contentTintColor=color;
        else if (view.wantsLayer) view.layer.backgroundColor=color.CGColor;
    }
    view.needsDisplay=YES; for (NSView *child in view.subviews) restyle(child);
}
void DFCalendarAppearance(void) {
    calendarView.layer.backgroundColor=ink(0x11151d).CGColor; calendarView.layer.borderColor=ink(0x2a3447).CGColor;
    restyle(calendarView);
}
void DFCalendarNotify(NSString *action) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:calendarNotification object:action userInfo:nil deliverImmediately:YES];
}
void DFCalendarInitialize(NSString *directory) {
    calendarDirectory=directory;
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:calendarNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
        if ([notification.object isEqual:@"hide"]) DFCalendarHide();
        else if ([notification.object isEqual:@"show"] || [notification.object isEqual:@"access"]) {
            DFCalendarShow(); if ([notification.object isEqual:@"access"]) [calendarView connect:nil];
        }
    }];
}
void DFCalendarShow(void) {
    DFMenusHide();
    DFControlsHide();
    createCalendar();
    if (calendarPanel.visible) { calendarAway=0; return; }
    NSPoint pointer=NSEvent.mouseLocation; NSScreen *screen=NSScreen.mainScreen;
    for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(pointer,candidate.frame)) screen=candidate;
    NSRect frame=screen.frame;
    CGFloat top=NSMaxY(frame)-screen.safeAreaInsets.top-44;
    CGFloat x=MAX(NSMinX(frame)+12,MIN(pointer.x-296,NSMaxX(frame)-352));
    [calendarPanel setFrameOrigin:NSMakePoint(x,MAX(NSMinY(frame)+12,top-536))];
    calendarAnchor=NSMakeRect(pointer.x-50,top,100,NSMaxY(frame)-top);
    calendarAway=0; [calendarView refresh]; DFPanelPrepare(calendarPanel);DFPanelPresent(calendarPanel);
}
void DFCalendarHide(void) { [calendarPanel orderOut:nil]; calendarAway=0; }
BOOL DFCalendarContainsPointer(NSPoint pointer) {
    return calendarPanel.visible && (calendarMenuOpen || calendarRequestPending ||
        NSPointInRect(pointer,NSInsetRect(calendarPanel.frame,-4,-4)) || NSPointInRect(pointer,calendarAnchor));
}
void DFCalendarTick(double now, NSPoint pointer) {
    if (!calendarPanel.visible) return;
    if (DFCalendarContainsPointer(pointer)) calendarAway=0;
    else if (!calendarAway) calendarAway=now;
    else if (now-calendarAway>0.32) DFCalendarHide();
}
NSDictionary *DFCalendarStatus(void) {
    return @{@"access":@([EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent]),
             @"visible":@(calendarPanel.visible),@"calendars":@(calendarView.calendars.count),@"events":@(calendarView.events.count)};
}
int DFCalendarSelfTest(void) {
    NSCalendar *calendar=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone=[NSTimeZone timeZoneWithName:@"America/Los_Angeles"];
    for (NSInteger year=2023; year<=2028; year++) for (NSInteger month=1; month<=12; month++) {
        NSDateComponents *parts=[NSDateComponents new]; parts.year=year; parts.month=month; parts.day=18;
        NSDate *first=monthStart(calendar,[calendar dateFromComponents:parts]);
        NSDate *start=gridStart(calendar,first);
        if ([calendar component:NSCalendarUnitWeekday fromDate:start]!=1) return 1;
        NSInteger found=0;
        for (NSInteger i=0; i<42; i++) {
            NSDate *date=[calendar dateByAddingUnit:NSCalendarUnitDay value:i toDate:start options:0];
            if ([calendar component:NSCalendarUnitMonth fromDate:date]==month) found++;
        }
        if (found!=(NSInteger)[calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:first].length) return 1;
        NSDate *next=[calendar dateByAddingUnit:NSCalendarUnitMonth value:1 toDate:first options:0];
        NSDate *previous=[calendar dateByAddingUnit:NSCalendarUnitMonth value:-1 toDate:next options:0];
        if (![previous isEqualToDate:first]) return 1;
    }
    puts("Calendar dates: 72 months, leap years, DST boundaries and year navigation passed."); return 0;
}
BOOL DFCalendarPreview(NSString *path) {
    calendarDirectory=@"/nonexistent"; createCalendar(); [calendarView refresh];
    NSBitmapImageRep *bitmap=[calendarView bitmapImageRepForCachingDisplayInRect:calendarView.bounds];
    [calendarView cacheDisplayInRect:calendarView.bounds toBitmapImageRep:bitmap];
    return [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}
