#import <Foundation/Foundation.h>

/// Symbol trong libsystem / framework, không trả bản đã interpose.
void *MCLookupRealSymbol(const char *name);

/// Gắn replacement vào mọi image đã load. originalOut nhận con trỏ cũ (có thể NULL).
BOOL MCRebindSymbol(const char *name, void *replacement, void **originalOut);

/// Con trỏ gốc đã bind trong mục __interpose của chính dylib. Không gọi dlsym.
void *MCInterposeReplacee(void *replacement);

/// Địa chỉ nằm trong ảnh hệ thống, không phải binary chính hay MunChanger.
int MCPointerInSystemImage(const void *addr);

/// Đổi mọi slot trong binary chính đang trỏ `from` sang `to`.
void MCRedirectMainImport(void *from, void *to);

/// Ghi đè slot lazy-bind của `symbol` trong binary chính. Slot chưa resolve
/// không chứa địa chỉ hàm gốc, nên so con trỏ sẽ trượt. Trang __DATA để lại RW.
void MCRedirectLazySymbol(const char *symbol, void *replacement);
