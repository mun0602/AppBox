#import "MCConfig.h"
#import "MCRebind.h"
#import "MCSwizzle.h"

#import <CoreMotion/CoreMotion.h>
#import <Metal/Metal.h>
#import <dlfcn.h>
#import <stdio.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <objc/runtime.h>
#import <stdint.h>
#import <string.h>

typedef id<MTLDevice> (*MTLCreateDeviceFn)(void);
static MTLCreateDeviceFn gOrigMTLCreateDevice;

static NSString *MCGPUNameForModel(NSString *model) {
    if (!model || model.length == 0) return @"Apple GPU";
    if ([model hasPrefix:@"iPhone18,"]) return @"Apple A19 GPU";
    if ([model hasPrefix:@"iPhone17,"]) return @"Apple A18 GPU";
    if ([model hasPrefix:@"iPhone16,"]) return @"Apple A17 GPU";
    if ([model hasPrefix:@"iPhone15,"]) return @"Apple A16 GPU";
    if ([model hasPrefix:@"iPhone14,"]) return @"Apple A15 GPU";
    if ([model hasPrefix:@"iPhone13,"]) return @"Apple A14 GPU";
    if ([model hasPrefix:@"iPhone12,"]) return @"Apple A13 GPU";
    if ([model hasPrefix:@"iPhone11,"]) return @"Apple A12 GPU";
    if ([model hasPrefix:@"iPhone10,"]) return @"Apple A11 GPU";
    return @"Apple GPU";
}

static id MCHookedMTLDeviceName(id self, SEL _cmd) {
    MCConfig *c = [MCConfig sharedConfig];
    return MCGPUNameForModel(c.deviceModel);
}

static uint64_t MCHookedMTLDeviceMemory(id self, SEL _cmd) {
    MCConfig *c = [MCConfig sharedConfig];
    if (c.memsizeBytes > 0) {
        return c.memsizeBytes;
    }
    return 6442450944ULL; // 6GB mặc định
}

static id<MTLDevice> MCHookedMTLCreateSystemDefaultDevice(void) NS_RETURNS_RETAINED;

static id<MTLDevice> MCRealDevice(void) {
    static id<MTLDevice> cached;
    static __thread int depth;
    if (cached) return cached;
    if (depth) return nil;
    depth++;
    if (!gOrigMTLCreateDevice || gOrigMTLCreateDevice == MCHookedMTLCreateSystemDefaultDevice
        || !MCPointerInSystemImage((void *)gOrigMTLCreateDevice)) {
        void *real = MCInterposeReplacee((void *)MCHookedMTLCreateSystemDefaultDevice);
        if (MCPointerInSystemImage(real)) gOrigMTLCreateDevice = (MTLCreateDeviceFn)real;
        if (!gOrigMTLCreateDevice) {
            void *image = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_NOLOAD);
            if (!image) image = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_LAZY);
            void *sym = image ? dlsym(image, "MTLCreateSystemDefaultDevice") : NULL;
            if (MCPointerInSystemImage(sym)) gOrigMTLCreateDevice = (MTLCreateDeviceFn)sym;
        }
    }
    __block id<MTLDevice> dev = nil;
    if (gOrigMTLCreateDevice) {
        if ([NSThread isMainThread]) {
            dev = gOrigMTLCreateDevice();
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                dev = gOrigMTLCreateDevice();
            });
        }
    }
    if (!dev) {
        void *image = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_LAZY);
        NSArray *(*copyAll)(void) = image ? dlsym(image, "MTLCopyAllDevices") : NULL;
        if (MCPointerInSystemImage((void *)copyAll)) {
            NSArray *all = copyAll();
            if (all.count > 0) dev = all.firstObject;
        }
    }
    if (dev) cached = dev;
    depth--;
    return dev;
}

@interface MCGPUNameProxy : NSObject
@end
@implementation MCGPUNameProxy
- (NSString *)name {
    return MCGPUNameForModel([[MCConfig sharedConfig] deviceModel]);
}
@end

static int MCCallerInMainExecutable(const void *addr) {
    if (!addr) return 0;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *mh = _dyld_get_image_header(i);
        if (!mh || mh->magic != MH_MAGIC_64 || mh->filetype != MH_EXECUTE) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct mach_header_64 *mh64 = (const struct mach_header_64 *)mh;
        const uint8_t *p = (const uint8_t *)(mh64 + 1);
        for (uint32_t c = 0; c < mh64->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)p;
            if (lc->cmdsize < sizeof(*lc)) break;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                uintptr_t start = (uintptr_t)seg->vmaddr + (uintptr_t)slide;
                uintptr_t end = start + (uintptr_t)seg->vmsize;
                if ((uintptr_t)addr >= start && (uintptr_t)addr < end) return 1;
            }
            p += lc->cmdsize;
        }
    }
    return 0;
}

// Metal khai báo NS_RETURNS_RETAINED. Thiếu attribute thì ARC autorelease,
// caller giải phóng thêm một lần, pool của createScene đụng con trỏ đã chết.
static id<MTLDevice> MCHookedMTLCreateSystemDefaultDevice(void) NS_RETURNS_RETAINED {
    id<MTLDevice> dev = MCRealDevice();
    if (dev) {
        Class cls = [dev class];
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            IMP prevName = NULL;
            MCSwizzleInstance(cls, sel_registerName("name"), (IMP)MCHookedMTLDeviceName, &prevName);
            IMP prevMem = NULL;
            MCSwizzleInstance(cls, sel_registerName("recommendedMaxWorkingSetSize"), (IMP)MCHookedMTLDeviceMemory, &prevMem);
        });
        return dev;
    }
    // UIKit gọi từ ảnh hệ thống. App đo gọi từ binary chính.
    if (MCCallerInMainExecutable(__builtin_return_address(0))) {
        return (id<MTLDevice>)[MCGPUNameProxy new];
    }
    return nil;
}

static BOOL MCHookedAlwaysTrue(id self, SEL _cmd) {
    return YES;
}

#define DYLD_INTERPOSE(_replacement,_replacee) \
__attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

DYLD_INTERPOSE(MCHookedMTLCreateSystemDefaultDevice, MTLCreateSystemDefaultDevice)

void MCHookWolverineInstall(void) {
    static BOOL gHooked;
    if (gHooked) return;
    gHooked = YES;

    MCRebindSymbol("MTLCreateSystemDefaultDevice", (void *)MCHookedMTLCreateSystemDefaultDevice, (void **)&gOrigMTLCreateDevice);

    Class cm = objc_getClass("CMMotionManager");
    if (cm) {
        IMP p1 = NULL, p2 = NULL, p3 = NULL, p4 = NULL;
        MCSwizzleInstance(cm, sel_registerName("isAccelerometerAvailable"), (IMP)MCHookedAlwaysTrue, &p1);
        MCSwizzleInstance(cm, sel_registerName("isGyroAvailable"), (IMP)MCHookedAlwaysTrue, &p2);
        MCSwizzleInstance(cm, sel_registerName("isMagnetometerAvailable"), (IMP)MCHookedAlwaysTrue, &p3);
        MCSwizzleInstance(cm, sel_registerName("isDeviceMotionAvailable"), (IMP)MCHookedAlwaysTrue, &p4);
    }

    Class alt = objc_getClass("CMAltimeter");
    if (alt) {
        IMP p = NULL;
        Class meta = object_getClass((id)alt);
        MCSwizzleInstance(meta, sel_registerName("isRelativeAltitudeAvailable"), (IMP)MCHookedAlwaysTrue, &p);
    }
}
