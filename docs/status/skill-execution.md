# Skills in the Apple workspace

Implemented in the current project on `mac/workspace`.

## Behavior

- Skills library is available from chat menus and the agent profile. The Mac inspector shows the selected agent's assigned skills.
- Create and edit named instructions, required/optional string parameters (`{{parameter}}`) and tools. Every save creates an immutable `SkillRevision`; restoring a revision changes only the active pointer. Archive retains history.
- Assign and revoke a skill per agent independently of the agent's configuration. Assignment grants no external tool permissions. Native app operations include their resource-discovery tool.
- Manual runs and `skill_run` atomically create a local queued task with the selected revision, configuration and expanded goal. Validation failures leave no partial task. Replaying a command/tool call does not enqueue twice.
- `skill_list` discovers only assigned, active skills, with parameters and pagination. Models receive an explicit distinction between queued and completed. Task execution cannot recursively launch other skills.
- Execution tools are limited to the skill revision's declared tools and the agent's pinned/current permissions. Archiving, revocation, unresolved conflicts and lost tool permissions block execution. Access is rechecked before model/tool phases and before committing a final response.
- A run can prefill a schedule with expanded instructions and the exact revision. Subsequent skill edits do not change queued tasks or schedules. Revoking an assignment or archiving the skill prevents subsequent scheduled runs; existing schedule failure reporting surfaces the failure.

## Storage and compatibility

No public DTO or schema changes. Existing `Skill`, `SkillRevision`, `Task.skillRevisionId` and `Automation.skillRevisionId` are used. Expanded input is stored in the task/schedule goal, not a new parameter envelope. Revision history identifies immutable IDs and timestamps rather than inferred sequential revision numbers.

Assignment uses the existing `ApprovalGrant` rule shape: operationClass `skill.use`, scope `agent:<UUID>`, resource `skill:<UUID>`, no actionId, revoked on removal. The stable record ID is derived from workspace/skill/agent. Concurrent revocation wins; a later causal assignment can restore access. Assignment records and revisions travel through existing encrypted replica snapshots/sync. Native action rules continue to match their own exact operation class and resource.

This is Apple-local Swift execution. Java clients can retain these existing records, but do not gain a Java skill executor from this change. No MCP or external-plugin implementation is included.

## Verification

- Swift workspace tests cover immutable inputs, replay, history/restore, template validation, missing parameters, conversation membership, missing tool permissions, revocation during generation, archives, discovery, recursion prevention, scheduled runs, and replica synchronization/restoration.
- `scripts/verify-skill-execution.swift` checks service commands/snapshots, actual task-queue execution, model discovery + enqueue, archive enforcement and reopen persistence using isolated databases and a deterministic model. No external action is executed.
- Regression checks: existing task, schedule and group service scenarios; Mac build and generic iOS compile. No application GUI or simulator is launched.

Final validation: **104 Swift tests passed**, **44 Java tests passed** (`application` + `infrastructure`), four skill service scenarios plus the existing task/schedule/group scenarios passed. Both Mac and generic iOS builds succeeded. The iOS build retains an unrelated `Text + Text` deprecation warning in `PhoneAuthenticationView`. The JSON-schema check could not run because neither installed Python environment provides `jsonschema`; no schemas/DTOs were changed by this block. The skill verification executable/cache were removed after completion; existing incremental Mac/iOS builds were retained. Free disk space remained above 20 GiB.
