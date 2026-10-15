# Decisions (autopilot)

One line per fork: `D-nn · chose X over Y · why · reversible?`

- D-01 · Mojo calls AppKit/UIKit through the Objective-C runtime, over a SwiftUI skin or GPU-drawn UI · the owner picked "Mojo drives Apple UI" · yes
- D-02 · look up `objc_msgSend` at runtime (`OwnedDLHandle`) over `external_call` · Mojo rejects one C symbol declared with two signatures in a module, and every UI call needs a different one · yes
- D-03 · pass CGRect/NSRect as four Float64 arguments over a C helper · on arm64 a 4-double struct travels in the same four float registers, and it keeps the app C-free; wrong on Intel, which is out of scope · yes
- D-04 · write the 3 Mojo runtime functions (AlignedAlloc, AlignedFree, GetStackTrace) in Mojo, in their own file, over linking Modular's runtime dylib or a C shim · app becomes self-contained and C-free; separate file because Mojo refuses to define them in a module that also calls them · yes
- D-05 · link on Linux with pixi's `ld64.lld` + hand-written `.tbd` symbol stubs over the real Apple SDK · the SDK needs an Apple login (out of bounds); the stubs only list names and install paths · yes
- D-06 · enter the app through the linker's `-e _mojo_entry` (LC_MAIN) over a C `main` · removes the last C file · yes
- D-07 · iOS uses the scene lifecycle (UIWindowScene) over a classic app-delegate window · recent iOS releases require scenes; it also avoids needing the screen size · yes
- D-08 · keep `ios-xtool/` (SwiftUI skin) as a fallback, marked superseded, over deleting it · reversible and costs nothing · yes
- D-09 · own signature verifier (`scripts/verify_signature.py`: recompute page + Info.plist hashes) over `rcodesign verify` · rcodesign says its verify is buggy and it fails on every ad-hoc signature; checking on the executable, not the bundle folder. Also tightened: entry point must be `_mojo_entry`, no stray bytes after the signature · yes
- D-10 · one variadic `msg()` that casts `objc_msgSend`'s address (copied from Mojo's own `_DLCallable`) over five `OwnedDLHandle` overloads · fewer lines, no dlopen/dlclose per call, nothing raises · yes
- D-11 · iPhone button uses Liquid Glass (`prominentGlassButtonConfiguration`, iOS 26+) when the class responds to it, else a filled capsule · phone follows the Liquid design language; the check keeps it working on iOS 17-18 · yes
- D-12 · reviewer findings: fixed 1-9 (protocol miss now printed; build.sh fails on Mojo errors and deletes stale objects; Gatekeeper advice for macOS 15+; BOOL encodings `B`; allowlist + stubs trimmed to exactly what's used; resource seal checked; iOS Dynamic Type; Cmd+W) · #10 (bundle ID clash) is a non-issue: xtool prefixes a per-user ID (ProvisioningIdentifiers.swift:24) · yes
- D-13 · mark binaries as built with SDK 26 (`-platform_version ios 17.0 26.0`, `macos 14.0 26.0`) over 17/14 · otherwise iOS/macOS 26 run the app in compatibility mode without the current look; unproven without the real SDK, one-line revert · yes

## Goal 2: declarative UI
- D-14 · view tree stored as a flat list of nodes (parent → child indexes) over a recursive struct · Mojo 1.1 rejects `List[View]` inside `View` ("non-Deinitable"); a flat list is also easy to diff and to pair with native handles · yes
- D-15 · Linux renderer: GTK4 + libadwaita over SDL3+Clay (ROADMAP decision 4) · the owner asked for *native* rendering; GTK is Linux's native toolkit, it's installed, and it can be run and screenshotted here · yes
- D-16 · platforms this run: Linux, Mac, iPhone; web/Android/Windows logged as next · only these have a Mojo build target and a native toolkit reachable today · yes
- D-17 · hosts create the app themselves (`App` requires `__init__()`) over passing an instance in · UIKit builds the window later in a scene callback that can't carry data · yes
- D-18 · Apple taps: button tag packs `(host address << 16) | node` over associated objects / ivars · no globals and no extra Objective-C runtime functions; checked at start-up that the address fits · yes
- D-19 · taps look the message up in the current tree by node index over storing the message on the widget · message changes (SET_MSG) then need no rewiring · yes
- D-20 · GTK test mode doesn't show the window (unless asked for a PNG) over always presenting it · checker runs don't pop windows on the owner's desktop; the widgets and taps are still real GTK · yes
- D-21 · screenshots rendered by GTK itself (widget → paintable → texture → PNG) over grabbing the screen with grim · no desktop disruption, exact pixels GTK drew · yes
- D-22 · stand-in for `KGEN_CompilerRT_fprintf` (writes the raw format string) and `bzero` added to the allowlist · Mojo's bounds-check failure path needs fprintf; bzero is a real libSystem function · yes
- D-23 · apps name the parameter `message`, not `msg`, over loosening the checker's platform-word list · `msg` is the Objective-C helper's name; the checker stays strict · yes
- D-24 · removed experiment 1's hand-written Mac/iPhone apps and `apple/build.sh` · superseded by the declarative hosts + `scripts/build.sh`; still in git history · yes (git)
