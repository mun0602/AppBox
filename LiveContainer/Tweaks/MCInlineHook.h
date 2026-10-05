#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Vá 16 byte đầu hàm đích thành jump tuyệt đối tới replacement.
BOOL MCInlineHook(void *target, void *replacement);

/// Như MCInlineHook, đồng thời dựng trampoline orig (16 byte đầu + jump về target+16).
/// origOut bắt buộc. NO nếu 16 byte đầu có lệnh PC-relative hoặc không cấp được RX.
BOOL MCInlineHookOrig(void *target, void *replacement, void *_Nonnull *_Nonnull origOut);

/// Tìm mọi bản copy của `name` (kể cả symbol local trong binary chính) rồi vá.
/// Trả về số địa chỉ đã vá.
int MCInlineHookNamed(const char *name, void *replacement);

NS_ASSUME_NONNULL_END
