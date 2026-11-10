#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
products="$PWD/.build/xcode/Build/Products/Debug"
checks="$PWD/.build/verify-session-files"
app="$checks/SessionFilesVerification.app"
mkdir -p "$app/Contents/MacOS" "$checks/cache"
sources=(WorkspaceService WorkspaceForms WorkspacePersonalization WorkspaceMessageContext WorkspaceSnapshot WorkspaceApplicationInterfaces WorkspaceMessagePinProviding WorkspaceAccountApplicationService WorkspaceAccountProfileActions WorkspaceAccountSynchronizing WorkspaceModelCredentials WorkspaceBrowserAuthenticator LocalWorkspaceService WorkspaceScheduleHost WorkspaceSkillCommands WorkspaceSkillToolCatalog WorkspaceFileCommands WorkspaceDeviceCommands WorkspaceDevicePairingCommands WorkspaceGroupResponder WorkspaceGroupBudget WorkspaceExportFormat WorkspaceMCPProviding WorkspaceNativeProviding WorkspaceBrowserProviding WorkspaceSessionFileProviding WorkspaceAppleIntegrationProviding)
arguments=()
for source in "${sources[@]}"; do arguments+=("apps/shared/WorkspaceV3/$source.swift"); done
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor -module-cache-path "$checks/cache" \
    -I "$products" -I packages/BlotWorkspace/Sources/CSQLite \
    "$products/BlotDomain.o" "$products/BlotWorkspace.o" "$products/BlotAppleIntegrations.o" -lsqlite3 \
    "${arguments[@]}" scripts/verify-session-files.swift -o "$app/Contents/MacOS/SessionFilesVerification"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.blot.session-files-verification</string>
<key>CFBundleExecutable</key><string>SessionFilesVerification</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleName</key><string>SessionFilesVerification</string><key>CFBundleVersion</key><string>1</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
scripts/build-native-executor.sh "$app" "$products"
cat > "$checks/Host.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
</dict></plist>
PLIST
scripts/sign-native.sh --entitlements "$checks/Host.entitlements" "$app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/SessionFilesVerification"
