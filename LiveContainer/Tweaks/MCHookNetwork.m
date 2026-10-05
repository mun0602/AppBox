#import "MCConfig.h"
#import "MCRebind.h"

#import <dlfcn.h>
#import <stdio.h>
#import <ifaddrs.h>
#import <stdbool.h>
#import <stdint.h>
#import <string.h>
#import <sys/mount.h>
#import <sys/statvfs.h>

typedef int (*MCGetifaddrsFn)(struct ifaddrs **);
typedef int (*MCStatfsFn)(const char *, struct statfs *);
typedef char *(*MCGetenvFn)(const char *);
typedef CFArrayRef (*MCCNIfacesFn)(void);
typedef CFDictionaryRef (*MCCNInfoFn)(CFStringRef);

typedef int (*MCStatvfsFn)(const char *, struct statvfs *);

static MCGetifaddrsFn gOrigGetifaddrs;
static MCStatfsFn gOrigStatfs;
static MCStatfsFn gOrigStatfs64;
static MCStatvfsFn gOrigStatvfs;
static MCGetenvFn gOrigGetenv;
static MCCNIfacesFn gOrigCNIfaces;
static MCCNInfoFn gOrigCNInfo;

static void *MCBindOrig(const char *name, void *repl) {
    // Caller phải tăng depth trước. dlsym cấp phát; malloc có thể gọi lại statfs.
    void *sym = dlsym(RTLD_NEXT, name);
    if (!sym || sym == repl) sym = dlsym(RTLD_DEFAULT, name);
    if (sym == repl) sym = NULL;
    return sym;
}

// Darwin getifaddrs = một malloc; freeifaddrs chỉ free(head).
// ifa_name/addr trỏ vào trong block — không free() node lẻ.
static BOOL MCIfaceDrop(const char *name) {
    if (!name || name[0] == '\0') return NO;
    if (strcmp(name, "lo0") == 0 || strcmp(name, "en0") == 0) return NO;
    static const char *prefs[] = { "utun", "ipsec", "ppp", "tap", "tun" };
    for (size_t i = 0; i < sizeof(prefs) / sizeof(prefs[0]); i++) {
        if (strncmp(name, prefs[i], strlen(prefs[i])) == 0) return YES;
    }
    return NO;
}

static void MCStripVPN(struct ifaddrs **ifap) {
    struct ifaddrs *head = *ifap;
    struct ifaddrs *keep = NULL;
    struct ifaddrs *prev = NULL;
    for (struct ifaddrs *cur = head; cur != NULL; ) {
        struct ifaddrs *next = cur->ifa_next;
        if (!MCIfaceDrop(cur->ifa_name)) {
            if (!keep) keep = cur;
            if (prev) prev->ifa_next = cur;
            prev = cur;
        }
        cur = next;
    }
    if (!keep) {
        freeifaddrs(head);
        *ifap = NULL;
        return;
    }
    prev->ifa_next = NULL;
    if (keep != head) {
        struct ifaddrs saved = *keep;
        *head = saved;
        head->ifa_next = saved.ifa_next;
    }
    *ifap = head;
}

static int MCHookedGetifaddrs(struct ifaddrs **ifap) {
    MCGetifaddrsFn orig = gOrigGetifaddrs;
    if (!orig || orig == (MCGetifaddrsFn)MCHookedGetifaddrs) {
        if (ifap) *ifap = NULL;
        return -1;
    }
    int rc = orig(ifap);
    if (rc != 0 || !ifap || !*ifap) return rc;
    if (![[MCConfig sharedConfig] fakeNetworkEnabled]) return rc;
    MCStripVPN(ifap);
    return rc;
}

static void MCPatchStatfs(struct statfs *buf) {
    if (!buf || buf->f_bsize == 0) return;
    uint64_t total = [[MCConfig sharedConfig] diskTotalBytes];
    if (total == 0) return;
    uint64_t freeb = [[MCConfig sharedConfig] diskFreeBytes];
    if (freeb > total) freeb = total;
    uint64_t bsize = buf->f_bsize;
    buf->f_blocks = total / bsize;
    buf->f_bfree = freeb / bsize;
    buf->f_bavail = freeb / bsize;
}

static int MCHookedStatfs(const char *path, struct statfs *buf) {
    static __thread int depth;
    if (depth) return -1;
    depth++;
    int rc = -1;
    MCStatfsFn orig = gOrigStatfs;
    if (orig && orig != (MCStatfsFn)MCHookedStatfs) {
        rc = orig(path, buf);
        if (rc == 0) MCPatchStatfs(buf);
    }
    depth--;
    return rc;
}

