# GOAL 4: the components real apps need, then a fancier app everywhere

**End goal (owner's words, 2026-10-15 morning):** "continue with 2–4, 8, then move to 9 … complete until 9 … on autopilot … and build a fancier app for all platforms, while I test on Apple."
Items refer to the list in the chat: 2 segmented/radio, 3 multi-line text, 4 alerts, 5 date picker, 6 icons, 7 grid, 8 navigation (stack + tabs), 9 long lists that draw only visible rows.

## Milestones (build order: 2, 3, 4, 8 first, then 5, 6, 7, 9, then the app)
Each component: core node + tests, and all four hosts (GTK, web, AppKit, UIKit). GTK and web are driven by the shared step language and must end in identical states; Apple must build, link and sign with only the allowed system functions.

| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Choice controls | `Segmented` and `Radio`; core tests; gallery2 GTK + web runs pick options and echo them, identical |
| M2 | Multi-line text | `TextArea`; typing multi-line text round-trips on GTK + web, identical |
| M3 | Alerts | `Alert` (declarative: present while it's in the view); choosing a button sends its index; GTK + web identical |
| M4 | Navigation | `Tabs` (switch sections) and `NavBar` (title + back); a two-level flow works on GTK + web, identical |
| M5 | Date picker | `DatePicker` → `event.text` "YYYY-MM-DD"; GTK + web identical |
| M6 | Icons | `Icon(name)` with a shared name set mapped to each platform's own icons; GTK + web report them |
| M7 | Grid | `Grid(items, columns)`; GTK + web lay children out in rows of N |
| M8 | Long lists | `LazyList(count, …)`: only visible rows are built; a 10,000-row list scrolls and taps a far row on GTK + web, with far fewer than 10,000 rows ever built |
| M9 | Fancier app | `examples/expenses/app.mojo` uses tabs, a nav stack, text area, date picker, segmented, alert, icons, grid and a long list; GTK + web runs identical; builds and signs for Mac + iPhone |
| M10 | Nothing regressed | goal 3's checks still pass (hello, gallery, todo, GPU, Android library) |
| M11 | Docs | README component table lists every component with its native control per platform; every path exists |

## Out of bounds
Same as goal 3: no deploying, sign-ups, logins, secrets, pushing or accepting licences; no taking over the desktop. Don't touch `../mojo-ui-apple-test` (the owner is testing from it).

## Assumptions
- Modals and navigation stay declarative: an `Alert` is shown while it's in the view; the current screen/tab is app state.
- `Tabs` renders as each platform's segmented-style section switcher at the top (not a bottom tab bar) in this round.
- Long lists ask the app for rows on demand through an `App.row(list_id, index)` method with a default.
- Lazy rows are display-only plus one tap message per row (no controls inside lazy rows yet).

## Budget
~6 hours. Stop with a clear report if blocked.
