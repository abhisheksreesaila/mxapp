# Goal 18 report: omxapp on the iPad: the kit app, the UIKit and AppKit hosts

**End goal:** the owner's definite target is iPadOS. While MX frame is still being written, everything omxplorer's screens use should exist in the iPad host too, the iPad's own way, proven as far as Linux can prove it.

**Plainly: no Apple build has run on hardware yet.** This goal proves that the kit links, bundles and signs for iPad and Mac with only the allowed symbols, and that the hosts build every kind the kit uses. The owner runs them at the weekend; every Apple cell in `docs/components.md` stays 🔨 until then.

## How far it got
`scripts/check` (`build/check-goal18.log`):

| # | Milestone | Result |
|---|---|---|
| M1 | The kit app on GTK and the web: menus, Ctrl+S, a context menu, a dialog, a toast with Undo, a popover, checkboxes, a Board drag, a skin switch; identical dumps; light and dark | PASS |
| M2 | The UIKit host builds every kind the kit uses; the kit links, bundles and signs for iPad; 🔨 on iPhone | PASS |
| M3 | iPad: every orientation, multitasking, ⌘ shortcuts from menu items, pointer tooltips, right click / long press, hardware keys, bundled fonts | PASS |
| M4 | The AppKit host: the same, with the app's menus in the system menu bar; the kit links, bundles and signs for Mac | PASS |
| M5 | Goal 17's checks (goals 3–15 inside them) and the matrix | PASS |

## 30-second demo
```
scripts/build.sh kit all      # Linux, web, Mac (.app + zip), iPad/iPhone (.ipa)
build/kit/linux/kit           # the kit on Linux: right-click the canvas, File > Save, Ctrl+S, the skin segments
apple/install_iphone.sh kit   # the owner's wizard: xtool installs build/kit/ios/KitMojo.ipa on a device
```

## What to look at first on the iPad (the weekend)
1. Does the window show the kit at all (the Board with the table and note, the inspector)?
2. File menu button → a UIMenu with Save (⌘S shown); ⌘S from a hardware keyboard saves (the status bar says so).
3. Right-click (trackpad) or long-press the canvas → a popover of items; "Sort Z→A" updates the status bar; tapping outside closes it (on_close).
4. "Open dialog" → a form sheet with the radio skins and checkboxes; Done closes it; Graphite turns the window dark.
5. "Show toast" → a strip at the bottom with Undo and ✕; it leaves after 6 s.
6. Drag the note by its title (the Board's on_move).
7. Hover a tool button with a trackpad → a tooltip.

## Three decisions worth a second look
- **D-157** the kit app is the proving ground: every host builds it, and its screen is the contract the matrix reads.
- **D-158** on iPad, context menus and popovers are popover-presented controllers of plain buttons, not UIKit's context-menu interaction (which needs the menu at interaction time; our model opens it after a round trip).
- **D-159** "Ctrl" means ⌘ on Apple platforms.

## What's next
The weekend run; then fix what it shows. omxplorer itself reaches the iPad once MX frame replaces its Python shims. The wasm target stays parked (D-90).
