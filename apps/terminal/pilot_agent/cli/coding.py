from __future__ import annotations

import sys
import uuid
from dataclasses import dataclass
from pathlib import Path

from pilot_agent.agent.context import ContextManager
from pilot_agent.agent.iteration_budget import IterationBudget
from pilot_agent.agent.loop import AgentLoop
from pilot_agent.agent.phases import Phase
from pilot_agent.agent.safety import redact_sensitive_text
from pilot_agent.agent.session_lock import ProjectSessionLock
from pilot_agent.agent.state import pilot_agent_dir, read_message_log
from pilot_agent.agent.types import Message, Role, ToolResult
from pilot_agent.backends.base import ExecutionBackend
from pilot_agent.cli.coding_tools import CodingProject, ProjectRead, ReviewedCommand, TrackedEdit
from pilot_agent.cli.ui import UI
from pilot_agent.cli.ui.coding_terminal import CodingTerminal
from pilot_agent.config.schema import PilotAgentConfig
from pilot_agent.providers.base import Provider
from pilot_agent.tools.base import ToolRegistry, ToolSearchSettings
from pilot_agent.tools.bash import BashTool
from pilot_agent.tools.file_ops import EditFileTool, ListFilesTool, ReadFileTool, WriteFileTool

READ_TOOLS = ["read_file", "list_files"]
CODING_PROMPT = (
    "You are Ori, a programming agent working in the user's current project. "
    "Follow applicable AGENTS.md instructions, including nested instructions. "
    "Read the relevant code before proposing changes. Match the scope of the request. "
    "Preserve existing user changes. Use file tools for source edits, and shell commands "
    "for inspection, builds, and tests. Shell execution requires user approval. "
    "Report changed files and the checks you actually ran, including failures and skipped checks."
)
WORK = Phase("work", CODING_PROMPT, [*READ_TOOLS, "write_file", "edit_file", "bash"], None)
PLAN = Phase(
    "plan",
    CODING_PROMPT + " Inspect the project and respond with a plan. Use read-only file tools.",
    READ_TOOLS,
    None,
)
COMMANDS = {
    "/diff": "Show file edits made by Ori in this task",
    "/plan": "Toggle read-only planning mode",
    "/new": "Start another task",
    "/resume": "Select a saved task",
    "/help": "Show commands",
    "/quit": "Save and exit",
}


@dataclass(frozen=True)
class CodingTask:
    journal: Path

    @property
    def id(self) -> str:
        return self.journal.stem

    @property
    def diff(self) -> Path:
        return self.journal.with_suffix(".diff")

    def title(self) -> str:
        messages = read_message_log(self.journal)
        first = next((item.content for item in messages if item.role == Role.USER), "")
        return (" ".join(first.split()) or "Untitled task")[:80]

    def append_diff(self, change: str) -> None:
        if change:
            with self.diff.open("a", encoding="utf-8") as handle:
                handle.write(redact_sensitive_text(change))


class CodingTasks:
    def __init__(self, root: Path):
        self.directory = pilot_agent_dir(root) / "tasks"

    def new(self) -> CodingTask:
        return CodingTask(self.directory / f"{uuid.uuid4().hex[:12]}.jsonl")

    def saved(self) -> list[CodingTask]:
        journals = sorted(
            self.directory.glob("*.jsonl"),
            key=lambda path: path.stat().st_mtime_ns,
            reverse=True,
        )
        return [CodingTask(path) for path in journals]

    def find(self, task_id: str | None = None) -> CodingTask | None:
        return next((item for item in self.saved() if task_id is None or item.id == task_id), None)


