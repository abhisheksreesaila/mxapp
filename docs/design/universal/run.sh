#!/usr/bin/env bash
# One Stitch project per option: upload its design system, then the sheet, report and phone screens.
set -uo pipefail
cd "$(dirname "$0")"
opt="$1"
out="stitch-$opt.log"
: > "$out"
proj=${2:-}; [[ -n "$proj" ]] || proj=$(stitch create project --title "omxplorer universal · $opt" --json | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("data",d).get("id") or d["data"]["name"].split("/")[-1])')
echo "project $proj" >> "$out"
stitch upload design "$opt.md" --project "$proj" --apply --json >> "$out" 2>&1
for s in sheet report; do
  stitch generate screen --project "$proj" --prompt "$(cat $s.prompt)" --device DESKTOP --title "$opt · $s" --json > "stitch-$opt-$s.json" 2>&1 &
done
stitch generate screen --project "$proj" --prompt "$(cat phone.prompt)" --device MOBILE --title "$opt · phone" --json > "stitch-$opt-phone.json" 2>&1 &
wait
echo done >> "$out"
