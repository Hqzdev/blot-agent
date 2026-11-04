# Website sign-in and Apple handoff

`/login` supports email registration, verification, password recovery and Google sign-in. `/register` opens registration. With `DATABASE_URL`, the account service runs in the website's Node.js Vercel Functions and stores accounts in PostgreSQL. No separately hosted Java service is required.

## Server configuration

Set these variables in the website's deployment environment. For local development, `next.config.mjs` also reads the repository root `.env`. Values remain server-only.

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | Pooled PostgreSQL connection string, injected by the Neon integration in Vercel. Enables the built-in service. |
| `BLOT_CLOUD_ORIGIN` | Optional legacy Java account-service origin; `BLOT_ACCOUNT_SERVICE_URL` is an alias. Used only when `DATABASE_URL` is absent. |
| `BLOT_AUTH_CHALLENGE_SECRET` | Optional independent secret for email-code HMACs. Defaults to a domain-separated key derived from the session secret. |
| `BLOT_WEB_SESSION_SECRET` | At least 24 random characters for encrypted browser cookies. The Google web client secret is used when this variable is absent. |
| `BLOT_GOOGLE_WEB_CLIENT_ID` | Google OAuth **Web application** client ID. |
| `BLOT_GOOGLE_WEB_CLIENT_SECRET` | Google web client secret, stored only on the server. |
| `BLOT_GOOGLE_WEB_REDIRECT_URI` | Exact registered callback, `https://blot-agent.vercel.app/auth/google/callback`. |

Google settings are optional for email sign-in. Google sign-in requests only `openid email profile`; Gmail and Calendar permissions are separate. Production has no localhost account-service fallback.

The built-in service preserves `/v1/auth/register`, `verify`, `login`, `me`, `password/request`, `password/reset`, `refresh`, `logout`, `revoke-sessions`, `browser/code` and `browser/token`. Google identity verification is internal to the website callback and verifies signature, issuer, audience, expiry, nonce and verified email. Set `BLOT_SMTP_HOST`, `BLOT_SMTP_PORT`, `BLOT_SMTP_USERNAME`, `BLOT_SMTP_PASSWORD` and `BLOT_SMTP_FROM` in Vercel for verification and recovery. SMTP requires TLS. Passwords use scrypt; only hashed session tokens and keyed email-code digests persist. Rate limits persist in PostgreSQL across function instances.

The first request applies the additive, idempotent schema in `lib/accounts/schema.sql` under a PostgreSQL advisory lock. The database connection and schema initialization are lazy, so a build does not need database access. Credentials stay server-only.

## Chats and projects

`/v1/workspace/backups` stores account-scoped workspace snapshots in PostgreSQL. Native clients upload bounded 512 KiB chunks, then commit only after the server validates completeness, digest and account/workspace identity. A failed upload never replaces a complete backup. The last two complete snapshots per device remain available, with at most 128 MiB reserved per account and 32 MiB per snapshot. Each request authenticates its account; snapshot IDs alone grant no access.

`WorkspaceCloudBackup` uploads local changes and polls for other devices every 30 seconds, reusing the existing causal merge for offline edits and deletions. Backup contents include chats, messages, project records and other replicated workspace records. File attachments' bytes and device-only preferences/credentials are not included. Transfers use HTTPS; these database backups are readable by the server and are not the end-to-end encrypted peer transport. A new app build is required to enable this client behavior.

## Native contract

The app opens `/login` with `response_type=code`, `client_id`, `redirect_uri`, random `state`, a SHA-256 `code_challenge`, `code_challenge_method=S256` and `intent=login|register`.

| Client | Callback |
| --- | --- |
| `blot-ios` | `blot-agent-ios:/oauth/account` |
| `blot-macos` | `blot-agent-macos:/oauth/account` |

After successful sign-in or email verification, the page automatically issues the native authorization code and redirects to Blot. The same return happens when an authenticated browser session is restored. A retry control is available only as a fallback if the browser blocks automatic app opening. The callback carries only a one-time code and the original state. The app exchanges the code and its private PKCE verifier at `/v1/auth/browser/token`. This endpoint is also proxied through the website origin. Session tokens never appear in a callback URL or browser JavaScript.

When opened directly, the signed-in page automatically opens `blot-agent-ios:/oauth/start` or `blot-agent-macos:/oauth/start`. The app starts its own PKCE attempt, then returns through the flow above. Both app URL schemes and the native browser authorization handler must be included in the installed app.

## Validation

Run `npm run test:auth` and `npm run build` from `landing/`. Tests use an embedded PostgreSQL engine for registration, verification attempt limits, password reset, refresh rotation, persistent rate limits, PKCE replay rejection, atomic backups and account isolation. Swift cloud-backup tests verify multi-chunk transfer, project/chat restoration, offline edits and lost commit-response retries. Actual Google consent, production email delivery and OS app opening require separate device verification.
