#import "MCDeviceCatalog.h"

NSString *MCCatalogDevicesJSON(void);
NSString *MCCatalogOSJSON(void);

static NSDictionary<NSString *, NSDictionary *> *MCDeviceMap(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [MCCatalogDevicesJSON() dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSMutableDictionary *built = [NSMutableDictionary dictionary];
        if ([parsed isKindOfClass:[NSArray class]]) {
            for (id item in (NSArray *)parsed) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                NSString *pid = item[@"productType"];
                if ([pid isKindOfClass:[NSString class]] && pid.length) built[pid] = item;
            }
        }
        map = built;
    });
    return map;
}

static NSArray<NSDictionary *> *MCReleases(void) {
    static NSArray *rows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [MCCatalogOSJSON() dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        rows = [parsed isKindOfClass:[NSArray class]] ? parsed : @[];
    });
    return rows;
}

static NSDictionary *MCRecord(NSString *model) {
    if (![model isKindOfClass:[NSString class]] || model.length == 0) return nil;
    return MCDeviceMap()[model];
}

static NSInteger MCMajorOfIOS(NSString *ios) {
    if (![ios isKindOfClass:[NSString class]] || ios.length == 0) return 0;
    return [[ios componentsSeparatedByString:@"."].firstObject integerValue];
}

static NSInteger MCChipGeneration(NSString *chip) {
    if (![chip isKindOfClass:[NSString class]] || chip.length < 2) return 0;
    if ([chip hasPrefix:@"M"]) return 99;
    if (![chip hasPrefix:@"A"]) return 0;
    NSInteger n = 0;
    for (NSUInteger i = 1; i < chip.length; i++) {
        unichar ch = [chip characterAtIndex:i];
        if (ch < '0' || ch > '9') break;
        n = n * 10 + (ch - '0');
    }
    return n;
}

static BOOL MCOutDouble(double *slot, double value) {
    if (slot) *slot = value;
    return YES;
}

@implementation MCDeviceCatalog

+ (BOOL)containsModel:(NSString *)model {
    return MCRecord(model) != nil;
}

+ (nullable NSString *)randomModelIdentifierForFamily:(NSString *)family {
    BOOL iPad = [family caseInsensitiveCompare:@"iPad"] == NSOrderedSame;
    NSString *want = iPad ? @"iPad" : @"iPhone";
    NSMutableArray<NSString *> *pool = [NSMutableArray array];
    [MCDeviceMap() enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *rec, BOOL *stop) {
        (void)stop;
        if (![rec[@"family"] isEqualToString:want]) return;
        if (![rec[@"random"] boolValue]) return;
        [pool addObject:key];
    }];
    if (pool.count == 0) return nil;
    return pool[arc4random_uniform((uint32_t)pool.count)];
}

+ (NSArray<NSString *> *)modelIdentifiersForFamily:(NSString *)family {
    BOOL iPad = [family caseInsensitiveCompare:@"iPad"] == NSOrderedSame;
    NSString *want = iPad ? @"iPad" : @"iPhone";
    NSMutableArray<NSString *> *all = [NSMutableArray array];
    [MCDeviceMap() enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *rec, BOOL *stop) {
        (void)stop;
        if ([rec[@"family"] isEqualToString:want]) [all addObject:key];
    }];
    // Sort "iPhone17,2" style: major desc, minor desc.
    NSArray<NSString *> *sorted = [all sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSArray *pa = [a componentsSeparatedByString:@","];
        NSArray *pb = [b componentsSeparatedByString:@","];
        NSInteger ma = [pa.firstObject integerValue];
        NSInteger mb = [pb.firstObject integerValue];
        if (ma != mb) return ma > mb ? NSOrderedAscending : NSOrderedDescending;
        NSInteger na = pa.count > 1 ? [pa[1] integerValue] : 0;
        NSInteger nb = pb.count > 1 ? [pb[1] integerValue] : 0;
        return na > nb ? NSOrderedAscending : (na < nb ? NSOrderedDescending : NSOrderedSame);
    }];
    return sorted;
}

+ (nullable NSString *)displayNameForModel:(NSString *)model {
    id name = MCRecord(model)[@"name"];
    return [name isKindOfClass:[NSString class]] && [(NSString *)name length] ? name : nil;
}

+ (double)screenInchesForModel:(NSString *)model {
    return [MCRecord(model)[@"inches"] doubleValue];
}

+ (nullable NSString *)subtitleForModel:(NSString *)model {
    NSDictionary *rec = MCRecord(model);
    if (!rec) return nil;
    double inches = [rec[@"inches"] doubleValue];
    NSString *inch = inches <= 0 ? @"?" : [NSString stringWithFormat:@"%.1f″", inches];
    if (inches > 0 && inches == (int)inches) {
        inch = [NSString stringWithFormat:@"%.0f″", inches];
    }
    return [NSString stringWithFormat:@"%@ · %@ · iOS %ld–%ld",
            rec[@"name"] ?: model, inch,
            (long)[rec[@"minOS"] integerValue], (long)[rec[@"maxOS"] integerValue]];
}

