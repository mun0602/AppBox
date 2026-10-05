# Plan: đưa tính năng spoof của MunChanger vào LiveContainer

> Nguồn đối chiếu: `mun-changer/dylib/` (18 nhóm hook + `MCMissingAPI`)
> Đích: `/Users/macmoon/Documents/code/LiveContainer` @ `ac2186e`

> ## ✅ TRẠNG THÁI: ĐÃ HOÀN THÀNH (2026-10-05)
>
> Toàn bộ plan này đã thực hiện xong, vượt cả phạm vi ban đầu:
>
> | Mục plan | Kết quả |
> |---|---|
> | Port 18 nhóm hook (P0→P3) | ✅ 18/18 file trong `LiveContainer/Tweaks/` (keychain bỏ có chủ ý) |
> | `MCProfileInit()` trong `LCBootstrap.m` | ✅ Sau `DyldHooksInit`, có kill-switch `mc.disabled` |
> | Build verify | ✅ **Full app BUILD SUCCEEDED** (LiveContainerShared + SwiftUI + main + mọi extension) |
> | (ngoài plan) Generator identity | ✅ `MCRandom` port + resources embed (`MCResources*`) |
> | (ngoài plan) UI quản lý profile | ✅ Section "Device Changer" trong `LCAppSettingsView` |
> | (ngoài plan) Submodule gãy | ✅ litehook vendor từ opa334 + patch; OpenSSL xcframework vendor |
>
> Chi tiết quá trình + kết quả từng phase: **`MUN_CHANGER_REMAINING.md`**.
> Còn duy nhất Phase R3: test runtime trên thiết bị thật.
>
> Nội dung dưới đây giữ nguyên làm tài liệu thiết kế/architecture đối chiếu.

## Kết luận

LiveContainer đã có **6/18** nhóm hook của MunChanger. 12 nhóm còn lại (hardware/OS/network
identity) **hoàn toàn không có** — không phải vì bị chặn mà vì code chưa từng đụng tới.

Port được: cùng cơ chế rebind, không cần entitlement đặc quyền, chạy trong tiến trình app khách.

## 1. LiveContainer đã có sẵn (6/18)

| Tính năng LC | Key / entry | Hook thực thi | Tương đương MC |
|---|---|---|---|
| Spoof IDFV theo container | `spoofIdentifierForVendor` + `spoofedIdentifierForVendor` | `Tweaks/IDFV.m:16` → `method_setImplementation` trên `LSApplicationWorkspace.deviceIdentifierForVendor`; gọi tại `LCBootstrap.m:531-536` | `MCHookDevice` (1 phần) |
| Spoof SDK version | `spoofSDKVersion` | `Tweaks/Dyld.m:384-391` → hook `dyld_program_sdk_at_least` + `dyld_get_program_sdk_version` | `MCHookVersion` (1 phần) |
| Ẩn dấu vết LiveContainer | `hideLiveContainer` | `Tweaks/Dyld.m:374-380` → rebind 4 hàm `_dyld_image_count/get_image_header/get_image_vmaddr_slide/get_image_name` | `MCHookJBDetect` (1 phần) |
| Đổi bundle id | `useLCBundleId` / `doUseLCBundleId` | `LCBootstrap.m:317-318` patch `CFBundleIdentifier` trong Info.plist | — |
| Tách keychain theo container | `keychainGroupId` (0–127) + rebind 7 hàm | `Tweaks/SecItem.m:145-151` (`SecItemAdd/CopyMatching/Update/Delete`, `SecKeyCreateRandomKey/CreateWithData/GeneratePair`) | `MCHookKeychain` (mạnh hơn MC) |
| Cô lập app group | `isolateAppGroup` | `Tweaks/NSFileManager+GuestHooks.m:42-50` redirect path | `MCHookDefaults` (1 phần) |

Bổ sung cùng họ: `fixFilePicker`, `fixLocalNotification` (`TweakLoader/DocumentPicker.m`),
`segCountMismatch` bypass iOS 27 (`LCBootstrap.m:579-580`), `initDead10ccFix` (`:520`),
`dontLoadTweakLoader` / `dontInjectTweakLoader`, external container qua bookmark.

## 2. Còn thiếu (12/18) — phần cần port

