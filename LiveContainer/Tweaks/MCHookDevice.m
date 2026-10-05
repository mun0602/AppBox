#import "MCConfig.h"
#import "MCSwizzle.h"

#import <mach/mach.h>
#import <mach/mach_host.h>
#import <objc/runtime.h>
#import <sys/time.h>
#import <time.h>

typedef NSString *(*MCStringIMP)(id, SEL);
typedef NSUUID *(*MCUUIDIMP)(id, SEL);
typedef NSTimeInterval (*MCTimeIMP)(id, SEL);
typedef NSUInteger (*MCCountIMP)(id, SEL);
typedef unsigned long long (*MCMemIMP)(id, SEL);
typedef struct {
    NSInteger major;
    NSInteger minor;
    NSInteger patch;
} MCNSOperatingSystemVersion;
typedef MCNSOperatingSystemVersion (*MCOSVersionIMP)(id, SEL);

static MCStringIMP gOrigModel;
static MCStringIMP gOrigName;
static MCStringIMP gOrigLocalizedModel;
static MCStringIMP gOrigSystemVersion;
static MCUUIDIMP gOrigVendor;
static MCOSVersionIMP gOrigOSVersion;
static MCStringIMP gOrigOSVersionString;
static MCTimeIMP gOrigUptime;
static MCCountIMP gOrigProcessorCount;
static MCCountIMP gOrigActiveProcessorCount;
static MCMemIMP gOrigPhysicalMemory;
static MCStringIMP gOrigHostName;

static BOOL gHookedModel;
static BOOL gHookedName;
static BOOL gHookedLocalizedModel;
static BOOL gHookedSystemVersion;
static BOOL gHookedVendor;
static BOOL gHookedOSVersion;
static BOOL gHookedOSVersionString;
static BOOL gHookedUptime;
static BOOL gHookedProcessorCount;
static BOOL gHookedActiveProcessorCount;
static BOOL gHookedPhysicalMemory;
static BOOL gHookedHostName;

static NSString *MCCallOriginal(MCStringIMP original, id self, SEL _cmd) {
    return original ? original(self, _cmd) : nil;
}

static NSString *MCHookedModel(id self, SEL _cmd) {
    NSString *fake = [[MCConfig sharedConfig] deviceModel];
    if (fake.length > 0) {
        if ([fake containsString:@"iPad"]) return @"iPad";
        if ([fake containsString:@"iPod"]) return @"iPod touch";
        return @"iPhone";
    }
    return MCCallOriginal(gOrigModel, self, _cmd) ?: @"iPhone";
}

static NSString *MCHookedName(id self, SEL _cmd) {
    NSString *fake = [[MCConfig sharedConfig] deviceName];
    if (fake.length > 0) {
        return fake;
    }
    return MCCallOriginal(gOrigName, self, _cmd);
}

static NSString *MCHookedLocalizedModel(id self, SEL _cmd) {
    NSString *fake = [[MCConfig sharedConfig] deviceModel];
    if (fake.length > 0) {
        if ([fake containsString:@"iPad"]) return @"iPad";
        if ([fake containsString:@"iPod"]) return @"iPod touch";
        return @"iPhone";
    }
    return MCCallOriginal(gOrigLocalizedModel, self, _cmd) ?: @"iPhone";
}

static NSString *MCHookedSystemVersion(id self, SEL _cmd) {
    NSString *fake = [[MCConfig sharedConfig] systemVersion];
    if (fake.length > 0) {
        return fake;
    }
    return MCCallOriginal(gOrigSystemVersion, self, _cmd);
}

static NSUUID *MCHookedVendor(id self, SEL _cmd) {
    NSUUID *fake = [[MCConfig sharedConfig] vendorUUID];
    if (fake) {
        return fake;
    }
    return gOrigVendor ? gOrigVendor(self, _cmd) : nil;
}

static MCNSOperatingSystemVersion MCHookedOSVersion(id self, SEL _cmd) {
    NSString *fake = [[MCConfig sharedConfig] systemVersion];
    if (fake.length > 0) {
        NSArray<NSString *> *parts = [fake componentsSeparatedByString:@"."];
        MCNSOperatingSystemVersion v = {0, 0, 0};
        v.major = parts.count > 0 ? [parts[0] integerValue] : 0;
        v.minor = parts.count > 1 ? [parts[1] integerValue] : 0;
        v.patch = parts.count > 2 ? [parts[2] integerValue] : 0;
        return v;
    }
    return gOrigOSVersion ? gOrigOSVersion(self, _cmd) : (MCNSOperatingSystemVersion){0, 0, 0};
}

