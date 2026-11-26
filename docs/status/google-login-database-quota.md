# Google sign-in: account database quota

18 November 2026. The reported Mac browser login returned “Unable to sign in with Google”.

Subsequently resolved by the user-authorized [new Supabase database release](supabase-account-release.md). The previous Neon quota diagnosis below remains historical evidence.

## Confirmed diagnosis

- The production alias `blot-agent.vercel.app` still points to `dpl_HSSd9U7mmUwRanENeyhrBWRRxMHa`.
- Google web client ID, secret and redirect URI variables are present in Vercel. Their values were not printed or exported.
- The public account endpoint `/v1/auth/me`, without credentials, returns HTTP 503 `auth_service_unavailable`.
- An isolated preview build ran `scripts/check-account-database.mjs` using the existing Vercel database environment. PostgreSQL rejected the connection before any SQL ran: SQLSTATE `53000`, classified message category `quota`. The exact compute/transfer quota was not established.
- Diagnostic deployments: `dpl_DDnXTN71ERo28T7QUMLk5Rbj2ZCf` and `dpl_GVTPazFSBL4MhdEq46mFnMR7s348`. These intentionally stopped at the failed database check. No production alias was changed. An earlier preview, `dpl_4b5aoeTkGwpG1YsuSFaUHbidZFWT`, built the existing release source; its build configuration did not execute the check.

Neon's [plans documentation](https://neon.com/docs/introduction/plans) identifies `53000` as the connection failure when compute or public network transfer allowances are exhausted and the compute is suspended. Restoration requires the allowance reset or an appropriate plan change in the owning organization's billing settings. The investigation did not upgrade a plan, change quotas, replace the database or change existing accounts.

## Local changes and validation

Database initialization now logs only a bounded error code and maps failures to the existing `auth_service_unavailable` error. The Google callback consequently preserves the account-service error instead of labelling an unexpected database exception `google_failed`. Logging excludes exception messages, connection strings and account data. Failed initialization remains retryable.

The read-only deployment check validates connection availability and required account schema columns without querying user records or applying migrations. It is an explicit diagnostic command, not a mandatory build dependency.

`npm run test:auth`: 40 passed, including new shared-initialization/retry and diagnostic redaction checks. `git diff --check` passed. These local changes have not been published to production. Google consent and successful native handoff remain unverified until the database is available.

After restoring the existing Neon database, verify that `/v1/auth/me` without credentials returns the expected HTTP 401 `session_required`, then have the user retry Google sign-in from Blot and verify the native PKCE handoff. Do not create a replacement empty database: existing accounts and chat data must remain attached to their owners.
