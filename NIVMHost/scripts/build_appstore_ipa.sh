#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPMAIL_ARTIFACT_ROOT="${TEMPMAIL_ARTIFACT_ROOT:-/Users/king/Documents/AppBox}"
TEMPMAIL_CLIENT_IOS_ROOT="${TEMPMAIL_CLIENT_IOS_ROOT:-${PROJECT_ROOT}/../../pornhub/pornhub_client/ios}"
TEMPMAIL_CATALOG_BASE_URL="${TEMPMAIL_CATALOG_BASE_URL:-https://3601.help}"
TEMPMAIL_CLIENT_AES_KEY="${TEMPMAIL_CLIENT_AES_KEY:-}"
TEMPMAIL_ASSET_AES_KEY="${TEMPMAIL_ASSET_AES_KEY:-}"
TEMPMAIL_ASSET_AES_IV="${TEMPMAIL_ASSET_AES_IV:-}"
PORNHUB_GUEST_IPA="${PORNHUB_GUEST_IPA:-/Users/king/Documents/GitHub/pornhub/pornhub_client/dist/ios/non_tf/天涯-非TF.ipa}"
# The stock release-mode engine currently crashes source-built Flutter guests
# during DartVM::GetVMData. Keep the previously verified custom debug-unopt
# engine and strip its debug/local symbols below for a safe size reduction.
CUSTOM_FLUTTER_FRAMEWORK="${CUSTOM_FLUTTER_FRAMEWORK:-/Users/king/flutter/engine/src/out/ios_debug_unopt/Flutter.framework}"
TEAM_ID="${TEAM_ID:-6TQJ3XWC45}"
TEMPMAIL_PROFILE_SPECIFIER="${TEMPMAIL_PROFILE_SPECIFIER:-}"
TEMPMAIL_SIGNING_IDENTITY="${TEMPMAIL_SIGNING_IDENTITY:-Apple Distribution}"
BUILD_STAMP="${BUILD_STAMP:-$(date '+%Y%m%d-%H%M%S')}"
APP_VERSION="${APP_VERSION:-1.0.0}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-$(date '+%Y%m%d%H%M')}"
OUTPUT_ROOT="${OUTPUT_ROOT:-${PROJECT_ROOT}/dist/TempMail-appstore-optimized-${BUILD_STAMP}}"
ARCHIVE_PATH="${OUTPUT_ROOT}/TempMail.xcarchive"
EXPORT_PATH="${OUTPUT_ROOT}/export"
DERIVED_DATA="${OUTPUT_ROOT}/DerivedData"
ZIPFOUNDATION_DERIVED_DATA="${OUTPUT_ROOT}/ZIPFoundationDerivedData"
RUNTIME_ROOT="${OUTPUT_ROOT}/Runtime"
RUNTIME_FRAMEWORKS="${RUNTIME_ROOT}/Frameworks"
PLUGIN_ROOT="${OUTPUT_ROOT}/PornhubPlugins"
EXPORT_OPTIONS="${OUTPUT_ROOT}/ExportOptions-AppStore.plist"
ARCHIVE_ENTITLEMENTS="${OUTPUT_ROOT}/archive-entitlements.plist"
LEGACY_IPAD_ICON_SOURCE="${PROJECT_ROOT}/Runner/Assets.xcassets/TempMailAppIcon.appiconset/TempMail-AppIcon-83.5x83.5@2x.png"
LEGACY_IPAD_ICON_NAME="TempMailAppIcon83.5x83.5"
LEGACY_IPAD_ICON_FILE="${LEGACY_IPAD_ICON_NAME}@2x~ipad.png"

fail() {
  printf 'App Store build failed: %s\n' "$*" >&2
  exit 1
}

