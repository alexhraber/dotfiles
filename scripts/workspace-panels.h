#import <AppKit/AppKit.h>

void DFWorkspaceInitialize(NSString *directory);
void DFWorkspaceShow(void);
void DFWorkspaceHide(void);
void DFWorkspaceTick(double now, NSPoint pointer);
void DFWorkspaceRefreshAppearance(void);
NSDictionary *DFWorkspaceStatus(void);
int DFWorkspaceSelfTest(void);
NSDictionary *DFWorkspaceDiagnostics(BOOL capture);
