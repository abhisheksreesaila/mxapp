#!/usr/bin/env bash
# omxplorer: build it (only what changed), then open it.
#   scripts/omxplorer.sh                 the native Linux window (Start screen)
#   scripts/omxplorer.sh path/to/file    open a .csv or .omx straight away
#   scripts/omxplorer.sh web             serve it at http://127.0.0.1:5001
set -euo pipefail
cd "$(dirname "$0")/.."
what="${1:-linux}"
if [[ "$what" == "web" ]]; then
  scripts/build.sh omxplorer web
  echo "→ http://127.0.0.1:5001"
  exec pixi run python mojoui/hosts/web.py build/omxplorer/web
fi
scripts/build.sh omxplorer linux
if [[ "$what" != "linux" ]]; then
  export OMX_OPEN="$(realpath "$what")"
fi
exec pixi run build/omxplorer/linux/omxplorer
