# Tiến độ tích hợp MunChanger → LiveContainer

> Log theo thời gian. Tài liệu liên quan: `MUN_CHANGER_PORT_PLAN.md` (thiết kế), `MUN_CHANGER_REMAINING.md` (gap + roadmap R1–R3), `README.md` (hướng dẫn sử dụng).

## 2026-10-04 (tối) — Port lõi + build standalone

- Build `mun-changer/build/MunChanger.dylib` standalone: 27 object, iOS SDK 27.0, arm64, ldid sign — dùng cho Phase 0 baseline.
- Copy 25 file source từ `mun-changer/dylib/` vào `LiveContainer/Tweaks/` (P0: Gestalt + Device + Version trước).
- Tạo `MCProfile.h/.m` — integration layer gọi 18 nhóm hook (bỏ Keychain — LC tự hook SecItem với 128 group).
- `Tweaks.h`: +19 declaration `MCHook*Install()` + `MCProfileInit()`.
- `LCBootstrap.m:530`: gọi `MCProfileInit()` sau `DyldHooksInit()`.
- Fix `MCHookGestalt.m`: bỏ `<sys/proc.h>` (macOS-only) → `#define P_TRACED 0x80`.
- Viết `MUN_CHANGER_PORT_PLAN.md` (11 section) + rewrite `README.md` theo hướng "app launcher + device-info changer".
- Verify compile lần 1: các file MC sạch, toàn bộ lỗi còn lại là submodule gãy (litehook/OpenSSL 404).

## 2026-10-05 (00:37–00:51) — Review symbol-level, bắt 5 bug

Lần verify trước chỉ check compile từng file, bỏ sót link. Review audit symbol-level (nm trên object files) phát hiện:

1. 🔴 **`MCMain.m` chứa `__attribute__((constructor))`** của standalone dylib — sẽ chạy ở mọi process link LiveContainerShared (kể cả UI/extensions), trước khi LC setup environment, double-install hook cùng `MCProfileInit()`, và gọi 2 symbol keychain undefined → **link fail**. Fix: viết lại MCMain.m chỉ giữ `MCLogLine`; `MCProfile.m` là entry duy nhất.
2. 🟠 **15 file hook được gọi nhưng chưa copy** (Carrier, Screen, Network, Advertising, Locale, Time, Location, Motion, Sensors, FileManager, Defaults, JBDetect, AntiDebug, Wolverine, Signature). Fix: copy đủ → 18/18 nhóm.
3. 🟠 `Tweaks.h` khai báo `void MCProfileInit` mâu thuẫn `BOOL` + sai tên `MCHookMissingAPIInstall` (đúng: `MCMissingAPIInstall`). Fix cả hai.
4. 🟡 README claim `mc.disabled` kill-switch nhưng code không có. Fix: implement trong `MCProfile.m` (check `NSHomeDirectory()/mc.disabled` trước khi đọc config).
5. 🟡 README claim UI "Changer Profile" + `randomizeOnLaunch` không tồn tại. Fix README trung thực.

Kết quả review: 30 object compile sạch + **0 symbol MC unresolved** (nm audit).

## 2026-10-05 (00:51–01:25) — Gap analysis → R1 + R2 + hạ tầng → FULL BUILD

### Gap vs MunChanger standalone
Thiếu: UI quản lý profile (app/), bộ sinh identity thực tế (MCRandom + resources), keychain reset (bỏ có chủ ý). Không cần port: daemon/injector/cli (LC tự là injector).

### Phase R1 — Resources + Generator
- `mun-changer/tools/gen_lc_resources.py` → sinh `MCResourcesJSON.m` (name.txt 26KB + CarrierList 30KB + AppleOUI 152B embed thành string constant — guest process không đọc được bundle file nên phải compile-in).
- `MCResources.h/.m` — parse + cache 3 resource.
- `MCRandom.h/.m` — port từ `app/MCRandom.m`: serial 12 ký tự (bảng bỏ I/O), UDID 40-hex không gạch (format iOS thật), IMEI 15 số prefix 35 + Luhn checksum, MAC Apple-OUI thật (unicast), carrier name+mcc+mnc+iso từ CarrierList, seeded SHA256 (`seed|purpose`) ổn định qua reboot, `fillIdentityForModel:intoDictionary:` cho model cố định. Key output đối chiếu khớp 100% alias map của dylib `MCConfig.m`.
- `MCDeviceCatalog +modelIdentifiersForFamily:` — list cho UI picker, sort mới nhất trước.

