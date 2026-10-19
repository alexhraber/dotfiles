#import <AppKit/AppKit.h>

BOOL DFWorkspaceRequest(NSString *directory, NSString *kind, pid_t pid, NSRect anchor);
void DFWorkspaceCancel(NSString *directory);
void DFWorkspaceCancelAll(NSString *directory);
NSDictionary *DFWorkspaceReadStatus(NSString *directory);

NSString *DFNativeUIActiveToken(NSString *directory);
BOOL DFNativeUIBusy(NSString *directory);
BOOL DFNativeUIBegin(NSString *directory, NSString *token);
void DFNativeUIEnd(NSString *directory, NSString *token);