validate_appstore_bundle() {
  local app_path="$1"
  local require_distribution="${2:-1}"
  local info_plist="${app_path}/Info.plist"
  local key value

  for key in \
    NSCameraUsageDescription \
    NSPhotoLibraryUsageDescription \
    NSPhotoLibraryAddUsageDescription \
    NSMicrophoneUsageDescription \
    NSContactsUsageDescription \
    NSSpeechRecognitionUsageDescription \
    NSCalendarsUsageDescription \
    NSCalendarsFullAccessUsageDescription \
    NSLocationWhenInUseUsageDescription \
    NSLocationAlwaysAndWhenInUseUsageDescription; do
    value="$(plutil -extract "${key}" raw -o - "${info_plist}" 2>/dev/null || true)"
    [[ -n "${value}" ]] || fail "missing or empty privacy purpose string: ${key}"
  done

  for key in NSCalendarsWriteOnlyAccessUsageDescription NSLocalNetworkUsageDescription; do
    if plutil -extract "${key}" raw -o - "${info_plist}" >/dev/null 2>&1; then
      fail "unused privacy purpose string remains: ${key}"
    fi
  done

  value="$(plutil -extract CFBundleDisplayName raw -o - "${info_plist}" 2>/dev/null || true)"
  [[ "${value}" == "临时邮箱" ]] || fail "CFBundleDisplayName must be 临时邮箱"
  value="$(plutil -extract CFBundleName raw -o - "${info_plist}" 2>/dev/null || true)"
  [[ "${value}" == "TempMail" ]] || fail "CFBundleName must be TempMail"
  value="$(plutil -extract CFBundleIdentifier raw -o - "${info_plist}" 2>/dev/null || true)"
  [[ "${value}" == "com.tianya.tempmail" ]] || fail "CFBundleIdentifier must be com.tianya.tempmail"
  value="$(plutil -extract CFBundleShortVersionString raw -o - "${info_plist}" 2>/dev/null || true)"
  [[ "${value}" == "${APP_VERSION}" ]] || fail "unexpected marketing version: ${value}"
  value="$(plutil -extract CFBundleVersion raw -o - "${info_plist}" 2>/dev/null || true)"
  [[ "${value}" == "${APP_BUILD_NUMBER}" ]] || fail "unexpected build number: ${value}"
  value="$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw -o - \
      "${info_plist}" 2>/dev/null || true)"
  [[ "${value}" == "tempmail" ]] || fail "primary URL scheme must be tempmail"
  if /usr/bin/strings -a "${app_path}/TempMail" | grep -Fqx '天涯盒子'; then
    fail "legacy user-facing brand remains in the host executable: 天涯盒子"
  fi

  if rg -a -l -F '_cfBundle' "${app_path}" >/dev/null; then
    fail "non-public selector remains in the built application: _cfBundle"
  fi

  if /usr/bin/strings -a "${app_path}/TempMail" | grep -Fqx 'suspend'; then
    fail "non-public UIApplication suspend selector remains in the host executable"
  fi

  [[ -f "${app_path}/PrivacyInfo.xcprivacy" ]] \
    || fail "app privacy manifest is missing"
  plutil -lint "${app_path}/PrivacyInfo.xcprivacy" >/dev/null \
    || fail "app privacy manifest is invalid"

  if plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoads raw -o - \
      "${info_plist}" 2>/dev/null | grep -qx 'true'; then
    fail "NSAllowsArbitraryLoads must not be enabled"
  fi

  if plutil -extract CFBundleIcons.CFBundleAlternateIcons xml1 -o - \
      "${info_plist}" >/dev/null 2>&1 || \
     plutil -extract 'CFBundleIcons~ipad.CFBundleAlternateIcons' xml1 -o - \
      "${info_plist}" >/dev/null 2>&1; then
    fail "alternate app icons remain in the application"
  fi

  if rg -a -l -e 'AppIcon(WeChat|QQ|Alipay|Toutiao|Douyin|Xiaohongshu|Telegram)' \
      -e 'guest_(adult_douyin|chungong|dyzb_gq|dyzb_tf|ig_xiongmao|pornhub|tianya)' \
      "${app_path}" >/dev/null; then
    fail "retired third-party icon assets remain in the application"
  fi

  local signed_entitlements
  signed_entitlements="$(mktemp)"
  codesign -d --entitlements :- "${app_path}" > "${signed_entitlements}" 2>/dev/null
  value="$(/usr/libexec/PlistBuddy -c 'Print :get-task-allow' \
      "${signed_entitlements}" 2>/dev/null || true)"
  [[ "${require_distribution}" != "1" || "${value}" != "true" ]] || {
    rm -f "${signed_entitlements}"
    fail "App Store application must not contain get-task-allow=true"
  }
  for key in \
    com.apple.developer.networking.networkextension \
    com.apple.developer.networking.wifi-info \
    com.apple.developer.associated-domains \
    com.apple.developer.healthkit \
    com.apple.developer.icloud-services \
    com.apple.developer.family-controls \
    com.apple.developer.kernel.increased-memory-limit \
    com.apple.security.application-groups \
    aps-environment \
    keychain-access-groups; do
    if /usr/libexec/PlistBuddy -c "Print :${key}" \
        "${signed_entitlements}" >/dev/null 2>&1; then
      rm -f "${signed_entitlements}"
      fail "unexpected entitlement remains in App Store application: ${key}"
    fi
  done
  rm -f "${signed_entitlements}"

  if find "${app_path}" -type d \( -name 'TempMailActivityMonitor.appex' \
      -o -name 'TempMailShieldConfiguration.appex' \
      -o -name 'TempMailShieldAction.appex' \
      -o -name 'TempMailUsageReport.appex' \) -print -quit | grep -q .; then
    fail "obsolete Screen Time extension remains in App Store application"
  fi

  if otool -L "${app_path}/TempMail" | grep -Eq \
      '/(FamilyControls|ManagedSettings|ManagedSettingsUI|DeviceActivity)\\.framework/'; then
    fail "obsolete Screen Time framework remains linked in App Store application"
  fi
}