### Fix hạ tầng (phát hiện trong lúc làm R2)
- 🔴 **`shared/` (repo-root) không thuộc target nào** — LiveContainerShared chỉ synchronize `Tweaks/`. Chuyển 8 file MC từ `shared/` → `LiveContainer/Tweaks/`, xoá thư mục rỗng. (Giả định "không cần sửa pbxproj vì shared/ auto-include" trong plan cũ là SAI — may là Tweaks/ đúng.)
- 🔴 **litehook submodule 404** (`LiveContainer/litehook` private/deleted; api.github.com bị chặn từ mạng này). Vendor từ `opa334/litehook` (MIT, fork gốc) + patch: header expose `gRebinds`/`gRebindCount`/`global_rebind` + TPRO helpers (`os_tpro_is_supported`, `os_thread_self_restrict_tpro_to_rw/ro`), thêm `litehook_find_symbol_file` (alias `litehook_find_symbol`), include `dyld_cache_format.h` → `../external/include/` (header có sẵn trong repo opa334).
- Fix 2 include gãy sẵn của LC (không phải file MC): `dyld_bypass_validation.m:18` + `LCMachOUtils.m:6` → relative path.
- 🔴 **OpenSSL submodule** — vendor `OpenSSL.xcframework` (99MB) đúng commit LC pin `623c84d` ("3.3.3001 with legacy provider") của `krzyzanowskim/OpenSSL` → `OpenSSL/Frameworks/`.
- 🟠 3 symbol private framework (`MGCopyAnswer`, `CNCopyCurrentNetworkInfo/SupportedInterfaces`) không resolve khi link LiveContainerShared → thêm `-Wl,-U,...` vào OTHER_LDFLAGS (Debug+Release) theo đúng pattern LC dùng cho LSOpenConfiguration.

### Phase R2 — UI Device Changer
- `LCAppSettingsView.swift`: section "Device Changer (MunChanger)" — Generate fake device profile → Picker 154 model (display name, mới nhất trước) → Toggle enabled → hiển thị ios/build/serial/udid/carrier → Randomize identity → Remove profile.
- Ghi `com.mun.changer.plist` vào `containerURL/Library/Preferences/` (container đang chọn, fallback default) — đúng path mà `MCConfig.m` fallback đọc trong guest process.
- Expose `MCRandom.h` + `MCDeviceCatalog.h` qua `LiveContainerSwiftUI-Bridging-Header.h`.
- Fix Swift-ObjC rename collision (2 overload `fillRandomIdentity`/`fillIdentityForModel` bị importer gộp) → đổi selector thành `fillIdentityForModel:intoDictionary:`.

### Kết quả build cuối (xcodebuild CLI, iPhoneOS 27.0 SDK, arm64, iOS 15+, signing off)
```
LiveContainerShared   → BUILD SUCCEEDED  (38 file MC + litehook + link đầy đủ)
LiveContainerSwiftUI  → BUILD SUCCEEDED  (UI Device Changer + bridging)
LiveContainer (full)  → BUILD SUCCEEDED  (main + TweakLoader + ZSign/OpenSSL + mọi extension)
```

## Số liệu tổng
- File MC trong `LiveContainer/Tweaks/`: 38 (18 hook + Config/Profile/Rebind/Swizzle/InlineHook/Main/MissingAPI + Catalog×2 + Resources×2 + MCRandom×2 + headers).
- File LC có sẵn sửa: `Tweaks.h`, `LCBootstrap.m`, `LCAppSettingsView.swift`, `LiveContainerSwiftUI-Bridging-Header.h`, `dyld_bypass_validation.m`, `LCMachOUtils.m`, `project.pbxproj` (OTHER_LDFLAGS).
- Vendor: `litehook/` (opa334 + patch), `OpenSSL/Frameworks/` (99MB xcframework).
- Doc: `README.md`, `MUN_CHANGER_PORT_PLAN.md`, `MUN_CHANGER_REMAINING.md`, file này.

