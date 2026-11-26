"""Presentation for Ori's interactive coding sessions."""

from __future__ import annotations

from prompt_toolkit.application import get_app
from prompt_toolkit.formatted_text import FormattedText
from rich import box
from rich.console import Console
from rich.panel import Panel
from rich.style import Style
from rich.text import Text

from pilot_agent.cli.ui.input import PilotAgentInput
from pilot_agent.cli.ui.theme import CODING_HEADING, Palette, glyphs, unicode_enabled


class CodingTerminal:
    def __init__(self, console: Console, input_view: PilotAgentInput):
        self.console = console
        self.input_view = input_view
        self._workspace = ""
        self._model = ""
        self._mode = "Code"

    def open(
        self,
        *,
        project: str,
        branch: str | None,
        model: str,
        backend: str,
        interactive: bool,
    ) -> None:
        separator = f" {glyphs().BULLET} "
        workspace = separator.join([project, branch] if branch else [project])
        self._workspace = workspace
        self._model = model

        if not interactive:
            self.console.print(Text(separator.join(["Ori", workspace, "/help"])))
            return

        self.input_view.bottom_toolbar = self._toolbar
        label = Text("Ori", style=CODING_HEADING)
        label.append(f"{separator}Coding session")
        context = Text(workspace, style="bold")
        context.append(f"\n{model}{separator}{backend} shell")
        self.console.print(
            Panel(
                context,
                title=label,
                title_align="left",
                box=box.ROUNDED if unicode_enabled() else box.ASCII,
                border_style=Style(color=Palette.CODING),
                padding=(0, 1),
                expand=False,
            )
        )

    def set_mode(self, *, planning: bool) -> None:
        self._mode = "Plan" if planning else "Code"

    def diff(self, content: str) -> None:
        self.console.print(Text("Task diff", style="pilot_agent.coding.heading"))
        output = Text(overflow="fold")
        for line in content.splitlines(keepends=True):
            if line.startswith(("--- ", "+++ ", "@@")):
                style = "pilot_agent.coding.heading"
            elif line.startswith("+"):
                style = "green"
            elif line.startswith("-"):
                style = "red"
            else:
                style = ""
            output.append(line, style)
        self.console.print(output, end="" if content.endswith("\n") else "\n")

    def _toolbar(self) -> FormattedText:
        width = get_app().output.get_size().columns
        separator = f" {glyphs().BULLET} "
        mode = f" {self._mode}"
        controls = separator + ("/help  Ctrl+C" if width >= 72 else "/help")
        available = max(0, width - len(mode) - Text(controls).cell_len - 1)
        workspace = Text(separator + self._workspace, no_wrap=True)
        model = Text(separator + self._model, no_wrap=True)
        if workspace.cell_len + model.cell_len <= available:
            workspace.append(model)
        else:
            workspace.truncate(available, overflow="ellipsis")
        return FormattedText([("class:coding.mode", mode), ("", workspace.plain + controls)])
