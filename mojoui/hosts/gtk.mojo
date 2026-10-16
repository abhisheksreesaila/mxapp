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
    SEGMENTED, RADIO, TEXTAREA, ALERT, TABS, NAVBAR, DATE, ICON, GRID, LAZYLIST, CANVAS, BOARD, PAN, ZOOM, TAP,
    START, CENTER, END, STRETCH, BETWEEN, AUTO, Node, CARD, CARD_WARN, CARD_GOOD, FLUENT, OMARCHY,
    TITLE, HEADLINE, CAPTION, PROMINENT, DESTRUCTIVE, OVERLAY, PRESS, RELEASE, DOUBLE, SUBTLE, ICON_ONLY,
)
from mojoui.diff import Diff, SET_TEXT, SET_VALUE, SET_IMAGE, SET_PLACE
from mojoui.app import App, Event, Runtime
from mojoui.canvas import Surface
from mojoui.icons_data import LUCIDE_NAMES, lucide_svg
from mojoui.theme import Palette, hex_of, mix
from std.math import log2
from std.time import perf_counter_ns

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


def is_set(name: String) -> Bool:
    """Whether an environment variable is set at all (even to "")."""
    var n = name
    return external_call["getenv", Int](n.as_c_string_span()) != 0


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


def connect_any[F: AnyType](obj: Int, signal: String, callback: F, data: Int):
    """g_signal_connect for a callback of any C signature (doubles, return values…)."""
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
    """A control's default width (a GTK minimum). build() skips it when the app sizes the view."""
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
    for n in materialize[LUCIDE_NAMES]():
        if n == name:
            return "mojoui-" + name  # the same Lucide SVG as the web (written by install_icons)
    return "image-missing-symbolic"


def install_icons(themed: Bool = False):
    """Writes the Lucide icons as SVG files (Fluent's neutral foreground, and white for filled
    buttons) to a cache folder and adds it to the display's icon theme: icons named
    "mojoui-<name>" and "mojoui-<name>-light"."""
    var base = c_str(external_call["g_get_user_cache_dir", Int]()) + ("/mojoui/icons-omarchy" if themed else "/mojoui/icons-1")
    _ = external_call["g_mkdir_with_parents", c_int](base.as_c_string_span(), c_int(0o755))
    var pal = Palette.omarchy()
    var ink = hex_of(pal.ink2) if themed else String("#424242")
    var on_accent = hex_of(pal.accent_ink) if themed else String("#ffffff")
    for n in materialize[LUCIDE_NAMES]():
        var svg = lucide_svg(n)
        for variant in [("", ink), ("-light", on_accent)]:
            var path = base + "/mojoui-" + n + variant[0] + ".svg"
            try:
                with open(path, "w") as f:
                    f.write(svg.replace("currentColor", variant[1]))
            except:
                pass
    var display = external_call["gdk_display_get_default", Int]()
    var theme = external_call["gtk_icon_theme_get_for_display", Int](display)
    external_call["gtk_icon_theme_add_search_path", NoneType](theme, base.as_c_string_span())


def mojo_icon(gtk_name: String) -> String:
    if gtk_name.startswith("mojoui-"):
        return String(gtk_name[byte=7:])
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