## Còn lại — Phase R3 (cần thiết bị thật)
1. Mở Xcode → set `DEVELOPMENT_TEAM` trong `xcconfigs/Global.xcconfig` → build & cài lên iPhone.
2. Test runtime: bật profile từ UI → guest app đọc `sysctl hw.machine` / `MGCopyAnswer` / `[UIDevice currentDevice]` thấy giá trị fake.
3. Test kill-switch `mc.disabled`; test 2 container 2 identity; test đổi profile.
4. Test iOS 26+ JITLess (rebind cần __DATA writable — chưa verify).

## 2026-10-05 (01:45) — Đổi thương hiệu LiveContainer → mun container

### Đổi (branding + identifier)
- Display name: `Resources/Info.plist` (CFBundleDisplayName + CFBundleName) + `INFOPLIST_KEY_CFBundleDisplayName` trong pbxproj → "mun container".
- Bundle ID: `com.kdt.livecontainer` → `com.mun.container` (Global.xcconfig, pbxproj 3 target, entitlements.xml + entitlements.catalyst.xml + LiveProcess.entitlements — gồm 128 keychain access group `.shared.*`, Resources/Info.plist + LiveProcess/Info.plist URLName).
- Code refs bundle ID: `LCUtils.m` (LiveProcess guess, `Apps/com.mun.container/App.app`, sibling export `com.mun.%@`), `SecItem.m`, `LCJITLessDiagnoseView.swift`, `LCSettingsView.swift` (kSecAttrService).
- Chuỗi UI "LiveContainer" → "mun container": LCUtilsExtensions (8 msg JIT), LCBootstrap.m, LCSharedUtils.m, LCUtils.m, LCAppInfo.m (web clip), TweakLoader alert titles ×5, LaunchAppExtension ×3, SideStore.swift ×2, ShareExtensionViews nav title, LCMultiLCManagementView (display name chính), LCDataManagementView.
- `Localizable.xcstrings`: 583 value đa ngôn ngữ (chỉ value, key giữ nguyên để không phá `.loc` lookup).
- README.md: retitle + rewrite section Installation (build từ source, bỏ link download upstream) + ghi chú fork.

### Giữ nguyên CÓ CHỦ Ý (protocol/storage — đổi sẽ phá chức năng)
- URL scheme `livecontainer://`, `livecontainer2://`, `livecontainer3://` (StikDebug/guest app/web clip đang dùng).
- Thư mục data trong app group: `LiveContainer/Data/Application/...`, `Apps/com.SideStore.../App.app`.
- Preference keys: `hideLiveContainer`, `PrimaryLiveContainerTeamId`.
- Sibling LC naming (LiveContainer2/3) — scheme sinh từ lowercase tên, đổi tên sẽ sinh scheme chứa space.
- Tên target/thư mục (LiveContainer, LiveContainerSwiftUI, ...) — sửa pbxproj đại trà rủi ro cao, không nhìn thấy bởi user.
- Icon app: chưa thay asset (cần icon mới "mun container").

## 2026-10-05 (01:57–02:25) — Việt hóa + Remote API + fix TrollStore signing

### Việt hóa
- Upstream đã có 327/335 key vi; dịch nốt 8 key thiếu + thêm 20 key mới (en+vi): MunChanger UI (9), JIT msgs (8), bootstrap/utils (4).
- Chuyển ~20 chuỗi hardcode sang `.loc`: LCAppSettingsView (MunChanger section), LCUtilsExtensions (8 JIT), LCBootstrap (2), LCUtils (1), LCSharedUtils (1), LCAppInfo (web clip).
- Rebrand sót: 39 file `*.lproj/InfoPlist.strings` còn `CFBundleName=LiveContainer` → "mun container".

### Remote API (mới) — `LiveContainerSwiftUI/Utilities/MCRemoteAPI.swift`
- HTTP server Network.framework (NWListener), port mặc định 8642, token auth (X-Mun-Token / ?token=).
- Endpoints: GET /api/status, /api/apps; POST /api/launch, /api/install (url IPA); GET/POST /api/mc, /api/mc/randomize, /api/mc/remove (quản lý MunChanger profile từng app).
- Settings: section "API điều khiển từ xa" — toggle, port, token + copy, trạng thái; autostart trong App.init khi enabled.
- File mới tự vào target nhờ PBXFileSystemSynchronizedRootGroup.
- Diag: ghi `~/Documents/mcapi.log` khi start/failed (không log token).

