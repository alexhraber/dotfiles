#import <AppKit/AppKit.h>

void DFMenusInitialize(NSString *sketchybar);
void DFMenusNotify(NSString *command);
void DFMenusTick(double now, NSPoint pointer, BOOL barVisible);
void DFMenusHide(void);
BOOL DFMenusContainsPointer(NSPoint pointer);
NSDictionary *DFMenusStatus(void);
int DFMenusSelfTest(void);
