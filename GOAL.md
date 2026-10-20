# GOAL 27: a lean core, themes on top, and polish

**End goal (owner, 2026-10-19, after goal 26):** "currently I want the best looking, best polished UI; features can be added later. Of course components will be native by default; the themes are opinionated, stacked on top of it… anybody can add their own themes. I don't want to tightly couple this… the goal of the framework is to stay lean, provide a language for all platforms; everything theming, apps, are plugins on top of it. After this polish, super silky smooth UI, make a list of operations you need from mxframe."

Today the hosts carry the themes: ~350 lines of Liquid, Ledger, Fluent and Omarchy CSS inside the GTK host, ~300 inside the web host, and the core names every theme (`LIQUID`, `skin_palette`, `Palette.omarchy()`, omxplorer's brand colours). This goal moves them out (D-260).

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M0 | Before, as pictures | every themed screen shot on GTK and the web before the move (omxplorer's start, sheet, report and Settings in Liquid, Ledger, Graphite and Blueprint; kit's skins; Fluent; Omarchy; a native app), twice, to know the noise (`build/g27/before`, `scripts/theme_shots.py`) |
| M1 | The core knows no theme | no theme's name, colours or style sheet in `mojoui/` (the words liquid, ledger, graphite, blueprint, fluent, omarchy and the brand colours: 0 hits); an app hands its hosts a `Theme` (a name, a palette for drawn views, a GTK and a web style sheet), the hosts load whatever they're given; every theme lives in `themes/`, outside the framework |
| M2 | Native by default | an app that names no theme gets each platform's own look: on GTK no style sheet from mojoui beyond layout, the system's light or dark; on the web the system font and colours |
| M3 | Nothing moved | every M0 screen again after the move: no more pixels differ than between M0's two runs (+0.2 %) |
| M4 | Anyone can add a theme | a new theme (`themes/paper.mojo`) written without touching `mojoui/`, picked by an example, switches live on GTK and the web |
| M5 | Polish | a design pass over omxplorer's screens in Liquid (start, import, sheet, report, Settings, menus, popovers; 1742×876 and 1280×720), every finding in `docs/goals/27/polish.md` fixed, with before/after shots |
| M6 | Silky by default | the Scene is GTK's default for the grid (`MOJOUI_SCENE=0` turns it off); goal 26's numbers hold without the flag; hover and press feedback ≤ 150 ms on every control |
| M8 | What we need from MX frame | `docs/mxframe-needs.md`: each operation omxplorer and the framework need from MX frame, why, what we do meanwhile, how much it matters |
| M7 | Nothing regressed | goal 26's checks (M0–M5, M8, M7; every earlier goal inside them) pass |

## Out of bounds
Chart editing ("the title is the query", goal 28 now, docs/goals/28-draft.md); the menu-bar island; new components; the web, Apple and Android drawing through the Scene.

## Done means
`scripts/check` prints PASS for M0–M8; the reviewer passes it; `docs/report.md` is short, with the before/after; pushed to `origin`.
