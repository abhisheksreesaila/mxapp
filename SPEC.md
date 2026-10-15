# SPEC.md — `mojo-ui` v0: "Hello, Name" on Native + Web from one Mojo core

> Hand this repo to Claude Code; it starts from `CLAUDE.md`. Primary dev machine: Linux. M4 needs a Mac; M5 steps 3–4 need a real iPhone plus xtool (or a Mac with Xcode).
>
> **Revision 2 (2026-10-14):** iOS native is now a goal. Two architecture changes make that possible and apply on every platform: the platform owns the event loop and calls into Mojo (§1 rule 7, §6), and the bridge is resolved at link time instead of with `dlopen` (§1 rule 8, §2). Milestone M5 is an iOS go/no-go spike (§9).
>
> **Revision 3 (2026-10-14, after the first experiment):** M0 and M5 steps 1–2 were run for real on Linux with Mojo 1.1.0. §2 now uses the verified pointer APIs, §8 the verified install and link flags, and §9 records the results. Details: `EXPERIMENTS.md`.

---

## 0. North star (read first)

We are planting the seed of a universal UI framework: **app logic and UI are written once in Mojo; thin, swappable "hosts" put it on screen.**

v0 is deliberately tiny and dumb:

```
┌──────────────────────────────────────┐
│  mojo-ui · hello                     │
│  [ Your name________ ]  [ Greet ]    │
│  Hello, Ada!                         │
└──────────────────────────────────────┘
```

Type a name → press **Greet** (or Enter) → the label says `Hello, <name>!` (or `Hello, world!` if empty).

The *same* Mojo `State`, `update()` and `view()` must drive **two hosts**:

| Host | Platforms (now) | How |
|---|---|---|
| **Native** | Linux (primary), macOS arm64 (M4), iOS (M5 spike) | SDL3 window + Clay layout (C) via a flat C bridge. A small C host owns the loop and calls exported Mojo functions, the same way Flutter's iOS shell calls its engine |
| **Web** | Any browser. Covers Windows and Android for now, and iOS until M5 succeeds | Mojo renders HTML; a thin FastHTML server calls Mojo as a Python extension module; HTMX swaps the DOM |

### Non-goals for v0
GPU rendering, WebGPU, WASM, Android, App Store release builds, theming, animations, scrolling, clipboard, text selection, IME composition, multiple windows. All are on the roadmap (§10), none are in this build. iOS in v0 means "the same app runs on a simulator and a phone" (M5), not a shippable app.

---

## 1. Architecture: "Mojo core, thin hosts"

```
                 ┌────────────── core (pure Mojo, no I/O) ──────────────┐
   Msg  ───────▶ │ update(mut state, msg)                               │
                 │ view(state) -> ViewTree   (flat arena of Nodes)      │
                 └───────────────┬───────────────────────┬──────────────┘
                                 │ ViewTree (data)       │ ViewTree (data)
                       ┌─────────▼─────────┐   ┌─────────▼──────────┐
                       │ Native host        │   │ Web host            │
                       │ walk tree → bridge │   │ render_html(tree)   │
                       │ SDL3 + Clay (C)    │   │ FastHTML + HTMX     │
                       │ events → Msg       │   │ POST /event → Msg   │
                       └────────────────────┘   └─────────────────────┘
```

Design rules (these are the actual "framework"; protect them):

1. **The UI is data.** `view()` returns a `ViewTree` value. It never draws, never calls C, never touches Python. Any host can consume it; tests can snapshot it.
2. **Events are data.** Nodes carry *message tags* (`on_click = MSG_GREET`), not callbacks. Hosts translate raw input into `Msg` values and call `update()`. This is the Elm / Iced pattern and it is what makes native and web interchangeable.
3. **One source of truth.** `State` lives in exactly one place per host (the native loop, or the web session). Hosts never mutate UI nodes directly.
4. **Flat tree, not recursive structs.** `ViewTree` is a `List[Node]` arena; nodes reference children by index (`first_child`, `next_sibling`). Avoids recursive-type headaches in Mojo, is cache-friendly, and mirrors how Clay / Taffy / Masonry store trees.
5. **Every node has an accessibility `role`** (`ROLE_BUTTON`, `ROLE_TEXTBOX`, `ROLE_LABEL`, `ROLE_GROUP`) and a stable string `id`, even though nothing consumes `role` yet. The web host maps it to semantic HTML; a future native host maps it to an AccessKit-style tree. Retrofitting this later is painful; carrying it now is free.
6. **The C bridge is boring on purpose** (see §4). Scalars, `(ptr, len)` strings, and getters only.
7. **The platform owns the loop; Mojo is called.** Mojo never runs a `while` loop that blocks on events. A small C host uses SDL3's *main callbacks* (`SDL_AppInit`, `SDL_AppEvent`, `SDL_AppIterate`, `SDL_AppQuit`) and forwards each one to an exported Mojo function. iOS requires this because UIKit owns the run loop. Browsers work the same way, so a future WASM host fits too.
8. **No `dlopen`. Resolve the bridge at link time.** Mojo calls bridge functions with `external_call`, and the linker connects them. iOS restricts runtime library loading, and link-time resolution works on every platform.

