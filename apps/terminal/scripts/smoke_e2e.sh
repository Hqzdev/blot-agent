#!/usr/bin/env bash
set -euo pipefail

APP_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIRECTORY"

docker compose build
docker compose run --rm pilot-agent version
docker compose run --rm pilot-agent doctor --json || true

if [ "${PILOT_AGENT_RELEASE_CHECK:-0}" = "1" ]; then
  if grep -R "NotImplementedError\\|TODO:" pilot_agent docs tests README.md AGENTS.md CONTRIBUTING.md SECURITY.md; then
    echo "Release gate failed: NotImplementedError or TODO marker remains."
    exit 1
  fi
fi
