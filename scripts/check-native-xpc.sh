#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
products="${1:-$PWD/packages/BlotWorkspace/.build/out/Products/Debug}"
build="$PWD/.build/native-xpc-verification"
app="$build/NativeVerification.app"
mkdir -p "$app/Contents/MacOS" "$build/cache"
xcrun swiftc -parse-as-library -swift-version 6 -module-cache-path "$build/cache" -I "$products" -I packages/BlotWorkspace/Sources/CSQLite \
    "$products/BlotDomain.o" "$products/BlotWorkspace.o" -lsqlite3 scripts/verify-native-xpc.swift -o "$app/Contents/MacOS/NativeVerification"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.blot.native-verification</string>
<key>CFBundleExecutable</key><string>NativeVerification</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
scripts/build-native-executor.sh "$app" "$products"
cat > "$build/Host.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST
scripts/sign-native.sh --entitlements "$build/Host.entitlements" "$app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/NativeVerification"
