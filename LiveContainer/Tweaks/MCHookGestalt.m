#import "MCConfig.h"
#import "MCInlineHook.h"
#import "MCRebind.h"

// MCLogLine định nghĩa trong MCMain.m — dùng cho log key sysctl rơi fallback.
extern void MCLogLine(NSString *message);

#import <stdbool.h>
// sys/proc.h is macOS-only; P_TRACED is the only thing we need from it (value=0x80).
#define P_TRACED 0x00000080
#include <sys/sysctl.h>
#import <sys/utsname.h>
#import <errno.h>
#import <stdarg.h>
#import <string.h>
#import <unistd.h>
#import <dlfcn.h>
#import <sys/syscall.h>

void MCHookedNWSetUpdate(void *monitor, void (^handler)(void *path));
bool MCHookedNWUses(void *path, int type);

typedef CFTypeRef (*MCGestaltFn)(CFStringRef);
typedef int (*MCSysctlFn)(const char *, void *, size_t *, void *, size_t);
typedef int (*MCUnameFn)(struct utsname *);

static MCGestaltFn gOrigGestalt;
static MCSysctlFn gOrigSysctl;
static MCUnameFn gOrigUname;

static id MCGestaltFake(NSString *key) {
    MCConfig *c = [MCConfig sharedConfig];
    // Key obfuscate của MobileGestalt (app App Store dùng dạng này; danh sách
    // lấy từ libdylib1.dylib vendored trong XoaInfo).
    static NSDictionary<NSString *, NSString *> *obf = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        obf = @{
            @"h9jDsQjKXl7zZE5Yrt5ftg" : @"ProductType",
            @"j8yXztHhBQHN6TFf2sQm5w" : @"SerialNumber",
            @"0Y4fmR6ZHZPxDZFfPtBnRQ" : @"UniqueDeviceID",
            @"mZfUC7qo4pURNhyMHZ62RQ" : @"SerialNumber",
            @"h63QSdBCiT/z0WU6rdQv6Q" : @"ProductVersion",
            @"aoAKcHLuTUp/o3squcJkhA" : @"ProductType",
            @"lo3szoQ4sLy7o3+ZD0GcAQ" : @"BuildVersion",
            @"q4cLktMwtrx8dCJAQTeqTg" : @"UserAssignedDeviceName",
            @"z5WdOli5YaLOZmQaQpxPrg" : @"DeviceName",
        };
    });
    NSString *mapped = obf[key];
    if (mapped) {
        return MCGestaltFake(mapped);
    }
    if ([key isEqualToString:@"ProductType"]) {
        return c.deviceModel;
    }
    // HardwareModel là BOARD id (D64AP) — trả ProductType là bất thường cross-check
    // (đo 2026-10-02: MGCopyAnswer(HardwareModel) => iPhone14,3 — sai).
    if ([key isEqualToString:@"HWModelStr"] || [key isEqualToString:@"HardwareModel"]) {
        return c.hwModel.length > 0 ? c.hwModel : c.deviceModel;
    }
    // CPUArchitecture: hằng arm64e cho mọi iPhone A7+; nil là dấu bất thường.
    if ([key isEqualToString:@"CPUArchitecture"]) {
        return @"arm64e";
    }
    if ([key isEqualToString:@"ProductVersion"]) {
        return c.systemVersion;
    }
    if ([key isEqualToString:@"BuildVersion"]) {
        return c.buildVersion;
    }
    if ([key isEqualToString:@"SerialNumber"]) {
        return c.serialNumber;
    }
    if ([key isEqualToString:@"UniqueDeviceID"]) {
        return c.udid;
    }
    if ([key isEqualToString:@"UserAssignedDeviceName"] || [key isEqualToString:@"DeviceName"]) {
        return c.deviceName;
    }
    if ([key isEqualToString:@"InternationalMobileEquipmentIdentity"] || [key isEqualToString:@"IMEI"]) {
        return c.imei;
    }
    if ([key isEqualToString:@"InternationalMobileSubscriberIdentity"] || [key isEqualToString:@"IMSI"]) {
        return c.imsi;
    }
    if ([key isEqualToString:@"HardwarePlatform"]) {
        return c.hardwarePlatform;
    }
    if ([key isEqualToString:@"WiFiAddress"]) {
        return c.wifiAddress;
    }
    if ([key isEqualToString:@"BluetoothAddress"]) {
        return c.bluetoothAddress;
    }
    if ([key isEqualToString:@"BoardId"]) {
        if (c.boardId.length > 0) {
            unsigned int v = 0;
            if ([[NSScanner scannerWithString:c.boardId] scanHexInt:&v] || [[NSScanner scannerWithString:c.boardId] scanInt:(int *)&v]) {
                return @(v);
            }
            return c.boardId;
        }
    }
    if ([key isEqualToString:@"ChipID"] || [key isEqualToString:@"UniqueChipID"] || [key isEqualToString:@"DieId"]) {
        if (c.chipId.length > 0) {
            unsigned int v = 0;
            if ([[NSScanner scannerWithString:c.chipId] scanHexInt:&v] || [[NSScanner scannerWithString:c.chipId] scanInt:(int *)&v]) {
                return @(v);
            }
            return c.chipId;
        }
    }
    return nil;
}

