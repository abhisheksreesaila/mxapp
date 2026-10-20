#!/usr/bin/env bash
# Goal 26 M6: the Scene on a real GPU display. Opens omxplorer on 1M rows twice (today's pixels, then the Scene drawn
# by GTK's renderer), scrolls 60 frames and glides the selection 10 times in each, and prints what each frame cost and
# how evenly frames arrived. A window appears for about a minute each time: don't touch it.
#   scripts/scene-bench.sh            (writes docs/goals/26/owner-run.txt)
set -euo pipefail
cd "$(dirname "$0")/.."
DATA="build/data/orders_1m.csv"
test -f "$DATA" || { echo "no $DATA (goal 14's 1M-row file)"; exit 2; }
scripts/build.sh omxplorer linux >/dev/null
OUT="docs/goals/26/owner-run.txt"
mkdir -p docs/goals/26
CFG="$(mktemp -d)"
{
  echo "Goal 26 owner run, $(date -Iseconds), $(hyprctl monitors 2>/dev/null | grep -m1 -E '@' | xargs || echo 'display: unknown')"
  echo "GSK_RENDERER=${GSK_RENDERER:-default (Vulkan on Wayland)}"
  for mode in pixels scene; do
    extra=(MOJOUI_SCENE=0)
    [[ $mode == scene ]] && extra=(MOJOUI_SCENE=1)
    echo "== $mode"
    env "${extra[@]}" MOJOUI_TRACE=1 OMX_CONFIG="$CFG" OMX_DOCUMENTS="$CFG" MOJOUI_SHOT="$CFG/shot-$mode.png" \
      MOJOUI_TEST="pick:Choose a file=$PWD/$DATA;tap:Create table;bench:glide=10;bench:scroll=60" \
      build/omxplorer/linux/omxplorer 2>/dev/null | grep '^BENCH' || echo "(no BENCH lines)"
  done
} | tee "$OUT"
echo
echo "Saved to $OUT. Per frame: paint = Mojo's work, upload = handing it to GTK; interval = time between frames"
echo "(16.7 ms is every frame on time at 60 Hz, 8.3 ms at 120 Hz)."
