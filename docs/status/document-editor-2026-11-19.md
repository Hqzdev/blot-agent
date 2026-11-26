# Local document editors — 19 November 2026

Scope: shared Apple-local Swift runtime, macOS and iOS UI. Google document APIs are not used.

- Generated PDF/Markdown documents, CSV tables and PDF slide decks have editable structured sources. Existing generated PDFs/decks recover their exact source from recorded document_create calls. Plain UTF-8 and CSV imports are editable; arbitrary imported PDFs/images keep their original viewer.
- Saving creates an immutable rendered Artifact and a JSON source revision with a stable document ID, parent revision and export ID. It never changes original artifact hashes or binary paths. Existing encrypted artifact sync/backup carries the revisions; older clients can still read original attachments. No generated v3 model/schema change is required.
- Source/render records commit in one transaction after bytes are durable. Repeated commands return the saved revision; stale heads and modified command replay are rejected. Original files stay intact. Concurrent/offline branches produce a conflict rather than a silent overwrite.
- App editors support text, table cells/rows/columns, slide titles/bodies, adding/removing/reordering slides, Save/Command-S, Revert and draft preview. Preview does not publish artifacts. Drafts remain in the current account's app session when switching tabs; explicit Save persists them across app restarts. Conflicts retain the draft and provide loading the latest version and restoring the user's draft.
- Assistant attachments render rounded document cards with type, title, content excerpt and Open and edit. Cards resolve the latest saved source. Internal source/render artifacts are omitted from the normal Files list. File tabs encode the stable file ID for restoration.

Validation:

- 227 shared Swift tests passed, including source recovery, all three render types, save replay, stale-save rejection, failed-edit rollback, preview isolation and reopening the repository.
- 168 schema fixtures and existing shared web/Apple payload checks passed.
- Live Mac: edited/saved a CSV cell (12000 to 15000), a PDF document body, and slide 2 of a 3-slide deck. Save returned to Saved, and table/PDF previews displayed the changed content. Only existing synthetic QA files were used.
- Generic physical iOS compilation passed; no simulator was used. Mac restart verification passed: CSV 15000, the appended PDF text and the edited second slide were reopened from persisted revisions.

- Card layout was checked in the narrow chat column: file title is on its own line, preview and type are visible, and the full card opens the editor.

Final build logs: .build/document-editor-macos-build.log and .build/document-editor-ios-build.log. Mac was left running with the QA presentation editor and its readable chat card open.
