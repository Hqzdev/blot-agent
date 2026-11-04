#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mode="${1:-run}"
case "$mode" in
    run|--build-only|--design|--debug|--logs|--telemetry|--verify|--verify-keychain) ;;
    *) echo "usage: $0 [--build-only|--design|--debug|--logs|--telemetry|--verify|--verify-keychain]" >&2; exit 2 ;;
esac
if [[ -z "${BLOT_ENV_FILE:-}" && -f "$PWD/.env" ]]; then
    export BLOT_ENV_FILE="$PWD/.env"
fi
stop_running_app() {
    local pids pid state attempt
    pids=$(pgrep -u "$(id -u)" -x Blot || true)
    for pid in $pids; do
        state=$(ps -o stat= -p "$pid") || continue
        if [[ "$state" == *T* || "$state" == *X* ]]; then
            echo "Blot (PID $pid) остановлен отладчиком. Нажмите ■ Stop в Xcode или завершите LLDB, затем повторите команду." >&2
            return 1
        fi
    done
    for pid in $pids; do
        kill -TERM "$pid" 2>/dev/null || continue
        for ((attempt = 0; attempt < 50; attempt++)); do
            if ! kill -0 "$pid" 2>/dev/null; then break; fi
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            echo "Blot (PID $pid) ещё завершает работу. Закройте приложение и повторите команду." >&2
            return 1
        fi
    done
}
open_app() {
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$1"
    open -n "$1"
}
python3 scripts/apple_build_configuration.py

if [[ "$mode" != --build-only && "$mode" != --verify-keychain ]]; then stop_running_app; fi
export BLOT_SIGNING_IDENTITY="${BLOT_SIGNING_IDENTITY:--}"
xcodebuild -quiet -project apps/Blot.xcodeproj -scheme BlotMac -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED="${BLOT_CODE_SIGNING_ALLOWED:-YES}" build
app_bundle="$PWD/.build/xcode/Build/Products/Debug/Blot.app"
# Backend входит в build phase BlotMac; не запускаем приложение с неполными ресурсами.
[[ -s "$app_bundle/Contents/Resources/Backend/blot-backend.jar" && -x "$app_bundle/Contents/Resources/Backend/runtime/Contents/Home/bin/java" ]] || {
    echo 'Backend is missing from the built app. Check the Embed Java backend build phase.' >&2
    exit 1
}
case "$mode" in
    --build-only) echo "Built: $app_bundle" ;;
    --design) open -n "$app_bundle" --args --team-design ;;
    --debug) lldb -- "$app_bundle/Contents/MacOS/Blot" ;;
    --logs) open_app "$app_bundle"; /usr/bin/log stream --info --style compact --predicate 'process == "Blot"' ;;
    --telemetry)
        bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_bundle/Contents/Info.plist")
        open_app "$app_bundle"
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$bundle_id\""
        ;;
    --verify) open_app "$app_bundle"; sleep 1; pgrep -x Blot >/dev/null ;;
    --verify-keychain)
        keychain_result_path="$PWD/.build/mac-keychain-verification.json"
        open -W -n -o "$keychain_result_path" --stderr "$PWD/.build/mac-keychain-verification.stderr.log" "$app_bundle" --args --verify-keychain
        python3 - "$keychain_result_path" <<'PY'
import json
from pathlib import Path
import sys
result = json.loads(Path(sys.argv[1]).read_text())
print(result)
sys.exit(0 if result.get("passed") is True else 1)
PY
        ;;
    run) open_app "$app_bundle" ;;
esac
