#import "MCConfig.h"
#import <string.h>
#import <stdio.h>
#import <uuid/uuid.h>

static NSString *const MCPrefsPath = @"/var/mobile/Library/Preferences/com.mun.changer.plist";

static BOOL MCValueIsEnabled(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value boolValue];
    }
    if (![value isKindOfClass:[NSString class]]) {
        return NO;
    }
    NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text isEqualToString:@"1"]) {
        return YES;
    }
    return [text caseInsensitiveCompare:@"YES"] == NSOrderedSame;
}

static NSString *MCCoerceString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return text.length > 0 ? text : nil;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    return nil;
}

@interface MCConfig ()
@property (nonatomic, copy, nullable) NSDictionary *root;
@property (nonatomic, readwrite, getter=isEnabled) BOOL enabled;
@end

@implementation MCConfig

+ (instancetype)sharedConfig {
    static MCConfig *config;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        config = [[MCConfig alloc] init];
    });
    return config;
}

- (BOOL)reload {
    self.root = nil;
    self.enabled = NO;

    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:MCPrefsPath];
    if (![plist isKindOfClass:[NSDictionary class]]) {
        // App sandbox (App Store) không đọc được /var/mobile/Library — thử
        // container của chính app đích (injector copy prefs vào đó).
        NSString *home = NSHomeDirectory();
        NSString *containerPrefs = [home stringByAppendingPathComponent:@"Library/Preferences/com.mun.changer.plist"];
        plist = [NSDictionary dictionaryWithContentsOfFile:containerPrefs];
    }
    if (![plist isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    self.root = plist;
    self.enabled = MCValueIsEnabled(plist[@"enabled"]);
    return YES;
}

- (nullable NSString *)stringForAliases:(NSArray<NSString *> *)aliases {
    NSDictionary *root = self.root;
    id nested = root[@"device"];
    NSDictionary *device = [nested isKindOfClass:[NSDictionary class]] ? nested : nil;

    // ApplyFake: key ngắn nằm trong dict device, alias (ProductType, …) ở root.
    for (NSString *key in aliases) {
        NSString *found = MCCoerceString(root[key]);
        if (found) {
            return found;
        }
        found = MCCoerceString(device[key]);
        if (found) {
            return found;
        }
    }
    return nil;
}

- (nullable NSString *)deviceModel {
    return [self stringForAliases:@[ @"model", @"ProductType" ]];
}

- (nullable NSString *)hwModel {
    return [self stringForAliases:@[ @"HWModelStr", @"HardwareModel", @"model" ]];
}

- (nullable NSString *)deviceName {
    return [self stringForAliases:@[ @"name", @"DeviceName" ]];
}

- (nullable NSString *)systemVersion {
    return [self stringForAliases:@[ @"systemVersion", @"ProductVersion", @"ios" ]];
}

- (nullable NSString *)carrierName {
    return [self stringForAliases:@[ @"carrier", @"carrierName" ]];
}

- (nullable NSString *)serialNumber {
    return [self stringForAliases:@[ @"serialNumber", @"Serial", @"serial" ]];
}

- (nullable NSString *)udid {
    return [self stringForAliases:@[ @"udid", @"UDID" ]];
}

- (nullable NSString *)buildVersion {
    return [self stringForAliases:@[ @"build", @"buildVersion", @"Build" ]];
}

- (nullable NSString *)isoCountryCode {
    NSString *v = [self stringForAliases:@[ @"isoCountryCode", @"iso" ]];
    if (v.length > 0) {
        return v;
    }
    return self.carrierName.length > 0 ? @"CN" : nil;
}

- (nullable NSString *)mobileCountryCode {
    NSString *v = [self stringForAliases:@[ @"mobileCountryCode", @"mcc" ]];
    if (v.length > 0) {
        return v;
    }
    return self.carrierName.length > 0 ? @"460" : nil;
}

- (nullable NSString *)mobileNetworkCode {
    NSString *v = [self stringForAliases:@[ @"mobileNetworkCode", @"mnc" ]];
    if (v.length > 0) {
        return v;
    }
    return self.carrierName.length > 0 ? @"00" : nil;
}

- (nullable NSString *)imei {
    return [self stringForAliases:@[ @"imei", @"IMEI", @"InternationalMobileEquipmentIdentity" ]];
}

- (nullable NSString *)imsi {
    return [self stringForAliases:@[ @"imsi", @"IMSI", @"InternationalMobileSubscriberIdentity" ]];
}

- (nullable NSString *)boardId {
    return [self stringForAliases:@[ @"boardId", @"BoardId", @"board" ]];
}

- (nullable NSString *)chipId {
    return [self stringForAliases:@[ @"chipId", @"ChipID", @"chip" ]];
}

- (nullable NSString *)hardwarePlatform {
    return [self stringForAliases:@[ @"hardwarePlatform", @"HardwarePlatform", @"platform" ]];
}

- (nullable NSString *)wifiAddress {
    return [self stringForAliases:@[ @"wifiAddress", @"WiFiAddress", @"wifi", @"mac" ]];
}

- (nullable NSString *)bluetoothAddress {
    return [self stringForAliases:@[ @"bluetoothAddress", @"BluetoothAddress", @"bluetooth", @"bt" ]];
}

- (nullable NSUUID *)vendorUUID {
    NSString *udid = self.udid;
    if (udid.length == 0) {
        return nil;
    }
    uuid_t bytes;
    memset(bytes, 0, sizeof(bytes));
    NSUInteger n = udid.length;
    BOOL hex = YES;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [udid characterAtIndex:i];
        BOOL ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        if (!ok) {
            hex = NO;
            break;
        }
    }
    if (hex && n >= 32) {
        static const unsigned char lut[256] = {
            ['0'] = 0, ['1'] = 1, ['2'] = 2, ['3'] = 3, ['4'] = 4, ['5'] = 5, ['6'] = 6, ['7'] = 7,
            ['8'] = 8, ['9'] = 9, ['a'] = 10, ['b'] = 11, ['c'] = 12, ['d'] = 13, ['e'] = 14, ['f'] = 15,
            ['A'] = 10, ['B'] = 11, ['C'] = 12, ['D'] = 13, ['E'] = 14, ['F'] = 15
        };
        const char *s = udid.UTF8String;
        for (int i = 0; i < 16; i++) {
            unsigned char hi = (unsigned char)s[i * 2];
            unsigned char lo = (unsigned char)s[i * 2 + 1];
            bytes[i] = (unsigned char)((lut[hi] << 4) | lut[lo]);
        }
    } else {
        NSData *data = [udid dataUsingEncoding:NSUTF8StringEncoding];
        memcpy(bytes, data.bytes, MIN((size_t)data.length, sizeof(bytes)));
    }
    return [[NSUUID alloc] initWithUUIDBytes:bytes];
}

