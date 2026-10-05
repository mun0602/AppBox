#import "MCResources.h"

// Sinh bởi mun-changer/tools/gen_lc_resources.py.
extern NSString * const MCResourceDeviceNames;
extern NSString * const MCResourceCarrierList;
extern NSString * const MCResourceAppleOUI;

static NSArray<NSString *> *MCParseLines(NSString *blob) {
    if (blob.length == 0) {
        return @[];
    }
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *raw in [blob componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *t = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length == 0 || [t hasPrefix:@"#"] || [t hasPrefix:@"//"]) {
            continue;
        }
        [lines addObject:t];
    }
    return lines;
}

@implementation MCResources

+ (NSArray<NSString *> *)deviceNames {
    static NSArray<NSString *> *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cached = MCParseLines(MCResourceDeviceNames);
    });
    return cached;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)carrierRecords {
    static NSArray<NSDictionary<NSString *, NSString *> *> *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *rows = [NSMutableArray array];
        for (NSString *line in MCParseLines(MCResourceCarrierList)) {
            NSArray<NSString *> *parts = [line componentsSeparatedByString:@"|"];
            // name|mcc|mnc|iso|tech — country ở parts[0] không dùng.
            if (parts.count < 5) {
                continue;
            }
            NSString *name = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *mcc = [parts[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *mnc = [parts[3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *iso = [[parts[4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
            if (name.length == 0 || mcc.length == 0 || mnc.length == 0) {
                continue;
            }
            [rows addObject:@{ @"name": name, @"mcc": mcc, @"mnc": mnc, @"iso": iso ?: @"" }];
        }
        cached = rows;
    });
    return cached;
}

+ (NSArray<NSString *> *)appleOUIs {
    static NSArray<NSString *> *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *ouis = [NSMutableArray array];
        for (NSString *line in MCParseLines(MCResourceAppleOUI)) {
            if (line.length >= 8) {
                [ouis addObject:line.uppercaseString];
            }
        }
        cached = ouis;
    });
    return cached;
}

@end
