# iPhone widgets

Implemented in `ios/widgets`, based on `origin/ios/main`. The editable design remains in `agent.pen`, in the **Blot · iOS · Widgets · Light / Dark** frames.

## Included widgets

| Widget | Family | Tap destination |
| --- | --- | --- |
| New request | Small | New chat with the app's preferred agent |
| Your decision | Small | Conversation with the oldest pending decision |
| Current task | Medium | Active conversation, falling back to the latest conversation |
| Agent team | Medium | Agents; individual avatars open their chats |
| Upcoming runs | Medium | Schedules |
| Workspace overview | Large | Chats; individual rows open their conversations |

The extension supports system light/dark backgrounds and accented rendering. States include signed out, empty data, unreadable data and stale snapshots. It displays the snapshot time instead of claiming a live connection or inventing progress. Approvals and other external actions are performed in the app.

## Data and compatibility

- `BlotWidgets` is embedded only in `BlotIOS`. Minimum iOS remains 26.
- Both targets use `group.yaroslavstrelkov.blot-agent.ios`. The provisioning profiles must authorize this App Group.
- The app writes `WidgetSnapshot.json` atomically with file protection until first device unlock. The extension has no database or credential access. It reads bounded titles, avatar properties, states, pending-decision expirations and upcoming schedule times.
- Snapshot version is 1. Unsupported/corrupt data produces an unavailable state. Leaving the account immediately replaces the cached snapshot with an empty one. Preview stores never publish to the group.
- Changes are coalesced before projection. Identical content avoids disk writes and timeline reloads for a minute; backgrounding flushes pending data. WidgetKit controls actual refresh timing. Requested refresh is at the next cached expiration/run boundary or in five minutes. Foreground application updates republish the next recurring schedule occurrences.
- Deep links use `blot-agent-ios://widgets/...`. Parsing is strict; navigation waits for session restoration and verifies the record still exists. Removed or archived destinations fall back to chats/agents. Existing authentication URL handling is preserved.
- Shared `WorkspaceSnapshot` adds optional `tasks` and `preparedActions` fields populated from the existing local projection. Older saved snapshots still decode. Generated contracts, APIs and databases are unchanged; no migration is required. The existing lifecycle verification project includes the new Swift package.
- Avatar color lookup is shared through `WorkspaceAvatarPalette`; existing named colors are preserved, with additional hexadecimal color support.

## Verification

```sh
swift test --package-path packages/BlotWidgetSupport
swift test --package-path packages/BlotDesign
BLOT_ENV_FILE=/absolute/path/to/.env xcodebuild \
  -project apps/Blot.xcodeproj -scheme BlotIOS -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath .build/widgets-signed -allowProvisioningUpdates build
```

On 2026-11-05: 9 widget-support tests and 24 design tests passed on the physical Mac. The iPhone application and embedded extension built successfully, including provisioning and signatures authorizing their App Group. Production SwiftUI widget views were rendered on the Mac in light/dark appearances and signed-out sizes; these are visual checks, not an iPhone SpringBoard run.

The registered physical iPhone was unavailable. Device installation, the widget gallery, App Group handoff on iPhone and cold/warm tap navigation still need on-device verification. No simulator or emulator was used.

With the connected physical iPhone selected, build/run `BlotIOS`, sign in, then add the six Blot widgets through the Home Screen widget gallery. Check each link, change chat/task data, background Blot and check the published snapshot; sign out and verify private titles disappear. Repeat with light, dark and tinted appearances and large text. Check that expired decisions disappear and a removed chat falls back to the chats list.

## Current-project integration — 2026-11-06

Integrated the widget extension and glass tab bar into the primary `klin-agent` working project, preserving existing Apple integrations, message pins, settings and profile changes. The test-project generator now links both Apple integrations and widget support with distinct Xcode object identifiers. Language publication follows the current language preferences instead of replacing their implementation.

The current project passes the 9 widget-support tests and 24 design tests, and both signed iOS and macOS builds. The iPhone app embeds `BlotWidgets.appex`; both provisioning profiles authorize the same App Group. Installed this current-project build in place on the connected physical iPhone 13 Pro Max and verified that the installed app reports the App Group. Launch was denied because the phone was locked; manual app opening, widget gallery selection and runtime data/deep-link validation remain unverified. No simulator was used. The optional existing schema check could not run because `jsonschema` is absent; this integration does not change contracts or generated schemas.
