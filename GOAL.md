# GOAL 2: declarative Mojo UI, rendered natively everywhere

**End goal (owner's words):** "All I want is Mojo declarative code and then it's rendered natively on all the platforms. That's it."

Experiment 1 (`docs/goals/01-mojo-all-the-way.md`) proved Mojo can drive AppKit and UIKit directly. This one adds the declarative layer: write the screen once as data, and a native renderer per platform draws it.

## Milestones
`scripts/check` prints PASS or FAIL per milestone.

| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Declarative core | `mojoui/` gives `VStack`, `HStack`, `Text`, `Button`, `Spacer` and an `App` trait (`view()`, `update()`); `tests/test_mojoui.mojo` passes: exact trees, updates, and diffs (text change → one in-place patch; shape change → rebuild) |
| M2 | Linux, native GTK | `examples/hello/app.mojo` runs as a real GTK4 window; in test mode it taps the real Greet button 3 times and reads the real label back: `Hello, Ada! (click 3)` |
| M3 | Mac, native AppKit | the same `examples/hello/app.mojo` builds into a signed `HelloMojo.app` (same symbol/entry/library/signature checks as experiment 1) |
| M4 | iPhone, native UIKit | the same file builds into a signed `HelloMojo.ipa` (same checks) |
| M5 | Truly one source | the app files import only `mojoui` (no AppKit, UIKit, GTK or objc names), and all three builds compile the identical file |
| M6 | Not a one-off | a second example with a changing structure, `examples/todo/app.mojo` (add/remove rows), passes a GTK test-mode run and builds for Mac and iPhone |
| M7 | You can try it | `README.md` and `apple/README.md` show how to write an app and run it on each platform; every path they name exists |

## Done means
`scripts/check` passes M1–M7; the Linux version is also shown as a real screenshot; the report says plainly what ran here (Linux) versus what still needs your Mac and iPhone.

## Out of bounds
No deploying, paid services, sign-ups, Apple login, secrets or pushing. Nothing outside this folder.

## Assumptions (made instead of asking)
- "All the platforms" = where Mojo runs and we can build today: **Linux (GTK4), Mac (AppKit), iPhone (UIKit)**. Web, Android and Windows are next steps, not this run (no Mojo target for Android/Windows yet; web needs its own design).
- Native = each platform's own toolkit draws its own controls (GTK4 + libadwaita on Linux).
- Messages are plain `Int` ids for now (e.g. `comptime GREET = 1`); richer message types later.
- Updates: compare the old and new trees; same shape → change only what changed (e.g. a label's text); different shape → rebuild the window's content. Fine for small apps.
- The app module is called `app.mojo` and defines `Main`; each platform's host imports it.

## Budget
80 turns. Stop early with a clear report if blocked.