[[ -d "${TEMPMAIL_CLIENT_IOS_ROOT}/.symlinks/plugins" ]] \
  || fail "Flutter plugin links were not found at ${TEMPMAIL_CLIENT_IOS_ROOT}"
[[ -f "${PORNHUB_GUEST_IPA}" ]] || fail "pornhub_client IPA is missing: ${PORNHUB_GUEST_IPA}"
[[ -f "${CUSTOM_FLUTTER_FRAMEWORK}/Flutter" ]] \
  || fail "release Flutter runtime is missing: ${CUSTOM_FLUTTER_FRAMEWORK}"
[[ -f "${LEGACY_IPAD_ICON_SOURCE}" ]] \
  || fail "167x167 iPad Pro icon is missing: ${LEGACY_IPAD_ICON_SOURCE}"

mkdir -p "${OUTPUT_ROOT}" "${RUNTIME_FRAMEWORKS}" "${PLUGIN_ROOT}"
mkdir -p "${PROJECT_ROOT}/.symlinks"
ln -sfn "${TEMPMAIL_CLIENT_IOS_ROOT}/.symlinks/plugins" "${PROJECT_ROOT}/.symlinks/plugins"

"${SCRIPT_DIR}/validate_app_icons.sh"

xcodebuild \
  -quiet \
  -project "${PROJECT_ROOT}/Pods/Pods.xcodeproj" \
  -scheme ZIPFoundation \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "${ZIPFOUNDATION_DERIVED_DATA}" \
  build

"${SCRIPT_DIR}/prepare_playbox_runtime.sh" "${RUNTIME_FRAMEWORKS}"

ZIPFOUNDATION_FRAMEWORK="${PROJECT_ROOT}/build/Release-iphoneos/ZIPFoundation/ZIPFoundation.framework"
[[ -f "${ZIPFOUNDATION_FRAMEWORK}/ZIPFoundation" ]] \
  || fail "ZIPFoundation runtime was not built: ${ZIPFOUNDATION_FRAMEWORK}"
ditto "${ZIPFOUNDATION_FRAMEWORK}" "${RUNTIME_FRAMEWORKS}/ZIPFoundation.framework"
ditto "${CUSTOM_FLUTTER_FRAMEWORK}" "${RUNTIME_FRAMEWORKS}/Flutter.framework"

