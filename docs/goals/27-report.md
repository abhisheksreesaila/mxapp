# Goal 27 report: a lean core, themes on top, and polish

**End goal (owner, 2026-10-19):** "the best looking, best polished UI; features can be added later. Components native by default; the themes are opinionated, stacked on top… anybody can add their own. I don't want to tightly couple this… the framework stays lean, a language for all platforms; theming, apps are plugins on top. After this polish, super silky smooth UI, make a list of operations you need from mxframe."

## Result
M0–M8 PASS (M6 and M7 in a rerun after the last fixes: every earlier goal inside them, on the Scene and on pixels). Reviewer: round 2 PASS.
```
PASS  M0  42 shots (omxplorer's 4 screens in 4 skins, kit's skins, Fluent, Omarchy, native; GTK and the web); two runs differ by at most 0.05% of pixels
PASS  M1  mojoui/ names no theme, colour or style sheet (0 hits); the GTK host loads only its padding rules and the app's theme, neither host styles a theme's class; Liquid, the skins, Fluent and Omarchy are themes/ modules; hosts apply App.theme()
PASS  M2  hello names no theme: GTK loads no style sheet but layout (THEME: none); the web page is the system font and colours, no body class
PASS  M3  42 screens from a build of the move (76d715b): at most 0.07% of pixels differ (per channel, each within its own noise); at HEAD, kit, Fluent (but its bars' tracks, P9), Omarchy and native unchanged
PASS  M4  themes/paper.mojo (no line of it in mojoui/) picked in the themes example: GTK and the web switch live from native to Paper (window and page in #f4efe6)
PASS  M5  docs/goals/27/polish.md: every finding fixed; at 1742×876 and 1280×720: one name, no empty chip, the GPU's state once, the report's toolbar the sheet's height, a titled inspector, charts not red; the web's dialog covers the window and Choose a file is the primary; no theme draws dark with a dark system
PASS  M8  docs/mxframe-needs.md: 19 operations, each with why, what the app does meanwhile and how much it matters; the order to ask in
PASS  M6  no flag: scroll 0.8 ms p95, glide 0.2 ms, 0 cell rebuilds, 0 uploads; hover and press ≤ 150 ms (goal 25's M5); goals 3–24 (goal 25's M7) pass on the Scene; MOJOUI_SCENE=0 is the pixel path
PASS  M7  goal 26's M0–M5, M8 and M7 (goals 3–25 inside them) pass
```

## Themes are plugins now
Before: the GTK host carried ~350 lines of Liquid, Ledger, Fluent and Omarchy CSS, the web host ~300, and the core named every theme (and omxplorer's brand colours). Now:

- **The core knows no theme.** `mojoui/` has zero mentions of any theme, colour or style sheet (a check greps for them). It defines only the vocabulary: a `Palette` (the colours drawn views use) and a `Theme` value (CSS classes, a palette, a GTK style sheet, a web style sheet).
- **An app hands its hosts a theme**: `def theme(self) -> Theme: return liquid()`. The hosts apply whatever they get, and restyle live when it changes (a skin picked, the sheet's green, the report's red).
- **No theme = the platform's own look.** libadwaita on Linux (light or dark, as the system is), the system font and colours on the web. Drawn views follow the system's light or dark too (new `App.appearance`).
- **The themes live in `themes/`**, outside the framework: Liquid, the skins (Ledger, Graphite, Blueprint), Fluent, Omarchy, and **Paper**, a new one written without touching the core (≈100 lines, the one to copy). `examples/themes` switches between them live.
- **Proof nothing moved:** 42 screens (omxplorer's 4 screens in 4 skins, kit, Fluent, Omarchy, native; GTK and the web) shot before and after, **pixel-identical** (the one difference, 0.05 %, is the noise between two runs of the same build). The comparison caught one real slip on the way: layout rules for tools and the file picker were hiding inside the Omarchy sheet; they're in the core now (D-262).

| No theme (system dark) | Paper on GTK | Paper on the web |
|---|---|---|
| ![](27/themes-native-dark.jpg) | ![](27/themes-paper-gtk.jpg) | ![](27/themes-paper-web.jpg) |

## Polish (Liquid)
Every screen looked at again at your window size and at 1280×720; twelve findings, all fixed and checked on the running app (`docs/goals/27/polish.md`):

| Before | After |
|---|---|
| ![](27/start-before.jpg) | ![](27/start-after.jpg) |
| ![](27/report-before.jpg) | ![](27/report-after.jpg) |
| ![](27/settings-web-before.jpg) | ![](27/settings-web-after.jpg) |

- **Start:** the sidebar's rows read from their leading edge with one icon set; no repeated name; no empty chip in the menu bar; the web's "Choose a file" is the indigo primary as on Linux.
- **Report:** charts draw in the skin's teal, not the report's red (red read as a loss); no grey track behind each bar; the toolbar is one line, the sheet's height (switching tabs no longer shifts everything); the inspector's head is a title, not a one-button switch.
- **Everywhere:** the GPU's state shows once (it was in three places); at 1280 wide the toolbar stays one line.
- **Web:** the Settings dialog was stuck to the left edge with only a strip dimmed; it's centred over a dimmed window now.

## Silky by default
The Scene (goal 26: the grid as a display list drawn by GTK's GPU renderer) is now the default on Linux: no flag. `MOJOUI_SCENE=0` brings back the pixel path. Every earlier goal's checks pass on it (M6), and on the pixel path too (M7).

## What we need from MX frame
`docs/mxframe-needs.md`: 19 operations, ranked. The top four are about smoothness: **run a query off the UI thread** (with progress and cancel), **incremental results after an edit**, **range aggregates in sorted order** (the selection's Sum without reading cells one by one), **a window of rows in one call**. Then the chart ones for goal 28: more aggregates per group (mean, median, σ), sorted and top-N groups, filters as expressions per query, group by month. Not filed on MX frame's GitHub yet: say the word and I'll open the issues.

## Your test
```
build/themes/linux/themes                            # the theme switcher: Native follows your system's light/dark
scripts/omxplorer.sh build/data/orders_1m.csv         # the Scene is on by default now
scripts/scene-bench.sh                                # goal 26's M6, still waiting for your display
```

## Not done
- **Known in this build:** Undo right after Add row crashes (the selection stays on the removed row); and picking a choice in a popover could scroll the sheet. Both found while building goal 28 and fixed there.
- Android hosts take no theme yet (their own look only); Mac and iPhone apply a theme's palette but haven't run on hardware. `App.appearance` is GTK and the web only.
- Charts and the import preview still paint pixels (only the grid is a Scene).
- Chart editing ("the title is the query") is goal 28 (`docs/goals/28-draft.md`).
