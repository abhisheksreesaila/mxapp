# Report: the web, real components, a real app on every platform (goal 3)

**End goal (your words):** "render the web… build all the components necessary… build an app like a todo list… the same declarative code in Mojo runs on all of them… try Android… then an app that's great on GPUs."

**How far it got:** all 9 milestones pass, M7 (Android) as a documented exploration. One Mojo file per app now runs:
- natively on **Linux** (GTK) and on the **web** (FastHTML + HTMX), both tested here;
- on **Mac** and **iPhone**, building and signing from the same file, but not yet run on real hardware;
- on **Android**, as far as a real arm64 library.

The **GPU** example runs a plain Mojo function as a GPU kernel on your RTX 3090. **Images** work everywhere: GTK, the web, and Mac/iPhone, via a PNG encoder written in Mojo.

```
$ scripts/check
PASS  M1  Chromium clicked Greet 3x on the FastHTML page → 'Hello, Ada! (click 3)'; GTK hello still passes and draws
PASS  M2  core + PNG tests pass; every component built and tested
PASS  M3  GTK: typed, toggled, chose, slid, pressed Return on real widgets; every echo label right
PASS  M4  Chromium: same interactions, same echoed state
PASS  M5  hello, gallery, todo: Mac + iPhone build, link, sign; only Apple system functions
PASS  M6  todo: GTK and Chromium give identical state; Mac + iPhone build; apps import only mojoui
PASS  M7  todo for Android arm64: libmojoui.so with a native entry point; no APK yet (see docs/android.md)
PASS  M8  GPU kernel ran on the NVIDIA GPU; result shown in GTK and web, verified against the CPU; no-GPU run degrades gracefully
PASS  M9  README covers every platform and component; all paths exist
```

Screenshots (real, rendered by GTK and Chromium): `docs/img/todo-linux.png`, `docs/img/todo-web.png`, `docs/img/gallery-linux.png`, `docs/img/gallery-web.png`, `docs/img/gpu-linux.png`, `docs/img/gpu-web.png`.

## 30-second demo
```bash
scripts/build.sh todo linux && build/todo/linux/todo                                         # a native GTK window
scripts/build.sh todo web && pixi run python mojoui/hosts/web.py build/todo/web   # then open http://127.0.0.1:5001
scripts/build.sh gpu linux && build/gpu/linux/gpu                                            # drag Zoom; press Run on GPU
```

## 3 decisions worth your second look (`docs/decisions.md`)
1. **D-26, the web runs the Mojo app inside Python.** FastHTML imports the app compiled as a Python module and sends plain HTML; HTMX posts events back. One app state per browser tab, held on the server. This was your FastHTML idea. The cons: every click is a round trip to the server, and state lives in server memory.
2. **D-36, Android stopped at a real library plus a plan.** Android only delivers taps to Java objects, so there are three options: a ~40-line Java listener shim (recommended), a pure-Mojo polling workaround, or a hand-built dex. Packaging also needs Google's SDK licence. Both are your call: `docs/android.md`.
3. **D-34 and D-37, the web host had a real bug** (typing then Return straight away lost the task), found by review and fixed. A stricter checker then caught a second web bug, which is also fixed. I proved the checks bite by putting each bug back.

## Ran here vs. needs you
| Ran here | Needs you |
|---|---|
| Linux GTK app: every component, driven through real signals | Run the Mac and iPhone builds (`apple/README.md`) |
| Web app in Chromium: every component, the same final state as GTK | Android: choose Java shim or Mojo-only, accept the SDK licence, provide a phone |
| GPU kernel on the RTX 3090, verified against the CPU; no-GPU machines degrade gracefully | GPU on Mac (Apple GPU) isn't wired up |
| Mac/iPhone: compile, link, sign; reviewer checked the calling convention in the compiled code | |

**Next:** run it on your Mac and iPhone, then pick the Android route.
