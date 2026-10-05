#import "MCSwizzle.h"

BOOL MCSwizzleInstance(Class cls, SEL sel, IMP replacement, IMP *originalOut) {
    if (!cls || !sel || !replacement) {
        return NO;
    }
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) {
        return NO;
    }
    IMP previous = method_setImplementation(method, replacement);
    if (originalOut) {
        *originalOut = previous;
    }
    return YES;
}
