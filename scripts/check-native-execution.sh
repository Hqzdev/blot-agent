#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
products="${1:-$PWD/.build/xcode/Build/Products/Debug}"
checks="$PWD/.build/verify-native-execution"
app="$checks/NativeServiceVerification.app"
mkdir -p "$app/Contents/MacOS"
# Compile the same application services as the group/task verification harness.
sources="WorkspaceService WorkspaceForms WorkspacePersonalization WorkspaceMessageContext WorkspaceSnapshot WorkspaceApplicationInterfaces WorkspaceMessagePinProviding WorkspaceAccountApplicationService WorkspaceAccountProfileActions WorkspaceAccountSynchronizing WorkspaceModelCredentials WorkspaceBrowserAuthenticator LocalWorkspaceService WorkspaceScheduleHost WorkspaceSkillCommands WorkspaceSkillToolCatalog WorkspaceFileCommands WorkspaceDeviceCommands WorkspaceDevicePairingCommands WorkspaceGroupResponder WorkspaceGroupBudget WorkspaceExportFormat WorkspaceMCPProviding WorkspaceNativeProviding WorkspaceBrowserProviding WorkspaceSessionFileProviding WorkspaceAppleIntegrationProviding"
set --
for source in $sources; do set -- "$@" "apps/shared/WorkspaceV3/$source.swift"; done
mkdir -p "$checks/cache"
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor -module-cache-path "$checks/cache" \
    -I "$products" -I packages/BlotWorkspace/Sources/CSQLite "$products/BlotDomain.o" "$products/BlotWorkspace.o" "$products/BlotAppleIntegrations.o" -lsqlite3 \
    "$@" scripts/verify-native-execution.swift -o "$app/Contents/MacOS/NativeServiceVerification"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.blot.native-service-verification</string>
<key>CFBundleExecutable</key><string>NativeServiceVerification</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
scripts/build-native-executor.sh "$app" "$products"
cat > "$checks/Host.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST
scripts/sign-native.sh --entitlements "$checks/Host.entitlements" "$app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/NativeServiceVerification"
