# MunChanger trong LiveContainer — Gap Analysis & Roadmap

> Cập nhật 2026-10-05, sau review symbol-level. Companion của `MUN_CHANGER_PORT_PLAN.md`.

## Hiện trạng

| Thành phần | Trạng thái |
|---|---|
| Hook engine (18 nhóm, `Tweaks/MCHook*.m`) | ✅ Port đủ 24/25 file source của `dylib/` |
| Catalog 154 thiết bị (`Tweaks/MCDeviceCatalog` + `MCCatalogJSON`) | ✅ Được dùng thật bởi `MCHookScreen.m:34` |
| Integration layer (`MCProfile.m` → gọi từ `LCBootstrap.m:530`) | ✅ Kill-switch `mc.disabled` + đọc plist container |
| Keychain hook (`MCHookKeychain.m`) | 🔵 Bỏ có chủ ý — LC hook SecItem với 128 group mạnh hơn. Trade-off: đổi profile không xóa identity cũ app đã cache trong keychain → dùng container mới khi đổi profile |
| Compile + symbol resolution | ✅ 27 .o sạch, 0 symbol MC unresolved |

## Còn thiếu so với MunChanger standalone

1. **UI quản lý profile** — standalone có app đầy đủ (`app/HomeViewController`, `FakeViewController`...). Trong LC phải sửa tay `com.mun.changer.plist`.
2. **Bộ sinh identity thực tế** (`app/MCRandom.m`) — serial 12 ký tự (bảng 0-9A-Z bỏ I/O), UDID 40 hex (không gạch — đúng format iOS thật), IMEI 15 số có Luhn checksum (prefix 35), Wi-Fi/BT MAC dùng Apple OUI thật, carrier từ CarrierList (name+mcc+mnc+iso), device name từ pool name.txt.
3. **Resources** — `name.txt` (26KB), `CarrierList.txt` (30KB), `AppleOUI.txt` (152B). Chưa port. Lưu ý: cách standalone load file (walk bundle/CWD) **không hoạt động** trong guest process của LC — phải embed như string constant (pattern `MCCatalogJSON.m` đã chứng minh).
4. **Seeded identity** (UDIDFaker-style: SHA256 `seed|purpose` → identity ổn định qua reboot, đổi seed = đổi toàn bộ hồ sơ) — cần port nhưng tham số hóa seed thay vì global state.

Không cần port: `daemon/`, `injector/`, `cli/`, `shims/`, `vendor/`, `tests/` — LC tự là injector, config đi qua container plist.

## Roadmap

### Phase R1 — Embed resources + port MCRandom ✅ (2026-10-05)
- `mun-changer/tools/gen_lc_resources.py`: đọc name.txt / CarrierList.txt / AppleOUI.txt → sinh `MCResourcesJSON.m` (3 string constant).
- `MCResources.h/.m`: `deviceNames` / `carrierRecords` / `appleOUIs` — parse + cache (mirror `MCLinesInFile`).
- `MCRandom.h/.m`: port từ `app/MCRandom.m`; resources từ MCResources; iOS range qua tham số; seeded API nhận seed tường minh; thêm `fillIdentityForModel:intoDictionary:...` (model cố định). Key output khớp 100% alias map của dylib `MCConfig.m` (đã đối chiếu từng accessor).
- Thêm `MCDeviceCatalog modelIdentifiersForFamily:` (sort mới nhất trước) cho UI picker.

### Phase R2 — UI trong LCAppSettingsView ✅ (2026-10-05)
- Section "Device Changer (MunChanger)" trong `LCAppSettingsView.swift`: toggle enabled, Picker 154 model (display name), hiển thị ios/build/serial/udid/carrier, nút Randomize identity + Remove profile.
- Ghi `com.mun.changer.plist` vào `containerURL/Library/Preferences/` (container đang chọn, fallback default).
- Expose qua `LiveContainerSwiftUI-Bridging-Header.h`.

### Fix hạ tầng phát hiện trong lúc làm (quan trọng)
- **`shared/` không thuộc target nào** — LiveContainerShared chỉ synchronize `Tweaks/`. Toàn bộ file MC đã chuyển từ `shared/` → `LiveContainer/Tweaks/` (thư mục shared/ bị xoá).
- **litehook submodule 404** (`LiveContainer/litehook` private/deleted) — vendor từ `opa334/litehook` + patch: header expose `gRebinds`/`gRebindCount`/`global_rebind`, TPRO helpers, thêm `litehook_find_symbol_file`; include `dyld_cache_format.h` chuyển sang `../external/include/` (header này có sẵn trong repo opa334).
- **2 include gãy trong LC chính** (không phải file MC): `dyld_bypass_validation.m` + `LCMachOUtils.m` include trần `"litehook.h"`/`"dyld_cache_format.h"` — đã chuyển sang relative path.
- **OpenSSL submodule**: vendor `OpenSSL.xcframework` từ commit LC pin (623c84d "3.3.3001 with legacy provider") của `krzyzanowskim/OpenSSL` vào `OpenSSL/Frameworks/`.
- **3 symbol private framework** (`MGCopyAnswer`, `CNCopyCurrentNetworkInfo/SupportedInterfaces`) — thêm `-Wl,-U,...` vào OTHER_LDFLAGS của LiveContainerShared (Debug+Release), theo đúng pattern LC dùng cho LSOpenConfiguration.

### Kết quả build (xcodebuild, iOS SDK 27.0, arm64, iOS 15+)
- `LiveContainerShared` — **BUILD SUCCEEDED** (38 file MC + litehook + link đầy đủ)
- `LiveContainerSwiftUI` — **BUILD SUCCEEDED** (UI Device Changer + bridging)
- Toàn app `LiveContainer` — **BUILD SUCCEEDED** (main + TweakLoader + ZSign/OpenSSL + mọi extension)

### Phase R3 — Verify trên thiết bị thật (còn lại)
- Build lại trong Xcode với signing team thật → cài lên máy.
- Test: bật profile từ UI → launch guest app → kiểm tra `sysctl hw.machine`, `MGCopyAnswer`, `[UIDevice currentDevice]` trả giá trị fake.
- Test kill-switch `mc.disabled`; test đổi profile giữa 2 container.
- Test iOS 26+ JITLess (rebind cần __DATA writable).

## Acceptance criteria
- ✅ Người dùng cuối tạo profile fake hoàn chỉnh không sửa tay plist: chọn app → App Settings → Device Changer → Generate/Randomize.
- ✅ Identity format thật: UDID 40 hex, IMEI Luhn-valid (prefix 35), MAC Apple-OUI, serial 12 ký tự (bỏ I/O), carrier/mcc/mnc/iso nhất quán từ CarrierList.
- ⏳ Đổi profile giữa 2 container không rò identity — cần test thiết bị thật.
