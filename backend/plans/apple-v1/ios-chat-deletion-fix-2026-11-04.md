# iOS chat deletion crash

The physical iPhone debugger stopped on an uncaught `NSException`:

> attempt to delete item 2 from section 0 which only contains 2 items before the update

The user reported deleting an agent chat immediately before the crash. The captured main-thread stack enters `UICollectionViewListCoordinatorBase.performUpdates` and `UpdateCoalescingCollectionView.performBatchUpdates` from SwiftUI, then fails UIKit's item-count assertion. This is an aborted list update, rather than a network wait. The original backtrace is saved locally at `.build/ios-chat-lifecycle/original-backtrace.txt`.

## Changes

- `PhoneChatsView` supplies one flat, explicitly identified row collection. Pinned, archive, empty and feedback rows have stable identities alongside agent and conversation rows. Removing the last conversation can replace it with an empty-state row without changing the structure of nested dynamic list builders. Feedback is wrapped in one stack and included only when present; its nested conditional error/notice views cannot change the number of list rows implicitly.
- Conversation ordering has a UUID tie-breaker when update timestamps match.
- Pin animation applies to the horizontal pinned strip, rather than the whole UIKit-backed list.
- Each phone route has its own view identity, so chats and agents do not reuse one list coordinator while their row types change.
- Unchanged interaction metadata and mutation snapshots no longer cause additional observable updates and presentation-state writes during response streaming.

## Verification

The signed `BlotIOS` Debug build succeeds. The isolated UIKit regression test mounts the production `WorkspaceRootView`, deletes pinned and last chats, removes the final archived row, and repeatedly switches between chats and agents. It uses an in-memory preview store and a separate test-host bundle; it does not delete the user's chats.

Run on an unlocked connected iPhone:

```sh
python3 scripts/check-ios-chat-lifecycle.py --device-udid <device-udid>
```

Physical-device verification passed on iPhone 13 Pro Max / iOS 27.2: one lifecycle test, zero failures, 4.704 seconds. It covers active pinned-chat deletion, deleting the final archived conversation, empty-state rendering, simultaneous error/notice rendering and removal, and eight round trips between agents and chats. The first test run exposed incorrect fixture assumptions (all initial pins were archived, and absent feedback contributes no row); the test now explicitly prepares active pinned chats and checks UIKit's actual row counts.

Result bundle: `.build/ios-chat-lifecycle/DerivedData/Logs/Test/Test-BlotWorkspaceVerification-2026.11.04_14-33-08-+0500.xcresult`.

This verifies list lifecycle updates. It does not establish a cause for every reported delay in the signed-in application's other screens; those require reproduction if they persist.

The final signed app was installed successfully over the existing bundle. Launching the product after installation was denied by iOS with `FBSOpenApplicationErrorDomain Code=7 / Locked`; the phone must be unlocked before the signed-in application can be exercised. The successful lifecycle test ran in the separate verification host.
