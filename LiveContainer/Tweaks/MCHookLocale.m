#import "MCConfig.h"
#import "MCSwizzle.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/// Fake TimeZone (4.2) / Locale (4.3) / Language (4.4).

typedef id (*MCObjectIMP)(id, SEL);

static MCObjectIMP gOrigSystemTimeZone;
static MCObjectIMP gOrigLocalTimeZone;
static MCObjectIMP gOrigDefaultTimeZone;
static MCObjectIMP gOrigCurrentLocale;
static MCObjectIMP gOrigAutoLocale;
static MCObjectIMP gOrigPreferredLanguages;
static MCObjectIMP gOrigBundlePreferredLocalizations;
static BOOL gHooked;

static id MCHookedSystemTimeZone(id self, SEL _cmd) {
    MCConfig *config = [MCConfig sharedConfig];
    if (config.fakeTimeZoneEnabled) {
        return [NSTimeZone timeZoneWithName:config.timeZoneName];
    }
    return gOrigSystemTimeZone(self, _cmd);
}

static id MCHookedLocalTimeZone(id self, SEL _cmd) {
    MCConfig *config = [MCConfig sharedConfig];
    if (config.fakeTimeZoneEnabled) {
        return [NSTimeZone timeZoneWithName:config.timeZoneName];
    }
    return gOrigLocalTimeZone(self, _cmd);
}

static id MCHookedDefaultTimeZone(id self, SEL _cmd) {
    MCConfig *config = [MCConfig sharedConfig];
    if (config.fakeTimeZoneEnabled) {
        return [NSTimeZone timeZoneWithName:config.timeZoneName];
    }
    return gOrigDefaultTimeZone(self, _cmd);
}

static id MCHookedCurrentLocale(id self, SEL _cmd) {
    MCConfig *config = [MCConfig sharedConfig];
    if (config.fakeLocaleEnabled) {
        return [NSLocale localeWithLocaleIdentifier:config.localeIdentifier];
    }
    return gOrigCurrentLocale(self, _cmd);
}

static id MCHookedAutoLocale(id self, SEL _cmd) {
    MCConfig *config = [MCConfig sharedConfig];
    if (config.fakeLocaleEnabled) {
        return [NSLocale localeWithLocaleIdentifier:config.localeIdentifier];
    }
    return gOrigAutoLocale(self, _cmd);
}

static id MCHookedPreferredLanguages(id self, SEL _cmd) {
    MCConfig *config = [MCConfig sharedConfig];
    if (config.fakeLanguageEnabled) {
        return [config.preferredLanguages copy];
    }
    return gOrigPreferredLanguages(self, _cmd);
}

static id MCHookedBundlePreferredLocalizations(id self, SEL _cmd) {
    MCConfig *config = [MCConfig sharedConfig];
    if (config.fakeLanguageEnabled) {
        return [config.preferredLanguages copy];
    }
    return gOrigBundlePreferredLocalizations(self, _cmd);
}

void MCHookLocaleInstall(void) {
    if (gHooked) return;
    gHooked = YES;

    Class tz = objc_getClass("NSTimeZone");
    Class tzMeta = tz ? object_getClass((id)tz) : nil;
    if (tzMeta) {
        MCSwizzleInstance(tzMeta, sel_registerName("systemTimeZone"), (IMP)MCHookedSystemTimeZone, (IMP *)&gOrigSystemTimeZone);
        MCSwizzleInstance(tzMeta, sel_registerName("localTimeZone"), (IMP)MCHookedLocalTimeZone, (IMP *)&gOrigLocalTimeZone);
        MCSwizzleInstance(tzMeta, sel_registerName("defaultTimeZone"), (IMP)MCHookedDefaultTimeZone, (IMP *)&gOrigDefaultTimeZone);
    }
    Class locale = objc_getClass("NSLocale");
    Class localeMeta = locale ? object_getClass((id)locale) : nil;
    if (localeMeta) {
        MCSwizzleInstance(localeMeta, sel_registerName("currentLocale"), (IMP)MCHookedCurrentLocale, (IMP *)&gOrigCurrentLocale);
        MCSwizzleInstance(localeMeta, sel_registerName("autoupdatingCurrentLocale"), (IMP)MCHookedAutoLocale, (IMP *)&gOrigAutoLocale);
        MCSwizzleInstance(localeMeta, sel_registerName("preferredLanguages"), (IMP)MCHookedPreferredLanguages, (IMP *)&gOrigPreferredLanguages);
    }
    Class bundle = objc_getClass("NSBundle");
    if (bundle) {
        MCSwizzleInstance(bundle, sel_registerName("preferredLocalizations"), (IMP)MCHookedBundlePreferredLocalizations, (IMP *)&gOrigBundlePreferredLocalizations);
    }
}