### What we're borrowing from the Rust ecosystem
| Rust project | Idea we take | Where it lands in v0 |
|---|---|---|
| Elm-style (Iced, Relm) | `State` + `Msg` + `update` + `view` | `core/app.mojo` |
| Dioxus | One virtual tree, many renderers (desktop, web, LiveView) | `ViewTree` consumed by two hosts |
| Taffy | Layout is a pluggable engine, separate from widgets | Clay behind the bridge; swappable for a Mojo port later |
| AccessKit | Accessibility tree as plain data | `role` on every node |
| Vello / wgpu | GPU renderer as a later, separate layer | Roadmap only |

---

## 2. Mojo 1.x rules for the agent (verified against Mojo 1.1.0 on 2026-10-14)

Mojo 1.0 shipped 2026-08-11; 1.1 is current. Docs are agent-friendly: **`https://mojolang.org/llms.txt`**, and any docs page is available as Markdown by appending `.md`. When unsure of an API, fetch the `.md` page instead of guessing. If Modular's official Mojo agent skills are installable in this environment, install and use them.

1. **`def` only.** `fn` is deprecated. `def` is non-raising by default; add `raises` explicitly (`def main() raises:`).
2. **No `@value`.** Use `@fieldwise_init` + explicit traits, e.g. `struct Node(Copyable, Movable):`.
3. **Constructors:** `def __init__(out self, ...)`. Mutating methods take `mut self`. Consuming: `var` / `deinit`.
4. **Imports use the `std.` prefix:** `from std.ffi import external_call`, `from std.memory import Pointer`, `from std.memory.alloc import alloc, Layout`, `from std.python import Python, PythonObject`, `from std.python.bindings import PythonModuleBuilder`, `from std.os import abort`.
5. **Calling C (Mojo → bridge): use `external_call`.** *(Verified.)*
   ```mojo
   from std.ffi import external_call
   var v = external_call["mui_version", Int32]()
   var s = String("Hello")
   _ = external_call["mui_echo", Int32](s.unsafe_ptr(), Int32(s.byte_length()))
   ```
   The symbol is resolved when the Mojo program or library is linked against `libmojoui_bridge` (see §8).
   **Being called from C (host → Mojo): export with `@export` and `abi("C")`.** *(Verified.)*
   ```mojo
   @export
   def mojo_app_event(app: Int, kind: Int32) abi("C") -> Int32:
       ...
   ```
   `abi("C")` functions cannot `raise`: catch errors inside and return an error code.
   **App state across callbacks:** heap-allocate it once and hand C an opaque address. *(Verified. Mojo 1.1 deprecated `UnsafePointer` in favour of `Pointer`, and `alloc` now takes a `Layout` and returns an owning `Allocation` that the compiler forces you to consume.)*
   ```mojo
   from std.memory.alloc import alloc, Layout
   from std.memory import Pointer

   def app_ptr(app: Int) -> Pointer[App, MutUntrackedOrigin]:
       return Pointer[App, MutUntrackedOrigin](unsafe_from_address=app)

   @export
   def mojo_app_init() abi("C") -> Int:
       var allocation = alloc(Layout[App].single())
       var p = allocation^.unsafe_leak()   # hand ownership to C on purpose
       p.unsafe_write(App())
       return Int(p)

   @export
   def mojo_app_quit(app: Int) abi("C"):
       var p = app_ptr(app)
       p.unsafe_deinit_pointee()
       p.unsafe_free()
   ```
