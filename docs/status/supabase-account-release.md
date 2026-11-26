# Account service restored on Supabase

18 November 2026. Owning branch: `mac/workspace`.

The user authorized a new empty database and explicitly waived migration of the old account data. Existing Neon data was not deleted. The Vercel project is `landing` (`prj_kUhW84aq7Ygx3w8mLeBCOJxX4YBd`), team `ha1zyys-projects`.

## Configuration

Supabase resource `supabase-citrine-lighthouse` (`dqntfgwnhsrxedipoyts`) is on the Free plan. The user corrected the project connection prefix from `NEXT_PUBLIC` to `BLOT`. The connection now supplies server-only `BLOT_POSTGRES_URL` in Preview and Production. No database password or connection string was retrieved, printed or saved locally. Vercel rejects renaming sensitive variables through its environment API; that failed attempt changed no variables.

The account service and web runtime/migrations prefer `BLOT_POSTGRES_URL`. Legacy `DATABASE_URL`/`POSTGRES_URL` remain compatibility fallbacks. Google continues through Blot's existing OAuth callback and account service; this release does not switch identity handling to Supabase Auth.

Supabase requires its CA for verified PostgreSQL TLS. Both pg and postgres.js use the public Supabase Root 2021 CA, certificate SHA-256 `807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa`. It was obtained from `https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt`; see [Supabase TLS guidance](https://supabase.com/docs/guides/platform/ssl-enforcement). Certificate and hostname verification remain enabled.

The seven public account/session/challenge/backup tables have row-level security enabled with no public row policies, protecting Supabase's public REST schema. Account migrations precede web migrations. The existing seven web migration tags `0000_clean_foundation` through `0006_shared_chat_sync` were applied to the new database.

## Published deployments

| Application | Production deployment | Alias |
| --- | --- | --- |
| Account service and website | `dpl_8Q7GES9yvGjSGgFBCubSJYfyaVEB` | `https://blot-agent.vercel.app` |
| Web application | `dpl_9heoLTLmvbrHNsp6Nep7QLQUx3TJ` | `https://blot-web-ha1zyys-projects.vercel.app` |

Both are READY. Aliases were assigned explicitly after successful builds; automatic custom-domain assignment is disabled so a web build cannot replace the website. Source manifests from the previous published releases were checked against deployment file hashes, then only the focused database connection/TLS/migration changes were overlaid. Unrelated uncommitted client/UI/billing changes were not published.

## Validation

- 43 local account/auth tests, including Google JWT validation, server URL precedence, TLS configuration, row-level security, retry and safe logging.
- 3 local shared chat sync tests and web TypeScript check.
- Local website production build and both Vercel production builds passed. A mistaken pnpm invocation in the npm-managed website attempted dependency installation; `npm ci` restored its locked dependencies before the successful local build. No package or lockfile changes resulted.
- Production build checked the actual Supabase schema, all seven account RLS flags, account session creation and Mac/iPhone PKCE code exchange/replay rejection. A synthetic verified identity was used; the transaction rolled back every test account and token. No user Google consent or email was performed.
- The web build verified actual database message persistence, owner isolation, rate limits, shared Apple/web synchronization and a short live model response. Its temporary test data was removed or rolled back by the existing checks.
- Public `/v1/auth/me` returns expected 401 `session_required` instead of 503. Native login form returns 200 with Google enabled. Web `/api/history` rejects anonymous access with 401, `/api/auth/session` returns 200 `null`; ordinary website login redirects to the existing web sign-in route.
- New web runtime error/fatal logs were empty during the initial checks; `git diff --check` passed.

The user subsequently confirmed successful real Google sign-in and return to Blot on their physical Mac (“Да, вошёл в Blot”). This completes the interactive Mac login validation in addition to the synthetic server checks. Physical iPhone login was not exercised in this release.