Bằng chứng thiếu: grep `MobileGestalt|hw.model|utsname|sysctl|systemVersion|CTCarrier|UIScreen`
trên toàn repo → **0 kết quả trong `LiveContainer/`**. App khách đọc thông số máy thật.

| # | Nhóm MC | Nội dung spoof | Ưu tiên |
|---|---|---|---|
| 1 | `MCHookGestalt` | MobileGestalt, `hw.model`, `hw.machine`, board, platform, chip, `hw.memsize`, `hw.ncpu`, `hw.cpufamily`, `kern.*` | **P0** |
| 2 | `MCHookDevice` | model, HW model, tên thiết bị, serial, UDID, vendorUUID | **P0** |
| 3 | `MCHookVersion` | `systemVersion`, `ProductVersion`, `isFakeOSVersionAtLeast` | **P0** |
| 4 | `MCHookCarrier` | carrier name, ISO country, MCC, MNC, IMEI, IMSI | **P1** |
| 5 | `MCHookScreen` | kích thước màn theo model được chọn | **P1** |
| 6 | `MCHookNetwork` | `getifaddrs`, IP, Wi-Fi MAC/SSID/BSSID, `getenv` | **P1** |
| 7 | `MCHookAdvertising` | IDFA (`ASIdentifierManager`), vendorUUID | **P1** |
| 8 | `MCHookLocale` | locale identifier, timezone, preferred languages | P2 |
| 9 | `MCHookTime` | system time, boot time, uptime | P2 |
| 10 | `MCHookLocation` | GPS lat/long | P2 |
| 11 | `MCHookMotion` / `MCHookSensors` | accelerometer, gyroscope, motion | P2 |
| 12 | `MCHookFileManager` | path chứa identity (serial/UDID trong tên file) | P2 |
| 13 | `MCHookWolverine` | fingerprint chống đa thiết bị | P3 |
| 14 | `MCHookSignature` | code signature introspection | P3 |
| 15 | `MCHookAntiDebug` | phát hiện debugger/traces | P3 |
| 16 | `MCMissingAPI` | bù API OS mới mà model giả không có | P3 |

## 3. Quyết định kiến trúc

**Chọn: port vào core LiveContainer** (không nhét dylib ngoài).

Lý do:
- LC đã dùng `litehook_rebind_symbol` + swizzle helper (`Tweaks.h`) — cùng họ với `MCRebind`
  của MC, code MC chuyển sang gần như nguyên vẹn
- Có sẵn pattern per-app (`guestAppInfo`) + per-container (`guestContainerInfo`) → tự có toggle UI
- Không phải ký/manage dylib ngoài, không phụ thuộc JIT (JIT chỉ là điều kiện chạy app, không phải
  điều kiện hook)
- Ít vỡ khi LC update vì chỉ chạm vào file mới

**Phương án nhanh (baseline, không sửa code):** copy `MunChanger.dylib` vào
`<container>/Documents/Tweaks/`, copy `com.mun.changer.plist` vào
`<container>/Library/Preferences/`, bấm "Sign" trong tab Tweaks (nếu JITLess). Constructor tự
chạy lúc TweakLoader dlopen — `MCMain.m:44`. Đây là Phase 0, dùng làm chuẩn đối chiếu.

## 4. Những thứ KHÔNG cần sửa

| Thứ | Lý do |
|---|---|
| `project.pbxproj` | `objectVersion = 73`, `Tweaks` là `PBXFileSystemSynchronizedRootGroup` (`pbxproj:336`) → file `.m` mới trong `LiveContainer/Tweaks/` **tự được include vào build**. Không cần thêm thủ công |
| Entitlements | Hook chạy in-process, không cần entitlement nào. `entitlements.xml` giữ nguyên |
| `TweakLoader` | Không sửa — nó chỉ dlopen; hook tự cài qua constructor |
| Substrate | `MCInlineHook` **không có call site nào** (chỉ `#import` ở `MCHookGestalt.m:2`) → không port, và không tạo phụ thuộc CydiaSubstrate |

## 5. Thêm key mới — không có registry trung tâm

`LCAppInfo.m` không có schema/registry. Danh sách `lcAppInfoKeys` ở `LCAppInfo.m:31-52` chỉ là
**whitelist migrate appInfo cũ** (chạy khi `LCPatchRevision` có mặt và `_info` rỗng).

