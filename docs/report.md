# Report: layout as a thin layer (goal 5)

**End goal (your words):** "just use the existing layout, the flex layout… a very thin wrapper… one language… a very thin layer between the code we write and what compiles."

**Result:** 11/11. Every view now takes flexbox-named layout settings:
- `padding`, `width`/`height`, `min_width`/`max_width`;
- `grow`, `fill`;
- on stacks, `align` and `justify`;
- `tag`, which names a view for tests and accessibility.

Each host translates them straight into its own layout system. There's no layout engine of ours: CSS flexbox on the web, GtkBox with CSS padding on Linux, and NSStackView/UIStackView with Auto Layout on Apple.

```
$ scripts/check
PASS  M1  layout settings on every view; core tests pass
PASS  M2  padding 16: the child sits 16 in from the box's left and top, on GTK + web
PASS  M3  fixed 200×60 exact; max width 200 and min width 150 respected, on GTK + web
PASS  M4  a filled child spans its 320-wide box minus 10+10 padding, on GTK + web
PASS  M5  a growing child takes the rest of its 320-wide row, on GTK + web
PASS  M6  justify START/CENTER/END/BETWEEN in 320-wide rows, on GTK + web
PASS  M7  align START/CENTER/END/STRETCH in 320-wide columns, on GTK + web
PASS  M8  layout settings mapped to NSStackView/UIStackView + Auto Layout; layout, expenses, kitchen build and sign
PASS  M9  Pocket Expenses and todo use fill/grow/padding/justify; GTK + web still identical
PASS  M10  goal 4's checks (and goal 3's inside them) still pass
PASS  M11  README documents every layout setting; all paths exist
```

**How it's proven:** the checker measures the real widgets on GTK (window shown) and in Chromium. It checks the same relations on both, within 1.5 points:
- a padded child sits exactly 16 in;
- a fixed button is exactly 200×60;
- a filled child is its box minus padding;
- a growing child takes the rest of its row;
- all four `justify` and four `align` modes put children where flexbox says.

Layout isn't pixel-identical across platforms (fonts and control heights differ), but the geometry rules are the same.

**Real apps use it:** Pocket Expenses and the todo app now use full-width fields and lists, a growing text field, and justified total rows (`docs/img/expenses-*.png`, `docs/img/todo-*.png`).

## Found by looking, not just measuring
The relation checks passed, but the screenshots showed three mapping gaps:
- on the web, a growing field pushed "Add" onto a new line;
- on the web, `Scroll` laid rows out sideways;
- on GTK, a "fixed" width was only a minimum, and wrapping labels squeezed to one word per line.

All are fixed.

A test window also caught real keystrokes from your desktop, so test windows now ignore real input.

The review then found that each host's built-in control widths fought the app's layout settings, for example a field's default 200 points against `fill()` in a 320-point column. On iPhone and Mac that's an Auto Layout conflict; on web and GTK the list stuck out of its column. Now:
- **A built-in width is only a preference:** a lower-priority constraint on Apple, dropped or overridable on GTK and the web. The app's own settings always win.
- **The checker measures it:** in Pocket Expenses the field and list span their 320-point columns exactly, on both hosts.

## Worth your second look
1. **Sizes are border-box everywhere**: `width(300)` includes padding. GTK size requests already work that way. On Apple I add the constraints to the outer (padded) view.
2. **On GTK, fixed and maximum widths go through `AdwClamp`**, because GTK's size request is only a minimum.
3. **Apple layout is compiled and signed but not yet run.** The reviewer passed it after three rounds of checking the compiled calls. Real Auto Layout behaviour is the part your Mac and iPhone test will prove.

**Next:** your Apple test results, then the Android route.
