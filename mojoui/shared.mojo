# mojoui.shared: a process-wide registry for data built once by App.init_shared() and read by every
# session (web tabs, windows). Mojo has no global variables, so the addresses live in the process
# environment (MOJOUI_SHARED_<slot>): every host and platform has one.
#
#   @staticmethod
#   def init_shared():
#       if get_shared(0) == 0:
#           put_shared(0, share(generate_columns(20_000_000)))   # mojoui.frame.share → an address
#   def __init__(out self):
#       self.frame = Frame(get_shared(0))

from std.os import getenv, setenv
from std.memory.alloc import alloc, Layout


def put_shared(slot: Int, addr: Int):
    _ = setenv("MOJOUI_SHARED_" + String(slot), String(addr), True)


def get_shared(slot: Int) -> Int:
    var text = getenv("MOJOUI_SHARED_" + String(slot), "")
    if text == "":
        return 0
    try:
        return Int(text)
    except:
        return 0


def shared_loads() -> Int:
    """How many times init_shared() built its data in this process (hosts report it)."""
    return get_shared(99)


def count_load():
    put_shared(99, shared_loads() + 1)


def keep[T: Movable](var value: T) -> Int:
    """Moves a value to the heap for the life of the process; returns its address (see at[T])."""
    var p = alloc(Layout[T].single()).unsafe_leak()
    p.unsafe_write(value^)
    return Int(p)


def at[T: Movable](addr: Int) -> Pointer[T, MutUntrackedOrigin]:
    return Pointer[T, MutUntrackedOrigin](unsafe_from_address=addr)
