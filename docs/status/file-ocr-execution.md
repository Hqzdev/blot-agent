# Files and OCR in the Apple workspace

Implemented in the current `mac/workspace` project. No public v3 DTO/schema changes and no Java OCR executor are introduced.

## Import and reading

- Import UTF-8 text/source files, JSON/CSV/TSV, PDF, PNG, JPEG, HEIC/HEIF, TIFF and WebP. Original bytes are retained in the existing content-addressed store. Source paths never enter replicated metadata.
- Scanned and blank PDFs can be imported without a text layer. Validation rejects damaged/password-protected PDFs, documents over 1,000 pages, invalid images and images over 100 megapixels. Existing 32 MiB file limits remain in effect.
- Read a native PDF text layer first; rasterize and recognize only pages without text. Recognize images using Apple Vision on the device, with installed recognition languages and automatic language detection. Raster dimensions are bounded. No external OCR service is used.
- `WorkspaceFileService.read` returns content, requested starting page, document page count, next page, OCR provenance and truncation. Reads cover at most 20 pages and 48,000 characters; callers can request a later page range. A single very dense page may still require opening the original for full content.
- OCR results are a disposable local cache keyed by source hash, media type, extraction version and page range. Originals are checked for size/hash/ownership before every read, including cache hits. Invalid cache entries are regenerated. Caches are not replicated; another device recognizes its downloaded original locally.
- Cancellation is checked during reads and between recognition/pages. A synchronous Vision request already in progress finishes before cancellation is observed; it never commits a canceled result to the cache.

## App integration

- Both file libraries have an import action. The file viewer retains original preview/share actions and displays recognized text, OCR provenance and page navigation. Empty/unreadable scans display a specific explanation while keeping the original available.
- Chat attachment context uses the same extractor. A failed file does not abort the whole response. A system policy distinguishes untrusted document content from the user's actual request, which remains a separate final user message. Extracted text is sent to the configured chat model under the existing attachment flow.
- `file_read` still requires an explicit attachment on the current source message. It accepts optional `start_page` and `page_count` and returns extraction metadata; errors and partial extracts are explicit.
- `document_create` supports real CSV headers/rows in addition to the existing content-only export. CSV shape/size are validated and formula-like values, including those after leading whitespace, are escaped.
- Created documents are linked to the assistant response and retain task execution provenance. Reattaching the same file is idempotent. Existing Markdown/PDF exports remain available.
- The Mac library search label now describes its actual name-based filtering. Full-text indexing, office-document parsing and cloud OCR are not part of this block.

## Verification

Swift tests cover real Vision recognition of PNG and a rotated scanned PDF; JPEG and multipage TIFF import; mixed native/scanned PDFs; persistent/cache-corruption behavior; original integrity; blank/invalid files; read bounds; cancellation; explicit attachment access; structured CSV; response attachments and task provenance.

`scripts/verify-file-execution.swift` exercises the actual service with isolated databases, generated image/PDF fixtures and a deterministic chat model: import/preview/OCR, send after source removal, document context boundaries, scan pagination, empty scans, response-linked CSV, task output and reopen persistence. No user files, external app actions or real model provider calls are used by verification.

Final results: **114 Swift tests passed**, including real local Vision recognition. All **five file-service scenarios** and the existing skill/task/schedule/group service regressions passed. Mac and generic iOS builds succeeded; no application GUI, simulator or emulator was launched. Existing Java application/infrastructure checks were successful and up to date (44 tests). Public schemas were unchanged; the schema validator remains unavailable because the installed Python environments lack `jsonschema`. A missing `BlotDomain` import in the concurrently added `PhoneWorkspacePageHeader` was added to complete the iOS build. Its existing authentication `Text + Text` deprecation warning is unrelated. Temporary file/skill verification executables/caches were removed after completion; reusable build directories were retained and free space stayed above 20 GiB.
