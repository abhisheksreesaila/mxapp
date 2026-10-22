# GOAL 31 (draft, parked 2026-10-21 for the island): cards that tile, tiles with defaults, bars that switch smoothly

**Why (owner, 2026-10-21, after the alpha):** "help snap the object when it's added, like Hyprland in Omarchy Linux. Of
course the user can move, but symmetry and snapping are satisfying… the chart controls on first creation are on the
ribbon, which is too restrictive: it needs to pick a default, or put them in the chart inspector… when I picked median
vs count vs sum in the chart, only that was jittery."

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M0 | Tiling, a component | `mojoui/tiling.mojo` with its own test (tests/test_tiling.mojo): a card added to the Board joins the last row while it has room (2 a row; 3 on a page 1,500 points or wider) and the row's cards split its width equally, 16-point gaps, one height; a full row starts a new one at full width; removing a card lets its row's others close the gap; a drop within 24 points of a neighbour's edge, the page's edge or a row's line snaps to it; a drop onto another card swaps their places; a resize snaps to ⅓, ½, ⅔ or the full width and to its row's height; a card nobody tiled (moved freely) is never moved by another's insert |
| M1 | omxplorer tiles its sheet | Chart, then Pivot, then Chart: the first fills the row under the table, the second shares it half and half, the third starts a row; removing one closes the gap; identical BOARD places on GTK and the web; kept across save and reopen (goal 15's checks follow the new places: D-274) |
| M2 | Snap and glide | on GTK and the web, a card dropped 10 points off a neighbour's edge lands on it; dropped on another card, the two swap; a corner drag to just under half the page snaps to half; the host glides a card from where it was to where the app puts it (GTK: frames printed in between; web: a CSS transition), at once when less motion is asked |
| M3 | Tiles and charts start from a default | the Report's toolbar has no "Tiles of" dropdown: **Tile** adds a Sum tile of the sheet's first money column (else its first number column), **Chart** a chart tile of it by the text column with the fewest groups; tapping a tile opens its inspector (Kind: Sum, Average, Median, Distinct, Count; Column), and changing them there changes the tile; each value equals pyarrow's; on GTK and the web |
| M4 | Bars that switch without a jitter | a chart's move is timed by the clock (330 ms whatever the frame rate); switching Sum → Count → Median → Average (and changing the value column) keeps the plot area still in every frame of the move (the axis labels take the new scale at once; the bars grow from the baseline when the units change, glide from their old height when they don't); the chart's canvas keeps its size across a pick; every bar's height moves one way only; at 1M rows the pick's compute and first frame fit 16 ms |
| M5 | Nothing regressed | goal 29's checks (M0–M5; every earlier goal inside them) |

## Out of bounds
Background queries and the island (MX frame 23edc59: goal 31); the omxqua theme (goal 32); a live snap preview while
dragging; tiling on the Report page (its tiles already sit in a grid); pushing (CLAUDE.md: never push).

## Assumptions (instead of asking)
- "The ribbon is too restrictive" means the Report's toolbar (a column picked before adding any tile, six tile buttons);
  the sheet's Chart already picks a default and opens the inspector.
- Hyprland's feel without its rules: rows, equal splits, swap on drop. Cards keep the Board's free placement: a card the
  person moved off the rows is left where they put it.
- The owner's "snap the object when it's added" is the "fill it" answer goal 29 asked for: goal 15's pinned 520×340
  places change to the tiled ones (its other assertions stay).

## Done means
PASS for M0–M5, the reviewer passes it, a short `docs/report.md`; merged into main locally. Budget: 80 turns.
