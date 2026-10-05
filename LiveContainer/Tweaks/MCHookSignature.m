#import "MCConfig.h"
#import "MCRebind.h"

#import <Foundation/Foundation.h>

/// Phase 7: Giữ nguyên vẹn hàm ký Sig3/Sig4 của Kuaishou (atlasSign), không can thiệp làm hỏng chữ ký
typedef void *(*MCAtlasSignFn)(void *param1, void *param2, void *param3);
static MCAtlasSignFn gOrigAtlasSign;

static void *MCHookedAtlasSign(void *param1, void *param2, void *param3) {
    if (gOrigAtlasSign && gOrigAtlasSign != MCHookedAtlasSign) {
        return gOrigAtlasSign(param1, param2, param3);
    }
    return NULL;
}

void MCHookSignatureInstall(void) {
    static BOOL gHooked;
    if (gHooked) return;
    gHooked = YES;

    // Passthrough an toàn: bind nếu symbol tồn tại trong binary Kuaishou
    MCRebindSymbol("atlasSign", (void *)MCHookedAtlasSign, (void **)&gOrigAtlasSign);
}
