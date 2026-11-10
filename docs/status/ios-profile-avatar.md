# iOS profile avatar persistence and provider import

The profile editor now waits for a successful local presentation-state write before closing. A failed write stays visible in the editor and can be retried. Saving a photo does not require a nonempty nickname.

`WorkspacePresentationState.profile` is an optional `WorkspaceUserProfile`: nickname, image bytes, avatar source and the imported provider URL. Existing presentation JSON without this field remains readable. The local SQLite database is already scoped to the authenticated account and workspace. The Mac client preserves this optional profile when writing its other presentation settings.

A manually selected photo takes precedence over provider imports. Removing a photo records an explicit removal so the next sign-in does not silently restore it. Imported photos are downloaded without account credentials or cookies, restricted to provider image hosts, bounded to 2 MiB, and resized before being saved. Account changes and manual edits invalidate an outstanding import.

## Shared account API and migrations

`GET /v1/auth/me` adds optional `avatarURL` (HTTPS URL or null). Existing Apple clients ignore additional response fields; the Java server retains every existing account field. Older servers may omit it; the iOS client still saves manually selected photos.

The website account service stores `blot_accounts.avatar_url` through an idempotent additive PostgreSQL migration. Verified Google `picture` and Yandex `default_avatar_id` values feed the field at provider sign-in. Yandex requests `login:avatar` in addition to its existing permissions and ignores placeholder portraits.

The Java cloud service adds nullable `accounts.avatar_url` in SQLite schema version 5 and preserves Google's verified picture claim. No v3 generated model, synchronization record or agent avatar contract changes.

Provider import requires deploying the updated account service and website authorization code, then signing in again to populate the provider URL. Existing Yandex authorizations may need consent for the portrait permission. This change does not deploy services or install a new phone build.

Provider references: [Google OIDC claims](https://developers.google.com/identity/openid-connect/reference), [Yandex user information and portraits](https://yandex.ru/dev/id/doc/ru/user-information).

## Validation

- iOS and Mac builds with no simulator or phone installation.
- Website authentication suite: 30 tests, including provider picture validation, existing-account refresh and additive migration with session retention.
- Java cloud suite: 13 tests, including verified Google pictures and migration from the existing schema.
- `scripts/verify-profile-persistence.swift` checks production presentation state, writer and SQLite: reopen recovery, legacy JSON, account isolation, removal, explicit write failure and successful retry.