### Bài học TrollStore trên máy này (iPhone 8, iOS 16.7.15, Dopamine rootless)
- IPA ký ldid sẵn → install lỗi 179. **IPA phải để binary chính UNsigned** (TrollStore tự ký App-Store-code-directory + TeamID TROLLTROLL).
- Muốn entitlement tùy ý: ký TRƯỚC binary chính với app-identifier `TROLLTROLL.com.mun.container` → TrollStore giữ nguyên khi cài → hết cảnh báo "bundle ID does not match application-identifier".
- Re-sign binary đã cài bằng ldid -S → phá cấu trúc signature đặc biệt → SIGSEGV tại launch. Đừng làm.
- **cfprefsd cache**: ghi plist sau lưng cfprefsd (dù đúng container path) bị bỏ qua — phải `killall -9 cfprefsd` sau khi ghi, trước khi launch app.
- Prefs của app TrollStore nằm ở `<data-container>/Library/Preferences/`, KHÔNG phải `/var/mobile/Library/Preferences/`.

### Kết quả test thực tế (qua iproxy 8642)
- 401 đúng khi sai token; /api/status, /api/apps, index OK. Server tự khởi động cùng app (prefs enabled=true).

## 2026-10-05 (02:27) — Đổi ngôn ngữ trong app

- `Localization.m`: thêm `+lcStringsBundle` — đọc key `MCLanguageOverride` từ UserDefaults, trỏ lookup `.loc` sang `<lang>.lproj` tương ứng trong main bundle ("system"/rỗng = theo iOS). Chỉ override lookup chuỗi, KHÔNG swap `lcMainBundle` (vì nó còn dùng cho dlopen framework + bundle ID). Đổi `value:@""` → `value:self` để key thiếu fallback sang enBundle thay vì trả rỗng.
- `LCSettingsView`: section "Ngôn ngữ" — Picker dynamic liệt kê mọi ngôn ngữ có trong app (41 lproj, tên hiển thị bằng `Locale.localizedString(forIdentifier:)`), tiếng Việt đứng đầu; footer chú thích cần mở lại app cho các màn hình đã mở.
- Keys en+vi: lc.settings.language / languageSystem / languageFooter.
- Lưu ý: `lcMainBundle` được ShareExtension override riêng — không ảnh hưởng.

### Fix "đổi ngôn ngữ không ăn" (02:33)
- Nguyên nhân: UI SwiftUI dùng `.loc` **riêng** trong `Shared.swift` (`NSLocalizedString` = theo ngôn ngữ hệ thống) — bản vá `Localization.m` chỉ tác động phía ObjC (TweakLoader/LCBootstrap).
- Fix: `Shared.swift` thêm `overrideStringsBundle()` (cache Bundle theo mã ngôn ngữ) — `.loc` tra từ bundle override khi có `MCLanguageOverride`. Picker trong Settings giờ đổi tiếng ngay trên màn hình đó; các tab khác tươi lại khi điều hướng.

### Mặc định tiếng Việt (02:35)
- `Shared.swift` + `Localization.m`: khi `MCLanguageOverride` chưa set → dùng "vi" (tiếng Việt mặc định). "system" = theo hệ thống (tùy chọn vẫn còn trong picker).
- Picker trong Settings mặc định chọn "Tiếng Việt".

### Cài IPA/TIPA từ file trong máy (02:44)
- Màn Nguồn (Sources): nút toolbar "Cài IPA/TIPA từ file trong máy" — fileImporter (.ipa/.tipa) → đẩy qua `livecontainer://install?url=file://...` → tái dùng `installFromUrl` (đã hỗ trợ file URL + security-scoped bookmark sẵn của LC).
- Key en+vi: lc.sources.installLocalFile.

### Quét mã QR cài app (02:54)
- `MCQRScannerView.swift` (mới): scanner AVFoundation (AVCaptureMetadataOutput, .qr) — chạy được cả A11/iPhone 8 (DataScannerViewController cần A12+ nên không dùng).
- Màn Nguồn: nút toolbar "Quét mã QR"; menu + của tab Apps: "Cài từ mã QR". Quét URL http/https/file → đẩy qua `livecontainer://install?url=...` → pipeline install sẵn.
- Keys en+vi: lc.sources.scanQr, scanQrInvalid, scanQrCameraError, lc.appList.installFromQr.
- Lưu ý: lần đầu quét iOS hỏi quyền camera (NSCameraUsageDescription có sẵn trong Info.plist).