def one_decimal(v: Float32) -> String:
    var tenths = Int(Float64(v) * 10 + (0.5 if v >= 0 else -0.5))
    var sign = "-" if tenths < 0 else ""
    tenths = abs(tenths)
    return sign + String(tenths // 10) + "." + String(tenths % 10)


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


def fresh_rows(list: Int, count: Int):
    """Gives a GtkListView a new model of `count` placeholder items, so every visible
    row is bound again (asking the app for its text); the scroll position is kept."""
    var model = external_call["gtk_string_list_new", Int](0)
    var empty = String("")
    for _ in range(count):
        external_call["gtk_string_list_append", NoneType](model, empty.as_c_string_span())
    var selection = external_call["gtk_list_view_get_model", Int](list)
    external_call["gtk_no_selection_set_model", NoneType](selection, model)
    external_call["g_object_unref", NoneType](model)


def refresh_rows(list: Int, count: Int):
    """Re-binds the rows on screen: fresh items over the range of rows GTK drew since the
    last refresh (cheap; keeps the scroll position and row widgets), or a new model if the
    row count changed."""
    var selection = external_call["gtk_list_view_get_model", Int](list)
    var model = external_call["gtk_no_selection_get_model", Int](selection)
    if Int(external_call["g_list_model_get_n_items", c_uint](model)) != count:
        fresh_rows(list, count)
        return
    var app = external_call["g_application_get_default", Int]()
    var lo = String("mojoui-bound-lo")
    var hi = String("mojoui-bound-hi")
    var first = external_call["g_object_get_data", Int](app, lo.as_c_string_span()) - 1
    var last = external_call["g_object_get_data", Int](app, hi.as_c_string_span()) - 1
    external_call["g_object_set_data", NoneType](app, lo.as_c_string_span(), 0)  # start tracking afresh:
    external_call["g_object_set_data", NoneType](app, hi.as_c_string_span(), 0)  # the splice re-binds what's shown
    var n = min(last + 1, count) - max(first, 0)
    if first < 0 or n <= 0:
        return
    first = max(first, 0)
    var empty = String("")
    var additions = List[Int](length=n + 1, fill=Int(empty.unsafe_ptr()))  # n pointers to "" + NULL
    additions[n] = 0
    _ = empty.as_c_string_span()  # make sure "" is NUL-terminated
    external_call["gtk_string_list_splice", NoneType](model, c_uint(first), c_uint(n), Int(additions.unsafe_ptr()))
    _ = len(additions)  # keep the pointer array alive past the call
    _ = empty.byte_length()


def spacer(orientation: Int) -> Int:
    """An empty widget that soaks up free space (for justify)."""
    var s = external_call["gtk_box_new", Int](c_int(orientation), c_int(0))
    if orientation == HORIZONTAL:
        external_call["gtk_widget_set_hexpand", NoneType](s, c_int(1))
    else:
        external_call["gtk_widget_set_vexpand", NoneType](s, c_int(1))
    return s


def escape_newlines(text: String) -> String:
    return text.replace("\n", "\\n")


# ---------- the host ----------

struct GtkCanvas(Copyable, Movable):
    """One Canvas on screen: its GtkPicture, gesture controllers and the pixels last drawn."""

    var node: Int
    var widget: Int  # GtkPicture showing the pixels as a texture
    var drag: Int  # GtkGestureDrag
    var scroll: Int  # GtkEventControllerScroll
    var click: Int  # GtkGestureClick
    var pixels: List[UInt32]
    var wpx: Int
    var hpx: Int
    var scale: Float64
    var drawn: Int  # the version last drawn (-1: none yet)
    var draws: Int
    var frames: Int  # frame events sent
    var first_us: Int  # frame-clock time of the first and last frame event (for FRAMES)
    var last_us: Int
    var drag_x: Float64  # the drag's offset so far
    var drag_y: Float64
    var start_x: Float64  # where the drag started (canvas points)
    var start_y: Float64
    var ptr_x: Float64  # where the pointer is (-1: unknown)
    var ptr_y: Float64
    var pinch: Float64  # the pinch's scale so far
    var moved: Bool  # the current press became a drag (so it's not a tap)
    var armed: Bool  # a tick callback is running (only while frames, a redraw or a resize may be due)
    var quiet: Int  # idle ticks in a row (layout can change after ticks, so wait before stopping)

    def __init__(out self, node: Int, widget: Int):
        self.node = node
        self.widget = widget
        self.drag = 0
        self.scroll = 0
        self.click = 0
        self.pixels = List[UInt32]()
        self.wpx = 0
        self.hpx = 0
        self.scale = 1
        self.drawn = -1
        self.draws = 0
        self.frames = 0
        self.first_us = 0
        self.last_us = 0
        self.drag_x = 0
        self.drag_y = 0
        self.start_x = 0
        self.start_y = 0
        self.ptr_x = -1
        self.ptr_y = -1
        self.pinch = 1
        self.moved = False
        self.armed = False
        self.quiet = 0


struct BoardChild(Copyable, Movable):
    """One object on a Board: dragged by its header (move) or its bottom-right corner (resize)."""

    var board: Int  # the Board node
    var node: Int  # the child node
    var index: Int  # its index among the board's children
    var widget: Int
    var fixed: Int  # the GtkFixed holding it
    var drag: Int  # GtkGestureDrag
    var active: Bool
    var resizing: Bool

    def __init__(out self, board: Int, node: Int, index: Int, widget: Int, fixed: Int, drag: Int):
        self.board = board
        self.node = node
        self.index = index
        self.widget = widget
        self.fixed = fixed
        self.drag = drag
        self.active = False
        self.resizing = False


struct GtkHost[A: App](Movable):
    var rt: Runtime[Self.A]
    var canvases: List[GtkCanvas]
    var boards: List[BoardChild]
    var window_w: Int  # the window's width in points (boards narrower than 720 become lists)
    var board_list: Bool  # the last build showed boards as lists
    var board_scrollers: List[Tuple[Int, Int]]  # (Board node, its GtkScrolledWindow)
    var revealed: Int  # the last Board reveal token scrolled to (Board's value)
    var reveal_pending: Int  # a Board node waiting for its layout to scroll a child into view, or -1
    var window: Int
    var widgets: List[Int]  # the GTK widget drawn for each node of rt.shown
    var dialog: Int  # the open alert dialog, if any
    var css: Int  # one GtkCssProvider for padding classes
    var css_rules: String
    var focus: Int  # text field to keep focused across the next rebuild (-1: none)

    def __init__(out self, var app: Self.A):
        self.rt = Runtime(app^)
        self.canvases = List[GtkCanvas]()
        self.boards = List[BoardChild]()
        self.window_w = 0
        self.board_list = False
        self.board_scrollers = List[Tuple[Int, Int]]()
        self.revealed = 0
        self.reveal_pending = -1
        self.window = 0
        self.widgets = List[Int]()
        self.dialog = 0
        self.css = 0
        self.css_rules = ""
        self.focus = -1

    def padding_class(mut self, v: Int, h: Int) -> String:
        """A CSS class giving `v`/`h` padding (GTK has no padding setter; CSS does it)."""
        var name = "mui-p-" + String(v) + "-" + String(h)
        if ("." + name + " ") not in self.css_rules:
            if self.css == 0:
                self.css = external_call["gtk_css_provider_new", Int]()
                var display = external_call["gdk_display_get_default", Int]()
                external_call["gtk_style_context_add_provider_for_display", NoneType](display, self.css, c_uint(800))
            self.css_rules += "." + name + " { padding: " + String(v) + "px " + String(h) + "px; }\n"
            var rules = self.css_rules
            external_call["gtk_css_provider_load_from_string", NoneType](self.css, rules.as_c_string_span())
        return name

    def apply_layout(mut self, i: Int, w: Int) -> Int:
        """Maps node i's own layout settings onto its GTK widget; returns what goes into the parent."""
        var node = self.rt.shown.nodes[i].copy()
        if node.pad_v != 0 or node.pad_h != 0:
            add_class(w, self.padding_class(node.pad_v, node.pad_h))
        var want_w = max(node.w, node.min_w)
        if want_w != 0 or node.h != 0:
            external_call["gtk_widget_set_size_request", NoneType](w, c_int(want_w if want_w != 0 else -1), c_int(node.h if node.h != 0 else -1))
        # GTK size requests are minimums; AdwClamp caps the width: at max_w, or exactly at a
        # fixed width (so a fixed-width view never grows past it, as on the other hosts).
        if node.w != 0:  # a fixed width never takes spare room (GTK passes children's expand up)
            external_call["gtk_widget_set_hexpand", NoneType](w, c_int(0))
        if node.h != 0:
            external_call["gtk_widget_set_vexpand", NoneType](w, c_int(0))
        var cap = node.max_w if node.max_w != 0 else node.w
        if cap != 0:
            var clamp = external_call["adw_clamp_new", Int]()
            external_call["adw_clamp_set_maximum_size", NoneType](clamp, c_int(cap))
            external_call["adw_clamp_set_tightening_threshold", NoneType](clamp, c_int(cap))
            external_call["adw_clamp_set_child", NoneType](clamp, w)
            return clamp
        return w

    def place_child(self, parent: Node, child_node: Node, child: Int):
        """Aligns a stack's child: the stack's align, then the child's own fill/grow."""
        var vertical = parent.kind == VSTACK
        var cross = ALIGN_CENTER
        if parent.align_items == START:
            cross = 1  # GTK_ALIGN_START
        elif parent.align_items == END:
            cross = 2  # GTK_ALIGN_END
        if parent.align_items == STRETCH or child_node.fills or child_node.kind == SPACER:
            cross = 0  # GTK_ALIGN_FILL
        if vertical:
            external_call["gtk_widget_set_halign", NoneType](child, c_int(cross))
            if child_node.grows:
                external_call["gtk_widget_set_vexpand", NoneType](child, c_int(1))
                external_call["gtk_widget_set_valign", NoneType](child, c_int(0))
        else:
            external_call["gtk_widget_set_valign", NoneType](child, c_int(cross))
            if child_node.grows:
                external_call["gtk_widget_set_hexpand", NoneType](child, c_int(1))
                external_call["gtk_widget_set_halign", NoneType](child, c_int(0))

    def build(mut self, i: Int, self_addr: Int) -> Int:
        """Creates the GTK widget for node i (and its children)."""
        var node = self.rt.shown.nodes[i].copy()  # copy: building children mutates self
        # A control's built-in width yields when the app sizes it (fill, grow or width).
        var sized = node.sized_width()
        var w: Int
        if node.kind == TEXT:
            var t = node.text
            w = external_call["gtk_label_new", Int](t.as_c_string_span())
            external_call["gtk_label_set_wrap", NoneType](w, c_int(1))
            external_call["gtk_label_set_natural_wrap_mode", NoneType](w, c_int(1))  # prefer one line; wrap only when squeezed
            external_call["gtk_label_set_justify", NoneType](w, c_int(2))  # centre
            if node.style == TITLE:
                add_class(w, "title-1")
            elif node.style == HEADLINE:
                add_class(w, "title-4")
            elif node.style == CAPTION:
                add_class(w, "caption")
                add_class(w, "dim-label")
            if node.value == 1:
                add_class(w, "mui-tone-warn")
            elif node.value == 2:
                add_class(w, "mui-tone-good")
            elif node.value == 3:
                add_class(w, "mui-tone-strong")
            elif node.value == 4:
                add_class(w, "mui-tone-accent")
        elif node.kind == BUTTON:
            var t = node.text
            if node.hint != "" and node.style == ICON_ONLY:  # just the icon; the title is the tooltip
                var icon = gtk_icon(node.hint)
                w = external_call["gtk_button_new_from_icon_name", Int](icon.as_c_string_span())
                external_call["gtk_widget_set_tooltip_text", NoneType](w, t.as_c_string_span())
            elif node.hint != "":  # icon + title
                w = external_call["gtk_button_new", Int]()
                var content = external_call["adw_button_content_new", Int]()
                var icon = gtk_icon(node.hint) + ("-light" if node.style == PROMINENT and node.hint != "" else "")
                external_call["adw_button_content_set_icon_name", NoneType](content, icon.as_c_string_span())
                external_call["adw_button_content_set_label", NoneType](content, t.as_c_string_span())
                external_call["gtk_button_set_child", NoneType](w, content)
            else:
                w = external_call["gtk_button_new_with_label", Int](t.as_c_string_span())
            if node.style == PROMINENT:
                add_class(w, "suggested-action")
                if node.hint == "":
                    add_class(w, "pill")
            elif node.style == DESTRUCTIVE:
                add_class(w, "destructive-action")
            elif node.style == SUBTLE or node.style == ICON_ONLY:
                add_class(w, "flat")
            connect(w, "clicked", on_clicked[Self.A], self_addr)
        elif node.kind == FIELD:
            w = external_call["gtk_entry_new", Int]()
            if node.value == 1:
                add_class(w, "mui-cell-editor")
            var t = node.text
            var h = node.hint
            external_call["gtk_editable_set_text", NoneType](w, t.as_c_string_span())
            external_call["gtk_entry_set_placeholder_text", NoneType](w, h.as_c_string_span())
            if not sized:
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
            if not sized:
                width(w, 240)
            connect(w, "value-changed", on_slid[Self.A], self_addr)
        elif node.kind == PROGRESS:
            w = external_call["gtk_progress_bar_new", Int]()
            external_call["gtk_progress_bar_set_fraction", NoneType](w, Float64(node.value) / 100.0)
            if not sized:
                width(w, 240)
        elif node.kind == DIVIDER:
            w = external_call["gtk_separator_new", Int](c_int(HORIZONTAL))
            if not sized:
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
        elif node.kind == CANVAS:
            w = external_call["gtk_picture_new", Int]()
            external_call["gtk_picture_set_can_shrink", NoneType](w, c_int(1))  # its size comes from the layout
            external_call["gtk_picture_set_content_fit", NoneType](w, c_int(0))  # fill: the pixels match its size
            external_call["gtk_widget_set_size_request", NoneType](w, c_int(-1 if sized else 320), c_int(-1 if node.sized_height() else 240))
            var ci = len(self.canvases)
            var c = GtkCanvas(i, w)
            set_index(w, ci)
            var drag = external_call["gtk_gesture_drag_new", Int]()
            set_index(drag, ci)
            connect_any(drag, "drag-begin", on_drag_begin[Self.A], self_addr)
            connect_any(drag, "drag-update", on_drag_update[Self.A], self_addr)
            connect_any(drag, "drag-end", on_drag_end[Self.A], self_addr)
            external_call["gtk_widget_add_controller", NoneType](w, drag)
            var scroll = external_call["gtk_event_controller_scroll_new", Int](c_int(1))  # vertical
            set_index(scroll, ci)
            connect_any(scroll, "scroll", on_scroll[Self.A], self_addr)
            external_call["gtk_widget_add_controller", NoneType](w, scroll)
            var motion = external_call["gtk_event_controller_motion_new", Int]()
            set_index(motion, ci)
            connect_any(motion, "motion", on_motion[Self.A], self_addr)
            external_call["gtk_widget_add_controller", NoneType](w, motion)
            var pinch = external_call["gtk_gesture_zoom_new", Int]()
            set_index(pinch, ci)
            connect3(pinch, "begin", on_pinch_begin[Self.A], self_addr)
            connect_any(pinch, "scale-changed", on_pinch[Self.A], self_addr)
            external_call["gtk_widget_add_controller", NoneType](w, pinch)
            var click = external_call["gtk_gesture_click_new", Int]()
            set_index(click, ci)
            connect_any(click, "released", on_click_released[Self.A], self_addr)
            external_call["gtk_widget_add_controller", NoneType](w, click)
            c.drag = drag
            c.scroll = scroll
            c.click = click
            self.canvases.append(c^)
            self.arm(ci, self_addr)
            # A picture asks for its texture's size in pixels, which would grow the canvas each
            # redraw on a scaled screen: a scrolled window that never scrolls takes no size from it.
            self.widgets[i] = w
            var holder = external_call["gtk_scrolled_window_new", Int]()
            external_call["gtk_scrolled_window_set_policy", NoneType](holder, c_int(3), c_int(3))  # GTK_POLICY_EXTERNAL
            external_call["gtk_scrolled_window_set_child", NoneType](holder, w)
            external_call["gtk_widget_set_size_request", NoneType](holder, c_int(-1 if sized else 320), c_int(-1 if node.sized_height() else 240))
            external_call["gtk_widget_set_size_request", NoneType](w, c_int(-1), c_int(-1))
            w = holder
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
            external_call["gtk_widget_set_size_request", NoneType](w, c_int(-1 if sized else 320), c_int(node.size))
        elif node.kind == ALERT:
            var heading = node.text
            var body = node.hint
            w = external_call["adw_alert_dialog_new", Int](heading.as_c_string_span(), body.as_c_string_span())
            for j in range(len(node.options)):
                var id = String(j)
                var label = node.options[j]
                external_call["adw_alert_dialog_add_response", NoneType](w, id.as_c_string_span(), label.as_c_string_span())
            var cancel = String("0")  # Escape answers with the first button (Cancel), as on Apple platforms
            external_call["adw_alert_dialog_set_close_response", NoneType](w, cancel.as_c_string_span())
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
                var tip = String("Back")
                external_call["gtk_widget_set_tooltip_text", NoneType](back, tip.as_c_string_span())  # also its accessible name
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
            connect3(factory, "unbind", on_row_unbind, self_addr)
            var list = external_call["gtk_list_view_new", Int](selection, factory)
            external_call["gtk_list_view_set_single_click_activate", NoneType](list, c_int(1))
            add_class(list, "boxed-list")
            set_node(list, i)
            connect3(list, "activate", on_row_activate[Self.A], self_addr)
            self.widgets[i] = list
            w = external_call["gtk_scrolled_window_new", Int]()
            external_call["gtk_scrolled_window_set_child", NoneType](w, list)
            external_call["gtk_scrolled_window_set_policy", NoneType](w, c_int(2), c_int(1))
            external_call["gtk_widget_set_size_request", NoneType](w, c_int(-1 if sized else 340), c_int(node.size))
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
        elif node.kind == OVERLAY:
            w = external_call["gtk_overlay_new", Int]()
            for k in range(len(node.children)):
                var c = node.children[k]
                var child = self.build(c, self_addr)
                if k == 0:
                    external_call["gtk_widget_set_hexpand", NoneType](child, c_int(1))
                    external_call["gtk_widget_set_vexpand", NoneType](child, c_int(1))
                    external_call["gtk_overlay_set_child", NoneType](w, child)
                else:  # an island: pinned to an edge, 12 pt in, its natural size
                    ref pin = self.rt.shown.nodes[c]
                    external_call["gtk_widget_set_halign", NoneType](child, c_int(1 if pin.x == START else (2 if pin.x == END else ALIGN_CENTER)))
                    external_call["gtk_widget_set_valign", NoneType](child, c_int(2 if pin.y == END else 1))
                    external_call["gtk_widget_set_margin_top", NoneType](child, c_int(12))
                    external_call["gtk_widget_set_margin_bottom", NoneType](child, c_int(12))
                    external_call["gtk_widget_set_margin_start", NoneType](child, c_int(12))
                    external_call["gtk_widget_set_margin_end", NoneType](child, c_int(12))
                    add_class(child, "mui-island")
                    external_call["gtk_overlay_add_overlay", NoneType](w, child)
        elif node.kind == BOARD:
            var inner: Int
            if self.window_w != 0 and self.window_w < 720:  # a phone-width window: the objects as a list
                self.board_list = True
                inner = external_call["gtk_box_new", Int](c_int(VERTICAL), c_int(16))
                for c in node.children:
                    if self.rt.shown.nodes[c].kind == FIELD and self.rt.shown.nodes[c].value == 1:
                        continue  # an in-place editor has no cell to sit over in the list
                    var child = self.build(c, self_addr)
                    external_call["gtk_widget_set_halign", NoneType](child, c_int(0))  # fill the width
                    external_call["gtk_widget_set_hexpand", NoneType](child, c_int(1))
                    external_call["gtk_box_append", NoneType](inner, child)
            else:
                inner = external_call["gtk_fixed_new", Int]()
                external_call["gtk_widget_set_size_request", NoneType](inner, c_int(node.spacing), c_int(node.size))
                external_call["gtk_widget_set_hexpand", NoneType](inner, c_int(1))  # at least the visible page (its dotted
                external_call["gtk_widget_set_vexpand", NoneType](inner, c_int(1))  # background); positions stay absolute
                # One drag gesture on the board itself (never on the object it moves: a gesture
                # measures from the widget it's attached to, so a moving widget would measure
                # against itself and jitter); drag-begin finds the object under the pointer.
                var drag = external_call["gtk_gesture_drag_new", Int]()
                set_index(drag, len(self.boards))  # its first child in self.boards
                connect_any(drag, "drag-begin", on_board_drag_begin[Self.A], self_addr)
                connect_any(drag, "drag-update", on_board_drag_update[Self.A], self_addr)
                connect_any(drag, "drag-end", on_board_drag_end[Self.A], self_addr)
                external_call["gtk_widget_add_controller", NoneType](inner, drag)
                for k in range(len(node.children)):
                    var c = node.children[k]
                    var child = self.build(c, self_addr)
                    external_call["gtk_fixed_put", NoneType](inner, child, Float64(self.rt.shown.nodes[c].x), Float64(self.rt.shown.nodes[c].y))
                    self.boards.append(BoardChild(i, c, k, child, inner, drag))
            # The page scrolls when it's bigger than the room it's given (both ways).
            w = external_call["gtk_scrolled_window_new", Int]()
            external_call["gtk_scrolled_window_set_policy", NoneType](w, c_int(1), c_int(1))  # automatic, automatic
            external_call["gtk_scrolled_window_set_child", NoneType](w, inner)
            add_class(inner, "mui-board")
            self.widgets[i] = inner  # patches move and size the board's own widget
            self.board_scrollers.append((i, w))
            if node.value != 0 and node.value != self.revealed:
                self.reveal_pending = i
        else:
            var orientation = VERTICAL if node.kind == VSTACK else HORIZONTAL
            w = external_call["gtk_box_new", Int](c_int(orientation), c_int(node.spacing))
            if node.kind == VSTACK and (node.style == CARD or node.style == CARD_WARN or node.style == CARD_GOOD):
                add_class(w, "card")  # libadwaita's own card look
                add_class(w, "mui-card")
                if node.style == CARD_WARN:
                    add_class(w, "mui-warn")
                elif node.style == CARD_GOOD:
                    add_class(w, "mui-good")
            if node.kind == HSTACK:
                external_call["gtk_widget_set_halign", NoneType](w, c_int(ALIGN_CENTER))
            # justify: GtkBox packs from the start; invisible expanding spacers do the rest.
            var j = node.justify_items
            for c in node.children:  # a growing child takes all the free space: no spacers
                if self.rt.shown.nodes[c].grows:
                    j = AUTO
            if j == CENTER or j == END:
                external_call["gtk_box_append", NoneType](w, spacer(orientation))
            for k in range(len(node.children)):
                var c = node.children[k]
                if j == BETWEEN and k > 0:
                    external_call["gtk_box_append", NoneType](w, spacer(orientation))
                var child = self.build(c, self_addr)
                self.place_child(node, self.rt.shown.nodes[c], child)
                if orientation == VERTICAL and self.rt.shown.nodes[c].kind == TEXT and node.align_items == START:
                    external_call["gtk_label_set_justify", NoneType](self.widgets[c], c_int(0))  # left-aligned lines too
                    external_call["gtk_label_set_xalign", NoneType](self.widgets[c], Float32(0))
                external_call["gtk_box_append", NoneType](w, child)
            if j == CENTER:
                external_call["gtk_box_append", NoneType](w, spacer(orientation))
        set_node(w, i)
        if self.widgets[i] == 0:  # (some branches already stored an inner control)
            self.widgets[i] = w
        return self.apply_layout(i, w)

    def show(mut self, self_addr: Int):
        """(Re)builds the window's content from rt.shown."""
        set_busy(True)
        if self.dialog != 0:  # the previous screen's alert goes with it
            _ = external_call["adw_dialog_force_close", c_int](self.dialog)
            external_call["g_object_unref", NoneType](self.dialog)
            self.dialog = 0
        self.widgets = List[Int](length=len(self.rt.shown.nodes), fill=0)
        self.canvases = List[GtkCanvas]()
        self.boards = List[BoardChild]()
        self.board_scrollers = List[Tuple[Int, Int]]()
        var root = self.build(0, self_addr)
        if self.rt.shown.nodes[0].grows or self.rt.shown.nodes[0].fills:  # the screen fills the window
            external_call["gtk_widget_set_valign", NoneType](root, c_int(0))
            external_call["gtk_widget_set_halign", NoneType](root, c_int(0))
        else:
            external_call["gtk_widget_set_valign", NoneType](root, c_int(ALIGN_CENTER))
            external_call["gtk_widget_set_margin_top", NoneType](root, c_int(32))
            external_call["gtk_widget_set_margin_bottom", NoneType](root, c_int(32))
            external_call["gtk_widget_set_margin_start", NoneType](root, c_int(32))
            external_call["gtk_widget_set_margin_end", NoneType](root, c_int(32))
        external_call["gtk_window_set_child", NoneType](self.window, root)
        if self.reveal_pending >= 0:
            _ = external_call["gtk_widget_add_tick_callback", c_uint](root, on_reveal_tick[Self.A], self_addr, 0)
        if self.dialog != 0 and (getenv("MOJOUI_TEST") == "" or getenv("MOJOUI_SHOT") != ""):  # plain tests drive it unseen
            external_call["adw_dialog_present", NoneType](self.dialog, self.window)
        for k in range(len(self.rt.shown.nodes)):  # an in-place editor (.focused()) takes the keyboard, its text selected
            if self.rt.shown.nodes[k].kind == FIELD and self.rt.shown.nodes[k].value == 1 and self.widgets[k] != 0:
                _ = external_call["gtk_widget_grab_focus", c_int](self.widgets[k])
                external_call["gtk_editable_select_region", NoneType](self.widgets[k], c_int(0), c_int(-1))
                self.focus = -1
        if 0 <= self.focus < len(self.widgets) and self.rt.shown.nodes[self.focus].kind == FIELD:
            _ = external_call["gtk_entry_grab_focus_without_selecting", c_int](self.widgets[self.focus])  # keep typing
        self.focus = -1
        set_busy(False)

    def scroller_of(self, board: Int) -> Int:
        for bs in self.board_scrollers:
            if bs[0] == board:
                return bs[1]
        return 0

    def reveal(mut self) -> Bool:
        """Scrolls the pending Board so its reveal child shows (clear of the islands). Returns
        False while the page isn't laid out yet (try again next frame)."""
        var i = self.reveal_pending
        if i < 0 or i >= len(self.rt.shown.nodes) or self.rt.shown.nodes[i].kind != BOARD:
            self.reveal_pending = -1
            return True
        ref b = self.rt.shown.nodes[i]
        var k = b.value % 64 - 1
        var sw = self.scroller_of(i)
        if sw == 0 or k < 0 or k >= len(b.children):
            self.reveal_pending = -1
            return True
        var vadj = external_call["gtk_scrolled_window_get_vadjustment", Int](sw)
        var hadj = external_call["gtk_scrolled_window_get_hadjustment", Int](sw)
        var page = external_call["gtk_adjustment_get_page_size", Float64](vadj)
        var upper = external_call["gtk_adjustment_get_upper", Float64](vadj)
        if page <= 0 or (not self.board_list and upper < Float64(b.size)):
            return False
        # where the card really is (on the page, or stacked in the narrow list): its widget's bounds
        var rect = List[Float32](length=4, fill=0)  # graphene_rect_t: x, y, width, height
        var inner = self.widgets[i]
        if external_call["gtk_widget_compute_bounds", c_int](self.widgets[b.children[k]], inner, Int(rect.unsafe_ptr())) == 0:
            return False
        var cx = Float64(rect[0])
        var cy = Float64(rect[1])
        var cw = Float64(rect[2])
        var ch = Float64(rect[3])
        _ = len(rect)
        var v = external_call["gtk_adjustment_get_value", Float64](vadj)
        if cy < v + 72 or cy + min(ch, page - 160) > v + page - 56:  # (clear of the top and bottom islands)
            external_call["gtk_adjustment_set_value", NoneType](vadj, max(cy - 88, 0.0))
        var hv = external_call["gtk_adjustment_get_value", Float64](hadj)
        var hpage = external_call["gtk_adjustment_get_page_size", Float64](hadj)
        if cx < hv or cx + min(cw, hpage - 48) > hv + hpage:
            external_call["gtk_adjustment_set_value", NoneType](hadj, max(cx - 24, 0.0))
        self.revealed = b.value
        self.reveal_pending = -1
        return True

    def in_view(self, board: Int) -> List[String]:
        """Tags of the Board's children whose header (top-left 44 pt) is inside the visible page."""
        var out = List[String]()
        var sw = self.scroller_of(board)
        if sw == 0:
            return out^
        var vadj = external_call["gtk_scrolled_window_get_vadjustment", Int](sw)
        var hadj = external_call["gtk_scrolled_window_get_hadjustment", Int](sw)
        var v = external_call["gtk_adjustment_get_value", Float64](vadj)
        var vp = external_call["gtk_adjustment_get_page_size", Float64](vadj)
        var h = external_call["gtk_adjustment_get_value", Float64](hadj)
        var hp = external_call["gtk_adjustment_get_page_size", Float64](hadj)
        for c in self.rt.shown.nodes[board].children:
            ref n = self.rt.shown.nodes[c]
            if Float64(n.y) >= v - 1 and Float64(n.y + 44) <= v + vp + 1 and Float64(n.x) >= h - 1 and Float64(n.x + 44) <= h + hp + 1:
                out.append(n.name)
        sort(out)
        return out^

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
                elif kind == BUTTON and self.rt.shown.nodes[p.node].hint != "":
                    if self.rt.shown.nodes[p.node].style == ICON_ONLY:
                        external_call["gtk_widget_set_tooltip_text", NoneType](w, t.as_c_string_span())
                    else:
                        external_call["adw_button_content_set_label", NoneType](external_call["gtk_button_get_child", Int](w), t.as_c_string_span())
                elif kind == BUTTON or kind == TOGGLE:
                    external_call["gtk_button_set_label", NoneType](w, t.as_c_string_span()) if kind == BUTTON else external_call["gtk_check_button_set_label", NoneType](w, t.as_c_string_span())
                elif kind == FIELD:
                    if c_str(external_call["gtk_editable_get_text", Int](w)) != p.text:  # don't fight the typist
                        external_call["gtk_editable_set_text", NoneType](w, t.as_c_string_span())
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
            elif p.op == SET_VALUE and kind == BOARD:
                var token = self.rt.shown.nodes[p.node].value
                if token != 0 and token != self.revealed:
                    self.reveal_pending = p.node
                    _ = external_call["gtk_widget_add_tick_callback", c_uint](self.window, on_reveal_tick[Self.A], self_addr, 0)
            elif p.op == SET_VALUE and kind == LAZYLIST:
                pass  # the refresh below hands it a model of the new length
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
            elif p.op == SET_PLACE and not self.board_list:  # (a list ignores positions)
                ref n = self.rt.shown.nodes[p.node]
                if kind == BOARD:
                    external_call["gtk_widget_set_size_request", NoneType](w, c_int(n.spacing), c_int(n.size))
                else:
                    for b in self.boards:
                        if b.node == p.node:
                            external_call["gtk_fixed_move", NoneType](b.fixed, b.widget, Float64(n.x), Float64(n.y))
            # SET_MSG needs nothing: events look the message up in rt.shown.
        # Ask for the visible rows of every long list again: row text isn't part of the
        # view, so an edit that keeps the row count wouldn't show otherwise. GTK only
        # re-binds rows whose items changed, so the list gets fresh items (scroll is kept).
        for k in range(len(self.rt.shown.nodes)):
            if self.rt.shown.nodes[k].kind == LAZYLIST and self.widgets[k] != 0:
                refresh_rows(self.widgets[k], self.rt.shown.nodes[k].value)
        self.arm_all(self_addr)  # a new version, frames starting, or a layout change: canvases look again
        set_busy(False)

    # ---------- canvases ----------

    def arm(mut self, ci: Int, self_addr: Int):
        """Ticks canvas ci on every display frame until it's idle again (no frames asked for,
        current version drawn at the current size): idle canvases don't wake the CPU."""
        if 0 <= ci < len(self.canvases):
            self.canvases[ci].quiet = 0
        if 0 <= ci < len(self.canvases) and not self.canvases[ci].armed:
            self.canvases[ci].armed = True
            _ = external_call["gtk_widget_add_tick_callback", c_uint](self.canvases[ci].widget, on_tick[Self.A], self_addr, 0)

    def arm_all(mut self, self_addr: Int):
        for k in range(len(self.canvases)):
            self.arm(k, self_addr)

    def idle(self, ci: Int) -> Bool:
        ref c = self.canvases[ci]
        if self.rt.shown.nodes[c.node].msg2 != 0:
            return False
        var w = Int(external_call["gtk_widget_get_width", c_int](c.widget))
        var h = Int(external_call["gtk_widget_get_height", c_int](c.widget))
        return w > 0 and c.drawn == self.rt.shown.nodes[c.node].value and c.wpx == Int(Float64(w) * c.scale + 0.5) and c.hpx == Int(Float64(h) * c.scale + 0.5)

    def canvas_send(mut self, ci: Int, kind: Int, x: Float64, y: Float64, dx: Float64, dy: Float64, zoom: Float64, self_addr: Int):
        if ci < 0 or ci >= len(self.canvases):
            return
        var d = self.rt.gesture(self.canvases[ci].node, kind, x, y, dx, dy, zoom)
        self.apply(d, self_addr)

    def pointer(self, ci: Int) -> Tuple[Float64, Float64]:
        """Where the pointer is over canvas ci (its centre if it hasn't been seen)."""
        ref c = self.canvases[ci]
        if c.ptr_x >= 0:
            return (c.ptr_x, c.ptr_y)
        return (Float64(Int(external_call["gtk_widget_get_width", c_int](c.widget))) / 2,
                Float64(Int(external_call["gtk_widget_get_height", c_int](c.widget))) / 2)

    def tick(mut self, ci: Int, clock: Int, self_addr: Int) -> Bool:
        """Every display frame: send a frame event if the canvas asked for them, then redraw if
        needed. Returns whether to keep ticking."""
        if ci < 0 or ci >= len(self.canvases):
            return False
        var node = self.canvases[ci].node
        var now = Int(external_call["gdk_frame_clock_get_frame_time", Int64](clock))
        if self.rt.shown.nodes[node].msg2 != 0:
            var last = self.canvases[ci].last_us
            self.canvases[ci].last_us = now
            if self.canvases[ci].frames == 0:
                self.canvases[ci].first_us = now
            self.canvases[ci].frames += 1
            var d = self.rt.frame(node, now - last if last > 0 else 16667)
            self.apply(d, self_addr)
            if d.rebuild:
                return False  # the new widgets get their own ticks
        else:
            self.canvases[ci].last_us = 0
        self.draw_canvas(ci, self_addr)
        if ci < len(self.canvases) and self.idle(ci):
            self.canvases[ci].quiet += 1
            if self.canvases[ci].quiet >= 30:  # (~0.5 s: lets late relayouts, e.g. lists filling in, settle)
                self.canvases[ci].armed = False
                return False
        elif ci < len(self.canvases):
            self.canvases[ci].quiet = 0
        return True

    def draw_canvas(mut self, ci: Int, self_addr: Int):
        """Asks the app to paint canvas ci at its real pixel size (if its size or version changed)."""
        var widget = self.canvases[ci].widget
        var node = self.canvases[ci].node
        var w = Int(external_call["gtk_widget_get_width", c_int](widget))
        var h = Int(external_call["gtk_widget_get_height", c_int](widget))
        var native = external_call["gtk_widget_get_native", Int](widget)
        if w <= 0 or h <= 0 or native == 0:
            return
        var scale = external_call["gdk_surface_get_scale", Float64](external_call["gtk_native_get_surface", Int](native))
        var wpx = Int(Float64(w) * scale + 0.5)
        var hpx = Int(Float64(h) * scale + 0.5)
        var version = self.rt.shown.nodes[node].value
        if wpx == self.canvases[ci].wpx and hpx == self.canvases[ci].hpx and version == self.canvases[ci].drawn:
            return
        if len(self.canvases[ci].pixels) != wpx * hpx:
            self.canvases[ci].pixels = List[UInt32](length=wpx * hpx, fill=0)
        var surface = Surface(Int(self.canvases[ci].pixels.unsafe_ptr()), wpx, hpx, scale)
        var d = self.rt.draw(node, surface)
        var tex = texture(self.canvases[ci].pixels, wpx, hpx)
        external_call["gtk_picture_set_paintable", NoneType](widget, tex)
        external_call["g_object_unref", NoneType](tex)
        self.canvases[ci].wpx = wpx
        self.canvases[ci].hpx = hpx
        self.canvases[ci].scale = scale
        self.canvases[ci].drawn = version
        self.canvases[ci].draws += 1
        self.apply(d, self_addr)

    def canvases_drawn(self) -> Bool:
        """Whether every canvas shows its current version at its current size."""
        for ref c in self.canvases:
            var w = Int(external_call["gtk_widget_get_width", c_int](c.widget))
            var h = Int(external_call["gtk_widget_get_height", c_int](c.widget))
            if c.drawn != self.rt.shown.nodes[c.node].value or c.wpx == 0 or c.wpx != Int(Float64(w) * c.scale + 0.5) or c.hpx != Int(Float64(h) * c.scale + 0.5):
                return False
        return True

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

def on_reveal_tick[A: App](widget: Int, clock: Int, host_addr: Int) abi("C") -> c_int:
    """Each frame until the Board is laid out: scroll its reveal child into view, then stop."""
    return 0 if host_at[A](host_addr)[].reveal() else 1


def on_tick[A: App](widget: Int, clock: Int, host_addr: Int) abi("C") -> c_int:
    if busy():
        return 1  # G_SOURCE_CONTINUE: try again next frame
    return 1 if host_at[A](host_addr)[].tick(get_index(widget), clock, host_addr) else 0  # 0: G_SOURCE_REMOVE


# (These two only set flags and add tick callbacks, so they're safe even while the host is busy.)
def on_window_resized[A: App](window: Int, pspec: Int, host_addr: Int) abi("C"):
    host_at[A](host_addr)[].arm_all(host_addr)  # canvases redraw at their new size


def on_surface_layout[A: App](surface: Int, width: c_int, height: c_int, host_addr: Int) abi("C"):
    host_at[A](host_addr)[].arm_all(host_addr)  # the compositor resized the window (e.g. tiling)


def on_window_realize[A: App](window: Int, host_addr: Int) abi("C"):
    var surface = external_call["gtk_native_get_surface", Int](window)
    if surface != 0:
        connect_any(surface, "layout", on_surface_layout[A], host_addr)
        connect3(surface, "notify::scale", on_window_resized[A], host_addr)  # moved to a screen with another scale


def on_drag_begin[A: App](drag: Int, x: Float64, y: Float64, host_addr: Int) abi("C"):
    var host = host_at[A](host_addr)
    var ci = get_index(drag)
    if ci < 0 or ci >= len(host[].canvases):
        return
    host[].canvases[ci].drag_x = 0
    host[].canvases[ci].drag_y = 0
    host[].canvases[ci].start_x = x
    host[].canvases[ci].start_y = y
    host[].canvases[ci].moved = False
    if not busy():
        host[].canvas_send(ci, PRESS, x, y, 0, 0, 1, host_addr)  # where a drag (or a tap) starts


def on_drag_end[A: App](drag: Int, off_x: Float64, off_y: Float64, host_addr: Int) abi("C"):
    if busy():
        return
    var host = host_at[A](host_addr)
    var ci = get_index(drag)
    if ci < 0 or ci >= len(host[].canvases) or not host[].canvases[ci].moved:
        return  # (a plain tap: the click gesture sends TAP)
    host[].canvas_send(ci, RELEASE, host[].canvases[ci].start_x + off_x, host[].canvases[ci].start_y + off_y, 0, 0, 1, host_addr)


def on_drag_update[A: App](drag: Int, off_x: Float64, off_y: Float64, host_addr: Int) abi("C"):
    if busy():
        return
    var host = host_at[A](host_addr)
    var ci = get_index(drag)
    if ci < 0 or ci >= len(host[].canvases):
        return
    var dx = off_x - host[].canvases[ci].drag_x
    var dy = off_y - host[].canvases[ci].drag_y
    host[].canvases[ci].drag_x = off_x
    host[].canvases[ci].drag_y = off_y
    if abs(off_x) + abs(off_y) > 3:
        host[].canvases[ci].moved = True
    # where the pointer is now: the drag's start plus its offset (exact, and the same in test runs)
    host[].canvas_send(ci, PAN, host[].canvases[ci].start_x + off_x, host[].canvases[ci].start_y + off_y, dx, dy, 1, host_addr)


def on_scroll[A: App](scroll: Int, dx: Float64, dy: Float64, host_addr: Int) abi("C") -> c_int:
    """Mouse wheel / touchpad scroll: zoom around the pointer (4 notches = 2×)."""
    if busy():
        return 1
    var host = host_at[A](host_addr)
    var ci = get_index(scroll)
    if ci < 0 or ci >= len(host[].canvases) or dy == 0:
        return 1
    var at = host[].pointer(ci)
    # A mouse wheel scrolls in notches; touchpads in surface pixels (100 px = 4 notches = 2×).
    var notches = dy / 25.0 if external_call["gtk_event_controller_scroll_get_unit", c_int](scroll) == 1 else dy
    host[].canvas_send(ci, ZOOM, at[0], at[1], 0, 0, 2.0 ** (-notches / 4.0), host_addr)
    return 1


def on_motion[A: App](motion: Int, x: Float64, y: Float64, host_addr: Int) abi("C"):
    var host = host_at[A](host_addr)
    var ci = get_index(motion)
    if 0 <= ci < len(host[].canvases):
        host[].canvases[ci].ptr_x = x
        host[].canvases[ci].ptr_y = y


def on_pinch_begin[A: App](pinch: Int, sequence: Int, host_addr: Int) abi("C"):
    var host = host_at[A](host_addr)
    var ci = get_index(pinch)
    if 0 <= ci < len(host[].canvases):
        host[].canvases[ci].pinch = 1


def on_pinch[A: App](pinch: Int, scale: Float64, host_addr: Int) abi("C"):
    if busy() or scale <= 0:
        return
    var host = host_at[A](host_addr)
    var ci = get_index(pinch)
    if ci < 0 or ci >= len(host[].canvases):
        return
    var factor = scale / host[].canvases[ci].pinch
    host[].canvases[ci].pinch = scale
    var xy = List[Float64](length=2, fill=0)
    if external_call["gtk_gesture_get_bounding_box_center", c_int](pinch, Int(xy.unsafe_ptr()), Int(xy.unsafe_ptr()) + 8) == 0:
        var at = host[].pointer(ci)
        xy[0] = at[0]
        xy[1] = at[1]
    host[].canvas_send(ci, ZOOM, xy[0], xy[1], 0, 0, factor, host_addr)
    _ = len(xy)


def on_click_released[A: App](click: Int, presses: c_int, x: Float64, y: Float64, host_addr: Int) abi("C"):
    if busy():
        return
    var host = host_at[A](host_addr)
    var ci = get_index(click)
    if ci < 0 or ci >= len(host[].canvases) or host[].canvases[ci].moved:
        return
    host[].canvas_send(ci, DOUBLE if presses == 2 else TAP, x, y, 0, 0, 1, host_addr)  # (the first click of a double was a TAP)


def board_object[A: App](host: Pointer[GtkHost[A], MutUntrackedOrigin], drag: Int) -> Int:
    """The object this board gesture is dragging (its index in host.boards), or -1."""
    var bi = get_index(drag)
    while 0 <= bi < len(host[].boards) and host[].boards[bi].drag == drag:
        if host[].boards[bi].active:
            return bi
        bi += 1
    return -1


def on_board_drag_begin[A: App](drag: Int, x: Float64, y: Float64, host_addr: Int) abi("C"):
    var host = host_at[A](host_addr)
    var first = get_index(drag)
    if first < 0 or first >= len(host[].boards):
        return
    var last = first
    while last + 1 < len(host[].boards) and host[].boards[last + 1].drag == drag:
        last += 1
    var bi = last  # the topmost object under the pointer (later children draw above earlier ones)
    while bi >= first:
        ref b = host[].boards[bi]
        ref n = host[].rt.shown.nodes[b.node]
        var w = Float64(Int(external_call["gtk_widget_get_width", c_int](b.widget)))
        var h = Float64(Int(external_call["gtk_widget_get_height", c_int](b.widget)))
        var lx = x - Float64(n.x)
        var ly = y - Float64(n.y)
        if 0.0 <= lx and lx < w and 0.0 <= ly and ly < h:
            if n.kind == FIELD:  # an in-place editor floating on the page: it's typed in, never dragged
                external_call["gtk_gesture_set_state", c_int](drag, c_int(2))
                return
            host[].boards[bi].resizing = lx > w - 24 and ly > h - 24
            host[].boards[bi].active = host[].boards[bi].resizing or ly < 44  # the header moves it; the rest is the object's own
            if not host[].boards[bi].active:
                external_call["gtk_gesture_set_state", c_int](drag, c_int(2))  # GTK_EVENT_SEQUENCE_DENIED
            return
        bi -= 1
    external_call["gtk_gesture_set_state", c_int](drag, c_int(2))  # nothing under it


def on_board_drag_update[A: App](drag: Int, off_x: Float64, off_y: Float64, host_addr: Int) abi("C"):
    if busy():
        return
    var host = host_at[A](host_addr)
    var bi = board_object[A](host, drag)
    if bi < 0:
        return
    ref b = host[].boards[bi]
    ref n = host[].rt.shown.nodes[b.node]
    if b.resizing:  # live feedback; the app decides the final size on drag-end
        external_call["gtk_widget_set_size_request", NoneType](b.widget, c_int(max(n.w + Int(off_x), 120)), c_int(max(n.h + Int(off_y), 80)))
    else:
        external_call["gtk_fixed_move", NoneType](b.fixed, b.widget, Float64(max(n.x + Int(off_x), 0)), Float64(max(n.y + Int(off_y), 0)))


def on_board_drag_end[A: App](drag: Int, off_x: Float64, off_y: Float64, host_addr: Int) abi("C"):
    if busy():
        return
    var host = host_at[A](host_addr)
    var bi = board_object[A](host, drag)
    if bi < 0:
        return
    host[].boards[bi].active = False
    var b = host[].boards[bi].copy()
    var d = host[].rt.gesture(b.board, ZOOM if b.resizing else PAN, Float64(b.index), 0, off_x, off_y, 1)
    host[].apply(d, host_addr)


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
    count_up("mojoui-rows-bound")
    # Track the range of rows drawn since the last refresh (stored +1; 0 = none yet).
    var app = external_call["g_application_get_default", Int]()
    var lo = String("mojoui-bound-lo")
    var hi = String("mojoui-bound-hi")
    var low = external_call["g_object_get_data", Int](app, lo.as_c_string_span())
    if low == 0 or position + 1 < low:
        external_call["g_object_set_data", NoneType](app, lo.as_c_string_span(), position + 1)
    if position + 1 > external_call["g_object_get_data", Int](app, hi.as_c_string_span()):
        external_call["g_object_set_data", NoneType](app, hi.as_c_string_span(), position + 1)
    if position == 0:  # (for the test report: what row 0 shows right now)
        var key = String("mojoui-row0")
        var app = external_call["g_application_get_default", Int]()
        var free_name = String("g_free")
        var g_free = external_call["dlsym", Int](0, free_name.as_c_string_span())
        external_call["g_object_set_data_full", NoneType](app, key.as_c_string_span(),
            external_call["g_strdup", Int](text.as_c_string_span()), g_free)
        var owner = String("mojoui-row0-item")
        external_call["g_object_set_data", NoneType](app, owner.as_c_string_span(), item)
    var label = external_call["gtk_list_item_get_child", Int](item)
    external_call["gtk_label_set_text", NoneType](label, text.as_c_string_span())


def on_row_unbind(factory: Int, item: Int, host_addr: Int) abi("C"):
    var owner = String("mojoui-row0-item")
    var app = external_call["g_application_get_default", Int]()
    if external_call["g_object_get_data", Int](app, owner.as_c_string_span()) == item:  # row 0's widget left
        var key = String("mojoui-row0")
        external_call["g_object_set_data", NoneType](app, key.as_c_string_span(), 0)
        external_call["g_object_set_data", NoneType](app, owner.as_c_string_span(), 0)


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


def wait_frame(window: Int):
    """Lets the shown window's frame clock tick once (up to 300 ms), so a step's layout (a new tab
    page, a rebuilt board) is allocated before the next step or the report measures it. On X11 the
    tick is a timer, which `settle()` (pending work only) doesn't wait for."""
    var clock = external_call["gtk_widget_get_frame_clock", Int](window)
    if clock == 0:
        return
    var before = external_call["gdk_frame_clock_get_frame_counter", Int64](clock)
    external_call["gdk_frame_clock_request_phase", NoneType](clock, c_int(1 << 3))  # GDK_FRAME_CLOCK_PHASE_LAYOUT
    var deadline = perf_counter_ns() + 300_000_000
    while external_call["gdk_frame_clock_get_frame_counter", Int64](clock) == before and perf_counter_ns() < deadline:
        _ = external_call["g_main_context_iteration", c_int](0, c_int(1))


def wait_allocated(widget: Int):
    """Runs pending main-loop work until the widget has a size (the first step may come before the
    first layout pass). Never blocks: an unshown test window has nothing pending, so it gives up."""
    var deadline = perf_counter_ns() + 3_000_000_000
    while external_call["gtk_widget_get_width", c_int](widget) == 0 and perf_counter_ns() < deadline:
        if external_call["g_main_context_iteration", c_int](0, c_int(0)) == 0:
            return  # nothing pending: nothing will change


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
        var id = String(index)
        if rest == "Escape":  # what AdwAlertDialog sends on Escape: its close response
            id = c_str(external_call["adw_alert_dialog_get_close_response", Int](host[].widgets[i]))
        elif index < 0:
            print("TEST: no alert button", rest)
            return
        var signal = String("response")
        external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].widgets[i], signal.as_c_string_span(), id.as_c_string_span())
    elif verb == "back":
        var i = find(host[], NAVBAR, "", 0)
        if i < 0:
            print("TEST: no navbar")
            return
        var back = external_call["gtk_widget_get_first_child", Int](host[].widgets[i])
        if host[].rt.shown.nodes[i].msg == 0 or back == external_call["gtk_widget_get_last_child", Int](host[].widgets[i]):
            print("TEST: no back button")
            return
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
    elif verb == "drag" or verb == "dragat" or verb == "doubletap" or verb == "zoom" or verb == "frames" or verb == "tapat":
        var kv = split_at(rest, "=")
        var node = find(host[], CANVAS, "", to_int(kv[0]))
        var ci = -1
        for k in range(len(host[].canvases)):
            if host[].canvases[k].node == node:
                ci = k
        if ci < 0:
            print("TEST: no canvas", kv[0])
            return
        wait_allocated(host[].canvases[ci].widget)
        var drawn_by = perf_counter_ns() + 3_000_000_000  # and drawn once: a person can't tap what isn't on screen yet
        while not host[].canvases_drawn() and perf_counter_ns() < drawn_by:
            if external_call["g_main_context_iteration", c_int](0, c_int(0)) == 0 and getenv("MOJOUI_SHOT") == "":
                break  # unshown window: it will never draw
        if verb == "tapat":  # a click at (x, y) thousandths of the canvas: the click gesture's own signal
            var xy = split_at(kv[1], ",")
            var cw = Float64(Int(external_call["gtk_widget_get_width", c_int](host[].canvases[ci].widget)))
            var chh = Float64(Int(external_call["gtk_widget_get_height", c_int](host[].canvases[ci].widget)))
            var released = String("released")
            var pressed = String("drag-begin")  # a real click presses first (the drag gesture begins: PRESS)
            external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].canvases[ci].drag, pressed.as_c_string_span(),
                Float64(to_int(xy[0])) / 1000.0 * cw, Float64(to_int(xy[1])) / 1000.0 * chh)
            host[].canvases[ci].moved = False
            external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].canvases[ci].click, released.as_c_string_span(), c_int(1),
                Float64(to_int(xy[0])) / 1000.0 * cw, Float64(to_int(xy[1])) / 1000.0 * chh)
        elif verb == "doubletap":  # a double click at (x, y) thousandths: press, click 1, press, click 2
            var xy = split_at(kv[1], ",")
            var px = Float64(to_int(xy[0])) / 1000.0 * Float64(Int(external_call["gtk_widget_get_width", c_int](host[].canvases[ci].widget)))
            var py = Float64(to_int(xy[1])) / 1000.0 * Float64(Int(external_call["gtk_widget_get_height", c_int](host[].canvases[ci].widget)))
            var released = String("released")
            var pressed = String("drag-begin")
            for n_press in range(1, 3):
                external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].canvases[ci].drag, pressed.as_c_string_span(), px, py)
                host[].canvases[ci].moved = False
                external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].canvases[ci].click, released.as_c_string_span(), c_int(n_press), px, py)
                settle()
        elif verb == "drag" or verb == "dragat":  # the drag gesture's own signals, as a real drag sends them
            var sx = 10.0
            var sy = 10.0
            var rest2 = kv[1]
            if verb == "dragat":  # dragat:K=fx,fy,dx,dy: start at (fx, fy) thousandths of the canvas
                var a = split_at(rest2, ",")
                var b = split_at(a[1], ",")
                sx = Float64(to_int(a[0])) / 1000.0 * Float64(Int(external_call["gtk_widget_get_width", c_int](host[].canvases[ci].widget)))
                sy = Float64(to_int(b[0])) / 1000.0 * Float64(Int(external_call["gtk_widget_get_height", c_int](host[].canvases[ci].widget)))
                rest2 = b[1]
            var xy = split_at(rest2, ",")
            var dx = Float64(to_int(xy[0]))
            var dy = Float64(to_int(xy[1]))
            var begin = String("drag-begin")
            var update = String("drag-update")
            external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].canvases[ci].drag, begin.as_c_string_span(), sx, sy)
            external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].canvases[ci].drag, update.as_c_string_span(), dx / 2, dy / 2)
            external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].canvases[ci].drag, update.as_c_string_span(), dx, dy)
        elif verb == "zoom":  # the scroll controller's signal: 4 notches up = 2×
            var factor = Float64(to_int(kv[1]))
            var handled = List[c_int](length=1, fill=0)
            var signal = String("scroll")
            external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](host[].canvases[ci].scroll, signal.as_c_string_span(), Float64(0), -4.0 * log2(factor), Int(handled.unsafe_ptr()))
            _ = len(handled)
        else:  # frames: let the display run n frames, then report the rate
            var n = to_int(kv[1])
            var start = host[].canvases[ci].frames
            var draws = host[].canvases[ci].draws
            var first = 0
            var deadline = perf_counter_ns() + 20_000_000_000
            while perf_counter_ns() < deadline:
                _ = external_call["g_main_context_iteration", c_int](0, c_int(1))
                if ci >= len(host[].canvases):
                    break
                var done = host[].canvases[ci].frames - start
                if done == 1 and first == 0:
                    first = host[].canvases[ci].last_us
                    draws = host[].canvases[ci].draws
                if done > n:
                    break
            var ms = Float64(host[].canvases[ci].last_us - first) / 1000.0
            var got = host[].canvases[ci].frames - start - 1
            var fps = Float64(got) / (ms / 1000.0) if ms > 0 else 0.0
            print("FRAMES: " + String(got) + " in " + one_decimal(Float32(ms)) + " ms = " + one_decimal(Float32(fps)) + " fps, draws " + String(host[].canvases[ci].draws - draws))
    elif verb == "move" or verb == "resize":  # a board object dragged by its header (or its corner), as a real drag sends it
        var kv = split_at(rest, "=")
        var xy = split_at(kv[1], ",")
        var dx = Float64(to_int(xy[0]))
        var dy = Float64(to_int(xy[1]))
        var bi = -1
        for k in range(len(host[].boards)):
            if host[].rt.shown.nodes[host[].boards[k].node].name == kv[0]:
                bi = k
        if bi < 0:
            print("TEST: no board object", kv[0])
            return
        wait_allocated(host[].boards[bi].widget)
        var w = Float64(Int(external_call["gtk_widget_get_width", c_int](host[].boards[bi].widget)))
        var h = Float64(Int(external_call["gtk_widget_get_height", c_int](host[].boards[bi].widget)))
        ref n = host[].rt.shown.nodes[host[].boards[bi].node]
        var sx = Float64(n.x) + (w - 8 if verb == "resize" else 20.0)  # in the board's coordinates
        var sy = Float64(n.y) + (h - 8 if verb == "resize" else 16.0)
        var begin = String("drag-begin")
        var update = String("drag-update")
        var end = String("drag-end")
        var g = host[].boards[bi].drag
        external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](g, begin.as_c_string_span(), sx, sy)
        external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](g, update.as_c_string_span(), dx / 2, dy / 2)
        external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](g, update.as_c_string_span(), dx, dy)
        external_call["g_signal_emit_by_name", NoneType, num_fixed_args=2](g, end.as_c_string_span(), dx, dy)
    else:
        print("TEST: unknown step", step)


