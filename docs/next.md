# Next (saved 2026-10-20, after goal 29)

The owner paused feature work after goal 29: "100M no one will try on day 1. I want to publish to GitHub and advertise on Twitter and the Modular forum… nice docs and a story."

## 1. The launch (released 2026-10-21)
- Done: the README, the launch page, llms.txt; two clips and stills (docs/img/clip-sentence-gtk.mp4, clip-sentence-web.mp4; `scripts/clips.py` records them again); drafts for a GitHub release, an X thread and a Modular forum post (docs/launch/posts.md).
- Released: `v0.1.0-alpha` (pre-release, name omxapp) at github.com/abhisheksreesaila/mxapp/releases, with both clips and the native still attached.
- **Owner:** post the X thread and the Modular forum post from docs/launch/posts.md (no access to either from here); attach the clips by hand.
- Seen while recording, web only: during an ask one frame shows the grid and the chart blank (the page swaps them); the ask field doesn't widen with a widened chart.

## 2. Polish seen in goal 29's screenshots (done 2026-10-21 but one)
- Done: "by month"; the ask's reply once (status bar); a chart's time once (its card); "$" was a column without a currency format (guard test).
- **Owner's call:** a new chart filling its row's width breaks goal 15's layout (a chart at 520 with a pivot beside it, kept across reopen). Charts resize from the corner today (the clips drag it as wide as the table first: compare docs/img/omxplorer-sentence-gtk.jpg). Say "fill it" and goal 15's check changes with it.

## 3. Goal 30: done 2026-10-22 (docs/report.md)
- The island and background queries over MX frame 23edc59; 100M rows never freeze the window. Packages: `scripts/package.sh omxplorer linux|mac`.

## 3b. Goal 31, next: tiles that snap, labels that fit, bars that switch smoothly (docs/goals/31-draft.md)
- The owner, trying the package: pivots land over each other and the table; the inspector reads "Ave… Co… Me…".
- Then: the island drawn as a Scene (today a pixel canvas: it uploads a texture per frame while it moves); the Mac's jobs off the start call.
- The rename to omxcode (D-285, branch rename-omxcode): in the repo first, then the release's title and notes and the site (the owner said yes).

## 4. Later, parked by the owner (2026-10-21)
- `AGENTS.md` plus a "build an omxapp app" skill, so a coding agent writes a working app from one sentence (follows llms.txt, e4e929d).
- A measured comparison against a familiar tool (pandas or DuckDB, same machine) for the launch table.
- "Drop one Mojo app next to your Python": mounting an omxapp web app inside a FastHTML site.
