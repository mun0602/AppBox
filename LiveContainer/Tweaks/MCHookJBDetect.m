#import "MCConfig.h"
#import "MCRebind.h"
#import "MCSwizzle.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <dirent.h>
#import <errno.h>
#import <fcntl.h>
#import <sys/syscall.h>
#import <stdarg.h>
#import <string.h>
#import <strings.h>
#import <sys/stat.h>
#import <unistd.h>

// Phase 3 Kuaishou: ẩn path JB + URL scheme khi hideJailbreakEnabled.
// Fail-open nếu option tắt. Không blacklist MunChanger — tránh che prefs của mình.
// fileExists* chồng MCHookFileManager: check blacklist trước, rồi gọi orig (chain).

static const char *const kMCJBPrefixes[] = {
    "/Applications/Cydia.app",
    "/Applications/Sileo.app",
    "/Applications/Zebra.app",
    "/Applications/Installer.app",
    "/bin/bash",
    "/bin/sh",
    "/usr/sbin/sshd",
    "/etc/apt",
    "/etc/ssh/sshd_config",
    "/private/var/lib/apt",
    "/private/var/lib/cydia",
    "/private/var/tmp/cydia.log",
    "/private/jailbreak.txt",
    "/Library/MobileSubstrate",
    "/usr/lib/substrate",
    "/usr/lib/libsubstrate",
    "/usr/lib/TweakInject",
    "/var/jb",
    "/jb/",
    "/.bootstrapped_electra",
    "/.cydia_no_stash",
    "/.installed_unc0ver",
    "/var/mobile/Library/SBSettings",
    "/etc/apt/sources.list.d",
};

// Không needle CydiaSubstrate/ElleKit — dylib mình dlopen framework đó trong bundle.
static const char *const kMCJBNeedles[] = {
    "libhooker",
    "substitute",
    "FridaGadget",
    "frida-agent",
    "/Library/MobileSubstrate/DynamicLibraries",
};

static const char *const kMCJBSchemes[] = {
    "cydia",
    "sileo",
    "zbra",
    "filza",
    "undecimus",
    "activator",
    "shc",
    "jailbreak",
};

static __thread int gMCJBDepth;

static BOOL MCPathBlacklisted(const char *path) {
    if (!path || path[0] == '\0') {
        return NO;
    }
    for (size_t i = 0; i < sizeof(kMCJBPrefixes) / sizeof(kMCJBPrefixes[0]); i++) {
        const char *prefix = kMCJBPrefixes[i];
        size_t n = strlen(prefix);
        if (strncmp(path, prefix, n) == 0) {
            return YES;
        }
    }
    for (size_t i = 0; i < sizeof(kMCJBNeedles) / sizeof(kMCJBNeedles[0]); i++) {
        if (strstr(path, kMCJBNeedles[i]) != NULL) {
            return YES;
        }
    }
    return NO;
}

// Depth chặn đệ quy: sharedConfig đọc plist bằng chính stat/open đang hook.
static BOOL MCHideJBOn(void) {
    if (gMCJBDepth > 0) {
        return NO;
    }
    gMCJBDepth++;
    BOOL hide = [[MCConfig sharedConfig] hideJailbreakEnabled];
    gMCJBDepth--;
    return hide;
}

static BOOL MCShouldHidePath(const char *path) {
    if (!MCPathBlacklisted(path)) {
        return NO;
    }
    return MCHideJBOn();
}

static BOOL MCShouldHideNSPath(NSString *path) {
    if (path.length == 0) {
        return NO;
    }
    return MCShouldHidePath(path.UTF8String);
}

typedef int (*MCAccessFn)(const char *, int);
typedef int (*MCStatFn)(const char *, struct stat *);
typedef int (*MCOpenFn)(const char *, int, ...);
typedef DIR *(*MCOpendirFn)(const char *);
typedef struct dirent *(*MCReaddirFn)(DIR *);

static MCAccessFn gOrigAccess;
static MCStatFn gOrigStat;
static MCStatFn gOrigLstat;
static MCOpenFn gOrigOpen;
static MCOpendirFn gOrigOpendir;
static MCReaddirFn gOrigReaddir;

static int MCHookedAccess(const char *path, int mode) {
    // Không dlsym ở đây. access() trong ảnh này là hàm gốc, không đi qua interpose.
    static __thread int depth;
    if (MCPathBlacklisted(path)) {
        errno = ENOENT;
        return -1;
    }
    if (depth) return -1;
    depth++;
    int rc = access(path, mode);
    depth--;
    return rc;
}

