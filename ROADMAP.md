# mojo-ui roadmap and decisions

_Last updated: 2026-10-14 · a long-term, speculative side project, developed slowly and organically_

## Vision
One language, Mojo, from the button you tap to the GPU kernel underneath it, on every device and on the server. App logic and UI are written once as `State` + `update()` + `view() → ViewTree`; thin native "skins" put the ViewTree on screen.

The dream: one Mojo codebase that ships a web app, a Mac app and a touch-native iOS app at the same time.

## Why one language, if agents can write many?
The fair counter-argument: fragmentation is a human problem; an agent can write Swift, Kotlin and TypeScript just as easily. Agents do remove most of the *writing* cost. They don't remove:
- **Runtime boundaries.** Data crossing between languages gets copied and serialized. For data, GPU and AI apps, moving data is the bottleneck, and one language sharing memory is a performance win no agent can write around.
- **N codebases to verify.** Every platform version needs its own tests, and behavior drifts between them.
- **Capability gaps.** Most UI languages can't write GPU kernels or SIMD code; Mojo can, in the same program as the UI.

So the strongest case for Mojo is speed and zero-copy for data-heavy apps, not developer convenience.

## The split
| Layer | Written in | Can use |
|---|---|---|
| App logic, UI, GPU, AI | Mojo, once | Mojo kernels, MAX for models |
| Backend | Mojo | Any Python library (Mojo's Python interop), any C library, any HTTP service |
| Desktop and mobile front end | Nothing extra | Native skins draw the ViewTree |
| Web front end | Small JS adapters per library | The whole JS ecosystem, via islands (decision 7) |

## Decisions so far
1. **Architecture: Mojo core, thin hosts.** The UI is data (ViewTree), events are data (Msg). Hosts never touch state directly. (See SPEC.md.)
2. **The platform owns the loop; Mojo is called.** SDL3 main callbacks call exported Mojo functions, Flutter-style. Required for iOS, fine everywhere. *(Proven on Linux in Experiment 1.)*
3. **No dlopen.** The C bridge is resolved at link time. *(Proven on Linux in Experiment 1.)*
4. **Native skins per platform:** SwiftUI on Apple, Jetpack Compose on Android, SDL3 + Clay on Linux, HTML + HTMX on web. All fed by the same ViewTree (as JSON for Swift/Kotlin skins).
5. **Desktop first (decided 2026-10-14).** Linux first, then Mac, where Mojo already runs. iOS is an experimental side track. Windows uses the web host until Mojo for Windows ships. Android waits for the iOS answer.
6. **Flagship app: a native data workstation.** Every row, no sampling; GPU-drawn charts; billions of records through the user's own Mojo dataframe library, MX frame; local embedding and language models (for example Gemma) running on the machine. Check which models MAX supports when this stage arrives.
7. **Web keeps the JS ecosystem through "islands" (decided 2026-10-14).** A ViewTree node kind `ISLAND(id, lib, props_json, on_event)` renders on the web as a placeholder `<div data-island="<lib>" data-props='…' hx-preserve="true">`. A small JS registry mounts the library into it; the library handles fast interactions locally and sends only meaningful events back as Msgs. Prior art: Phoenix LiveView JS hooks, Streamlit components.
   - Islands must survive HTMX swaps (`hx-preserve` or a morphing swap).
   - Each library needs a small adapter (typically 10–30 lines of JS).
   - On native, each island needs a decision: native equivalent, web-only, or (desktop only) a single-widget embedded web view.
   - Keep island events coarse ("drag ended", not every move).
   - Pin and self-host third-party JS.
8. **iOS from Linux: xtool + SwiftUI skin (decided 2026-10-14).** Mojo cross-compiles to an iPhone static library on Linux; a SwiftUI skin (a Swift package) calls it; xtool builds, signs and installs it on a real iPhone, no Mac or Xcode app needed. This also skips porting SDL3 to iOS. A Mac with Xcode remains the fallback, and is the only way to use the iOS Simulator.

9. **Apple UI straight from Mojo (decided 2026-10-14, Experiment 2).** Supersedes the SwiftUI skin in decision 8 for Apple platforms: Mojo calls AppKit/UIKit through the Objective-C runtime, so the Mac and iPhone apps contain no Swift or C. xtool is still used, but only to sign and install the finished `.ipa`. Cons: every Objective-C call is untyped (mistakes show up at run time), Apple Silicon only, and the hand-written Mojo runtime functions are unofficial.

10. **Layout = the platforms' own layout systems, driven by flexbox-style settings (decided 2026-10-15).** Apps say `padding`, `gap`, `grow`, `align`, `justify`, widths and heights; each host maps them onto GtkBox, CSS flexbox, NSStackView and UIStackView. No layout engine of our own for now: the translation layer stays thin. A Mojo flexbox engine (Yoga-like) is a possible separate project later, needed only for a self-drawn (GPU) renderer; the flexbox names keep app code unchanged if that ever happens.

## Tracks
| Track | Steps |
|---|---|
| Main: Linux, then Mac | ✅ M0 → M1 core + tests → M2 web host → M3 Linux window → M4 Mac window → Framework (widgets, text input, layout in Mojo, GPU charts) → MX frame hookup → Flagship workstation |
| Side: iOS (experimental) | ✅ M5 steps 1–2 (iPhone objects, runtime needs measured) → M5 step 3: "Hello, Ada!" from Mojo in a SwiftUI app on an iPhone via xtool → grow the skin to render the ViewTree → Android (M6) later |

## Long-term stages
1. Foundation: mojo-ui v0 on Linux, then Mac; iOS test on the side
2. Framework: widgets, layout in Mojo, real text input, accessibility, web islands for JS libraries
3. GPU renderer: UI and charts drawn by Mojo GPU kernels
4. Data and AI layer: MX frame as the data engine; on-device embedding and language models
5. Ecosystem: plugins (payments, push, storage), templates, docs

## Watch for
- Official Mojo on Windows (announced with Microsoft at ModCon 2026, no date)
- Any official Mojo iOS or Android target
- Maturity of Mojo's Apple GPU support (check before betting the Mac flagship on it)
- xtool progress (debugging on iOS 17+, App Store upload)

## Known risks
- Speculative by design: parts may turn out impossible; the milestones are built to find out cheaply
- Agents write Mojo less fluently than Swift, Kotlin or TypeScript (less training data, a young language); lean on Modular's docs (`.md` pages, llms.txt) and agent skills
- iOS runtime needs: today only two allocation functions, covered by an unofficial 10-line stand-in; bigger features may pull in more. Re-measure as `core/` grows
- xtool: real iPhone only (no simulator on Linux), Xcode.xip license terms, short-lived signing on free Apple IDs, limited debugging
- Text input, accessibility and GPU battery cost need real-device testing
- Apple's Neural Engine is only reachable through Core ML
- Phone memory limits on-device model size
- Desktop distribution: signing, notarization, installers, auto-update
- Web islands: per-library adapters, native parity decisions, third-party JS security
- Focus: one flagship app, not every use case at once
