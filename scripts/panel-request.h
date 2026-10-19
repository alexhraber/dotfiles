#import <AppKit/AppKit.h>

BOOL DFWorkspaceRequest(NSString *directory, NSString *kind, pid_t pid, NSRect anchor);
void DFWorkspaceCancel(NSString *directory);
void DFWorkspaceCancelAll(NSString *directory);
NSDictionary *DFWorkspaceReadStatus(NSString *directory);