static void MCPatchStatvfs(struct statvfs *buf) {
    if (!buf) return;
    if (buf->f_frsize == 0) buf->f_frsize = buf->f_bsize ? buf->f_bsize : 4096;
    uint64_t total = [[MCConfig sharedConfig] diskTotalBytes];
    if (total == 0) return;
    uint64_t freeb = [[MCConfig sharedConfig] diskFreeBytes];
    if (freeb > total) freeb = total;
    uint64_t fr = buf->f_frsize;
    buf->f_blocks = total / fr;
    buf->f_bfree = freeb / fr;
    buf->f_bavail = freeb / fr;
    if (buf->f_bsize == 0) buf->f_bsize = (unsigned long)fr;
}

static int MCHookedStatvfs(const char *path, struct statvfs *buf) {
    static __thread int depth;
    if (depth) return -1;
    depth++;
    int rc = -1;
    MCStatvfsFn orig = gOrigStatvfs;
    if (orig && orig != (MCStatvfsFn)MCHookedStatvfs) {
        rc = orig(path, buf);
        if (rc == 0) MCPatchStatvfs(buf);
    }
    depth--;
    return rc;
}

// Cùng layout statfs trên Darwin 64-bit inode. Symbol có thì mới resolve.
extern int statfs64(const char *path, struct statfs *buf) __attribute__((weak_import));

static int MCHookedStatfs64(const char *path, struct statfs *buf) {
    static __thread int depth;
    if (depth) return -1;
    depth++;
    int rc = -1;
    MCStatfsFn orig = gOrigStatfs64;
    if (orig && orig != (MCStatfsFn)MCHookedStatfs64) {
        rc = orig(path, buf);
        if (rc == 0) MCPatchStatfs(buf);
    }
    depth--;
    return rc;
}

static BOOL MCGetenvHidden(const char *name) {
    if (strcmp(name, "DYLD_INSERT_LIBRARIES") == 0) return YES;
    if (strstr(name, "_proxy")) return YES;
    if (strstr(name, "HTTP_PROXY")) return YES;
    if (strstr(name, "http_proxy")) return YES;
    if (strstr(name, "HTTPS_PROXY")) return YES;
    if (strstr(name, "ALL_PROXY")) return YES;
    return NO;
}

static char *MCHookedGetenv(const char *name) {
    // Chặn đệ quy khi dlsym/config gọi lại getenv lúc chưa có orig.
    static __thread int depth;
    if (depth > 0) {
        MCGetenvFn orig = gOrigGetenv;
        if (orig && orig != (MCGetenvFn)MCHookedGetenv) return orig(name);
        return NULL;
    }
    depth++;
    if (!gOrigGetenv || gOrigGetenv == (MCGetenvFn)MCHookedGetenv) {
        gOrigGetenv = (MCGetenvFn)MCBindOrig("getenv", (void *)MCHookedGetenv);
    }
    char *out = NULL;
    BOOL hide = name && MCGetenvHidden(name) && [[MCConfig sharedConfig] fakeNetworkEnabled];
    if (!hide && gOrigGetenv && gOrigGetenv != (MCGetenvFn)MCHookedGetenv) {
        out = gOrigGetenv(name);
    }
    depth--;
    return out;
}

extern CFArrayRef CNCopySupportedInterfaces(void) __attribute__((weak_import));
extern CFDictionaryRef CNCopyCurrentNetworkInfo(CFStringRef interfaceName) __attribute__((weak_import));

static CFArrayRef MCHookedCNIfaces(void) {
    MCConfig *c = [MCConfig sharedConfig];
    if (c.fakeNetworkEnabled && (c.wifiSSID.length > 0 || c.wifiAddress.length > 0)) {
        CFStringRef en0 = CFSTR("en0");
        return CFArrayCreate(kCFAllocatorDefault, (const void **)&en0, 1, &kCFTypeArrayCallBacks);
    }
    if (!gOrigCNIfaces || gOrigCNIfaces == (MCCNIfacesFn)MCHookedCNIfaces) {
        gOrigCNIfaces = (MCCNIfacesFn)MCBindOrig("CNCopySupportedInterfaces", (void *)MCHookedCNIfaces);
    }
    MCCNIfacesFn orig = gOrigCNIfaces;
    if (orig && orig != (MCCNIfacesFn)MCHookedCNIfaces) return orig();
    return NULL;
}

static CFDictionaryRef MCWifiDict(NSString *ssid, NSString *bssid) {
    NSData *raw = [ssid dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithCapacity:3];
    info[@"SSID"] = ssid;
    info[@"SSIDDATA"] = raw;
    if (bssid.length > 0) info[@"BSSID"] = bssid;
    return (CFDictionaryRef)CFBridgingRetain(info);
}

static BOOL MCIsEn0(CFStringRef name) {
    if (!name) return NO;
    return CFStringCompare(name, CFSTR("en0"), 0) == kCFCompareEqualTo;
}