- (nullable id)defaultsValueForKey:(nullable NSString *)key {
    if (key.length == 0) {
        return nil;
    }
    if ([key isEqualToString:@"enabled"]) {
        return @(self.enabled);
    }
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"serial": @"serial",
            @"serialNumber": @"serial",
            @"Serial": @"serial",
            @"udid": @"udid",
            @"UDID": @"udid",
            @"model": @"model",
            @"ProductType": @"model",
            @"ios": @"ios",
            @"systemVersion": @"ios",
            @"ProductVersion": @"ios",
            @"build": @"build",
            @"buildVersion": @"build",
            @"Build": @"build",
            @"name": @"name",
            @"DeviceName": @"name",
            @"carrier": @"carrier",
            @"carrierName": @"carrier",
            @"isoCountryCode": @"iso",
            @"iso": @"iso",
            @"mobileCountryCode": @"mcc",
            @"mcc": @"mcc",
            @"mobileNetworkCode": @"mnc",
            @"mnc": @"mnc",
            @"imei": @"imei",
            @"IMEI": @"imei",
            @"InternationalMobileEquipmentIdentity": @"imei",
            @"boardId": @"board",
            @"BoardId": @"board",
            @"board": @"board",
            @"chipId": @"chip",
            @"ChipID": @"chip",
            @"chip": @"chip",
            @"hardwarePlatform": @"platform",
            @"HardwarePlatform": @"platform",
            @"platform": @"platform",
            @"wifiAddress": @"wifi",
            @"WiFiAddress": @"wifi",
            @"wifi": @"wifi",
            @"mac": @"wifi",
            @"bluetoothAddress": @"bluetooth",
            @"BluetoothAddress": @"bluetooth",
            @"bluetooth": @"bluetooth",
        };
    });
    NSString *kind = map[key];
    if (!kind) {
        return nil;
    }
    if ([kind isEqualToString:@"serial"]) return self.serialNumber;
    if ([kind isEqualToString:@"udid"]) return self.udid;
    if ([kind isEqualToString:@"model"]) return self.deviceModel;
    if ([kind isEqualToString:@"ios"]) return self.systemVersion;
    if ([kind isEqualToString:@"build"]) return self.buildVersion;
    if ([kind isEqualToString:@"name"]) return self.deviceName;
    if ([kind isEqualToString:@"carrier"]) return self.carrierName;
    if ([kind isEqualToString:@"iso"]) return self.isoCountryCode;
    if ([kind isEqualToString:@"mcc"]) return self.mobileCountryCode;
    if ([kind isEqualToString:@"mnc"]) return self.mobileNetworkCode;
    if ([kind isEqualToString:@"imei"]) return self.imei;
    if ([kind isEqualToString:@"board"]) return self.boardId;
    if ([kind isEqualToString:@"chip"]) return self.chipId;
    if ([kind isEqualToString:@"platform"]) return self.hardwarePlatform;
    if ([kind isEqualToString:@"wifi"]) return self.wifiAddress;
    if ([kind isEqualToString:@"bluetooth"]) return self.bluetoothAddress;
    return nil;
}