static CFTypeRef MCHookedGestalt(CFStringRef key) {
    if (key) {
        id fake = MCGestaltFake((__bridge NSString *)key);
        if (fake) {
            return CFBridgingRetain(fake);
        }
    }
    if (gOrigGestalt && gOrigGestalt != (MCGestaltFn)MCHookedGestalt) {
        return gOrigGestalt(key);
    }
    return NULL;
}

static int MCFillCString(void *oldp, size_t *oldlenp, NSString *value) {
    if (!value) {
        return -1;
    }
    const char *utf = value.UTF8String ?: "";
    size_t n = strlen(utf) + 1;
    if (oldp == NULL) {
        if (oldlenp) *oldlenp = n;
        return 0;
    }
    if (!oldlenp || *oldlenp < n) {
        if (oldlenp) *oldlenp = n;
        errno = ENOMEM;
        return -1;
    }
    memcpy(oldp, utf, n);
    *oldlenp = n;
    return 0;
}

static int MCFillBytes(void *oldp, size_t *oldlenp, const void *src, size_t n) {
    if (oldp == NULL) {
        if (oldlenp) *oldlenp = n;
        return 0;
    }
    if (!oldlenp || *oldlenp < n) {
        if (oldlenp) *oldlenp = n;
        errno = ENOMEM;
        return -1;
    }
    memcpy(oldp, src, n);
    *oldlenp = n;
    return 0;
}

