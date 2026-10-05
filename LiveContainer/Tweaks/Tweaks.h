//
//  Tweaks.h
//  LiveContainer
//
//  Created by s s on 2025/2/7.
//

void swizzle(Class class, SEL originalAction, SEL swizzledAction);
bool performHookDyldApi(const char* functionName, uint32_t adrpOffset, void** origFunction, void* hookFunction);

void NUDGuestHooksInit(void);
void SecItemGuestHooksInit(void);
void DyldHooksInit(bool hideLiveContainer, bool hookDlopen, uint32_t spoofSDKVersion);
void NSFMGuestHooksInit(void);
void NSURLSCGuestHooksInit(void);
void initDead10ccFix(void);
void IDFVHookInit(NSUUID* uuid);

// MunChanger profile hooks — called by MCProfileInit()
// NOTE: keychain hook intentionally absent — LC's own SecItem hooks own that domain.
void MCHookGestaltInstall(void);
void MCHookDeviceInstall(void);
void MCHookVersionInstall(void);
void MCHookCarrierInstall(void);
void MCHookScreenInstall(void);
void MCHookNetworkInstall(void);
void MCHookAdvertisingInstall(void);
void MCHookLocaleInstall(void);
void MCHookTimeInstall(void);
void MCHookLocationInstall(void);
void MCHookMotionInstall(void);
void MCHookSensorsInstall(void);
void MCHookFileManagerInstall(void);
void MCHookDefaultsInstall(void);
void MCHookJBDetectInstall(void);
void MCHookAntiDebugInstall(void);
void MCHookWolverineInstall(void);
void MCHookSignatureInstall(void);
void MCMissingAPIInstall(void);
BOOL MCProfileInit(void);

@interface NSBundle(LiveContainer)
- (instancetype)initWithPathForMainBundle:(NSString *)path;
@end


extern uint32_t appMainImageIndex;
extern void* appExecutableHandle;
extern bool tweakLoaderLoaded;
void* getGuestAppHeader(void);
void* getDSCAddr(void);
void* getCachedSymbol(NSString* symbolName, struct mach_header_64* header);
void saveCachedSymbol(NSString* symbolName, struct mach_header_64* header, uint64_t offset);
void* dlopen_nolock(const char *path, int mode);
void bypass_seg_count_check(void (^block)(void));

static void hook_do_nothing(void) {}
