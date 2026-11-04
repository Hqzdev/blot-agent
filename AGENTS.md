# Repository instructions

## Code standards

- Follow OOP principles strictly: single responsibility, encapsulation, composition over inheritance.
- Write clean, minimal, intentional code. No dead code or placeholders.

## Platform branches

This repository is developed on two computers: macOS for Mac/iPhone, and Windows for Windows/Android. Android is written in Java.

| Target | Platform base | Task branch | Main source paths |
| --- | --- | --- | --- |
| iOS | `ios/main` | `ios/<task>` (for example, `ios/auth`) | `apps/ios/` |
| macOS | `mac/main` | `mac/<task>` (for example, `mac/auth`) | `apps/macos/` |
| Windows | `windows/main` | `windows/<task>` (for example, `windows/auth`) | `apps/windows/` |
| Android | `android/main` | `android/<task>` (for example, `android/auth`) | `apps/android/` |

- Choose the prefix from the application being changed. On the Mac computer, iPhone tasks use `ios/` and Mac tasks use `mac/`; on the Windows computer, Android tasks use `android/` and Windows tasks use `windows/`. The host OS alone does not identify the target.
- Git cannot have both `ios` and `ios/auth`; the same restriction applies to the other platforms. Always use `<platform>/main` for the platform base. Do not create bare `ios`, `mac`, `windows`, or `android` branches.
- Before editing, inspect `git status`, the current branch, and worktrees. Fetch `origin`, then create a task branch from the current remote platform base: `git switch -c ios/auth origin/ios/main`. Replace the platform and task as appropriate.
- Use a separate branch/worktree per task. Do not switch, reset, stash, or include another task's uncommitted changes without authorization. If an existing task branch matches the work, continue on it.
- Push explicitly to the matching remote branch, for example `git push -u origin ios/auth`. Never push iOS work to `mac/*`, Android work to `windows/*`, or vice versa. These names replace the earlier `codex/*` and `work/*` conventions.
- Platform bases receive reviewed task changes through pull requests. `main` remains the shared integration/default branch; integrate platform changes into `main` through a reviewed pull request. Fetch and merge updated `origin/main` into a platform base before starting work that needs those updates. Never force-push shared branches.
- Work spanning both Apple clients goes into one owning platform task branch (for example, `mac/shared-auth`), then reaches the other platform through `main`. Do not independently duplicate shared changes in several branches.

## Shared code and compatibility

- `backend/`, `contracts/`, `fixtures/`, `landing/`, `scripts/`, CI, and this file affect more than one platform. `apps/shared/`, `packages/`, and `apps/Blot.xcodeproj` are shared by the Apple clients. Inspect their consumers before changing them.
- Isolate shared backend/contract changes in a focused commit or pull request under the owning platform prefix. Check affected consumers, integrate through `main`, then update dependent platform bases. Shared backend code must not import platform UI or system APIs; use interfaces and platform adapters.
- `contracts/v3/model.json` is the source for generated v3 models. Modify it and run `python3 scripts/generate-v3-contracts.py`, then `python3 scripts/format-v3-java.py`. Do not hand-edit generated Java/Swift DTOs or schemas. Commit the source and all affected generated outputs together.
- Preserve compatibility with other platform branches. Breaking API, schema, or sync changes require a coordinated version/migration change and validation of affected clients. A clean Git merge does not prove compatibility.
- Before pushing, inspect the staged diff and run the checks appropriate to the changes. Shared changes require the existing relevant Java, schema, and Swift checks; report checks that cannot run on the current OS. Add Android/Windows build checks when those projects are introduced.
- Keep SDK paths, `local.properties`, credentials, signing keys, local databases, and build outputs out of commits.
- Do not delete or rename branches, rewrite history, or alter another worktree as routine cleanup without an explicit user request. Existing `archive/2026-11-04/*` tags preserve branch tips from the platform migration; do not remove them during routine cleanup.
