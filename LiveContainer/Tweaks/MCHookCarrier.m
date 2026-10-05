#import "MCConfig.h"
#import "MCSwizzle.h"

#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>

typedef NSString *(*MCStringIMP)(id, SEL);

static MCStringIMP gOrigCarrierName;
static MCStringIMP gOrigISO;
static MCStringIMP gOrigMCC;
static MCStringIMP gOrigMNC;
static BOOL gHookedCarrier;

static NSString *MCHookedCarrierName(id self, SEL _cmd) {
    NSString *fake = [[MCConfig sharedConfig] carrierName];
    if (fake.length > 0) {
        return fake;
    }
    return gOrigCarrierName ? gOrigCarrierName(self, _cmd) : nil;
}

static NSString *MCHookedISO(id self, SEL _cmd) {
    NSString *fake = [[MCConfig sharedConfig] isoCountryCode];
    if (fake.length > 0) {
        return fake;
    }
    return gOrigISO ? gOrigISO(self, _cmd) : nil;
}

static NSString *MCHookedMCC(id self, SEL _cmd) {
    NSString *fake = [[MCConfig sharedConfig] mobileCountryCode];
    if (fake.length > 0) {
        return fake;
    }
    return gOrigMCC ? gOrigMCC(self, _cmd) : nil;
}

static NSString *MCHookedMNC(id self, SEL _cmd) {
    NSString *fake = [[MCConfig sharedConfig] mobileNetworkCode];
    if (fake.length > 0) {
        return fake;
    }
    return gOrigMNC ? gOrigMNC(self, _cmd) : nil;
}

static BOOL MCHookStr(Class cls, const char *selName, IMP replacement, MCStringIMP *orig) {
    IMP previous = NULL;
    if (!MCSwizzleInstance(cls, sel_registerName(selName), replacement, &previous)) {
        return NO;
    }
    *orig = (MCStringIMP)previous;
    return YES;
}

static NSString *MCHookedRadio(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    return @"CTRadioAccessTechnologyNRNSA";
}

static NSDictionary *MCHookedServiceRadio(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    return @{ @"0000000100000001" : @"CTRadioAccessTechnologyNRNSA" };
}

void MCHookCarrierInstall(void) {
    if (gHookedCarrier) {
        return;
    }
    Class radio = objc_getClass("CTTelephonyNetworkInfo");
    if (radio) {
        MCSwizzleInstance(radio, sel_registerName("currentRadioAccessTechnology"), (IMP)MCHookedRadio, NULL);
        MCSwizzleInstance(radio, sel_registerName("serviceCurrentRadioAccessTechnology"), (IMP)MCHookedServiceRadio, NULL);
    }
    Class cls = objc_getClass("CTCarrier");
    if (!cls) {
        return;
    }
    BOOL ok = YES;
    ok = MCHookStr(cls, "carrierName", (IMP)MCHookedCarrierName, &gOrigCarrierName) && ok;
    ok = MCHookStr(cls, "isoCountryCode", (IMP)MCHookedISO, &gOrigISO) && ok;
    ok = MCHookStr(cls, "mobileCountryCode", (IMP)MCHookedMCC, &gOrigMCC) && ok;
    ok = MCHookStr(cls, "mobileNetworkCode", (IMP)MCHookedMNC, &gOrigMNC) && ok;
    gHookedCarrier = ok;
}
