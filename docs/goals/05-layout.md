# GOAL 5: layout, as a thin layer over each platform's own layout

**End goal (owner's words, 2026-10-15):** "I would just use the existing layout, the flex layout… I like your hybrid approach… the vision is a very thin wrapper… one language… a very thin layer between the code we write and what compiles." (ROADMAP decision 10.)

Layout settings with flexbox names, on any view, mapped by each host onto its native layout system (GtkBox/CSS, CSS flexbox, NSStackView, UIStackView). No layout engine of our own.

## API (chainable, on any View)
`.padding(all)` / `.padding(vertical, horizontal)`, `.width(n)`, `.height(n)`, `.min_width(n)`, `.max_width(n)`, `.grow()` (take the free space along the parent's direction), `.fill()` (stretch across the parent's direction), and on stacks `.align(START|CENTER|END|STRETCH)` (cross axis) and `.justify(START|CENTER|END|BETWEEN)` (main axis); `.tag(name)` names a view for tests and accessibility. Sizes are in points and include padding (border-box), on every host.

## Milestones
GTK runs show the window (it must lay out to be measured); both hosts report each tagged view's box (x, y, width, height); the checker asserts the same geometric relations on both, within 1.5 points.

| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Core API | settings stored on nodes; layout changes are rebuilds or patches as appropriate; tests pass |
| M2 | Padding | a padded box's child sits exactly `padding` in from the box's edges, on GTK + web |
| M3 | Sizes | fixed width/height are exact; min/max width are respected, on GTK + web |
| M4 | Fill | a filled child spans its parent's width minus padding, on GTK + web |
| M5 | Grow | a growing child takes all the free space in its row (siblings + gaps + it = row width), on GTK + web |
| M6 | Justify | START/CENTER/END/BETWEEN place children at the start, middle, end, or both ends of a wider row, on GTK + web |
| M7 | Align | START/CENTER/END/STRETCH line children up on the cross axis, on GTK + web |
| M8 | Apple | layout settings map onto NSStackView/UIStackView + Auto Layout; layout, expenses and kitchen build, link and sign |
| M9 | Real apps use it | Pocket Expenses and the todo app use layout settings (full-width fields and lists, growing labels, a justified total row); their GTK + web runs stay identical |
| M10 | Nothing regressed | goal 4's checks still pass |
| M11 | Docs | README documents every setting with an example; every path exists |

## Out of bounds
As before: no deploying, sign-ups, logins, secrets, pushing or licences; windows may flash briefly during checks only; don't touch `../mojo-ui-apple-test`.

## Assumptions
- Defaults stay as they are (stacks centre their children), so existing apps don't change until they use a setting.
- Hosts may add invisible helper views (e.g. spacers for `justify` on GTK) — that's still a mapping, not an engine.
- Layout isn't pixel-identical across platforms (fonts, control sizes differ); the checks prove the *relations*.

## Budget
~5 hours. Stop with a clear report if blocked.
