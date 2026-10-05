#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCConfig : NSObject

@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;

+ (instancetype)sharedConfig;

/// Đọc com.mun.changer.plist. NO nếu file thiếu hoặc không phải dict.
- (BOOL)reload;

/// model, rồi ProductType. Nil nếu trống.
- (nullable NSString *)deviceModel;

- (nullable NSString *)hwModel;

- (nullable NSString *)stringForAliases:(NSArray<NSString *> *)aliases;

/// name, rồi DeviceName.
- (nullable NSString *)deviceName;

/// systemVersion, rồi ProductVersion.
- (nullable NSString *)systemVersion;

/// carrier, rồi carrierName.
- (nullable NSString *)carrierName;

- (nullable NSString *)serialNumber;
- (nullable NSString *)udid;
- (nullable NSString *)buildVersion;
- (nullable NSString *)isoCountryCode;
- (nullable NSString *)mobileCountryCode;
- (nullable NSString *)mobileNetworkCode;
- (nullable NSString *)imei;
/// IMSI giả. Thiếu key thì không bịa.
- (nullable NSString *)imsi;
- (nullable NSString *)boardId;
- (nullable NSString *)chipId;
- (nullable NSString *)hardwarePlatform;
- (nullable NSString *)wifiAddress;
- (nullable NSString *)bluetoothAddress;

/// UUID ổn định từ udid. Nil nếu không có udid.
- (nullable NSUUID *)vendorUUID;

/// optionFakeScreen — mục 2.1/2.2 (kích thước màn theo model).
- (BOOL)fakeScreenEnabled;
/// optionFakeGPS — mục 4.1.
- (BOOL)fakeGPSEnabled;
- (double)gpsLatitude;
- (double)gpsLongitude;
/// optionFakeTimeZone — mục 4.2.
- (BOOL)fakeTimeZoneEnabled;
- (nullable NSString *)timeZoneName;
/// optionFakeLocale — mục 4.3.
- (BOOL)fakeLocaleEnabled;
- (nullable NSString *)localeIdentifier;
/// optionFakeLanguage — mục 4.4.
- (BOOL)fakeLanguageEnabled;
- (nullable NSArray<NSString *> *)preferredLanguages;
/// optionFakeSensors — mục 7 (rung/gia tốc).
- (BOOL)fakeSensorsEnabled;

#pragma mark - Kuaishou / hardware profile (Phase 0–3)

/// RAM bytes (`hw.memsize`). 0 = không fake.
- (uint64_t)memsizeBytes;
/// Số nhân CPU (`hw.ncpu` / physical / logical / active). 0 = không fake.
- (int)cpuCount;
/// `hw.cpufamily` (vd A15 = 0x287a2ae7). 0 = không fake.
- (uint32_t)cpuFamily;
- (uint32_t)cpuType;
- (uint32_t)cpuSubtype;
/// `hw.cpufrequency` Hz. 0 = không fake.
- (uint64_t)cpuFrequencyHz;
/// `kern.boottime` giây (epoch). 0 = không fake.
- (int64_t)boottimeSec;
- (int32_t)boottimeUsec;
/// `kern.bootsessionuuid` — cố định per-profile.
- (nullable NSString *)bootSessionUUID;
/// `kern.hostname` / NSProcessInfo hostName.
- (nullable NSString *)hostName;
/// Darwin release cho `uname.release` (vd 22.5.0).
- (nullable NSString *)darwinRelease;
/// IDFA (`ASIdentifierManager`).
- (nullable NSUUID *)advertisingUUID;
/// SSID / BSSID Wi-Fi giả.
- (nullable NSString *)wifiSSID;
- (nullable NSString *)wifiBSSID;
/// Disk total / free bytes (`statfs`). 0 = không fake.
- (uint64_t)diskTotalBytes;
- (uint64_t)diskFreeBytes;
/// Bật ẩn path JB + scheme cydia (mặc định YES khi enabled).
- (BOOL)hideJailbreakEnabled;
/// Bật rewrite mạng (getifaddrs / SSID / getenv). Mặc định YES khi có wifiAddress hoặc wifiSSID.
- (BOOL)fakeNetworkEnabled;

/// Giá trị giả cho NSUserDefaults objectForKey:. Nil nếu key không thuộc identity.
- (nullable id)defaultsValueForKey:(nullable NSString *)key;

/// Map **tường minh** keychain identity key (service/account/label) → kind
/// (serial/udid/imei/idfa/idfv/model/chip/board/wifi/bluetooth).
///
/// Cố ý KHÔNG đoán theo substring: `uuid`, `deviceid`, `did` trần trả nil vì
/// đó là định danh cấp app (không phải phần cứng) — nếu thay bằng udid thì
/// app đọc lệch với nguồn khác và tự tạo mâu thuẫn cho evaluator.
/// Nil nếu key không identity.
- (nullable NSString *)keychainIdentityKindForKey:(nullable NSString *)key;

/// Giá trị profile cho `kind` xem trên. Nil nếu kind rỗng hoặc profile thiếu.
- (nullable NSString *)keychainValueForKind:(nullable NSString *)kind;

/// optionKeychainNamespace — mọi item do app ghi/đọc đi qua prefix `mc_<tag>_`
/// trong `kSecAttrService` để mỗi profile một namespace riêng.
/// **Mặc định NO** (chưa verify trên thiết bị — xem KUAISHOU_FAKE_DEVICE_PLAN.md 4.4).
- (BOOL)keychainNamespaceEnabled;

/// Prefix namespace đầy đủ, ví dụ `mc_1a2b3c4d_`. Nil nếu tắt hoặc chưa có identity.
- (nullable NSString *)keychainNamespacePrefix;

/// Path có chứa serial/udid giả — app sniff file identity.
- (BOOL)isIdentityPath:(nullable NSString *)path;

/// So version giả với (major, minor, subminor). Dùng orig nếu không có systemVersion giả.
- (BOOL)isFakeOSVersionAtLeastMajor:(uint32_t)major minor:(uint32_t)minor patch:(uint32_t)patch
                         hasFakeVersion:(BOOL *)hasFakeVersion;

@end

NS_ASSUME_NONNULL_END
