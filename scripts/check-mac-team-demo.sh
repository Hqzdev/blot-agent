#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p .build/mac-demo-check/module-cache
xcrun swiftc -parse-as-library -module-cache-path .build/mac-demo-check/module-cache \
    apps/macos/BlotMac/Features/TeamDesign/Domain/*.swift scripts/verify-mac-team-demo.swift \
    -o .build/mac-demo-check/verify
.build/mac-demo-check/verify
