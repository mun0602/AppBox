#import "MCConfig.h"
#import "MCDeviceCatalog.h"
#import "MCSwizzle.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

/// Fake kích thước màn hình theo model (mục 2.1 Screen Size + 2.2 Full Screen).
/// Cơ chế XoaInfo: swizzle 5 method UIScreen (bounds/applicationFrame/nativeBounds/
/// nativeScale/scale) — trả CGRect/CGFloat tra từ ProductType. Fail-open: option
/// tắt hoặc model lạ → gọi orig.

typedef CGRect (*MCREctIMP)(id, SEL);
typedef CGFloat (*MCFloatIMP)(id, SEL);
typedef void (*MCVoidIMP)(id, SEL, id);

static MCREctIMP gOrigBounds;
static MCREctIMP gOrigAppFrame;
static MCREctIMP gOrigNativeBounds;
static MCFloatIMP gOrigScale;
static MCFloatIMP gOrigNativeScale;
static MCVoidIMP gOrigSetDelegate;
static BOOL gHooked;

typedef struct {
    CGFloat w, h;
    CGFloat scale;
    CGFloat nativeScale;
    CGFloat pixW, pixH;
} MCScreenSpec;

static MCScreenSpec MCGScreenSpecForModel(NSString *model) {
    MCScreenSpec spec = { 0, 0, 0, 0, 0, 0 };
    double w = 0, h = 0, scale = 0, native = 0, pixW = 0, pixH = 0;
    if (![MCDeviceCatalog screenForModel:model width:&w height:&h scale:&scale nativeScale:&native pixelWidth:&pixW pixelHeight:&pixH]) {
        return spec;
    }
    spec.w = (CGFloat)w;
    spec.h = (CGFloat)h;
    spec.scale = (CGFloat)scale;
    spec.nativeScale = (CGFloat)(native > 0 ? native : scale);
    spec.pixW = (CGFloat)pixW;
    spec.pixH = (CGFloat)pixH;
    return spec;
}

static BOOL MCGScreenFake(MCScreenSpec *out) {
    if (!out) return NO;
    MCConfig *config = [MCConfig sharedConfig];
    if (!config.fakeScreenEnabled) return NO;
    MCScreenSpec spec = MCGScreenSpecForModel(config.deviceModel);
    if (spec.w == 0 || spec.h == 0) return NO;
    *out = spec;
    return YES;
}

static CGRect MCHookedBounds(id self, SEL _cmd) {
    MCScreenSpec spec;
    if (MCGScreenFake(&spec)) {
        return CGRectMake(0, 0, spec.w, spec.h);
    }
    return gOrigBounds(self, _cmd);
}

static CGRect MCHookedApplicationFrame(id self, SEL _cmd) {
    MCScreenSpec spec;
    if (MCGScreenFake(&spec)) {
        // Full screen trừ status bar ~47pt (đúng hành vi applicationFrame).
        return CGRectMake(0, 47, spec.w, spec.h - 47);
    }
    return gOrigAppFrame(self, _cmd);
}

static CGRect MCHookedNativeBounds(id self, SEL _cmd) {
    MCScreenSpec spec;
    if (MCGScreenFake(&spec)) {
        return CGRectMake(0, 0, spec.pixW, spec.pixH);
    }
    return gOrigNativeBounds(self, _cmd);
}

static CGFloat MCHookedScale(id self, SEL _cmd) {
    MCScreenSpec spec;
    if (MCGScreenFake(&spec)) {
        return spec.scale;
    }
    return gOrigScale(self, _cmd);
}

static CGFloat MCHookedNativeScale(id self, SEL _cmd) {
    MCScreenSpec spec;
    if (MCGScreenFake(&spec)) {
        return spec.nativeScale > 0 ? spec.nativeScale : spec.scale;
    }
    return gOrigNativeScale(self, _cmd);
}

// WeChat thấy iOS 26 thì gọi method này lúc scene vào foreground.
// iOS 16 không có. Trả nil để lời gọi objc vào nil, không abort.
static id MCEmptySystemProtectionManager(id self, SEL _cmd) {
    return nil;
}

// +[NSURL URLWithString:encodingInvalidCharacters:] có từ iOS 17.
// Chuỗi hợp lệ đi đường URLWithString:. Chuỗi hỏng và encode=YES thì bọc phần trăm.
static NSURL *MCURLWithStringEncoding(id self, SEL _cmd, NSString *string, BOOL encodeInvalid) {
    if (![string isKindOfClass:[NSString class]]) return nil;
    NSURL *url = [NSURL URLWithString:string];
    if (url || !encodeInvalid) return url;
    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
    NSString *encoded = [string stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return encoded ? [NSURL URLWithString:encoded] : nil;
}

void MCHookScreenInstall(void) {
    if (gHooked) return;
    gHooked = YES;
    Class cls = objc_getClass("UIScreen");
    if (!cls) return;
    MCSwizzleInstance(cls, sel_registerName("bounds"), (IMP)MCHookedBounds, (IMP *)&gOrigBounds);
    MCSwizzleInstance(cls, sel_registerName("applicationFrame"), (IMP)MCHookedApplicationFrame, (IMP *)&gOrigAppFrame);
    MCSwizzleInstance(cls, sel_registerName("nativeBounds"), (IMP)MCHookedNativeBounds, (IMP *)&gOrigNativeBounds);
    MCSwizzleInstance(cls, sel_registerName("scale"), (IMP)MCHookedScale, (IMP *)&gOrigScale);
    MCSwizzleInstance(cls, sel_registerName("nativeScale"), (IMP)MCHookedNativeScale, (IMP *)&gOrigNativeScale);
    Class scene = objc_getClass("UIWindowScene");
    SEL prot = sel_registerName("systemProtectionManager");
    if (scene && !class_getInstanceMethod(scene, prot)) {
        class_addMethod(scene, prot, (IMP)MCEmptySystemProtectionManager, "@@:");
    }
    Class url = objc_getClass("NSURL");
    SEL urlSel = sel_registerName("URLWithString:encodingInvalidCharacters:");
    Class urlMeta = url ? object_getClass((id)url) : nil;
    if (urlMeta && !class_getInstanceMethod(urlMeta, urlSel)) {
        class_addMethod(urlMeta, urlSel, (IMP)MCURLWithStringEncoding, "@@:@B");
    }
}
