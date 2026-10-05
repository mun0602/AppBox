#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Truy cập resources MunChanger đã embed (MCResourcesJSON.m).
/// Trong guest process của LiveContainer không load được file từ bundle,
/// nên name.txt / CarrierList.txt / AppleOUI.txt được compile-in.
@interface MCResources : NSObject

/// Device name pool (name.txt). Rỗng nếu thiếu.
+ (NSArray<NSString *> *)deviceNames;

/// Carrier rows: name|mcc|mnc|iso (CarrierList.txt). Rỗng nếu thiếu.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)carrierRecords;

/// Apple OUI prefixes (AppleOUI.txt), uppercase. Rỗng nếu thiếu.
+ (NSArray<NSString *> *)appleOUIs;

@end

NS_ASSUME_NONNULL_END
