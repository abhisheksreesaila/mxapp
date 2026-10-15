# iPhone entry point: runs the app module (`app.mojo`, chosen with -I) with UIKit.
# The linker's `-e _mojo_entry` makes iOS start here.
from std.ffi import c_int

from app import Main
from mojoui.hosts.uikit import run


@export("mojo_entry")
def entry(argc: c_int, argv: Int) abi("C") -> c_int:
    return run[Main](argc, argv)
