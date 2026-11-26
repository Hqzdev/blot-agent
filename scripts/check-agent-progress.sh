#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_root="${1:-$PWD/.build/xcode}"
products="$build_root/Build/Products/Debug"
checks="$PWD/.build/agent-progress/harness"
mkdir -p "$checks/cache"
python3 - "$build_root" <<'PY'
from pathlib import Path
import sys
objects=Path(sys.argv[1])/'Build/Intermediates.noindex/Blot.build/Debug/Blot.build/Objects-normal/arm64'
items=sorted(p.resolve() for p in objects.glob('*.o') if p.name != 'BlotMacApp.o')
assert items and all('"' not in str(p) for p in items)
Path('.build/agent-progress/harness/objects.txt').write_text('\n'.join('"'+str(p)+'"' for p in items)+'\n')
PY
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor -module-cache-path "$checks/cache" \
    -I "$products" -I packages/BlotWorkspace/Sources/CSQLite \
    "$products/BlotDomain.o" "$products/BlotWorkspace.o" "$products/BlotAppleIntegrations.o" "$products/BlotDesign.o" "$products/BlotAPI.o" \
    @"$checks/objects.txt" -lsqlite3 scripts/verify-agent-progress.swift -o "$checks/verify"
"$checks/verify"