class CodingSession:
    def __init__(
        self,
        *,
        project: CodingProject,
        provider: Provider,
        backend: ExecutionBackend,
        config: PilotAgentConfig,
        ui: UI,
    ):
        self.project = project
        self.provider = provider
        self.backend = backend
        self.config = config
        self.ui = ui
        self.terminal = CodingTerminal(ui.console, ui.input)
        self.tasks = CodingTasks(project.root)
        self.phase = WORK
        self.task = self.tasks.new()
        self.agent: AgentLoop
        self.interactive = sys.stdin.isatty() and sys.stdout.isatty()

    def run(self, *, task: CodingTask | None = None, prompt: str | None = None) -> None:
        with ProjectSessionLock(self.project.root):
            branch = self.project.git("branch", "--show-current")
            self.ui.renderer.coding = self.interactive
            self.terminal.open(
                project=self.project.root.name,
                branch=branch,
                model=self.provider.model,
                backend=self.backend.name,
                interactive=self.interactive,
            )
            self._open(task or self.task)
            if prompt:
                self._submit(prompt)
            if not self.interactive:
                return
            while True:
                try:
                    line = self.ui.prompt_user().strip()
                    if line == "/quit":
                        return
                    if line.startswith("/"):
                        self._command(line)
                    elif line:
                        self._submit(line)
                except EOFError:
                    return
                except KeyboardInterrupt:
                    self.ui.notice("Interrupted. Your task is saved. Use /quit to exit.")

    def _open(self, task: CodingTask) -> None:
        tools = [
            ProjectRead(ReadFileTool(self.project.root), self.project),
            ProjectRead(ListFilesTool(self.project.root), self.project),
            TrackedEdit(
                WriteFileTool(self.project.root),
                self.project,
                self._approve,
                task.append_diff,
            ),
            TrackedEdit(
                EditFileTool(self.project.root),
                self.project,
                self._approve,
                task.append_diff,
            ),
            ReviewedCommand(
                BashTool(self.project.root, self.backend),
                self._approve,
                self.backend,
                self.config.tool_timeout_s,
            ),
        ]
        self.task = task
        history = read_message_log(task.journal)
        last_request = next((item for item in reversed(history) if item.role == Role.USER), None)
        self.phase = PLAN if last_request is not None and last_request.phase == PLAN.name else WORK
        self.terminal.set_mode(planning=self.phase == PLAN)
        self.agent = AgentLoop(
            project_root=self.project.root,
            provider=self.provider,
            registry=ToolRegistry(
                tools,
                self.project.root,
                inline=True,
                artifact_scope=task.id,
                tool_search=ToolSearchSettings(enabled="off"),
            ),
            ctx=ContextManager(self.provider, self.config.budget_ratio, session_log=task.journal),
            history=history,
            phase_name=None,
            journal=task.journal,
            ui=self.ui,
        )
        self._close_pending_calls()
        if task.journal.exists():
            self.ui.notice(f"Resumed {task.id} · {task.title()}")
            if self.phase == PLAN:
                self.ui.notice("Planning mode · read only")

    def _submit(self, text: str) -> None:
        self.agent.record(Message(role=Role.USER, content=text, phase=self.phase.name))
        instructions = self.project.instructions()
        context = f"Project instructions (AGENTS.md):\n{instructions}" if instructions else ""
        budget = IterationBudget(self.config.max_turns)
        try:
            while budget.consume():
                if not self.agent.exchange(self.phase, state_md="", project_context=context):
                    return
            self.ui.warning("Turn limit reached. Enter another instruction to continue.")
        except KeyboardInterrupt:
            self._close_pending_calls()
            self.ui.notice(f"Interrupted. Task {self.task.id} saved.")
        except Exception:
            self._close_pending_calls()
            raise

    def _close_pending_calls(self) -> None:
        if not self.agent.history:
            return
        last = self.agent.history[-1]
        if last.role == Role.ASSISTANT and last.tool_calls:
            self.agent.record(
                Message(
                    role=Role.TOOL,
                    phase=last.phase,
                    tool_results=[
                        ToolResult(
                            call.id,
                            "Interrupted before results were saved. Check current project state.",
                            is_error=True,
                        )
                        for call in last.tool_calls
                    ],
                )
            )

    def _command(self, line: str) -> None:
        if line == "/help":
            self.ui.notice("\n".join(f"{command:<9} {verb}" for command, verb in COMMANDS.items()))
        elif line == "/plan":
            self.phase = WORK if self.phase == PLAN else PLAN
            self.terminal.set_mode(planning=self.phase == PLAN)
            self.ui.notice("Planning mode · read only" if self.phase == PLAN else "Coding mode")
        elif line == "/diff":
            if self.task.diff.exists():
                self.terminal.diff(self.task.diff.read_text(encoding="utf-8"))
            else:
                self.ui.notice("No file edits recorded for this task.")
            self.ui.notice("For changes from shell commands, check git diff.")
        elif line == "/new":
            self._open(self.tasks.new())
            self.ui.notice("New task")
        elif line == "/resume":
            saved = self.tasks.saved()
            if not saved:
                self.ui.notice("No saved tasks in this project.")
                return
            selected = self.ui.input.select(
                "Resume a task",
                [(item.id, f"{item.id} · {item.title()}") for item in saved],
            )
            task = next(item for item in saved if item.id == selected)
            self._open(task)
        else:
            self.ui.warning("Unknown command. Use /help.")

    def _approve(self, action: str) -> bool:
        if not self.interactive:
            return False
        self.ui.notice(action)
        return self.ui.input.confirm("Allow?")
