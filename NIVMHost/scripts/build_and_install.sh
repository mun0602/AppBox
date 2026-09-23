#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST_DIR="$PROJECT_ROOT"
TEMPMAIL_CLIENT_IOS_ROOT="${TEMPMAIL_CLIENT_IOS_ROOT:-$PROJECT_ROOT/../../pornhub/pornhub_client/ios}"
DEFAULT_DEVICE="003F06EE-CAF3-553A-8035-CDD0276F9ED1"
DEVICE_ID="${1:-$DEFAULT_DEVICE}"
DERIVED_DATA="$PROJECT_ROOT/Build/DerivedData"
ZIPFOUNDATION_DERIVED_DATA="$PROJECT_ROOT/Build/ZIPFoundationDerivedData"
TEMPMAIL_CATALOG_BASE_URL="${TEMPMAIL_CATALOG_BASE_URL:-https://3601.help}"
TEMPMAIL_CLIENT_AES_KEY="${TEMPMAIL_CLIENT_AES_KEY:-6btlrID18OytwUZ0s41atap+4WxlXr1xpebjrE04hnY=}"
TEMPMAIL_ASSET_AES_KEY="${TEMPMAIL_ASSET_AES_KEY:-}"
TEMPMAIL_ASSET_AES_IV="${TEMPMAIL_ASSET_AES_IV:-}"
PLAYBOX_RUNTIME_ROOT="$(mktemp -d /tmp/tempmail-playbox-runtime.XXXXXX)"
PLAYBOX_RUNTIME_FRAMEWORKS="$PLAYBOX_RUNTIME_ROOT/Frameworks"
PORNHUB_GUEST_IPA="${PORNHUB_GUEST_IPA:-/Users/king/Documents/GitHub/pornhub/pornhub_client/dist/ios/non_tf/天涯-非TF.ipa}"
CUSTOM_FLUTTER_FRAMEWORK="/Users/king/flutter/engine/src/out/ios_debug_unopt/Flutter.framework"

if [[ ! -d "$TEMPMAIL_CLIENT_IOS_ROOT/.symlinks/plugins" ]]; then
  echo "pornhub_client Flutter plugin links were not found: $TEMPMAIL_CLIENT_IOS_ROOT" >&2
  exit 9
fi
mkdir -p "$HOST_DIR/.symlinks"
ln -sfn "$TEMPMAIL_CLIENT_IOS_ROOT/.symlinks/plugins" "$HOST_DIR/.symlinks/plugins"

xcodebuild \
  -project "$HOST_DIR/Pods/Pods.xcodeproj" \
  -scheme ZIPFoundation \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$ZIPFOUNDATION_DERIVED_DATA" \
  build

"$SCRIPT_DIR/prepare_playbox_runtime.sh" "$PLAYBOX_RUNTIME_FRAMEWORKS"
ZIPFOUNDATION_FRAMEWORK="$HOST_DIR/build/Release-iphoneos/ZIPFoundation/ZIPFoundation.framework"
if [[ ! -f "$ZIPFOUNDATION_FRAMEWORK/ZIPFoundation" ]]; then
  echo "ZIPFoundation runtime was not built: $ZIPFOUNDATION_FRAMEWORK" >&2
  exit 11
fi
rm -rf "$PLAYBOX_RUNTIME_FRAMEWORKS/ZIPFoundation.framework"
ditto "$ZIPFOUNDATION_FRAMEWORK" "$PLAYBOX_RUNTIME_FRAMEWORKS/ZIPFoundation.framework"
if [[ ! -f "$CUSTOM_FLUTTER_FRAMEWORK/Flutter" ]]; then
  echo "Custom Flutter runtime was not built: $CUSTOM_FLUTTER_FRAMEWORK" >&2
  exit 12
fi
ditto "$CUSTOM_FLUTTER_FRAMEWORK" "$PLAYBOX_RUNTIME_FRAMEWORKS/Flutter.framework"

# Core Flutter plugins are taken from the exact target IPA and re-signed as
# nested TempMail code. They are not linked into the launcher and are loaded only
# after the Flutter guest runtime has been selected.
PORNHUB_PLUGIN_ROOT="$(mktemp -d /tmp/tempmail-pornhub-plugins.XXXXXX)"
ditto -x -k "$PORNHUB_GUEST_IPA" "$PORNHUB_PLUGIN_ROOT"
PORNHUB_PLUGIN_APP="$(find "$PORNHUB_PLUGIN_ROOT/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
for framework_name in \
  JNKeychain \
  connectivity_plus \
  device_info_plus \
  flutter_secure_storage \
  mobile_device_identifier \
  package_info_plus \
  path_provider_foundation \
  shared_preferences_foundation; do
  source_framework="$PORNHUB_PLUGIN_APP/Frameworks/$framework_name.framework"
  if [[ ! -f "$source_framework/$framework_name" ]]; then
    echo "Required pornhub_client plugin is missing: $framework_name" >&2
    exit 13
  fi
  ditto "$source_framework" "$PLAYBOX_RUNTIME_FRAMEWORKS/$framework_name.framework"
