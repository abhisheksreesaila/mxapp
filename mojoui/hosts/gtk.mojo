# Linux host: draws a mojoui View with real GTK4 widgets (styled by libadwaita).
#
# Test mode (used by scripts/check): MOJOUI_TEST="tap:Greet;type:Your name=Ada;
# submit:Your name;toggle:Notifications;select:0=Large;slide:0=70" drives the
# real widgets through their normal APIs (so their real signals fire), then
# prints each widget's state as GTK reports it and quits. The window isn't
# shown unless MOJOUI_SHOT=<file.png> asks GTK to render it to a PNG.

from std.ffi import external_call, c_int, c_char, c_uint
from std.memory import Pointer
from std.memory.alloc import alloc, Layout

from mojoui.view import (
    View, TEXT, BUTTON, VSTACK, HSTACK, SPACER, FIELD, TOGGLE, DROPDOWN, SLIDER, PROGRESS, DIVIDER, SCROLL, IMAGE,
    SEGMENTED, RADIO, TEXTAREA, ALERT, TABS, NAVBAR, DATE, ICON, GRID, LAZYLIST,
    TITLE, HEADLINE, CAPTION, PROMINENT, DESTRUCTIVE,
)
from mojoui.diff import Diff, SET_TEXT, SET_VALUE, SET_IMAGE
from mojoui.app import App, Event, Runtime

comptime G_APPLICATION_NON_UNIQUE = 32
comptime HORIZONTAL = 0
comptime VERTICAL = 1
comptime ALIGN_CENTER = 3
comptime RTLD_DEFAULT = 0  # glibc
comptime NODE_KEY = "mojoui-node"


# ---------- small C helpers ----------

def c_str(addr: Int) -> String:
    """Copies a NUL-terminated C string into a Mojo String."""
    if addr == 0:
        return ""
    return String(unsafe_from_utf8_ptr=Pointer[c_char, MutUntrackedOrigin](unsafe_from_address=addr))


def getenv(name: String) -> String:
    var n = name
    return c_str(external_call["getenv", Int](n.as_c_string_span()))


def ccall[T: RegisterPassable = Int, *A: AnyType](name: String, *args: *A) -> T:
    """Calls a C function found at run time, with this call's argument types.
    (For functions we need with several signatures, e.g. g_signal_connect_data.)"""
    var n = name
    var addr = external_call["dlsym", Int](RTLD_DEFAULT, n.as_c_string_span())
    var raw = Pointer[NoneType, MutUntrackedOrigin](unsafe_from_address=addr)
    var f = Pointer(to=raw).unsafe_bitcast[def(*a: *A) thin abi("C") -> T]()[]
    return f(*args)


def connect(obj: Int, signal: String, callback: def(Int, Int) thin abi("C"), data: Int):
    var s = signal
    _ = ccall("g_signal_connect_data", obj, s.as_c_string_span(), callback, data, 0, 0)


def connect3(obj: Int, signal: String, callback: def(Int, Int, Int) thin abi("C"), data: Int):
    var s = signal
    _ = ccall("g_signal_connect_data", obj, s.as_c_string_span(), callback, data, 0, 0)


def add_class(widget: Int, name: String):
    var n = name
    external_call["gtk_widget_add_css_class", NoneType](widget, n.as_c_string_span())


def set_node(widget: Int, node: Int):
    var key = String(NODE_KEY)
    external_call["g_object_set_data", NoneType](widget, key.as_c_string_span(), node + 1)  # +1: never NULL


def get_node(widget: Int) -> Int:
    var key = String(NODE_KEY)
    return external_call["g_object_get_data", Int](widget, key.as_c_string_span()) - 1


def set_busy(on: Bool):
    """Marks that the host itself is changing widgets, so their signals are ignored.

    Kept on the GApplication (a real C call), not in a Mojo field: the signals
    arrive re-entrantly while a `mut self` method runs, and the compiler may
    assume nothing else reads that field in between.
    """
    var key = String("mojoui-busy")
    var app = external_call["g_application_get_default", Int]()
    external_call["g_object_set_data", NoneType](app, key.as_c_string_span(), 1 if on else 0)


def busy() -> Bool:
    var key = String("mojoui-busy")
    var app = external_call["g_application_get_default", Int]()
    return external_call["g_object_get_data", Int](app, key.as_c_string_span()) != 0


def texture(pixels: List[UInt32], w: Int, h: Int) -> Int:
    """A GdkMemoryTexture holding a copy of the RGBA pixels."""
    comptime GDK_MEMORY_R8G8B8A8 = 5
    var n = len(pixels) * 4
    var bytes = external_call["g_bytes_new", Int](Int(pixels.unsafe_ptr()), n)  # copies
    var tex = external_call["gdk_memory_texture_new", Int](c_int(w), c_int(h), c_int(GDK_MEMORY_R8G8B8A8), bytes, w * 4)
    external_call["g_bytes_unref", NoneType](bytes)
    return tex


def width(widget: Int, w: Int):
    external_call["gtk_widget_set_size_request", NoneType](widget, c_int(w), c_int(-1))


comptime INDEX_KEY = "mojoui-index"


def set_index(obj: Int, index: Int):
    var key = String(INDEX_KEY)
    external_call["g_object_set_data", NoneType](obj, key.as_c_string_span(), index + 1)


def get_index(obj: Int) -> Int:
    var key = String(INDEX_KEY)
    return external_call["g_object_get_data", Int](obj, key.as_c_string_span()) - 1


def count_up(name: String):
    """A counter kept on the GApplication (safe to bump from re-entrant callbacks)."""
    var key = name
    var app = external_call["g_application_get_default", Int]()
    var n = external_call["g_object_get_data", Int](app, key.as_c_string_span())
    external_call["g_object_set_data", NoneType](app, key.as_c_string_span(), n + 1)


