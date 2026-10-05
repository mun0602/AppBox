#import "MCConfig.h"

#import <os/log.h>

// LiveContainer port note: this file originally contained the standalone
// MunChanger dylib's __attribute__((constructor)) entry, which auto-installed
// all 18 hook groups at dylib load time (and called MCHookKeychainInstall /
// MCKeychainResetIfIdentityChanged). That behavior is WRONG inside
// LiveContainer:
//   1. A constructor would fire in every process linking LiveContainerShared
//      (UI app, extensions) — not just guest app processes.
//   2. It would run before LCBootstrap sets up the guest environment, so
//      MCConfig would resolve paths against the wrong HOME.
//   3. It would double-install hooks together with MCProfileInit().
//   4. Keychain is LC's domain (Tweaks/SecItem.m) — deliberately not ported.
// The single integration entry is now MCProfileInit() (MCProfile.m), called
// from LCBootstrap.m after DyldHooksInit. Only the logger survives here.

// Log thật. Bản cũ có `logline` là stub rỗng nên khi config hỏng hoặc bị
// disable, constructor thoát im lặng và không ai biết hook chưa cài — monitor
// tay không phân biệt được "hook chưa cài" với "hook trả giá trị thật".
// Đọc: log stream --predicate 'subsystem == "com.mun.changer"'
void MCLogLine(NSString *message) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.mun.changer", "dylib");
    });
    os_log_info(log, "%{public}s", message.UTF8String ?: "");
}
