from __future__ import annotations

import io
import subprocess
from collections.abc import Iterator
from pathlib import Path
from typing import Any

from rich.console import Console
from typer.testing import CliRunner

from pilot_agent.agent.context import StaticSummaryProvider
from pilot_agent.agent.state import read_message_log
from pilot_agent.agent.types import CompletionResponse, Message, Role, ToolCall, ToolSpec
from pilot_agent.backends.local import LocalBackend
from pilot_agent.cli import main
from pilot_agent.cli.coding import CodingSession, CodingTasks
from pilot_agent.cli.coding_tools import CodingProject
from pilot_agent.cli.ui import UI
from pilot_agent.config.schema import PilotAgentConfig


class ScriptedProvider(StaticSummaryProvider):
    def __init__(self, *calls: list[ToolCall]):
        super().__init__("Finished.")
        self.script = iter(calls)
        self.requests: list[tuple[str, list[Message], list[ToolSpec]]] = []

    def _complete(
        self,
        system: str,
        messages: list[Message],
        tools: list[ToolSpec],
        max_tokens: int = 4096,
    ) -> CompletionResponse:
        self.requests.append((system, list(messages), tools))
        calls = next(self.script, [])
        if calls:
            return CompletionResponse(
                Message(role=Role.ASSISTANT, tool_calls=calls), "tool_use", {}
            )
        return super()._complete(system, messages, tools, max_tokens)


class SessionUI(UI):
    def __init__(self, lines: list[str]):
        super().__init__(console=Console(file=io.StringIO(), width=120, force_terminal=False))
        self.lines = iter(lines)

    def prompt_user(self) -> str:
        return next(self.lines)

    def output(self) -> str:
        return str(self.console.file.getvalue())


def make_session(root: Path, provider: ScriptedProvider, ui: SessionUI) -> CodingSession:
    return CodingSession(
        project=CodingProject(root),
        provider=provider,
        backend=LocalBackend(),
        config=PilotAgentConfig(),
        ui=ui,
    )


def test_coding_prompt_edit_diff_and_resume_from_cli(
    tmp_path: Path,
    monkeypatch: Any,
) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    monkeypatch.setenv("PILOT_AGENT_BACKEND", "local")
    provider = ScriptedProvider(
        [ToolCall("write", "write_file", {"path": "example.py", "content": "answer = 42\n"})],
    )
    monkeypatch.setattr(main, "from_config", lambda _config: provider)
    (tmp_path / "AGENTS.md").write_text("Use descriptive variable names.", encoding="utf-8")

    runner = CliRunner()
    result = runner.invoke(main.app, ["Add an example"])
    assert result.exit_code == 0, result.output
    assert (tmp_path / "example.py").read_text() == "answer = 42\n"
    assert "Use descriptive variable names." in provider.requests[0][0]

    task = CodingTasks(tmp_path).saved()[0]
    assert "+answer = 42" in task.diff.read_text()
    assert "Add an example" in runner.invoke(main.app, ["sessions", "list"]).output
    assert runner.invoke(main.app, ["resume", task.id]).exit_code == 0
    assert len(provider.requests) == 2
    assert not (tmp_path / ".pilot-agent" / "session.jsonl").exists()


def test_plan_tool_allowlist_and_task_switching(tmp_path: Path, monkeypatch: Any) -> None:
    provider = ScriptedProvider(
        [
            ToolCall("edit", "write_file", {"path": "unexpected", "content": "test"}),
            ToolCall("shell", "bash", {"command": "touch unexpected"}),
        ]
    )
    ui = SessionUI(["/plan", "Plan a change", "/new", "Separate issue", "/resume", "/quit"])
    monkeypatch.setattr(ui.input, "select", lambda *_args: CodingTasks(tmp_path).saved()[-1].id)
    session = make_session(tmp_path, provider, ui)
    session.interactive = True
    session.run()

    assert {tool.name for tool in provider.requests[0][2]} == {"read_file", "list_files"}
    assert not (tmp_path / "unexpected").exists()
    first = CodingTasks(tmp_path).saved()[-1]
    results = read_message_log(first.journal)[2].tool_results
    assert all(result.is_error for result in results)
    assert len(results) == 2
    assert session.task.id == first.id
    assert "Resumed" in ui.output()


