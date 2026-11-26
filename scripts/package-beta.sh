#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

free_kib=$(df -Pk . | awk 'NR == 2 {print $4}')
if [[ "$free_kib" -lt 20971520 ]]; then
    echo 'Apple release builds require at least 20 GiB of free disk space.' >&2
    exit 1
fi
[[ "$(uname -m)" == arm64 ]] || { echo 'An Apple Silicon Mac is required.' >&2; exit 1; }

tag=v1.0.0-beta.2
output="$PWD/.build/releases/$tag"
mkdir -p "$output"
stage=$(mktemp -d "$output/stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT

for name in ${!BLOT_@}; do
    unset "$name"
done
export BLOT_ENV_FILE="$stage/public.env"
export BLOT_DISTRIBUTION=public-beta
export BLOT_SIGNING_IDENTITY=-
cat > "$BLOT_ENV_FILE" <<'EOF'
BLOT_AUTH_URL=https://blot-agent.vercel.app/login
BLOT_GIGACHAT_MODEL=GigaChat-2
EOF

common=(-project apps/Blot.xcodeproj -configuration Release -disableAutomaticPackageResolution
    CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION=101 MARKETING_VERSION=1.0)
xcodebuild "${common[@]}" -scheme BlotMac -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath .build/xcode ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
xcodebuild "${common[@]}" -scheme BlotIOS -destination 'generic/platform=iOS' \
    -derivedDataPath .build/ios build

mac="$PWD/.build/xcode/Build/Products/Release/Ori.app"
ios="$PWD/.build/ios/Build/Products/Release-iphoneos/Ori.app"
python3 - "$mac" "$ios" <<'PY'
from pathlib import Path
import plistlib
import sys

for argument in sys.argv[1:]:
    bundle = Path(argument)
    resources = bundle / 'Contents/Resources' if (bundle / 'Contents').is_dir() else bundle
    configuration = plistlib.loads((resources / 'AppleInstallation.plist').read_bytes())
    oauth = plistlib.loads((resources / 'GoogleOAuth.plist').read_bytes())
    if configuration['Profile'] != 'public-beta' or 'AuthorizationKey' in configuration['GigaChat']:
        raise SystemExit('Invalid public beta model configuration')
    if any('ClientSecret' in client for client in oauth['Clients'].values()):
        raise SystemExit('A public beta must not include Google credentials')
    if any(p.name in {'.env', 'embedded.mobileprovision', 'embedded.provisionprofile'}
           or p.name.startswith('.env.') for p in bundle.rglob('*')):
        raise SystemExit('A public beta must not include environment files or private profiles')
PY

scripts/sign-native.sh --entitlements apps/macos/BlotMac/BlotMac.entitlements "$mac"
codesign --verify --deep --strict "$mac"
mkdir -p "$stage/dmg" "$stage/ipa/Payload"
ditto "$mac" "$stage/dmg/Ori.app"
ln -s /Applications "$stage/dmg/Applications"
ditto "$ios" "$stage/ipa/Payload/Ori.app"

dmg=Ori-1.0-Beta.2-macOS-arm64.dmg
ipa=Ori-1.0-Beta.2-iOS.ipa
hdiutil create -fs HFS+ -format UDZO -srcfolder "$stage/dmg" -volname 'Ori 1.0 Beta 2' "$stage/$dmg"
hdiutil verify "$stage/$dmg"
(cd "$stage/ipa" && ditto -c -k --keepParent Payload "$stage/$ipa")
unzip -tq "$stage/$ipa"
(cd "$stage" && shasum -a 256 "$dmg" "$ipa" > SHA256SUMS.txt)
mv "$stage/$dmg" "$stage/$ipa" "$stage/SHA256SUMS.txt" "$output/"
printf 'Beta artifacts: %s\n' "$output"
