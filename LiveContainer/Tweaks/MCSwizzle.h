#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/// Đổi IMP instance method. NO và không đụng originalOut nếu class/selector/method thiếu.
BOOL MCSwizzleInstance(Class _Nullable cls, SEL _Nullable sel, IMP _Nullable replacement, IMP _Nullable *_Nullable originalOut);

NS_ASSUME_NONNULL_END
