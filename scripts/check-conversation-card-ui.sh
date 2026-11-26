#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$PWD/.build/grok-chat-cards/ui"
products="$PWD/.build/xcode/Build/Products/Debug"
app="$products/Ori.app/Contents"
[[ -d "$products/Blot.swiftmodule" && -f "$app/MacOS/Ori.debug.dylib" ]] || {
    echo 'Build BlotMac Debug first with ./script/build_and_run.sh --build-only' >&2
    exit 1
}
mkdir -p "$check_dir"
ditto "$products/BlotDesign_BlotDesign.bundle" "$check_dir/BlotDesign_BlotDesign.bundle"
cp "$app/Resources/Assets.car" "$check_dir/Assets.car"
for locale in en ru; do
    if [[ -d "$app/Resources/$locale.lproj" ]]; then ditto "$app/Resources/$locale.lproj" "$check_dir/$locale.lproj"; fi
done
# Link the exact built implementation; do not compile a second copy of the app or packages.
python3 - "$check_dir" <<'PY'
from pathlib import Path
import sys
output = Path(sys.argv[1])
for source in ['apps/verification/WorkspacePresentationTests/ConversationCardSamples.swift',
               'scripts/verify-conversation-card-ui.swift', 'scripts/verify-mac-chat-interface.swift']:
    path = Path(source)
    (output / path.name).write_text('@testable import Blot\n' + path.read_text())
PY
swiftc -target "$(uname -m)-apple-macos26.0" -module-cache-path "$PWD/.build/xcode/ModuleCache.noindex" \
    -parse-as-library -swift-version 5 -default-isolation MainActor -enable-upcoming-feature MemberImportVisibility -D DEBUG \
    -I "$products" -I packages/BlotWorkspace/Sources/CSQLite \
    "$check_dir/ConversationCardSamples.swift" "$check_dir/verify-conversation-card-ui.swift" "$check_dir/verify-mac-chat-interface.swift" \
    "$app/MacOS/Ori.debug.dylib" -Xlinker -rpath -Xlinker "$app/MacOS" -o "$check_dir/verify"
"$check_dir/verify" "$PWD/.build/grok-chat-cards/screenshots/cards"