static void MCPatchSystemFileTime(const char *path, struct stat *buf) {
    if (!path || !buf) return;
    if (strstr(path, "/System/Library/CoreServices/SystemVersion.plist") != NULL) {
        MCConfig *c = [MCConfig sharedConfig];
        if (c.boottimeSec > 86400 * 30) {
            time_t fakeMtime = (time_t)(c.boottimeSec - 86400 * 30);
            buf->st_mtime = fakeMtime;
            buf->st_atime = fakeMtime;
            buf->st_ctime = fakeMtime;
        }
    }
}

static int MCHookedStat(const char *path, struct stat *buf) {
    if (MCShouldHidePath(path)) {
        errno = ENOENT;
        return -1;
    }
    MCStatFn fn = (gOrigStat && gOrigStat != MCHookedStat) ? gOrigStat : (MCStatFn)dlsym(RTLD_DEFAULT, "stat");
    int ret = fn ? fn(path, buf) : -1;
    if (ret == 0) {
        MCPatchSystemFileTime(path, buf);
    }
    return ret;
}

static int MCHookedLstat(const char *path, struct stat *buf) {
    if (MCShouldHidePath(path)) {
        errno = ENOENT;
        return -1;
    }
    MCStatFn fn = (gOrigLstat && gOrigLstat != MCHookedLstat) ? gOrigLstat : (MCStatFn)dlsym(RTLD_DEFAULT, "lstat");
    int ret = fn ? fn(path, buf) : -1;
    if (ret == 0) {
        MCPatchSystemFileTime(path, buf);
    }
    return ret;
}

static int MCHookedOpen(const char *path, int flags, ...) {
    if (MCShouldHidePath(path)) {
        errno = ENOENT;
        return -1;
    }
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
    MCOpenFn fn = (gOrigOpen && gOrigOpen != (MCOpenFn)MCHookedOpen) ? gOrigOpen : (MCOpenFn)dlsym(RTLD_DEFAULT, "open");
    return fn ? fn(path, flags, mode) : -1;
}

// Dấu hiệu jailbreak trong TÊN phần tử thư mục. Audit IDA: opendir 36 caller,
// readdir 34 caller — phần lớn dò bằng cách liệt kê thư mục rồi so tên, nên lọc
// ở tầng này rẻ hơn nhiều so với chặn từng đường dẫn.
static BOOL MCEntryNameLooksJB(const char *name) {
    if (!name || name[0] == '\0') {
        return NO;
    }
    static const char *const needles[] = {
        "Cydia", "Sileo", "Zebra", "unc0ver", "Electra", "palera1n",
        "FridaGadget", "frida", "Substrate", "Substitute", "ElleKit",
        "libhooker", "TweakInject", "Checkra1n", "Chimera",
    };
    for (size_t i = 0; i < sizeof(needles) / sizeof(needles[0]); i++) {
        if (strstr(name, needles[i]) != NULL) {
            return YES;
        }
    }
    return NO;
}

static DIR *MCHookedOpendir(const char *path) {
    if (MCShouldHidePath(path)) {
        errno = ENOENT;
        return NULL;
    }
    MCOpendirFn fn = (gOrigOpendir && gOrigOpendir != MCHookedOpendir) ? gOrigOpendir : (MCOpendirFn)dlsym(RTLD_DEFAULT, "opendir");
    return fn ? fn(path) : NULL;
}

static struct dirent *MCHookedReaddir(DIR *dirp) {
    MCReaddirFn fn = (gOrigReaddir && gOrigReaddir != MCHookedReaddir) ? gOrigReaddir : (MCReaddirFn)dlsym(RTLD_DEFAULT, "readdir");
    if (!fn) {
        return NULL;
    }
    if (!MCHideJBOn()) {
        return fn(dirp);
    }
    // Bỏ qua entry có dấu hiệu jailbreak, nhưng PHẢI đi tiếp thay vì trả NULL
    // (NULL nghĩa là hết danh sách, sẽ cắt ngắn vòng duyệt của app).
    for (int guard = 0; guard < 4096; guard++) {
        struct dirent *ent = fn(dirp);
        if (!ent) {
            return NULL;
        }
        if (!MCEntryNameLooksJB(ent->d_name)) {
            return ent;
        }
    }
    return NULL;
}

// Không interpose tĩnh access/stat: syscall và dlopen trong hook làm malloc đệ quy lúc mở app.
typedef BOOL (*MCExistsIMP)(id, SEL, NSString *);
typedef BOOL (*MCExistsDirIMP)(id, SEL, NSString *, BOOL *);
typedef BOOL (*MCCanOpenIMP)(id, SEL, NSURL *);

static MCExistsIMP gOrigExists;
static MCExistsDirIMP gOrigExistsDir;
static MCCanOpenIMP gOrigCanOpen;

