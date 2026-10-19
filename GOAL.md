# GOAL 24: omxplorer, polished: Liquid, smooth, a showcase

**End goal (owner, 2026-10-18):** "now it's about helping the user get there quickly with all the styling necessary… take the components we have built in this framework, style it the way you want, and show them an app so liquid, so smooth, so fast that they are like wow… the focus now is not to get the features right, but the polish, the current features right." The vision stays: one language, one set of components, every platform. omxplorer is the showcase of how far a skin on those components can go (Linux GTK and the web now; the Mac's own Liquid Glass later).

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | The Liquid design, chosen and handed off | `docs/design/liquid/`: Stitch's and Claude's start, import, sheet, report and phone side by side (`compare.html`); `docs/design/liquid.md` names the chosen option, tokens, motion and a gestures table; the choice is in `docs/decisions.md` |
| M2 | Liquid is omxplorer's skin, on GTK and the web | a fresh install opens in Liquid (`DESIGN: liquid`) on both hosts; Settings still offers Ledger, Graphite and Blueprint; screenshots of start, import, sheet and report show the backdrop around floating islands (toolbar inset from the window, backdrop colour beside it, a white sheet inside), saved to `build/g24/` with a side-by-side page against the design |
| M3 | The screens the owner flagged look right | every row of an open menu (submenus included) has the same height and type; the import dialog's column table lines up with its preview and its empty area holds no stray drawing; report tiles sit in a grid of equal widths (at most 3 a row) with their remove button inside the tile; the toolbar's tools share one height; the Liquid skin uses one type scale (11, 12, 13, 15, 17, 22, 34 px) |
| M4 | Liquid motion | the Liquid skin animates hover and press (transitions) and menus, popovers and dialogs arriving (a spring-shaped animation) on both hosts; moving the selection glides the ring over at least 6 frames, each drawn in under 20 ms (GTK, measured) |
| M5 | Select a range of cells | a drag, Shift+click or Shift+arrows select a block; the status bar's Sum, Average and Count are the block's (pyarrow's answer); Bold applies to every cell of the block; Copy puts the block on the clipboard as tab-separated text; the same on GTK and the web |
| M6 | Nothing regressed | goal 23's checks (M1–M3; every earlier goal's inside them) pass |

## Done means
`scripts/check` prints PASS for M1–M6; `docs/report.md` is short, with before/after screenshots. Push to `origin` after (owner's standing permission).

## Out of bounds
New features beyond range selection (no SQL, no AI, no new tile kinds); changing MX frame; deploying, paid services, secrets, anything outside this repo; `../mojo-ui-apple-test` stays untouched; the phone design is a reference only (no phone build this goal).

## Assumptions
- D-225: Liquid **light** (frosted white glass over a soft cool backdrop) with omxplorer's teal, not Liquid's navy: long sessions with numbers, the owner's earlier pick of a light sheet, and a Mac-like feel. Ledger, Graphite and Blueprint stay as switchable skins.
- GTK can't blur what is behind a widget (no backdrop-filter): on Linux, glass is translucent white with a rim, a highlight and a soft shadow over the backdrop; the web gets the real blur; the Mac's own glass waits for its host.
- GTK's CSS has no `linear()` easing: springs are keyframe animations with an overshoot and cubic-bezier steps; canvas motion (the selection ring) runs on the frame clock.
- D-230: Liquid lives in the framework (any app's `design()` can pick it), because AG-UI generative interfaces, a video editor and graphics simulations come next on this baseline (owner, 2026-10-18).
- Budget: about 80 turns.
