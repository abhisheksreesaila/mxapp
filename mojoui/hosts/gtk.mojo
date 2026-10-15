# Linux host: draws a mojoui View with real GTK4 widgets (styled by libadwaita).
#
# Test mode: MOJOUI_TEST="Greet,Greet,Remove@1" taps those buttons on the real
# widgets (by title; @k = the k-th button with that title), then prints every
# label and button as GTK reports it, and quits. The window isn't shown in test
# mode (so tests don't pop up on the desktop) unless MOJOUI_SHOT=<file.png> asks
# GTK to render it to a PNG.

from std.ffi import external_call, c_int, c_char
from std.memory import Pointer
from std.memory.alloc import alloc, Layout

from mojoui.view import View, TEXT, BUTTON, VSTACK, HSTACK, SPACER, TITLE, HEADLINE, CAPTION, PROMINENT
from mojoui.diff import Diff, SET_TEXT
from mojoui.app import App, Runtime

comptime G_APPLICATION_NON_UNIQUE = 32
comptime ORIENTATION_HORIZONTAL = 0
comptime ORIENTATION_VERTICAL = 1
comptime ALIGN_FILL = 0
comptime ALIGN_CENTER = 3


def c_str(addr: Int) -> String:
    """Copies a NUL-terminated C string into a Mojo String."""
    if addr == 0:
        return ""
    return String(unsafe_from_utf8_ptr=Pointer[c_char, MutUntrackedOrigin](unsafe_from_address=addr))


def getenv(name: String) -> String:
    var n = name
    return c_str(external_call["getenv", Int](n.as_c_string_span()))


def add_class(widget: Int, name: String):
    var n = name
    external_call["gtk_widget_add_css_class", NoneType](widget, n.as_c_string_span())


def connect(obj: Int, signal: String, callback: def(Int, Int) thin abi("C"), data: Int):
    var s = signal
    _ = external_call["g_signal_connect_data", Int](obj, s.as_c_string_span(), callback, data, 0, 0)


struct GtkHost[A: App](Movable):
    var rt: Runtime[Self.A]
    var window: Int
    var widgets: List[Int]  # the GTK widget drawn for each node of rt.shown

    def __init__(out self, var app: Self.A):
        self.rt = Runtime(app^)
        self.window = 0
        self.widgets = List[Int]()

    def build(mut self, i: Int, self_addr: Int) -> Int:
        """Creates the GTK widget for node i (and its children)."""
        var node = self.rt.shown.nodes[i].copy()  # copy: building children mutates self
        var w: Int
        if node.kind == TEXT:
            var t = node.text
            w = external_call["gtk_label_new", Int](t.as_c_string_span())
            external_call["gtk_label_set_wrap", NoneType](w, c_int(1))
            external_call["gtk_label_set_justify", NoneType](w, c_int(2))  # GTK_JUSTIFY_CENTER
            if node.style == TITLE:
                add_class(w, "title-1")
            elif node.style == HEADLINE:
                add_class(w, "title-3")
            elif node.style == CAPTION:
                add_class(w, "caption")
                add_class(w, "dim-label")
        elif node.kind == BUTTON:
            var t = node.text
            w = external_call["gtk_button_new_with_label", Int](t.as_c_string_span())
            if node.style == PROMINENT:
                add_class(w, "suggested-action")
                add_class(w, "pill")
            var key = String("mojoui-node")
            external_call["g_object_set_data", NoneType](w, key.as_c_string_span(), i + 1)  # +1: never NULL
            connect(w, "clicked", on_clicked[Self.A], self_addr)
        elif node.kind == SPACER:
            w = external_call["gtk_box_new", Int](c_int(ORIENTATION_VERTICAL), c_int(0))
            external_call["gtk_widget_set_hexpand", NoneType](w, c_int(1))
            external_call["gtk_widget_set_vexpand", NoneType](w, c_int(1))
        else:
            var orientation = ORIENTATION_VERTICAL if node.kind == VSTACK else ORIENTATION_HORIZONTAL
            w = external_call["gtk_box_new", Int](c_int(orientation), c_int(node.spacing))
            if node.kind == HSTACK:
                external_call["gtk_widget_set_halign", NoneType](w, c_int(ALIGN_CENTER))
            for c in node.children:
                var child = self.build(c, self_addr)
                if node.kind == VSTACK and self.rt.shown.nodes[c].kind != SPACER:
                    external_call["gtk_widget_set_halign", NoneType](child, c_int(ALIGN_CENTER))  # natural width, centred
                external_call["gtk_box_append", NoneType](w, child)
        self.widgets[i] = w
        return w

    def show(mut self, self_addr: Int):
        """(Re)builds the window's content from rt.shown."""
        self.widgets = List[Int](length=len(self.rt.shown.nodes), fill=0)
        var root = self.build(0, self_addr)
        external_call["gtk_widget_set_valign", NoneType](root, c_int(ALIGN_CENTER))
        external_call["gtk_widget_set_margin_top", NoneType](root, c_int(32))
        external_call["gtk_widget_set_margin_bottom", NoneType](root, c_int(32))
        external_call["gtk_widget_set_margin_start", NoneType](root, c_int(32))
        external_call["gtk_widget_set_margin_end", NoneType](root, c_int(32))
        external_call["gtk_window_set_child", NoneType](self.window, root)

    def apply(mut self, d: Diff, self_addr: Int):
        if d.rebuild:
            self.show(self_addr)
            return
        for p in d.patches:
            if p.op == SET_TEXT:
                var t = p.text
                var w = self.widgets[p.node]
                if self.rt.shown.nodes[p.node].kind == TEXT:
                    external_call["gtk_label_set_text", NoneType](w, t.as_c_string_span())
                else:
                    external_call["gtk_button_set_label", NoneType](w, t.as_c_string_span())
            # SET_MSG needs nothing: taps look the message up in rt.shown.