static BOOL MCSchemeBlocked(NSString *scheme) {
    if (scheme.length == 0) {
        return NO;
    }
    const char *utf = scheme.UTF8String;
    if (!utf) {
        return NO;
    }
    for (size_t i = 0; i < sizeof(kMCJBSchemes) / sizeof(kMCJBSchemes[0]); i++) {
        if (strcasecmp(utf, kMCJBSchemes[i]) == 0) {
            return YES;
        }
    }
    return NO;
}

static BOOL MCHookedExists(id self, SEL _cmd, NSString *path) {
    if (MCShouldHideNSPath(path)) {
        return NO;
    }
    return gOrigExists ? gOrigExists(self, _cmd, path) : NO;
}

static BOOL MCHookedExistsDir(id self, SEL _cmd, NSString *path, BOOL *isDir) {
    if (MCShouldHideNSPath(path)) {
        if (isDir) {
            *isDir = NO;
        }
        return NO;
    }
    return gOrigExistsDir ? gOrigExistsDir(self, _cmd, path, isDir) : NO;
}

static BOOL MCHookedCanOpenURL(id self, SEL _cmd, NSURL *url) {
    if (MCSchemeBlocked(url.scheme) && MCHideJBOn()) {
        return NO;
    }
    return gOrigCanOpen ? gOrigCanOpen(self, _cmd, url) : NO;
}

static BOOL MCDyldNameLeaks(const char *name) {
    if (!name) return NO;
    return strstr(name, "MunChanger") || strstr(name, "ubstrate") || strstr(name, "frida")
        || strstr(name, "ellekit") || strstr(name, "ElleKit") || strstr(name, "Dopamine")
        || strstr(name, "TrollStore");
}

static const char *MCHookedDyldName(uint32_t index) {
    static __thread int depth;
    if (depth) return NULL;
    depth++;
    const char *name = _dyld_get_image_name(index);
    depth--;
    if (MCDyldNameLeaks(name)) return "/usr/lib/libobjc.A.dylib";
    return name;
}

static int MCHookedDladdr(const void *addr, Dl_info *info) {
    static __thread int depth;
    if (depth) return 0;
    depth++;
    int rc = dladdr(addr, info);
    depth--;
    if (rc && info && MCDyldNameLeaks(info->dli_fname)) {
        info->dli_fname = "/usr/lib/libobjc.A.dylib";
        info->dli_sname = NULL;
        info->dli_saddr = NULL;
    }
    return rc;
}

#define DYLD_INTERPOSE(_replacement,_replacee) \
__attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

extern int access(const char *, int);
extern const char *_dyld_get_image_name(uint32_t);
extern int dladdr(const void *, Dl_info *);
DYLD_INTERPOSE(MCHookedAccess, access)
DYLD_INTERPOSE(MCHookedDyldName, _dyld_get_image_name)
DYLD_INTERPOSE(MCHookedDladdr, dladdr)

static BOOL gHooked;

void MCHookJBDetectInstall(void) {
    if (gHooked) {
        return;
    }
    gHooked = YES;

    MCRebindSymbol("access", (void *)MCHookedAccess, (void **)&gOrigAccess);
    MCRebindSymbol("stat", (void *)MCHookedStat, (void **)&gOrigStat);
    MCRebindSymbol("lstat", (void *)MCHookedLstat, (void **)&gOrigLstat);
    MCRebindSymbol("open", (void *)MCHookedOpen, (void **)&gOrigOpen);
    MCRebindSymbol("opendir", (void *)MCHookedOpendir, (void **)&gOrigOpendir);
    MCRebindSymbol("readdir", (void *)MCHookedReaddir, (void **)&gOrigReaddir);

    Class fm = objc_getClass("NSFileManager");
    if (fm) {
        IMP prev = NULL;
        if (MCSwizzleInstance(fm, sel_registerName("fileExistsAtPath:"), (IMP)MCHookedExists, &prev)) {
            gOrigExists = (MCExistsIMP)prev;
        }
        prev = NULL;
        if (MCSwizzleInstance(fm, sel_registerName("fileExistsAtPath:isDirectory:"), (IMP)MCHookedExistsDir, &prev)) {
            gOrigExistsDir = (MCExistsDirIMP)prev;
        }
    }

    Class app = objc_getClass("UIApplication");
    if (app) {
        IMP prev = NULL;
        if (MCSwizzleInstance(app, sel_registerName("canOpenURL:"), (IMP)MCHookedCanOpenURL, &prev)) {
            gOrigCanOpen = (MCCanOpenIMP)prev;
        }
    }
}