6. **Never pass or return a struct by value across FFI.** Scalars (`Int32`, `Float32`, `UInt32`, `Int`) and pointers only.
7. **Strings into C are `(ptr, len)` pairs**, never null-terminated: `s.unsafe_ptr()` and `s.byte_length()` *(verified)*.
8. **Strings out of C:** use getters (`mui_event_text_len()`, `mui_event_text_byte(i)`), build the Mojo `String` from bytes. No out-pointer gymnastics in v0.
9. **Python extension entry point:**
   ```mojo
   @export
   def PyInit_mojoui_web() abi("C") -> PythonObject:
       try:
           var m = PythonModuleBuilder("mojoui_web")
           m.def_function[render]("render")
           return m.finalize()
       except e:
           abort(String("mojoui_web init failed: ", e))
   ```
   `abi("C")` functions can't `raise`; registered functions can.
10. Build the extension **ahead of time** with `mojo build ... --emit shared-lib`, because the `mojo.importer` hook does not support import paths for non-stdlib packages (our `core/`).
11. **Mojo's compiler tries to send telemetry** to `telemetry.modular.com`. In a sandbox without network access this shows up as a harmless proxy warning; ignore it.

---

## 3. Repository layout

```
mojo-ui/
├── SPEC.md
├── EXPERIMENTS.md            # dated log of what was tried and what happened
├── pixi.toml                 # toolchain + tasks (see §8)
├── CMakeLists.txt            # builds build/libmojoui_bridge.{so,dylib} and the hello-native host executable
├── third_party/clay/clay.h   # vendored, pinned to a tagged release; record tag in README
├── assets/fonts/             # one OFL font (e.g. Inter or DejaVu Sans) + its license
├── bridge/
│   ├── mojoui_bridge.h       # the ENTIRE C ABI surface (§4), both directions
│   ├── mojoui_bridge.c       # SDL3 + SDL3_ttf + Clay; CLAY_IMPLEMENTATION lives here
│   └── host_main.c           # SDL3 main callbacks → mojo_app_* (the "Flutter shell"); CLI flags
├── ios-xtool/                # M5: SwiftUI skin + prebuilt Mojo iPhone library, built with xtool (see its README)
├── spike/                    # M5 experiments (iOS objects, runtime stand-in)
├── scripts/m0_linux.sh       # reproduces Experiment 1 end to end
├── CLAUDE.md / ROADMAP.md    # agent briefing; vision and decisions
├── core/                     # pure Mojo, no I/O, no FFI, no Python
│   ├── __init__.mojo
│   ├── style.mojo            # Style struct + constants + chainable modifiers
│   ├── tree.mojo             # Node, ViewTree, ViewBuilder
│   └── app.mojo              # State, Msg, update(), view()
├── hosts/
│   ├── native/
│   │   ├── bridge.mojo       # typed Mojo wrappers over external_call
│   │   └── app_entry.mojo    # @export mojo_app_init / _event / _frame / _quit: events → Msg → update → view → bridge
│   └── web/
│       ├── html.mojo         # render_html(tree) -> String (pure Mojo, escapes text)
│       ├── mojoui_web.mojo   # Python extension module (PyInit_mojoui_web)
│       └── server.py         # FastHTML app; ~50 lines; no UI logic
└── tests/
    ├── test_core.mojo        # update() + view() snapshot tests
    ├── test_html.mojo        # HTML snapshot + escaping tests
    └── test_web.py           # HTTP round-trip test
```

---

## 4. The C bridge (`bridge/mojoui_bridge.h`)

Link: SDL3, SDL3_ttf, Clay (header-only). Every function below takes and returns only scalars or `(const uint8_t*, int32_t)` string pairs.

