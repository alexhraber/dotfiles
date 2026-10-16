#import <AppKit/AppKit.h>

void DFCalendarInitialize(NSString *directory);
void DFCalendarShow(void);
void DFCalendarHide(void);
void DFCalendarAppearance(void);
void DFCalendarTick(double now, NSPoint pointer);
BOOL DFCalendarContainsPointer(NSPoint pointer);
void DFCalendarNotify(NSString *action);
NSDictionary *DFCalendarStatus(void);
int DFCalendarSelfTest(void);
BOOL DFCalendarPreview(NSString *path);
