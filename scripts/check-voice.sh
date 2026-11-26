#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
products="$PWD/.build/xcode/Build/Products/Debug"
checks="$PWD/.build/voice"
app="$checks/VoiceVerification.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$checks/cache"
/usr/bin/say -v Milena -o "$app/Contents/Resources/RussianFixture.aiff" "Привет. Это проверка голосового режима. Создай папку для отчёта."
xcrun swiftc -parse-as-library -swift-version 6 -module-cache-path "$checks/cache" \
    -I "$products" -I packages/BlotWorkspace/Sources/CSQLite \
    "$products/BlotDomain.o" "$products/BlotWorkspace.o" "$products/BlotAppleIntegrations.o" -lsqlite3 \
    scripts/verify-voice.swift -o "$checks/VoiceVerification.new"
mv "$checks/VoiceVerification.new" "$app/Contents/MacOS/VoiceVerification"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.blot.voice-verification</string>
<key>CFBundleExecutable</key><string>VoiceVerification</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleName</key><string>Blot Voice Verification</string><key>CFBundleVersion</key><string>1</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSMicrophoneUsageDescription</key><string>Проверка голосового разговора Blot по вашему запросу.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Проверка локального распознавания речи для Blot.</string>
</dict></plist>
PLIST
cat > "$checks/Voice.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.device.audio-input</key><true/>
</dict></plist>
PLIST
scripts/sign-native.sh --entitlements "$checks/Voice.entitlements" "$app"
codesign --verify --strict "$app"
mode="${1:---self-test}"
if [[ "$mode" == --interactive ]]; then
    /usr/bin/open -n "$app"
else
    log="$checks/${mode#--}.log"
    /usr/bin/open -n -W "$app" --args "$mode"
    cp "$HOME/Library/Containers/dev.blot.voice-verification/Data/Library/Caches/VoiceVerification.log" "$log"
    cat "$log"
    if [[ "$mode" == --capture-smoke ]]; then rg -q '^PASS: real microphone verification completed$' "$log"
    else rg -q '^PASS: native voice round trip completed$' "$log"; fi
fi
