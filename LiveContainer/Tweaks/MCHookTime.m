#import "MCConfig.h"
#import "MCRebind.h"

#import <errno.h>
#import <mach/mach_time.h>
#import <string.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <time.h>

typedef uint64_t (*MCMachTimeFn)(void);
typedef int (*MCStatFn)(const char *, struct stat *);

static MCMachTimeFn gOrigMachAbsolute;
static MCMachTimeFn gOrigMachContinuous;
static MCStatFn gOrigStat;
static MCStatFn gOrigLstat;

static uint64_t gRealStartAbsolute = 0;
static uint64_t gRealStartContinuous = 0;
static uint64_t gFakeBaseTicks = 0;
static mach_timebase_info_data_t gTimebase = {0, 0};

static void MCInitTimebaseIfNeeded(void) {
    if (gTimebase.denom == 0) {
        mach_timebase_info(&gTimebase);
        if (gTimebase.denom == 0) {
            gTimebase.numer = 1;
            gTimebase.denom = 1;
        }
    }
}

static uint64_t MCCalculateFakeBaseTicks(void) {
    MCInitTimebaseIfNeeded();
    MCConfig *c = [MCConfig sharedConfig];
    uint64_t bootSec = c.boottimeSec;
    if (bootSec == 0) {
        return 0;
    }
    struct timeval now;
    gettimeofday(&now, NULL);
    if ((uint64_t)now.tv_sec <= bootSec) {
        return 0;
    }
    uint64_t uptimeSec = (uint64_t)now.tv_sec - bootSec;
    uint64_t uptimeNs = uptimeSec * 1000000000ULL + ((uint64_t)now.tv_usec * 1000ULL);
    uint64_t ticks = uptimeNs * (uint64_t)gTimebase.denom / (uint64_t)gTimebase.numer;
    return ticks;
}

static uint64_t MCHookedMachAbsoluteTime(void) {
    MCMachTimeFn orig = gOrigMachAbsolute ? gOrigMachAbsolute : mach_absolute_time;
    uint64_t realNow = orig();
    if (gFakeBaseTicks == 0) {
        gFakeBaseTicks = MCCalculateFakeBaseTicks();
        gRealStartAbsolute = realNow;
    }
    if (gFakeBaseTicks > 0) {
        uint64_t elapsed = (realNow >= gRealStartAbsolute) ? (realNow - gRealStartAbsolute) : 0;
        return gFakeBaseTicks + elapsed;
    }
    return realNow;
}

static uint64_t MCHookedMachContinuousTime(void) {
    MCMachTimeFn orig = gOrigMachContinuous ? gOrigMachContinuous : mach_continuous_time;
    uint64_t realNow = orig();
    if (gFakeBaseTicks == 0) {
        gFakeBaseTicks = MCCalculateFakeBaseTicks();
        gRealStartContinuous = realNow;
    }
    if (gFakeBaseTicks > 0) {
        uint64_t elapsed = (realNow >= gRealStartContinuous) ? (realNow - gRealStartContinuous) : 0;
        return gFakeBaseTicks + elapsed;
    }
    return realNow;
}

static BOOL MCIsSystemVersionFile(const char *path) {
    if (!path) return NO;
    return (strstr(path, "/System/Library/CoreServices/SystemVersion.plist") != NULL);
}

static int MCHideJBPath(const char *path) {
    if (!path) return 0;
    if (strncmp(path, "/var/jb", 7) == 0 && (path[7] == '\0' || path[7] == '/')) return 1;
    return 0;
}

static int MCHookedTimeStat(const char *path, struct stat *buf) {
    if (MCHideJBPath(path)) {
        errno = ENOENT;
        return -1;
    }
    static __thread int depth;
    if (depth) return -1;
    depth++;
    int ret = -1;
    if (gOrigStat && gOrigStat != MCHookedTimeStat) {
        ret = gOrigStat(path, buf);
    } else {
        ret = stat(path, buf);
    }
    depth--;
    if (ret == 0 && buf && MCIsSystemVersionFile(path)) {
        MCConfig *c = [MCConfig sharedConfig];
        if (c.boottimeSec > 86400 * 30) {
            // Mtime cập nhật iOS hợp lý: 30 ngày trước mốc boottime giả lập
            time_t fakeMtime = (time_t)(c.boottimeSec - 86400 * 30);
            buf->st_mtime = fakeMtime;
            buf->st_atime = fakeMtime;
            buf->st_ctime = fakeMtime;
        }
    }
    return ret;
}

static int MCHookedTimeLstat(const char *path, struct stat *buf) {
    if (MCHideJBPath(path)) {
        errno = ENOENT;
        return -1;
    }
    static __thread int depth;
    if (depth) return -1;
    depth++;
    int ret = -1;
    if (gOrigLstat && gOrigLstat != MCHookedTimeLstat) {
        ret = gOrigLstat(path, buf);
    } else {
        ret = lstat(path, buf);
    }
    depth--;
    if (ret == 0 && buf && MCIsSystemVersionFile(path)) {
        MCConfig *c = [MCConfig sharedConfig];
        if (c.boottimeSec > 86400 * 30) {
            time_t fakeMtime = (time_t)(c.boottimeSec - 86400 * 30);
            buf->st_mtime = fakeMtime;
            buf->st_atime = fakeMtime;
            buf->st_ctime = fakeMtime;
        }
    }
    return ret;
}

/// Tăng và lưu số lần mở app (launchCount) tự nhiên per-profile (Phase 5.3)
void MCIncrementLaunchCount(void) {
    NSString *home = NSHomeDirectory();
    if (home.length == 0) return;
    NSString *path = [home stringByAppendingPathComponent:@"Library/Preferences/com.mun.changer.launch.plist"];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    MCConfig *c = [MCConfig sharedConfig];
    NSString *tag = c.udid.length >= 8 ? [c.udid substringToIndex:8] : (c.serialNumber ?: @"default");
    NSInteger count = [dict[tag] integerValue];
    count += 1;
    dict[tag] = @(count);
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [dict writeToFile:path atomically:YES];
}

#define DYLD_INTERPOSE(_replacement,_replacee) \
__attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

DYLD_INTERPOSE(MCHookedMachAbsoluteTime, mach_absolute_time)
DYLD_INTERPOSE(MCHookedMachContinuousTime, mach_continuous_time)
DYLD_INTERPOSE(MCHookedTimeStat, stat)
DYLD_INTERPOSE(MCHookedTimeLstat, lstat)

void MCHookTimeInstall(void) {
    static BOOL gHooked;
    if (gHooked) return;
    gHooked = YES;

    MCInitTimebaseIfNeeded();
    gFakeBaseTicks = MCCalculateFakeBaseTicks();
    gRealStartAbsolute = mach_absolute_time();
    gRealStartContinuous = mach_continuous_time();

    MCRebindSymbol("mach_absolute_time", (void *)MCHookedMachAbsoluteTime, (void **)&gOrigMachAbsolute);
    MCRebindSymbol("mach_continuous_time", (void *)MCHookedMachContinuousTime, (void **)&gOrigMachContinuous);
    MCRebindSymbol("stat", (void *)MCHookedTimeStat, (void **)&gOrigStat);
    MCRebindSymbol("lstat", (void *)MCHookedTimeLstat, (void **)&gOrigLstat);

    MCIncrementLaunchCount();
}
