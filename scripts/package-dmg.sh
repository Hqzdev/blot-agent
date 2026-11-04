#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

application="${1:?Pass the built Blot.app path}"
output="${2:?Pass the output DMG path}"
[[ -d "$application/Contents" ]] || { echo 'Blot.app is missing' >&2; exit 1; }
codesign --verify --deep --strict "$application"

builder="$PWD/.build/dmg-venv/bin/dmgbuild"
if [[ ! -x "$builder" ]]; then
    python3 -m venv .build/dmg-venv
    .build/dmg-venv/bin/pip install -r scripts/requirements-dmg.txt
fi
"$builder" -s scripts/dmg-settings.py -D app="$application" \
    -D background="$PWD/assets/dmg/background.tiff" 'Blot 1.0 Beta' "$output"
hdiutil verify "$output"
