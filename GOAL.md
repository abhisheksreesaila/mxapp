# GOAL: Mojo all the way, on Mac then iPhone

**End goal:** "Create a Mojo app for macOS which I can test, and then do it for iOS, and tell me how to install and test it. Mojo all the way."

## Milestones
Each one is checked by `scripts/check` (prints PASS or FAIL per milestone). Everything is built on this Linux machine.

| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | The app's logic is plain Mojo with tests | `tests/test_hello_core.mojo` runs and its asserts pass |
| M2 | The Mac app is all Mojo and needs no Mojo runtime | `apple/mac/hello_mac.mojo` + `apple/mojo_rt.mojo` compile for `arm64-apple-macos`; their undefined symbols are only Apple system functions on the allowlist; no `.c`, `.m` or `.swift` files under `apple/` |
| M3 | A signed Mac app bundle exists | `build/mac/HelloMojo.app`: arm64 Mach-O executable with an `LC_MAIN` entry, loads AppKit, libobjc and libSystem only, valid Info.plist, code signature verifies with `rcodesign` |
| M4 | The iPhone app is all Mojo too | `apple/ios/hello_ios.mojo` + `apple/mojo_rt.mojo` compile for `arm64-apple-ios17.0`; undefined symbols only on the allowlist |
| M5 | An installable iPhone app exists | `build/ios/HelloMojo.ipa` contains `Payload/HelloMojo.app` with an arm64 iOS Mach-O (platform iOS), loads UIKit, Info.plist has the iOS keys and a scene manifest, signature verifies |
| M6 | You can test it from instructions alone | `apple/README.md` has Mac and iPhone install steps; every command and path it names exists in the repo |

## Done means
`scripts/check` prints PASS for M1 to M6, and the report says plainly what was only checked here (structure, symbols, signature) versus what needs a real Mac and iPhone (running it).

## Out of bounds
No deploying, no paid services or sign-ups, no Apple login, no secrets, no pushing anywhere, nothing outside this folder (except pixi's own cache).

## Assumptions (made instead of asking)
- "Mojo all the way" = app logic **and** UI code in Mojo; Mojo calls Apple's AppKit/UIKit directly through the Objective-C runtime. No Swift, no C, no Objective-C source files.
- Apple Silicon only (the user has one). Rects are passed as 4 floats, which is only correct on arm64.
- The three tiny Mojo runtime functions are written in Mojo (`apple/mojo_rt.mojo`) instead of linking Modular's runtime, so the app is self-contained. Unofficial; signatures read from compiled code.
- The apps are linked on Linux with `ld64.lld` against small hand-written `.tbd` stubs (symbol lists) for Apple's system libraries, not the real Apple SDK (which needs an Apple login).
- iPhone install uses `xtool install` with the user's free Apple ID (it re-signs the app); the Mac app is ad-hoc signed.
- iOS uses the scene lifecycle, since recent iOS versions require it.

## Budget
80 turns. Stop early with a clear report if blocked.
