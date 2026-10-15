# HelloMojo: a Mac and iPhone app written only in Mojo

One screen: a greeting, a **Greet** button, and a label that counts your taps ("Hello, Ada! (click 3)").
Everything is Mojo: the logic (`apple/hello_core.mojo`), the UI (`apple/mac/hello_mac.mojo`, `apple/ios/hello_ios.mojo`), even the app's start-up and the three tiny runtime functions Mojo needs (`apple/mojo_rt.mojo`). There is no Swift, C or Objective-C. Mojo calls Apple's own AppKit and UIKit through the Objective-C runtime (`apple/objc.mojo`), so the controls are real native ones.

Build both apps (on Linux or a Mac, about a minute):

```bash
apple/build.sh all     # → build/mac/HelloMojo.app, build/mac/HelloMojo-mac.zip, build/ios/HelloMojo.ipa
scripts/check          # rebuilds and checks every milestone in GOAL.md
```

## Mac (Apple Silicon)

**Option 1: copy the app built on Linux** (quickest)
1. `apple/build.sh mac`
2. Copy `build/mac/HelloMojo-mac.zip` to the Mac, e.g. `scp build/mac/HelloMojo-mac.zip you@your-mac:~/Desktop/`
3. On the Mac: `cd ~/Desktop && unzip HelloMojo-mac.zip && open HelloMojo.app`

**Option 2: build on the Mac**: copy this folder to the Mac, install pixi (`curl -fsSL https://pixi.sh/install.sh | sh`), then `apple/build.sh mac && open build/mac/HelloMojo.app`.

**What you should see:** a window titled HelloMojo. Click **Greet** (or press Return) and the text changes to "Hello, Ada! (click 1)", counting up. Cmd+W closes the window, which also quits; so does Cmd+Q.

**If macOS refuses to open it** ("damaged" or "can't be opened"): that's Gatekeeper, because the app is signed by nobody (ad-hoc). Copies made with `scp` usually aren't blocked; downloads and AirDrop are. Fix: `xattr -dr com.apple.quarantine HelloMojo.app`, or try to open it once, then System Settings → Privacy & Security → **Open Anyway**.

**If it quits or crashes:** run it from Terminal to see its output: `./HelloMojo.app/Contents/MacOS/HelloMojo`. Then check Console.app → Crash Reports → HelloMojo, and paste both into the next session.

## iPhone (free Apple ID, from this Linux machine)

Run the guided script; it walks you through every step and does the typing:

```bash
apple/install_iphone.sh
```

What it does, in order:
1. Builds `build/ios/HelloMojo.ipa` if needed (`apple/build.sh ios`).
2. Installs `usbmuxd` (asks first; needs `sudo`) so Linux can talk to the phone over USB.
3. Signs you in to xtool with your Apple ID (`xtool auth login --mode password`, with a 2-factor code).
4. Waits for the iPhone: plug it in, unlock, tap **Trust**.
5. Installs the app: `xtool install --usb build/ios/HelloMojo.ipa`. xtool re-signs it with your Apple ID and prefixes the bundle ID with an ID unique to you, so it can't clash with anyone else's.
6. Tells you the two one-time switches on the phone: **Developer Mode** (Settings → Privacy & Security, then restart) and **trust your Apple ID** (Settings → General → VPN & Device Management).
7. Open HelloMojo and tap **Greet**.

**Free Apple ID limits:** the app stops opening after 7 days, so run the script again to renew it. Up to 3 self-signed apps at a time. No Xcode, Mac or paid account needed.

## How it works (in one breath)

- `objc.mojo` looks up `objc_msgSend`'s address and casts it to the exact C signature of each call, so `msg(button, "setTag:", 42)` is a real Objective-C message from Mojo.
- Button handlers are Mojo functions marked `abi("C")`, added as methods to classes Mojo creates at run time (`MojoHandler`, `MojoAppDelegate`, `MojoSceneDelegate`).
- The linker's `-e _mojo_entry` makes the OS start directly in Mojo; no `main.c`.
- `mojo_rt.mojo` supplies the 3 Mojo runtime functions in Mojo, so the apps carry no Modular runtime library: the Mac app is about 70 KB.
- Linked on Linux by `ld64.lld` against `apple/sdk/` (lists of Apple function names; see `apple/sdk/README.md`). No Apple SDK download needed.

## Limits and cons

- **Not yet run on real hardware.** Everything above is verified on Linux: compiled, linked, signed, symbols and machine code checked. Running it on your Mac and iPhone is the real test.
- The apps say they were built with the 26 SDKs (so macOS 26 and iOS 26 give them the current Liquid Glass look, not compatibility mode), though they're linked without Apple's SDK. Unproven; if it causes trouble, change `26.0` back to `14.0`/`17.0` in `apple/build.sh`.
- Apple Silicon only: rects are passed as four floats, which is right on arm64 and wrong on Intel.
- `mojo_rt.mojo` is unofficial (signatures read from compiled Mojo 1.1 code) and may need updating with new Mojo releases.
- Each `msg()` call is untyped: a wrong argument type compiles fine and misbehaves at run time, just like raw Objective-C runtime code.
- The older SwiftUI version in `ios-xtool/` is superseded by this one.
