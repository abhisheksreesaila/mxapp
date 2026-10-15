# HelloMojo for iPhone, built on Linux with xtool (M5 step 3)

A SwiftUI app whose logic lives in Mojo. Tap **Greet** and the text comes from Mojo: "Hello, Ada! (click 1)".

**Status: prepared, not yet built.** The Mojo iPhone libraries are built and checked (`Mojo/ios-device`, `Mojo/ios-simulator`), and the C glue compiles. The Swift package has not been through xtool yet; that first build *is* the experiment.

## What's inside
| Path | What it is |
|---|---|
| `Package.swift` | Swift package: `MojoBridge` (C glue, links the Mojo library) + `HelloMojo` (SwiftUI) |
| `xtool.yml` | xtool project settings (bundle ID) |
| `Mojo/ios-device/libmojoapp.a` | `app_entry.mojo` compiled for iPhone (arm64, iOS 17) |
| `Mojo/ios-simulator/libmojoapp.a` | Same, for the iOS Simulator (Mac only) |
| `Sources/MojoBridge/` | `mojoui_bridge.c` (receives text from Mojo), `kgen_shim.c` (unofficial runtime stand-in), `include/MojoBridge.h` |
| `Sources/HelloMojo/HelloMojoApp.swift` | The SwiftUI skin |
| `build_mojo_ios.sh` | Rebuilds the Mojo libraries and refreshes the C glue |

## Steps (Linux, WSL or Mac)
1. **Install xtool** from https://github.com/xtool-org/xtool (Linux: AppImage on its releases page), plus a Swift toolchain from swift.org.
2. **Download Xcode.xip** in a browser from Apple's developer site (you must accept Apple's license; `curl` won't work). Check it with `file Xcode.xip`.
3. **Run `xtool setup`.** Choose the API-key login (paid Apple Developer account, recommended) or password login (any Apple ID; uses private Apple APIs). Point it at Xcode.xip.
4. **Set your bundle ID** in `xtool.yml` (something unique, e.g. `com.yourname.HelloMojo`).
5. **Plug in your iPhone** over USB, unlock it, trust the computer. On WSL, attach the device with `usbipd`.
6. **Build and run:** `xtool dev` from this folder.
7. **On the phone:** tap **Greet** three times → "Hello, Ada! (click 3)".

If `xtool dev` can't reach the phone: `xtool dev build --ipa`, then install the `.ipa` with a sideloading tool.

## If something goes wrong (most likely first)
- **Package shape differs from xtool's template:** run `xtool new Scratch` in a temp folder, compare its `Package.swift` and `xtool.yml`, and adapt ours (keep our two targets).
- **Linker can't find `mojoapp`:** check the `-L` path in `Package.swift` points at `Mojo/ios-device`, and that `unsafeFlags` is allowed (it is for a root package).
- **Undefined `KGEN_CompilerRT_*` symbol:** a new Mojo runtime function is needed. Run `./build_mojo_ios.sh`, look at its symbol list, and record it in `EXPERIMENTS.md`. Don't guess its signature without inspecting call sites.
- **App installs but crashes on launch:** check the device log for the missing symbol or crash reason; record it.
- **Free Apple ID:** the app's signing expires after a short time (typically about a week); reinstall with `xtool dev`.

## Notes and cons
- No simulator on Linux: Apple's simulator only runs on macOS. On a Mac you can switch `Package.swift` to `Mojo/ios-simulator`.
- `kgen_shim.c` is unofficial and may break on a future Mojo release.
- Xcode.xip's license terms apply to how you use the SDK; read them.
- Record whatever happens, success or failure, in `../EXPERIMENTS.md`.
