#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
products="$PWD/.build/xcode/Build/Products/Debug"
checks="$PWD/.build/voice/chat"
mkdir -p "$checks/cache"
# Reuse the exact compiled app implementation, excluding only its @main entry.
python3 - <<'PY'
from pathlib import Path
objects=Path('.build/xcode/Build/Intermediates.noindex/Blot.build/Debug/Blot.build/Objects-normal/arm64')
items=sorted(p.resolve() for p in objects.glob('*.o') if p.name != 'BlotMacApp.o')
assert items and all('"' not in str(p) for p in items)
Path('.build/voice/chat/objects.txt').write_text('\n'.join('"'+str(p)+'"' for p in items)+'\n')
PY
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor -module-cache-path "$checks/cache" \
    -I "$products" -I packages/BlotWorkspace/Sources/CSQLite \
    "$products/BlotDomain.o" "$products/BlotWorkspace.o" "$products/BlotAppleIntegrations.o" "$products/BlotDesign.o" "$products/BlotAPI.o" \
    @"$checks/objects.txt" -lsqlite3 scripts/verify-voice-chat.swift -o "$checks/verify"
"$checks/verify"
