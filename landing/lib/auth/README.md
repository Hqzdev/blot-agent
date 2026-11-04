# Website sign-in and Apple handoff

`/login` supports email registration, verification, password recovery and Google sign-in. `/register` opens registration. The website uses the Java account service; it does not create a separate account database.

## Server configuration

Set these variables in the website's deployment environment. For local development, `next.config.mjs` also reads the repository root `.env`. Values remain server-only.

| Variable | Purpose |
| --- | --- |
| `BLOT_CLOUD_ORIGIN` | HTTPS origin of the Java account service; `BLOT_ACCOUNT_SERVICE_URL` is an alias. Required in production. |
| `BLOT_WEB_SESSION_SECRET` | At least 24 random characters for encrypted browser cookies. The Google web client secret is used when this variable is absent. |
| `BLOT_GOOGLE_WEB_CLIENT_ID` | Google OAuth **Web application** client ID. |
| `BLOT_GOOGLE_WEB_CLIENT_SECRET` | Google web client secret, stored only on the server. |
| `BLOT_GOOGLE_WEB_REDIRECT_URI` | Exact registered callback, `https://blot-agent.vercel.app/auth/google/callback`. |

Google settings are optional for email sign-in. Google sign-in requests only `openid email profile`; Gmail and Calendar permissions are separate. Production has no localhost account-service fallback.

The Java service must provide `/v1/auth/register`, `verify`, `login`, `me`, `password/request`, `password/reset`, `logout`, `browser/code`, `browser/token` and `google/login`. Email verification and recovery require SMTP on that service. `google/login` must verify the Google signature, audience, issuer, nonce and verified email.

## Native contract

The app opens `/login` with `response_type=code`, `client_id`, `redirect_uri`, random `state`, a SHA-256 `code_challenge`, `code_challenge_method=S256` and `intent=login|register`.

| Client | Callback |
| --- | --- |
| `blot-ios` | `blot-agent-ios:/oauth/account` |
| `blot-macos` | `blot-agent-macos:/oauth/account` |

After sign-in, the user selects **Continue in Blot**, then **Open Blot**. The callback carries only a one-time code and the original state. The app exchanges the code and its private PKCE verifier at `/v1/auth/browser/token`. This endpoint is also proxied through the website origin. Session tokens never appear in a callback URL or browser JavaScript.

When opened directly, the signed-in page links to `blot-agent-ios:/oauth/start` or `blot-agent-macos:/oauth/start`. The app starts its own PKCE attempt, then returns through the flow above. Both app URL schemes and the native browser authorization handler must be included in the installed app.

## Validation

Run `node --test lib/auth/browser-session.test.mjs` and `npm run build` from `landing/`. Browser-cookie tampering/expiry, callback restrictions and malformed PKCE requests are covered by the tests. Local integration against the Java service and isolated TLS SMTP has additionally verified registration, verification, password reset, code exchange, replay rejection and independent native sessions. Actual Google consent and the OS opening an installed app require separate device verification.
