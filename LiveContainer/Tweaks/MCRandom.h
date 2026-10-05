#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Port của app/MCRandom.m từ MunChanger standalone, cho LiveContainer.
/// Khác biệt so với bản gốc:
///   - Resources load từ MCResources (compile-in) thay vì walk bundle/CWD.
///   - Khoảng iOS major nhận qua tham số thay vì MCConfig app-side.
///   - Seeded identity nhận seed tường minh (UI lưu seed vào plist) thay vì
///     global state trong NSUserDefaults.
///
/// Output dict dùng đúng key mà dylib MCConfig.m đọc (model/ios/build/serial/
/// udid/name/carrier/mcc/mnc/iso/imei/wifiAddress/bluetoothAddress/...).
@interface MCRandom : NSObject

+ (NSString *)randomSerial;
/// 40 ký tự hex không gạch — đúng format UDID iOS thật.
+ (NSString *)randomUDID;
/// 15 số, prefix 35, Luhn checksum hợp lệ.
+ (NSString *)randomIMEI;
/// MAC dùng Apple OUI thật; byte đầu & 0xfe (unicast, không multicast).
+ (NSString *)randomWiFiAddress;
+ (NSString *)randomBluetoothAddress;

+ (nullable NSString *)randomModelForFamily:(NSString *)family;
+ (NSString *)randomDeviceName;
+ (NSDictionary<NSString *, NSString *> *)randomCarrierRecord;
+ (NSString *)userAgentForIOS:(NSString *)ios;

/// Sinh toàn bộ hồ sơ vào dict: identity + model + ios/build/darwin +
/// board/chip/RAM/CPU + carrier + tên thiết bị. Giữ nguyên family của
/// dict[@"model"] nếu đã có. minMajor/maxMajor giới hạn khoảng iOS (mặc định
/// 15–26); 0/0 = không giới hạn.
+ (void)fillRandomIdentity:(NSMutableDictionary *)dictionary;
+ (void)fillRandomIdentity:(NSMutableDictionary *)dictionary
                minIOSMajor:(NSInteger)minMajor
                maxIOSMajor:(NSInteger)maxMajor;

/// Như trên nhưng model cố định (ios/build/board/chip/... sinh theo model này).
+ (void)fillIdentityForModel:(NSString *)model intoDictionary:(NSMutableDictionary *)dictionary;
+ (void)fillIdentityForModel:(NSString *)model
               intoDictionary:(NSMutableDictionary *)dictionary
                 minIOSMajor:(NSInteger)minMajor
                 maxIOSMajor:(NSInteger)maxMajor;

#pragma mark - Seeded (UDIDFaker-style: SHA256 seed|purpose — ổn định theo seed)

+ (NSString *)seededHex:(NSString *)seed purpose:(NSString *)purpose length:(NSUInteger)length;
+ (NSString *)seededUDID:(NSString *)seed;
+ (NSString *)seededUUID:(NSString *)seed purpose:(NSString *)purpose;
/// Thay các trường định danh (serial/udid/imei/idfa/wifi/bt) bằng bản seeded;
/// model/ios/build/carrier vẫn giữ nguyên như dict hiện tại.
+ (void)fillSeededIdentity:(NSMutableDictionary *)dictionary seed:(NSString *)seed;

@end

NS_ASSUME_NONNULL_END