// Chuẩn hoá key: lowercase, chỉ giữ [a-z0-9] — gom "UDID", "device_udid",
// "com.x.deviceId" về cùng dạng "deviceudid" để tra bảng alias tỉnh.
static NSString *MCNormalizeIdentityKey(NSString *key) {
    if (key.length == 0) {
        return nil;
    }
    NSMutableString *out = [NSMutableString stringWithCapacity:key.length];
    NSCharacterSet *drop = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    for (NSUInteger i = 0; i < key.length; i++) {
        unichar ch = [key characterAtIndex:i];
        if (![drop characterIsMember:ch]) {
            [out appendFormat:@"%C", ch];
        }
    }
    return [out lowercaseString];
}

- (nullable NSString *)keychainIdentityKindForKey:(nullable NSString *)key {
    NSString *n = MCNormalizeIdentityKey(key);
    if (n.length == 0) {
        return nil;
    }
    static NSDictionary<NSString *, NSString *> *exact;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exact = @{
            @"udid": @"udid",
            @"deviceudid": @"udid",
            @"hwudid": @"udid",
            @"uniqueidentifier": @"udid",
            @"serial": @"serial",
            @"serialnumber": @"serial",
            @"hwserialnumber": @"serial",
            @"imei": @"imei",
            @"internationalmobileequipmentidentity": @"imei",
            @"idfa": @"idfa",
            @"advertisingidentifier": @"idfa",
            @"idfv": @"idfv",
            @"identifierforvendor": @"idfv",
            @"model": @"model",
            @"hwmodel": @"model",
            @"producttype": @"model",
            @"chipid": @"chip",
            @"boardid": @"board",
            @"wifimac": @"wifi",
            @"macaddress": @"wifi",
            @"bluetoothaddress": @"bluetooth",
        };
    });
    NSString *kind = exact[n];
    if (kind.length > 0) {
        return kind;
    }
    // Ghép tên dài: chỉ nhận cụm có nghĩa, không nhận `uuid` trần
    // (service kiểu "...uuidCache" phải đi nguyên qua, không bị thay data).
    if ([n containsString:@"advertisingidentifier"] || [n containsString:@"idfa"]) return @"idfa";
    if ([n containsString:@"identifierforvendor"] || [n containsString:@"idfv"]) return @"idfv";
    if ([n containsString:@"internationalmobileequipmentidentity"] || [n containsString:@"imei"]) return @"imei";
    if ([n containsString:@"serialnumber"] || [n containsString:@"hwserial"]) return @"serial";
    if ([n containsString:@"uniqueidentifier"] || [n containsString:@"deviceudid"] || [n containsString:@"udid"]) return @"udid";
    if ([n containsString:@"chipid"]) return @"chip";
    if ([n containsString:@"boardid"]) return @"board";
    if ([n containsString:@"bluetoothaddress"] || [n containsString:@"bluetoothmac"]) return @"bluetooth";
    if ([n containsString:@"wifimac"] || [n containsString:@"macaddress"]) return @"wifi";
    return nil;
}