static int MCHookedSysctl(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && newp == NULL) {
        MCConfig *c = [MCConfig sharedConfig];
        if (strcmp(name, "hw.machine") == 0 && c.deviceModel.length > 0) {
            return MCFillCString(oldp, oldlenp, c.deviceModel);
        }
        if (strcmp(name, "hw.model") == 0) {
            NSString *hwModel = c.hwModel.length > 0 ? c.hwModel : c.deviceModel;
            return MCFillCString(oldp, oldlenp, hwModel);
        }
        if (strcmp(name, "kern.osproductversion") == 0 && c.systemVersion.length > 0) {
            return MCFillCString(oldp, oldlenp, c.systemVersion);
        }
        // kern.ostype/osrelease: giá trị hằng của Darwin — hook không có nhánh này
        // thì rơi vào fallback gãy (gOrigSysctl NULL dưới interpose tĩnh) và trả -1,
        // app thấy sysctl fail bất thường (đo trực tiếp 2026-10-02: rc=-1).
        if (strcmp(name, "kern.ostype") == 0) {
            return MCFillCString(oldp, oldlenp, @"Darwin");
        }
        if (strcmp(name, "kern.osrelease") == 0 && c.darwinRelease.length > 0) {
            return MCFillCString(oldp, oldlenp, c.darwinRelease);
        }
        // kern.version: chuỗi kernel đầy đủ chứa Darwin version THẬT — monitor
        // 2026-10-02 bắt được Kwai đọc key này (leak nếu bỏ qua).
        if (strcmp(name, "kern.version") == 0 && c.darwinRelease.length > 0) {
            NSString *board = @"T8110";
            NSString *model = c.deviceModel ?: @"";
            if ([model hasPrefix:@"iPhone15,"]) board = @"T8120";
            else if ([model hasPrefix:@"iPhone16,"]) board = @"T8122";
            else if ([model hasPrefix:@"iPhone17,"]) board = @"T8132";
            NSString *kv = [NSString stringWithFormat:@"Darwin Kernel Version %@: root:xnu-RELEASE_ARM64_%@", c.darwinRelease, board];
            return MCFillCString(oldp, oldlenp, kv);
        }
        // hw.cputype / hw.cpusubtype: monitor 2026-10-02 thấy Kwai đọc; thiếu
        // nhánh này thì fallback -1.
        if (strcmp(name, "hw.cputype") == 0 && c.cpuType != 0) {
            uint32_t v = c.cpuType;
            return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
        }
        if (strcmp(name, "hw.cpusubtype") == 0 && c.cpuSubtype != 0) {
            uint32_t v = c.cpuSubtype;
            return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
        }
        // Hằng số an toàn trên mọi arm64 iOS — không mang identity nhưng fallback
        // gãy (trả -1) là dấu hiệu sysctl fail bất thường (monitor thấy Kwai đọc
        // hw.pagesize). byteorder 1234 = little-endian, cacheline 128B.
        if (strcmp(name, "hw.pagesize") == 0) {
            int v = 16384;
            return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
        }
        if (strcmp(name, "hw.byteorder") == 0) {
            int32_t v = 1234;
            return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
        }
        if (strcmp(name, "hw.cachelinesize") == 0) {
            int v = 128;
            return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
        }
        if (strcmp(name, "hw.availcpu") == 0 && c.cpuCount > 0) {
            int v = c.cpuCount;
            return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
        }
        if (strcmp(name, "kern.osversion") == 0 && c.buildVersion.length > 0) {
            return MCFillCString(oldp, oldlenp, c.buildVersion);
        }
        if (strcmp(name, "kern.hostname") == 0 && c.hostName.length > 0) {
            return MCFillCString(oldp, oldlenp, c.hostName);
        }
        if (strcmp(name, "kern.bootsessionuuid") == 0 && c.bootSessionUUID.length > 0) {
            return MCFillCString(oldp, oldlenp, c.bootSessionUUID);
        }
        if (strcmp(name, "hw.memsize") == 0 && c.memsizeBytes > 0) {
            uint64_t v = c.memsizeBytes;
            return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
        }
        if ((strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.physicalcpu") == 0 ||
             strcmp(name, "hw.logicalcpu") == 0 || strcmp(name, "hw.activecpu") == 0 ||
             strcmp(name, "hw.physicalcpu_max") == 0 || strcmp(name, "hw.logicalcpu_max") == 0) &&
            c.cpuCount > 0) {
            int v = c.cpuCount;
            return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
        }
        if (strcmp(name, "hw.cpufamily") == 0 && c.cpuFamily != 0) {
            uint32_t v = c.cpuFamily;
            return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
        }
        if ((strcmp(name, "hw.cpufrequency") == 0 || strcmp(name, "hw.cpufrequency_max") == 0 ||
             strcmp(name, "hw.cpufrequency_min") == 0) &&
            c.cpuFrequencyHz > 0) {
            uint64_t v = c.cpuFrequencyHz;
            return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
        }
        if (strcmp(name, "kern.boottime") == 0 && c.boottimeSec > 0) {
            struct timeval tv;
            memset(&tv, 0, sizeof(tv));
            tv.tv_sec = (time_t)c.boottimeSec;
            tv.tv_usec = (suseconds_t)c.boottimeUsec;
            return MCFillBytes(oldp, oldlenp, &tv, sizeof(tv));
        }
    }
    if (name && strcmp(name, "net.host_cache") == 0 && newp == NULL) {
        if (gOrigSysctl && gOrigSysctl != (MCSysctlFn)MCHookedSysctl
            && gOrigSysctl(name, oldp, oldlenp, newp, newlen) == 0) {
            return 0;
        }
        if (oldp == NULL) {
            if (oldlenp) *oldlenp = 4;
            return 0;
        }
        if (oldlenp && *oldlenp >= 4) {
            memset(oldp, 0, 4);
            *oldlenp = 4;
            return 0;
        }
    }
    if (gOrigSysctl && gOrigSysctl != (MCSysctlFn)MCHookedSysctl) {
        return gOrigSysctl(name, oldp, oldlenp, newp, newlen);
    }
    // Fallback gãy (gOrigSysctl NULL dưới interpose tĩnh) — log key để monitor
    // bắt được key nào cần thêm vào map thay vì fail âm thầm. Có depth-guard
    // vì os_log cấp phát bộ nhớ trong lúc sysctl đang chạy.
    static __thread int sDepth = 0;
    if (name && sDepth == 0) {
        sDepth++;
        MCLogLine([NSString stringWithFormat:@"sysctl FALLBACK rc=-1 key=%s (them vao map hoac sua passthrough)", name]);
        sDepth--;
    }
    return -1;
}

typedef int (*MCSysctlRawFn)(int *, u_int, void *, size_t *, void *, size_t);
static MCSysctlRawFn gOrigSysctlRaw;

