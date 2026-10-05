#import "MCConfig.h"
#import "MCSwizzle.h"

#import <objc/runtime.h>
#import <stdio.h>

void MCLogLine(NSString *message);

static void (*gOrigInst)(id, SEL, SEL);
static void (*gOrigClass)(id, SEL, SEL);

// Lần gọi này vẫn thoát. Lần sau cùng selector đã có method trả nil, app đi tiếp
// và ghi hàm thiếu kế tiếp. File: Library/mc-missing.txt trong container app.
static id MCNilStub(id self, SEL _cmd) {
    return nil;
}

static NSString *MCMissingPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/mc-missing.txt"];
}

static void MCWriteMissing(NSString *line) {
    MCLogLine(line);
    FILE *f = fopen(MCMissingPath().fileSystemRepresentation, "a");
    if (!f) return;
    fprintf(f, "%s\n", line.UTF8String ?: "");
    fflush(f);
    fclose(f);
}

static void MCInstallStub(const char *className, SEL sel, BOOL isClassMethod) {
    if (!className || !sel) return;
    Class cls = objc_getClass(className);
    if (!cls) return;
    Class bucket = isClassMethod ? object_getClass((id)cls) : cls;
    if (!class_getInstanceMethod(bucket, sel)) {
        class_addMethod(bucket, sel, (IMP)MCNilStub, "@@:");
    }
}

// Lần mở sau gắn lại các hàm đã ghi, để app đi qua hàm cũ và lộ hàm thiếu kế tiếp.
static void MCReplayMissing(void) {
    FILE *f = fopen(MCMissingPath().fileSystemRepresentation, "r");
    if (!f) return;
    char buf[512];
    while (fgets(buf, sizeof(buf), f)) {
        char kind[8] = {0};
        char cls[160] = {0};
        char seln[160] = {0};
        if (sscanf(buf, "%7s %159s %159s", kind, cls, seln) != 3) continue;
        SEL sel = sel_registerName(seln);
        MCInstallStub(cls, sel, kind[0] == '+');
    }
    fclose(f);
}

static void MCNoteMissing(id self, SEL sel, BOOL isClassMethod) {
    if (!self || !sel) return;
    const char *name = object_getClassName(self);
    NSString *line = [NSString stringWithFormat:@"%@ %s %s",
                      isClassMethod ? @"+" : @"-",
                      name ?: "?",
                      sel_getName(sel)];
    static NSMutableSet *seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        seen = [NSMutableSet set];
    });
    @synchronized (seen) {
        if ([seen containsObject:line]) return;
        [seen addObject:line];
    }
    // Instance: class của object. Class method: metaclass, vì self là Class.
    MCInstallStub(name, sel, isClassMethod);
    MCWriteMissing(line);
}

static void MCMissingInstance(id self, SEL _cmd, SEL sel) {
    MCNoteMissing(self, sel, NO);
    if (gOrigInst) gOrigInst(self, _cmd, sel);
}

static void MCMissingClass(id self, SEL _cmd, SEL sel) {
    MCNoteMissing(self, sel, YES);
    if (gOrigClass) gOrigClass(self, _cmd, sel);
}

void MCMissingAPIInstall(void) {
    NSString *ver = [MCConfig sharedConfig].systemVersion;
    if (ver.intValue < 17) return;
    MCReplayMissing();
    Class ns = objc_getClass("NSObject");
    if (!ns) return;
    MCSwizzleInstance(ns, sel_registerName("doesNotRecognizeSelector:"),
                      (IMP)MCMissingInstance, (IMP *)&gOrigInst);
    MCSwizzleInstance(object_getClass((id)ns), sel_registerName("doesNotRecognizeSelector:"),
                      (IMP)MCMissingClass, (IMP *)&gOrigClass);
    MCLogLine(@"missing_api watch on");
}
