#import <AppKit/AppKit.h>
void DFOverviewGestureStart(void (^action)(BOOL open));
void DFOverviewGestureStop(void);
BOOL DFOverviewGestureSuppressScroll(CGEventRef event);
NSDictionary *DFOverviewGestureStatus(void);
int DFOverviewGestureSelfTest(void);
