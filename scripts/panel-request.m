#import "panel-request.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <limits.h>

static NSString *const workspaceNotification=@"local.dotfiles.desktop.workspace";
static NSDictionary *readPrivate(NSString *path) {
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);
    if (fd<0) return @{};
    struct stat status;
    BOOL safe=fstat(fd,&status)==0 && S_ISREG(status.st_mode) && status.st_uid==getuid()
        && !(status.st_mode&0077) && status.st_size>0 && status.st_size<16384;
    NSData *data=safe ? [[[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES] readDataToEndOfFile] : nil;
    if (!safe) close(fd);
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
NSDictionary *DFWorkspaceReadStatus(NSString *directory) {
    NSDictionary *status=readPrivate([directory stringByAppendingPathComponent:@"bar/workspace-status.json"]);
    double age=NSDate.date.timeIntervalSince1970-[status[@"updated"] doubleValue];
    return age>=0 && age<.8 ? status : @{};
}
static BOOL writeRequest(NSString *directory,NSDictionary *request) {
    NSString *bar=[directory stringByAppendingPathComponent:@"bar"];
    if (![NSFileManager.defaultManager createDirectoryAtPath:bar withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return NO;
    NSData *data=[NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    NSString *temporary=[bar stringByAppendingPathComponent:[@".workspace-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    int fd=open(temporary.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);
    if (fd<0) return NO;
    BOOL written=write(fd,data.bytes,data.length)==(ssize_t)data.length;close(fd);
    if (written) written=rename(temporary.fileSystemRepresentation,[[bar stringByAppendingPathComponent:@"workspace-request.json"] fileSystemRepresentation])==0;
    unlink(temporary.fileSystemRepresentation);return written;
}
BOOL DFWorkspaceRequest(NSString *directory, NSString *kind, pid_t pid, NSRect anchor) {
    if (![@[@"dock",@"launcher"] containsObject:kind]) return NO;
    NSString *helper=[directory stringByAppendingPathComponent:@"wifi-pane"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:helper]) return NO;
    NSDictionary *request=@{@"request":NSUUID.UUID.UUIDString,@"kind":kind,@"pid":@(pid),
        @"anchor":@[@(anchor.origin.x),@(anchor.origin.y),@(anchor.size.width),@(anchor.size.height)],
        @"updated":@(NSDate.date.timeIntervalSince1970)};
    if (!writeRequest(directory,request)) return NO;
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:workspaceNotification object:@"show" userInfo:nil deliverImmediately:YES];
    // Reuse the existing short-lived UI server, or launch the signed app. The
    // server lock forwards a request that races a concurrent startup/shutdown.
    NSDictionary *status=DFWorkspaceReadStatus(directory);
    if (![status[@"visible"] boolValue]) {
        NSURL *bundle=[NSURL fileURLWithPath:helper.stringByResolvingSymlinksInPath];
        for (NSUInteger i=0;i<3;i++) bundle=bundle.URLByDeletingLastPathComponent;
        NSTask *task=NSTask.new;task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/open"];
        task.arguments=@[@"-g",@"-n",@"-a",bundle.path,@"--args",@"--workspace-ui"];
        task.standardInput=NSFileHandle.fileHandleWithNullDevice;
        task.standardOutput=NSFileHandle.fileHandleWithNullDevice;task.standardError=NSFileHandle.fileHandleWithNullDevice;
        return [task launchAndReturnError:nil];
    }
    return YES;
}
void DFWorkspaceCancel(NSString *directory) {
    // A fresh launcher is explicit user intent and survives dock/bar autohide.
    if ([readPrivate([directory stringByAppendingPathComponent:@"bar/workspace-request.json"])[@"kind"] isEqual:@"launcher"]) return;
    DFWorkspaceCancelAll(directory);
}
void DFWorkspaceCancelAll(NSString *directory) {
    if (!directory.length) return;
    writeRequest(directory,@{@"request":NSUUID.UUID.UUIDString,@"kind":@"hide",@"updated":@(NSDate.date.timeIntervalSince1970)});
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:workspaceNotification object:@"hide" userInfo:nil deliverImmediately:YES];
}

// A private, expiring lease prevents the menu watchdog from resetting native
// controls in the middle of a managed transaction. A dead helper cannot hold it.
NSString *DFNativeUIActiveToken(NSString *directory) {
    NSDictionary *lease=readPrivate([directory stringByAppendingPathComponent:@"bar/native-ui-lease.json"]);
    NSString *token=lease[@"token"];NSNumber *expires=lease[@"expires"],*pid=lease[@"pid"];
    if (![token isKindOfClass:NSString.class] || !token.length || token.length>64
        || ![expires isKindOfClass:NSNumber.class] || ![pid isKindOfClass:NSNumber.class]) return nil;
    double left=expires.doubleValue-NSDate.date.timeIntervalSince1970;long long owner=pid.longLongValue;
    return left>0 && left<=12 && owner>0 && owner<=INT_MAX && pid.doubleValue==owner
        && (kill((pid_t)owner,0)==0 || errno==EPERM) ? token : nil;
}
BOOL DFNativeUIBusy(NSString *directory) {return DFNativeUIActiveToken(directory)!=nil;}
BOOL DFNativeUIBegin(NSString *directory, NSString *token) {
    if (!token.length || token.length>64 || DFNativeUIBusy(directory)) return NO;
    NSString *bar=[directory stringByAppendingPathComponent:@"bar"];
    if (![NSFileManager.defaultManager createDirectoryAtPath:bar withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return NO;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"token":token,@"pid":@(getpid()),@"expires":@(NSDate.date.timeIntervalSince1970+12)} options:0 error:nil];
    NSString *temporary=[bar stringByAppendingPathComponent:[@".native-ui-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    int fd=open(temporary.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);
    if(fd<0)return NO;
    BOOL written=write(fd,data.bytes,data.length)==(ssize_t)data.length;close(fd);
    if(written)written=rename(temporary.fileSystemRepresentation,[[bar stringByAppendingPathComponent:@"native-ui-lease.json"] fileSystemRepresentation])==0;
    unlink(temporary.fileSystemRepresentation);return written;
}
void DFNativeUIEnd(NSString *directory, NSString *token) {
    NSString *path=[directory stringByAppendingPathComponent:@"bar/native-ui-lease.json"];
    if ([readPrivate(path)[@"token"] isEqual:token]) unlink(path.fileSystemRepresentation);
}
