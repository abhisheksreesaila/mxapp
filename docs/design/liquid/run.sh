#!/usr/bin/env bash
# Stitch drafts of omxplorer's Liquid skin: desktop start, import, sheet, report; phone sheet.
cd "$(dirname "$0")"
P=15162298038433052241
for s in start import sheet report; do
  stitch generate screen --project $P --prompt "$(cat $s.prompt)" --device DESKTOP --title "liquid · $s" --json > stitch-$s.json 2>&1 &
done
stitch generate screen --project $P --prompt "$(cat phone.prompt)" --device MOBILE --title "liquid · phone" --json > stitch-phone.json 2>&1 &
wait