## 2026-10-05 (02:55–03:07) — Cài qua API + fix guest mode

### Kết quả test full loop (trên máy thật)
- POST /api/install WeChat (IPA từ LAN 192.168.1.180:8765) → vào danh sách app ~25s.
- POST /api/mc/randomize TRƯỚC lần launch đầu → tạo profile giả chuẩn format (UDID 40-hex, IMEI prefix 35, carrier thật).
- POST /api/launch → WeChat chạy trong LC.
- GET /api/status trong guest mode → server vẫn sống, token đúng.

### 3 bug fix
1. **Server chết ở guest mode**: autostart chỉ chạy trong SwiftUI App.init (UI mode). Fix: `@_cdecl("MCMaybeStartRemoteAPI")` export từ framework, LCBootstrap dlopen + gọi ở mọi mode (trừ LiveProcess).
2. **Token sai ở guest mode**: LC swap domain NSUserDefaults sang guest → token sinh lại. Fix: cache token + prime cache tại bootstrap (trước swap).
3. **mc/randomize fail trước launch đầu**: containers rỗng + dataUUID nil. Fix: `ensureContainer` mirror logic `LCAppModel.runApp` (tạo LCContainer + LCContainerInfo.plist + dataUUID).

### Vận hành
- IPAs cũ đã lưu vào `/var/mobile/old-ipas/` trên máy — tránh cài nhầm bản cũ qua TrollStore (đã случ: 03:00 cài đè bản cũ làm mất fix).
- `/var/mobile/deploy4.sh <tên-ipa>` trên máy = script deploy chuẩn (uninstall → install → inject prefs → kill cfprefsd → launch).

## 2026-10-05 (03:23–03:45) — FIX TẦNG REBIND, verify thật qua AppFake

### Chẩn đoán (dựa test thật, không đoán)
1. Report đầu tiên lấy nhầm từ AppFake STANDALONE (TrollStore cài trực tiếp, chạy ngoài LC, giữ port 18080) — mọi kết luận "rebind hỏng" trước đó phải kiểm lại.
2. Trong LC, MCProfileInit gọi ở bootstrap dòng 531 — TRƯỚC khi guest bundle load (dòng 626) → interpose trượt guest.
3. `dyld_dynamic_interpose` trên dyld4/iOS16 gọi được nhưng KHÔNG viết lại GOT.
4. MCConfig.read: fallback đúng guest home, nhưng deploy/uninstall xoá profile (data container không được backup).

### Fix (4 tầng)
1. **MCRebindSymbol → litehook**: dlsym `litehook_rebind_symbol` (LC đã link, chạy được cả jailed iOS 16+; global rebind qua gRebinds/Dyld.m áp cả image load sau). Kết quả log: `method=1` cho toàn bộ sysctl/uname/getifaddrs/dlsym/syscall…
2. **MCProfileInit chuyển xuống sau `[appBundle load]`**, trước khi guest main chạy.
3. Deploy script backup/restore cả `Documents/Data` (data container chứa profile).
4. MCRebindDebug ghi `$HOME/mcdebug.log` (chẩn đoán quay lại được bất cứ lúc nào).

### Verify thật (AppFake /info trong guest, iPhone 8 thật)
| Trường | Trước | Sau |
|---|---|---|
| uname.machine | iPhone10,1 | **iPhone15,2** |
| raw_productType / hwmodel | iPhone10,1 / D20AP | **iPhone15,2 / D73AP** |
| OS / build | 16.7.15 thật | **26.5.2 / 23E261** (đồng bộ UIDevice + processInfo) |
| deviceName / IDFV / carrier | thật | **"Journey Briella" / sinh từ UDID giả / carrier giả** |

### Còn lại (đã biết, chưa fix trong phiên này)
- `mobilegestalt` trả null toàn bộ (hook MGCopyAnswer có rebind nhưng trả nil — cần xem alias map).
- `ifaddrs_mac` còn 02:00:… (hook getifaddrs đã rebind; profile thiếu `wifiAddress` hoặc hook thụ động).
- Màn hình guest không đổi theo model (375x667 thật) — MCHookScreen cần profile có kích thước theo model.
- Vận hành: máy hay bị cài lại qua TrollStore UI giữa chừng (mất data container + prefs) — khi test dùng `sudo sh /var/mobile/deploy5.sh <ipa>` là đủ.