```c
// lifecycle
int32_t mui_version(void);                         // returns e.g. 1; used for the M0 smoke test
int32_t mui_init(const uint8_t* title, int32_t title_len,
                 int32_t width, int32_t height,
                 const uint8_t* font_path, int32_t font_path_len,
                 float font_size);                 // 0 = ok, nonzero = error code
void    mui_shutdown(void);
const char* mui_last_error(void);                  // debug only; read via getters if needed

// events (getter style: no out-pointers). host_main.c stores the current SDL event,
// then calls mojo_app_event(app, type); Mojo reads details through these getters.
float   mui_event_x(void);
float   mui_event_y(void);
int32_t mui_event_key(void);                       // MUI_KEY_* constants below
int32_t mui_event_text_len(void);                  // for TEXT_INPUT (UTF-8 bytes)
int32_t mui_event_text_byte(int32_t i);
int32_t mui_window_w(void);
int32_t mui_window_h(void);
void    mui_text_input(int32_t enabled);           // SDL_StartTextInput / SDL_StopTextInput

// layout + render (one frame)
void    mui_begin(float mouse_x, float mouse_y, int32_t mouse_down);
void    mui_open(const uint8_t* id, int32_t id_len,
                 int32_t direction,                // 0 = row, 1 = column
                 float padding, float gap,
                 int32_t w_mode, float w,          // 0 = fit, 1 = grow, 2 = fixed
                 int32_t h_mode, float h,
                 uint32_t bg_rgba, uint32_t border_rgba,
                 float border_width, float radius);
void    mui_text(const uint8_t* text, int32_t text_len,
                 float font_size, uint32_t color_rgba);
void    mui_close(void);
void    mui_end_and_present(uint32_t clear_rgba);  // Clay_EndLayout + draw render commands
int32_t mui_pointer_over(const uint8_t* id, int32_t id_len);  // 1 if pointer over element (last layout)

// debug / verification
int32_t mui_screenshot(const uint8_t* path, int32_t path_len); // writes BMP or PNG of last frame

// native-platform hook (proves we're a real OS process; v0 = log line only)
void    mui_platform_ping(void);

// ---- Exported BY Mojo, called by host_main.c (the other direction) ----
int64_t mojo_app_init(void);                         // returns opaque app address; 0 = failure
int32_t mojo_app_event(int64_t app, int32_t type);   // 0 = continue, 1 = quit
int32_t mojo_app_frame(int64_t app);                 // draw if dirty; 0 = continue, 1 = quit
void    mojo_app_quit(int64_t app);                  // free app state
```

### `host_main.c`: the shell
- `#define SDL_MAIN_USE_CALLBACKS` and include `SDL3/SDL_main.h`, so SDL provides `main` on desktop and the UIKit entry point on iOS.
- `SDL_AppInit`: parse CLI flags (§6), `mui_init(...)`, then `*appstate = (void*)mojo_app_init()`.
- `SDL_AppEvent`: store the event for the getters, map the SDL type to an MUI type, call `mojo_app_event`. Return `SDL_APP_SUCCESS` when Mojo asks to quit.
- `SDL_AppIterate`: run the next `--script` step if any, then `mojo_app_frame`; after the script finishes, write `--screenshot` and quit.
- `SDL_AppQuit`: `mojo_app_quit`, then `mui_shutdown`.
- On desktop, the font path comes from `assets/fonts/`; on iOS, from the app bundle (`SDL_GetBasePath()`).

Event types: `0 NONE, 1 QUIT, 2 MOUSE_DOWN, 3 MOUSE_UP, 4 MOUSE_MOVE, 5 KEY_DOWN, 6 TEXT_INPUT, 7 RESIZE`.
Keys: `MUI_KEY_BACKSPACE = 1, MUI_KEY_ENTER = 2, MUI_KEY_ESCAPE = 3, MUI_KEY_TAB = 4, other = 0`.

### Implementation notes
- **Clay wiring:** the `CLAY(...)` macro expands to open / configure / close calls; `mui_open` / `mui_close` call those underlying functions directly. Read `clay.h` for the exact names in the pinned version.
- **Clay does not copy strings.** `Clay_String` holds a pointer that must stay valid until rendering finishes. The bridge must copy every `id` and `text` passed in into a **per-frame arena**, reset at `mui_begin`.
- **Text measurement:** register Clay's measure-text callback using SDL3_ttf (`TTF_GetStringSize` or equivalent). Text drawing: SDL3_ttf's renderer text engine or a cached texture per string; pick the simplest that works.
- **Reference renderer:** Clay ships example renderers (SDL2/SDL3/raylib/HTML). If an SDL3 renderer exists in the pinned version, adapt it rather than writing one from scratch. Rounded corners are optional in v0; square boxes are fine.
- **Headless mode:** when `SDL_VIDEODRIVER=offscreen` (or `dummy`) is set, everything must still work, including `mui_screenshot`. This is how the agent verifies the native host without a display. Fall back to `xvfb-run` if offscreen rendering misbehaves.
- `mui_platform_ping`: `#ifdef __APPLE__` / `__linux__` log line naming the platform. Real native API calls come later.

---

## 5. Core (pure Mojo)

