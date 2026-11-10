#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
products="$PWD/.build/xcode/Build/Products/Debug"
checks="$PWD/.build/verify-chat-performance"
mkdir -p "$checks/cache"
sources=(WorkspaceSnapshot WorkspaceMessagePresentation WorkspaceMessageIndex WorkspaceTranscriptWindow WorkspaceChatPresentation WorkspaceMessagePluginAttribution ApplePluginIcon)
arguments=()
for source in "${sources[@]}"; do arguments+=("apps/shared/WorkspaceV3/$source.swift"); done
text_root="$PWD"
if [[ "${1:-}" == --baseline ]]; then text_root="$PWD/.build/chat-performance-baseline"; fi
if [[ "${1:-}" == --scroll-baseline ]]; then text_root="$PWD/.build/chat-scroll-baseline"; fi
arguments+=("$text_root/apps/shared/WorkspaceV3/WorkspacePluginReference.swift" "$text_root/apps/shared/WorkspaceV3/WorkspaceMessageText.swift")
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor -module-cache-path "$checks/cache" \
    -I "$products" -I packages/BlotWorkspace/Sources/CSQLite \
    "$products/BlotDomain.o" "$products/BlotWorkspace.o" "$products/BlotDesign.o" "$products/BlotAppleIntegrations.o" -lsqlite3 \
    "${arguments[@]}" scripts/verify-chat-performance.swift -o "$checks/verify"
"$checks/verify"
