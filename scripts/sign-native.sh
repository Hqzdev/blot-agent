#!/bin/sh
set -eu

# Локальная сборка использует ad hoc без Apple-сертификата. App Sandbox задаётся entitlements.
# Hardened Runtime включаем с настоящей identity: он требует Team ID у библиотек JVM/JNI.
identity="${BLOT_SIGNING_IDENTITY:--}"
if [ "$identity" = '-' ]; then
    exec /usr/bin/codesign --force --options 0 --sign - "$@"
fi
exec /usr/bin/codesign --force --options runtime --sign "$identity" "$@"
