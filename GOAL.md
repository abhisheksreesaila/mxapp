# GOAL 17: omxplorer's universal theme (Ledger) and the components it needs (Linux + web)

**End goal (owner's words, 2026-10-17):** "I want this to have universal theme on all platforms just for this app, think EXCEL, same theme on all"; "I am fan of ledger produced by CLAUDE… we can use that as default, but ship all skins for people to change"; "dont you need additional components like menu bar etc"; "please continue with building additional components needed to make this UI happen". Design: `docs/design/universal.md` and `docs/design/universal/kit.html` (Ledger default; Graphite and Blueprint as skins).

## Components this needs (from `docs/components.md`, before the build)
| Component | Before | Plan |
|---|---|---|
| A fixed skin: colours, Inter and JetBrains Mono shipped with the app | Fluent and Omarchy (the desktop's theme) | `Palette.ledger/graphite/blueprint`, `design() = LEDGER…`; one CSS per host from the palette; the fonts in `mojoui/hosts/static/fonts/`, baked for canvases |
| Menu bar, menus, context menu, keyboard shortcuts | nothing | `mojoui/menus.mojo`: `MenuBar`, `Menu`, `Item`, `ContextMenu`; a `SECONDARY` canvas gesture; shortcuts bound by the host |
| Dialog with a scrim, Toast with an action, Tooltip, Checkbox, Popover | `Alert` only | `mojoui/overlays.mojo`: `Dialog`, `Toast`, `Popover`; `.tooltip()`; `Checkbox` |
| Grid states: a type badge per column, a corner mark on edited cells | names only; a sort triangle | `DataGrid` draws them |
| Settings → Appearance (skin picker, saved), About, the Start screen | the Omarchy start screen | omxplorer composites from the above; `settings.txt` in the config folder |

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | The skins | `Palette.ledger()`, `graphite()`, `blueprint()` with the kit's exact colours (test); the fonts are in the repo with their licences and the canvas atlases are baked from them; omxplorer on both hosts reports `DESIGN: ledger` with a light sheet, and `skin=graphite` in the config folder's `settings.txt` gives `DESIGN: graphite` with a dark one (screenshot brightness); the web page loads Inter |
| M2 | Menus | `MenuBar`, `Menu`, `Item`, `ContextMenu` in mojoui with a test; omxplorer's menu bar on both hosts lists the same menus and items; `menu:Data>Sort largest first` sorts the sheet; `shortcut:Ctrl+S` saves the document; a right-click on a column header opens a context menu (`rightclick:` step) whose `Sort largest first` sorts; identical dumps on GTK and web |
| M3 | Dialogs, toasts, tooltips, checkboxes, popovers | in mojoui with a test; `menu:File>Settings…` opens a Settings dialog on both hosts; `radio:0=Graphite` switches the skin live (`DESIGN: graphite`, dark screenshot) and writes `settings.txt`; a sort shows a toast with Undo and `toast:Undo` undoes it; every toolbar button has a tooltip (`TIP:` lines); the Settings checkboxes report `CHECK:`; the formula bar's ƒx opens a popover (`POPOVER:`) that closes; identical on GTK and web |
| M4 | Grid states | the header shows a type badge per column (`#`, `$`, `Aa`, `date`, `ƒx`) and an edited cell gets an accent corner mark (test_datagrid draws and reads the pixels) |
| M5 | omxplorer in the Ledger | the Start screen (drop zone, recent files, samples) and the sheet carry the menu bar; `menu:Help>About omxplorer` opens the About dialog; the start and sheet dumps are identical on GTK and web |
| M6 | Nothing regressed | goal 15's checks (and every earlier goal's inside them) still pass; the matrix is current and lists the new components ✅ on Linux and web |

## Done means
`scripts/check` prints PASS for M1–M6; push to `origin` after (the owner allowed pushes at stopping points).

## Out of bounds
The command palette, the Import dialog's streaming (waits for MX frame), the column filter popover (needs row masks in the engine), phone bottom sheets, column header histograms, own-drawn controls on Mac, iPhone and Android (D-151). No deploying, no paid services, no secrets, nothing outside this repo. Omarchy stays the look of the other examples.

## Assumptions
- D-151: Mac, iPhone and Android keep native controls for now; omxplorer draws its own there later.
- D-152: Windows is covered by the web host until there's a Windows host.
- D-153: the phone uses the same skins, with bottom sheets instead of menus, later.
- D-154: menus are built from the hosts' own popovers and buttons (not GMenu models), so the skin styles them and tests can read them.
- D-155: Inter replaces Noto Sans for canvas text on every design, and JetBrains Mono replaces the Nerd Font build; both are vendored (SIL OFL).
- D-156: the skin lives in `<config>/settings.txt` (`skin=ledger`); the hosts reload their CSS when `design()` changes, so the switch is live.
- Budget: the rest of today (about 120 turns).
