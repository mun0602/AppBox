#import "MCConfig.h"
#import "MCRebind.h"
#import "MCSwizzle.h"

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>

/// IDFA / ATT denied / pasteboard rỗng / accessibility + content size = không lộ máy thật.

typedef id (*MCObjectIMP)(id, SEL);
typedef BOOL (*MCBoolIMP)(id, SEL);
typedef NSUInteger (*MCStatusIMP)(id, SEL);
typedef BOOL (*MCAccFn)(void);

static MCObjectIMP gOrigAdvertisingID;
static MCBoolIMP gOrigTrackingEnabled;
static MCStatusIMP gOrigATTStatus;
static MCObjectIMP gOrigGeneralPasteboard;
static MCObjectIMP gOrigContentSize;
static MCAccFn gOrigVoiceOver;
static MCAccFn gOrigBoldText;
static MCAccFn gOrigInvertColors;
static MCAccFn gOrigReduceMotion;
static BOOL gHooked;

static BOOL MCHookInst(Class cls, const char *selName, IMP replacement, IMP *orig) {
    if (!cls) return NO;
    IMP previous = NULL;
    if (!MCSwizzleInstance(cls, sel_registerName(selName), replacement, &previous)) return NO;
    if (orig) *orig = previous;
    return YES;
}

/// Class method = instance method của metaclass.
static BOOL MCHookClass(Class cls, const char *selName, IMP replacement, IMP *orig) {
    return MCHookInst(cls ? object_getClass((id)cls) : Nil, selName, replacement, orig);
}

static Class MCClassNamed(const char *name, const char *frameworkPath) {
    Class cls = objc_getClass(name);
    if (!cls && frameworkPath) {
        dlopen(frameworkPath, RTLD_LAZY);
        cls = objc_getClass(name);
    }
    return cls;
}

static id MCHookedAdvertisingID(id self, SEL _cmd) {
    MCConfig *config = [MCConfig sharedConfig];
    if (config.isEnabled) {
        NSUUID *fake = config.advertisingUUID;
        if (fake) return fake;
    }
    return gOrigAdvertisingID ? gOrigAdvertisingID(self, _cmd) : nil;
}

static BOOL MCHookedTrackingEnabled(id self, SEL _cmd) {
    if ([[MCConfig sharedConfig] isEnabled]) return NO;
    return gOrigTrackingEnabled ? gOrigTrackingEnabled(self, _cmd) : NO;
}

static NSUInteger MCHookedATTStatus(id self, SEL _cmd) {
    // 2 = ATTrackingManagerAuthorizationStatusDenied. Không trả authorized.
    if ([[MCConfig sharedConfig] isEnabled]) return 2;
    return gOrigATTStatus ? gOrigATTStatus(self, _cmd) : 0;
}

static id MCHookedGeneralPasteboard(id self, SEL _cmd) {
    if ([[MCConfig sharedConfig] isEnabled]) {
        return [UIPasteboard pasteboardWithName:@"mun.fake.empty" create:YES];
    }
    return gOrigGeneralPasteboard ? gOrigGeneralPasteboard(self, _cmd) : nil;
}

static id MCHookedContentSize(id self, SEL _cmd) {
    if ([[MCConfig sharedConfig] isEnabled]) return UIContentSizeCategoryLarge;
    return gOrigContentSize ? gOrigContentSize(self, _cmd) : UIContentSizeCategoryLarge;
}

static BOOL MCAccCall(MCAccFn *slot, const char *name, void *selfFn) {
    if (!*slot) {
        void *p = dlsym(RTLD_NEXT, name);
        if (!p || p == selfFn) p = dlsym(RTLD_DEFAULT, name);
        if (p == selfFn) p = NULL;
        *slot = (MCAccFn)p;
    }
    if ([[MCConfig sharedConfig] isEnabled]) return NO;
    return *slot ? (*slot)() : NO;
}

static BOOL MCHookedVoiceOver(void) {
    return MCAccCall(&gOrigVoiceOver, "UIAccessibilityIsVoiceOverRunning", (void *)MCHookedVoiceOver);
}

static BOOL MCHookedBoldText(void) {
    return MCAccCall(&gOrigBoldText, "UIAccessibilityIsBoldTextEnabled", (void *)MCHookedBoldText);
}

static BOOL MCHookedInvertColors(void) {
    return MCAccCall(&gOrigInvertColors, "UIAccessibilityIsInvertColorsEnabled", (void *)MCHookedInvertColors);
}

static BOOL MCHookedReduceMotion(void) {
    return MCAccCall(&gOrigReduceMotion, "UIAccessibilityIsReduceMotionEnabled", (void *)MCHookedReduceMotion);
}

#define DYLD_INTERPOSE(_replacement,_replacee) \
__attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

DYLD_INTERPOSE(MCHookedVoiceOver, UIAccessibilityIsVoiceOverRunning)
DYLD_INTERPOSE(MCHookedBoldText, UIAccessibilityIsBoldTextEnabled)
DYLD_INTERPOSE(MCHookedInvertColors, UIAccessibilityIsInvertColorsEnabled)
DYLD_INTERPOSE(MCHookedReduceMotion, UIAccessibilityIsReduceMotionEnabled)

static void MCRebindAcc(const char *name, void *replacement, MCAccFn *orig) {
    if (!dlsym(RTLD_DEFAULT, name) && !dlsym(RTLD_NEXT, name)) return;
    MCRebindSymbol(name, replacement, (void **)orig);
    if (*orig == (MCAccFn)replacement) *orig = NULL;
}

void MCHookAdvertisingInstall(void) {
    if (gHooked) return;
    gHooked = YES;

    Class idfa = MCClassNamed("ASIdentifierManager",
                              "/System/Library/Frameworks/AdSupport.framework/AdSupport");
    if (idfa) {
        MCHookInst(idfa, "advertisingIdentifier", (IMP)MCHookedAdvertisingID, (IMP *)&gOrigAdvertisingID);
        MCHookInst(idfa, "isAdvertisingTrackingEnabled", (IMP)MCHookedTrackingEnabled, (IMP *)&gOrigTrackingEnabled);
    }

    Class att = MCClassNamed("ATTrackingManager",
                             "/System/Library/Frameworks/AppTrackingTransparency.framework/AppTrackingTransparency");
    if (att) {
        MCHookClass(att, "trackingAuthorizationStatus", (IMP)MCHookedATTStatus, (IMP *)&gOrigATTStatus);
    }

    Class paste = objc_getClass("UIPasteboard");
    if (paste) {
        MCHookClass(paste, "generalPasteboard", (IMP)MCHookedGeneralPasteboard, (IMP *)&gOrigGeneralPasteboard);
    }

    Class app = objc_getClass("UIApplication");
    if (app) {
        MCHookInst(app, "preferredContentSizeCategory", (IMP)MCHookedContentSize, (IMP *)&gOrigContentSize);
    }

    MCRebindAcc("UIAccessibilityIsVoiceOverRunning", (void *)MCHookedVoiceOver, &gOrigVoiceOver);
    MCRebindAcc("UIAccessibilityIsBoldTextEnabled", (void *)MCHookedBoldText, &gOrigBoldText);
    MCRebindAcc("UIAccessibilityIsInvertColorsEnabled", (void *)MCHookedInvertColors, &gOrigInvertColors);
    MCRebindAcc("UIAccessibilityIsReduceMotionEnabled", (void *)MCHookedReduceMotion, &gOrigReduceMotion);
}
