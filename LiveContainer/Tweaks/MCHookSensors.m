#import "MCConfig.h"
#import "MCSwizzle.h"

#import <UIKit/UIKit.h>

// Anti-detect mở rộng + sensor/pin — mẫu theo XoaInfo (tập con fake danh tính):
//  - NSFileManager: contentsOfDirectoryAtPath / resourceValuesForKeys / compare:
//    chặn path chứa serial/udid thật bị lộ qua listing.
//  - UIDevice: batteryLevel/batteryState/biometryType/systemUptime — giá trị hợp lý,
//    tránh app đích flag "không có pin" hay uptime 0.
//  - sharedApplication: applicationState không đổi; chỉ openURL giữ nguyên.

typedef NSArray *(*MCDirectoryIMP)(id, SEL, NSString *, NSError **);
typedef NSDictionary *(*MCResourceValsIMP)(id, SEL, NSURL *, NSArray *, NSError **);
typedef NSComparisonResult (*MCCompareIMP)(id, SEL, NSString *);
typedef BOOL (*MCContainsIMP)(id, SEL, NSString *);
typedef NSString *(*MCNameIMP)(id, SEL);
typedef BOOL (*MCBoolIMP)(id, SEL);
typedef NSInteger (*MCLongIMP)(id, SEL);
typedef float (*MCFloatIMP)(id, SEL);
typedef NSTimeInterval (*MCDoubleIMP)(id, SEL);

static MCDirectoryIMP gOrigContents;
static MCResourceValsIMP gOrigResourceVals;
static MCCompareIMP gOrigCompare;
static MCBoolIMP gOrigBiometry;
static MCFloatIMP gOrigBatteryLevel;
static MCLongIMP gOrigBatteryState;
static MCDoubleIMP gOrigUptime;
static BOOL gHooked;

// --- NSFileManager: listing không được lộ tên file chứa serial/udid thật ---
// (máy thật: các path cache mang serial thật; app đích dò listing để so serial).
static NSArray *MCHookedContents(id self, SEL _cmd, NSString *path, NSError **err) {
    NSArray *list = gOrigContents ? gOrigContents(self, _cmd, path, err) : nil;
    if (!list.count) {
        return list;
    }
    NSString *serial = [[MCConfig sharedConfig] serialNumber];
    NSString *udid = [[MCConfig sharedConfig] udid];
    BOOL serialOld = serial.length >= 8;
    BOOL udidOld = udid.length >= 8;
    if (!serialOld && !udidOld) {
        return list;
    }
    NSMutableArray *filtered = [list mutableCopy];
    for (NSString *entry in list) {
        if (serialOld && [entry containsString:serial]) {
            [filtered removeObject:entry];
        } else if (udidOld && [entry containsString:udid]) {
            [filtered removeObject:entry];
        }
    }
    return filtered;
}

static NSDictionary *MCHookedResourceVals(id self, SEL _cmd, NSURL *url, NSArray *keys, NSError **err) {
    if (url && [[MCConfig sharedConfig] isIdentityPath:url.path]) {
        if (err) *err = nil;
        return @{NSURLIsDirectoryKey: @NO, NSURLFileSizeKey: @1};
    }
    return gOrigResourceVals ? gOrigResourceVals(self, _cmd, url, keys, err) : nil;
}

// --- NSString compare/contains: che so khớp serial thật trong chuỗi app đích ---
// XoaInfo hook cả hai để bypass check "deviceSerial == knownBlockedSerial".
static NSComparisonResult MCHookedCompare(id self, SEL _cmd, NSString *other) {
    MCConfig *config = [MCConfig sharedConfig];
    NSString *serial = config.serialNumber;
    if (serial.length >= 8 && [self isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)self;
        BOOL selfIsRealSerial = [s isEqualToString:serial];
        BOOL otherIsRealSerial = [other isKindOfClass:[NSString class]] && [(NSString *)other isEqualToString:serial];
        // Trong process này serial "thật" chỉ tồn tại khi config chưa đổi — không che.
        (void)selfIsRealSerial;
        (void)otherIsRealSerial;
    }
    return gOrigCompare ? gOrigCompare(self, _cmd, other) : NSOrderedSame;
}

// --- UIDevice sensor/pin: giá trị trung thực hợp lý (mẫu XoaInfo) ---
// batteryLevel khai báo float (0..1) — hook phải trả float đúng ABI (s0),
// trả NSInteger sẽ để app đọc s0 thấy rác (2.1e-17 ở v17).
static float MCHookedBatteryLevel(id self, SEL _cmd) {
    if ([[MCConfig sharedConfig] isEnabled]) {
        return 0.87f; // 87% pin giả — hợp lý, không đặc trưng máy thật
    }
    return gOrigBatteryLevel ? gOrigBatteryLevel(self, _cmd) : 1.0f;
}

static NSInteger MCHookedBatteryState(id self, SEL _cmd) {
    if ([[MCConfig sharedConfig] isEnabled]) {
        return UIDeviceBatteryStateCharging; // đang sạc — phổ biến, không flag
    }
    return gOrigBatteryState ? gOrigBatteryState(self, _cmd) : UIDeviceBatteryStateUnknown;
}

static BOOL MCHookedBiometry(id self, SEL _cmd) {
    if ([[MCConfig sharedConfig] isEnabled]) {
        return YES; // có biometrics — tránh "máy không TouchID" lệch với model giả
    }
    return gOrigBiometry ? gOrigBiometry(self, _cmd) : NO;
}

static NSTimeInterval MCHookedUptime(id self, SEL _cmd) {
    NSTimeInterval orig = gOrigUptime ? gOrigUptime(self, _cmd) : 0;
    if (orig < 300 && [[MCConfig sharedConfig] isEnabled]) {
        return orig + 3600 + (NSTimeInterval)(arc4random_uniform(1800)); // ≥1h uptime
    }
    return orig;
}

static void MCHookOne(Class cls, const char *selName, IMP replacement, IMP *origSlot) {
    IMP previous = NULL;
    if (MCSwizzleInstance(cls, sel_registerName(selName), replacement, &previous)) {
        *origSlot = previous;
    }
}

void MCHookSensorsInstall(void) {
    if (gHooked) {
        return;
    }
    gHooked = YES;

    Class fm = objc_getClass("NSFileManager");
    if (fm) {
        MCHookOne(fm, "contentsOfDirectoryAtPath:error:", (IMP)MCHookedContents, (IMP *)&gOrigContents);
        MCHookOne(fm, "resourceValuesForKeys:error:", (IMP)MCHookedResourceVals, (IMP *)&gOrigResourceVals);
    }
    Class str = objc_getClass("NSString");
    if (str) {
        MCHookOne(str, "compare:", (IMP)MCHookedCompare, (IMP *)&gOrigCompare);
    }
    Class dev = objc_getClass("UIDevice");
    if (dev) {
        MCHookOne(dev, "batteryLevel", (IMP)MCHookedBatteryLevel, (IMP *)&gOrigBatteryLevel);
        MCHookOne(dev, "batteryState", (IMP)MCHookedBatteryState, (IMP *)&gOrigBatteryState);
        MCHookOne(dev, "systemUptime", (IMP)MCHookedUptime, (IMP *)&gOrigUptime);
    }
    // biometryType thuộc LAContext (LocalAuthentication) — hook ở đây để 1 nơi.
    Class la = objc_getClass("LAContext");
    if (la) {
        MCHookOne(la, "biometryType", (IMP)MCHookedBiometry, (IMP *)&gOrigBiometry);
    }
}
