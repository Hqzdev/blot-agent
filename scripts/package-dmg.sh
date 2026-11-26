#!/usr/bin/env bash
set -euo pipefail

application="${1:?Pass the path to the built Ori.app}"
output="${2:?Pass the output DMG path}"
volume="${3:?Pass the volume name}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

codesign --verify --deep --strict "$application"
environment="$root/.build/dmg-venv"
if [[ ! -x "$environment/bin/dmgbuild" ]]; then
    python3 -m venv "$environment"
    "$environment/bin/python" -m pip install -r "$root/scripts/requirements-dmg.txt"
fi

"$environment/bin/dmgbuild" -s "$root/scripts/dmg-settings.py" \
    -D app="$application" -D background="$root/assets/dmg/background.tiff" "$volume" "$output"
hdiutil verify "$output"
