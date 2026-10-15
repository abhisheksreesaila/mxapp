# Android entry point (exploration, see docs/android.md): the app module
# (`app.mojo`, chosen with -I) built into libmojoui.so for a NativeActivity.
#
# Today this proves the app and the mojoui core run as Android arm64 native code:
# Android calls ANativeActivity_onCreate on the UI thread; we create the app,
# build its first screen and log it. Drawing it with real Android views (via JNI)
# and receiving taps is the next step; docs/android.md explains the blocker.
from std.ffi import external_call, c_int

from app import Main
from mojoui.app import Runtime


def log(text: String):
    var tag = String("mojoui")
    var t = text
    _ = external_call["__android_log_write", c_int](c_int(4), tag.as_c_string_span(), t.as_c_string_span())  # INFO


@export("ANativeActivity_onCreate")
def on_create(activity: Int, saved_state: Int, saved_state_size: Int) abi("C"):
    var rt = Runtime(Main())
    var buttons = 0
    for n in rt.shown.nodes:
        if n.kind == 2:
            buttons += 1
    log(rt.app.title() + ": first screen has " + String(len(rt.shown.nodes)) + " nodes, " + String(buttons) + " buttons")