def counter(name: String) -> Int:
    var key = name
    var app = external_call["g_application_get_default", Int]()
    return external_call["g_object_get_data", Int](app, key.as_c_string_span())


def gtk_icon(name: String) -> String:
    """mojoui icon names → Adwaita symbolic icons."""
    if name == "star": return "starred-symbolic"
    if name == "trash": return "user-trash-symbolic"
    if name == "gear": return "emblem-system-symbolic"
    if name == "plus": return "list-add-symbolic"
    if name == "check": return "object-select-symbolic"
    if name == "calendar": return "x-office-calendar-symbolic"
    if name == "search": return "system-search-symbolic"
    if name == "heart": return "emblem-favorite-symbolic"
    if name == "home": return "go-home-symbolic"
    if name == "person": return "avatar-default-symbolic"
    if name == "travel": return "airplane-mode-symbolic"
    if name == "food": return "emoji-food-symbolic"
    if name == "fun": return "emoji-activities-symbolic"
    if name == "chart": return "x-office-spreadsheet-symbolic"
    return "image-missing-symbolic"


def mojo_icon(gtk_name: String) -> String:
    for n in ["star", "trash", "gear", "plus", "check", "calendar", "search", "heart", "home", "person", "travel", "food", "fun", "chart"]:
        if gtk_icon(n) == gtk_name:
            return n
    return "?"


def parse_date(text: String) -> Tuple[Int, Int, Int]:
    """ "YYYY-MM-DD" → (year, month, day); (2000, 1, 1) if it doesn't parse."""
    try:
        var parts = text.split("-")
        if len(parts) == 3:
            return (Int(String(parts[0])), Int(String(parts[1])), Int(String(parts[2])))
    except:
        pass
    return (2000, 1, 1)


def two(n: Int) -> String:
    return ("0" if n < 10 else "") + String(n)


def calendar_date(cal: Int) -> String:
    var dt = external_call["gtk_calendar_get_date", Int](cal)
    var y = Int(external_call["g_date_time_get_year", c_int](dt))
    var m = Int(external_call["g_date_time_get_month", c_int](dt))
    var d = Int(external_call["g_date_time_get_day_of_month", c_int](dt))
    external_call["g_date_time_unref", NoneType](dt)
    return String(y) + "-" + two(m) + "-" + two(d)


def calendar_select(cal: Int, text: String):
    var ymd = parse_date(text)
    var dt = external_call["g_date_time_new_local", Int](c_int(ymd[0]), c_int(ymd[1]), c_int(ymd[2]), c_int(0), c_int(0), Float64(0))
    external_call["gtk_calendar_select_day", NoneType](cal, dt)
    external_call["g_date_time_unref", NoneType](dt)


def buffer_text(buffer: Int) -> String:
    """All the text in a GtkTextBuffer."""
    var start = List[Int](length=16, fill=0)  # GtkTextIter is ~80 bytes; 128 is plenty
    var end = List[Int](length=16, fill=0)
    external_call["gtk_text_buffer_get_bounds", NoneType](buffer, Int(start.unsafe_ptr()), Int(end.unsafe_ptr()))
    var raw = external_call["gtk_text_buffer_get_text", Int](buffer, Int(start.unsafe_ptr()), Int(end.unsafe_ptr()), c_int(0))
    # Keep the iterator buffers alive until here: Mojo frees values right after their
    # last use, and turning a pointer into an Int doesn't count as a use.
    _ = len(start)
    _ = len(end)
    var text = c_str(raw)
    external_call["g_free", NoneType](raw)
    return text


def escape_newlines(text: String) -> String:
    return text.replace("\n", "\\n")


# ---------- the host ----------