### `core/style.mojo`
```
Style: direction, padding, gap, w_mode, w, h_mode, h,
       bg (UInt32 RGBA), fg, border, border_width, radius, font_size
```
Chainable modifiers returning a modified copy: `.row()`, `.col()`, `.pad(16)`, `.gap(8)`, `.w(180)`, `.grow_w()`, `.h(40)`, `.bg(0x4F46E5FF)`, `.fg(...)`, `.rounded(8)`, `.font(18)`.
Provide a small default theme: `button_style()`, `textbox_style()`, `label_style()`, `root_style()`.

### `core/tree.mojo`
```
Node:  kind (KIND_GROUP | KIND_LABEL | KIND_BUTTON | KIND_TEXTBOX)
       role (ROLE_GROUP | ROLE_LABEL | ROLE_BUTTON | ROLE_TEXTBOX)
       id: String, text: String, placeholder: String
       style: Style
       on_click: Int   (MSG_NONE if none)
       on_input: Int   (MSG_NONE if none)
       focused: Bool
       first_child: Int, next_sibling: Int   (-1 = none)

ViewTree: nodes: List[Node], root: Int
ViewBuilder: open_row(id, style) / open_col(id, style) / close()
             label(id, text, style) / button(id, text, on_click, style)
             textbox(id, value, placeholder, on_input, focused, style)
             finish() -> ViewTree
```
**Declarative syntax:** if Mojo context managers compile cleanly here, offer
```mojo
with b.col("root", root_style()):
    b.label("title", "mojo-ui · hello", title_style())
    with b.row("form", Style().row().gap(8)):
        b.textbox("name", state.input, "Your name", MSG_SET_INPUT, state.focus == "name", textbox_style())
        b.button("greet", "Greet", MSG_GREET, button_style())
    b.label("greeting", state.greeting, label_style())
```
Otherwise fall back to explicit `open_col(...)` / `close()` calls with the same shape. Do not spend more than ~30 minutes fighting the `with` version.

### `core/app.mojo`
```
State: input: String, greeting: String, focus: String   # focus = id of focused node or ""
Msg:   kind: Int, payload: String
       MSG_NONE, MSG_SET_INPUT(payload), MSG_APPEND_TEXT(payload),
       MSG_BACKSPACE, MSG_FOCUS(payload=id), MSG_BLUR, MSG_GREET

update(mut state, msg):
  SET_INPUT   → input = payload
  APPEND_TEXT → input += payload            (cap input at 64 bytes)
  BACKSPACE   → remove last *codepoint*, not last byte (UTF-8 safe)
  FOCUS/BLUR  → focus = payload / ""
  GREET       → greeting = "Hello, " + trimmed(input) + "!"  or  "Hello, world!" if empty

view(state) -> ViewTree    # exactly the layout in §0
```
`update` and `view` must not import anything from `hosts/`.

---

## 6. Native host (`hosts/native/`)

`bridge.mojo`: thin typed wrappers over `external_call` for every `mui_*` function, plus Mojo-friendly helpers (`open(node)`, `text(...)`, `pointer_over(id) -> Bool`).

`app_entry.mojo`: no `main()`, no loop. It defines `App { state: State, dirty: Bool }` and the four exported callbacks from §4:
- `mojo_app_init()`: allocate `App` on the heap, mark dirty, return its address.
- `mojo_app_event(app, type)`: translate the event to `Msg` values (rules below), run `update`, set `dirty` if anything changed. Return 1 on `QUIT`.
- `mojo_app_frame(app)`: if dirty (or on resize / first frame), `tree = view(state)`, walk it depth-first emitting `mui_begin` / `mui_open` / `mui_text` / `mui_close`, then `mui_end_and_present`; clear dirty.
- `mojo_app_quit(app)`: destroy and free `App`.

Translation rules (inside `mojo_app_event`):
   - `MOUSE_DOWN`: for each node with `on_click != MSG_NONE`, if `pointer_over(id)` → emit that msg. For textboxes under the pointer → `MSG_FOCUS(id)`; click elsewhere → `MSG_BLUR`.
   - `TEXT_INPUT` with a focused textbox → `MSG_APPEND_TEXT(text)`.
   - `KEY_DOWN`: Backspace → `MSG_BACKSPACE`; Enter while textbox focused → `MSG_GREET`; Escape → `MSG_BLUR`.
   - Call `mui_text_input(1/0)` when focus changes. On iOS this shows and hides the on-screen keyboard.
   - On touch devices SDL3 also delivers touches as mouse events by default; v0 relies on that.