done

BUILD_ACTIONS=(build)
if [[ "${TEMPMAIL_CLEAN_BUILD:-1}" == "1" ]]; then
  BUILD_ACTIONS=(clean build)
fi

XCODEBUILD_ARGUMENTS=(
  -project "$HOST_DIR/Runner.xcodeproj"
  -scheme Runner
  -configuration Release
  -destination "id=$DEVICE_ID"
  -derivedDataPath "$DERIVED_DATA"
)
if [[ "${TEMPMAIL_ALLOW_PROVISIONING_UPDATES:-0}" == "1" ]]; then
  XCODEBUILD_ARGUMENTS+=(
    -allowProvisioningUpdates
    -allowProvisioningDeviceRegistration
  )
fi

XCODEBUILD_ARGUMENTS+=(
  "FRAMEWORK_SEARCH_PATHS=\$(inherited) $PLAYBOX_RUNTIME_FRAMEWORKS"
  'OTHER_LDFLAGS=$(inherited) -framework ZIPFoundation'
  "TEMPMAIL_CATALOG_BASE_URL=$TEMPMAIL_CATALOG_BASE_URL"
  "TEMPMAIL_CLIENT_AES_KEY=$TEMPMAIL_CLIENT_AES_KEY"
  "TEMPMAIL_ASSET_AES_KEY=$TEMPMAIL_ASSET_AES_KEY"
  "TEMPMAIL_ASSET_AES_IV=$TEMPMAIL_ASSET_AES_IV"
  "${BUILD_ACTIONS[@]}"
)

xcodebuild "${XCODEBUILD_ARGUMENTS[@]}"

HOST_APP="$DERIVED_DATA/Build/Products/Release-iphoneos/TempMail.app"
if [[ ! -d "$HOST_APP" ]]; then
  echo "Built TempMail was not found: $HOST_APP" >&2
  exit 20
fi
SIGNING_AUTHORITY="$(codesign -d --verbose=4 "$HOST_APP" 2>&1 \
  | sed -n 's/^Authority=//p' \
  | head -1)"
SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
  | grep -F "\"$SIGNING_AUTHORITY\"" \
  | awk 'NR == 1 { print $2 }')"
ENTITLEMENTS="$DERIVED_DATA/Build/Intermediates.noindex/Runner.build/Release-iphoneos/Runner.build/TempMail.app.xcent"
if [[ -z "$SIGNING_IDENTITY" || ! -f "$ENTITLEMENTS" ]]; then
  echo "Could not resolve the development signing identity or entitlements." >&2
  exit 21
fi

mkdir -p "$HOST_APP/Frameworks"
while IFS= read -r framework; do
  ditto "$framework" "$HOST_APP/Frameworks/$(basename "$framework")"
done < <(find "$PLAYBOX_RUNTIME_FRAMEWORKS" -maxdepth 1 -type d -name '*.framework' -print | sort)
if [[ ! -f "$HOST_APP/Frameworks/PBPlayerKit.framework/Floating.bundle/cscb_floating_icon@2x.png" ]]; then
  echo "PBPlayerKit floating UI bundle was not staged into TempMail." >&2
  exit 24
fi

# CopySwiftLibs may strip the custom Flutter binary after the Xcode phase signed
# it. Seal the nested framework and outer app in their final on-disk form.
while IFS= read -r framework; do
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$framework"
done < <(find "$HOST_APP/Frameworks" -maxdepth 1 -type d -name '*.framework' -print | sort)
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none \
  --entitlements "$ENTITLEMENTS" "$HOST_APP"
codesign --verify --deep --strict --verbose=2 "$HOST_APP"
xcrun devicectl device install app --device "$DEVICE_ID" "$HOST_APP"

xcrun devicectl device process launch --device "$DEVICE_ID" \
  --terminate-existing com.tianya.tempmail

echo "TEMPMAIL_HOST_OK"
echo "device=$DEVICE_ID"
echo "bundle=com.tianya.tempmail"
echo "host_app=$HOST_APP"