ditto -x -k "${PORNHUB_GUEST_IPA}" "${PLUGIN_ROOT}"
PORNHUB_PLUGIN_APP="$(find "${PLUGIN_ROOT}/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "${PORNHUB_PLUGIN_APP}" ]] || fail "pornhub_client app bundle was not found in the IPA"
for framework_name in \
  JNKeychain \
  connectivity_plus \
  device_info_plus \
  flutter_secure_storage \
  mobile_device_identifier \
  package_info_plus \
  path_provider_foundation \
  shared_preferences_foundation; do
  source_framework="${PORNHUB_PLUGIN_APP}/Frameworks/${framework_name}.framework"
  [[ -f "${source_framework}/${framework_name}" ]] \
    || fail "required pornhub_client plugin is missing: ${framework_name}"
  ditto "${source_framework}" "${RUNTIME_FRAMEWORKS}/${framework_name}.framework"
done

if [[ "${TEMPMAIL_STRIP_RUNTIME:-1}" == "1" ]]; then
  for binary in \
    "${RUNTIME_FRAMEWORKS}/Flutter.framework/Flutter" \
    "${RUNTIME_FRAMEWORKS}/PBPlayerKit.framework/PBPlayerKit" \
    "${RUNTIME_FRAMEWORKS}/VLCKit.framework/VLCKit"; do
    [[ -f "${binary}" ]] || fail "runtime binary is missing: ${binary}"
    xcrun strip -S -x "${binary}"
  done
fi

ARCHIVE_SIGNING_ARGS=(-allowProvisioningUpdates)
EXPORT_SIGNING_ARGS=(-allowProvisioningUpdates)
if [[ -n "${TEMPMAIL_PROFILE_SPECIFIER}" ]]; then
  EXPORT_SIGNING_ARGS=()
  ARCHIVE_SIGNING_ARGS=(
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=${TEMPMAIL_SIGNING_IDENTITY}"
    "PROVISIONING_PROFILE_SPECIFIER=${TEMPMAIL_PROFILE_SPECIFIER}"
  )
fi

xcodebuild \
  -quiet \
  -workspace "${PROJECT_ROOT}/Runner.xcworkspace" \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "${DERIVED_DATA}" \
  -archivePath "${ARCHIVE_PATH}" \
  "${ARCHIVE_SIGNING_ARGS[@]}" \
  "FRAMEWORK_SEARCH_PATHS=\$(inherited) ${RUNTIME_FRAMEWORKS}" \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  TEMPMAIL_CATALOG_BASE_URL="${TEMPMAIL_CATALOG_BASE_URL}" \
  TEMPMAIL_CLIENT_AES_KEY="${TEMPMAIL_CLIENT_AES_KEY}" \
  TEMPMAIL_ASSET_AES_KEY="${TEMPMAIL_ASSET_AES_KEY}" \
  TEMPMAIL_ASSET_AES_IV="${TEMPMAIL_ASSET_AES_IV}" \
  MARKETING_VERSION="${APP_VERSION}" \
  CURRENT_PROJECT_VERSION="${APP_BUILD_NUMBER}" \
  archive

HOST_APP="${ARCHIVE_PATH}/Products/Applications/TempMail.app"
[[ -d "${HOST_APP}" ]] || fail "archived application was not found: ${HOST_APP}"

# Xcode keeps the 167x167 rendition in Assets.car, but App Store validation can
# also require the legacy standalone iPad Pro icon referenced by Info.plist.
# Keep both representations so the bundle is accepted by modern and older
# validation paths.
ditto "${LEGACY_IPAD_ICON_SOURCE}" "${HOST_APP}/${LEGACY_IPAD_ICON_FILE}"

INFO_PLIST="${HOST_APP}/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleIconFiles~ipad' "${INFO_PLIST}" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFiles~ipad array' "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFiles~ipad:0 string TempMailAppIcon60x60' "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFiles~ipad:1 string TempMailAppIcon76x76' "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFiles~ipad:2 string ${LEGACY_IPAD_ICON_NAME}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles' "${INFO_PLIST}" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles array' "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles:0 string TempMailAppIcon60x60' "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles:1 string TempMailAppIcon76x76' "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles:2 string ${LEGACY_IPAD_ICON_NAME}" "${INFO_PLIST}"

SIGNING_AUTHORITY="$(codesign -d --verbose=4 "${HOST_APP}" 2>&1 \
  | sed -n 's/^Authority=//p' \
  | head -1)"
SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
  | grep -F "\"${SIGNING_AUTHORITY}\"" \
  | awk 'NR == 1 { print $2 }')"
