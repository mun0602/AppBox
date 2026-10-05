#import "MCRandom.h"
#import "MCDeviceCatalog.h"
#import "MCResources.h"

#import <CommonCrypto/CommonDigest.h>

static NSString * const MCSerialChars = @"0123456789ABCDEFGHJKLMNPQRSTUVWXYZ";

static NSDictionary<NSString *, NSString *> *MCRandomVersionForModel(NSString *model, NSInteger lo, NSInteger hi) {
    NSArray *vers = [MCDeviceCatalog versionsForModel:model minMajor:lo maxMajor:hi];
    if (vers.count == 0) vers = [MCDeviceCatalog versionsForModel:model];
    if (vers.count == 0) vers = [MCDeviceCatalog versionsForModel:nil];
    if (vers.count == 0) return @{ @"ios": @"26.5", @"build": @"23F77" };
    // Ưu tiên 2 major mới nhất trong list → hồ sơ trông như máy đã update.
    NSInteger maxMajor = 0;
    for (NSDictionary *v in vers) {
        NSInteger m = [[v[@"ios"] componentsSeparatedByString:@"."].firstObject integerValue];
        if (m > maxMajor) maxMajor = m;
    }
    NSMutableArray *recent = [NSMutableArray array];
    for (NSDictionary *v in vers) {
        NSInteger m = [[v[@"ios"] componentsSeparatedByString:@"."].firstObject integerValue];
        if (m >= maxMajor - 1) [recent addObject:v];
    }
    NSArray *pool = recent.count ? recent : vers;
    return pool[arc4random_uniform((uint32_t)pool.count)];
}

static NSString *MCAgentForIOS(NSString *ios) {
    NSString *ver = ios.length ? ios : @"27.0.1";
    NSString *uaOS = [ver stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSArray *parts = [ver componentsSeparatedByString:@"."];
    NSString *safari = parts.count >= 2
        ? [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]]
        : ver;
    return [NSString stringWithFormat:@"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/%@ Mobile/15E148 Safari/604.1",
            uaOS, safari];
}

static NSString *MCMACWithOUI(NSString *oui, const uint8_t tail[3]) {
    unsigned a = 0, b = 0, c = 0;
    sscanf(oui.UTF8String ?: "F0:18:98", "%x:%x:%x", &a, &b, &c);
    return [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X",
            a & 0xfe, b, c, tail[0], tail[1], tail[2]];
}

static void MCFillIdentityForModel(NSMutableDictionary *dictionary, NSString *model, NSInteger lo, NSInteger hi) {
    if (model.length > 0) dictionary[@"model"] = model;
    // ios/build/darwin/board/chip/RAM/CPU lấy cùng một hàng catalog.
    NSDictionary *ver = MCRandomVersionForModel(dictionary[@"model"], lo, hi);
    NSString *ios = ver[@"ios"] ?: @"";
    dictionary[@"ios"] = ios;
    dictionary[@"build"] = ver[@"build"];
    NSString *darwin = [MCDeviceCatalog darwinForVersion:ios];
    if (darwin.length) dictionary[@"darwinRelease"] = darwin;
    NSString *board = [MCDeviceCatalog boardForModel:dictionary[@"model"]];
    if (board.length) dictionary[@"HWModelStr"] = board;
    uint64_t ram = [MCDeviceCatalog ramBytesForModel:dictionary[@"model"]];
    if (ram > 0) dictionary[@"memsize"] = @(ram);
    NSInteger cores = [MCDeviceCatalog cpuCountForModel:dictionary[@"model"]];
    if (cores > 0) dictionary[@"ncpu"] = @(cores);
    uint32_t family = [MCDeviceCatalog cpuFamilyForModel:dictionary[@"model"]];
    if (family > 0) dictionary[@"cpufamily"] = @(family);
    uint32_t cpuType = [MCDeviceCatalog cpuTypeForModel:dictionary[@"model"]];
    if (cpuType > 0) dictionary[@"cputype"] = @(cpuType);
    uint32_t cpuSub = [MCDeviceCatalog cpuSubtypeForModel:dictionary[@"model"]];
    if (cpuSub > 0) dictionary[@"cpusubtype"] = @(cpuSub);
    // Màn hình không cần ghi vào plist — MCHookScreen tự tính từ model qua catalog.

    dictionary[@"serial"] = [MCRandom randomSerial];
    dictionary[@"udid"] = [MCRandom randomUDID];
    dictionary[@"userAgent"] = MCAgentForIOS(ios);
    dictionary[@"name"] = [MCRandom randomDeviceName];
    NSDictionary *carrier = [MCRandom randomCarrierRecord];
    dictionary[@"carrier"] = carrier[@"name"];
    dictionary[@"mcc"] = carrier[@"mcc"];
    dictionary[@"mnc"] = carrier[@"mnc"];
    dictionary[@"iso"] = carrier[@"iso"];
    dictionary[@"imei"] = [MCRandom randomIMEI];
    dictionary[@"wifiAddress"] = [MCRandom randomWiFiAddress];
    dictionary[@"bluetoothAddress"] = [MCRandom randomBluetoothAddress];
}

