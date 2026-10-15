# Mac host: draws a mojoui View with real AppKit controls.
#
# Events: every control's tag packs the host's address and the node index
# ((host << 16) | node), and its target is one MojoTarget object whose methods
# (tap:, submit:, toggle:, select:, slide:, controlTextDidChange:) are Mojo
# functions. AppKit doesn't send actions when we set values ourselves, so there's
# no echo to guard against (unlike GTK).

from std.ffi import c_int
from std.memory import Pointer
from std.memory.alloc import alloc, Layout

from mojoui.view import (
    TEXT, BUTTON, VSTACK, HSTACK, SPACER, FIELD, TOGGLE, DROPDOWN, SLIDER, PROGRESS, DIVIDER, SCROLL,
    TITLE, HEADLINE, CAPTION, PROMINENT, DESTRUCTIVE,
)
from mojoui.diff import Diff, SET_TEXT, SET_VALUE
from mojoui.app import App, Event, Runtime
from mojoui.hosts.objc import (
    cls, sel, msg, new, ns_string, from_ns, constrain, new_class, add_method, register_class, pool_push,
)

comptime NODE_BITS = 16


def tag_for(host_addr: Int, node: Int) -> Int:
    return (host_addr << NODE_BITS) | node


struct AppKitHost[A: App](Movable):
    var rt: Runtime[Self.A]
    var window: Int
    var target: Int  # MojoTarget object that receives every event
    var widgets: List[Int]

    def __init__(out self):
        self.rt = Runtime(Self.A())
        self.window = 0
        self.target = 0
        self.widgets = List[Int]()

    def wire(self, w: Int, i: Int, self_addr: Int, action: String):
        _ = msg(w, "setTag:", tag_for(self_addr, i))
        _ = msg(w, "setTarget:", self.target)
        _ = msg(w, "setAction:", sel(action))

    def build(mut self, i: Int, self_addr: Int) -> Int:
        var node = self.rt.shown.nodes[i].copy()  # copy: building children mutates self
        var w: Int
        if node.kind == TEXT:
            w = msg(cls("NSTextField"), "labelWithString:", ns_string(node.text))
            _ = msg(w, "setAlignment:", 1)  # NSTextAlignmentCenter (1 on Apple Silicon; 2 is right)
            var size = Float64(13)
            var bold = False
            if node.style == TITLE:
                size, bold = Float64(26), True
            elif node.style == HEADLINE:
                size, bold = Float64(15), True
            elif node.style == CAPTION:
                size = Float64(11)
                _ = msg(w, "setTextColor:", msg(cls("NSColor"), "secondaryLabelColor"))
            _ = msg(w, "setFont:", msg(cls("NSFont"), "boldSystemFontOfSize:" if bold else "systemFontOfSize:", size))
        elif node.kind == BUTTON:
            w = msg(cls("NSButton"), "buttonWithTitle:target:action:", ns_string(node.text), self.target, sel("tap:"))
            _ = msg(w, "setTag:", tag_for(self_addr, i))
            if node.style == PROMINENT:
                _ = msg(w, "setKeyEquivalent:", ns_string("\r"))  # the blue default button; Return taps it
                _ = msg(w, "setControlSize:", 3)  # NSControlSizeLarge
            elif node.style == DESTRUCTIVE:
                _ = msg(w, "setHasDestructiveAction:", 1)
                _ = msg(w, "setContentTintColor:", msg(cls("NSColor"), "systemRedColor"))
        elif node.kind == FIELD:
            w = msg(cls("NSTextField"), "textFieldWithString:", ns_string(node.text))
            _ = msg(w, "setPlaceholderString:", ns_string(node.hint))
            _ = msg(w, "setDelegate:", self.target)  # controlTextDidChange: as you type
            self.wire(w, i, self_addr, "submit:")  # the action fires on Return
            constrain(w, "widthAnchor", Float64(220))
        elif node.kind == TOGGLE:
            w = msg(cls("NSButton"), "checkboxWithTitle:target:action:", ns_string(node.text), self.target, sel("toggle:"))
            _ = msg(w, "setTag:", tag_for(self_addr, i))
            _ = msg(w, "setState:", node.value)  # NSControlStateValueOn = 1
        elif node.kind == DROPDOWN:
            w = msg(
                msg(cls("NSPopUpButton"), "alloc"),
                "initWithFrame:pullsDown:",
                Float64(0), Float64(0), Float64(160), Float64(28),  # rect as 4 floats (arm64)
                0,  # pop-up, not pull-down
            )
            for o in node.options:
                _ = msg(w, "addItemWithTitle:", ns_string(o))
            _ = msg(w, "selectItemAtIndex:", node.value)
            self.wire(w, i, self_addr, "select:")
        elif node.kind == SLIDER:
            w = msg(
                cls("NSSlider"), "sliderWithValue:minValue:maxValue:target:action:",
                Float64(node.value), Float64(0), Float64(100), self.target, sel("slide:"),
            )
            _ = msg(w, "setTag:", tag_for(self_addr, i))
            _ = msg(w, "setContinuous:", 1)
            constrain(w, "widthAnchor", Float64(240))
        elif node.kind == PROGRESS:
            w = new("NSProgressIndicator")
            _ = msg(w, "setStyle:", 0)  # bar
            _ = msg(w, "setIndeterminate:", 0)
            _ = msg(w, "setMinValue:", Float64(0))
            _ = msg(w, "setMaxValue:", Float64(100))
            _ = msg(w, "setDoubleValue:", Float64(node.value))
            constrain(w, "widthAnchor", Float64(240))
        elif node.kind == DIVIDER:
            w = new("NSBox")
            _ = msg(w, "setBoxType:", 2)  # NSBoxSeparator
            constrain(w, "widthAnchor", Float64(280))
        elif node.kind == SPACER:
            w = new("NSView")
        elif node.kind == SCROLL:
            w = new("NSScrollView")
            _ = msg(w, "setHasVerticalScroller:", 1)
            _ = msg(w, "setDrawsBackground:", 0)
            var content = self.build(node.children[0], self_addr)
            _ = msg(content, "setTranslatesAutoresizingMaskIntoConstraints:", 0)
            _ = msg(w, "setDocumentView:", content)
            var clip = msg(w, "contentView")
            for anchor in ["topAnchor", "leadingAnchor", "widthAnchor"]:
                _ = msg(msg(msg(content, anchor), "constraintEqualToAnchor:", msg(clip, anchor)), "setActive:", 1)
            constrain(w, "heightAnchor", Float64(node.size))
            constrain(w, "widthAnchor", Float64(320))
        else:
            w = new("NSStackView")
            _ = msg(w, "setOrientation:", 1 if node.kind == VSTACK else 0)
            _ = msg(w, "setAlignment:", 9 if node.kind == VSTACK else 10)  # NSLayoutAttributeCenterX / CenterY
            _ = msg(w, "setSpacing:", Float64(node.spacing))
            for c in node.children:
                _ = msg(w, "addArrangedSubview:", self.build(c, self_addr))
        self.widgets[i] = w
        return w

    def show(mut self, self_addr: Int):
        # Old controls are deliberately never released: that keeps a control alive
        # while its window content is replaced in the middle of its own action.
        # (Adding `release` later means delaying it until the handler returns.)
        self.widgets = List[Int](length=len(self.rt.shown.nodes), fill=0)  # 0 = nil: patches become no-ops
        if len(self.rt.shown.nodes) >= (1 << NODE_BITS):
            var note = msg(cls("NSTextField"), "labelWithString:", ns_string("Too many items to show (limit 65,535)."))
            _ = msg(self.window, "setContentView:", note)  # no stale controls left to use
            return
        var root = self.build(0, self_addr)
        var holder = new("NSStackView")  # centres the app's root in the window
        _ = msg(holder, "setOrientation:", 1)
        _ = msg(holder, "setAlignment:", 9)
        _ = msg(holder, "setEdgeInsets:", Float64(32), Float64(32), Float64(32), Float64(32))
        _ = msg(holder, "addArrangedSubview:", root)
        _ = msg(self.window, "setContentView:", holder)

    def apply(mut self, d: Diff, self_addr: Int):
        if d.rebuild:
            self.show(self_addr)
            return
        for p in d.patches:
            var w = self.widgets[p.node]
            var kind = self.rt.shown.nodes[p.node].kind
            if p.op == SET_TEXT:
                if kind == TEXT:
                    _ = msg(w, "setStringValue:", ns_string(p.text))
                elif kind == FIELD:
                    if from_ns(msg(w, "stringValue")) != p.text:  # don't fight the typist
                        _ = msg(w, "setStringValue:", ns_string(p.text))
                else:  # buttons and checkboxes
                    _ = msg(w, "setTitle:", ns_string(p.text))
            elif p.op == SET_VALUE:
                if kind == TOGGLE:
                    _ = msg(w, "setState:", p.number)
                elif kind == DROPDOWN:
                    _ = msg(w, "selectItemAtIndex:", p.number)
                elif kind == SLIDER or kind == PROGRESS:
                    _ = msg(w, "setDoubleValue:", Float64(p.number))
            # SET_MSG needs nothing: events look the message up in rt.shown.

    def send(mut self, node: Int, second: Bool, text: String, number: Int, self_addr: Int):
        """A control changed: build the event, run update(), patch the controls."""
        ref n = self.rt.shown.nodes[node]
        var message = n.msg2 if second else n.msg
        if message == 0:
            return
        var d = self.rt.dispatch(Event(message, text, number))
        self.apply(d, self_addr)


