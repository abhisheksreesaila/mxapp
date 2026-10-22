# Next (saved 2026-10-20, after goal 29)

The owner paused feature work after goal 29: "100M no one will try on day 1. I want to publish to GitHub and advertise on Twitter and the Modular forum… nice docs and a story."

## 1. The launch (waiting on the owner's yes)
- Done: the README, the launch page, llms.txt; two clips and stills (docs/img/clip-sentence-gtk.mp4, clip-sentence-web.mp4; `scripts/clips.py` records them again); drafts for a GitHub release, an X thread and a Modular forum post (docs/launch/posts.md).
- **Owner:** read the drafts; decide the name (omxapp or mxapp) and the tag; say yes to push and post. Nothing is pushed or posted before that.
- Seen while recording, web only: during an ask one frame shows the grid and the chart blank (the page swaps them); the ask field doesn't widen with a widened chart.

## 2. Polish seen in goal 29's screenshots (done 2026-10-21 but one)
- Done: "by month"; the ask's reply once (status bar); a chart's time once (its card); "$" was a column without a currency format (guard test).
- **Owner's call:** a new chart filling its row's width breaks goal 15's layout (a chart at 520 with a pivot beside it, kept across reopen). Charts resize from the corner today (the clips drag it as wide as the table first: compare docs/img/omxplorer-sentence-gtk.jpg). Say "fill it" and goal 15's check changes with it.

## 3. Goal 30, parked: the island with background queries (6–10 h)
- MX frame 23edc59 (issue #2): `start_job`/`Job` with poll, cancel, progress; `range_aggregate` for the status bar; `read_block` for the grid. The engine job's vendoring is uncommitted on an old base (~/.abode/home/worktrees/mojo-ui/t3-828a9b57): vendor it ourselves (D-270).
- Why: on the UI thread at 100M rows a median takes 657 ms, a month chart 481 ms, a sum 46 ms (`docs/goals/29/bench.txt`). The status bar's sum at 100M isn't measured yet.
- The island (D-255, option B, `docs/design/island/README.md`): an `Island` component that morphs, one activity queue that replaces Toasts, an expanded panel; remove the document and GPU chips. A query runs in the background and shows in the island; the chart animates in when it lands.

## 4. Later, parked by the owner (2026-10-21)
- `AGENTS.md` plus a "build an omxapp app" skill, so a coding agent writes a working app from one sentence (follows llms.txt, e4e929d).
- A measured comparison against a familiar tool (pandas or DuckDB, same machine) for the launch table.
- "Drop one Mojo app next to your Python": mounting an omxapp web app inside a FastHTML site.