+ (NSInteger)minOSMajorForModel:(NSString *)model {
    return [MCRecord(model)[@"minOS"] integerValue];
}

+ (NSInteger)maxOSMajorForModel:(NSString *)model {
    return [MCRecord(model)[@"maxOS"] integerValue];
}

+ (nullable NSString *)boardForModel:(NSString *)model {
    id board = MCRecord(model)[@"board"];
    return [board isKindOfClass:[NSString class]] && [(NSString *)board length] ? board : nil;
}

+ (nullable NSString *)chipNameForModel:(NSString *)model {
    id chip = MCRecord(model)[@"chip"];
    if (![chip isKindOfClass:[NSString class]] || [(NSString *)chip length] == 0) return nil;
    if ([(NSString *)chip hasPrefix:@"Apple "]) return chip;
    return [@"Apple " stringByAppendingString:chip];
}

+ (uint64_t)ramBytesForModel:(NSString *)model {
    return [MCRecord(model)[@"ram"] unsignedLongLongValue];
}

+ (NSInteger)cpuCountForModel:(NSString *)model {
    return [MCRecord(model)[@"cores"] integerValue];
}

+ (uint32_t)cpuFamilyForModel:(NSString *)model {
    return [MCRecord(model)[@"cpuFamily"] unsignedIntValue];
}

+ (uint32_t)cpuTypeForModel:(NSString *)model {
    return MCRecord(model) ? 16777228u : 0;
}

+ (uint32_t)cpuSubtypeForModel:(NSString *)model {
    NSDictionary *rec = MCRecord(model);
    if (!rec) return 0;
    NSInteger gen = MCChipGeneration(rec[@"chip"]);
    if (gen == 0) return 0;
    return gen >= 12 ? 2u : 0u;
}

+ (BOOL)screenForModel:(NSString *)model
                  width:(double *)width
                 height:(double *)height
                  scale:(double *)scale
            nativeScale:(double *)nativeScale
             pixelWidth:(double *)pixelWidth
            pixelHeight:(double *)pixelHeight {
    NSDictionary *rec = MCRecord(model);
    NSArray *points = rec[@"points"];
    NSArray *pixels = rec[@"pixels"];
    if (![points isKindOfClass:[NSArray class]] || points.count < 2) return NO;
    if (![pixels isKindOfClass:[NSArray class]] || pixels.count < 2) return NO;
    MCOutDouble(width, [points[0] doubleValue]);
    MCOutDouble(height, [points[1] doubleValue]);
    MCOutDouble(scale, [rec[@"scale"] doubleValue]);
    double native = [rec[@"nativeScale"] doubleValue];
    if (native <= 0) native = [rec[@"scale"] doubleValue];
    MCOutDouble(nativeScale, native);
    MCOutDouble(pixelWidth, [pixels[0] doubleValue]);
    MCOutDouble(pixelHeight, [pixels[1] doubleValue]);
    return [points[0] doubleValue] > 0 && [points[1] doubleValue] > 0;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)versionsForModel:(NSString *)model {
    return [self versionsForModel:model minMajor:0 maxMajor:0];
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)versionsForModel:(NSString *)model
                                                             minMajor:(NSInteger)minMajor
                                                             maxMajor:(NSInteger)maxMajor {
    NSDictionary *rec = MCRecord(model);
    NSInteger lo = [rec[@"minOS"] integerValue];
    NSInteger hi = [rec[@"maxOS"] integerValue];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *rel in MCReleases()) {
        NSString *ios = rel[@"version"];
        NSString *build = rel[@"build"];
        if (![ios isKindOfClass:[NSString class]] || ![build isKindOfClass:[NSString class]]) continue;
        NSInteger major = MCMajorOfIOS(ios);
        if (rec) {
            if (major < lo || major > hi) continue;
        }
        if (minMajor > 0 && major < minMajor) continue;
        if (maxMajor > 0 && major > maxMajor) continue;
        [out addObject:@{ @"ios": ios, @"build": build }];
    }
    return out;
}

+ (nullable NSString *)buildForVersion:(NSString *)ios {
    if (![ios isKindOfClass:[NSString class]] || ios.length == 0) return nil;
    for (NSDictionary *rel in MCReleases()) {
        if ([ios isEqualToString:rel[@"version"]]) return rel[@"build"];
    }
    return nil;
}

+ (nullable NSString *)darwinForVersion:(NSString *)ios {
    if (![ios isKindOfClass:[NSString class]] || ios.length == 0) return nil;
    for (NSDictionary *rel in MCReleases()) {
        if ([ios isEqualToString:rel[@"version"]]) {
            id darwin = rel[@"darwin"];
            return [darwin isKindOfClass:[NSString class]] ? darwin : nil;
        }
    }
    return nil;
}

@end
