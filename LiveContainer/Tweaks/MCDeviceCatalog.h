#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Danh mục thiết bị + bản iOS. Nguồn: resources/devices.json và os-releases.json,
/// nhúng lúc build bởi tools/gen_catalog.py.
@interface MCDeviceCatalog : NSObject

+ (BOOL)containsModel:(nullable NSString *)model;

/// "iPhone" | "iPad" → identifier có random=true.
+ (nullable NSString *)randomModelIdentifierForFamily:(NSString *)family;

/// Toàn bộ identifier theo family ("iPhone" | "iPad"), mới nhất lên đầu
/// (iPhone17,2 trước iPhone14,2). Dùng cho UI picker.
+ (NSArray<NSString *> *)modelIdentifiersForFamily:(NSString *)family;

+ (nullable NSString *)displayNameForModel:(NSString *)model;
+ (double)screenInchesForModel:(NSString *)model;
+ (nullable NSString *)subtitleForModel:(NSString *)model;

+ (NSInteger)minOSMajorForModel:(NSString *)model;
+ (NSInteger)maxOSMajorForModel:(NSString *)model;

+ (nullable NSString *)boardForModel:(NSString *)model;
/// "Apple A15", "Apple A18 Pro", "Apple M4". nil nếu catalog không ghi chip.
+ (nullable NSString *)chipNameForModel:(NSString *)model;
+ (uint64_t)ramBytesForModel:(NSString *)model;
+ (NSInteger)cpuCountForModel:(NSString *)model;
+ (uint32_t)cpuFamilyForModel:(NSString *)model;
/// CPU_TYPE_ARM64. 0 nếu không có máy.
+ (uint32_t)cpuTypeForModel:(NSString *)model;
/// 2 = arm64e (A12 trở đi / M). 0 = arm64 cũ hoặc chưa biết chip.
+ (uint32_t)cpuSubtypeForModel:(NSString *)model;

/// Point dọc, scale, nativeScale, pixel dọc. NO nếu không có máy.
+ (BOOL)screenForModel:(NSString *)model
                  width:(double *)width
                 height:(double *)height
                  scale:(double *)scale
            nativeScale:(double *)nativeScale
             pixelWidth:(double *)pixelWidth
            pixelHeight:(double *)pixelHeight;

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)versionsForModel:(nullable NSString *)model
                                                             minMajor:(NSInteger)minMajor
                                                             maxMajor:(NSInteger)maxMajor;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)versionsForModel:(nullable NSString *)model;
+ (nullable NSString *)buildForVersion:(NSString *)ios;
/// kern.osrelease khớp bản, ví dụ iOS 27 → "26.0.0". nil nếu không có bản.
+ (nullable NSString *)darwinForVersion:(NSString *)ios;

@end

NS_ASSUME_NONNULL_END
