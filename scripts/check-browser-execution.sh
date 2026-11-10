#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
products="$PWD/.build/xcode/Build/Products/Debug"
checks="$PWD/.build/verify-browser-execution"
app="$checks/BrowserVerification.app"
mkdir -p "$app/Contents/MacOS" "$checks/cache"
rm -f "$checks/port"
python3 scripts/verify-browser-site.py "$checks/port" > "$checks/site.log" 2>&1 &
site_pid=$!
trap 'kill "$site_pid" 2>/dev/null || true' EXIT
for ((attempt=0;attempt<50;attempt++)); do [[ -s "$checks/port" ]] && break; sleep 0.1; done
port=$(cat "$checks/port")
sources=(WorkspaceService WorkspaceForms WorkspacePersonalization WorkspaceMessageContext WorkspaceSnapshot WorkspaceApplicationInterfaces WorkspaceMessagePinProviding WorkspaceAccountApplicationService WorkspaceAccountProfileActions WorkspaceAccountSynchronizing WorkspaceModelCredentials WorkspaceBrowserAuthenticator LocalWorkspaceService WorkspaceScheduleHost WorkspaceSkillCommands WorkspaceSkillToolCatalog WorkspaceFileCommands WorkspaceDeviceCommands WorkspaceDevicePairingCommands WorkspaceGroupResponder WorkspaceGroupBudget WorkspaceExportFormat WorkspaceMCPProviding WorkspaceNativeProviding WorkspaceBrowserProviding WorkspaceSessionFileProviding WorkspaceAppleIntegrationProviding)
arguments=()
for source in "${sources[@]}"; do arguments+=("apps/shared/WorkspaceV3/$source.swift"); done
xcrun swiftc -parse-as-library -swift-version 5 -module-cache-path "$checks/cache" \
    -I "$products" -I packages/BlotWorkspace/Sources/CSQLite \
    "$products/BlotDomain.o" "$products/BlotWorkspace.o" "$products/BlotAppleIntegrations.o" -lsqlite3 \
    -default-isolation MainActor "${arguments[@]}" apps/macos/BlotMac/Features/Workspace/MacBrowserSplitView.swift scripts/verify-browser-model.swift scripts/verify-browser-execution.swift -o "$app/Contents/MacOS/BrowserVerification"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.blot.browser-verification</string>
<key>CFBundleExecutable</key><string>BrowserVerification</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleName</key><string>BrowserVerification</string><key>CFBundleVersion</key><string>1</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
scripts/sign-native.sh "$app"
"$app/Contents/MacOS/BrowserVerification" "$port"