static int MCHookedSysctlRaw(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && namelen >= 2 && newp == NULL) {
        MCConfig *c = [MCConfig sharedConfig];
        if (name[0] == CTL_HW) {
            if (name[1] == HW_MACHINE && c.deviceModel.length > 0) {
                return MCFillCString(oldp, oldlenp, c.deviceModel);
            }
            if (name[1] == HW_MODEL) {
                NSString *hwModel = c.hwModel.length > 0 ? c.hwModel : c.deviceModel;
                return MCFillCString(oldp, oldlenp, hwModel);
            }
            if (name[1] == HW_PHYSMEM && c.memsizeBytes > 0) {
                // HW_PHYSMEM historically int; prefer HW_MEMSIZE (64-bit) below.
                unsigned int v = (unsigned int)MIN(c.memsizeBytes, (uint64_t)UINT32_MAX);
                return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
            }
#ifdef HW_MEMSIZE
            if (name[1] == HW_MEMSIZE && c.memsizeBytes > 0) {
                uint64_t v = c.memsizeBytes;
                return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
            }
#endif
            if (name[1] == HW_NCPU && c.cpuCount > 0) {
                int v = c.cpuCount;
                return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
            }
#ifdef HW_AVAILCPU
            if (name[1] == HW_AVAILCPU && c.cpuCount > 0) {
                int v = c.cpuCount;
                return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
            }
#endif
#ifdef HW_PAGESIZE
            if (name[1] == HW_PAGESIZE) {
                int v = 16384;
                return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
            }
#endif
#ifdef HW_BYTEORDER
            if (name[1] == HW_BYTEORDER) {
                int32_t v = 1234;
                return MCFillBytes(oldp, oldlenp, &v, sizeof(v));
            }
#endif
        }
        if (name[0] == CTL_KERN) {
            // KERN_OSTYPE=1 / KERN_OSRELEASE=2: trả "Darwin"/darwinRelease thay vì
            // fallback -1 (đo 2026-10-02: Kwai sandbox gọi 2 key này fail rc=-1).
            if (name[1] == KERN_OSTYPE) {
                return MCFillCString(oldp, oldlenp, @"Darwin");
            }
            if (name[1] == KERN_OSRELEASE && c.darwinRelease.length > 0) {
                return MCFillCString(oldp, oldlenp, c.darwinRelease);
            }
            if (name[1] == KERN_OSVERSION && c.buildVersion.length > 0) {
                return MCFillCString(oldp, oldlenp, c.buildVersion);
            }
            if (name[1] == KERN_HOSTNAME && c.hostName.length > 0) {
                return MCFillCString(oldp, oldlenp, c.hostName);
            }
            if (name[1] == KERN_BOOTTIME && c.boottimeSec > 0) {
                struct timeval tv;
                memset(&tv, 0, sizeof(tv));
                tv.tv_sec = (time_t)c.boottimeSec;
                tv.tv_usec = (suseconds_t)c.boottimeUsec;
                return MCFillBytes(oldp, oldlenp, &tv, sizeof(tv));
            }
            if (name[1] == KERN_PROC && namelen >= 3 && name[2] == KERN_PROC_PID) {
                if (gOrigSysctlRaw && gOrigSysctlRaw != (MCSysctlRawFn)MCHookedSysctlRaw) {
                    int rc = gOrigSysctlRaw(name, namelen, oldp, oldlenp, newp, newlen);
                    if (rc == 0 && oldp && oldlenp && *oldlenp >= sizeof(struct kinfo_proc)) {
                        ((struct kinfo_proc *)oldp)->kp_proc.p_flag &= ~P_TRACED;
                        return 0;
                    }
                }
                if (oldp == NULL) {
                    if (oldlenp) *oldlenp = sizeof(struct kinfo_proc);
                    return 0;
                }
                if (oldlenp && *oldlenp >= sizeof(struct kinfo_proc)) {
                    memset(oldp, 0, sizeof(struct kinfo_proc));
                    ((struct kinfo_proc *)oldp)->kp_proc.p_pid = namelen >= 4 ? name[3] : getpid();
                    *oldlenp = sizeof(struct kinfo_proc);
                    return 0;
                }
            }
        }
    }
    if (gOrigSysctlRaw && gOrigSysctlRaw != (MCSysctlRawFn)MCHookedSysctlRaw) {
        return gOrigSysctlRaw(name, namelen, oldp, oldlenp, newp, newlen);
    }
    return -1;
}

