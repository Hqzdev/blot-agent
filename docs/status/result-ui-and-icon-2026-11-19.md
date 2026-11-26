# Result presentation and installed icon — 19 November 2026

Scope: shared Apple UI/runtime, macOS installation. Existing document editing and revision storage remain in use.

- Assistant result artifacts are shown outside chat bubbles as compact file links and horizontal result rows with Open in Blot, Edit, Share and Copy link actions. Readable reports with result links use a flat content surface. Ordinary conversation keeps its existing bubble styling.
- Generated-file results include a stable blot-file:// artifact URL. The Markdown renderer resolves only valid IDs present in the current workspace, opens files in Blot and routes HTTP(S) links into the internal browser. Arbitrary filesystem links are not opened. Link guidance is scoped to the document tool rather than expanding every model request.
- Explicit Markdown web links produce compact website rows; attached images form a bounded thumbnail grid. Website previews do not prefetch third-party pages. Browser screenshots now attach their actual image artifact to the response.
- Completed tool activity collapses into a worked-duration row using actual persisted model-step timestamps. Errors are marked; details remain expandable.
- Opening a file defaults to formatted preview; Edit remains available in the result menu and document toolbar. Existing stable file tabs are reused.
- The current .icon source and built AppIcon.icns already contained the requested large white Blot. /Applications/Blot.app still contained the old dark centered icon. Its old bundle was retained under .build/app-install-backups and the current signed build installed atomically. Installed icon bytes match the build. No global Dock cache was cleared and no user account data was removed.
- ./script/build_and_run.sh --install now builds, retains the prior installed bundle, installs into /Applications and registers/launches that exact copy. Normal development launch behavior remains available.

Verification: 229 shared Swift tests passed; native macOS and generic physical iOS builds passed. Installer and shell syntax checks passed. The installed executable was confirmed running from /Applications/Blot.app. UI automation currently reports cgWindowNotFound; the user has been asked to open the window before live visual verification.