def from_tag(control: Int) -> Tuple[Int, Int]:
    var tag = msg(control, "tag")
    return (tag >> NODE_BITS, tag & ((1 << NODE_BITS) - 1))


def host_at[A: App](addr: Int) -> Pointer[AppKitHost[A], MutUntrackedOrigin]:
    return Pointer[AppKitHost[A], MutUntrackedOrigin](unsafe_from_address=addr)


# ---------- MojoTarget methods (AppKit calls these) ----------

def on_tap[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    host_at[A](t[0])[].send(t[1], False, "", 0, t[0])


def on_submit[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    host_at[A](t[0])[].send(t[1], True, from_ns(msg(sender, "stringValue")), 0, t[0])


def on_text_change[A: App](target: Int, cmd: Int, notification: Int) abi("C"):
    var field = msg(notification, "object")
    var t = from_tag(field)
    host_at[A](t[0])[].send(t[1], False, from_ns(msg(field, "stringValue")), 0, t[0])


def on_toggle[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    host_at[A](t[0])[].send(t[1], False, "", msg(sender, "state"), t[0])


def on_select[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    var index = msg(sender, "indexOfSelectedItem")
    host_at[A](t[0])[].send(t[1], False, from_ns(msg(sender, "titleOfSelectedItem")), index, t[0])


def on_slide[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    var value = Int(msg[Float64](sender, "doubleValue") + 0.5)
    host_at[A](t[0])[].send(t[1], False, "", value, t[0])


def quit_when_closed(target: Int, cmd: Int, app: Int) abi("C") -> Int8:
    return 1  # YES to applicationShouldTerminateAfterLastWindowClosed:


def make_menu(app: Int, title: String):
    var bar = new("NSMenu")
    var app_item = new("NSMenuItem")
    _ = msg(bar, "addItem:", app_item)
    var app_menu = new("NSMenu")
    _ = msg(app_menu, "addItemWithTitle:action:keyEquivalent:", ns_string("Close Window"), sel("performClose:"), ns_string("w"))
    _ = msg(app_menu, "addItemWithTitle:action:keyEquivalent:", ns_string("Quit " + title), sel("terminate:"), ns_string("q"))
    _ = msg(app_item, "setSubmenu:", app_menu)
    # Edit menu: gives text fields their Cut/Copy/Paste/Select All shortcuts.
    var edit_item = new("NSMenuItem")
    _ = msg(bar, "addItem:", edit_item)
    var edit = msg(msg(cls("NSMenu"), "alloc"), "initWithTitle:", ns_string("Edit"))
    _ = msg(edit, "addItemWithTitle:action:keyEquivalent:", ns_string("Cut"), sel("cut:"), ns_string("x"))
    _ = msg(edit, "addItemWithTitle:action:keyEquivalent:", ns_string("Copy"), sel("copy:"), ns_string("c"))
    _ = msg(edit, "addItemWithTitle:action:keyEquivalent:", ns_string("Paste"), sel("paste:"), ns_string("v"))
    _ = msg(edit, "addItemWithTitle:action:keyEquivalent:", ns_string("Select All"), sel("selectAll:"), ns_string("a"))
    _ = msg(edit_item, "setSubmenu:", edit)
    _ = msg(app, "setMainMenu:", bar)


def run[A: App]() -> c_int:
    """Opens the app in a native AppKit window and runs until it's closed."""
    _ = pool_push()
    var host = alloc(Layout[AppKitHost[A]].single()).unsafe_leak()  # lives as long as the app
    host.unsafe_write(AppKitHost[A]())
    var addr = Int(host)
    if (addr >> (63 - NODE_BITS)) != 0:
        print("mojoui: can't pack host address into a control tag")
        return 1

    var app = msg(cls("NSApplication"), "sharedApplication")
    _ = msg(app, "setActivationPolicy:", 0)  # a regular app: Dock icon and menu bar
    var title = host[].rt.app.title()
    make_menu(app, title)

    var c = new_class("MojoTarget", "NSObject")
    add_method(c, "tap:", on_tap[A], "v@:@")
    add_method(c, "submit:", on_submit[A], "v@:@")
    add_method(c, "toggle:", on_toggle[A], "v@:@")
    add_method(c, "select:", on_select[A], "v@:@")
    add_method(c, "slide:", on_slide[A], "v@:@")
    add_method(c, "controlTextDidChange:", on_text_change[A], "v@:@")
    add_method(c, "applicationShouldTerminateAfterLastWindowClosed:", quit_when_closed, "B@:@")
    register_class(c)
    host[].target = msg(c, "new")
    _ = msg(app, "setDelegate:", host[].target)

    host[].window = msg(
        msg(cls("NSWindow"), "alloc"),
        "initWithContentRect:styleMask:backing:defer:",
        Float64(0), Float64(0), Float64(480), Float64(560),  # rect as 4 floats (arm64)
        1 | 2 | 4 | 8,  # titled, closable, miniaturizable, resizable
        2,  # NSBackingStoreBuffered
        0,  # defer: NO
    )
    _ = msg(host[].window, "setTitle:", ns_string(title))
    _ = msg(host[].window, "setReleasedWhenClosed:", 0)
    host[].show(addr)
    _ = msg(host[].window, "center")
    _ = msg(host[].window, "makeKeyAndOrderFront:", 0)
    _ = msg(app, "activateIgnoringOtherApps:", 1)
    _ = msg(app, "run")
    return 0