static CFDictionaryRef MCHookedCNInfo(CFStringRef interfaceName) {
    MCConfig *c = [MCConfig sharedConfig];
    if (c.fakeNetworkEnabled && MCIsEn0(interfaceName) && c.wifiSSID.length > 0) {
        return MCWifiDict(c.wifiSSID, c.wifiBSSID);
    }
    if (!gOrigCNInfo || gOrigCNInfo == (MCCNInfoFn)MCHookedCNInfo) {
        gOrigCNInfo = (MCCNInfoFn)MCBindOrig("CNCopyCurrentNetworkInfo", (void *)MCHookedCNInfo);
    }
    MCCNInfoFn orig = gOrigCNInfo;
    if (orig && orig != (MCCNInfoFn)MCHookedCNInfo) return orig(interfaceName);
    return NULL;
}

void MCHookedNWSetUpdate(void *monitor, void (^handler)(void *path)) {
    (void)monitor;
    if (handler) handler((void *)(uintptr_t)1);
}

bool MCHookedNWUses(void *path, int type) {
    (void)path;
    return type == 1;
}

#define DYLD_INTERPOSE(_replacement,_replacee) \
__attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

DYLD_INTERPOSE(MCHookedGetifaddrs, getifaddrs)
DYLD_INTERPOSE(MCHookedStatfs, statfs)
DYLD_INTERPOSE(MCHookedStatfs64, statfs64)
DYLD_INTERPOSE(MCHookedStatvfs, statvfs)
// Không dùng static DYLD_INTERPOSE cho getenv vì libsystem_malloc gọi getenv sớm lúc init malloc zones.
// MCRebindSymbol trong MCHookNetworkInstall sẽ áp an toàn sau khi runtime sẵn sàng.
DYLD_INTERPOSE(MCHookedCNIfaces, CNCopySupportedInterfaces)
DYLD_INTERPOSE(MCHookedCNInfo, CNCopyCurrentNetworkInfo)

static void MCKeepReal(void **slot, void *repl) {
    if (!slot) return;
    if (*slot && *slot != repl && MCPointerInSystemImage(*slot)) return;
    void *real = MCInterposeReplacee(repl);
    if (real && real != repl) *slot = real;
    else if (!MCPointerInSystemImage(*slot)) *slot = NULL;
}

void MCHookNetworkInstall(void) {
    static BOOL hooked;
    if (hooked) return;
    MCRebindSymbol("getifaddrs", (void *)MCHookedGetifaddrs, (void **)&gOrigGetifaddrs);
    MCRebindSymbol("statfs", (void *)MCHookedStatfs, (void **)&gOrigStatfs);
    MCRebindSymbol("statfs64", (void *)MCHookedStatfs64, (void **)&gOrigStatfs64);
    MCRebindSymbol("statvfs", (void *)MCHookedStatvfs, (void **)&gOrigStatvfs);
    MCKeepReal((void **)&gOrigGetifaddrs, (void *)MCHookedGetifaddrs);
    MCKeepReal((void **)&gOrigStatfs, (void *)MCHookedStatfs);
    MCKeepReal((void **)&gOrigStatfs64, (void *)MCHookedStatfs64);
    MCKeepReal((void **)&gOrigStatvfs, (void *)MCHookedStatvfs);
    MCRebindSymbol("getenv", (void *)MCHookedGetenv, (void **)&gOrigGetenv);
    MCRebindSymbol("CNCopySupportedInterfaces", (void *)MCHookedCNIfaces, (void **)&gOrigCNIfaces);
    MCRebindSymbol("CNCopyCurrentNetworkInfo", (void *)MCHookedCNInfo, (void **)&gOrigCNInfo);
    if (!gOrigGetifaddrs) {
        void *p = MCBindOrig("getifaddrs", (void *)MCHookedGetifaddrs);
        if (MCPointerInSystemImage(p)) gOrigGetifaddrs = (MCGetifaddrsFn)p;
    }
    if (!gOrigStatfs) {
        void *p = MCBindOrig("statfs", (void *)MCHookedStatfs);
        if (MCPointerInSystemImage(p)) gOrigStatfs = (MCStatfsFn)p;
    }
    if (!gOrigStatfs64) {
        void *p = MCBindOrig("statfs64", (void *)MCHookedStatfs64);
        if (MCPointerInSystemImage(p)) gOrigStatfs64 = (MCStatfsFn)p;
    }
    if (!gOrigGetenv) gOrigGetenv = (MCGetenvFn)MCBindOrig("getenv", (void *)MCHookedGetenv);
    if (!gOrigCNIfaces) gOrigCNIfaces = (MCCNIfacesFn)MCBindOrig("CNCopySupportedInterfaces", (void *)MCHookedCNIfaces);
    if (!gOrigCNInfo) gOrigCNInfo = (MCCNInfoFn)MCBindOrig("CNCopyCurrentNetworkInfo", (void *)MCHookedCNInfo);
    hooked = YES;
}