struct GtkHost[A: App](Movable):
    var rt: Runtime[Self.A]
    var window: Int
    var widgets: List[Int]  # the GTK widget drawn for each node of rt.shown
    var dialog: Int  # the open alert dialog, if any
    var focus: Int  # text field to keep focused across the next rebuild (-1: none)

    def __init__(out self, var app: Self.A):
        self.rt = Runtime(app^)
        self.window = 0
        self.widgets = List[Int]()
        self.dialog = 0
        self.focus = -1

    def build(mut self, i: Int, self_addr: Int) -> Int:
        """Creates the GTK widget for node i (and its children)."""
        var node = self.rt.shown.nodes[i].copy()  # copy: building children mutates self
        var w: Int
        if node.kind == TEXT:
            var t = node.text
            w = external_call["gtk_label_new", Int](t.as_c_string_span())
            external_call["gtk_label_set_wrap", NoneType](w, c_int(1))
            external_call["gtk_label_set_justify", NoneType](w, c_int(2))  # centre
            if node.style == TITLE:
                add_class(w, "title-1")
            elif node.style == HEADLINE:
                add_class(w, "title-4")
            elif node.style == CAPTION:
                add_class(w, "caption")
                add_class(w, "dim-label")
        elif node.kind == BUTTON:
            var t = node.text
            w = external_call["gtk_button_new_with_label", Int](t.as_c_string_span())
            if node.style == PROMINENT:
                add_class(w, "suggested-action")
                add_class(w, "pill")
            elif node.style == DESTRUCTIVE:
                add_class(w, "destructive-action")
            connect(w, "clicked", on_clicked[Self.A], self_addr)
        elif node.kind == FIELD:
            w = external_call["gtk_entry_new", Int]()
            var t = node.text
            var h = node.hint
            external_call["gtk_editable_set_text", NoneType](w, t.as_c_string_span())
            external_call["gtk_entry_set_placeholder_text", NoneType](w, h.as_c_string_span())
            width(w, 220)
            connect(w, "changed", on_field_changed[Self.A], self_addr)
            connect(w, "activate", on_field_submit[Self.A], self_addr)
        elif node.kind == TOGGLE:
            var t = node.text
            w = external_call["gtk_check_button_new_with_label", Int](t.as_c_string_span())
            external_call["gtk_check_button_set_active", NoneType](w, c_int(node.value))
            connect(w, "toggled", on_toggled[Self.A], self_addr)
        elif node.kind == DROPDOWN:
            var model = external_call["gtk_string_list_new", Int](0)
            for o in node.options:
                var s = o
                external_call["gtk_string_list_append", NoneType](model, s.as_c_string_span())
            w = external_call["gtk_drop_down_new", Int](model, 0)
            external_call["gtk_drop_down_set_selected", NoneType](w, c_uint(node.value))
            connect3(w, "notify::selected", on_selected[Self.A], self_addr)
        elif node.kind == SLIDER:
            w = external_call["gtk_scale_new_with_range", Int](c_int(HORIZONTAL), Float64(0), Float64(100), Float64(1))
            external_call["gtk_range_set_value", NoneType](w, Float64(node.value))
            width(w, 240)
            connect(w, "value-changed", on_slid[Self.A], self_addr)
        elif node.kind == PROGRESS:
            w = external_call["gtk_progress_bar_new", Int]()
            external_call["gtk_progress_bar_set_fraction", NoneType](w, Float64(node.value) / 100.0)
            width(w, 240)
        elif node.kind == DIVIDER:
            w = external_call["gtk_separator_new", Int](c_int(HORIZONTAL))
            width(w, 280)
        elif node.kind == IMAGE:
            var tex = texture(node.pixels, node.spacing, node.size)
            w = external_call["gtk_picture_new_for_paintable", Int](tex)
            external_call["g_object_unref", NoneType](tex)
            external_call["gtk_picture_set_can_shrink", NoneType](w, c_int(0))
            external_call["gtk_picture_set_content_fit", NoneType](w, c_int(3))  # scale-down: never bigger than its pixels
            external_call["gtk_widget_set_halign", NoneType](w, c_int(ALIGN_CENTER))
            external_call["gtk_widget_set_valign", NoneType](w, c_int(ALIGN_CENTER))
            external_call["gtk_widget_set_size_request", NoneType](w, c_int(node.spacing), c_int(node.size))
        elif node.kind == SEGMENTED or node.kind == TABS:
            w = external_call["adw_toggle_group_new", Int]()  # GNOME's own segmented control
            for j in range(len(node.options)):
                var t = external_call["adw_toggle_new", Int]()
                var label = node.options[j]
                external_call["adw_toggle_set_label", NoneType](t, label.as_c_string_span())
                external_call["adw_toggle_group_add", NoneType](w, t)
            external_call["adw_toggle_group_set_active", NoneType](w, c_uint(node.value))
            if node.kind == TABS:
                add_class(w, "round")
            connect3(w, "notify::active", on_toggle_group[Self.A], self_addr)
        elif node.kind == RADIO:
            w = external_call["gtk_box_new", Int](c_int(VERTICAL), c_int(4))
            var first = 0
            for j in range(len(node.options)):
                var label = node.options[j]
                var b = external_call["gtk_check_button_new_with_label", Int](label.as_c_string_span())
                if first == 0:
                    first = b
                else:
                    external_call["gtk_check_button_set_group", NoneType](b, first)  # radio look
                external_call["gtk_check_button_set_active", NoneType](b, c_int(1 if j == node.value else 0))
                set_node(b, i)
                set_index(b, j)
                connect(b, "toggled", on_radio[Self.A], self_addr)
                external_call["gtk_box_append", NoneType](w, b)
        elif node.kind == TEXTAREA:
            var view = external_call["gtk_text_view_new", Int]()
            external_call["gtk_text_view_set_wrap_mode", NoneType](view, c_int(2))  # GTK_WRAP_WORD
            external_call["gtk_text_view_set_left_margin", NoneType](view, c_int(8))
            external_call["gtk_text_view_set_top_margin", NoneType](view, c_int(8))
            var buffer = external_call["gtk_text_view_get_buffer", Int](view)
            var t = node.text
            external_call["gtk_text_buffer_set_text", NoneType](buffer, t.as_c_string_span(), c_int(-1))
            set_node(buffer, i)
            connect(buffer, "changed", on_text_changed[Self.A], self_addr)
            self.widgets[i] = view
            w = external_call["gtk_scrolled_window_new", Int]()
            external_call["gtk_scrolled_window_set_child", NoneType](w, view)
            add_class(w, "card")
            external_call["gtk_widget_set_size_request", NoneType](w, c_int(320), c_int(node.size))
        elif node.kind == ALERT:
            var heading = node.text
            var body = node.hint
            w = external_call["adw_alert_dialog_new", Int](heading.as_c_string_span(), body.as_c_string_span())
            for j in range(len(node.options)):
                var id = String(j)
                var label = node.options[j]
                external_call["adw_alert_dialog_add_response", NoneType](w, id.as_c_string_span(), label.as_c_string_span())
            set_node(w, i)
            connect3(w, "response", on_alert_response[Self.A], self_addr)
            _ = external_call["g_object_ref_sink", Int](w)
            self.dialog = w
            self.widgets[i] = w
            w = external_call["gtk_box_new", Int](c_int(VERTICAL), c_int(0))  # nothing in the layout itself
        elif node.kind == NAVBAR:
            w = external_call["gtk_box_new", Int](c_int(HORIZONTAL), c_int(8))
            if node.msg != 0:
                var icon = String("go-previous-symbolic")
                var back = external_call["gtk_button_new_from_icon_name", Int](icon.as_c_string_span())
                add_class(back, "flat")
                set_node(back, i)
                connect(back, "clicked", on_clicked[Self.A], self_addr)
                external_call["gtk_box_append", NoneType](w, back)
            var t = node.text
            var title = external_call["gtk_label_new", Int](t.as_c_string_span())
            add_class(title, "title-2")
            external_call["gtk_box_append", NoneType](w, title)
        elif node.kind == DATE:
            w = external_call["gtk_calendar_new", Int]()
            calendar_select(w, node.text)
            connect(w, "day-selected", on_day_selected[Self.A], self_addr)
        elif node.kind == ICON:
            var name = gtk_icon(node.text)
            w = external_call["gtk_image_new_from_icon_name", Int](name.as_c_string_span())
            external_call["gtk_image_set_pixel_size", NoneType](w, c_int(node.size))
        elif node.kind == GRID:
            w = external_call["gtk_grid_new", Int]()
            external_call["gtk_grid_set_row_spacing", NoneType](w, c_uint(node.spacing))
            external_call["gtk_grid_set_column_spacing", NoneType](w, c_uint(node.spacing))
            external_call["gtk_grid_set_column_homogeneous", NoneType](w, c_int(1))
            for k in range(len(node.children)):
                var child = self.build(node.children[k], self_addr)
                external_call["gtk_grid_attach", NoneType](w, child, c_int(k % node.value), c_int(k // node.value), c_int(1), c_int(1))
        elif node.kind == LAZYLIST:
            var model = external_call["gtk_string_list_new", Int](0)
            var empty = String("")
            for _ in range(node.value):  # placeholders only; row text is asked for when a row is shown
                external_call["gtk_string_list_append", NoneType](model, empty.as_c_string_span())
            var selection = external_call["gtk_no_selection_new", Int](model)
            var factory = external_call["gtk_signal_list_item_factory_new", Int]()
            set_node(factory, i)
            connect3(factory, "setup", on_row_setup[Self.A], self_addr)
            connect3(factory, "bind", on_row_bind[Self.A], self_addr)
            var list = external_call["gtk_list_view_new", Int](selection, factory)
            external_call["gtk_list_view_set_single_click_activate", NoneType](list, c_int(1))
            add_class(list, "boxed-list")
            set_node(list, i)
            connect3(list, "activate", on_row_activate[Self.A], self_addr)
            self.widgets[i] = list
            w = external_call["gtk_scrolled_window_new", Int]()
            external_call["gtk_scrolled_window_set_child", NoneType](w, list)
            external_call["gtk_scrolled_window_set_policy", NoneType](w, c_int(2), c_int(1))
            external_call["gtk_widget_set_size_request", NoneType](w, c_int(340), c_int(node.size))
        elif node.kind == SPACER:
            w = external_call["gtk_box_new", Int](c_int(VERTICAL), c_int(0))
            external_call["gtk_widget_set_hexpand", NoneType](w, c_int(1))
            external_call["gtk_widget_set_vexpand", NoneType](w, c_int(1))
        elif node.kind == SCROLL:
            w = external_call["gtk_scrolled_window_new", Int]()
            external_call["gtk_scrolled_window_set_policy", NoneType](w, c_int(2), c_int(1))  # never, automatic
            external_call["gtk_scrolled_window_set_max_content_height", NoneType](w, c_int(node.size))
            external_call["gtk_scrolled_window_set_propagate_natural_height", NoneType](w, c_int(1))
            external_call["gtk_scrolled_window_set_propagate_natural_width", NoneType](w, c_int(1))
            for c in node.children:
                external_call["gtk_scrolled_window_set_child", NoneType](w, self.build(c, self_addr))
        else:
            var orientation = VERTICAL if node.kind == VSTACK else HORIZONTAL
            w = external_call["gtk_box_new", Int](c_int(orientation), c_int(node.spacing))
            if node.kind == HSTACK:
                external_call["gtk_widget_set_halign", NoneType](w, c_int(ALIGN_CENTER))
            for c in node.children:
                var child = self.build(c, self_addr)
                if node.kind == VSTACK and self.rt.shown.nodes[c].kind != SPACER:
                    external_call["gtk_widget_set_halign", NoneType](child, c_int(ALIGN_CENTER))
                if node.kind == HSTACK:
                    external_call["gtk_widget_set_valign", NoneType](child, c_int(ALIGN_CENTER))
                external_call["gtk_box_append", NoneType](w, child)
        set_node(w, i)
        if self.widgets[i] == 0:  # (some branches already stored an inner control)
            self.widgets[i] = w
        return w

    def show(mut self, self_addr: Int):
        """(Re)builds the window's content from rt.shown."""
        set_busy(True)
        if self.dialog != 0:  # the previous screen's alert goes with it
            _ = external_call["adw_dialog_force_close", c_int](self.dialog)
            external_call["g_object_unref", NoneType](self.dialog)
            self.dialog = 0
        self.widgets = List[Int](length=len(self.rt.shown.nodes), fill=0)
        var root = self.build(0, self_addr)
        external_call["gtk_widget_set_valign", NoneType](root, c_int(ALIGN_CENTER))
        external_call["gtk_widget_set_margin_top", NoneType](root, c_int(32))
        external_call["gtk_widget_set_margin_bottom", NoneType](root, c_int(32))
        external_call["gtk_widget_set_margin_start", NoneType](root, c_int(32))
        external_call["gtk_widget_set_margin_end", NoneType](root, c_int(32))
        external_call["gtk_window_set_child", NoneType](self.window, root)
        if self.dialog != 0 and getenv("MOJOUI_TEST") == "":  # tests drive the dialog without showing it
            external_call["adw_dialog_present", NoneType](self.dialog, self.window)
        if 0 <= self.focus < len(self.widgets) and self.rt.shown.nodes[self.focus].kind == FIELD:
            _ = external_call["gtk_entry_grab_focus_without_selecting", c_int](self.widgets[self.focus])  # keep typing
        self.focus = -1
        set_busy(False)

    def apply(mut self, d: Diff, self_addr: Int):
        if d.rebuild:
            # Rebuild on the next idle turn, never inside a signal handler: the widget
            # that sent the signal would be destroyed while GTK is still using it.
            set_busy(True)  # ignore events until the new widgets are up
            _ = external_call["g_idle_add", c_uint](on_idle_rebuild[Self.A], self_addr)
            return
        set_busy(True)
        for p in d.patches:
            var w = self.widgets[p.node]
            var kind = self.rt.shown.nodes[p.node].kind
            if p.op == SET_TEXT:
                var t = p.text
                if kind == TEXT:
                    external_call["gtk_label_set_text", NoneType](w, t.as_c_string_span())
                elif kind == BUTTON or kind == TOGGLE:
                    external_call["gtk_button_set_label", NoneType](w, t.as_c_string_span()) if kind == BUTTON else external_call["gtk_check_button_set_label", NoneType](w, t.as_c_string_span())
                elif kind == FIELD:
                    if c_str(external_call["gtk_editable_get_text", Int](w)) != p.text:  # don't fight the typist
                        external_call["gtk_editable_set_text", NoneType](w, t.as_c_string_span())
            elif p.op == SET_TEXT and kind == TEXTAREA:
                pass  # (handled below)
            if p.op == SET_TEXT and kind == TEXTAREA:
                var buffer = external_call["gtk_text_view_get_buffer", Int](w)
                if buffer_text(buffer) != p.text:  # don't fight the typist
                    var t = p.text
                    external_call["gtk_text_buffer_set_text", NoneType](buffer, t.as_c_string_span(), c_int(-1))
            elif p.op == SET_TEXT and kind == DATE:
                if calendar_date(w) != p.text:
                    calendar_select(w, p.text)
            elif p.op == SET_TEXT and kind == NAVBAR:
                var title = external_call["gtk_widget_get_last_child", Int](w)
                var t = p.text
                external_call["gtk_label_set_text", NoneType](title, t.as_c_string_span())
            elif p.op == SET_VALUE and (kind == SEGMENTED or kind == TABS):
                external_call["adw_toggle_group_set_active", NoneType](w, c_uint(p.number))
            elif p.op == SET_VALUE and kind == RADIO:
                var b = external_call["gtk_widget_get_first_child", Int](w)
                var j = 0
                while b != 0:
                    external_call["gtk_check_button_set_active", NoneType](b, c_int(1 if j == p.number else 0))
                    b = external_call["gtk_widget_get_next_sibling", Int](b)
                    j += 1
            elif p.op == SET_VALUE and kind == LAZYLIST:
                var model = external_call["gtk_string_list_new", Int](0)
                var empty = String("")
                for _ in range(p.number):
                    external_call["gtk_string_list_append", NoneType](model, empty.as_c_string_span())
                var selection = external_call["gtk_list_view_get_model", Int](w)
                external_call["gtk_no_selection_set_model", NoneType](selection, model)
                external_call["g_object_unref", NoneType](model)
            elif p.op == SET_VALUE:
                if kind == TOGGLE:
                    external_call["gtk_check_button_set_active", NoneType](w, c_int(p.number))
                elif kind == DROPDOWN:
                    external_call["gtk_drop_down_set_selected", NoneType](w, c_uint(p.number))
                elif kind == SLIDER:
                    external_call["gtk_range_set_value", NoneType](w, Float64(p.number))
                elif kind == PROGRESS:
                    external_call["gtk_progress_bar_set_fraction", NoneType](w, Float64(p.number) / 100.0)
            elif p.op == SET_IMAGE:
                ref img = self.rt.shown.nodes[p.node]
                var tex = texture(img.pixels, img.spacing, img.size)
                external_call["gtk_picture_set_paintable", NoneType](w, tex)
                external_call["g_object_unref", NoneType](tex)
            # SET_MSG needs nothing: events look the message up in rt.shown.
        set_busy(False)

    def send(mut self, node: Int, second: Bool, text: String, number: Int, self_addr: Int):
        """A widget changed: build the event, run update(), patch the widgets."""
        ref n = self.rt.shown.nodes[node]
        var message = n.msg2 if second else n.msg
        if message == 0:
            return
        self.focus = node if n.kind == FIELD else -1
        var d = self.rt.dispatch(Event(message, text, number))
        self.apply(d, self_addr)


def host_at[A: App](addr: Int) -> Pointer[GtkHost[A], MutUntrackedOrigin]:
    return Pointer[GtkHost[A], MutUntrackedOrigin](unsafe_from_address=addr)


# ---------- signal handlers (GTK calls these) ----------

def on_idle_rebuild[A: App](host_addr: Int) abi("C") -> c_int:
    host_at[A](host_addr)[].show(host_addr)  # show() clears the busy flag
    return 0  # G_SOURCE_REMOVE: run once


def settle():
    """Runs pending GTK work (such as a deferred rebuild) before the next test step."""
    while external_call["g_main_context_pending", c_int](0) != 0:
        _ = external_call["g_main_context_iteration", c_int](0, c_int(0))

def on_clicked[A: App](button: Int, host_addr: Int) abi("C"):
    if busy():
        return
    host_at[A](host_addr)[].send(get_node(button), False, "", 0, host_addr)


def on_field_changed[A: App](entry: Int, host_addr: Int) abi("C"):
    if busy():
        return
    var text = c_str(external_call["gtk_editable_get_text", Int](entry))
    host_at[A](host_addr)[].send(get_node(entry), False, text, 0, host_addr)


def on_field_submit[A: App](entry: Int, host_addr: Int) abi("C"):
    if busy():
        return
    var text = c_str(external_call["gtk_editable_get_text", Int](entry))
    host_at[A](host_addr)[].send(get_node(entry), True, text, 0, host_addr)


def on_toggled[A: App](check: Int, host_addr: Int) abi("C"):
    if busy():
        return
    var on = Int(external_call["gtk_check_button_get_active", c_int](check))
    host_at[A](host_addr)[].send(get_node(check), False, "", on, host_addr)


def on_selected[A: App](dropdown: Int, pspec: Int, host_addr: Int) abi("C"):
    if busy():
        return
    var index = Int(external_call["gtk_drop_down_get_selected", c_uint](dropdown))
    var host = host_at[A](host_addr)
    var node = get_node(dropdown)
    var text = String("")
    if index < len(host[].rt.shown.nodes[node].options):
        text = host[].rt.shown.nodes[node].options[index]
    host[].send(node, False, text, index, host_addr)


def on_toggle_group[A: App](group: Int, pspec: Int, host_addr: Int) abi("C"):
    if busy():
        return
    var host = host_at[A](host_addr)
    var node = get_node(group)
    var index = Int(external_call["adw_toggle_group_get_active", c_uint](group))
    ref opts = host[].rt.shown.nodes[node].options
    if index < 0 or index >= len(opts):
        return
    host[].send(node, False, opts[index], index, host_addr)


def on_radio[A: App](button: Int, host_addr: Int) abi("C"):
    if busy() or external_call["gtk_check_button_get_active", c_int](button) == 0:
        return  # (the button being switched off also fires)
    var host = host_at[A](host_addr)
    var node = get_node(button)
    var index = get_index(button)
    host[].send(node, False, host[].rt.shown.nodes[node].options[index], index, host_addr)


def on_text_changed[A: App](buffer: Int, host_addr: Int) abi("C"):
    if busy():
        return
    host_at[A](host_addr)[].send(get_node(buffer), False, buffer_text(buffer), 0, host_addr)


def on_alert_response[A: App](dialog: Int, response: Int, host_addr: Int) abi("C"):
    if busy():
        return
    var host = host_at[A](host_addr)
    var node = get_node(dialog)
    var index = 0
    try:
        index = Int(c_str(response))
    except:
        return
    host[].send(node, False, host[].rt.shown.nodes[node].options[index], index, host_addr)


def on_day_selected[A: App](cal: Int, host_addr: Int) abi("C"):
    if busy():
        return
    host_at[A](host_addr)[].send(get_node(cal), False, calendar_date(cal), 0, host_addr)


def on_row_setup[A: App](factory: Int, item: Int, host_addr: Int) abi("C"):
    var empty = String("")
    var label = external_call["gtk_label_new", Int](empty.as_c_string_span())
    external_call["gtk_label_set_xalign", NoneType](label, Float32(0))
    external_call["gtk_widget_set_margin_start", NoneType](label, c_int(12))
    external_call["gtk_widget_set_margin_top", NoneType](label, c_int(10))
    external_call["gtk_widget_set_margin_bottom", NoneType](label, c_int(10))
    external_call["gtk_list_item_set_child", NoneType](item, label)
    count_up("mojoui-rows-built")  # a row widget was made (GTK reuses them while scrolling)


def on_row_bind[A: App](factory: Int, item: Int, host_addr: Int) abi("C"):
    var host = host_at[A](host_addr)
    var node = get_node(factory)
    if node < 0 or node >= len(host[].rt.shown.nodes):
        return
    var position = Int(external_call["gtk_list_item_get_position", c_uint](item))
    var text = host[].rt.app.row(host[].rt.shown.nodes[node].msg2, position)  # asked for on demand
    var label = external_call["gtk_list_item_get_child", Int](item)
    external_call["gtk_label_set_text", NoneType](label, text.as_c_string_span())


def on_row_activate[A: App](list: Int, position: Int, host_addr: Int) abi("C"):
    if busy():
        return
    # `position` is a C guint: only the low 32 bits of the register are defined.
    host_at[A](host_addr)[].send(get_node(list), False, "", position & 0xFFFFFFFF, host_addr)


def on_slid[A: App](scale: Int, host_addr: Int) abi("C"):
    if busy():
        return
    var value = Int(external_call["gtk_range_get_value", Float64](scale) + 0.5)
    host_at[A](host_addr)[].send(get_node(scale), False, "", value, host_addr)


# ---------- test mode ----------

def find(host: GtkHost, kind: Int, label: String, nth: Int, by_hint: Bool = False) -> Int:
    """The nth node of `kind` whose text (or hint) is `label` ("" = any)."""
    var seen = 0
    for i in range(len(host.rt.shown.nodes)):
        ref n = host.rt.shown.nodes[i]
        var name = n.hint if by_hint else n.text
        if n.kind == kind and (label == "" or name == label):
            if seen == nth:
                return i
            seen += 1
    return -1


def split_at(s: String, sep: String) -> Tuple[String, String]:
    var i = s.find(sep)
    if i < 0:
        return (s, String(""))
    return (String(s[byte=:i]), String(s[byte = i + sep.byte_length() :]))


def to_int(s: String) -> Int:
    try:
        return Int(s)
    except:
        return 0


def run_step[A: App](host_addr: Int, step: String):
    var host = host_at[A](host_addr)
    var verb_rest = split_at(step, ":")
    var verb = verb_rest[0]
    var rest = verb_rest[1]
    if verb == "tap":
        var t = split_at(rest, "@")
        var i = find(host[], BUTTON, t[0], to_int(t[1]))
        if i < 0:
            print("TEST: no button", rest)
            return
        var s = String("clicked")
        external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].widgets[i], s.as_c_string_span())
    elif verb == "type" or verb == "submit" or verb == "enter":
        var kv = split_at(rest, "=")
        var i = find(host[], FIELD, kv[0], 0, by_hint=True)
        if i < 0:
            print("TEST: no field", kv[0])
            return
        if verb == "type" or verb == "enter":
            var t = kv[1]
            external_call["gtk_editable_set_text", NoneType](host[].widgets[i], t.as_c_string_span())
        if verb == "submit" or verb == "enter":  # "enter": Return straight after typing
            var s = String("activate")
            external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].widgets[i], s.as_c_string_span())
    elif verb == "toggle":
        var i = find(host[], TOGGLE, rest, 0)
        if i < 0:
            print("TEST: no toggle", rest)
            return
        var w = host[].widgets[i]
        var on = external_call["gtk_check_button_get_active", c_int](w)
        external_call["gtk_check_button_set_active", NoneType](w, c_int(1) - on)
    elif verb == "select":
        var kv = split_at(rest, "=")
        var i = find(host[], DROPDOWN, "", to_int(kv[0]))
        if i < 0:
            print("TEST: no dropdown", kv[0])
            return
        var index = -1
        ref opts = host[].rt.shown.nodes[i].options
        for j in range(len(opts)):
            if opts[j] == kv[1]:
                index = j
        if index < 0:
            print("TEST: no option", kv[1])
            return
        external_call["gtk_drop_down_set_selected", NoneType](host[].widgets[i], c_uint(index))
    elif verb == "slide":
        var kv = split_at(rest, "=")
        var i = find(host[], SLIDER, "", to_int(kv[0]))
        if i < 0:
            print("TEST: no slider", kv[0])
            return
        external_call["gtk_range_set_value", NoneType](host[].widgets[i], Float64(to_int(kv[1])))
    elif verb == "segment" or verb == "tab" or verb == "radio":
        var kv = split_at(rest, "=")
        var kind = SEGMENTED if verb == "segment" else (TABS if verb == "tab" else RADIO)
        var i = find(host[], kind, "", to_int(kv[0]))
        if i < 0:
            print("TEST: no", verb, kv[0])
            return
        var index = -1
        ref opts = host[].rt.shown.nodes[i].options
        for j in range(len(opts)):
            if opts[j] == kv[1]:
                index = j
        if index < 0:
            print("TEST: no option", kv[1])
            return
        if kind == RADIO:
            var b = external_call["gtk_widget_get_first_child", Int](host[].widgets[i])
            for _ in range(index):
                b = external_call["gtk_widget_get_next_sibling", Int](b)
            external_call["gtk_check_button_set_active", NoneType](b, c_int(1))
        else:
            external_call["adw_toggle_group_set_active", NoneType](host[].widgets[i], c_uint(index))
    elif verb == "textarea":
        var kv = split_at(rest, "=")
        var i = find(host[], TEXTAREA, "", to_int(kv[0]))
        if i < 0:
            print("TEST: no textarea", kv[0])
            return
        var t = kv[1].replace("\\n", "\n")
        var buffer = external_call["gtk_text_view_get_buffer", Int](host[].widgets[i])
        external_call["gtk_text_buffer_set_text", NoneType](buffer, t.as_c_string_span(), c_int(-1))
    elif verb == "alert":
        var i = find(host[], ALERT, "", 0)
        if i < 0:
            print("TEST: no alert")
            return
        var index = -1
        ref opts = host[].rt.shown.nodes[i].options
        for j in range(len(opts)):
            if opts[j] == rest:
                index = j
        if index < 0:
            print("TEST: no alert button", rest)
            return
        var signal = String("response")
        var id = String(index)
        external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].widgets[i], signal.as_c_string_span(), id.as_c_string_span())
    elif verb == "back":
        var i = find(host[], NAVBAR, "", 0)
        if i < 0:
            print("TEST: no navbar")
            return
        var back = external_call["gtk_widget_get_first_child", Int](host[].widgets[i])
        var s = String("clicked")
        external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](back, s.as_c_string_span())
    elif verb == "date":
        var kv = split_at(rest, "=")
        var i = find(host[], DATE, "", to_int(kv[0]))
        if i < 0:
            print("TEST: no date picker", kv[0])
            return
        calendar_select(host[].widgets[i], kv[1])
        if calendar_date(host[].widgets[i]) == kv[1] and host[].rt.shown.nodes[i].text != kv[1]:
            var s = String("day-selected")  # make sure the selection is reported like a click
            external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].widgets[i], s.as_c_string_span())
    elif verb == "scroll" or verb == "row":
        var kv = split_at(rest, "=")
        var i = find(host[], LAZYLIST, "", to_int(kv[0]))
        if i < 0:
            print("TEST: no list", kv[0])
            return
        var position = to_int(kv[1])
        if verb == "scroll":
            external_call["gtk_list_view_scroll_to", NoneType](host[].widgets[i], c_uint(position), c_int(0), 0)
        else:
            var s = String("activate")
            external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].widgets[i], s.as_c_string_span(), c_uint(position))
    else:
        print("TEST: unknown step", step)


