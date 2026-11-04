#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export BLOT_DISTRIBUTION=public-beta
export BLOT_ENV_FILE="$PWD/config/apple-public-beta.env"
export BLOT_SIGNING_IDENTITY=-
: "${JAVA_HOME:?Select JDK 25 before packaging}"

output="$PWD/.build/releases/v1.0.0-beta.1"
mkdir -p "$output" .build
common=(-quiet -project apps/Blot.xcodeproj -configuration Release CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION=100 MARKETING_VERSION=1.0)
xcodebuild "${common[@]}" -scheme BlotMac -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath .build/release-mac ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build > .build/beta-mac-build.log 2>&1
xcodebuild "${common[@]}" -scheme BlotIOS -destination 'generic/platform=iOS' \
    -derivedDataPath .build/release-ios build > .build/beta-ios-build.log 2>&1

mac="$PWD/.build/release-mac/Build/Products/Release/Blot.app"
ios="$PWD/.build/release-ios/Build/Products/Release-iphoneos/BlotIOS.app"
python3 - "$mac" "$ios" <<'PY'
from pathlib import Path
import plistlib
import sys

for argument in sys.argv[1:]:
    bundle = Path(argument)
    resources = bundle / 'Contents/Resources' if (bundle / 'Contents').is_dir() else bundle
    config = plistlib.loads((resources / 'AppleInstallation.plist').read_bytes())
    if config['Profile'] != 'public-beta' or config['GigaChat']['AuthorizationKey']:
        raise SystemExit('Refusing to package a build with managed model credentials')
    if any(p.name == '.env' or p.name.startswith('.env.') for p in bundle.rglob('*')):
        raise SystemExit('Refusing to package an environment file')
    if (bundle / 'embedded.mobileprovision').exists():
        raise SystemExit('Public IPA must not include a personal development provisioning profile')
PY

# Configuration is written after backend signing; sign the final outer bundle again.
scripts/sign-native.sh --entitlements apps/macos/BlotMac/BlotMac.entitlements "$mac"
codesign --verify --deep --strict "$mac"
stage="$(mktemp -d "$PWD/.build/beta-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/ipa/Payload"
bash scripts/package-dmg.sh "$mac" "$output/Blot-1.0-Beta-macOS-arm64.dmg"
ditto "$ios" "$stage/ipa/Payload/BlotIOS.app"
(cd "$stage/ipa" && ditto -c -k --keepParent Payload "$output/Blot-1.0-Beta-iOS.ipa")
unzip -tq "$output/Blot-1.0-Beta-iOS.ipa"
(cd "$output" && shasum -a 256 Blot-1.0-Beta-macOS-arm64.dmg Blot-1.0-Beta-iOS.ipa > SHA256SUMS.txt)
echo "Beta artifacts: $output"
