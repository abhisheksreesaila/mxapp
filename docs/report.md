# Goal 17 report: omxplorer's universal theme and the components it needs

**End goal:** one look for omxplorer on every platform (Claude's Ledger by default; Graphite and Blueprint as skins), and the components the design kit showed were missing: a menu bar, menus, dialogs, toasts, tooltips, popovers, checkboxes, grid badges.

## How far it got
`scripts/check` (see `build/check-goal17.log` for the run):

| # | Milestone | Result |
|---|---|---|
| M1 | The skins: exact tokens, vendored and baked fonts, both hosts report `DESIGN: ledger` / `graphite`, light and dark screenshots | PASS |
| M2 | Menus: the bar on both hosts, Data > Sort largest first sorts, Ctrl+S saves, a right-click context menu sorts; identical dumps | PASS |
| M3 | Settings dialog switches the skin live and saves it; a sort's toast undoes it; tooltips on every tool; ƒx's popover | PASS |
| M4 | Grid badges and corner marks, read back from pixels | PASS |
| M5 | The Ledger Start screen and the sheet carry the menu bar; About | PASS |
| M6 | Goal 15's checks (goals 3–14 inside them) and the matrix | PASS (build/check-goal17-m6.log) |

## 30-second demo
```
scripts/omxplorer.sh                    # Linux: the Ledger; File > Settings… to switch skins
pixi run python mojoui/hosts/web.py build/omxplorer/web   # the web, the same look
```
Right-click a column header for its menu; Ctrl+S saves; Data > Sort largest first shows a toast with Undo. Screenshots from the check: `build/omxplorer/skin-ledger-*.png`, `skin-graphite-*.png`, `menu-context-web.png`, `settings-web.png`, `popover-web.png`, `start-*.png`.

## Three decisions worth a second look
- **D-154** menus are flat buttons inside the hosts' own popovers, not GMenu models: the skin styles them and tests read them. GMenu would have given Mac-style menus for free later; the Mac gets its own path anyway (D-151).
- **D-155** Inter replaces Noto Sans for canvas text on every design (not only the skins), and the plain JetBrains Mono replaces the Nerd Font build: one atlas set. The Fluent showcase's canvas type changed slightly.
- **D-156** the skin reloads live: the GTK host swaps its CSS provider and the web page swaps a `<style>` and the body class. Everything else in the window stays; nothing restarts.

## What's next
Goal 16's polish list (sheet tabs on the left, hairlines between tool groups, the Σ total row), then the command palette and the Import dialog once MX frame streams.