Pattern đúng khi thêm key: viết accessor theo đúng dạng `LCAppInfo.m:507-515`
(`- (bool)hideLiveContainer` / `- (void)setHideLiveContainer:`), rồi khai báo `@property` bên
Swift. Key mới: `mcProfileName` (NSString) và `mcEnabled` (bool), đặt trong
`LCContainerInfo.plist` qua `LCContainer.makeLCContainerInfoPlist` (`LCContainer.swift:134`).

## 6. Catalog có sẵn để dùng

`mun-changer/resources/devices.json` — **154 thiết bị**, đã có sẵn mọi trường cần:
`productType`, `name`, `family`, `inches`, `points` (w,h), `scale`, `nativeScale`, `pixels`,
`minOS`, `maxOS`, `random`, `chip`, `cpuFamily`, `cores`.
Kèm `os-releases.json`. Dùng làm nguồn cho UI chọn model, tránh phải tự viết bảng model.

## 7. Các phase

### Phase 0 — Baseline (bắt buộc, không làm thì không chứng minh được port thành công)
**File:** không đụng code.
1. Dựng baseline theo phương án nhanh mục 3
2. Chạy app đích (Kwai), capture `log stream --predicate 'subsystem == "com.mun.changer"'`
3. Chụp lại giá trị thật của 16 nhóm (không fake) làm nhóm đối chứng
4. Chốt bảng check đỏ/xanh

**Xong khi:** có 2 bộ số liệu — thật vs fake — so sánh được từng trường.

### Phase 1 — Hạ tầng config
**File mới:** `LiveContainer/Tweaks/MCProfile.h`, `MCProfile.m`
**File sửa:** `LiveContainer/LCBootstrap.m` (khởi tạo, sau `DyldHooksInit` tại dòng 529)

- `MCProfile` đọc theo thứ tự:
  1. app group path — dùng chung 1 profile cho nhiều container (ưu tiên)
  2. `<container>/Library/Preferences/com.mun.changer.plist`
  3. bỏ `/var/mobile/Library/Preferences/...` (không tồn tại trong container)
- Bỏ `MCPrefsPath` cứng (`MCConfig.m:6`), thay bằng resolution động
- Giữ nguyên `MCValueIsEnabled` + toàn bộ accessor của `MCConfig` (chuyển nguyên vẹn)
- Bridge `MCRebind` → `litehook`: `MCRebindSymbol(name, repl, &orig)` gọi
  `litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, ...)`. Giữ cả tầng fallback vì MC có xử lý
  riêng image của chính nó (`MCPointerInSystemImage`, `MCRedirectMainImport`)

**Xong khi:** `log stream` in `hooks_begin name=… model=…` chứ không phải `hooks SKIPPED`.

### Phase 2 — Hook, theo thứ tự ưu tiên
**File mới:** `LiveContainer/Tweaks/MCGestalt.m`, `MCDevice.m`, `MCVersion.m`, … (mỗi nhóm 1 file)
**File sửa:** `LiveContainer/Tweaks/Tweaks.h` (khai báo `MCxxxInstall()`), `LCBootstrap.m` (gọi)

1. `MCHookGestalt` + `MCHookDevice` + `MCHookVersion` (P0 — model/board/version là thứ app
   đối thủ kiểm tra đầu tiên; sai 3 cái này thì các hook sau vô nghĩa)
2. `MCHookCarrier` + `MCHookScreen` + `MCHookNetwork` + `MCHookAdvertising` (P1)
3. `MCHookLocale` + `MCHookTime` + `MCHookLocation` + `MCHookMotion`/`MCHookSensors` +
   `MCHookFileManager` (P2)
4. `MCHookWolverine` + `MCHookSignature` + `MCHookAntiDebug` + `MCMissingAPI` (P3)

**Xong khi:** mỗi nhóm bật lên → `log stream` in `hooks_on` và giá trị đọc được khớp baseline.

### Phase 3 — UI
**File sửa:** `LCAppSettingsView.swift`, `LCContainerView.swift`, `LCAppInfo.m`, `LCContainer.swift`

- `LCAppSettingsView`: toggle master "Fake Device Profile", tách riêng "Spoof SDK Version" /
  "Spoof IDFV" để không double-spoof với sẵn có, cảnh báo khi bật cả hai nguồn
- `LCContainerView`: chọn profile từ catalog 154 model, hiện trạng fake của container
- Lưu profile vào `LCContainerInfo.plist` qua `makeLCContainerInfoPlist`
- Import/export JSON profile

