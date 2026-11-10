#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
bundle="${1:?Pass the generated app bundle}"
BLOT_SIGNING_IDENTITY="${BLOT_SIGNING_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY:--}}"
export BLOT_SIGNING_IDENTITY
[ -d "$bundle/Contents" ] || { echo "App bundle is missing" >&2; exit 1; }
# Конфигурация владельца остаётся вне распространяемого приложения.
if [ -n "$(find "$bundle" -type f \( -name '.env' -o -name '.env.*' \) -print -quit)" ]; then
    echo 'Remove .env files from the app bundle before packaging.' >&2
    exit 1
fi
select_java_home() {
    for candidate in "${JAVA_HOME:-}" "$PWD"/.build/tools/jdk-*/Contents/Home \
        "$(/usr/libexec/java_home -F -v 25 2>/dev/null || true)"; do
        [ -x "$candidate/bin/java" ] && [ -x "$candidate/bin/javac" ] && \
            [ -x "$candidate/bin/jlink" ] && [ -f "$candidate/include/jni.h" ] || continue
        if grep -Eq '^JAVA_VERSION="25([.+-]|")' "$candidate/release"; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    echo 'JDK 25 is required. Install it or set JAVA_HOME to a full JDK 25 installation.' >&2
    return 1
}
JAVA_HOME="$(select_java_home)"
export JAVA_HOME
GRADLE_USER_HOME="${GRADLE_USER_HOME:-$PWD/.build/gradle-home}"
export GRADLE_USER_HOME
echo '[Blot] Building Java backend'
backend/gradlew --no-daemon -p backend :api:bootJar
resources="$bundle/Contents/Resources/Backend"
mkdir -p "$resources"
cp backend/api/build/libs/blot-backend.jar "$resources/blot-backend.jar"
python3 scripts/copy-provider-ca.py "$resources/provider-ca.pem"
scripts/build-native-helpers.sh "$resources"
mkdir -p "$resources/native"
# Версия берётся из фактического bootJar, поэтому не дублируется в скрипте.
python3 - "$resources/blot-backend.jar" "$resources/native/libsqlitejdbc.dylib" <<'PYTHON'
import io, pathlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as application:
    libraries = [name for name in application.namelist() if name.startswith('BOOT-INF/lib/sqlite-jdbc-') and name.endswith('.jar')]
    if len(libraries) != 1:
        raise SystemExit('Expected one pinned SQLite JDBC library')
    with zipfile.ZipFile(io.BytesIO(application.read(libraries[0]))) as driver:
        pathlib.Path(sys.argv[2]).write_bytes(driver.read('org/sqlite/native/Mac/aarch64/libsqlitejdbc.dylib'))
PYTHON
scripts/sign-native.sh "$resources/native/libsqlitejdbc.dylib"

runtime="$resources/runtime/Contents/Home"
if [ ! -x "$runtime/bin/java" ]; then
    mkdir -p "$resources/runtime/Contents"
    "$JAVA_HOME/bin/jlink" --add-modules java.se,jdk.crypto.ec,jdk.unsupported,jdk.management,jdk.zipfs,jdk.charsets \
        --strip-debug --no-header-files --no-man-pages --output "$runtime"
fi
echo '[Blot] Embedding Java runtime and native helpers'

# Подписываем вложенный код отдельно; основной App Sandbox остаётся включённым.
find "$runtime" -type f \( -name '*.dylib' -o -perm -111 \) | while IFS= read -r binary; do
    if /usr/bin/file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
        case "$binary" in
            */lib/jspawnhelper) scripts/sign-native.sh --identifier com.blot.backend.spawn --entitlements native/InheritedProcess.entitlements "$binary" ;;
            */bin/java) scripts/sign-native.sh --identifier com.blot.backend.java --entitlements native/JavaRuntime.entitlements "$binary" ;;
            */bin/*) scripts/sign-native.sh --entitlements native/JavaRuntime.entitlements "$binary" ;;
            *) scripts/sign-native.sh "$binary" ;;
        esac
    fi
done

# Debug Xcode может вынести собственный код в отдельные dylib.
for library in "$bundle"/Contents/MacOS/*.dylib; do
    [ -f "$library" ] || continue
    scripts/sign-native.sh "$library"
done
scripts/build-native-executor.sh "$bundle" "${BUILT_PRODUCTS_DIR:-$(dirname "$bundle")}"
scripts/sign-native.sh --entitlements apps/macos/BlotMac/BlotMac.entitlements "$bundle"
codesign --verify --deep --strict "$bundle"
[ -x "$runtime/bin/java" ] && [ -s "$resources/blot-backend.jar" ] || { echo 'Backend packaging is incomplete.' >&2; exit 1; }
echo "[Blot] Backend packaged into $bundle"
