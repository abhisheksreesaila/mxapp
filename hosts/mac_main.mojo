# Mac entry point: runs the app module (`app.mojo`, chosen with -I) with AppKit.
# The linker's `-e _mojo_entry` makes macOS start here.
from std.ffi import c_int

from app import Main
from mojoui.hosts.appkit import run


@export("mojo_entry")
def entry(argc: c_int, argv: Int) abi("C") -> c_int:
    return run[Main]()
