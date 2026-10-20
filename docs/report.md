# Goal 29 report: charts that ask the new engine more (MX frame 321870f)

**End goal (owner):** one language for every platform; omxplorer is the showcase: the best-performing dashboard, with macOS polish, Linux speed and Windows usability. MX frame's session called **321870f** stable (SQL, expressions, FLOAT64, median and quantiles per group); goal 29 puts it under the chart sentence.

## Result
- **M0–M4 PASS** (the last full run, 2026-10-20): the engine is 321870f and every example builds; median and p90, eight number conditions and four calendar charts equal pyarrow's; at 1M rows every chart fits one frame (sum 0.5 ms, median 6.4 ms, month 5.8 ms).
- **M5 (every earlier goal's checks): all pass but one flaky step.** In three full runs, goal 7's Android check counted "click 2" after 3 taps on hello's Greet; on its own it read "click 3" 8 times out of 8 on the same code. Only the full run loads the machine (GTK, the web and GPU checks around the emulator), so the lost tap is put down to the emulator, not the app. The driver now waits for each tap to land, and never re-taps. Owner's call (2026-10-20): stop at this point and publish; not chased further.
- Reviewer: round 1 NEEDS WORK, rounds 2 and 3 PASS; every should-fix is in. The archived engine checks (goals 22, 23) prove the sources against MX frame's archive instead of byte-equal packages (D-269).
- Merged into main locally, not pushed (CLAUDE.md).

## What a chart can say now
The sentence from goal 28 (tap a word, or ask) gained three things people ask a dashboard first:

| Ask | What changes |
|---|---|
| *median*, *p90*, *90th percentile* | **Median** or **p90** of amount by region: each group's middle value, or the value 90 % of its rows stay under |
| *over 5,000*, *under 500*, *at least 2*, *at most 10*, *between 100 and 200*, *1.5k* | a number condition on the rows, beside a text or Yes/No one (*only paid and over 5,000*); also on the chart's Rows page |
| *by month of day*, *monthly*, *by quarter*, *by weekday* | groups by a date's month, quarter or weekday: every month of the span in calendar order, empty months too |

| Median by region | By month, as a line | Over 2,500 (Rows page) |
|---|---|---|
| ![](goals/29/median-gtk.jpg) | ![](goals/29/month-gtk.jpg) | ![](goals/29/over-gtk.jpg) |

- Every number is checked against pyarrow: 6 median/p90 charts, 8 number conditions (on money and on whole numbers, at an exact value), 4 calendar charts. Dates before 1970, across a year's end and centuries away read right.
- The ask won't guess: "qty under 2.5" on a whole-number column, a second number condition, or "p95" is skipped and said, never rounded or swapped.
- Saved in the document; a document that names something it can't use opens without it.

## What it costs (this machine, RTX 3090, engine 321870f)
| | sum by region | median by region | sum by month |
|---|---|---|---|
| 1M rows | 0.5 ms | 6.4 ms | 5.7 ms |
| 100M rows | 46 ms | 657 ms | 481 ms |

At 1M rows every chart fits one 60 Hz frame. At 100M rows a median or a month chart takes half a second, and today the window waits for it. Goal 30 moves those onto MX frame 23edc59's background queries.

## Fixed on the way
- **A month chart's dates ran into each other** on the x axis ("Jan 2025Feb 2025…"). A line chart now draws every k-th label so none touch, on every chart.
- The engine package isn't byte-for-byte reproducible (two builds of the same commit differ), so the old "vendor equals a fresh build" checks only held for a copied file. They now prove the sources match the commit's archive (D-269).
- **A median chart drew "(blank)" as a 0 bar** though it has no median: a group with no figure reads "—" and draws no bar (an average of no values too).
- The emulator kept a test app signed by another worktree's key, and Android installs failed; the driver reinstalls it.

## Your test
```
cd ~/Projects/mxapp/mojo-ui
scripts/omxplorer.sh build/data/orders_1m.csv
```
Insert → Chart, then in Ask: *median*, *by month of day, as a line*, *only paid and over 5,000*. Or tap the last-but-one word (every row) and pick a condition; the Rows page has Over / Under / Between.

## Not done
- "(blank)" has no median yet: rows without a group key need the engine's NULL group through SQL.
- One number condition per chart; weeks and years as groups; p-values other than p90.
- At 100M rows a median or month chart blocks for about half a second (goal 30).
- Mac, iPhone and Android build on 321870f; the new words weren't run there.