def report[A: App](host_addr: Int):
    """Prints every widget's state as GTK reports it, in screen order (alerts last,
    since they float above the page on every host)."""
    report_pass[A](host_addr, False)
    report_pass[A](host_addr, True)


def report_pass[A: App](host_addr: Int, alerts: Bool):
    var host = host_at[A](host_addr)
    if not alerts:
        print("NATIVE: GTK " + String(external_call["gtk_get_major_version", c_int]()) + "." + String(external_call["gtk_get_minor_version", c_int]()))
        if host[].rt.app.design() == FLUENT:
            print("DESIGN: fluent")
        if external_call["gtk_widget_get_mapped", c_int](host[].window) != 0:  # laid out, so measurable
            for i in range(len(host[].rt.shown.nodes)):
                if host[].rt.shown.nodes[i].name != "":
                    var rect = List[Float32](length=4, fill=0)  # graphene_rect_t: x, y, width, height
                    var ok = external_call["gtk_widget_compute_bounds", c_int](host[].widgets[i], host[].window, Int(rect.unsafe_ptr()))
                    if ok != 0:
                        print("BOX: " + host[].rt.shown.nodes[i].name + " " + one_decimal(rect[0]) + " " + one_decimal(rect[1])
                              + " " + one_decimal(rect[2]) + " " + one_decimal(rect[3]))
                    _ = len(rect)
    for i in range(len(host[].rt.shown.nodes)):
        if host[].rt.shown.nodes[i].kind == BOARD and not alerts:
            print("LAYOUT: " + ("list" if host[].board_list else "board"))
            for c in host[].rt.shown.nodes[i].children:
                ref ch = host[].rt.shown.nodes[c]
                if not host[].board_list:
                    print("BOARD: " + ch.name + " at " + String(ch.x) + "," + String(ch.y) + " " + String(ch.w) + "x" + String(ch.h))
            if not host[].board_list and getenv("MOJOUI_SHOT") != "":  # (only a shown window has a visible part)
                var seen = host[].in_view(i)
                var line = String("INVIEW: ")
                for k in range(len(seen)):
                    line += (", " if k > 0 else "") + seen[k]
                print(line)
    for i in range(len(host[].rt.shown.nodes)):
        ref n = host[].rt.shown.nodes[i]
        var w = host[].widgets[i]
        if (n.kind == ALERT) != alerts:
            continue
        if n.kind == TEXT:
            print("LABEL: " + c_str(external_call["gtk_label_get_text", Int](w)))
        elif n.kind == BUTTON:
            if n.hint != "" and n.style == ICON_ONLY:
                print("BUTTON: " + c_str(external_call["gtk_widget_get_tooltip_text", Int](w)))
            elif n.hint != "":
                print("BUTTON: " + c_str(external_call["adw_button_content_get_label", Int](external_call["gtk_button_get_child", Int](w))))
            else:
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
        if n.kind == ALERT:
            var line = c_str(external_call["adw_alert_dialog_get_heading", Int](w)) + " | " + c_str(external_call["adw_alert_dialog_get_body", Int](w)) + " | "
            for j in range(len(n.options)):
                var id = String(j)
                line += (", " if j > 0 else "") + c_str(external_call["adw_alert_dialog_get_response_label", Int](w, id.as_c_string_span()))
            print("ALERT: " + line)
            if getenv("MOJOUI_SHOT") != "":
                print("ALERTSHOWN: " + ("yes" if external_call["gtk_widget_get_mapped", c_int](w) != 0 else "no"))
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
            print("LISTBOUND: " + String(counter("mojoui-rows-bound")))
            var key = String("mojoui-row0")
            var app = external_call["g_application_get_default", Int]()
            var row0 = external_call["g_object_get_data", Int](app, key.as_c_string_span())
            if row0 != 0:  # only while row 0 is on screen (as on the web)
                print("LISTROW: " + c_str(row0))
        elif n.kind == CANVAS:
            for ref c in host[].canvases:
                if c.node == i and c.wpx > 0:
                    print("CANVAS: " + String(Int(external_call["gtk_widget_get_width", c_int](w))) + "x" + String(Int(external_call["gtk_widget_get_height", c_int](w)))
                          + " pt " + String(c.wpx) + "x" + String(c.hpx) + " px scale " + one_decimal(Float32(c.scale)) + " colours "
                          + String(colours(c.pixels)) + " draws " + String(c.draws) + " painted " + String(painted(c.pixels)))
        elif n.kind == IMAGE:
            var paintable = external_call["gtk_picture_get_paintable", Int](w)
            print("IMAGE: " + String(external_call["gdk_texture_get_width", c_int](paintable)) + "x" + String(external_call["gdk_texture_get_height", c_int](paintable)))


