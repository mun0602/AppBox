//
//  MCProfile.h
//  LiveContainer
//
//  Integration layer: bridge MunChanger hooks into LiveContainer.
//  Called from LCBootstrap.m after DyldHooksInit.
//

#ifndef MCProfile_h
#define MCProfile_h

#import <Foundation/Foundation.h>

/// Gọi một lần duy nhất từ LCBootstrap.m sau DyldHooksInit.
/// Đọc config từ $LC_HOME_PATH/Library/Preferences/com.mun.changer.plist
/// rồi cài toàn bộ MunChanger hooks nếu enabled.
/// Trả về YES nếu hooks được cài, NO nếu config không tìm thấy hoặc bị disabled.
BOOL MCProfileInit(void);

#endif /* MCProfile_h */
