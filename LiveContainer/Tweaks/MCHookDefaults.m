#import "MCConfig.h"
#import "MCSwizzle.h"

typedef id (*MCObjectIMP)(id, SEL, NSString *);
typedef NSInteger (*MCIntegerIMP)(id, SEL, NSString *);
typedef BOOL (*MCBoolIMP)(id, SEL, NSString *);

static MCObjectIMP gOrigObjectForKey;
static MCIntegerIMP gOrigIntegerForKey;
static MCBoolIMP gOrigBoolForKey;
static BOOL gHooked;

static id MCHookedObjectForKey(id self, SEL _cmd, NSString *key) {
    id fake = [[MCConfig sharedConfig] defaultsValueForKey:key];
    if (fake) {
        return fake;
    }
    return gOrigObjectForKey ? gOrigObjectForKey(self, _cmd, key) : nil;
}

static NSInteger MCHookedIntegerForKey(id self, SEL _cmd, NSString *key) {
    id fake = [[MCConfig sharedConfig] defaultsValueForKey:key];
    if (fake && [fake respondsToSelector:@selector(integerValue)]) {
        return [fake integerValue];
    }
    return gOrigIntegerForKey ? gOrigIntegerForKey(self, _cmd, key) : 0;
}

static BOOL MCHookedBoolForKey(id self, SEL _cmd, NSString *key) {
    id fake = [[MCConfig sharedConfig] defaultsValueForKey:key];
    if (fake && [fake respondsToSelector:@selector(boolValue)]) {
        return [fake boolValue];
    }
    return gOrigBoolForKey ? gOrigBoolForKey(self, _cmd, key) : NO;
}

void MCHookDefaultsInstall(void) {
    if (gHooked) {
        return;
    }
    Class cls = objc_getClass("NSUserDefaults");
    if (!cls) {
        return;
    }
    IMP previous = NULL;
    if (MCSwizzleInstance(cls, sel_registerName("objectForKey:"), (IMP)MCHookedObjectForKey, &previous)) {
        gOrigObjectForKey = (MCObjectIMP)previous;
    }
    previous = NULL;
    if (MCSwizzleInstance(cls, sel_registerName("integerForKey:"), (IMP)MCHookedIntegerForKey, &previous)) {
        gOrigIntegerForKey = (MCIntegerIMP)previous;
    }
    previous = NULL;
    if (MCSwizzleInstance(cls, sel_registerName("boolForKey:"), (IMP)MCHookedBoolForKey, &previous)) {
        gOrigBoolForKey = (MCBoolIMP)previous;
    }
    gHooked = YES;
}
