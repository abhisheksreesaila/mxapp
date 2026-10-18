#!/usr/bin/env bash
# The agent host for one app: builds its web module if needed, then prints the one command that gives it to
# Claude Code (or any MCP client) and, with --serve, runs it on stdio.
#   scripts/agent.sh omxplorer           # prints: claude mcp add omxplorer -- pixi run python mojoui/hosts/agent.py build/omxplorer/web
#   scripts/agent.sh kit --serve         # the server itself (what the client runs)
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:?usage: scripts/agent.sh <app> [--serve]}"
[[ -f "build/$app/web/mojoui_app.so" ]] || scripts/build.sh "$app" web >&2
if [[ "${2:-}" == "--serve" ]]; then exec pixi run python mojoui/hosts/agent.py "build/$app/web"; fi
echo "claude mcp add $app -- pixi run python $(pwd)/mojoui/hosts/agent.py $(pwd)/build/$app/web"