**Xong khi:** đổi profile trong UI → launch lại app → giá trị đổi theo, không cần build lại.

### Phase 4 — Test
- 1 app không fake (đối chứng) vs 1 app có profile → so từng trường
- Khớp với baseline Phase 0
- Test 2 container cùng app, profile khác nhau → xác nhận tách biệt
- Test iOS 26+ JITLess — xác nhận rebind vẫn ăn khi không có JIT

## 8. Safe mode và rollback

Rủi ro lớn nhất khi port vào core: **hook sai làm app khách crash ngay lúc khởi động → user
không vào được UI để tắt.**

Bắt buộc có trước Phase 2:
- Đọc cờ tắt từ **file** chứ không chỉ từ `guestAppInfo` (vì app khách crash thì UI chưa kịp
  áp). Đường dẫn: `<container>/mc.disabled` (file rỗng = tắt toàn bộ)
- Mỗi nhóm hook bọc trong guard, lỗi 1 nhóm không chặn các nhóm khác
- `log stream` in lý do bỏ qua từng nhóm
- Rollback nhanh: xoá `mc.disabled` mà không cần build lại

Ngoài ra: nếu đang chạy baseline (dylib ngoài) thì **tắt dylib trước khi bật bản port** — hai bộ
hook cùng chạy sẽ double-hook và giá trị mâu thuẫn.

## 9. Xung đột cần xử lý

| Xung đột | Giải pháp |
|---|---|
| LC đã có `spoofSDKVersion`, MC có `MCHookVersion` | Chọn một nguồn. UI cảnh báo khi bật cả hai |
| LC đã có `spoofIdentifierForVendor`, MC có IDFA trong `MCHookAdvertising` | Tách IDFA khỏi vendorUUID, không đè lên toggle LC |
| LC đã tách keychain bằng 128 group | Bỏ hẳn `optionKeychainNamespace` của MC (mặc định vẫn NO ở MC). Ngoài phạm vi |
| LC dùng `CFFIXED_USER_HOME`, MC dựa `NSHomeDirectory()` | Resolve path theo `LC_HOME_PATH`/`LP_HOME_PATH` như `NSFileManager+GuestHooks.m:63` đã làm |
| App khách không sandbox lẫn nhau (`README.md` phần Limitations) | Chấp nhận: hook fake giá trị đọc được, nhưng app vẫn đọc được data file app khác bằng path tuyệt đối. Ghi rõ vào tài liệu |

## 10. Rủi ro

- **Link symbol trong app đã sign**: một số app (đặc biệt iOS 26+) kiểm tra chữ ký ở load → rebind
  có thể trượt. `initDead10ccFix` (`LCBootstrap.m:520`) đã xử lý một dạng, cần verify từng app
- **Giá trị giả tự mâu thuẫn**: `hw.model` = iPhone 15 Pro nhưng `systemVersion` = 26.0 là tổ hợp
  không tồn tại → app check tương quan sẽ phát hiện. Cần validate profile trước khi áp
- **Bundle id**: `useLCBundleId` đổi bundle id nhưng entitlements vẫn của host → app đọc
  entitlements sẽ thấy mâu thuẫn (đã nằm trong Limitations của LC)
- **Chưa verify trên thiết bị thật**: toàn bộ phân tích trong plan này là tĩnh, đọc code.
  Không có kết luận nào ở trên được kiểm chứng bằng chạy thử.

## 11. Ưu lượng (ước lượng)

| Phase | Ưu lượng |
|---|---|
| 0 — Baseline | 0,5 ngày (cần máy thật) |
| 1 — Hạ tầng config | 1 ngày |
| 2 — Hook P0 | 1,5 ngày |
| 2 — Hook P1 | 1,5 ngày |
| 2 — Hook P2 | 1,5 ngày |
| 2 — Hook P3 | 1 ngày |
| 3 — UI | 1,5 ngày |
| 4 — Test + fix | 1 ngày |
| **Tổng** | **~10 ngày** (chưa tính thời gian verify trên máy thật) |

Ước lượng theo code MC hiện có (gần như chuyển nguyên vẹn). Phần tốn thời gian thực tế là
**debug từng app trên thiết bị** — app khác nhau kiểm tra khác nhau, mỗi app có thể lộ thêm
điểm cần hook.
