#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work_dir="$PWD/.build/workspace-v3-check"
mkdir -p "$work_dir"
# Use Xcode's actual package modules and resource accessors; BlotDesign has bundled assets.
./script/build_and_run.sh --build-only > "$work_dir/build.log" 2>&1
products="$PWD/.build/xcode/Build/Products/Debug"
ditto "$products/BlotDesign_BlotDesign.bundle" "$work_dir/BlotDesign_BlotDesign.bundle"
sources=()
while IFS= read -r -d '' source; do sources+=("$source"); done < <(find apps/macos/BlotMac apps/shared -name '*.swift' ! -name 'BlotMacApp.swift' ! -name 'ContentView.swift' -print0)
swiftc -module-cache-path "$work_dir/cache" -parse-as-library -whole-module-optimization -swift-version 5 -default-isolation MainActor -D DEBUG \
    -I "$products" -I packages/BlotWorkspace/Sources/CSQLite \
    "$products/BlotDomain.o" "$products/BlotAPI.o" "$products/BlotDesign.o" "$products/BlotWorkspace.o" -lsqlite3 \
    "${sources[@]}" scripts/verify-workspace-v3.swift -o "$work_dir/verify"
"$work_dir/verify" "$@"
