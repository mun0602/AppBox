#import "MCConfig.h"
#import "MCSwizzle.h"

typedef BOOL (*MCExistsIMP)(id, SEL, NSString *);
typedef BOOL (*MCExistsDirIMP)(id, SEL, NSString *, BOOL *);
typedef NSDictionary *(*MCAttrsIMP)(id, SEL, NSString *, NSError **);
typedef NSDictionary *(*MCFSAttrsIMP)(id, SEL, NSString *, NSError **);

static MCExistsIMP gOrigExists;
static MCExistsDirIMP gOrigExistsDir;
static MCAttrsIMP gOrigAttrs;
static MCFSAttrsIMP gOrigFSAttrs;
static BOOL gHooked;

static NSDictionary *MCFakeFileAttrs(void) {
    return @{
        NSFileType: NSFileTypeRegular,
        NSFileSize: @1,
    };
}

static BOOL MCHookedExists(id self, SEL _cmd, NSString *path) {
    if ([[MCConfig sharedConfig] isIdentityPath:path]) {
        return YES;
    }
    return gOrigExists ? gOrigExists(self, _cmd, path) : NO;
}

static BOOL MCHookedExistsDir(id self, SEL _cmd, NSString *path, BOOL *isDir) {
    if ([[MCConfig sharedConfig] isIdentityPath:path]) {
        if (isDir) *isDir = NO;
        return YES;
    }
    return gOrigExistsDir ? gOrigExistsDir(self, _cmd, path, isDir) : NO;
}

static NSDictionary *MCHookedAttrs(id self, SEL _cmd, NSString *path, NSError **err) {
    if ([[MCConfig sharedConfig] isIdentityPath:path]) {
        if (err) *err = nil;
        return MCFakeFileAttrs();
    }
    return gOrigAttrs ? gOrigAttrs(self, _cmd, path, err) : nil;
}

static NSDictionary *MCHookedFSAttrs(id self, SEL _cmd, NSString *path, NSError **err) {
    if ([[MCConfig sharedConfig] isIdentityPath:path]) {
        if (err) *err = nil;
        return gOrigFSAttrs ? gOrigFSAttrs(self, _cmd, @"/", err) : nil;
    }
    return gOrigFSAttrs ? gOrigFSAttrs(self, _cmd, path, err) : nil;
}

void MCHookFileManagerInstall(void) {
    if (gHooked) {
        return;
    }
    Class cls = objc_getClass("NSFileManager");
    if (!cls) {
        return;
    }
    IMP prev = NULL;
    if (MCSwizzleInstance(cls, sel_registerName("fileExistsAtPath:"), (IMP)MCHookedExists, &prev)) {
        gOrigExists = (MCExistsIMP)prev;
    }
    if (MCSwizzleInstance(cls, sel_registerName("fileExistsAtPath:isDirectory:"), (IMP)MCHookedExistsDir, &prev)) {
        gOrigExistsDir = (MCExistsDirIMP)prev;
    }
    if (MCSwizzleInstance(cls, sel_registerName("attributesOfItemAtPath:error:"), (IMP)MCHookedAttrs, &prev)) {
        gOrigAttrs = (MCAttrsIMP)prev;
    }
    if (MCSwizzleInstance(cls, sel_registerName("attributesOfFileSystemForPath:error:"), (IMP)MCHookedFSAttrs, &prev)) {
        gOrigFSAttrs = (MCFSAttrsIMP)prev;
    }
    gHooked = YES;
}