def host_at[A: App](addr: Int) -> Pointer[GtkHost[A], MutUntrackedOrigin]:
    return Pointer[GtkHost[A], MutUntrackedOrigin](unsafe_from_address=addr)


def on_clicked[A: App](button: Int, host_addr: Int) abi("C"):
    """GTK calls this on every button tap: run update(), then patch the widgets."""
    var key = String("mojoui-node")
    var node = external_call["g_object_get_data", Int](button, key.as_c_string_span()) - 1
    var host = host_at[A](host_addr)
    var d = host[].rt.dispatch(host[].rt.shown.nodes[node].msg)
    host[].apply(d, host_addr)


def run_test_steps[A: App](host_addr: Int):
    var host = host_at[A](host_addr)
    var steps = getenv("MOJOUI_TEST")
    for step_slice in steps.split(","):
        var step = String(step_slice)
        var title = step
        var nth = 0
        var at = step.find("@")
        if at >= 0:
            title = String(step[byte=:at])
            try:
                nth = Int(String(step[byte = at + 1 :]))
            except:
                print("TEST: bad step", step)
        var seen = 0
        var found = -1
        for i in range(len(host[].rt.shown.nodes)):
            ref n = host[].rt.shown.nodes[i]
            if n.kind == BUTTON and n.text == title:
                if seen == nth:
                    found = i
                    break
                seen += 1
        if found < 0:
            print("TEST: no button", step)
            continue
        var signal = String("clicked")
        external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](
            host[].widgets[found], signal.as_c_string_span()
        )
    print(
        "NATIVE: GTK",
        String(external_call["gtk_get_major_version", c_int]()) + "." + String(external_call["gtk_get_minor_version", c_int]()),
    )
    for i in range(len(host[].rt.shown.nodes)):
        ref n = host[].rt.shown.nodes[i]
        if n.kind == TEXT:
            print("LABEL: " + c_str(external_call["gtk_label_get_text", Int](host[].widgets[i])))
        elif n.kind == BUTTON:
            print("BUTTON: " + c_str(external_call["gtk_button_get_label", Int](host[].widgets[i])))


def save_png(window: Int, path: String):
    """Asks GTK to render the window (as drawn on screen) into a PNG file."""
    for _ in range(500):  # wait until the window is on screen
        if external_call["gtk_widget_get_mapped", c_int](window) != 0:
            break
        _ = external_call["g_main_context_iteration", c_int](0, c_int(1))
    for _ in range(50):  # let layout and drawing settle
        _ = external_call["g_main_context_iteration", c_int](0, c_int(0))
    var paintable = external_call["gtk_widget_paintable_new", Int](window)
    var w = external_call["gtk_widget_get_width", c_int](window)
    var h = external_call["gtk_widget_get_height", c_int](window)
    var snap = external_call["gtk_snapshot_new", Int]()
    external_call["gdk_paintable_snapshot", NoneType](paintable, snap, Float64(Int(w)), Float64(Int(h)))
    var node = external_call["gtk_snapshot_free_to_node", Int](snap)
    var renderer = external_call["gtk_native_get_renderer", Int](window)
    var texture = external_call["gsk_renderer_render_texture", Int](renderer, node, 0)
    var p = path
    var ok = external_call["gdk_texture_save_to_png", c_int](texture, p.as_c_string_span())
    print("SHOT:", path if ok != 0 else "failed")


def on_activate[A: App](gapp: Int, host_addr: Int) abi("C"):
    var host = host_at[A](host_addr)
    host[].window = external_call["gtk_application_window_new", Int](gapp)
    var title = host[].rt.app.title()
    external_call["gtk_window_set_title", NoneType](host[].window, title.as_c_string_span())
    external_call["gtk_window_set_default_size", NoneType](host[].window, c_int(460), c_int(340))
    host[].show(host_addr)
    var testing = getenv("MOJOUI_TEST") != ""
    var shot = getenv("MOJOUI_SHOT")
    if not testing or shot != "":
        external_call["gtk_window_present", NoneType](host[].window)
    if testing:
        run_test_steps[A](host_addr)
    if shot != "":
        save_png(host[].window, shot)
    if testing or shot != "":
        external_call["g_application_quit", NoneType](gapp)


def run[A: App]() -> Int:
    """Opens the app in a native GTK window and runs until it's closed."""
    var host = alloc(Layout[GtkHost[A]].single()).unsafe_leak()  # lives as long as the app
    host.unsafe_write(GtkHost[A](A()))
    var id = String("dev.mojoui.App")
    var gapp = external_call["adw_application_new", Int](id.as_c_string_span(), c_int(G_APPLICATION_NON_UNIQUE))
    connect(gapp, "activate", on_activate[A], Int(host))
    return Int(external_call["g_application_run", c_int](gapp, c_int(0), 0))