Textbox rendering: show `value` plus a `|` caret when focused; show `placeholder` in a muted color when `value` is empty.

CLI flags (parsed in `host_main.c`, needed for automated verification):
- `--script "type:Ada;click:greet;wait:1"`: inject synthetic events through the same `mojo_app_event` path as real input. `type:` emits `TEXT_INPUT`, `click:<id>` emits a click at the center of that element (use Clay's element bounding box), `key:enter` emits Enter.
- `--screenshot out.bmp`: save the frame after the script runs, then exit.
- `--frames N`: exit after N frames.

---

## 7. Web host (`hosts/web/`)

`html.mojo`: `render_html(tree: ViewTree) -> String`, pure Mojo, no Python.
- `KIND_GROUP` → `<div>` with inline flex CSS from `Style` (`display:flex; flex-direction; gap; padding; background; border-radius`).
- `KIND_LABEL` → `<p id=...>`; `KIND_TEXTBOX` → `<input type="text" name="value" id=... placeholder=... value=...>`; `KIND_BUTTON` → `<button id=...>` with HTMX attributes.
- **Escape all text and attribute values** (`& < > " '`). There is a test for this.
- Root element is `<div id="app">`. A button with `on_click = MSG_GREET` renders:
  `hx-post="/event" hx-vals='{"msg":"greet"}' hx-include="#app input" hx-target="#app" hx-swap="outerHTML"`.
- Wrap the form row in a `<form>` (or add `hx-trigger`) so Enter in the textbox also greets.

`mojoui_web.mojo` (Python extension module) exposes three functions; state crosses as a Python `dict` of strings:
```
initial_state() -> dict
dispatch(state: dict, msg: str, payload: str) -> dict    # dict → State → update → dict
render(state: dict) -> str                               # dict → State → view → render_html
```
On the web, `msg="greet"` with an included input value dispatches `SET_INPUT(value)` followed by `GREET`.

`server.py` (FastHTML, ≈50 lines, **no UI logic**):
- Imports the prebuilt `mojoui_web` module from `build/`.
- Per-session state in an in-memory dict keyed by a session cookie.
- `GET /` → full HTML page (HTMX script tag + `render(state)`).
- `POST /event` → read `msg` and `value` → `dispatch` → return `render(state)` as raw HTML.
- Serves on `http://localhost:5001`.

---

## 8. Toolchain & tasks

**Installing Mojo (verified):** `pip install mojo` (or `uv pip install mojo`) installs Mojo 1.1.0 from PyPI, no conda channel needed. Pixi with the `https://conda.modular.com/max` channel also works if you prefer pixi.

`pixi.toml` (optional):
- Channels: `https://conda.modular.com/max`, `conda-forge`.
- Dependencies: `mojo` (>=1.1,<2), `sdl3` (available on conda-forge), `sdl3_ttf` if available on conda-forge, `cmake`, `ninja`, `c-compiler`, `python` 3.12, `pkg-config`.
- PyPI dependencies: `python-fasthtml`, `httpx` (for tests).
- If `sdl3_ttf` is not on conda-forge: use the system package (`apt install libsdl3-dev libsdl3-ttf-dev`, `dnf install SDL3-devel SDL3_ttf-devel`, `pacman -S sdl3 sdl3_ttf`), or CMake `FetchContent` from the libsdl-org GitHub repos. Document whichever you used in the README.

How the native pieces link on desktop (verified for the M0 smoke test):
1. Build the bridge: `gcc -Wall -shared -fPIC -o build/libmojoui_bridge.so bridge/mojoui_bridge.c` (CMake later, once SDL3 is involved).
2. Build the Mojo app as a shared library linked against the bridge, **with `$ORIGIN` on its search path**:
   `mojo build hosts/native/app_entry.mojo -I . --emit shared-lib -o build/libmojoui_app.so -Xlinker -Lbuild -Xlinker -lmojoui_bridge -Xlinker -rpath -Xlinker '$ORIGIN'`
   Mojo stamps its own runtime folder into the library's `RUNPATH`, and a library with a `RUNPATH` ignores the executable's `rpath` when looking up *its* dependencies, so the extra `$ORIGIN` is required.
3. Build the host executable: `gcc -Wall -o build/hello-native bridge/host_main.c -Lbuild -lmojoui_app -lmojoui_bridge -Wl,--disable-new-dtags,-rpath,'$ORIGIN'`.
   The Mojo app library depends on exactly one Mojo runtime library, `libKGENCompilerRTShared.so`, found through the `RUNPATH` Mojo stamped in.

Keep the shape: C executable → Mojo app library → C bridge, no `dlopen`.

Tasks:
```
pixi run bridge      # build/libmojoui_bridge.so
pixi run app         # mojo: build/libmojoui_app.so (step 2 above)
pixi run native      # bridge + app + host → ./build/hello-native
pixi run webmod      # mojo build hosts/web/mojoui_web.mojo -I . --emit shared-lib -o build/mojoui_web.so
pixi run web         # webmod + python hosts/web/server.py
pixi run test        # all tests (§9)
```

iOS (M5) differs only in packaging: Mojo emits an **object file** for the iOS target (`--target-triple arm64-apple-ios17.0 --emit object`), and everything (Mojo object, bridge, Clay, SDL3) is linked **statically** into one app by Xcode. Use `llvm-nm` / `llvm-objdump` to inspect Mach-O objects on Linux (GNU `nm` can't read them).

---

## 9. Milestones & acceptance checks (do them in order)

**M0: Toolchain smoke** — ✅ *passed on Linux, 2026-10-14 (see EXPERIMENTS.md)*
- `mojo --version` prints 1.1.x or later.
- The bridge builds with zero warnings at `-Wall -Wextra`.
- A 10-line Mojo program calls `external_call["mui_version", Int32]()` (linked against the bridge as in §8) and prints the result.
- A minimal `host_main.c` calls an exported `mojo_app_init()` from a Mojo shared library, then `mojo_app_event` several times; the Mojo side keeps state across calls and calls back into the bridge. This proves both FFI directions before any UI work.

**M1: Core, headless**
- `tests/test_core.mojo`: `update` cases (append, backspace on multi-byte UTF-8 like "é", greet with empty input, greet with "  Ada  " → "Hello, Ada!").
- View snapshot: `view(state)` produces exactly 6 nodes, with ids `root, title, form, name, greet, greeting` in depth-first order, and the correct roles.

**M2: Web host**
- `tests/test_html.mojo`: HTML snapshot; input `<script>alert(1)</script>` appears escaped.
- `tests/test_web.py`: start server → `GET /` contains `<button`, `<input type="text"` → `POST /event` with `msg=greet&value=Ada` → response contains `Hello, Ada!`.
- Manual: open `http://localhost:5001`, type, click, see the label update without a full page reload.

**M3: Native host on Linux**
- `SDL_VIDEODRIVER=offscreen ./build/hello-native --script "type:Ada;click:greet" --screenshot build/native.bmp` exits 0.
- View the screenshot (convert to PNG if needed) and confirm the label reads "Hello, Ada!".
- With a display (or WSLg): real typing, Backspace, Enter and clicking all work; the window resizes without a crash.

**M4: macOS arm64 (needs a Mac)**
- Same commands produce `.dylib` libraries and a working window. Note any differences in the README.

**M5: iOS go/no-go spike (steps 1–2 run on Linux; steps 3–4 run on Linux via xtool with a real iPhone, or on a Mac with Xcode)**

The goal is a clear yes or no, not a polished app. Stop at the first step that fails and write up what blocked it in `EXPERIMENTS.md`.

1. **Does Mojo accept an iOS target?** — ✅ *Yes.* `mojo build tiny.mojo --target-triple arm64-apple-ios17.0 --emit object` (and `…-simulator`) produce Mach-O arm64 objects stamped `platform ios` / `platform iossimulator`. `--print-supported-targets` lists `arm64`/`aarch64`.
2. **What does it still need?** — ✅ *Measured.* The one-function object needs nothing external. The M0 app code (heap struct, `String`, calls into C) needs only standard C functions that iOS provides (`memcpy`, `write`, `fflush`, `fdopen`, `fclose`, `dup`), our bridge, and **two** Mojo runtime functions: `KGEN_CompilerRT_AlignedAlloc(align, size)` and `KGEN_CompilerRT_AlignedFree(ptr)`. On Linux, a 10-line C stand-in for those two (`spike/kgen_shim.c`) let the app link **statically with no Mojo runtime at all** and run cleanly under AddressSanitizer. Re-measure this every time `core/` grows: run `llvm-nm -u` on the iOS object and record any new runtime symbols.
3. **Swift calls Mojo, on a real iPhone, built from Linux with xtool.** *(Prepared in `ios-xtool/`, not yet built.)* The package links `Mojo/ios-device/libmojoapp.a` (the M0 `app_entry.mojo`, cross-compiled and archived with `llvm-ar --format=darwin`) plus the C glue (`mojoui_bridge.c`, `kgen_shim.c`). A SwiftUI view calls `mojo_app_init` / `mojo_app_event` and reads Mojo's text back with `mui_last_text()`. Run `xtool dev` with the iPhone attached. Acceptance: tap **Greet** three times and see "Hello, Ada! (click 3)". Follow `ios-xtool/README.md`.
   *Mac alternative:* the same package works with Xcode; switch the library path to `Mojo/ios-simulator` to use the simulator.
4. **The real app on iPhone.** Build `core/` (from M1) as an iOS library, expose `view()` as JSON (`mojo_app_view_json`), and grow the SwiftUI skin to render the ViewTree (Text, TextField, Button, VStack/HStack) and send Msgs back. Acceptance: type "Ada" in a real `TextField`, tap Greet, see "Hello, Ada!". This replaces the earlier plan of running SDL3 on iOS.

The runtime stand-in is an **unofficial experiment**: its signatures were inferred from compiled call sites and may change between Mojo releases. Keep it in `spike/`, clearly labelled. Do not rewrite Mach-O platform tags or patch the Mojo compiler; if something deeper blocks progress, record it and stop. The human decides the next step.

**Definition of done for v0:** M0–M3 green; README shows the run commands plus a screenshot of each host side by side. M4 is done when a Mac is available; M5 steps 3–4 when an iPhone and xtool are set up.

---

## 10. Roadmap (do NOT build now; keep the seams for it)

1. **Port layout from Clay to Mojo.** The bridge then shrinks to "window + draw primitives". `ViewTree` doesn't change.
2. **Client-side web host.** Ship a render-command list (or `ViewTree`) to the browser over WebSocket, LiveView-style, and draw with Canvas2D/WebGPU. Clay itself compiles to a ~15 KB WASM module, so layout can run client-side even before Mojo has a WASM target.
3. **Mojo → WASM** if or when the open-source compiler gains that target; then the core runs in the browser directly.
4. **iOS, after M5:** if the app grows to need more of the Mojo runtime than the stand-in covers, build that runtime for iOS from the open-source repo (contributable upstream). Once the app runs, add safe-area insets, rotation, keyboard avoidance, app backgrounding and an App Store build. Until then, iOS users get the web host.
5. **Android:** same shell pattern (SDL3 supports Android), once an Android Mojo target exists.
6. **Accessibility:** turn `role`s into a platform accessibility tree (AccessKit-style; VoiceOver on iOS).
7. **GPU viewport widget:** a Mojo `DeviceContext` kernel renders into a texture shown inside a node.
8. **Real native hooks** in `mui_platform_ping`: haptics, menu bar, file dialogs (Objective-C on Apple platforms).
9. **Windows native** once official Mojo-on-Windows lands; the web host covers Windows until then.

---

## 11. Known risks (for both the agent and the human)

- **Mojo API drift:** 1.x is stable but young. Revision 3 already had to update pointer APIs (`UnsafePointer` → `Pointer`, `Layout`-based `alloc`). Check the `.md` docs and adapt, then note the deviation in `EXPERIMENTS.md`.
- **Python→Mojo bindings are still marked beta** in the docs; keep `mojoui_web.mojo` tiny so churn is cheap.
- **Clay string lifetimes:** the most likely native crash source. Use the per-frame arena from day one.
- **Text input is a deep hole:** v0 does append, Backspace and Enter only. No IME composition, selection, clipboard or caret movement.
- **SDL3_ttf availability** varies by distro; see §8 fallbacks.
- **Two state lifetimes:** web state is per session on the server, native state is in-process. `core/` must stay pure so both work.
- **iOS depends on how much Mojo runtime the app pulls in.** Today it is two allocation functions. Bigger features (async, Python interop, `dlopen`, threads, GPU) may pull in more. Keep `core/` free of those, and re-run the `llvm-nm -u` check as it grows.
- **The runtime stand-in is unofficial** and may break on any Mojo release.
- **Callback-driven code can't block:** never sleep or wait inside `mojo_app_*`; the OS owns the thread.
