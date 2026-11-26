# Google Workspace — 19 November 2026

Scope: macOS and the shared Apple-local Swift runtime. No Java runtime parity or backend deployment is implied.

## Changes

- Fixed the Mac Desktop OAuth flow: its registered client required a client secret, but the old code never supplied one and collapsed the rejection into an expired-session message. A diagnostic using a deliberately invalid code confirmed `client_secret is missing`; with the matching Desktop configuration Google instead rejected only that deliberately invalid code.
- Mac now uses PKCE, the system browser and a state/port/path-bound callback on an ephemeral 127.0.0.1 port. iOS retains its separate native client and custom callback. The downloaded Desktop JSON is referenced from ignored .env; it is not copied into tracked source or the iOS resource. Tokens and refresh configuration stay in the device Keychain.
- Added full-operation cancellation and cancellation checks before publishing agent access. Failed grants restore previous credentials. Added minimal API verification before marking a new connection usable and a Check access button. API-disabled, missing-client-secret, expired-session and scope errors are distinguished.
- Added drive_create: new UTF-8 files up to 32 KiB or explicitly attached artifacts up to 5 MiB, optional writable parent folder, multipart metadata/content, owner review, actual ID and canonical view URL. It does not overwrite files or alter sharing.
- Added real-account discovery before Google action requests. Google argument-schema failures return a corrective result before execution; other providers retain their existing validation behavior. No grant or external operation is executed from a malformed call.
- Fixed remote-operation replay comparing differently escaped JSON strings. It now compares parsed JSON values. Successful uploads replay the recorded result; unknown outcomes are never automatically repeated.

## Verification

- 222 shared Swift tests passed (see .build/google-tests.log). Coverage includes OAuth state/PKCE/loopback binding, native credential isolation, Gmail search/read/draft/send, Calendar list/events/create/etag-update, Drive search/read/create/attachment, denied review, revoked access, disabled API, cancellation, replay and unknown outcomes. HTTP tests use isolated synthetic responses, not the user's mail or calendar content.
- 9 build-configuration tests passed. 168 schema fixtures and shared web/Apple payload checks passed.
- macOS build and launch succeeded on the physical Mac. Generic physical iOS compilation succeeded without a simulator. Actual iOS packaging excluded the Desktop client secret.
- Live Mac Drive: user completed OAuth for the QA agent, the connected account survived application restarts, Check access returned Google API verified, the model obtained the actual account ID, and the owner-review card completed a real 138-byte text upload. A later drive_read returned the exact synthetic text. The QA file was retained for inspection.
- Google Cloud console showed Drive API, Gmail API and Calendar API enabled in the same project. A transient SERVICE_DISABLED response from Drive cleared on a later metadata-only check.
- Live Gmail and Calendar: user completed each separate OAuth consent for QA 18-11 Assistant. Both native connection screens displayed Google API verified after metadata-only checks. No real email was sent and no private mailbox/event content was fed into the model.

## Remaining handoff

The user clarified that documents, tables and presentations must be generated and opened locally inside Blot, without Google. No new Google APIs were enabled. Docs/Sheets/Slides/Contacts/Tasks connections were not granted. The shipped Google service set remains Gmail, Calendar and Drive.

Implementation/configuration details: [Google Workspace guide](../integrations/google-workspace.md).

## Local documents and context compaction

- document_create supports Markdown/PDF documents, CSV tables and 16:9 PDF presentations with structured title/body slides. The PDF writer checks every title and body fits; it never silently clips content. Generation replay is bound to its exact inputs, so changing PDF metadata timestamps cannot cause duplicate files. Files persist as local artifacts, attach to the response and open inside Blot for the currently visible chat. Background chats do not steal focus.
- Local preview renders PDF pages, Markdown blocks and CSV cells, including quoted commas, quotes and multiline Unicode cells. No external browser or Google upload is used.
- The automatic context policy caps compaction at 250,000 estimated tokens, respecting the smaller model window, per-run budget and existing file-context allowance. UTF-8 byte size is intentionally a conservative token estimate, not a provider tokenizer. The installed default GigaChat window is 32,768, so compaction happens earlier.
- Summaries preserve goals, decisions, restrictions, pending work and exact document links/IDs. Recent messages remain in context and original messages are retained. Summary requests are batched below record-size limits; failed summarization does not replace history.

- Live file QA exposed selection of the filesystem plugin for a local CSV request. Local document intent now requires document_create until a real artifact ID is returned; schema repair stays before execution.

- Live Mac local files: the QA agent created a CSV table and a PDF document; each artifact attached to its reply and automatically opened in the internal panel. The CSV cells matched all three requested rows; PDF text matched the synthetic request.

- Live Mac presentation: document_create produced an actual 3-page PDF deck with the requested slide titles and bodies. It attached to the response, opened automatically in the internal panel, and the page counter navigated to slide 2. All three local file tabs remain available in QA 18-11 Assistant.
- Final macOS build/launch and generic physical iOS compilation passed after the local intent fix. No simulator was used.