static NSString *MCHookedOSVersionString(id self, SEL _cmd) {
    NSString *fake = [[MCConfig sharedConfig] systemVersion];
    if (fake.length > 0) {
        return [NSString stringWithFormat:@"Version %@ (Build %@)", fake,
                [[MCConfig sharedConfig] buildVersion] ?: @""];
    }
    return MCCallOriginal(gOrigOSVersionString, self, _cmd);
}

static NSTimeInterval MCHookedUptime(id self, SEL _cmd) {
    MCConfig *c = [MCConfig sharedConfig];
    if (c.boottimeSec > 0) {
        struct timeval now;
        gettimeofday(&now, NULL);
        NSTimeInterval up = (NSTimeInterval)(now.tv_sec - c.boottimeSec);
        up += ((NSTimeInterval)now.tv_usec - (NSTimeInterval)c.boottimeUsec) / 1.0e6;
        return up > 1.0 ? up : 1.0;
    }
    return gOrigUptime ? gOrigUptime(self, _cmd) : 0;
}

static NSUInteger MCHookedProcessorCount(id self, SEL _cmd) {
    int n = [[MCConfig sharedConfig] cpuCount];
    if (n > 0) return (NSUInteger)n;
    return gOrigProcessorCount ? gOrigProcessorCount(self, _cmd) : 0;
}

static NSUInteger MCHookedActiveProcessorCount(id self, SEL _cmd) {
    int n = [[MCConfig sharedConfig] cpuCount];
    if (n > 0) return (NSUInteger)n;
    return gOrigActiveProcessorCount ? gOrigActiveProcessorCount(self, _cmd) : 0;
}

static unsigned long long MCHookedPhysicalMemory(id self, SEL _cmd) {
    uint64_t m = [[MCConfig sharedConfig] memsizeBytes];
    if (m > 0) return m;
    return gOrigPhysicalMemory ? gOrigPhysicalMemory(self, _cmd) : 0;
}

static NSDate *MCHookedSystemBootTime(id self, SEL _cmd) {
    int64_t sec = [[MCConfig sharedConfig] boottimeSec];
    if (sec > 0) return [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)sec];
    return nil;
}

static NSString *MCHookedHostName(id self, SEL _cmd) {
    NSString *h = [[MCConfig sharedConfig] hostName];
    if (h.length > 0) return h;
    return MCCallOriginal(gOrigHostName, self, _cmd);
}

static BOOL MCHookOne(Class cls, const char *selName, IMP replacement, MCStringIMP *original) {
    IMP previous = NULL;
    if (!MCSwizzleInstance(cls, sel_registerName(selName), replacement, &previous)) {
        return NO;
    }
    *original = (MCStringIMP)previous;
    return YES;
}

static uint64_t gCachedMem;
static int gCachedCPU;

static kern_return_t MCHookedHostInfo(host_t host, host_flavor_t flavor, host_info_t info, mach_msg_type_number_t *count) {
    static __thread int depth;
    if (depth) return KERN_FAILURE;
    depth++;
    kern_return_t kr = host_info(host, flavor, info, count);
    depth--;
    if (kr == KERN_SUCCESS && flavor == HOST_BASIC_INFO && info) {
        host_basic_info_t basic = (host_basic_info_t)info;
        if (gCachedMem > 0) basic->max_mem = gCachedMem;
        if (gCachedCPU > 0) {
            basic->logical_cpu = gCachedCPU;
            basic->logical_cpu_max = gCachedCPU;
            basic->physical_cpu = gCachedCPU;
            basic->physical_cpu_max = gCachedCPU;
        }
    }
    return kr;
}

static kern_return_t MCHookedHostStats64(host_t host, host_flavor_t flavor, host_info64_t info, mach_msg_type_number_t *count) {
    static __thread int depth;
    if (depth) return KERN_FAILURE;
    depth++;
    kern_return_t kr = host_statistics64(host, flavor, info, count);
    depth--;
    if (kr == KERN_SUCCESS && flavor == HOST_VM_INFO64 && info && gCachedMem > 0) {
        vm_statistics64_t vm = (vm_statistics64_t)info;
        vm_size_t psz = 0;
        host_page_size(host, &psz);
        if (psz == 0) psz = 16384;
        uint64_t have = (uint64_t)vm->active_count + vm->inactive_count + vm->wire_count + vm->free_count + vm->compressor_page_count;
        uint64_t want = gCachedMem / psz;
        if (want > have) vm->free_count += (natural_t)(want - have);
    }
    return kr;
}

