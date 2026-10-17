#!/usr/bin/env bash
# MX Studio: build it (only what changed), then open it.
#   scripts/mxstudio.sh          the native Linux window
#   scripts/mxstudio.sh web      serve it at http://127.0.0.1:5001
set -euo pipefail
cd "$(dirname "$0")/.."
what="${1:-linux}"
if [[ "$what" == "web" ]]; then
  scripts/build.sh mxstudio web
  echo "→ http://127.0.0.1:5001"
  exec pixi run python mojoui/hosts/web.py build/mxstudio/web
fi
scripts/build.sh mxstudio linux
exec pixi run build/mxstudio/linux/mxstudio
