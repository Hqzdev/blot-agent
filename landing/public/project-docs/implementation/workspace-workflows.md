# Workspace workflows: implementation and setup

Updated 18 November 2026. Owning platform: macOS; shared Apple code also compiles for iOS. Enterprise dashboard is excluded from this scope.

## Implemented paths

| Scenario | Entry point | Persisted behavior |
| --- | --- | --- |
| Routines | Schedules → Edit / Delete | Optimistic versions; enable/pause, recurrence, timezone, missed runs; deleting a routine preserves prior runs/tasks |
| Custom Rules | Privacy → Rules | Personal ask-first/automatic rules scoped to tool, resource and agent; purchases and Gmail sending retain mandatory review |
| Memory review | Memory → Accept / Reject | Candidates are excluded from context until accepted; rejecting a candidate does not forget its source message |
| Memory import | Memory → Import | Copyable export prompt for another assistant, pasted facts, editable preview and selection; original input retained as source artifact |
| Website purchases | Agent browser tools | Visible pointer, pause/takeover, validated order card, approve/deny, exact document and page-content binding before payment click; bank confirmation is manual |
| Teach a task | Skills → Teach a task (Mac) | Select running app; record supported accessible buttons and ordinary text values; timer, pause, step review/edit/remove; saved recording artifact plus runnable skill |
| Taught task execution | Skill → Run | Owner approves recorded sequence; ambiguous/changed targets or application switching stop it; no automatic retry; iPhone can inspect/edit recorded steps and request execution on a paired physical Mac |
| Vault | Privacy → Vault | Owner-scoped device Keychain; login, contact, API secret and tokenized-card reference; CSV import; optimistic item versions |
| 1Password | Catalog → 1Password | Authenticate to an HTTPS Connect Server, select permitted vaults, import chosen logins into device Vault; passwords do not enter model output |
| Google services | Catalog → Gmail / Calendar / Drive | Native PKCE OAuth, Keychain refresh tokens, account/agent assignment, direct Google APIs; mail search/read/draft/send, calendar discovery/list/create/update, Drive search/text/export |
| Remote MCP services | Catalog → Notion / GitHub / Airtable / Asana / Granola | Official endpoints; discovery, PKCE OAuth or supported bearer/header credentials; choose actual server tools and assigned agents |
| Slack / Teams | Catalog → service | Native public-client PKCE OAuth; Slack can also use an owner-provided bot token; direct channel/message APIs, reviewed sending |
| Team Bot Manage | General or Privacy → Team Bots Manage | Server teams, verified-email invitations, owner/admin/member roles; versioned bot configuration, assigned physical desktop, channel triggers and allowed tools |
| Team Bot runtime | Blot running on selected Mac | Polls configured channels every 65 seconds, creates channel-isolated tasks, excludes personal memories, limits tools, adds owner review for changes; final reply returns to originating thread with a durable send claim |
| Pages / Library | Files → Pages and Library | Text/table/metric/link blocks, search, table filters, pins, archive/restore, immutable version history and conflict resolution; page_list/read/create/update tools and inline result cards |
| Sharing | Page / Skill → Share snapshot link | Explicit immutable publication, expiration 1–90 days, owner revocation and escaped public HTML; source history/chat/credentials are excluded |
| Marketplace skills | Skills → Marketplace | Reviewable bundled templates, install, JSON import/export, expiring publication; installation never grants tools or assignments |
| Composer skills | Composer attachment menu → Skills | Search installed skills, supply parameters, choose agent/revision/device and run |
| Billing | Usage → Billing | Current plan, monthly prices, owner-scoped payment history with test labels, web checkout, cancel to Free; YooKassa remains test-only |
| Updates | Settings → Updates | Installed version/build; Stable/Beta; fetch explicitly published release metadata and open its HTTPS download page |

## External setup still required

Slack and Microsoft apps have not been registered, as confirmed by the owner. No external accounts have been authorized during development. Implemented adapters are not evidence of a completed live provider test.

The new cloud endpoints and web Billing endpoint must be deployed before those features work against the hosted service. This implementation does not silently deploy backend changes or pretend an old server supports new routes. Native features continue working locally when cloud collaboration is unavailable.

### Slack

