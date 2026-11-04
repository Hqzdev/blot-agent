#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export BLOT_ENV_FILE="${BLOT_ENV_FILE:-$PWD/.env}"
if [[ -x .build/tools/jdk-25.0.4.1+1/Contents/Home/bin/java ]]; then
    export JAVA_HOME="$PWD/.build/tools/jdk-25.0.4.1+1/Contents/Home"
fi
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$PWD/.build/gradle-home}"
# Keep the challenge key stable across process restarts; never put its value in argv or stdout.
if [[ -z "${BLOT_CLOUD_CHALLENGE_KEY_FILE:-}" ]]; then
    export BLOT_CLOUD_CHALLENGE_KEY_FILE="$PWD/.build/cloud/challenge-key"
    python3 - <<'PY'
import base64, os
from pathlib import Path
path = Path(os.environ['BLOT_CLOUD_CHALLENGE_KEY_FILE'])
path.parent.mkdir(parents=True, exist_ok=True)
try:
    descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
except FileExistsError:
    pass
else:
    with os.fdopen(descriptor, 'wb') as file:
        file.write(base64.b64encode(os.urandom(32)))
PY
fi
export BLOT_CLOUD_DATABASE="${BLOT_CLOUD_DATABASE:-$PWD/.build/cloud/cloud.sqlite}"
exec backend/gradlew --no-daemon -p backend :cloud:bootRun
