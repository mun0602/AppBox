<div align="center">
   <img width="217" height="217" src="./screenshots/livecontainer_icon.png" alt="Logo">
</div>


<div align="center">
  <h1><b>mun container</b></h1>
  <p><i>Run iOS apps without installing — and control what those apps see about your device.</i></p>
</div>
<h6 align="center">

Crowdin Project: [![Crowdin](https://badges.crowdin.net/livecontainer/localized.svg)](https://crowdin.com/project/livecontainer) &nbsp;| &nbsp; Documentation:[liveconainer.github.io](https://livecontainer.github.io/docs/intro)

# mun container

- mun container is an **app launcher + device-info changer** (not an emulator or hypervisor) that runs iOS apps inside it.
- Install unlimited apps without hitting the 3-app / 10-app-id free-developer limit, and run multiple versions side-by-side with isolated data containers.
- **Built-in MunChanger**: every app launched in mun container can run with spoofed device, OS, network, sensor, locale, time, and identity values — picked per-app from a profile the user controls. No separate tweak dylib required.
- (Below iOS 26) When JIT is available, codesign is entirely bypassed, no need to sign your apps before installing. Otherwise, your app will be signed with the same certificate used by mun container.

> [!NOTE]
> **mun container is a personal rebranded fork of [LiveContainer](https://github.com/LiveContainer/LiveContainer)** (with the MunChanger device-spoof engine built in).
> Please be aware that all your apps are installed inside mun container, which means it **has full access to their data, including sensitive information such as keychain items and login credentials** — only install builds you compiled yourself.
> For issues of the original LiveContainer, please use the upstream repository; this fork is maintained separately.


# Installation

mun container is a personal fork — there is no public release channel. Build it yourself:

1. Open the project in Xcode.
2. Edit `DEVELOPMENT_TEAM[config=Debug]` / `DEVELOPMENT_TEAM[config=Release]` in `xcconfigs/Global.xcconfig` to your team id.
3. Select the **LiveContainer** scheme and build & install to your device.

The upstream install guides (SideStore/AltStore, JITLess certificates, etc.) still apply conceptually: [install guide](https://livecontainer.github.io/docs/installation), [FAQ](https://livecontainer.github.io/docs/faq).

If you encounter any issue please [read the upstream FAQ here](https://livecontainer.github.io/docs/faq)

## Requirements

- iOS/iPadOS 15+
   + Multitasking requires iOS/iPadOS 16.0+
- AltStore 2.0+ / SideStore 0.6.0+


# Features & Guides

## Device-Info Changer (MunChanger)

Every app you launch inside mun container can be run with a **spoofed device identity** — picked from a built-in catalog of 154 real Apple devices or a fully custom profile you write yourself. The hooks are installed in-process by mun container itself (no separate tweak dylib, no jailbreak, no `task_for_pid`).

### What can be spoofed

> The table below is the full MunChanger surface. All 18 hook groups have source files in `LiveContainer/Tweaks/` and are wired into `MCProfile.m` (keychain is intentionally LC-only, see below). Verified so far: compile + symbol resolution; per-group behavior still needs real-device testing — see the [TODO](#todo) section.

| Category | What's faked |
|---|---|
| Device & OS identity | `sysctl` (`hw.machine`, `kern.osproductversion`, `kern.version`, …), `MGCopyAnswer` / `MobileGestalt` answers, `uname`, `NSProcessInfo`, `UIDevice` |
| Screen & hardware | screen size, native scale, pixel density, CPU count, memory size, chip ID, board ID, cache line, `hw.cpufamily` |
| Network | MAC addresses (Wi-Fi / Bluetooth), IP/cell info, carrier name, MCC/MNC, `getifaddrs` |
| Identity | serial number, UDID, IMEI, IMSI, IDFV (keychain separation itself is a native mun container feature inherited from LiveContainer, not MunChanger) |
| Sensors & motion | `CLLocationManager`, `CMMotionManager` (accel/gyro/magnetometer), `CMAltimeter`, `CMHeading` |
| Locale & time | `NSCalendar`, `NSTimeZone`, `NSLocale`, `NSDateFormatter`, `NSURLSession` clock, `gettimeofday` |
| Advertising & fingerprinting | `ASIdentifierManager` (IDFA), `ASWebAuthenticationSession`, `Storage`/`UserDefaults` unique keys |
| Jailbreak / debug / tamper | hide jailbreak markers, `sysctl(KERN_PROC)` `P_TRACED` flag, debugger attach, code-signature verification (`SecCode`), `dlsym` hook detection |
| Storage & defaults | per-container `NSDocumentDirectory`/`NSCachesDirectory`, `NSUserDefaults` rewriting |
| Missing APIs | shim `NW*` and other symbols apps probe but aren't present on all OS versions |

### How to use

1. **Enable for an app** — long-press an installed app → **Settings** → **Device Changer (MunChanger)** → **Generate fake device profile**. This writes `com.mun.changer.plist` into that app's data container; the profile activates on the next launch.
2. **Pick a device** — the Device picker lists all 154 catalog models (newest first). Choosing one regenerates OS/build/board/chip/RAM/CPU/screen data from the catalog row so every value stays self-consistent.
3. **Randomize identity** — rolls a new serial (12 chars), UDID (40-hex, real iOS format), IMEI (Luhn-valid, prefix 35), Wi-Fi/Bluetooth MAC (real Apple OUI), carrier+MCC/MNC/ISO (from a real carrier list), and device name (from a name pool) — all matching real-world formats.
4. **Per-app profile** — the plist lives inside each data container, so two containers of the same app can run with two different device identities.
5. **Safe mode** — create an empty file named `mc.disabled` in the container's home folder to disable all MunChanger hooks for that container without touching the config. Delete the file to re-enable.

Power users can still hand-edit `com.mun.changer.plist` (reachable from the Files app / Finder since mun container enables file sharing) — the UI is just a front-end for it.

### Configuration file format

The plist lives at `~/Library/Preferences/com.mun.changer.plist` inside the container. Every key is optional — unset keys keep the real value. The full key surface (screen, GPS, timezone, locale, sensors, IDFA, Wi-Fi SSID/BSSID, disk size, …) is documented in [MUN_CHANGER_PORT_PLAN.md](./MUN_CHANGER_PORT_PLAN.md); the core identity keys:

```xml
<dict>
  <key>enabled</key>             <true/>
  <key>deviceName</key>          <string>Test iPhone</string>
  <key>deviceModel</key>         <string>iPhone17,1</string>
  <key>systemVersion</key>       <string>18.5</string>
  <key>buildVersion</key>        <string>22F66</string>
  <key>darwinRelease</key>       <string>24.5.0</string>
  <key>serialNumber</key>        <string>F2LXXXXXXXXX</string>
  <key>udid</key>                <string>00008110-001234ABCDEFGHI</string>
  <key>imei</key>                <string>353000000000010</string>
  <key>imsi</key>                <string>310260000000010</string>
  <key>wifiAddress</key>         <string>02:00:00:00:00:01</string>
  <key>bluetoothAddress</key>    <string>02:00:00:00:00:02</string>
  <key>cpuCount</key>            <integer>6</integer>
  <key>cpuType</key>             <integer>16777228</integer>
  <key>cpuSubtype</key>          <integer>2</integer>
  <key>cpuFamily</key>           <integer>461844506</integer>
  <key>memsizeBytes</key>        <integer>8589934592</integer>
</dict>
```

See [MUN_CHANGER_PORT_PLAN.md](./MUN_CHANGER_PORT_PLAN.md) for the full architecture and the list of every sysctl / gestalt / framework call that is intercepted.

---

## Container features

### Installing Apps
- Open mun container, tap the plus icon in the upper right hand corner and select IPA files to install.
- Choose the app you want to open in the next launch.
- You can long-press the app to manage it.

### [Add Apps to Home Screen](https://livecontainer.github.io/docs/guides/add-to-home-screen)

### [Multiple LiveContainers](https://livecontainer.github.io/docs/guides/multiple-livecontainers)
Using multiple LiveContainers allows you to run multiples different apps simultaneously, with *almost* seamless data transfer between the LiveContainers.

### [Multitasking](https://livecontainer.github.io/docs/guides/multitask)
You can now launch multiple apps simultaneously in in-app virtual windows. These windows can be resized, scaled, and even displayed using the native Picture-in-Picture (PiP) feature. On iPads, apps can run in native window mode, displaying each app in a separate system window. And if you wish, you can choose to run apps in multitasking mode by default in settings.

To use multitasking, hold its banner and tap **"Multitask"**. You can also make Multitask the default launch mode in settings.

>[!Note]
>1. To use multitasking, ensure you select **"Keep App Extensions"** when installing via SideStore/AltStore.
>2. If you want to enable JIT for multitasked apps, you'll need a JIT enabler that supports attaching by PID. (StikDebug)

### [JIT Support](https://livecontainer.github.io/docs/guides/jit-support)
### [Installing external tweaks](https://livecontainer.github.io/docs/guides/tweaks)
### [Multiple Containers/External Containers](https://livecontainer.github.io/docs/guides/containers-and-external-data)
### [Hiding Apps](https://livecontainer.github.io/docs/guides/lock-app)

### Fix File Picker & Local Notification
Some apps may experience issues with their file pickers or not be able to apply for notification permission in mun container. To resolve this, enable "Fix File Picker" & "Fix Local Notifications" accordingly in the app-specific settings.

### "Open In App" Support
- You can simply share a URL or a file to app simply by using iOS's native share sheet. In share sheet, select mun container, and mun container will ask you which app you'd like to open that URL/file in.
- What's more, you also can tap the link icon in the top-right corner of the "Apps" tab and input the URL. mun container will detect the appropriate app and ask if you want to launch that app.

## Compatibility
Unfortunately, not all apps work in mun container, so we have a [compatibility list](https://github.com/LiveContainer/LiveContainer/labels/compatibility) to tell if there is apps that have issues. If they aren't on this list, then it's likely going run. However, if it doesn't work, please make an [issue](https://github.com/LiveContainer/LiveContainer/issues/new/choose) about it.

## Building
Open Xcode, edit `DEVELOPMENT_TEAM[config=Debug]` in `xcconfigs/Global.xcconfig` to your team id and compile.

> **Submodules note:** `LiveContainer/litehook` (the pinned URL currently 404s) is vendored from [opa334/litehook](https://github.com/opa334/litehook) with small patches — header exposes `gRebinds`/`global_rebind`/TPRO helpers and adds `litehook_find_symbol_file` (see `litehook/src/`). `OpenSSL/Frameworks/OpenSSL.xcframework` is vendored from the pinned commit of [krzyzanowskim/OpenSSL](https://github.com/krzyzanowskim/OpenSSL). Both are already in the working tree, so a fresh clone does not need `--recurse-submodules` for these two.

## Project structure
### Main executable
- Core of mun container
- Contains the logic of setting up guest environment and loading guest app.
- If no app is selected, it loads LiveContainerSwiftUI.
- Hosts the **MunChanger hook installer** (`MCProfileInit`) which runs after `DyldHooksInit` and applies the per-container device-spoof profile to every launched app.

### LiveContainerSwiftUI
- SwiftUI rewrite of LiveContainerUI (by @hugeBlack)
- Language file `Localizable.xcstrings` is in here for multilingual support. To help us translate LiveContainer, please visit [our crowdin project](https://crowdin.com/project/livecontainer)
- Renders the **Device Changer** section in app settings (per-app device picker from the 154-model catalog, identity randomizer, enable/remove — writes `com.mun.changer.plist` into the app's data container).

### MultitaskSupport
- Contains the implementation of multitasking feature.
- Based on [FrontBoardAppLauncher](https://github.com/khanhduytran0/FrontBoardAppLauncher)

### SideStore
- Supporting code for SideStore's app refreshing integration

### TweakLoader
- A simple tweak injector, which loads CydiaSubstrate and loads tweaks.
- Injected to every app you install in mun container.

### ZSign
- The app signer shipped with mun container.
- Originally made by [zhlynn](https://github.com/zhlynn/zsign).
- mun container uses [Feather's](https://github.com/khcrysalis/Feather) version of ZSign modified by khcrysalis.
- Changes are made to meet mun container's needs.

### Tweaks/
- LC's in-process hook layer. Each `.m` file owns one category of system call (Dyld, SecItem, NSFileManager, NSURLSession, …).
- **MunChanger hook layer** lives here too: 18 hook-group files (`MCHookGestalt.m`, `MCHookDevice.m`, `MCHookVersion.m`, `MCHookCarrier.m`, `MCHookScreen.m`, `MCHookNetwork.m`, `MCHookAdvertising.m`, `MCHookLocale.m`, `MCHookTime.m`, `MCHookLocation.m`, `MCHookMotion.m`, `MCHookSensors.m`, `MCHookFileManager.m`, `MCHookDefaults.m`, `MCHookJBDetect.m`, `MCHookAntiDebug.m`, `MCHookWolverine.m`, `MCHookSignature.m`) plus `MCMissingAPI.m`, the config reader `MCConfig.m`, the single integration entry `MCProfile.m` (reads `com.mun.changer.plist`, installs every group in dependency order), the 154-device catalog (`MCDeviceCatalog.m` + `MCCatalogJSON.m`), the embedded identity resources (`MCResources.m` + `MCResourcesJSON.m`), and the identity generator `MCRandom.m` (real-format serial/UDID/IMEI/MAC/carrier, seeded variants). `MCHookKeychain.m` is intentionally absent — keychain stays LC's domain (`SecItem.m`).
- The standalone rebind engine is `MCRebind.m`; inline patching (only used where dyld rebind is too coarse) is `MCInlineHook.m`.

### shared/
- *(removed)* MunChanger catalog/generator files originally landed here, but this folder is not part of any build target — they now live in `Tweaks/` (see above): `MCDeviceCatalog`, `MCCatalogJSON`, `MCResources`, `MCResourcesJSON` (embedded name/carrier/OUI data), and `MCRandom` (the identity generator ported from the standalone MunChanger app).

## How does it work?

### Patching guest executable
- Patch `__PAGEZERO` segment:
  + Change `vmaddr` to `0xFFFFC000` (`0x100000000 - 0x4000`)
  + Change `vmsize` to `0x4000`
- Change `MH_EXECUTE` to `MH_DYLIB`.
- Inject a load command to load `TweakLoader.dylib`

### Patching `@executable_path`
- Hook `dyld4::APIs::_NSGetExecutablePath`
- Call `_NSGetExecutablePath`
- Replace `config.process.mainExecutablePath`
  - Calculate address of `config.process.mainExecutablePath` using `dyld4::APIs` instance (passed as first parameter)
  - Use `builtin_vm_protect` or TPRO unlock to make it writable
  - Replace the address with one we have control of
- Put the original `dyld4::APIs::_NSGetExecutablePath` back

> Old Method
>- Call `_NSGetExecutablePath` with an invalid buffer pointer input -> SIGSEGV
>- Do some [magic stuff](https://github.com/khanhduytran0/LiveContainer/blob/5ef1e6a/main.m#L74-L115) to overwrite the contents of executable_path.

### Patching `NSBundle.mainBundle`
- This property is overwritten with the guest app's bundle.

### Bypassing Library Validation
- JIT is optional to bypass codesigning. In JIT-less mode, all executables are signed so this does not apply.
- Derived from [Restoring Dyld Memory Loading](https://blog.xpnsec.com/restoring-dyld-memory-loading)

### dlopening the executable
- Call `dlopen` with the guest app's executable
- TweakLoader loads all tweaks in the selected folder
- Find the entry point
- Jump to the entry point
- The guest app's entry point calls `UIApplicationMain` and start up like any other iOS apps.

### Multi-Account support & Keychain Semi-Separation
[128 keychain access groups](./entitlements.xml) are created and mun container allocates them randomly to each container of the same app. So you can create 128 container with different keychain access groups.

### Device-spoof hook installation (MunChanger)
- After `DyldHooksInit`, `LCBootstrap` calls `MCProfileInit()`.
- `MCProfile` reads the per-container plist via `MCConfig`, then calls each `MCHook*Install()` to install rebind-based patches for the symbols the app would otherwise query.
- Hooks run in the same process as the guest app — no `task_for_pid`, no platform-application entitlement, no external dylib.
- Keychain is intentionally **not** double-hooked: LC's own `SecItem.m` already separates containers across 128 access groups, which is stronger than MunChanger's namespace option. `MCHookKeychainInstall` is therefore skipped by `MCProfileInit`.

## Limitations
- Entitlements from the guest app are not applied to the host app. This isn't a big deal since sideloaded apps requires only basic entitlements.
- App Permissions are globally applied.
- Guest app containers are not sandboxed. This means one guest app can access other guest apps' data.
- App extensions aren't supported. they cannot be registered because: mun container is sandboxed, SpringBoard doesn't know what apps are installed in mun container, and they take up App ID.
- Multitasking can be achieved by using multiple LiveContainers and the multitasking feature. However, while we were able to fix physical keyboard input issue on iPadOS (https://github.com/LiveContainer/LiveContainer/issues/524), iPhone Mirroring uses different checks which still broke it (https://github.com/LiveContainer/LiveContainer/issues/793).
- Remote push notification will not work
- Querying custom URL schemes might not work(?)
- iOS 26+ JITLess mode: MunChanger uses rebind-based patches that need a writable __DATA segment; we have not yet verified on a JITLess iOS 26 device whether writable mappings are available without JIT. A bad profile may need the `mc.disabled` safe-mode file to recover.

## TODO
- **Real-device verification of all 18 hook groups** — the full project builds (LiveContainerShared + SwiftUI + main app), and sysctl/Gestalt spoofing was validated previously in the standalone dylib, but the in-mun-container runtime path (rebind after `DyldHooksInit`, per-launch effect, `MCHookFileManager` container paths) needs testing per group.
- **iOS 26+ JITLess device verification** — the rebind-based patches in `MCRebind.m` need a writable `__DATA` segment. We have not yet confirmed JITLess iOS 26 still exposes one without JIT. The `mc.disabled` safe-mode file will recover a broken profile.
- Use ChOma instead of custom MachO parser.

## License
[Apache License 2.0](https://github.com/khanhduytran0/LiveContainer/blob/main/LICENSE)

## Credits
- [xpn's blogpost: Restoring Dyld Memory Loading](https://blog.xpnsec.com/restoring-dyld-memory-loading)
- [LinusHenze's CFastFind](https://github.com/pinauten/PatchfinderUtils/blob/master/Sources/CFastFind/CFastFind.c): [MIT license](https://github.com/pinauten/PatchfinderUtils/blob/master/LICENSE)
- [litehook](https://github.com/opa334/litehook): [MIT license](https://github.com/opa334/litehook/blob/main/LICENSE)
- [MunChanger](https://github.com/mun/mun-changer) — in-process device-spoof hook engine ported into LiveContainer core
- @haxi0 & @m1337v for icon
- @Vishram1123 for the initial shortcut implementation.
- @hugeBlack for SwiftUI contribution
- @Staubgeborener for automatic AltStore/SideStore source updater
- @fkunn1326 for improved app hiding
- @slds1 for dynamic color feature
- @Vishram1123 for iOS 26+ JIT Script Support
- @StephenDev0 for AltStore source support
