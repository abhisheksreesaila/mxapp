# GOAL 3: the web, real components, a real app on every platform

**End goal (owner's words, 2026-10-15):** "First, render the web… build a very small app prototype… once you have a good rhythm, build all the components necessary (dropdown, text, label, all the typical components)… build an app like a todo list… the same declarative code in Mojo runs on all of them… I would also try to build Android… then build an app that's also great on GPUs."

Goals 1–2 (`docs/goals/`) gave Mojo-only native rendering on Linux (GTK), Mac (AppKit) and iPhone (UIKit).

## Milestones
`scripts/check` prints PASS or FAIL per milestone. Order = build order.

| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Web prototype | `examples/hello/app.mojo`, unchanged, served by FastHTML (Python) calling the app compiled as a Mojo Python module; a real Chrome clicks Greet 3× and the page reads `Hello, Ada! (click 3)` |
| M2 | Components in the core | events carry values (`Event`: message + text + number); new `TextField`, `Toggle`, `Dropdown`, `Slider`, `ProgressBar`, `Divider`, `Scroll`; `tests/test_mojoui.mojo` passes with exact trees/patches for each |
| M3 | Components on Linux | `examples/gallery/app.mojo` (every component) in GTK test mode: typing, toggling, choosing, sliding change the real widgets and the labels that echo the state |
| M4 | Components on the web | the same gallery in Chrome: same interactions, same echoed state |
| M5 | Components on Mac + iPhone | gallery, hello and todo build, link and sign for both (symbols, entry point, signature, same app file) |
| M6 | A real app everywhere | `examples/todo/app.mojo` rewritten as a real todo (type a task, add, tick done, filter All/Active/Done, remove, counts): passes a GTK run and a Chrome run with identical results; builds for Mac + iPhone; no platform code in any app file |
| M7 | Android (stretch) | Mojo app code compiles for Android arm64 and a native Android host is built; or, if tools are out of bounds, a written blocker with evidence and the nearest step done |
| M8 | GPU (stretch) | `examples/gpu/app.mojo`: a Mojo GPU kernel runs on the NVIDIA GPU and its result is shown in the UI (GTK + web runs report the GPU name and the computed result) |
| M9 | You can try it | README + docs cover web, components, todo, Android/GPU status; every path named exists |

## Done means
M1–M6 and M9 pass; M7 and M8 pass or end in a clear, evidenced report. Real screenshots of Linux and web. The report says what ran here (Linux, web, GPU) vs. what needs your Mac/iPhone/Android phone.

## Out of bounds
No deploying, paid services, sign-ups, logins, secrets or pushing. No accepting licences on the owner's behalf (e.g. Android SDK `sdkmanager --licenses`, Xcode). Nothing outside this folder except pixi/cache downloads. Don't take over the desktop: windows may flash briefly during checks only.

## Assumptions (made instead of asking)
- Web = FastHTML server-side rendering + HTMX (the owner's idea); the Mojo app runs on the server inside Python, one app state per browser tab session. JS islands (ROADMAP decision 7) only if time allows.
- Plain `python-fasthtml` for the web host, not fh-saas: this is a framework host, not a multi-tenant SaaS backend.
- Events: `update(mut self, event: Event)`; `event.message` is the old Int message. Existing examples are updated (breaking change is fine pre-release).
- Windows = the web host for now (no Mojo Windows target yet).
- Browser tests use the local Chrome via `chrome-devtools-axi`.

## Budget
About 5 hours / 150 turns, owner asleep. Stop early with a clear report if blocked.
