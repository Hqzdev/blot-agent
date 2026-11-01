#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

BLOT_ENV_FILE="${BLOT_ENV_FILE:-$PWD/.env}"
export BLOT_ENV_FILE
[ -f "$BLOT_ENV_FILE" ] || { echo 'Create .env from .env.example and fill in SMTP and GigaChat settings.' >&2; exit 1; }

if [ -x .build/tools/jdk-25.0.4.1+1/Contents/Home/bin/java ]; then
    JAVA_HOME="$PWD/.build/tools/jdk-25.0.4.1+1/Contents/Home"
    export JAVA_HOME
fi
GRADLE_USER_HOME="${GRADLE_USER_HOME:-$PWD/.build/gradle-home}"
export GRADLE_USER_HOME

# .env читает Java как данные, а не shell. Секреты не передаются в аргументах процесса.
exec backend/gradlew --no-daemon -p backend :api:bootRun
