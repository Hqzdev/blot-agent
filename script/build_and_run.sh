#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mode="${1:-run}"
case "$mode" in
    run|--build-only|--debug|--logs|--telemetry|--verify) ;;
    *) echo "usage: $0 [--build-only|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
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
open_app() (
    if [[ -z "${BLOT_ENV_FILE:-}" ]]; then
        exec open -n "$1"
    fi
    if [[ ! -f "$BLOT_ENV_FILE" || ! -r "$BLOT_ENV_FILE" ]]; then
        echo 'Не удалось прочитать BLOT_ENV_FILE.' >&2
        return 1
    fi
    if (( $(stat -f %z "$BLOT_ENV_FILE") > 262144 )); then
        echo '.env должен быть размером до 256 KiB.' >&2
        return 1
    fi
    local channel_directory channel writer_pid='' attempt
    channel_directory=$(mktemp -d "${TMPDIR:-/tmp}/blot-env.XXXXXX")
    channel="$channel_directory/input"
    cleanup_channel() {
        if [[ -n "$writer_pid" ]]; then
            kill "$writer_pid" 2>/dev/null || true
            wait "$writer_pid" 2>/dev/null || true
        fi
        rm -f "$channel"
        rmdir "$channel_directory"
    }
    trap cleanup_channel EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mkfifo -m 600 "$channel"
    # launchd не имеет доступа к Desktop. В stdin передаём приватный FIFO из временного каталога.
    cat "$BLOT_ENV_FILE" > "$channel" &
    writer_pid=$!
    open -n --env BLOT_ENV_STDIN=1 --stdin "$channel" "$1"
    for ((attempt = 0; attempt < 200; attempt++)); do
        if ! kill -0 "$writer_pid" 2>/dev/null; then
            wait "$writer_pid"
            writer_pid=''
            return 0
        fi
        sleep 0.1
    done
    echo 'Blot не принял настройки за 20 секунд. Проверьте журнал запуска macOS.' >&2
    return 1
)
if [[ "$mode" != --build-only ]]; then stop_running_app; fi
export BLOT_SIGNING_IDENTITY="${BLOT_SIGNING_IDENTITY:--}"
xcodebuild -quiet -project apps/Blot.xcodeproj -scheme BlotMac -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
app_bundle="$PWD/.build/xcode/Build/Products/Debug/Blot.app"
# Backend входит в build phase BlotMac; не запускаем приложение с неполными ресурсами.
[[ -s "$app_bundle/Contents/Resources/Backend/blot-backend.jar" && -x "$app_bundle/Contents/Resources/Backend/runtime/Contents/Home/bin/java" ]] || {
    echo 'Backend is missing from the built app. Check the Embed Java backend build phase.' >&2
    exit 1
}
case "$mode" in
    --build-only) echo "Built: $app_bundle" ;;
    --debug)
        if [[ -n "${BLOT_ENV_FILE:-}" ]]; then
            lldb -o 'command script import script/debug_env.py' -- "$app_bundle/Contents/MacOS/Blot"
        else
            lldb -- "$app_bundle/Contents/MacOS/Blot"
        fi
        ;;
    --logs) open_app "$app_bundle"; /usr/bin/log stream --info --style compact --predicate 'process == "Blot"' ;;
    --telemetry)
        bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_bundle/Contents/Info.plist")
        open_app "$app_bundle"
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$bundle_id\""
        ;;
    --verify) open_app "$app_bundle"; sleep 1; pgrep -x Blot >/dev/null ;;
    run) open_app "$app_bundle" ;;
esac