static int MCHookedUname(struct utsname *buf) {
    if (!buf) {
        return -1;
    }
    int rc = -1;
    if (gOrigUname && gOrigUname != (MCUnameFn)MCHookedUname) {
        rc = gOrigUname(buf);
    }
    if (rc != 0) {
        memset(buf, 0, sizeof(*buf));
        strncpy(buf->sysname, "Darwin", sizeof(buf->sysname) - 1);
        strncpy(buf->release, "21.6.0", sizeof(buf->release) - 1);
        strncpy(buf->version, "Darwin Kernel", sizeof(buf->version) - 1);
        strncpy(buf->nodename, "iPhone", sizeof(buf->nodename) - 1);
        rc = 0;
    }
    MCConfig *c = [MCConfig sharedConfig];
    NSString *model = c.deviceModel;
    if (model.length > 0) {
        strncpy(buf->machine, model.UTF8String, sizeof(buf->machine) - 1);
        buf->machine[sizeof(buf->machine) - 1] = 0;
    }
    if (c.hostName.length > 0) {
        strncpy(buf->nodename, c.hostName.UTF8String, sizeof(buf->nodename) - 1);
        buf->nodename[sizeof(buf->nodename) - 1] = 0;
    }
    if (c.darwinRelease.length > 0) {
        strncpy(buf->release, c.darwinRelease.UTF8String, sizeof(buf->release) - 1);
        buf->release[sizeof(buf->release) - 1] = 0;
    }
    return rc;
}

// Bộ đệm C điền một lần lúc cài hook. Thân syscall không được malloc, NSString, log, dlsym.
typedef struct {
    int ready;
    char machine[96];
    char model[96];
    char osrelease[64];
    char osversion[64];
    char hostname[256];
    int hasMachine;
    int hasModel;
    int hasOsrelease;
    int hasOsversion;
    int hasHostname;
    uint64_t memsize;
    int cpuCount;
    time_t bootSec;
    int32_t bootUsec;
    int hasBoot;
} MCSysctlCache;

static MCSysctlCache gSysctlCache;
typedef int (*MCSyscallFn)(int, ...);
static MCSyscallFn gOrigSyscall;
static __thread int gSyscallDepth;

static void MCCachePut(char *dst, size_t cap, NSString *value, int *has) {
    *has = 0;
    if (cap == 0) return;
    dst[0] = 0;
    if (value.length == 0) return;
    const char *utf = value.UTF8String;
    if (!utf || utf[0] == 0) return;
    strncpy(dst, utf, cap - 1);
    dst[cap - 1] = 0;
    *has = 1;
}

static void MCSysctlCacheFill(void) {
    MCConfig *c = [MCConfig sharedConfig];
    MCSysctlCache next;
    memset(&next, 0, sizeof(next));
    MCCachePut(next.machine, sizeof(next.machine), c.deviceModel, &next.hasMachine);
    NSString *hw = c.hwModel.length > 0 ? c.hwModel : c.deviceModel;
    MCCachePut(next.model, sizeof(next.model), hw, &next.hasModel);
    MCCachePut(next.osrelease, sizeof(next.osrelease), c.darwinRelease, &next.hasOsrelease);
    MCCachePut(next.osversion, sizeof(next.osversion), c.buildVersion, &next.hasOsversion);
    MCCachePut(next.hostname, sizeof(next.hostname), c.hostName, &next.hasHostname);
    next.memsize = c.memsizeBytes;
    next.cpuCount = c.cpuCount;
    if (c.boottimeSec > 0) {
        next.bootSec = (time_t)c.boottimeSec;
        next.bootUsec = c.boottimeUsec;
        next.hasBoot = 1;
    }
    gSysctlCache = next;
    __atomic_store_n(&gSysctlCache.ready, 1, __ATOMIC_RELEASE);
}

static int MCCacheReady(void) {
    return __atomic_load_n(&gSysctlCache.ready, __ATOMIC_ACQUIRE);
}

static int MCFillCBuf(void *oldp, size_t *oldlenp, const char *utf) {
    if (!utf) return -1;
    size_t n = strlen(utf) + 1;
    if (oldp == NULL) {
        if (oldlenp) *oldlenp = n;
        return 0;
    }
    if (!oldlenp || *oldlenp < n) {
        if (oldlenp) *oldlenp = n;
        errno = ENOMEM;
        return -1;
    }
    memcpy(oldp, utf, n);
    *oldlenp = n;
    return 0;
}

