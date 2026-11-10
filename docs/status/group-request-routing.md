# Group request routing

The task branch builds the group conversation, specialist and team paths without importing unrelated pending Apple-integration changes from the open Mac working copy. It depends on `ios/group-chat-identity` for the previously verified group header components.

- Complete social messages bypass the planner; other requests use a validated mode decision. Malformed mode JSON falls back to an ordinary coordinator response rather than a user-facing plan error.
- Specialist mode invokes only the selected member.
- Team mode assigns only relevant members. The coordinator posts and pins the plan; live member replies can hand work to a named colleague, with a bounded second turn per member. Stored reply and mention metadata links the real messages.
- A completed conclusion removes its own pin. Failure, cancellation, a blocked conclusion, remaining work, or a failed tool result leaves the plan available.
- Pins use account-local SQLite settings; no v3 DTO/schema change. New response relation commands preserve the existing Message fields and validate same-conversation, earlier-message targets.
- Tool-free generation cannot expose tools. Instructions distinguish social conversation, concrete work and genuinely blocking clarification.

## Apple integration in the open project

The open `mac/workspace` copy already contains an uncommitted Apple integration adapter and contract extensions absent from `origin/ios/main`. Those unrelated sources were preserved and were not copied into this task branch. `docs/patches/group-apple-access.patch` records only this task's focused changes against that adapter: preserving tool IDs/model on edit, restoring tool IDs from existing authorized connection assignments, and adding accurate per-agent access context. These changes are already applied in the open project and were built and tested there.

The patch is for the corresponding existing adapter baseline, not a replacement implementation of the pending Apple feature. Baseline SHA-256 hashes:

```json
{
  "apps/shared/WorkspaceV3/LocalWorkspaceService.swift": "730c705cea56547c26a561d54d3f55abb410a7eb3229f81eddc08d5cf6734dc5",
  "apps/shared/WorkspaceV3/WorkspaceStore.swift": "86c6df2d317d751108fa30a9d20fff85e7eaa7747fce037ef31c3f9ccd675861"
}
```

Validation in the open project: iOS and Mac builds, 67 BlotWorkspace tests, 13 Apple adapter tests, and `scripts/verify-group-routing.swift` using the real application pipeline with an isolated SQLite workspace and scripted model. The latter checks greeting, specialist, team document generation, real mentions/replies, pin lifecycle, blocked completion and malformed-router fallback. No live model, signed-in account, simulator or phone installation is needed for that check.

Run the end-to-end check against already-built Mac products: `scripts/check-group-routing.sh /absolute/path/to/Build/Products/Debug`. It does not build, launch, install or use a simulator.