@implementation MCRandom

+ (NSString *)randomSerial {
    NSMutableString *serial = [NSMutableString stringWithCapacity:12];
    NSUInteger alphabet = MCSerialChars.length;
    for (NSUInteger i = 0; i < 12; i++) {
        unichar ch = [MCSerialChars characterAtIndex:arc4random_uniform((uint32_t)alphabet)];
        [serial appendFormat:@"%C", ch];
    }
    return serial;
}

+ (NSString *)randomUDID {
    uint8_t bytes[20];
    arc4random_buf(bytes, sizeof(bytes));
    NSMutableString *hex = [NSMutableString stringWithCapacity:40];
    for (size_t i = 0; i < sizeof(bytes); i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return hex;
}

+ (nullable NSString *)randomModelForFamily:(NSString *)family {
    return [MCDeviceCatalog randomModelIdentifierForFamily:family];
}

+ (NSString *)randomDeviceName {
    NSArray<NSString *> *names = [MCResources deviceNames];
    if (names.count == 0) {
        NSArray<NSString *> *fallback = @[ @"iPhone", @"My iPhone", @"iPad", @"My iPad" ];
        return fallback[arc4random_uniform((uint32_t)fallback.count)];
    }
    return names[arc4random_uniform((uint32_t)names.count)];
}

+ (NSDictionary<NSString *, NSString *> *)randomCarrierRecord {
    NSArray<NSDictionary<NSString *, NSString *> *> *rows = [MCResources carrierRecords];
    if (rows.count == 0) {
        return @{ @"name": @"Viettel", @"mcc": @"452", @"mnc": @"04", @"iso": @"vn" };
    }
    return rows[arc4random_uniform((uint32_t)rows.count)];
}

+ (NSString *)userAgentForIOS:(NSString *)ios {
    return MCAgentForIOS(ios);
}

+ (NSString *)randomIMEI {
    int digits[15];
    digits[0] = 3;
    digits[1] = 5;
    for (int i = 2; i < 14; i++) {
        digits[i] = (int)arc4random_uniform(10);
    }
    int sum = 0;
    for (int i = 0; i < 14; i++) {
        int d = digits[i];
        if (i % 2 == 1) {
            d *= 2;
            if (d > 9) d -= 9;
        }
        sum += d;
    }
    digits[14] = (10 - (sum % 10)) % 10;
    NSMutableString *s = [NSMutableString stringWithCapacity:15];
    for (int i = 0; i < 15; i++) {
        [s appendFormat:@"%d", digits[i]];
    }
    return s;
}

+ (NSString *)randomWiFiAddress {
    NSArray<NSString *> *ouis = [MCResources appleOUIs];
    NSString *oui = ouis.count ? ouis[arc4random_uniform((uint32_t)ouis.count)] : @"F0:18:98";
    uint8_t tail[3];
    arc4random_buf(tail, sizeof(tail));
    return MCMACWithOUI(oui, tail);
}

+ (NSString *)randomBluetoothAddress {
    return [self randomWiFiAddress];
}

+ (void)fillRandomIdentity:(NSMutableDictionary *)dictionary {
    [self fillRandomIdentity:dictionary minIOSMajor:0 maxIOSMajor:0];
}

+ (void)fillRandomIdentity:(NSMutableDictionary *)dictionary
                minIOSMajor:(NSInteger)minMajor
                maxIOSMajor:(NSInteger)maxMajor {
    if (![dictionary isKindOfClass:[NSMutableDictionary class]]) return;

    id current = dictionary[@"model"];
    NSString *modelText = [current isKindOfClass:[NSString class]] ? current : nil;
    BOOL iPad = [modelText.lowercaseString hasPrefix:@"ipad"];

    NSString *model = iPad ? [self randomModelForFamily:@"iPad"] : [self randomModelForFamily:@"iPhone"];
    MCFillIdentityForModel(dictionary, model ?: (modelText ?: @"iPhone12,1"), minMajor, maxMajor);
}

+ (void)fillIdentityForModel:(NSString *)model intoDictionary:(NSMutableDictionary *)dictionary {
    [self fillIdentityForModel:model intoDictionary:dictionary minIOSMajor:0 maxIOSMajor:0];
}

+ (void)fillIdentityForModel:(NSString *)model
               intoDictionary:(NSMutableDictionary *)dictionary
                 minIOSMajor:(NSInteger)minMajor
                 maxIOSMajor:(NSInteger)maxMajor {
    if (![dictionary isKindOfClass:[NSMutableDictionary class]]) return;
    MCFillIdentityForModel(dictionary, model, minMajor, maxMajor);
}

#pragma mark - Seeded

static NSString *MCSeedHex(NSString *seed, NSString *purpose) {
    NSString *payload = [NSString stringWithFormat:@"%@|%@", seed ?: @"mun", purpose ?: @""];
    NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char md[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, md);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", md[i]];
    return hex;
}

+ (NSString *)seededHex:(NSString *)seed purpose:(NSString *)purpose length:(NSUInteger)length {
    NSString *hex = MCSeedHex(seed, purpose);
    return length < hex.length ? [hex substringToIndex:length] : hex;
}

+ (NSString *)seededUDID:(NSString *)seed {
    return [self seededHex:seed purpose:@"udid" length:40];
}

+ (NSString *)seededUUID:(NSString *)seed purpose:(NSString *)purpose {
    NSString *h = [self seededHex:seed purpose:purpose length:32];
    return [NSString stringWithFormat:@"%@-%@-%@-%@-%@",
            [h substringToIndex:8],
            [h substringWithRange:NSMakeRange(8, 4)],
            [h substringWithRange:NSMakeRange(12, 4)],
            [h substringWithRange:NSMakeRange(16, 4)],
            [h substringFromIndex:20]];
}

+ (void)fillSeededIdentity:(NSMutableDictionary *)dictionary seed:(NSString *)seed {
    if (![dictionary isKindOfClass:[NSMutableDictionary class]]) return;
    dictionary[@"serial"] = [self seededHex:seed purpose:@"serial" length:12];
    dictionary[@"udid"] = [self seededUDID:seed];
    dictionary[@"imei"] = [self seededHex:seed purpose:@"imei" length:15];
    dictionary[@"idfa"] = [self seededUUID:seed purpose:@"idfa"];
    NSArray<NSString *> *ouis = [MCResources appleOUIs];
    NSString *wm = [self seededHex:seed purpose:@"wifi" length:12];
    uint8_t tail[3] = {0};
    for (int i = 0; i < 3; i++) {
        NSString *b = [wm substringWithRange:NSMakeRange((3 + i) * 2, 2)];
        tail[i] = (uint8_t)strtoul(b.UTF8String, NULL, 16);
    }
    NSUInteger idx = ouis.count ? (strtoul(wm.UTF8String, NULL, 16) % ouis.count) : 0;
    NSString *oui = ouis.count ? ouis[idx] : @"F0:18:98";
    dictionary[@"wifiAddress"] = MCMACWithOUI(oui, tail);
    // bluetoothAddress để nguyên (nếu muốn seed riêng, thêm purpose "bluetooth").
}

@end
