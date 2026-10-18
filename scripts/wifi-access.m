#import <AppKit/AppKit.h>
#import <CoreWLAN/CoreWLAN.h>
#import <CoreLocation/CoreLocation.h>
#include <unistd.h>

// Only authorization is used from CoreLocation. No coordinates or location
// updates are requested. A separate bundle preserves Desktop Controls consent.
static NSString *authorization(CLAuthorizationStatus status) {
    switch (status) {
        case kCLAuthorizationStatusAuthorizedAlways: return @"authorized";
        case kCLAuthorizationStatusDenied: return @"denied";
        case kCLAuthorizationStatusRestricted: return @"restricted";
        default: return @"notDetermined";
    }
}
static BOOL validSSID(id value) {
    if (![value isKindOfClass:NSString.class] || ![value lengthOfBytesUsingEncoding:NSUTF8StringEncoding]
        || [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>32) return NO;
    return [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound;
}
static NSArray *normalize(NSArray *rows) {
    NSMutableDictionary *unique=NSMutableDictionary.new;
    for (NSDictionary *row in rows) {
        NSString *ssid=row[@"ssid"]; if (!validSSID(ssid)) continue;
        NSDictionary *old=unique[ssid];
        if (!old || [row[@"rssi"] integerValue]>[old[@"rssi"] integerValue]) unique[ssid]=row;
    }
    return [unique.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        NSInteger first=[a[@"rssi"] integerValue],second=[b[@"rssi"] integerValue];
        return first==second ? [a[@"ssid"] compare:b[@"ssid"]] : first>second ? NSOrderedAscending : NSOrderedDescending;
    }];
}
static void output(id value) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (data) puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}
static NSDictionary *snapshot(CLLocationManager *manager, BOOL scan) {
    NSString *access=authorization(manager.authorizationStatus);
    NSMutableDictionary *result=[@{@"authorization":access,@"services":@(CLLocationManager.locationServicesEnabled),
        @"sampled":@(NSDate.date.timeIntervalSince1970),@"ssid":@"",@"networks":@[]} mutableCopy];
    if (![access isEqual:@"authorized"] || !CLLocationManager.locationServicesEnabled) return result;
    CWInterface *radio=CWWiFiClient.sharedWiFiClient.interface;
    result[@"interface"]=radio.interfaceName ?: @""; result[@"powered"]=@(radio.powerOn);
    result[@"ssid"]=validSSID(radio.ssid) ? radio.ssid : @"";
    if (!scan || !radio.powerOn) return result;
    NSError *error=nil;
    NSSet<CWNetwork *> *networks=[radio scanForNetworksWithSSID:nil error:&error];
    if (error) { result[@"error"]=@"Wi-Fi scan unavailable"; return result; }
    NSMutableSet *known=NSMutableSet.new;
    for (CWNetworkProfile *profile in radio.configuration.networkProfiles)
        if (validSSID(profile.ssid)) [known addObject:profile.ssid];
    NSMutableArray *rows=NSMutableArray.new;
    for (CWNetwork *network in networks) if (validSSID(network.ssid))
        [rows addObject:@{@"ssid":network.ssid,@"rssi":@(network.rssiValue),
            @"known":@([known containsObject:network.ssid]),@"secure":@(![network supportsSecurity:kCWSecurityNone])}];
    result[@"networks"]=normalize(rows);
    // Timestamp completed scans rather than presenting an in-flight result as fresh.
    result[@"sampled"]=@(NSDate.date.timeIntervalSince1970);
    return result;
}

@interface AccessDelegate : NSObject <CLLocationManagerDelegate>
@property BOOL finished;
@end
@implementation AccessDelegate
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (manager.authorizationStatus!=kCLAuthorizationStatusNotDetermined) self.finished=YES;
}
@end

int main(int argc,const char **argv) { @autoreleasepool {
    NSString *mode=argc==2 ? @(argv[1]) : @"--status";
    if ([mode isEqual:@"--self-test"]) {
        NSArray *rows=normalize(@[@{@"ssid":@"Cafe; $(literal)",@"rssi":@-70},
            @{@"ssid":@"Cafe; $(literal)",@"rssi":@-40},@{@"ssid":@" Office ",@"rssi":@-50},
            @{@"ssid":@"bad\nname",@"rssi":@-1}]);
        if (rows.count!=2 || ![rows[0][@"rssi"] isEqual:@-40] || ![rows[1][@"ssid"] isEqual:@" Office "]
            || validSSID([@"x" stringByPaddingToLength:33 withString:@"x" startingAtIndex:0])) return 1;
        puts("Wi-Fi: literal SSIDs, byte bounds, duplicate radio selection and ordering passed."); return 0;
    }
    if (![@[@"--status",@"--scan",@"--request-access"] containsObject:mode]) return 2;
    // A hung system service must not leave a background helper behind.
    alarm([mode isEqual:@"--request-access"] ? 65 : 10);
    [NSApplication.sharedApplication setActivationPolicy:NSApplicationActivationPolicyAccessory];
    CLLocationManager *manager=CLLocationManager.new;
    if ([mode isEqual:@"--request-access"] && manager.authorizationStatus==kCLAuthorizationStatusNotDetermined) {
        AccessDelegate *delegate=AccessDelegate.new; manager.delegate=delegate;
        [NSApp activate];
        [manager requestWhenInUseAuthorization];
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:60];
        while (!delegate.finished && deadline.timeIntervalSinceNow>0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        manager.delegate=nil;
    }
    output(snapshot(manager,[mode isEqual:@"--scan"]));
    return 0;
} }
