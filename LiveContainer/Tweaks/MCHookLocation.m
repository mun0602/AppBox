#import "MCConfig.h"
#import "MCSwizzle.h"
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>

/// Fake GPS (mục 4.1) — cơ chế XoaInfo:
/// 1. `CLLocationManager.location` trả CLLocation từ gpsLat/gpsLng.
/// 2. Delegate `locationManager:didUpdateLocations:` bị swizzle TRÊN CLASS delegate
///    thật ngay lúc app gọi setDelegate: — thay mảng locations bằng toạ độ fake.

typedef id (*MCObjectIMP)(id, SEL);
typedef void (*MCSetDelegateIMP)(id, SEL, id);
typedef void (*MCDidUpdateIMP)(id, SEL, id, NSArray<CLLocation *> *);

static MCObjectIMP gOrigLocation;
static MCSetDelegateIMP gOrigSetDelegate;
static BOOL gHooked;
static NSMutableSet *gHookedDelegateClasses;

static CLLocation *MCGMakeFakeLocation(void) {
    MCConfig *config = [MCConfig sharedConfig];
    if (!config.fakeGPSEnabled) return nil;
    // Accuracy 5–30m ngẫu nhiên ổn định theo phút — nhìn thật, không nhảy.
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    uint32_t seed = (uint32_t)(now / 60);
    CLLocationAccuracy acc = 5.0 + (seed % 26);
    return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(config.gpsLatitude, config.gpsLongitude)
                                        altitude:0
                              horizontalAccuracy:acc
                              verticalAccuracy:acc
                                        course:-1
                                         speed:-1
                                     timestamp:[NSDate date]];
}

static id MCHookedLocation(id self, SEL _cmd) {
    CLLocation *fake = MCGMakeFakeLocation();
    if (fake) return fake;
    return gOrigLocation(self, _cmd);
}

/// Delegate callback: thay mảng locations bằng [fakeLocation].
static void MCHookedDidUpdateLocations(id self, SEL _cmd, id manager, NSArray<CLLocation *> *locations) {
    CLLocation *fake = MCGMakeFakeLocation();
    if (fake) {
        locations = @[ fake ];
    }
    // Gọi IMP gốc ĐÃ swizzle trên class này (giữ hành vi app delegate).
    MCDidUpdateIMP orig = (MCDidUpdateIMP)[(NSValue *)objc_getAssociatedObject(self, _cmd) pointerValue];
    if (orig) {
        orig(self, _cmd, manager, locations);
    }
}

/// setDelegate: là điểm duy nhất ta biết class delegate thật của app.
static void MCHookedSetDelegate(id self, SEL _cmd, id delegate) {
    gOrigSetDelegate(self, _cmd, delegate);
    if (!delegate) return;
    MCConfig *config = [MCConfig sharedConfig];
    if (!config.fakeGPSEnabled) return;

    Class cls = object_getClass(delegate);
    if (!cls) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gHookedDelegateClasses = [NSMutableSet set];
    });
    @synchronized (gHookedDelegateClasses) {
        NSString *name = NSStringFromClass(cls);
        // Không đụng class hệ thống của Apple (CLLocationManager không tự làm delegate).
        if ([name hasPrefix:@"NS"] || [name hasPrefix:@"UI"] || [name hasPrefix:@"CL"]) return;
        if ([gHookedDelegateClasses containsObject:name]) return;
        Method m = class_getInstanceMethod(cls, sel_registerName("locationManager:didUpdateLocations:"));
        if (!m) return;
        IMP origIMP = method_getImplementation(m);
        objc_setAssociatedObject(delegate, sel_registerName("locationManager:didUpdateLocations:"),
                                 [NSValue valueWithPointer:origIMP], OBJC_ASSOCIATION_RETAIN);
        if (MCSwizzleInstance(cls, sel_registerName("locationManager:didUpdateLocations:"),
                              (IMP)MCHookedDidUpdateLocations, NULL)) {
            [gHookedDelegateClasses addObject:name];
        }
    }
}

static BOOL MCHookedLocationServicesEnabled(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    return YES;
}

void MCHookLocationInstall(void) {
    if (gHooked) return;
    gHooked = YES;
    Class cls = objc_getClass("CLLocationManager");
    if (!cls) return;
    Class meta = object_getClass((id)cls);
    MCSwizzleInstance(meta, sel_registerName("locationServicesEnabled"), (IMP)MCHookedLocationServicesEnabled, NULL);
    MCSwizzleInstance(cls, sel_registerName("location"), (IMP)MCHookedLocation, (IMP *)&gOrigLocation);
    MCSwizzleInstance(cls, sel_registerName("setDelegate:"), (IMP)MCHookedSetDelegate, (IMP *)&gOrigSetDelegate);
}
