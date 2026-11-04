# Automatic website return and Mac account storage

The user reported that the Mac browser sign-in page closed but the account never appeared, and requested immediate return after successful registration without a second app-opening step.

## Confirmed native cause

The app received the browser callback, then failed in the token-exchange stage while clearing/replacing the account credential. A synthetic check inside the actual Apple Development-signed Blot bundle reproduced `WorkspaceCredentialError.unavailable(-34018)`. The bundle had sandbox entitlements but no Data Protection Keychain identity/profile.

Adding a private Keychain group would require a Mac App Development provisioning profile; Xcode could not provision one because no Apple account was available in its Accounts settings. No restricted entitlement was left in the app and sandboxing remains enabled.

The Mac credential implementation now uses the system login Keychain with application ACLs. iOS continues to use device-only Data Protection Keychain attributes. Credentials remain in Keychain and are excluded from workspace snapshots. This follows the platform distinction described in Apple's [TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains); the two implementations have different access-control models.

`./script/build_and_run.sh --verify-keychain` launches a separate diagnostic instance of the real signed bundle, using a random test service/value. It checks missing-item removal, write, readback, removal and final absence. It never reads an account credential. The result is emitted through stdout into `.build/mac-keychain-verification.json`.

Before: `.build/mac-keychain-before.json` reports `passed: false`, OSStatus `-34018`.

After: `.build/mac-keychain-after.json` reports `passed: true`.

Mac welcome now shows sign-in progress and errors, so a post-browser failure cannot silently return to an unchanged screen. Native diagnostic events record stages and numeric system/HTTP errors, never callbacks, email addresses, codes or tokens.

## Website behavior and deployment

After email verification, password login, Google return or restoration of an authenticated browser session, the page automatically prepares a one-time PKCE code and navigates to the native callback. Direct website registration automatically starts the app's own PKCE flow. An explicit retry control is available if the browser blocks external app navigation; OS/browser confirmation is still controlled by the system.

The handoff controller coalesces concurrent attempts, rejects expired or mismatched callbacks, and leaves the page available on failure. No session tokens appear in navigation URLs or browser JavaScript.

The four-file website patch was committed over the current published base `2d17b2cd4a22c317f6ab1f93200268bfcc35c537`, on branch `codex/automatic-app-login`, commit `ef5f7382aefc1c157bce04378fcf55d681a42b94`. The user explicitly approved sending these files to Hqzdev/kiln-agent and publishing the existing Vercel project.

Production deployment `dpl_4BgCnHsKtD24JHcWPZD1FCSWbe6v` reached READY and owns `blot-agent.vercel.app`. Public `/login` and its served JavaScript were checked for the new automatic return behavior.

## Verification

- 15 website authentication/PostgreSQL/handoff tests pass.
- Clean production website build passes in an isolated worktree based on the published version.
- 47 Swift workspace/session/PKCE/storage tests pass.
- Signed Mac Keychain check fails before the correction and passes after it.
- Final Mac app builds and launches through the standard script.

Full sign-in to the user's existing account still requires completing the interactive browser login. At preparation time the user was asked to do that in the updated Mac app; the synthetic Keychain check does not count as account-login acceptance.
