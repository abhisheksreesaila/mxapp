# Report: Mojo all the way, on Mac and iPhone

**End goal:** "Create a Mojo app for macOS which I can test, then do it for iOS, and tell me how to install and test it. Mojo all the way."

**How far it got:** all 6 milestones pass on Linux. Both apps are built, linked and signed, and ready for you to run. **Neither has run on real hardware yet**: that's the one check only you can do.

```
$ scripts/check
PASS  M1  ALL TESTS PASSED
PASS  M2  undefined symbols all Apple system functions; no C/ObjC/Swift sources
PASS  M3  Mach-O 64-bit arm64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|PIE>; loads 3 system libs; signed
PASS  M4  undefined symbols all Apple system functions; no C/ObjC/Swift sources
PASS  M5  Mach-O 64-bit arm64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|PIE>; loads 3 system libs; signed
PASS  M6  Mac and iPhone sections present; all referenced files exist
```

## What "Mojo all the way" turned out to mean
- The logic, the native UI calls (AppKit on Mac, UIKit on iPhone), the app's start-up and even Mojo's own tiny runtime are all Mojo. There's no Swift, C or Objective-C file in `apple/`.
- The Mac app is a 64 KB executable and the iPhone `.ipa` is 14 KB. They load only Apple's own libraries, with no Modular runtime.
- Built entirely on this Linux machine; no Mac or Xcode needed to build.

## 30-second demo
**Mac (Apple Silicon):**
```bash
apple/build.sh mac
scp build/mac/HelloMojo-mac.zip you@your-mac:~/Desktop/
# on the Mac:
cd ~/Desktop && unzip HelloMojo-mac.zip && open HelloMojo.app
```
Click **Greet** → "Hello, Ada! (click 1)", counting up.

**iPhone (free Apple ID):**
```bash
apple/install_iphone.sh     # guided: usbmuxd, Apple ID login, plug in, install, trust
```
Details and troubleshooting: `apple/README.md`.

## 3 decisions worth a second look (from `docs/decisions.md`)
1. **D-04, our own Mojo runtime functions** (`apple/mojo_rt.mojo`). They make the apps tiny and self-contained, but they're unofficial: signatures were read from compiled Mojo 1.1 code, and a Mojo upgrade could change them. If an upgrade breaks something, look here first.
2. **D-03, rects as four floats.** This keeps everything in Mojo, and the disassembly matches Apple's convention, but it's correct only on Apple Silicon (never Intel).
3. **D-13, marked as built with the 26 SDKs**, so macOS 26 and iOS 26 give the apps the current Liquid Glass look. This is unproven without Apple's real SDK; it's a one-line revert in `apple/build.sh` if launch misbehaves.

## Checked here vs. needs you
| Checked on Linux | Needs your Mac / iPhone |
|---|---|
| Compiles for macOS 14 / iOS 17 arm64; only allowed Apple functions | The window and the screen actually appear |
| Links; entry point is the Mojo function; only 3 system libraries | Tapping Greet updates the text |
| Signature hashes (code, Info.plist, resource seal) | Gatekeeper / iOS accept the signature |
| Machine code: rects in d0–d3, enums correct (reviewer) | Liquid Glass button on iOS 26 |

**Next:** run both on your hardware; if anything fails, paste the Terminal output (Mac) or what you saw (iPhone) into the next session.