1. Create a Slack app in the test workspace. Enable PKCE/public client.
2. Register `blot-agent-macos:/plugins/slack` and `blot-agent-ios:/plugins/slack`.
3. User scopes: `channels:read`, `groups:read`, `channels:history`, `groups:history`, `chat:write`, `search:read`, `users:read`.
4. Set public `BLOT_SLACK_CLIENT_ID` before building, or enter the client ID in the native connector.
5. Native PKCE grants act as the signed-in user. Slack does not allow bot scopes on native redirects. For a distinct bot identity, install a bot in the workspace and connect its `xoxb-` token in the SecureField; invite it to each selected channel. Never put a client secret in the native app.
6. Team Bot channel configuration uses the connector UUID shown in settings, Slack workspace ID, channel ID and a nonempty trigger such as `<@BOT_USER_ID>`.

Sources: [Slack PKCE](https://docs.slack.dev/authentication/using-pkce/), [OAuth installation](https://docs.slack.dev/authentication/installing-with-oauth/).

### Microsoft Teams

1. Register an Entra app supporting work/school accounts and public desktop/mobile authorization.
2. Register `blot-agent-macos:/plugins/teams` and `blot-agent-ios:/plugins/teams` as native redirects; enable the public-client flow.
3. Delegated scopes: `User.Read`, `Team.ReadBasic.All`, `Channel.ReadBasic.All`, `ChannelMessage.Read.All`, `ChannelMessage.Send`, `offline_access`. Tenant consent may be required.
4. Set public `BLOT_TEAMS_CLIENT_ID`, or enter it in the connector. Sign in on the Mac that executes the bot.
5. Configure connector UUID, Microsoft team ID, channel ID and trigger in Team Bot Manage.

This adapter posts as the signed-in Microsoft user. It is not an Azure Bot Framework app or a separately installed Teams bot identity. Such an identity needs its own Azure registration and deployment.

Sources: [Microsoft PKCE flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow), [Read channel messages](https://learn.microsoft.com/en-us/graph/api/channel-list-messages?view=graph-rest-1.0), [Send channel messages](https://learn.microsoft.com/en-us/graph/api/channel-post-messages?view=graph-rest-1.0).

### Google

Enable Gmail, Calendar and Drive APIs in the existing Google Cloud project. Configure native macOS/iOS clients using the existing `BLOT_GOOGLE_MACOS_CLIENT_ID` / `BLOT_GOOGLE_IOS_CLIENT_ID` build inputs. Add test users to the OAuth consent screen. Each service requests its own scopes and requires explicit account authorization. Public distribution with Gmail restricted scopes may require provider review; a working test-user login does not establish public verification.

[Google sending format](https://developers.google.com/workspace/gmail/api/guides/sending), [Calendar events](https://developers.google.com/workspace/calendar/api/v3/reference/events/insert), [Drive export](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/export).

### MCP and 1Password

Official MCP endpoints are preset in the catalog. Dynamic registration works only where offered. Providers that require registration need their registered client ID; a provider rejection remains a failed connection, not a simulated connected state. GitHub additionally supports its documented PAT setup. Generic MCP supports custom headers and local stdio on Mac.

1Password needs an existing account, running Connect Server and scoped Connect token. The UI accepts HTTPS only. [Connect requirements and API](https://developer.1password.com/docs/connect/connect-api-reference/).

## What can be tested without buying an API subscription

Provider quotas and eligibility were checked against official documentation on 18 November 2026. Free account availability does not mean every remote MCP tool is free or unlimited.

| Plugin | Test access |
| --- | --- |
| Apple apps, Pages, Routines, Rules, Vault, Teach | Local features need no external service API key; macOS system permissions still apply |
| GitHub | Free account plus appropriately scoped PAT; [authentication and rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) |
| Gmail / Calendar / Drive | Google account and Cloud project with test users; check the current per-project quotas, including the 2026 changes: [Gmail limits](https://developers.google.com/workspace/gmail/api/reference/quota) |
| Slack | Own development workspace/app; Free workspaces allow up to 10 custom/third-party app installations; [Free limitations](https://slack.com/help/articles/27204752526611-Feature-limitations-on-the-free-version-of-Slack) |
| Airtable | Free workspace quota: 1,000 API calls/month; [limits](https://support.airtable.com/articles/7735693959-managing-api-call-limits-in-airtable). MCP access is still subject to provider consent/tool availability |
| Asana | Free domains have API quota of 150 requests/minute; registration is needed for its MCP OAuth integration; [API limits](https://developers.asana.com/docs/rate-limits) |
| Granola | Basic includes MCP and its last 30 days of notes; [official description](https://www.granola.ai/blog/granola-mcp-claude-chatgpt-cursor) |
| Notion | Connect using the workspace's available MCP permissions; some tool/plan capabilities and enterprise approved-client policies can restrict access; [Notion MCP](https://www.notion.com/help/notion-mcp). No blanket claim that every tool is free |
| Teams | Work/school tenant with Teams entitlement; eligible members can request a Microsoft 365 developer subscription, not every account qualifies; [Developer Program](https://learn.microsoft.com/office/developer-program/microsoft-365-developer-program) |
| 1Password | Existing account/Connect or a provider trial; no perpetual free API tier is promised |
| Generic MCP | Depends on the chosen server; a local stdio server can be tested without a hosted subscription |

QuickBooks, Freshdesk, Beehiiv, Composio, Zapier, Adobe, Atlassian and Loom retain catalog entries. They are not presented as authenticated, working built-in integrations without a real connector/account. A service-supported MCP server can be added through generic MCP.

## Cloud/API compatibility and deployment

- SQLite cloud schema advances from 5 to 6; new collaboration/publication tables do not replace existing account/device/sync data. Account deletion cascades through the new owner/member records.
- Additive API prefix `/v1/collaboration`: teams, members, email-bound invites, bots with expected versions, publications and anonymous token read/share routes. Team members can read team configuration; only owner/admin can manage it. Bot execution credentials remain device-local.
- Public shares contain an explicitly published snapshot in plaintext on the cloud server. They are not the encrypted private workspace backup. Links are random, stored as hashes, expiring and revocable; HTML escapes content and disables scripts/frames.
- Public `/v1/releases/latest?platform=macos|ios&channel=stable|beta`: returns 204 until deployment config publishes metadata. Set `BLOT_RELEASE_<PLATFORM>_<CHANNEL>_JSON_FILE` to a file containing `version`, integer `build`, `minimumOS`, HTTPS `downloadURL`, `notes`, ISO-8601 `publishedAt`. Native clients open the advertised download page; they do not replace installed binaries automatically.
- Web Billing adds `getPaymentHistory` RPC and `/app/api/billing/overview`. Native bearer authorization resolves the existing Blot account; it does not create a second user. Provider payloads and confirmation secrets are excluded from history. Deploy the Billing service and web gateway together.
- Swift signed task delegation adds optional `skillRevisionID` with proof domain `BLOT-TASK-DELEGATION-3`. Existing task proofs remain domains 1/2. Older clients safely reject the new proof; update both Apple clients for remote skill execution. Shared Java source transfer does not implement this Apple-local executor on Android/Windows.
- Pages/recordings use existing immutable artifacts; no new replicated record kind is introduced. Purchase/Page card variants have text fallback for older viewers. Personal rules and team task policies use typed existing grant records; they never expand underlying tool permissions.
- Vault remains device-local Keychain storage. No cloud/team Vault synchronization is claimed. Raw card PAN/CVC, passwords and API secret values do not belong in chat cards or model tool results.
- Teach records supported accessibility controls and ordinary text values, not arbitrary gestures, hotkeys, video or secure fields. The private signed executor needs macOS Accessibility permission. No simulator is needed or used.
- Team polling runs while the selected Mac is awake and Blot is open. New channels begin at activation time; old history is not replayed automatically. Unknown delivery outcomes are not resent; verify the external thread first.

## Validation evidence

Logs are project-local under `.build/workflows-*.log`. Builds use `.build/xcode` and `.build/ios`; Swift tests reuse `.build/swift`. No simulator or runtime download is part of validation. Live OAuth, merchant/bank payments and external Slack/Teams messaging require owner accounts and provider registrations; unit fixtures do not substitute for those checks.

Latest local validation: all 201 Swift core tests passed, including the purchase-flow regression test. Two real WebKit/session tests passed on the Mac, including secret-field exclusion from order review. Java core/cloud checks passed (20 cloud tests); Billing's five focused unit tests, TypeScript typecheck, seven Apple build-configuration tests and 168 schema fixtures passed. Production SwiftUI rendering captured all 13 card types plus 42 chat-layout frames. The purchase amount/monthly-label and saved-page status issues found in those frames were corrected and rendered again.

Mac process launch succeeded, but the CUA service returned `cgWindowNotFound` for the main app window. Manual interaction with the live account window is not recorded as passed. iOS was compiled for a generic physical-device destination with signing disabled; no iPhone installation or simulator run was performed.
