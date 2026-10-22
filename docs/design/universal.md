# omxplorer's universal theme: the hand-off

**Status:** built on Linux and the web (goal 17, 2026-10-17): Claude's **Ledger** is the default, **Graphite** and **Blueprint** switch live from Settings → Appearance. The open decisions below were taken as D-151–D-153 (docs/decisions.md).
**Look at:** `universal/kit.html` (every component, every state, in all three skins: switch at the top), `universal/claude.html` (sheet, Report, phone), `universal/compare.html` (Stitch vs Claude).
**Colours:** `universal/ledger.md`, `graphite.md` and `blueprint.md`. The CSS variables in `universal/omx.css` are the source of truth, and `Palette.ledger()` etc. copy them.

## What "universal" means
- omxplorer looks the same on Linux, Windows, Mac, the web, iPad and phones, like Excel: its own colours, its own two fonts, and its own controls. It doesn't follow the desktop theme.
  - Omarchy stays the look of the other examples; it isn't omxplorer's.
- Both fonts ship inside the app:
  - **Inter** for words.
  - **JetBrains Mono** for numbers: tabular and right-aligned.
- **Skins** change colours only. The layout, sizes, fonts and components are identical in every skin.
  - Settings → Appearance picks a skin.
  - "When the computer is in dark mode, use" picks a second skin, Graphite by default, which is the only link to the system's theme.
- There are only three exceptions, all places where people expect their own system:
  - **On a Mac the menus go in the system menu bar** and the shortcuts show ⌘.
  - The **file open and save dialogs** are the system's own.
  - Phone **safe areas** are respected.

## Can the real app reach this much detail?
Yes for most of it. Today's app already has the same structure: toolbar, formula bar, grid, inspector, sheet tabs and status bar (`mojoui/sheetchrome.mojo`, `inspector.mojo`, `datagrid.mojo`). What differs is how each part is drawn:

| Part | How it's drawn | Same everywhere? | Work |
|---|---|---|---|
| Grid, header histograms, charts, sparklines, KPI figures | the Mojo canvas, pixel by pixel | **yes, already**: the same pixels on every host | Ledger colours; bake Inter into the canvas font atlases (today it's Noto Sans, `scripts/bake_font.py`); new grid states (below) |
| Buttons, fields, dropdowns, tabs, toolbar (native controls) | GTK widgets and web HTML, styled with CSS per design language (as Fluent and Omarchy are today) | **yes on Linux and the web**, close to pixel-identical | a `LEDGER`/`GRAPHITE`/`BLUEPRINT` CSS for GTK and web, from the tokens |
| The same on Mac, iPhone and Android | AppKit, UIKit and Android views | **no**: they can't be restyled to match exactly | **open decision 1** |
| Menus, popovers, dialogs, toasts, tooltips, command palette | **don't exist yet** | — | new components (below) |

## Components: what exists and what's missing
✅ in `docs/components.md` today · 🔧 exists, needs more states · 🆕 new

| Component | Status | Needs |
|---|---|---|
| Button | 🔧 | hover, pressed, **focus ring**, disabled and danger styles; icon-only and icon + label |
| TextField | 🔧 | focus ring, **error state with a help line**, read-only, search with a shortcut hint |
| Dropdown | 🔧 | the open list drawn in the theme (check on the chosen item, disabled items) |
| Toggle (switch), Segmented, Slider, Radio | 🔧 | theme colours only |
| **Checkbox** (with "some" for Select all) | 🆕 | the filter popover and Import |
| Stepper | 🔧 | used in the inspector as a composite; make it a component |
| Chip (filter chip with ✕, "+ Filter") | 🆕 | the Report filters |
| Tabs (inspector, dialog steps) | 🔧 | an underline style |
| Sheet tabs | ✅ | the accent top edge |
| ProgressBar | 🔧 | an unknown-length style, and **Cancel** beside it (bigger-than-memory) |
| Spinner, skeleton rows | 🆕 | rows still loading show grey bars, never zeros |
| Alert / banner | 🔧 | info, warning and error tones, with an action link |
| **Menu bar** | 🆕 | File · Edit · View · Insert · Data · Format · Window · Help, in the title bar (Linux, Windows, web); the Mac's system menu bar |
| **Menu / context menu** | 🆕 | icons, shortcuts, a checkmark, disabled, danger, separators, section labels, **submenus**; right-click on headers, cells and tabs; ⋯ on a phone |
| **Popover** | 🆕 | anchored to an element (the column filter) |
| **Dialog** with a scrim | 🆕 | Import, Settings, confirmations |
| **Toast** with Undo | 🆕 | after sort, filter and delete |
| **Tooltip** with a shortcut | 🆕 | every toolbar button |
| **Command palette** (Ctrl+K) | 🆕 | searches every menu item, column and recent file |
| **Bottom sheet** (phone) | 🆕 | where menus, popovers and the inspector go on a phone |
| Keyboard key (kbd) | 🆕 | in menus, tooltips and the palette |
| Start screen | 🆕 composite | open, drop a file, recent, samples, GPU status |
| Import dialog | 🆕 composite | preview, a type per column, values that didn't parse, background loading with progress (MX frame spec §7a) |
| Settings → Appearance | 🆕 composite | skin picker, dark-mode skin, row height, text size |
| DataGrid states | 🔧 | sorted ▾ and filtered headers, a frozen first column, selected range, editing, **a corner mark on cells changed from the file**, **empty shown as "empty"** (not 0), **errors as words (÷ 0)**, find match |

That's about 15 new components and 10 extended ones. Each one goes into `mojoui/` with its own test on GTK and the web first, per the components-first rule, and then into omxplorer.

## Open decisions (the owner's, before the build)
1. **Mac, iPhone and Android: draw our own controls, or keep native ones?**
   - To be identical everywhere, omxcode would draw buttons, fields and menus on its canvas there, as Flutter and Office do. That's more work, and it loses some native behaviour: accessibility, text input and the system spell-check.
   - Keeping native controls means a Ledger-coloured near-match.
   - *Recommendation:* draw our own for omxplorer's chrome on every platform except text input and the system menu bar and file dialogs. Do it after Linux and the web are done.
2. **Windows:** it isn't a host yet. The web host covers it until there's one.
3. **Phone:** is the phone layout the same app in a narrow window (what's drawn), or a separate phone design (Liquid, per the global rule)? *Recommendation:* the same skins, with bottom sheets instead of menus, because "the same everywhere" is the point.

## Build order (after the decisions)
1. Add `Palette.ledger()`, `graphite()` and `blueprint()`, and `design() = LEDGER …`.
   - Make the skin a setting stored in OMX_CONFIG.
   - Add GTK and web CSS generated from the same tokens.
   - Bake Inter.
2. Build the new components in this order: Menu, Popover, Dialog, Toast, Tooltip, Checkbox, then the menu bar, then the command palette.
3. Add the grid states.
4. Build the composites: Start, Import and Settings.
5. Check every screen in kit.html against a screenshot of the running app in all three skins.
