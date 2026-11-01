#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /private/tmp/blot-shell-check.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
packages="$check_dir/packages"
mkdir -p "$packages"
# Local packages the app imports, built as static modules the checker links against.
build_package() {
    local name=$1; shift
    local files=()
    while IFS= read -r -d '' file; do files+=("$file"); done < <(find "packages/$name/Sources/$name" -name '*.swift' -print0)
    swiftc -module-cache-path "$check_dir/modules" -parse-as-library -swift-version 6 -module-name "$name" \
        -I "$packages" "$@" -emit-module -emit-module-path "$packages/$name.swiftmodule" \
        -emit-library -static -o "$packages/lib$name.a" "${files[@]}"
}
build_package BlotDomain
build_package BlotAPI
build_package BlotDesign -default-isolation MainActor
sources=()
while IFS= read -r -d '' source; do sources+=("$source"); done < <(find apps/macos/BlotMac apps/shared -name '*.swift' ! -name 'BlotMacApp.swift' ! -name 'ContentView.swift' -print0)
swiftc -module-cache-path "$check_dir/modules" -default-isolation MainActor -parse-as-library \
    -I "$packages" -L "$packages" -lBlotDomain -lBlotAPI -lBlotDesign \
    "${sources[@]}" scripts/macos-render-scenarios.swift scripts/verify-macos-shell.swift -o "$check_dir/verify"
if [[ "${1:-}" == "--render" || "${1:-}" == "--render-only" ]]; then
    xcodebuild -quiet -project apps/Blot.xcodeproj -scheme BlotMac -destination "platform=macOS,arch=$(uname -m)" -configuration Debug -derivedDataPath "$check_dir/build" CODE_SIGNING_ALLOWED=NO build
    cp -R "$check_dir/build/Build/Products/Debug/Blot.app" "$check_dir/Preview.app"
    cp "$check_dir/verify" "$check_dir/Preview.app/Contents/MacOS/verify"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable verify' "$check_dir/Preview.app/Contents/Info.plist"
    "$check_dir/Preview.app/Contents/MacOS/verify" "$1" "$PWD/docs/verification/blot-shell"
else
    "$check_dir/verify"
fi