[[ -n "${SIGNING_IDENTITY}" ]] || fail "archive signing identity could not be resolved"

codesign -d --entitlements :- "${HOST_APP}" > "${ARCHIVE_ENTITLEMENTS}" 2>/dev/null
plutil -lint "${ARCHIVE_ENTITLEMENTS}" >/dev/null

mkdir -p "${HOST_APP}/Frameworks"
while IFS= read -r framework; do
  ditto "${framework}" "${HOST_APP}/Frameworks/$(basename "${framework}")"
done < <(find "${RUNTIME_FRAMEWORKS}" -maxdepth 1 -type d -name '*.framework' -print | sort)

while IFS= read -r framework; do
  codesign --force --sign "${SIGNING_IDENTITY}" --timestamp=none "${framework}"
done < <(find "${HOST_APP}/Frameworks" -maxdepth 1 -type d -name '*.framework' -print | sort)
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp=none \
  --entitlements "${ARCHIVE_ENTITLEMENTS}" "${HOST_APP}"
codesign --verify --deep --strict --verbose=2 "${HOST_APP}"
"${SCRIPT_DIR}/validate_app_icons.sh" "${HOST_APP}"
# Xcode may use a development profile for the intermediate archive and replace
# it with an App Store profile during export. All capability checks still run
# here; get-task-allow=false is enforced on the exported IPA below.
validate_appstore_bundle "${HOST_APP}" 0

plutil -create xml1 "${EXPORT_OPTIONS}"
plutil -insert destination -string export "${EXPORT_OPTIONS}"
plutil -insert manageAppVersionAndBuildNumber -bool NO "${EXPORT_OPTIONS}"
plutil -insert method -string app-store-connect "${EXPORT_OPTIONS}"
if [[ -n "${TEMPMAIL_PROFILE_SPECIFIER}" ]]; then
  plutil -insert signingStyle -string manual "${EXPORT_OPTIONS}"
  plutil -insert signingCertificate -string "${TEMPMAIL_SIGNING_IDENTITY}" "${EXPORT_OPTIONS}"
  python3 - "${EXPORT_OPTIONS}" "${TEMPMAIL_PROFILE_SPECIFIER}" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'rb') as handle:
    options = plistlib.load(handle)
options['provisioningProfiles'] = {'com.tianya.tempmail': sys.argv[2]}
with open(sys.argv[1], 'wb') as handle:
    plistlib.dump(options, handle)
PY
else
  plutil -insert signingStyle -string automatic "${EXPORT_OPTIONS}"
fi
plutil -insert stripSwiftSymbols -bool YES "${EXPORT_OPTIONS}"
plutil -insert teamID -string "${TEAM_ID}" "${EXPORT_OPTIONS}"
plutil -insert uploadSymbols -bool NO "${EXPORT_OPTIONS}"

xcodebuild \
  -quiet \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}" \
  ${EXPORT_SIGNING_ARGS[@]+"${EXPORT_SIGNING_ARGS[@]}"}

IPA_PATH="$(find "${EXPORT_PATH}" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
[[ -n "${IPA_PATH}" ]] || fail "export did not produce an IPA"
unzip -tq "${IPA_PATH}"

VALIDATION_ROOT="${OUTPUT_ROOT}/validation"
mkdir -p "${VALIDATION_ROOT}"
ditto -x -k "${IPA_PATH}" "${VALIDATION_ROOT}"
VALIDATION_APP="$(find "${VALIDATION_ROOT}/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "${VALIDATION_APP}" ]] || fail "exported app bundle was not found"
codesign --verify --deep --strict --verbose=2 "${VALIDATION_APP}"
"${SCRIPT_DIR}/validate_app_icons.sh" "${VALIDATION_APP}"
validate_appstore_bundle "${VALIDATION_APP}" 1

printf 'APPSTORE_IPA_OK\n'
printf 'ipa=%s\n' "${IPA_PATH}"
printf 'bytes=%s\n' "$(stat -f '%z' "${IPA_PATH}")"
printf 'sha256=%s\n' "$(shasum -a 256 "${IPA_PATH}" | awk '{print $1}')"
printf 'version=%s\n' "${APP_VERSION}"
printf 'build=%s\n' "${APP_BUILD_NUMBER}"