- (nullable NSString *)keychainValueForKind:(nullable NSString *)kind {
    if (kind.length == 0) {
        return nil;
    }
    if ([kind isEqualToString:@"serial"]) return self.serialNumber;
    if ([kind isEqualToString:@"udid"]) return self.udid;
    if ([kind isEqualToString:@"imei"]) return self.imei;
    if ([kind isEqualToString:@"idfa"]) return self.advertisingUUID.UUIDString;
    if ([kind isEqualToString:@"idfv"]) return self.vendorUUID.UUIDString;
    if ([kind isEqualToString:@"model"]) return self.deviceModel;
    if ([kind isEqualToString:@"chip"]) return self.chipId;
    if ([kind isEqualToString:@"board"]) return self.boardId;
    if ([kind isEqualToString:@"wifi"]) return self.wifiAddress;
    if ([kind isEqualToString:@"bluetooth"]) return self.bluetoothAddress;
    return nil;
}

- (BOOL)keychainNamespaceEnabled {
    // Gọi MCValueIsEnabled (không dùng MCBoolOption vì hàm này định nghĩa
    // ở dưới) — nil ⇒ NO ⇒ mặc định TẮT cho tới khi verify trên thiết bị.
    return MCValueIsEnabled(self.root[@"optionKeychainNamespace"]);
}

- (nullable NSString *)keychainNamespacePrefix {
    if (![self keychainNamespaceEnabled]) {
        return nil;
    }
    NSString *serial = self.serialNumber ?: @"";
    NSString *udid = self.udid ?: @"";
    NSString *model = self.deviceModel ?: @"";
    if (serial.length == 0 && udid.length == 0 && model.length == 0) {
        return nil;
    }
    // FNV-1a 32-bit trên fingerprint → tag ngắn, ổn định theo profile.
    NSString *fp = [NSString stringWithFormat:@"%@|%@|%@", serial, udid, model];
    const char *bytes = fp.UTF8String;
    if (bytes == NULL) {
        return nil;
    }
    uint32_t hash = 2166136261u;
    for (size_t i = 0; bytes[i] != '\0'; i++) {
        hash ^= (uint32_t)(unsigned char)bytes[i];
        hash *= 16777619u;
    }
    return [NSString stringWithFormat:@"mc_%08x_", hash];
}

- (BOOL)isIdentityPath:(nullable NSString *)path {
    if (path.length == 0) {
        return NO;
    }
    NSString *serial = self.serialNumber;
    NSString *udid = self.udid;
    if (serial.length >= 8 && [path containsString:serial]) {
        return YES;
    }
    if (udid.length >= 8 && [path containsString:udid]) {
        return YES;
    }
    return NO;
}