// Trả 1 khi MIB này đã có câu trả lời ở đường libc. newp khác NULL là lời ghi, để kernel xử lý.
static int MCSyscallSysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, long *out) {
    if (!MCCacheReady() || !name || namelen < 2 || newp != NULL || !out) return 0;
    const MCSysctlCache *c = &gSysctlCache;
    if (name[0] == CTL_HW) {
        if (name[1] == HW_MACHINE && c->hasMachine) {
            *out = MCFillCBuf(oldp, oldlenp, c->machine);
            return 1;
        }
        if (name[1] == HW_MODEL) {
            *out = c->hasModel ? MCFillCBuf(oldp, oldlenp, c->model) : -1;
            return 1;
        }
        if (name[1] == HW_PHYSMEM && c->memsize > 0) {
            unsigned int v = (unsigned int)MIN(c->memsize, (uint64_t)UINT32_MAX);
            *out = MCFillBytes(oldp, oldlenp, &v, sizeof(v));
            return 1;
        }
#ifdef HW_MEMSIZE
        if (name[1] == HW_MEMSIZE && c->memsize > 0) {
            uint64_t v = c->memsize;
            *out = MCFillBytes(oldp, oldlenp, &v, sizeof(v));
            return 1;
        }
#endif
        if (name[1] == HW_NCPU && c->cpuCount > 0) {
            int v = c->cpuCount;
            *out = MCFillBytes(oldp, oldlenp, &v, sizeof(v));
            return 1;
        }
#ifdef HW_AVAILCPU
        if (name[1] == HW_AVAILCPU && c->cpuCount > 0) {
            int v = c->cpuCount;
            *out = MCFillBytes(oldp, oldlenp, &v, sizeof(v));
            return 1;
        }
#endif
#ifdef HW_PAGESIZE
        if (name[1] == HW_PAGESIZE) {
            int v = 16384;
            *out = MCFillBytes(oldp, oldlenp, &v, sizeof(v));
            return 1;
        }
#endif
#ifdef HW_BYTEORDER
        if (name[1] == HW_BYTEORDER) {
            int32_t v = 1234;
            *out = MCFillBytes(oldp, oldlenp, &v, sizeof(v));
            return 1;
        }
#endif
        return 0;
    }
    if (name[0] == CTL_KERN) {
        if (name[1] == KERN_OSTYPE) {
            *out = MCFillCBuf(oldp, oldlenp, "Darwin");
            return 1;
        }
        if (name[1] == KERN_OSRELEASE && c->hasOsrelease) {
            *out = MCFillCBuf(oldp, oldlenp, c->osrelease);
            return 1;
        }
        if (name[1] == KERN_OSVERSION && c->hasOsversion) {
            *out = MCFillCBuf(oldp, oldlenp, c->osversion);
            return 1;
        }
        if (name[1] == KERN_HOSTNAME && c->hasHostname) {
            *out = MCFillCBuf(oldp, oldlenp, c->hostname);
            return 1;
        }
        if (name[1] == KERN_BOOTTIME && c->hasBoot) {
            struct timeval tv;
            memset(&tv, 0, sizeof(tv));
            tv.tv_sec = c->bootSec;
            tv.tv_usec = (suseconds_t)c->bootUsec;
            *out = MCFillBytes(oldp, oldlenp, &tv, sizeof(tv));
            return 1;
        }
    }
    return 0;
}

static int MCHookedSyscall(int number, ...);

static MCSyscallFn MCEnsureOrigSyscall(void) {
    if (gOrigSyscall && gOrigSyscall != (MCSyscallFn)MCHookedSyscall
        && MCPointerInSystemImage((void *)gOrigSyscall)) {
        return gOrigSyscall;
    }
    if (gSyscallDepth) return NULL;
    gSyscallDepth++;
    void *real = MCInterposeReplacee((void *)MCHookedSyscall);
    gSyscallDepth--;
    if (real && real != (void *)MCHookedSyscall && MCPointerInSystemImage(real)) {
        gOrigSyscall = (MCSyscallFn)real;
    }
    return gOrigSyscall;
}

