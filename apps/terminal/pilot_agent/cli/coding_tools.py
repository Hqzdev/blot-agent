from __future__ import annotations

import subprocess
from collections.abc import Callable
from difflib import unified_diff
from pathlib import Path
from typing import Any

from pilot_agent.agent.safety import redact_sensitive_text
from pilot_agent.backends.base import ExecutionBackend
from pilot_agent.tools.base import Tool
from pilot_agent.tools.file_ops import ProjectPaths


class CodingProject:
    def __init__(self, root: Path):
        self.root = root
        self.paths = ProjectPaths(root)

    def resolve(self, path: str, *, write: bool = False) -> Path:
        target = self.paths.resolve(path, write=write)
        if not target.is_relative_to(self.root):
            raise PermissionError("Select a path inside the project folder")
        parts = target.relative_to(self.root).parts
        if ".git" in parts or ".pilot-agent" in parts:
            raise PermissionError("Git metadata and Blot task files are managed separately")
        return target

    def git(self, *arguments: str) -> str | None:
        try:
            result = subprocess.run(
                [
                    "git",
                    "--no-optional-locks",
                    "--literal-pathspecs",
                    "-c",
                    "core.fsmonitor=false",
                    *arguments,
                ],
                cwd=self.root,
                capture_output=True,
                text=True,
                errors="replace",
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            return None
        return result.stdout.strip() if result.returncode == 0 else None

    def has_local_changes(self, relative_path: str) -> bool:
        status = self.git(
            "status",
            "--porcelain",
            "--untracked-files=all",
            "--ignored",
            "--no-renames",
            "--ignore-submodules=all",
            "--",
            relative_path,
        )
        return status != ""

    def instructions(self) -> str:
        try:
            path = self.paths.resolve("AGENTS.md")
            with path.open(encoding="utf-8", errors="replace") as handle:
                return redact_sensitive_text(handle.read(24_000))
        except (OSError, ValueError):
            return ""


class ReviewedCommand(Tool):
    def __init__(
        self,
        tool: Tool,
        approve: Callable[[str], bool],
        backend: ExecutionBackend,
        timeout_s: int,
    ):
        self.tool = tool
        self.approve = approve
        self.backend = backend
        self.name = tool.name
        self.description = tool.description
        self.parameters = tool.parameters
        self.timeout_s = timeout_s

    def execute(self, **kwargs: Any) -> str:
        command = str(kwargs["command"])
        if not self.approve(f"Run this command ({self.backend.name})?\n{command}"):
            raise PermissionError("Command was not approved")
        kwargs["timeout_s"] = min(int(kwargs.get("timeout_s", self.timeout_s)), self.timeout_s)
        try:
            return self.tool.execute(**kwargs)
        except KeyboardInterrupt:
            self.backend.cleanup()
            raise
        except subprocess.TimeoutExpired:
            self.backend.cleanup()
            return f"[exit 124]\nCommand timed out after {kwargs['timeout_s']}s"


class ProjectRead(Tool):
    def __init__(self, tool: Tool, project: CodingProject):
        self.tool = tool
        self.project = project
        self.name = tool.name
        self.description = tool.description
        self.parameters = tool.parameters

    def execute(self, **kwargs: Any) -> str:
        kwargs["path"] = str(self.project.resolve(kwargs.get("path", ".")))
        return self.tool.execute(**kwargs)


class TrackedEdit(Tool):
    def __init__(
        self,
        tool: Tool,
        project: CodingProject,
        approve: Callable[[str], bool],
        record_diff: Callable[[str], None],
    ):
        self.tool = tool
        self.project = project
        self.approve = approve
        self.record_diff = record_diff
        self.name = tool.name
        self.description = tool.description
        self.parameters = tool.parameters

    def execute(self, **kwargs: Any) -> str:
        target = self.project.resolve(kwargs["path"], write=True)
        relative = target.relative_to(self.project.root)
        before = _read_existing(target)
        needs_review = before is not None and self.project.has_local_changes(relative.as_posix())
        if needs_review and not self.approve(f"Edit existing local changes in {relative}?"):
            raise PermissionError("Edit was not approved")
        if _read_existing(target) != before:
            raise ValueError(f"{relative} changed during review. Read it and try again.")
        kwargs["path"] = str(target)
        result = self.tool.execute(**kwargs)
        after = _read_existing(target)
        lines = unified_diff(
            (before or "").splitlines(keepends=True),
            (after or "").splitlines(keepends=True),
            fromfile=f"a/{relative}" if before is not None else "/dev/null",
            tofile=f"b/{relative}",
        )
        self.record_diff("".join(line if line.endswith("\n") else line + "\n" for line in lines))
        return result


def _read_existing(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