- (BOOL)isFakeOSVersionAtLeastMajor:(uint32_t)major minor:(uint32_t)minor patch:(uint32_t)patch
                         hasFakeVersion:(BOOL *)hasFakeVersion {
    NSString *ver = self.systemVersion;
    if (ver.length == 0) {
        if (hasFakeVersion) *hasFakeVersion = NO;
        return NO;
    }
    if (hasFakeVersion) *hasFakeVersion = YES;
    uint32_t a = 0, b = 0, c = 0;
    sscanf(ver.UTF8String, "%u.%u.%u", &a, &b, &c);
    if (a != major) return a > major;
    if (b != minor) return b > minor;
    return c >= patch;
}

#pragma mark - Fake mở rộng (screen/GPS/locale/sensor)

static BOOL MCBoolOption(NSDictionary *root, NSString *key) {
    return MCValueIsEnabled(root[key]);
}

static NSString *MCStringOption(NSDictionary *root, NSString *key) {
    return MCCoerceString(root[key]);
}

- (BOOL)fakeScreenEnabled {
    return MCBoolOption(self.root, @"optionFakeScreen");
}

- (BOOL)fakeGPSEnabled {
    return MCBoolOption(self.root, @"optionFakeGPS") && self.gpsLatitude != 0.0 && self.gpsLongitude != 0.0;
}

- (double)gpsLatitude {
    return [MCStringOption(self.root, @"gpsLat") doubleValue];
}

- (double)gpsLongitude {
    return [MCStringOption(self.root, @"gpsLng") doubleValue];
}

- (BOOL)fakeTimeZoneEnabled {
    return MCBoolOption(self.root, @"optionFakeTimeZone") && self.timeZoneName.length > 0;
}

- (NSString *)timeZoneName {
    return MCStringOption(self.root, @"timeZone");
}

- (BOOL)fakeLocaleEnabled {
    return MCBoolOption(self.root, @"optionFakeLocale") && self.localeIdentifier.length > 0;
}

- (NSString *)localeIdentifier {
    return MCStringOption(self.root, @"localeId");
}

- (BOOL)fakeLanguageEnabled {
    return MCBoolOption(self.root, @"optionFakeLanguage") && self.preferredLanguages.count > 0;
}

- (NSArray<NSString *> *)preferredLanguages {
    NSString *raw = MCStringOption(self.root, @"languages");
    if (raw.length == 0) return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *part in [raw componentsSeparatedByString:@","]) {
        NSString *t = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (t.length > 0) [out addObject:t];
    }
    return out.count ? out : nil;
}

- (BOOL)fakeSensorsEnabled {
    return MCBoolOption(self.root, @"optionFakeSensors");
}

#pragma mark - Kuaishou / hardware profile

static uint64_t MCUint64Option(NSDictionary *root, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id v = root[key];
        if ([v isKindOfClass:[NSNumber class]]) {
            return [(NSNumber *)v unsignedLongLongValue];
        }
        NSString *s = MCCoerceString(v);
        if (s.length > 0) {
            return strtoull(s.UTF8String, NULL, 0);
        }
        id nested = root[@"device"];
        if ([nested isKindOfClass:[NSDictionary class]]) {
            id nv = ((NSDictionary *)nested)[key];
            if ([nv isKindOfClass:[NSNumber class]]) {
                return [(NSNumber *)nv unsignedLongLongValue];
            }
            NSString *ns = MCCoerceString(nv);
            if (ns.length > 0) {
                return strtoull(ns.UTF8String, NULL, 0);
            }
        }
    }
    return 0;
}

- (uint64_t)memsizeBytes {
    return MCUint64Option(self.root, @[ @"memsize", @"hw.memsize", @"hwMemsize", @"ram" ]);
}

- (int)cpuCount {
    uint64_t n = MCUint64Option(self.root, @[ @"ncpu", @"hw.ncpu", @"cpuCount", @"cores" ]);
    return n > 0 && n < 128 ? (int)n : 0;
}

- (uint32_t)cpuFamily {
    return (uint32_t)MCUint64Option(self.root, @[ @"cpufamily", @"hw.cpufamily", @"cpuFamily" ]);
}

- (uint32_t)cpuType {
    return (uint32_t)MCUint64Option(self.root, @[ @"cputype", @"hw.cputype", @"cpuType" ]);
}

