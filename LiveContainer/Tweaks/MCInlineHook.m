#import "MCInlineHook.h"

#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

#if !__has_feature(objc_arc)
#error MCInlineHook requires ARC
#endif

typedef void (*MSHookFunctionFn)(void *symbol, void *replace, void **result);
static MSHookFunctionFn gMSHookFunction = NULL;
static dispatch_once_t gSubstrateOnce;

static void MCEnsureSubstrate(void) {
    dispatch_once(&gSubstrateOnce, ^{
        // LiveContainer: TweakLoader dlopen CydiaSubstrate RTLD_GLOBAL trước khi
        // load tweaks, nên symbol đã nằm trong global namespace — dò RTLD_DEFAULT
        // trước khi thử path cứng (path @executable_path trỏ bundle host LC,
        // không phải bundle guest, path /Library và /usr/lib chỉ có trên JB).
        gMSHookFunction = (MSHookFunctionFn)dlsym(RTLD_DEFAULT, "MSHookFunction");
        if (gMSHookFunction) return;
        const char *paths[] = {
            "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            "/usr/lib/libsubstrate.dylib",
            "@executable_path/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            "@loader_path/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            NULL
        };
        for (int i = 0; paths[i]; i++) {
            void *h = dlopen(paths[i], RTLD_LAZY | RTLD_GLOBAL);
            if (!h) {
                h = dlopen(paths[i], RTLD_NOLOAD);
            }
            if (h) {
                gMSHookFunction = (MSHookFunctionFn)dlsym(h, "MSHookFunction");
                if (gMSHookFunction) break;
            }
        }
    });
}

BOOL MCInlineHook(void *target, void *replacement) {
    if (!target || !replacement) return NO;
    MCEnsureSubstrate();
    if (gMSHookFunction) {
        void *orig = NULL;
        gMSHookFunction(target, replacement, &orig);
        return YES;
    }
    return NO;
}

BOOL MCInlineHookOrig(void *target, void *replacement, void **origOut) {
    if (!target || !replacement || !origOut) return NO;
    MCEnsureSubstrate();
    if (gMSHookFunction) {
        *origOut = NULL;
        gMSHookFunction(target, replacement, origOut);
        return (*origOut != NULL);
    }
    return NO;
}

int MCInlineHookNamed(const char *name, void *replacement) {
    (void)name;
    (void)replacement;
    return 0;
}
