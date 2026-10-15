from std.memory.alloc import alloc, Layout
from std.memory import Pointer
from std.ffi import external_call


struct App(Movable):
    var clicks: Int
    var greeting: String

    def __init__(out self):
        self.clicks = 0
        self.greeting = String("")


def app_ptr(app: Int) -> Pointer[App, MutUntrackedOrigin]:
    return Pointer[App, MutUntrackedOrigin](unsafe_from_address=app)


@export
def mojo_app_init() abi("C") -> Int:
    var allocation = alloc(Layout[App].single())
    # Hand ownership to C on purpose: C keeps the address and passes it back on every call.
    var p = allocation^.unsafe_leak()
    p.unsafe_write(App())
    return Int(p)


@export
def mojo_app_event(app: Int, kind: Int32) abi("C") -> Int32:
    var p = app_ptr(app)
    if kind == 1:  # "button clicked"
        p[].clicks += 1
        p[].greeting = String("Hello, Ada! (click ") + String(p[].clicks) + ")"
        var g = p[].greeting
        _ = external_call["mui_echo", Int32](g.unsafe_ptr(), Int32(g.byte_length()))
    return 0


@export
def mojo_app_quit(app: Int) abi("C"):
    var p = app_ptr(app)
    p.unsafe_deinit_pointee()
    p.unsafe_free()