- (uint32_t)cpuSubtype {
    return (uint32_t)MCUint64Option(self.root, @[ @"cpusubtype", @"hw.cpusubtype", @"cpuSubtype" ]);
}

- (uint64_t)cpuFrequencyHz {
    return MCUint64Option(self.root, @[ @"cpufrequency", @"hw.cpufrequency", @"cpuFrequency" ]);
}

- (int64_t)boottimeSec {
    // Nested boottime: {sec, usec} hoặc flat boottimeSec.
    id bt = self.root[@"boottime"];
    if ([bt isKindOfClass:[NSDictionary class]]) {
        id sec = ((NSDictionary *)bt)[@"sec"];
        if ([sec isKindOfClass:[NSNumber class]]) return [(NSNumber *)sec longLongValue];
        NSString *s = MCCoerceString(sec);
        if (s.length) return (int64_t)strtoll(s.UTF8String, NULL, 10);
    }
    return (int64_t)MCUint64Option(self.root, @[ @"boottimeSec", @"kern.boottime", @"boottime" ]);
}

- (int32_t)boottimeUsec {
    id bt = self.root[@"boottime"];
    if ([bt isKindOfClass:[NSDictionary class]]) {
        id usec = ((NSDictionary *)bt)[@"usec"];
        if ([usec isKindOfClass:[NSNumber class]]) return [(NSNumber *)usec intValue];
        NSString *s = MCCoerceString(usec);
        if (s.length) return (int32_t)strtol(s.UTF8String, NULL, 10);
    }
    return (int32_t)MCUint64Option(self.root, @[ @"boottimeUsec" ]);
}

- (NSString *)bootSessionUUID {
    return [self stringForAliases:@[ @"bootSessionUUID", @"kern.bootsessionuuid", @"bootsessionuuid" ]];
}

- (NSString *)hostName {
    return [self stringForAliases:@[ @"hostName", @"hostname", @"kern.hostname" ]];
}

- (NSString *)darwinRelease {
    return [self stringForAliases:@[ @"darwinRelease", @"uname.release", @"Darwin" ]];
}

- (NSUUID *)advertisingUUID {
    NSString *raw = [self stringForAliases:@[ @"idfa", @"IDFA", @"advertisingIdentifier" ]];
    if (raw.length == 0) {
        // Derive ổn định từ udid nếu không có idfa riêng.
        NSUUID *v = self.vendorUUID;
        if (!v) return nil;
        uuid_t bytes;
        [v getUUIDBytes:bytes];
        bytes[0] ^= 0x5A;
        bytes[6] = (bytes[6] & 0x0F) | 0x40;
        bytes[8] = (bytes[8] & 0x3F) | 0x80;
        return [[NSUUID alloc] initWithUUIDBytes:bytes];
    }
    return [[NSUUID alloc] initWithUUIDString:raw];
}

- (NSString *)wifiSSID {
    return [self stringForAliases:@[ @"wifiSSID", @"SSID", @"ssid" ]];
}

- (NSString *)wifiBSSID {
    return [self stringForAliases:@[ @"wifiBSSID", @"BSSID", @"bssid" ]];
}

- (uint64_t)diskTotalBytes {
    return MCUint64Option(self.root, @[ @"diskTotal", @"diskTotalBytes", @"diskCapacity" ]);
}

- (uint64_t)diskFreeBytes {
    return MCUint64Option(self.root, @[ @"diskFree", @"diskFreeBytes", @"diskAvailable" ]);
}

- (BOOL)hideJailbreakEnabled {
    if (self.root[@"optionHideJB"] != nil) {
        return MCBoolOption(self.root, @"optionHideJB");
    }
    return self.enabled;
}

- (BOOL)fakeNetworkEnabled {
    if (self.root[@"optionFakeNetwork"] != nil) {
        return MCBoolOption(self.root, @"optionFakeNetwork");
    }
    return self.wifiAddress.length > 0 || self.wifiSSID.length > 0;
}

@end
