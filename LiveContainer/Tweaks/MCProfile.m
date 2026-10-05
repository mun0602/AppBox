//
//  MCProfile.m
//  LiveContainer
//
//  Integration layer: bridges MunChanger hooks into LiveContainer.
//  Called once from LCBootstrap.m after DyldHooksInit.
//

#import "MCProfile.h"
#import "MCConfig.h"
#import <os/log.h>

// MunChanger hook declarations
extern void MCHookGestaltInstall(void);
extern void MCHookDeviceInstall(void);
extern void MCHookVersionInstall(void);
extern void MCHookCarrierInstall(void);
extern void MCHookScreenInstall(void);
extern void MCHookNetworkInstall(void);
extern void MCHookAdvertisingInstall(void);
extern void MCHookLocaleInstall(void);
extern void MCHookTimeInstall(void);
extern void MCHookLocationInstall(void);
extern void MCHookMotionInstall(void);
extern void MCHookSensorsInstall(void);
extern void MCHookFileManagerInstall(void);
extern void MCHookDefaultsInstall(void);
extern void MCHookJBDetectInstall(void);
extern void MCHookAntiDebugInstall(void);
extern void MCHookWolverineInstall(void);
extern void MCHookSignatureInstall(void);
extern void MCMissingAPIInstall(void);

static os_log_t mcLog;

__attribute__((constructor))
static void MCProfileLogInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mcLog = os_log_create("com.mun.changer", "lc-integration");
    });
}

BOOL MCProfileInit(void) {
    MCProfileLogInit();
    {
        NSString *dbgPath = [NSHomeDirectory() stringByAppendingPathComponent:@"mcdebug.log"];
        FILE *f = fopen(dbgPath.fileSystemRepresentation, "a");
        if (f) { fprintf(f, "MCProfileInit enter home=%s\n", NSHomeDirectory().UTF8String); fclose(f); }
    }

    // Safe mode: presence of <container>/mc.disabled (any content) skips all
    // MunChanger hooks, so a bad profile can't lock the user out of the UI.
    // NSHomeDirectory() in a guest process is the container home.
    if ([[NSFileManager defaultManager] fileExistsAtPath:
            [NSHomeDirectory() stringByAppendingPathComponent:@"mc.disabled"]]) {
        os_log_info(mcLog, "MunChanger hooks SKIPPED: kill-switch file mc.disabled present");
        return NO;
    }

    MCConfig *config = [MCConfig sharedConfig];
    if (![config reload]) {
        os_log_info(mcLog, "MunChanger hooks SKIPPED: cannot read com.mun.changer.plist "
               "(LC_HOME_PATH=%s)", getenv("LC_HOME_PATH") ?: "<unset>");
        return NO;
    }
    if (!config.isEnabled) {
        os_log_info(mcLog, "MunChanger hooks SKIPPED: config.enabled = NO");
        return NO;
    }

    os_log_info(mcLog, "MCProfile: installing hooks — name=%@ model=%@ ios=%@ build=%@",
            config.deviceName ?: @"-",
            config.deviceModel ?: @"-",
            config.systemVersion ?: @"-",
            config.buildVersion ?: @"-");

    // P0: Gestalt (sysctl/MobileGestalt) + Device + Version
    MCHookGestaltInstall();
    MCHookDeviceInstall();
    MCHookVersionInstall();

    // P1: Carrier + Screen + Network + Advertising
    MCHookCarrierInstall();
    MCHookScreenInstall();
    MCHookNetworkInstall();
    MCHookAdvertisingInstall();

    // P2: Locale + Time + Location + Motion/Sensors + FileManager + Defaults
    MCHookLocaleInstall();
    MCHookTimeInstall();
    MCHookLocationInstall();
    MCHookMotionInstall();
    MCHookSensorsInstall();
    MCHookFileManagerInstall();
    MCHookDefaultsInstall();

    // JBDetect must come after core hooks so spoofed values are visible
    MCHookJBDetectInstall();
    MCHookAntiDebugInstall();

    // P3: Wolverine + Signature + MissingAPI
    MCHookWolverineInstall();
    MCHookSignatureInstall();
    MCMissingAPIInstall();

    // Note: keychain is entirely LC's domain. MCHookKeychainInstall and
    // MCKeychainResetIfIdentityChanged are intentionally NOT called (and
    // MCHookKeychain.m is intentionally not part of this target): LC's own
    // SecItem hooks (Tweaks/SecItem.m, installed earlier via
    // SecItemGuestHooksInit) already separate containers across 128 access
    // groups. Layering MunChanger's keychain rewrite on top would rebind the
    // same Sec* symbols twice with conflicting group logic.

    {
        NSString *dbgPath = [NSHomeDirectory() stringByAppendingPathComponent:@"mcdebug.log"];
        FILE *f = fopen(dbgPath.fileSystemRepresentation, "a");
        if (f) { fprintf(f, "MCProfileInit hooks installed OK\n"); fclose(f); }
    }
    os_log_info(mcLog, "MCProfile: hooks installed OK — name=%@ model=%@ ios=%@",
            config.deviceName ?: @"-",
            config.deviceModel ?: @"-",
            config.systemVersion ?: @"-");

    return YES;
}
