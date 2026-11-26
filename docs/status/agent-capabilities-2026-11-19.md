# Agent capabilities — 19 November 2026

The Apple-local workspace now exposes plugin setup and reusable skill creation in chat. This applies to the shared Swift runtime used by macOS and iOS; it does not implement the same runtime in the Java clients.

## Plugin setup

- `plugin_catalog(query?)` reports catalog metadata and access granted to the requesting agent on this device.
- `plugin_connect(plugin_id, reason)` creates a `connectionRequest` conversation card and waits for the owner's decision. The card opens the existing Apple, Google, messaging or MCP setup flow for that plugin and preselects the requesting agent.
- The owner chooses the account, resources and grants. Both the UI and the tool independently check access before accepting `connected`; displaying or dismissing setup does not grant access. A dismissed request returns `dismissed`.
- Live tool definitions and assignments refresh between model turns. Newly authorized tools can be used in the same reply while keeping the original task scope. Background tasks cannot expand their pinned permissions or open connection cards.
- Unsupported catalog entries are reported as unavailable, rather than pretending an integration exists. Provider registrations and credentials remain prerequisites for their real setup flows.

The new card uses the existing open `kind`/JSON payload fields; generated contracts are unchanged. Older clients can display the fallback text but cannot complete this new setup card.

## Skill Creator

Every existing agent has `skill_list`, `skill_read`, `skill_create` and `skill_run`, even before it has saved skills. Skill Creator also appears in the skills UI.

`skill_create` accepts `name`, `instructions`, `parameters: [{name, required}]` and `tool_ids`. It saves a normal versioned skill and assigns it only to the calling agent. Text-only skills use an empty tool list. Creation never grants external tools or executes the skill. Invalid requirements or templates return a corrective tool result. Read-only user restrictions still apply.

`skill_read` returns the complete assigned revision; `skill_read(skill-creator)` returns the built-in guide. `skill_run` expands declared parameter values into an immutable queued task. A queued task is not a completed result. Replaying a creation call does not restore an assignment revoked by the owner.

Explicit skill/setup requests bootstrap through real function calls. Ordinary prose such as “saved” cannot satisfy a required call. Named skill reuse discovers the saved skill before reading and running it.

## Appearance

The macOS footer profile circle and Connect apps capsule use opaque matte surfaces with subtle borders. Connect apps shows the Notion and Google Drive logos from the light Grok reference. The iOS chat-list profile button uses the same matte treatment. Other chat chrome retains its existing appearance.

## Validation

- Shared Swift suite: 208 tests passed, including real repository persistence, idempotency, access denial, spoofed connection responses, cancellation, live tool refresh and rejection of model promises without tool calls.
- Schema validation: 168 fixtures passed; shared web/Apple payload checks passed.
- macOS app built and launched on the user's physical Mac. Shared iOS code compiled for generic physical iOS; no simulator was used.
- Real GigaChat UI: `skill_list` and `skill_create` succeeded; the saved QA summary skill appeared in the library with its parameterized instructions. A later chat request completed `skill_list`, `skill_read` and `skill_run`, queuing the saved skill. Queue acceptance is verified separately from task completion.
- Real GigaChat UI: a Google Drive connection request appeared inline. Closing unsuccessful OAuth setup left it pending; choosing Not now changed it to Dismissed, stopped the tool and produced a refusal acknowledgement. No Google access was granted by the verification.
- Initial live runs exposed HTTP 422, a model-invented tool requirement and a timeout. Mandatory turns now send only the selected function, and invalid skill requirements return corrective results. The final create/read/queue and connection/dismissal runs succeeded. This does not claim that all provider errors are eliminated.

## Card demonstration

macOS Go → Agent card examples opens a separate in-memory Blot chat containing all 14 production card types: question, connectionRequest, plugin, credential, email, mailFailure, slack, command, takeover, cookies, purchase, subscription, page and task. The window uses the light theme. External-action buttons are disabled; no account services, credentials or working conversations are attached to its preview store.

The gallery window was opened on the physical Mac and all 14 card types were verified through the native UI, including disabled action controls. It was left open at the beginning of the chat for review.
