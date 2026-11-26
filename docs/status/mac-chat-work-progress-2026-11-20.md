# Mac chat work progress — 20 November 2026

Implemented in the current project on `mac/workspace`; unrelated working-tree changes were preserved.

## Behavior

- A multi-turn response shows real progress messages with tool rows underneath. All intermediate work collapses into one expandable Worked duration, followed by the final reply and result cards.
- A permission-bounded direct-work planner records ordered operations. The runtime advances only after actual tool results and stops on failure or uncertain outcomes. An ignored required call cannot become a prose success claim. Ordinary chat does not add a planning turn.
- When a provider returns a validated file call without explanatory text, a short status describes the pending call before execution. It does not claim completion.
- One avatar marks the start of the response. Empty running placeholders are hidden; the continuing typing indicator does not add another avatar. New live progress rows have a short entrance animation.
- Tail following coalesces message and tool updates, then scrolls after layout. Initial restored history is not animated through estimated row heights. Manual scrolling disables following until the reader returns to the bottom.
- Only a running tool label has a white animated highlight. Completed history stays static; app and system Reduce Motion disable the highlight.
- Worked, reply bubbles and footer actions share the same leading edge. The fourth footer control directly opens the branch picker instead of an ellipsis menu.
- File changes show Created/Edited, actual line counts and before/after content. Undo applies only to an edited file with a verified prior snapshot, through the original permissions and a compare-and-swap hash. It cannot overwrite later user edits. Creating a file does not expose destructive delete-as-undo.
- Branches copy the settled dialogue prefix through the selected response into a separate conversation for the chosen existing agent. Tools, pending approvals and credentials are not copied or executed. The composer identifies the source agent.
- Both sidebar divider targets are 24 points wide while their visible lines remain thin. Editor identity/name controls are on the left; model/tools and instructions remain open on the right. Narrow windows stack the same controls.

## Compatibility and storage

`Conversation.parentConversationId` and `parentMessageId` are optional additions to the generated v3 contract. Ordinary conversations omit them. Branches use a one-agent GROUP container so older direct-chat canonicalization does not merge them into the agent's primary chat. Older clients can display that container but do not provide the branch UI.

File-change snapshots are hidden internal artifacts bound to the originating action, source message, executor, agent and hashes. No database migration is required. Generated contracts and the source model were updated together.

## Validation

- Built and installed `/Applications/Blot.app` on the physical Mac. The final motion build and install succeeded; logs are `.build/work-run-motion-build.log` and `.build/work-run-motion-install.log`.
- Swift workspace suite: **234 tests passed**. Five focused checks cover branching, direct planning, session-file scope and conflict-safe Undo. The synthetic plugin adapter now explicitly declares its fake `new_read` tool; a confirmed connection gates its availability.
- Schema checks: **168 fixtures** and shared web/Apple payloads passed. Java `:core:test` and `:api:test` passed for the contract addition.
- Earlier generic iOS compile passed without running or downloading a simulator. The final motion UI was checked on Mac; it was not launched on iPhone.
- Real GigaChat scenario in **Demo · Work progress**: read `budget-demo.csv`, change 12000 to 15000 using the actual read hash, create `Demo-final-4`, save `Demo-final-4/result.md`. All four tool rows completed. Worked **23s** expanded/collapsed without a crash; Edited and Created cards appeared. Before/after content and an actual Undo were checked.
- Second real scenario: create `Motion-demo-20`, write `check.txt`, read it, then update it using its actual hash. All four actions completed; Worked **22s**, Created and Edited cards appeared. A live screenshot showed one avatar across all four progress messages and no avatar on the continuing typing indicator. The transcript followed the growing response to the bottom.
- Browser divider dragged from 855 to 915 points and back while grabbing beside the line; chat-list divider dragged from 301 to 331 and back. Wide editor columns and the `Chat from QA 18-11 Assistant` banner were observed in the installed app.

## Limits and retained evidence

File operations complete too quickly to assess the highlight's appearance from a still screenshot. Its active-only and Reduce Motion paths were built, but frame-rate improvement is not quantified. A manual scroll-up check during the final run was interrupted by concurrent user interaction, so that interaction policy is code-reviewed rather than claimed as an on-device pass.

Initial live attempts exposed an overly complex single-agent routing envelope, a planner-failure typing indicator and an ambiguous subfolder argument. The plan schema was simplified; planner errors now settle the response; the directory parameter explains that subfolders belong in `path`. Failed attempts remain visible in the demo history and are not counted as successful work.

The automatic reviewer rejected deleting the stable `.build/ios` directory; it was retained. Only finished CLI binaries/caches and obsolete install backups were removed. Incremental Mac/Swift directories and the latest rollback app were preserved. Mac verification below the repository's preferred free-space threshold used the user's earlier explicit authorization to continue Mac checks.