def report[A: App](host_addr: Int):
    """Prints every widget's state as GTK reports it, in screen order."""
    var host = host_at[A](host_addr)
    print("NATIVE: GTK " + String(external_call["gtk_get_major_version", c_int]()) + "." + String(external_call["gtk_get_minor_version", c_int]()))
    for i in range(len(host[].rt.shown.nodes)):
        ref n = host[].rt.shown.nodes[i]
        var w = host[].widgets[i]
        if n.kind == TEXT:
            print("LABEL: " + c_str(external_call["gtk_label_get_text", Int](w)))
        elif n.kind == BUTTON:
            print("BUTTON: " + c_str(external_call["gtk_button_get_label", Int](w)))
        elif n.kind == FIELD:
            print("FIELD: " + c_str(external_call["gtk_editable_get_text", Int](w)))
        elif n.kind == TOGGLE:
            var on = external_call["gtk_check_button_get_active", c_int](w) != 0
            print("TOGGLE: " + c_str(external_call["gtk_check_button_get_label", Int](w)) + ("=on" if on else "=off"))
        elif n.kind == DROPDOWN:
            var model = external_call["gtk_drop_down_get_model", Int](w)
            var sel = external_call["gtk_drop_down_get_selected", c_uint](w)
            print("DROPDOWN: " + c_str(external_call["gtk_string_list_get_string", Int](model, sel)))
        elif n.kind == SLIDER:
            print("SLIDER: " + String(Int(external_call["gtk_range_get_value", Float64](w) + 0.5)))
        elif n.kind == PROGRESS:
            print("PROGRESS: " + String(Int(external_call["gtk_progress_bar_get_fraction", Float64](w) * 100.0 + 0.5)))
        elif n.kind == SEGMENTED or n.kind == TABS:
            var index = external_call["adw_toggle_group_get_active", c_uint](w)
            var t = external_call["adw_toggle_group_get_toggle", Int](w, index)
            print(("SEGMENTED: " if n.kind == SEGMENTED else "TABS: ") + c_str(external_call["adw_toggle_get_label", Int](t)))
        elif n.kind == RADIO:
            var b = external_call["gtk_widget_get_first_child", Int](w)
            while b != 0:
                if external_call["gtk_check_button_get_active", c_int](b) != 0:
                    print("RADIO: " + c_str(external_call["gtk_check_button_get_label", Int](b)))
                b = external_call["gtk_widget_get_next_sibling", Int](b)
        elif n.kind == TEXTAREA:
            print("TEXTAREA: " + escape_newlines(buffer_text(external_call["gtk_text_view_get_buffer", Int](w))))
        elif n.kind == ALERT:
            var line = c_str(external_call["adw_alert_dialog_get_heading", Int](w)) + " | " + c_str(external_call["adw_alert_dialog_get_body", Int](w)) + " | "
            for j in range(len(n.options)):
                var id = String(j)
                line += (", " if j > 0 else "") + c_str(external_call["adw_alert_dialog_get_response_label", Int](w, id.as_c_string_span()))
            print("ALERT: " + line)
        elif n.kind == NAVBAR:
            var title = external_call["gtk_widget_get_last_child", Int](w)
            var has_back = external_call["gtk_widget_get_first_child", Int](w) != title
            print("NAV: " + c_str(external_call["gtk_label_get_text", Int](title)) + (" (back)" if has_back else ""))
        elif n.kind == DATE:
            print("DATE: " + calendar_date(w))
        elif n.kind == ICON:
            print("ICON: " + mojo_icon(c_str(external_call["gtk_image_get_icon_name", Int](w))))
        elif n.kind == GRID:
            var count = 0
            var c = external_call["gtk_widget_get_first_child", Int](w)
            while c != 0:
                count += 1
                c = external_call["gtk_widget_get_next_sibling", Int](c)
            print("GRID: " + String(n.value) + " columns, " + String(count) + " items")
        elif n.kind == LAZYLIST:
            var selection = external_call["gtk_list_view_get_model", Int](w)
            print("LIST: " + String(external_call["g_list_model_get_n_items", c_uint](selection)) + " rows")
            print("LISTBUILT: " + String(counter("mojoui-rows-built")))
        elif n.kind == IMAGE:
            var paintable = external_call["gtk_picture_get_paintable", Int](w)
            print("IMAGE: " + String(external_call["gdk_texture_get_width", c_int](paintable)) + "x" + String(external_call["gdk_texture_get_height", c_int](paintable)))