def colours(pixels: List[UInt32]) -> Int:
    """How many different colours a sample of the pixels has (to tell a picture from a blank)."""
    var sample = List[UInt32]()
    var step = max(len(pixels) // 20000, 1)
    for i in range(0, len(pixels), step):
        sample.append(pixels[i])
    sort(sample)
    var n = 0
    for i in range(len(sample)):
        if i == 0 or sample[i] != sample[i - 1]:
            n += 1
    return n


def painted(pixels: List[UInt32]) -> Int:
    """The share (percent) of a sample of the pixels that differ clearly from the most common colour,
    the background: a blank canvas is ~0, a drawn map or chart tens of percent (goal 7's measure, D-70).
    Colour counts depend on the renderer's antialiasing; this doesn't."""
    var sample = List[UInt32]()
    var step = max(len(pixels) // 20000, 1)
    for i in range(0, len(pixels), step):
        sample.append(pixels[i])
    if len(sample) == 0:
        return 0
    var sorted_ = sample.copy()
    sort(sorted_)
    var background = sorted_[0]
    var best = 0
    var run_start = 0
    for i in range(1, len(sorted_) + 1):
        if i == len(sorted_) or sorted_[i] != sorted_[run_start]:
            if i - run_start > best:
                best = i - run_start
                background = sorted_[run_start]
            run_start = i
    var n = 0
    for px in sample:
        var d = 0
        for shift in [0, 8, 16]:
            d += abs(Int((px >> UInt32(shift)) & 0xFF) - Int((background >> UInt32(shift)) & 0xFF))
        if d > 30:
            n += 1
    return n * 100 // len(sample)


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
    if node == 0:  # nothing drawn yet (e.g. a dialog window took the first frame)
        print("SHOT: skipped (window had no frame to capture)")
        return
    var renderer = external_call["gtk_native_get_renderer", Int](window)
    var texture = external_call["gsk_renderer_render_texture", Int](renderer, node, 0)
    var p = path
    var ok = external_call["gdk_texture_save_to_png", c_int](texture, p.as_c_string_span())
    print("SHOT:", path if ok != 0 else "failed")


# Fluent 2 tokens for GTK (apps whose design() is FLUENT): neutral greys, the brand blue as the accent,
# 4/8 px corners. Light theme. (Colours GTK can't take from CSS stay libadwaita's.)
comptime FLUENT_CSS = """
:root { --accent-bg-color: #0F6CBD; --accent-color: #0F6CBD; --accent-fg-color: #ffffff; }
window.fluent { background-color: #F7F7F8; color: #242424; font-size: 14px; }
window.fluent label.title-1 { font-size: 20px; font-weight: 600; letter-spacing: -0.01em; }
window.fluent label.title-4 { font-size: 14px; font-weight: 600; }
window.fluent label.caption { font-size: 12px; }
/* cards: white panels with a hairline and a soft lift */
window.fluent .mui-card { background-color: #ffffff; border-radius: 8px; padding: 12px 14px;
  box-shadow: 0 0 0 1px rgba(0,0,0,.06), 0 1px 2px rgba(0,0,0,.06), 0 4px 12px rgba(0,0,0,.04); }
/* islands: the chrome floating over the page */
window.fluent label.mui-tone-warn { color: #C2410C; } window.fluent label.mui-tone-good { color: #0F766E; }
window.fluent label.mui-tone-strong { font-weight: 700; } window.fluent label.mui-tone-accent { color: #0F6CBD; }
window.fluent .mui-card.mui-warn { background-color: #FFF7ED; box-shadow: inset 0 0 0 1px #FED7AA; }
window.fluent .mui-card.mui-good { background-color: #F0FDF4; box-shadow: inset 0 0 0 1px #BBF7D0; }
window.fluent .mui-island { background-color: #ffffff; border-radius: 10px; padding: 6px 10px; min-height: 32px;
  box-shadow: 0 0 0 1px rgba(0,0,0,.07), 0 6px 20px rgba(0,0,0,.10); }
/* the page: a quiet dotted canvas */
window.fluent .mui-board { background-color: #F7F7F8;
  background-image: radial-gradient(circle, #D6D6DA 1px, transparent 1.5px); background-size: 24px 24px; }
/* buttons: white with a hairline, semibold, 32 px; quiet ones have no fill until hovered */
window.fluent button { border-radius: 6px; min-height: 30px; padding: 2px 12px; font-weight: 600;
  background: #ffffff; color: #242424; box-shadow: inset 0 0 0 1px #D1D1D1; }
window.fluent button:hover { background: #F5F5F5; }
window.fluent button:active { background: #E0E0E0; }
window.fluent button.flat { background: transparent; box-shadow: none; font-weight: 500; color: #424242; }
window.fluent button.flat:hover { background: rgba(0,0,0,.05); }
window.fluent button.flat:active { background: rgba(0,0,0,.09); }
window.fluent button.image-button { min-width: 30px; padding: 2px 6px; }
window.fluent button.suggested-action { background: #0F6CBD; color: #ffffff; box-shadow: none; }
window.fluent button.suggested-action:hover { background: #115EA3; }
/* fields: white, hairline, Fluent's underline that turns blue on focus */
window.fluent entry, window.fluent textview, window.fluent dropdown > button { border-radius: 6px; background: #ffffff;
  box-shadow: inset 0 0 0 1px #D1D1D1, inset 0 -1px 0 0 #8A8A8A; font-weight: 400; }
window.fluent entry:focus-within { box-shadow: inset 0 0 0 1px #D1D1D1, inset 0 -2px 0 0 #0F6CBD; outline: none; }
window.fluent textview text { background: #ffffff; }
window.fluent dropdown > button { min-height: 30px; padding: 2px 10px; }
window.fluent dropdown > button:hover { background: #FAFAFA; }
window.fluent scrollbar slider { min-width: 8px; min-height: 8px; background-color: rgba(0,0,0,.28); }
"""


def omarchy_css(p: Palette) -> String:
    """The Omarchy skin for GTK, from the person's theme colours: flat, hairline borders, JetBrains Mono."""
    var page = hex_of(p.page)
    var card = hex_of(p.card)
    var raised = hex_of(p.raised)
    var ink = hex_of(p.ink)
    var ink2 = hex_of(p.ink2)
    var ink3 = hex_of(p.ink3)
    var line = hex_of(p.line)
    var strong = hex_of(p.line_strong)
    var accent = hex_of(p.accent)
    var wash = hex_of(p.accent_wash)
    var on_accent = hex_of(p.accent_ink)
    return (
        ":root { --accent-bg-color: " + accent + "; --accent-color: " + accent + "; --accent-fg-color: " + on_accent + "; }\n"
        + "window.omarchy { background-color: " + page + "; color: " + ink2 + "; font-family: 'JetBrainsMono Nerd Font', 'JetBrains Mono', monospace; font-size: 13px; }\n"
        + "window.omarchy label { color: " + ink2 + "; }\n"
        + "window.omarchy label.title-1, window.omarchy label.title-4 { color: " + ink + "; font-weight: 700; }\n"
        + "window.omarchy label.title-1 { font-size: 18px; } window.omarchy label.title-4 { font-size: 13px; }\n"
        + "window.omarchy label.caption { font-size: 11px; color: " + ink3 + "; }\n"
        + "window.omarchy .dim-label { opacity: 1; }\n"
        + "window.omarchy .mui-card { background-color: " + card + "; border-radius: 4px; padding: 12px 14px; box-shadow: inset 0 0 0 1px " + line + "; }\n"
        + "window.omarchy label.mui-tone-warn { color: " + hex_of(p.warn) + "; } window.omarchy label.mui-tone-good { color: " + hex_of(p.good) + "; }\n"
        + "window.omarchy label.mui-tone-strong { color: " + ink + "; font-weight: 700; } window.omarchy label.mui-tone-accent { color: " + accent + "; }\n"
        + "window.omarchy .mui-card.mui-warn { background-color: " + hex_of(mix(p.card, p.warn, 0.12)) + "; box-shadow: inset 0 0 0 1px " + hex_of(mix(p.card, p.warn, 0.55)) + "; }\n"
        + "window.omarchy .mui-card.mui-good { background-color: " + hex_of(mix(p.card, p.good, 0.10)) + "; box-shadow: inset 0 0 0 1px " + hex_of(mix(p.card, p.good, 0.50)) + "; }\n"
        + "window.omarchy .mui-island { background-color: " + card + "; border-radius: 4px; padding: 6px 10px; min-height: 32px; box-shadow: inset 0 0 0 1px " + strong + ", 0 6px 18px rgba(0,0,0,.35); }\n"
        + "window.omarchy .mui-board { background-color: " + page + "; background-image: radial-gradient(circle, " + line + " 1px, transparent 1.5px); background-size: 24px 24px; }\n"
        + "window.omarchy button { border-radius: 3px; min-height: 28px; padding: 2px 10px; font-weight: 500; background: transparent; color: " + ink + "; box-shadow: inset 0 0 0 1px " + strong + "; }\n"
        + "window.omarchy button:hover { background: " + raised + "; }\n"
        + "window.omarchy button:active { background: " + wash + "; }\n"
        + "window.omarchy button.flat { box-shadow: none; color: " + ink2 + "; }\n"
        + "window.omarchy button.flat:hover { background: " + raised + "; color: " + ink + "; }\n"
        + "window.omarchy button.image-button { min-width: 28px; padding: 2px 6px; }\n"
        + "window.omarchy button label, window.omarchy button image { color: inherit; }\n"
        + "window.omarchy button.suggested-action { background: " + accent + "; color: " + on_accent + "; box-shadow: none; font-weight: 700; }\n"
        + "window.omarchy button.suggested-action:hover { background: " + hex_of(mix(p.accent, p.ink, 0.2)) + "; }\n"
        + "window.omarchy entry, window.omarchy textview, window.omarchy dropdown > button { border-radius: 3px; background: " + page + "; color: " + ink + "; box-shadow: inset 0 0 0 1px " + strong + "; }\n"
        + "window.omarchy entry:focus-within { box-shadow: inset 0 0 0 1px " + accent + "; outline: none; }\n"
        + "window.omarchy textview text { background: " + page + "; color: " + ink + "; }\n"
        + "window.omarchy dropdown > button { min-height: 28px; padding: 2px 8px; }\n"
        + "window.omarchy popover > contents { background: " + card + "; color: " + ink + "; box-shadow: inset 0 0 0 1px " + strong + "; }\n"
        + "window.omarchy scrollbar slider { min-width: 6px; min-height: 6px; background-color: " + strong + "; border-radius: 3px; }\n"
        + "window.omarchy entry.mui-cell-editor { border-radius: 0; box-shadow: inset 0 0 0 2px " + accent + "; background: " + card + "; }\n"
    )


def on_activate[A: App](gapp: Int, host_addr: Int) abi("C"):
    var host = host_at[A](host_addr)
    host[].window = external_call["gtk_application_window_new", Int](gapp)
    var title = host[].rt.app.title()
    external_call["gtk_window_set_title", NoneType](host[].window, title.as_c_string_span())
    if host[].rt.app.design() == FLUENT:  # Fluent 2 tokens on top of libadwaita (a light design)
        var manager = external_call["adw_style_manager_get_default", Int]()
        external_call["adw_style_manager_set_color_scheme", NoneType](manager, c_int(1))  # ADW_COLOR_SCHEME_FORCE_LIGHT
        var provider = external_call["gtk_css_provider_new", Int]()
        var rules = String(FLUENT_CSS)
        external_call["gtk_css_provider_load_from_string", NoneType](provider, rules.as_c_string_span())
        var display = external_call["gdk_display_get_default", Int]()
        external_call["gtk_style_context_add_provider_for_display", NoneType](display, provider, c_uint(801))
        add_class(host[].window, "fluent")
    elif host[].rt.app.design() == OMARCHY:  # the person's Omarchy theme: its colours, JetBrains Mono, flat
        var pal = Palette.omarchy()
        var manager = external_call["adw_style_manager_get_default", Int]()
        external_call["adw_style_manager_set_color_scheme", NoneType](manager, c_int(4 if pal.dark else 1))  # FORCE_DARK / FORCE_LIGHT
        var provider = external_call["gtk_css_provider_new", Int]()
        var rules = omarchy_css(pal)
        external_call["gtk_css_provider_load_from_string", NoneType](provider, rules.as_c_string_span())
        var display = external_call["gdk_display_get_default", Int]()
        external_call["gtk_style_context_add_provider_for_display", NoneType](display, provider, c_uint(801))
        add_class(host[].window, "omarchy")
    install_icons(host[].rt.app.design() == OMARCHY)
    var size = host[].rt.app.window_size()
    var forced = getenv("MOJOUI_WINDOW")  # tests: "1280x800" checks a smaller laptop screen
    if forced != "":
        var wh = split_at(forced, "x")
        size = (to_int(wh[0]), to_int(wh[1]))
    external_call["gtk_window_set_default_size", NoneType](host[].window, c_int(size[0]), c_int(size[1]))
    host[].window_w = size[0]
    for prop in ["notify::default-width", "notify::default-height", "notify::maximized", "notify::fullscreened"]:
        connect3(host[].window, prop, on_window_resized[A], host_addr)
    connect(host[].window, "realize", on_window_realize[A], host_addr)
    host[].show(host_addr)
    var steps = getenv("MOJOUI_TEST")
    var testing = is_set("MOJOUI_TEST")  # set, even to "": report the widgets' state
    var shot = getenv("MOJOUI_SHOT")
    if testing:
        # Test windows ignore the real keyboard and mouse: the checks drive the widgets
        # themselves, and someone working at the desktop mustn't type into them by accident.
        external_call["gtk_widget_set_can_focus", NoneType](host[].window, c_int(0))
        external_call["gtk_widget_set_can_target", NoneType](host[].window, c_int(0))
        # A fixed size, so measurements don't depend on how the desktop tiles windows.
        external_call["gtk_window_set_resizable", NoneType](host[].window, c_int(0))
        var title = String("mojoui test window (closes by itself)")
        external_call["gtk_window_set_title", NoneType](host[].window, title.as_c_string_span())
    if not testing or shot != "":
        external_call["gtk_window_present", NoneType](host[].window)
    if testing and shot != "":
        # On X11 (the headless display) the first layout waits for the server's map event, which
        # isn't pending yet: block for it, up to 3 s, so steps and measurements see a laid-out window.
        var up_by = perf_counter_ns() + 3_000_000_000
        while external_call["gtk_widget_get_width", c_int](host[].window) == 0 and perf_counter_ns() < up_by:
            _ = external_call["g_main_context_iteration", c_int](0, c_int(1))
        settle()
    if testing:
        for step in steps.split(";"):
            if String(step) != "":
                run_step[A](host_addr, String(step))
            settle()
            if shot != "":
                wait_frame(host[].window)
                var by = perf_counter_ns() + 1_000_000_000
                while host[].reveal_pending >= 0 and perf_counter_ns() < by:  # a scroll into view waits for layout
                    _ = external_call["g_main_context_iteration", c_int](0, c_int(1))
        if shot != "" and len(host[].canvases) > 0:  # on screen: let canvases draw what they show now
            var deadline = perf_counter_ns() + 5_000_000_000
            while not host[].canvases_drawn() and perf_counter_ns() < deadline:
                _ = external_call["g_main_context_iteration", c_int](0, c_int(1))
            settle()
        report[A](host_addr)
    if shot != "":
        save_png(host[].window, shot)
    if testing or shot != "":
        external_call["g_application_quit", NoneType](gapp)


def run[A: App]() -> Int:
    """Opens the app in a native GTK window and runs until it's closed."""
    var host = alloc(Layout[GtkHost[A]].single()).unsafe_leak()  # lives as long as the app
    A.init_shared()
    host.unsafe_write(GtkHost[A](A()))
    var id = String("dev.mojoui.App")
    var gapp = external_call["adw_application_new", Int](id.as_c_string_span(), c_int(G_APPLICATION_NON_UNIQUE))
    connect(gapp, "activate", on_activate[A], Int(host))
    return Int(external_call["g_application_run", c_int](gapp, c_int(0), 0))
