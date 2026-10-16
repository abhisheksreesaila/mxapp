#!/usr/bin/env bash
# The Workbook: build it if needed, then open it.
#   scripts/workbook.sh          the native Linux window
#   scripts/workbook.sh web      serve it at http://127.0.0.1:5001 (every tab shares the 20M rows)
# Saves go to ~/Documents/Contoso Workbook.mxwb (or $MOJOUI_WORKBOOK).
set -euo pipefail
cd "$(dirname "$0")/.."
what="${1:-linux}"
if [[ "$what" == "web" ]]; then
  [[ -f build/workbook/web/mojoui_app.so ]] || scripts/build.sh workbook web
  echo "→ http://127.0.0.1:5001"
  exec pixi run python mojoui/hosts/web.py build/workbook/web
fi
[[ -x build/workbook/linux/workbook ]] || scripts/build.sh workbook linux
exec pixi run build/workbook/linux/workbook   # (pixi: the Python the Parquet writer needs)
