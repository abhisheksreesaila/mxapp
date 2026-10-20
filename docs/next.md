# Next (saved 2026-10-20, after goal 29)

The owner paused feature work after goal 29: "100M no one will try on day 1. I want to publish to GitHub and advertise on Twitter and the Modular forum… nice docs and a story."

## 1. The launch (next session)
- Docs and a story: the designed README showcase (measured numbers only), screenshots and short clips of omxplorer, what one Mojo codebase runs on (Linux, web, Android run; Mac and iPhone build).
- Drafts for a GitHub release, an X thread and a Modular forum post.
- Nothing is pushed or posted without the owner's yes (CLAUDE.md: never push).

## 2. Polish seen in goal 29's screenshots (small)
- The chart card is small, with empty space beside it: fill or let it resize.
- "by month of day" should read "by month" (the date column's name only when there are two).
- "Took median" under the chart repeats the title and the status bar.
- A chart's time shows three times (chip, inspector, status bar): once.
- A money column's median bars read "5,157" without "$".

## 3. Goal 30, parked: the island with background queries (6–10 h)
- MX frame 23edc59 (issue #2): `start_job`/`Job` with poll, cancel, progress; `range_aggregate` for the status bar; `read_block` for the grid. The engine job's vendoring is uncommitted on an old base (~/.abode/home/worktrees/mojo-ui/t3-828a9b57): vendor it ourselves (D-270).
- Why: on the UI thread at 100M rows a median takes 657 ms, a month chart 481 ms, a sum 46 ms (`docs/goals/29/bench.txt`). The status bar's sum at 100M isn't measured yet.
- The island (D-255, option B, `docs/design/island/README.md`): an `Island` component that morphs, one activity queue that replaces Toasts, an expanded panel; remove the document and GPU chips. A query runs in the background and shows in the island; the chart animates in when it lands.
