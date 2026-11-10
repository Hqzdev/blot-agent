# Parallel groups, device delegation and account deletion

Implemented in the current `mac/workspace` project. MCP and additional external plugins are outside these blocks.

## 5. Parallel group execution

Independent assignments run in structured waves of up to four workers. A plan may contain explicit `dependsOn` agent IDs; invalid references, duplicate IDs and cycles are rejected. A dependent assignment starts only after its prerequisites have a verified completed result. Explicit addressed tasks can derive dependencies from references to another member's result.

Each worker receives its own agent configuration, replies and execution evidence, with the current attachment context preserved. Its token allowance includes execution and verification while respecting the shared group limit. Results merge deterministically after a wave. One failed worker does not discard independent results; failed prerequisites block their dependants. Cancellation and membership changes stop the group. Follow-up work is bounded.

Recorded successful write operations are reused across the same source/configuration's follow-up passes. An unknown external outcome blocks a repeated write; read operations and distinct requests remain available. This prevents repeated known writes, rather than promising exactly-once execution for an external service with an unknown outcome.

## 6. Phone to Mac delegation

Both clients expose real device pairing and trust revocation. Pairing exchanges signed copyable invitation/reply/approval tokens, requires the same owner/workspace and comparison of a six-digit code, and expires after ten minutes. Public peer keys and the pairing nonce are pinned in the installation's credential store. Replicated `Device` records cannot grant execution authority.

The task editor can select a paired Mac for a direct agent conversation. A task proof binds owner, workspace, task and conversation IDs, origin, fixed executor, agent configuration, goal, budget and pairing nonce. It expires after seven days. The receiving Mac verifies the proof before claiming and during model/tool execution. Local tool permissions still apply. The phone does not execute the Mac's task; existing account backup synchronization carries the task and its eventual result. Blot must be running on the Mac to execute it. This block does not add a background daemon or iOS background execution.

Queued/running tasks can be stopped from the originating phone; synchronization interrupts the Mac worker. Revoking trust on the recipient blocks further tasks from that peer and interrupts its active work. Each installation controls its own trust pins; revocation must reach the recipient to stop its work.

Local task admission also requires a private local outbox creation receipt with matching immutable inputs. Terminal local receipts prevent replay even if replicated task/message history is replaced. A cloud record claiming the Mac's origin ID alone cannot start local work. These local admission receipts must be retained if outbox retention is added later.

`contracts/v3/model.json` adds optional `Task.authorizationJSON`; generated Java/Swift models, schemas and fixtures are updated together. Old Task JSON without the field is accepted; Swift omits a nil field and Java retains its previous constructor. New signed tasks require updated Apple clients. No shared Java executor is added: Java receives the compatible DTO, while execution remains in the Apple-local Swift core. SQLite adds an idempotent outbox lookup index and local settings receipts; existing user data is preserved.

## 7. Account deletion

The unified profile's danger zone includes permanent cloud/account deletion, separately from local-only cleanup. A signed-in owner requests an email challenge with purpose `delete`, then confirms its six-digit code. Both Node/PostgreSQL account routes and Java/SQLite cloud routes implement:

- `POST /v1/auth/account/delete/request`
- `POST /v1/auth/account/delete`

The Node route uses foreign-key cascades to remove the account, sessions, challenges, browser codes and workspace backups/parts. Its idempotent schema update permits the new challenge purpose. Java removes the owner's workspace graph, including devices/trust grants, relay data, task assignments/actions, blobs, sessions and model usage, in the confirmation transaction. Invalid codes and another owner's challenge do not delete data. Other accounts survive.

The client joins task/chat workers and stops schedules/synchronization before confirmation. A rejected request resumes those services. After a successful cloud response it writes a durable local cleanup intent, closes the account's SQLite repositories, removes only that owner's local directory and credentials, and clears presentation state. Failed local cleanup resumes on next startup from the intent. Symlink boundaries and live workspace process locks are checked before removal.

External calendar/email/provider content is not deleted. Offline copies on other devices cannot be remotely erased. If the network loses the successful deletion response, the client cannot infer cloud deletion from that failure and does not automatically erase its local copy. The cleanup intent is written after a confirmed response; a crash or disk failure before that write can require local-only cleanup.

These server routes have not been deployed by this task. The published application needs the matching updated account server before cloud deletion is available. No real account was deleted and no real email was sent during validation.

## Verification

- 127 Swift tests passed, including trust expiry/replay, proof tampering, recipient revocation, remote cancellation, local task admission, terminal replay and resumable owner-scoped cleanup.
- Service scenarios passed for actual parallel overlap, prerequisite ordering, independent failure, blocked dependencies and cancellation; signed pairing, two isolated installation repositories, task/result backup synchronization, suspend/resume and persisted revocation.
- Existing group routing, task, schedule, skill and file/OCR service regressions passed with deterministic models and generated fixtures.
- 67 Java tests passed: api 9, cloud 14, application 10 and infrastructure 34. Account deletion tests seed an owner graph, reject the wrong code, remove the graph and preserve another owner.
- 31 Node account/auth tests passed, including backup/part deletion and session invalidation. All 167 contract fixtures and schema/secret-field checks passed.
- Mac and generic physical-device iOS builds succeeded. No app GUI, physical iPhone session, simulator or emulator was launched. Logical phone/Mac service tests do not replace an on-device network/UI check.

Reusable incremental builds are retained. Disposable executables/caches created for the new service checks are removed after validation; free disk space stayed above 20 GiB.
