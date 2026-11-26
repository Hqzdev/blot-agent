#!/usr/bin/env bash
set -euo pipefail

APP_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIRECTORY"
export UV_PYTHON_DOWNLOADS=never

uv sync --all-groups --frozen

.venv/bin/ruff check pilot_agent tests
.venv/bin/mypy --no-incremental --no-sqlite-cache pilot_agent
.venv/bin/pytest
.venv/bin/python -m compileall pilot_agent
.venv/bin/python -m pilot_agent.cli --help >/dev/null
.venv/bin/blot --help >/dev/null