def save_png(window: Int, path: String):
    """Asks GTK to render the window (as drawn on screen) into a PNG file."""
    for _ in range(500):  # wait until the window is on screen
        if external_call["gtk_widget_get_mapped", c_int](window) != 0:
            break
        _ = external_call["g_main_context_iteration", c_int](0, c_int(1))
    for _ in range(60):  # let layout and drawing settle (~300 ms of frames)
        settle()
        external_call["g_usleep", NoneType](c_uint(5000))
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
    external_call["gtk_window_set_default_size", NoneType](host[].window, c_int(480), c_int(560))
    host[].show(host_addr)
    var steps = getenv("MOJOUI_TEST")
    var shot = getenv("MOJOUI_SHOT")
    if steps == "" or shot != "":
        external_call["gtk_window_present", NoneType](host[].window)
    if steps != "":
        for step in steps.split(";"):
            run_step[A](host_addr, String(step))
            settle()
        report[A](host_addr)
    if shot != "":
        save_png(host[].window, shot)
    if steps != "" or shot != "":
        external_call["g_application_quit", NoneType](gapp)


def run[A: App]() -> Int:
    """Opens the app in a native GTK window and runs until it's closed."""
    var host = alloc(Layout[GtkHost[A]].single()).unsafe_leak()  # lives as long as the app
    host.unsafe_write(GtkHost[A](A()))
    var id = String("dev.mojoui.App")
    var gapp = external_call["adw_application_new", Int](id.as_c_string_span(), c_int(G_APPLICATION_NON_UNIQUE))
    connect(gapp, "activate", on_activate[A], Int(host))
    return Int(external_call["g_application_run", c_int](gapp, c_int(0), 0))
