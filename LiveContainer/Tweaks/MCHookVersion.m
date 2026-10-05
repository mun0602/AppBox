#import "MCConfig.h"
#import "MCRebind.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/sysctl.h>

enum { kMCPlatformIOS = 2 };

static bool MCSysctlAtLeast(uint32_t major, uint32_t minor, uint32_t patch) {
    char buf[64] = {0};
    size_t size = sizeof(buf);
    if (sysctlbyname("kern.osproductversion", buf, &size, NULL, 0) != 0) {
        return false;
    }
    uint32_t a = 0, b = 0, c = 0;
    sscanf(buf, "%u.%u.%u", &a, &b, &c);
    if (a != major) {
        return a > major;
    }
    if (b != minor) {
        return b > minor;
    }
    return c >= patch;
}

static bool MCDecide(uint32_t major, uint32_t minor, uint32_t patch) {
    BOOL hasFake = NO;
    BOOL result = [[MCConfig sharedConfig] isFakeOSVersionAtLeastMajor:major
                                                                minor:minor
                                                                patch:patch
                                                       hasFakeVersion:&hasFake];
    if (hasFake) {
        return result;
    }
    return MCSysctlAtLeast(major, minor, patch);
}

static bool MCHookedOSVersion(uint32_t major, uint32_t minor, uint32_t patch) {
    return MCDecide(major, minor, patch);
}

static bool MCHookedPlatVersion(uint32_t platform, uint32_t major, uint32_t minor, uint32_t patch) {
    if (platform == kMCPlatformIOS) {
        return MCDecide(major, minor, patch);
    }
    return MCSysctlAtLeast(major, minor, patch);
}

static bool MCHookedAvail(uint32_t count, const uint32_t *vers) {
    if (count >= 1 && vers) {
        uint32_t platform = vers[0];
        uint32_t packed = count >= 2 ? vers[1] : 0;
        uint32_t major = (packed >> 16) & 0xFFFFu;
        uint32_t minor = (packed >> 8) & 0xFFu;
        uint32_t patch = packed & 0xFFu;
        if (platform == kMCPlatformIOS) {
            return MCDecide(major, minor, patch);
        }
    }
    return false;
}

void MCHookVersionInstall(void) {
    static BOOL gHooked;
    if (gHooked) {
        return;
    }
    MCRebindSymbol("_availability_version_check", (void *)MCHookedAvail, NULL);
    MCRebindSymbol("__isOSVersionAtLeast", (void *)MCHookedOSVersion, NULL);
    MCRebindSymbol("__isPlatformVersionAtLeast", (void *)MCHookedPlatVersion, NULL);
    gHooked = YES;
}