// Đối số sau number nằm trên stack (arm64). Phải khai báo variadic thì va_arg mới đọc đúng.
// libc sysctl gọi tiếp hàm này. Passthrough phải nhảy tới hàm gốc, không gọi syscall().
static int MCHookedSyscall(int number, ...) {
    va_list ap;
    va_start(ap, number);
    long a1 = va_arg(ap, long);
    long a2 = va_arg(ap, long);
    long a3 = va_arg(ap, long);
    long a4 = va_arg(ap, long);
    long a5 = va_arg(ap, long);
    long a6 = va_arg(ap, long);
    va_end(ap);
    MCSyscallFn orig = MCEnsureOrigSyscall();
    if (gSyscallDepth || !orig) {
        if (!orig) {
            errno = ENOSYS;
            return -1;
        }
        gSyscallDepth++;
        int r = orig(number, a1, a2, a3, a4, a5, a6);
        gSyscallDepth--;
        return r;
    }
    if (number == SYS_sysctl) {
        long rc = 0;
        if (MCSyscallSysctl((int *)(uintptr_t)a1, (u_int)a2, (void *)(uintptr_t)a3,
                            (size_t *)(uintptr_t)a4, (void *)(uintptr_t)a5, &rc)) {
            return (int)rc;
        }
    }
    gSyscallDepth++;
    int r = orig(number, a1, a2, a3, a4, a5, a6);
    gSyscallDepth--;
    return r;
}

// Interpose tĩnh: dyld áp cho TOÀN BỘ symbol đã bind trong binary chính lúc
// load image — con đường duy nhất phủ sysctl/uname/syscall trong app App Store.
// An toàn cùng guard RTLD_NEXT (MCRebind) — macro này KHÔNG gây đệ quy.
#define DYLD_INTERPOSE(_replacement,_replacee) \
__attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

static void *(*gRealDlsym)(void *, const char *);
static void *(*gRealDlopen)(const char *, int);
static void *MCHookedDlopen(const char *path, int mode);
static void *MCHookedDlsym(void *handle, const char *symbol);

// Interpose có hiệu lực trước constructor. App gọi dlopen/dlsym trong +load
// thì gReal còn NULL. Phải lấy hàm gốc ngay, không trả NULL cho app gọi tiếp.
static void *MCEnsureRealDlopen(void) {
    if (gRealDlopen) return gRealDlopen;
    static __thread int depth;
    if (depth) return NULL;
    depth++;
    void *real = MCInterposeReplacee((void *)MCHookedDlopen);
    if (!MCPointerInSystemImage(real)) real = MCLookupRealSymbol("dlopen");
    if (MCPointerInSystemImage(real)) gRealDlopen = real;
    depth--;
    return gRealDlopen;
}

static void *MCEnsureRealDlsym(void) {
    if (gRealDlsym) return gRealDlsym;
    static __thread int depth;
    if (depth) return NULL;
    depth++;
    void *real = MCInterposeReplacee((void *)MCHookedDlsym);
    if (!MCPointerInSystemImage(real)) real = MCLookupRealSymbol("dlsym");
    if (MCPointerInSystemImage(real)) gRealDlsym = real;
    depth--;
    return gRealDlsym;
}

// Trên máy này framework chỉ nằm trong dyld cache, dlopen đường dẫn trả NULL
// nên app đo không kịp gọi dlsym. Handle -2 là RTLD_DEFAULT, không NULL.
static void *MCHookedDlopen(const char *path, int mode) {
    void *(*real)(const char *, int) = MCEnsureRealDlopen();
    void *h = real ? real(path, mode) : NULL;
    if (!h && path && strstr(path, "MobileGestalt")) return (void *)(intptr_t)-2;
    return h;
}

static void *MCHookedDlsym(void *handle, const char *symbol) {
    if (symbol) {
        if (strcmp(symbol, "MGCopyAnswer") == 0) return (void *)MCHookedGestalt;
        if (strcmp(symbol, "nw_path_monitor_set_update_handler") == 0) return (void *)MCHookedNWSetUpdate;
        if (strcmp(symbol, "nw_path_uses_interface_type") == 0) return (void *)MCHookedNWUses;
    }
    void *(*real)(void *, const char *) = MCEnsureRealDlsym();
    if (!real) return NULL;
    return real(handle, symbol);
}

extern CFTypeRef MGCopyAnswer(CFStringRef key);
extern void *dlsym(void *, const char *);
DYLD_INTERPOSE(MCHookedGestalt, MGCopyAnswer)
DYLD_INTERPOSE(MCHookedSysctl, sysctlbyname)
DYLD_INTERPOSE(MCHookedSysctlRaw, sysctl)
DYLD_INTERPOSE(MCHookedUname, uname)
DYLD_INTERPOSE(MCHookedDlsym, dlsym)
DYLD_INTERPOSE(MCHookedDlopen, dlopen)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
DYLD_INTERPOSE(MCHookedSyscall, syscall)
#pragma clang diagnostic pop

