#import "MCConfig.h"
#import "MCSwizzle.h"
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

/// Fake cảm biến rung/gia tốc (mục 7) — pattern XoaInfo named/6495 + 6490:
/// gọi orig lấy data thật, chỉ THAY VECTOR bằng mô phỏng nhiễu quanh trọng lực.
/// Giữ timestamp/structure → app không flag "sensor chết".

typedef struct {
    double x, y, z;
} MCVec3;

static MCVec3 MCGSensorNoise(double t, double base, double amp, double freq) {
    // Nhiễu sin/cos deterministic theo thời gian — không cần state.
    MCVec3 v;
    v.x = base + amp * sin(2 * M_PI * freq * t + 0.3);
    v.y = base * 0.02 + amp * 0.6 * cos(2 * M_PI * freq * 0.7 * t);
    v.z = base + amp * sin(2 * M_PI * freq * 1.1 * t + 1.7);
    return v;
}

static BOOL MCGSensorOn(void) {
    return [MCConfig sharedConfig].fakeSensorsEnabled;
}

// ---- CMAccelerometerData.acceleration → struct CMAcceleration {x,y,z} ----
typedef struct { double x, y, z; } CMAccelStruct;

static CMAccelStruct (*gOrigAccelData)(id, SEL);

static CMAccelStruct MCHookedAccelData(id self, SEL _cmd) {
    CMAccelStruct orig = gOrigAccelData(self, _cmd);
    if (!MCGSensorOn()) return orig;
    double t = CACurrentMediaTime();
    MCVec3 v = MCGSensorNoise(t, -1.0, 0.02, 1.0);  // gravity -1g Z + rung nhẹ
    CMAccelStruct out = { v.x, v.y, v.z };
    return out;
}

// ---- CMGyroData.rotationRate → struct CMRotationRate {x,y,z} ----
typedef struct { double x, y, z; } CMGyroStruct;

static CMGyroStruct (*gOrigGyroData)(id, SEL);

static CMGyroStruct MCHookedGyroData(id self, SEL _cmd) {
    CMGyroStruct orig = gOrigGyroData(self, _cmd);
    if (!MCGSensorOn()) return orig;
    double t = CACurrentMediaTime();
    MCVec3 v = MCGSensorNoise(t, 0.0, 0.05, 0.8);  // quanh 0 ±0.05 rad/s
    CMGyroStruct out = { v.x, v.y, v.z };
    return out;
}

// ---- CMDeviceMotion: gravity / userAcceleration / rotationRate ----
typedef struct { double x, y, z; } CMVec;
typedef CMVec (*MCVecGetterIMP)(id, SEL);
static MCVecGetterIMP gOrigGravity;
static MCVecGetterIMP gOrigUserAccel;
static MCVecGetterIMP gOrigRotRate;

static CMVec MCHookedGravity(id self, SEL _cmd) {
    CMVec orig = gOrigGravity(self, _cmd);
    if (!MCGSensorOn()) return orig;
    double t = CACurrentMediaTime();
    MCVec3 v = MCGSensorNoise(t, 0.0, 0.02, 1.0);
    CMVec out = { v.x, v.y, -1.0 + v.z * 0.02 };
    return out;
}

static CMVec MCHookedUserAccel(id self, SEL _cmd) {
    CMVec orig = gOrigUserAccel(self, _cmd);
    if (!MCGSensorOn()) return orig;
    double t = CACurrentMediaTime();
    MCVec3 v = MCGSensorNoise(t + 0.7, 0.0, 0.01, 1.3);
    CMVec out = { v.x, v.y, v.z };
    return out;
}

static CMVec MCHookedRotRate(id self, SEL _cmd) {
    CMVec orig = gOrigRotRate(self, _cmd);
    if (!MCGSensorOn()) return orig;
    double t = CACurrentMediaTime();
    MCVec3 v = MCGSensorNoise(t + 1.3, 0.0, 0.04, 0.9);
    CMVec out = { v.x, v.y, v.z };
    return out;
}

static BOOL gHooked;

void MCHookMotionInstall(void) {
    if (gHooked) return;
    gHooked = YES;

    Class accel = objc_getClass("CMAccelerometerData");
    if (accel) {
        MCSwizzleInstance(accel, sel_registerName("acceleration"), (IMP)MCHookedAccelData, (IMP *)&gOrigAccelData);
    }
    Class gyro = objc_getClass("CMGyroData");
    if (gyro) {
        MCSwizzleInstance(gyro, sel_registerName("rotationRate"), (IMP)MCHookedGyroData, (IMP *)&gOrigGyroData);
    }
    Class dm = objc_getClass("CMDeviceMotion");
    if (dm) {
        MCSwizzleInstance(dm, sel_registerName("gravity"), (IMP)MCHookedGravity, (IMP *)&gOrigGravity);
        MCSwizzleInstance(dm, sel_registerName("userAcceleration"), (IMP)MCHookedUserAccel, (IMP *)&gOrigUserAccel);
        MCSwizzleInstance(dm, sel_registerName("rotationRate"), (IMP)MCHookedRotRate, (IMP *)&gOrigRotRate);
    }
}