#define DYLD_INTERPOSE(_replacement,_replacee) \
__attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

DYLD_INTERPOSE(MCHookedHostInfo, host_info)
DYLD_INTERPOSE(MCHookedHostStats64, host_statistics64)

void MCHookDeviceInstall(void) {
    Class cls = objc_getClass("UIDevice");
    if (cls) {
        if (!gHookedModel) {
            gHookedModel = MCHookOne(cls, "model", (IMP)MCHookedModel, &gOrigModel);
        }
        if (!gHookedName) {
            gHookedName = MCHookOne(cls, "name", (IMP)MCHookedName, &gOrigName);
        }
        if (!gHookedLocalizedModel) {
            gHookedLocalizedModel = MCHookOne(cls, "localizedModel", (IMP)MCHookedLocalizedModel, &gOrigLocalizedModel);
        }
        if (!gHookedSystemVersion) {
            gHookedSystemVersion = MCHookOne(cls, "systemVersion", (IMP)MCHookedSystemVersion, &gOrigSystemVersion);
        }
        if (!gHookedVendor) {
            IMP previous = NULL;
            if (MCSwizzleInstance(cls, sel_registerName("identifierForVendor"), (IMP)MCHookedVendor, &previous)) {
                gOrigVendor = (MCUUIDIMP)previous;
                gHookedVendor = YES;
            }
        }
    }
    Class pi = objc_getClass("NSProcessInfo");
    if (pi) {
        if (!gHookedOSVersion) {
            IMP previous = NULL;
            if (MCSwizzleInstance(pi, sel_registerName("operatingSystemVersion"), (IMP)MCHookedOSVersion, &previous)) {
                gOrigOSVersion = (MCOSVersionIMP)previous;
                gHookedOSVersion = YES;
            }
        }
        if (!gHookedOSVersionString) {
            IMP previous = NULL;
            if (MCSwizzleInstance(pi, sel_registerName("operatingSystemVersionString"), (IMP)MCHookedOSVersionString, &previous)) {
                gOrigOSVersionString = (MCStringIMP)previous;
                gHookedOSVersionString = YES;
            }
        }
        if (!gHookedUptime) {
            IMP previous = NULL;
            if (MCSwizzleInstance(pi, sel_registerName("systemUptime"), (IMP)MCHookedUptime, &previous)) {
                gOrigUptime = (MCTimeIMP)previous;
                gHookedUptime = YES;
            }
        }
        if (!gHookedProcessorCount) {
            IMP previous = NULL;
            if (MCSwizzleInstance(pi, sel_registerName("processorCount"), (IMP)MCHookedProcessorCount, &previous)) {
                gOrigProcessorCount = (MCCountIMP)previous;
                gHookedProcessorCount = YES;
            }
        }
        if (!gHookedActiveProcessorCount) {
            IMP previous = NULL;
            if (MCSwizzleInstance(pi, sel_registerName("activeProcessorCount"), (IMP)MCHookedActiveProcessorCount, &previous)) {
                gOrigActiveProcessorCount = (MCCountIMP)previous;
                gHookedActiveProcessorCount = YES;
            }
        }
        if (!gHookedPhysicalMemory) {
            IMP previous = NULL;
            if (MCSwizzleInstance(pi, sel_registerName("physicalMemory"), (IMP)MCHookedPhysicalMemory, &previous)) {
                gOrigPhysicalMemory = (MCMemIMP)previous;
                gHookedPhysicalMemory = YES;
            }
        }
        if (!gHookedHostName) {
            IMP previous = NULL;
            if (MCSwizzleInstance(pi, sel_registerName("hostName"), (IMP)MCHookedHostName, &previous)) {
                gOrigHostName = (MCStringIMP)previous;
                gHookedHostName = YES;
            }
        }
        gCachedMem = [[MCConfig sharedConfig] memsizeBytes];
        gCachedCPU = [[MCConfig sharedConfig] cpuCount];

        SEL bootSel = sel_registerName("systemBootTime");
        if (class_getInstanceMethod(pi, bootSel)) {
            IMP previous = NULL;
            MCSwizzleInstance(pi, bootSel, (IMP)MCHookedSystemBootTime, &previous);
        } else {
            class_addMethod(pi, bootSel, (IMP)MCHookedSystemBootTime, "@@:");
        }
    }
}
