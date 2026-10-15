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