void MCHookGestaltInstall(void) {
    // Không vá inline MGCopyAnswer ở đây: bản vá làm app đổ ngay lúc mở.
    // Lấy syscall gốc trước mọi dlsym: malloc trong lookup có thể gọi syscall.
    if (!gOrigSyscall || !MCPointerInSystemImage((void *)gOrigSyscall)) {
        void *real = MCInterposeReplacee((void *)MCHookedSyscall);
        if (real && real != (void *)MCHookedSyscall && MCPointerInSystemImage(real)) {
            gOrigSyscall = (MCSyscallFn)real;
        }
    }
    if (!gOrigSysctl || gOrigSysctl == (MCSysctlFn)MCHookedSysctl) {
        gOrigSysctl = (MCSysctlFn)MCLookupRealSymbol("sysctlbyname");
        if (gOrigSysctl == (MCSysctlFn)MCHookedSysctl) gOrigSysctl = NULL;
    }
    if (!gOrigSysctlRaw || gOrigSysctlRaw == (MCSysctlRawFn)MCHookedSysctlRaw) {
        gOrigSysctlRaw = (MCSysctlRawFn)MCLookupRealSymbol("sysctl");
        if (gOrigSysctlRaw == (MCSysctlRawFn)MCHookedSysctlRaw) gOrigSysctlRaw = NULL;
    }
    MCRebindSymbol("MGCopyAnswer", (void *)MCHookedGestalt, (void **)&gOrigGestalt);
    MCRebindSymbol("sysctlbyname", (void *)MCHookedSysctl, (void **)&gOrigSysctl);
    MCRebindSymbol("sysctl", (void *)MCHookedSysctlRaw, (void **)&gOrigSysctlRaw);
    MCRebindSymbol("uname", (void *)MCHookedUname, (void **)&gOrigUname);
    if (!MCPointerInSystemImage((void *)gOrigSysctl)) {
        void *real = MCInterposeReplacee((void *)MCHookedSysctl);
        gOrigSysctl = (real && real != (void *)MCHookedSysctl) ? (MCSysctlFn)real : NULL;
    }
    if (!MCPointerInSystemImage((void *)gOrigSysctlRaw)) {
        void *real = MCInterposeReplacee((void *)MCHookedSysctlRaw);
        gOrigSysctlRaw = (real && real != (void *)MCHookedSysctlRaw) ? (MCSysctlRawFn)real : NULL;
    }
    // Interpose tĩnh không bắt dlsym của AppFake. Gắn động, gọi hàm gốc đã lưu.
    if (!gRealDlsym) {
        void *real = MCInterposeReplacee((void *)MCHookedDlsym);
        if (!MCPointerInSystemImage(real)) real = MCLookupRealSymbol("dlsym");
        if (MCPointerInSystemImage(real)) gRealDlsym = real;
    }
    if (gRealDlsym) {
        void *ignored = NULL;
        MCRebindSymbol("dlsym", (void *)MCHookedDlsym, &ignored);
        // Slot lazy còn trỏ stub, không phải dlsym gốc. Ghi thẳng theo opcode.
        MCRedirectLazySymbol("dlsym", (void *)MCHookedDlsym);
    }
    if (!gRealDlopen) {
        void *real = MCInterposeReplacee((void *)MCHookedDlopen);
        if (!MCPointerInSystemImage(real)) real = MCLookupRealSymbol("dlopen");
        if (MCPointerInSystemImage(real)) gRealDlopen = real;
    }
    if (gRealDlopen) MCRedirectLazySymbol("dlopen", (void *)MCHookedDlopen);
    void *reboundSyscall = NULL;
    MCRebindSymbol("syscall", (void *)MCHookedSyscall, &reboundSyscall);
    if (reboundSyscall && reboundSyscall != (void *)MCHookedSyscall
        && MCPointerInSystemImage(reboundSyscall)) {
        gOrigSyscall = (MCSyscallFn)reboundSyscall;
    }
    if (!gOrigSyscall || gOrigSyscall == (MCSyscallFn)MCHookedSyscall
        || !MCPointerInSystemImage((void *)gOrigSyscall)) {
        void *real = MCInterposeReplacee((void *)MCHookedSyscall);
        if (real && real != (void *)MCHookedSyscall && MCPointerInSystemImage(real)) {
            gOrigSyscall = (MCSyscallFn)real;
        }
    }
    MCRedirectLazySymbol("syscall", (void *)MCHookedSyscall);
    MCSysctlCacheFill();
}
