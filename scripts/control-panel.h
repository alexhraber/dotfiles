#import <AppKit/AppKit.h>

void DFControlsInitialize(NSString *directory);
void DFControlsAppearance(NSString *path);
NSColor *DFPanelColor(unsigned fallback);
void DFControlsNotify(NSString *action);
void DFControlsHide(void);
void DFControlsTick(double now, NSPoint pointer);
BOOL DFControlsContainsPointer(NSPoint pointer);
NSDictionary *DFControlsStatus(void);
int DFControlsSelfTest(void);
BOOL DFControlsPreview(NSString *path, NSString *kind);
