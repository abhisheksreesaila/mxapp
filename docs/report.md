# Report: declarative Mojo UI, rendered natively (goal 2)

**End goal:** "All I want is Mojo declarative code and then it's rendered natively on all the platforms."

**How far it got:** 7/7 milestones. You write one `app.mojo` (state, `update()`, `view()`), and it becomes a GTK app on Linux, an AppKit app on Mac and a UIKit app on iPhone. **Linux runs and is tested here. Mac and iPhone build and sign from the same file but haven't run on real hardware yet.**

```
$ scripts/check
PASS  M1  ALL TESTS PASSED
PASS  M2  real GtkButton tapped 3x (signal), real GtkLabel reads 'Hello, Ada! (click 3)'; window shown and drawn by GTK
PASS  M3  arm64, entry _mojo_entry, 3 system libs, signature verified
PASS  M4  arm64, entry _mojo_entry, 3 system libs, signature verified
PASS  M5  app files import only mojoui; no C/ObjC/Swift sources; Linux, Mac and iPhone builds all compiled the identical file
PASS  M6  GTK run: 3 adds + 1 remove → rows 'Task 1', 'Task 3', '2 tasks'; Mac and iPhone builds pass
PASS  M7  README.md + apple/README.md cover Linux, Mac, iPhone; all paths exist
```

Linux screenshots, drawn by GTK itself: `docs/img/hello-linux.png`, `docs/img/todo-linux.png`.

## 30-second demo
```bash
scripts/build.sh todo linux && build/todo/linux/todo      # Linux: a real window, click away
scripts/build.sh hello mac                                 # then copy build/hello/mac/HelloMojo-mac.zip to your Mac
apple/install_iphone.sh                                    # iPhone, guided (free Apple ID)
```

## 3 decisions worth a second look (`docs/decisions.md`)
1. **D-14, a flat node list.** Mojo 1.1 can't put a `List[View]` inside `View`. The builder API hides this (`VStack(Text(...), Button(...))`), but the internals will change if Mojo gains recursive types.
2. **D-18, tag packing on Apple.** Each button's tag holds the host's address and the node number. It's simple and needs no globals, but it caps a screen at 65,535 nodes, checked on every redraw.
3. **D-20 and D-25, how M2 proves Linux.** Taps are GTK signal emissions, not mouse clicks. The window is also shown once and drawn by GTK into a PNG during the check, so a window flashes briefly.

## Checked here vs. needs you
| Checked on Linux | Needs your Mac / iPhone |
|---|---|
| Declarative core: exact trees, patches, rebuilds (9 tests) | AppKit/UIKit windows actually appear and look right |
| GTK: real widgets, taps, label text, window drawn | Taps update the native controls |
| Same `app.mojo` compiled for all three; no platform code in apps | Gatekeeper / iOS accept the signatures |
| Apple builds: only Apple system functions, entry point, signatures; reviewer checked the ABI in LLVM IR | Liquid Glass buttons on iOS 26 |

**Next:** run hello and todo on your Mac and iPhone. Then add text input, scrolling lists and images, and a web host.