def test_shell_requires_acceptance_and_reports_actual_exit(
    tmp_path: Path,
    monkeypatch: Any,
) -> None:
    provider = ScriptedProvider(
        [ToolCall("rejected", "bash", {"command": "touch rejected"})],
        [ToolCall("approved", "bash", {"command": "touch approved; exit 7"})],
    )
    ui = SessionUI(["/quit"])
    approvals: Iterator[bool] = iter([False, True])
    monkeypatch.setattr(ui.input, "confirm", lambda *_args: next(approvals))
    session = make_session(tmp_path, provider, ui)
    session.interactive = True
    session.run(prompt="Run the checks")

    assert not (tmp_path / "rejected").exists()
    assert (tmp_path / "approved").is_file()
    assert "touch approved; exit 7" in ui.output()
    assert "exit 7" in ui.output()


def test_interrupted_tool_is_not_replayed_on_resume(tmp_path: Path, monkeypatch: Any) -> None:
    provider = ScriptedProvider([ToolCall("pending", "bash", {"command": "touch unexpected"})])
    ui = SessionUI(["/quit"])

    def interrupt(*_args: Any) -> bool:
        raise KeyboardInterrupt

    monkeypatch.setattr(ui.input, "confirm", interrupt)
    initial = make_session(tmp_path, provider, ui)
    initial.interactive = True
    initial.run(prompt="Start the check")
    task = CodingTasks(tmp_path).find()
    assert task is not None

    ui = SessionUI(["/diff", "/quit"])
    resumed = make_session(tmp_path, provider, ui)
    resumed.interactive = True
    resumed.run(task=task)

    assert len(provider.requests) == 1
    assert not (tmp_path / "unexpected").exists()
    messages = read_message_log(task.journal)
    assert messages[-1].tool_results[0].is_error
    assert "Check current project state" in messages[-1].tool_results[0].content


def test_bare_blot_enters_the_coding_prompt(tmp_path: Path, monkeypatch: Any) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    monkeypatch.setenv("PILOT_AGENT_BACKEND", "local")
    provider = ScriptedProvider()
    ui = SessionUI(["Inspect this project", "/quit"])
    monkeypatch.setattr(main, "UI", lambda **_kwargs: ui)
    monkeypatch.setattr(main, "_interactive", lambda: True)
    monkeypatch.setattr(main, "from_config", lambda _config: provider)

    def interactive_session(**kwargs: Any) -> CodingSession:
        session = CodingSession(**kwargs)
        session.interactive = True
        return session

    monkeypatch.setattr(main, "CodingSession", interactive_session)
    result = CliRunner().invoke(main.app, [])

    assert result.exit_code == 0, result.output
    assert CodingTasks(tmp_path).saved()[0].title() == "Inspect this project"


def test_existing_git_changes_require_approval(tmp_path: Path, monkeypatch: Any) -> None:
    existing = tmp_path / "main.py"
    existing.write_text("user_change = True\n", encoding="utf-8")
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "add", "main.py"], cwd=tmp_path, check=True)
    provider = ScriptedProvider(
        [
            ToolCall("edit", "write_file", {"path": "main.py", "content": "agent_change = True\n"}),
        ]
    )
    ui = SessionUI(["/quit"])
    monkeypatch.setattr(ui.input, "confirm", lambda *_args: False)
    session = make_session(tmp_path, provider, ui)
    session.interactive = True
    session.run(prompt="Update main.py")

    assert existing.read_text() == "user_change = True\n"
    assert "Edit existing local changes in main.py?" in ui.output()
