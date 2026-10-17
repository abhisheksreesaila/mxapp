# GOAL 18: omxapp on the iPad: the kit app, and the UIKit and AppKit hosts catch up (builds here, runs at the weekend)

**End goal (owner's words, 2026-10-17):** "the only target we definitely want is iPadOS"; while MX frame "is still cooking", "work on other things". So: everything omxplorer's screens use (goal 17's components, the Board and Overlay, the skins) exists in the iPad host too, the iPad's own way (hardware keyboard shortcuts, pointer tooltips, popovers, a context menu on right-click or long press), proven as far as Linux can prove it: a kit app that runs on GTK and the web, and links, bundles and signs for iPad and Mac. The owner runs the Apple builds on hardware at the weekend; until then every Apple cell stays 🔨 (built, never run).

## Components this needs (from `docs/components.md`, before the build)
| Component | iPhone/iPad today | Plan |
|---|---|---|
| MenuBar, Menu, Item, ContextMenu | ❌ | UIKit: a menu button per menu (UIMenu of UIActions with key commands); the context menu as a popover of items at the right-click point (D-158); AppKit: the real NSMenu bar (D-150) |
| Dialog, Toast, Popover, Checkbox, tooltips | ❌ | UIKit: a form-sheet view controller, an overlay label, UIPopoverPresentationController, a checkmark button, UIToolTipInteraction; AppKit: a sheet, an overlay, NSPopover, a checkbox, setToolTip: |
| Board, Overlay | ❌ | UIKit/AppKit: a scroll view with framed children; a view with pinned subviews |
| Button styles (SUBTLE, ICON_ONLY, TOOL), text tones, icons | ❌ | UIButtonConfiguration variants with SF Symbols; label colours |
| Canvas: PRESS, RELEASE, DOUBLE, SECONDARY, KEY | ❌ | pan began/ended, a two-tap recogniser, a secondary-button tap and a long press, pressesBegan for hardware keys |
| Design: the skins (colours, Inter and JetBrains Mono) | ❌ | `design()` → UIColor/NSColor from the palette; the bundled fonts registered from the app bundle (D-155) |
| A kit app (every component on one screen set) | — | `examples/kit`: the proving ground for every host (D-157) |

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | The kit app on Linux and the web | `examples/kit` shows a menu bar, tool buttons with tooltips, a canvas with a context menu, a dialog, a toast, a popover, checkboxes, a Board with an Overlay island, and a skin switch; driven on both hosts (menu, rightclick, dialog, toast, popover, skin steps) with identical dumps; Ledger light and Graphite dark screenshots |
| M2 | The UIKit host catches up | `uikit.mojo` builds every kind the kit uses (a script lists each `kind ==` branch), the button styles, tones, tooltips, the canvas gestures and the skins; `scripts/build.sh kit ios` links, bundles and signs with only the allowed symbols; the matrix shows the new components 🔨 on iPhone |
| M3 | iPad | Info.plist allows every iPad orientation and multitasking; shortcuts from Items become UIKeyCommands (Ctrl = ⌘, D-159); tooltips use UIToolTipInteraction; a secondary-button tap or long press sends SECONDARY; the bundled fonts go into the .app and are registered at start; the build links |
| M4 | The AppKit host catches up | the same kinds on the Mac, the menu bar as the system menu bar with ⌘ shortcuts; `scripts/build.sh kit mac` links, bundles and signs; the matrix shows them 🔨 on Mac |
| M5 | Nothing regressed | goal 17's checks (and every earlier goal's inside them) still pass; the matrix is current |

## Done means
`scripts/check` prints PASS for M1–M5; push to `origin` after. `docs/report.md` says plainly that the Apple builds haven't run on hardware.

## Out of bounds
Running on Apple hardware (the owner's weekend); omxplorer itself on the iPad (its CSV and .omx shims need Python until MX frame lands); Android parity; the WebAssembly target (D-90: waits for a wasm32 Mojo); no deploying, no paid services, no secrets, nothing outside this repo; `../mojo-ui-apple-test` stays untouched.

## Assumptions
- D-157: the kit app is the components' proving ground on every host (components first).
- D-158: on iPad, context menus and popovers are popover-presented controllers of the app's own items (no public API presents a UIMenu at a point); the menu bar's menus are UIMenus on menu buttons.
- D-159: "Ctrl" in a shortcut means ⌘ on Apple platforms.
- Objective-C calls follow objc.mojo's style; new C functions go through `cfunc` (dlsym), so the .tbd stubs and ALLOWED don't change.
- Budget: the evening (about 100 turns).
