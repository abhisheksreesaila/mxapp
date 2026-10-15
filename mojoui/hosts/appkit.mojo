# Mac host: draws a mojoui View with real AppKit controls.
#
# Taps: each NSButton's tag packs the host's address and the node index
# ((host << 16) | node), so the one Mojo tap handler knows where to go
# without global variables or extra Objective-C runtime calls.

from std.ffi import c_int
from std.memory import Pointer
from std.memory.alloc import alloc, Layout

from mojoui.view import TEXT, BUTTON, VSTACK, HSTACK, SPACER, TITLE, HEADLINE, CAPTION, PROMINENT
from mojoui.diff import Diff, SET_TEXT
from mojoui.app import App, Runtime
from mojoui.hosts.objc import cls, sel, msg, new, ns_string, new_class, add_method, register_class, pool_push

comptime NODE_BITS = 16


struct AppKitHost[A: App](Movable):
    var rt: Runtime[Self.A]
    var window: Int
    var target: Int  # MojoTarget object that receives every tap
    var widgets: List[Int]

    def __init__(out self):
        self.rt = Runtime(Self.A())
        self.window = 0
        self.target = 0
        self.widgets = List[Int]()

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
            _ = msg(w, "setTag:", (self_addr << NODE_BITS) | i)
            if node.style == PROMINENT:
                _ = msg(w, "setKeyEquivalent:", ns_string("\r"))  # the blue default button; Return taps it
                _ = msg(w, "setControlSize:", 3)  # NSControlSizeLarge
        elif node.kind == SPACER:
            w = new("NSView")
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
        # Old controls are deliberately never released: that keeps a tapped button
        # alive while its window content is replaced in the middle of its own action.
        # (Adding `release` later means delaying it until the tap handler returns.)
        if len(self.rt.shown.nodes) >= (1 << NODE_BITS):
            print("mojoui: screen has", len(self.rt.shown.nodes), "nodes; the limit is 65535")
            return
        self.widgets = List[Int](length=len(self.rt.shown.nodes), fill=0)
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
            if p.op == SET_TEXT:
                var w = self.widgets[p.node]
                var setter = "setStringValue:" if self.rt.shown.nodes[p.node].kind == TEXT else "setTitle:"
                _ = msg(w, setter, ns_string(p.text))


def on_tap[A: App](target: Int, cmd: Int, button: Int) abi("C"):
    """AppKit calls this for every button: run update(), then patch the controls."""
    var tag = msg(button, "tag")
    var host_addr = tag >> NODE_BITS
    var node = tag & ((1 << NODE_BITS) - 1)
    var host = Pointer[AppKitHost[A], MutUntrackedOrigin](unsafe_from_address=host_addr)
    var d = host[].rt.dispatch(host[].rt.shown.nodes[node].msg)
    host[].apply(d, host_addr)


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
    _ = msg(app, "setMainMenu:", bar)


def run[A: App]() -> c_int:
    """Opens the app in a native AppKit window and runs until it's closed."""
    _ = pool_push()
    var host = alloc(Layout[AppKitHost[A]].single()).unsafe_leak()  # lives as long as the app
    host.unsafe_write(AppKitHost[A]())
    var addr = Int(host)
    if (addr >> (63 - NODE_BITS)) != 0:
        print("mojoui: can't pack host address into a button tag")
        return 1

    var app = msg(cls("NSApplication"), "sharedApplication")
    _ = msg(app, "setActivationPolicy:", 0)  # a regular app: Dock icon and menu bar
    var title = host[].rt.app.title()
    make_menu(app, title)

    var c = new_class("MojoTarget", "NSObject")
    add_method(c, "tap:", on_tap[A], "v@:@")
    add_method(c, "applicationShouldTerminateAfterLastWindowClosed:", quit_when_closed, "B@:@")
    register_class(c)
    host[].target = msg(c, "new")
    _ = msg(app, "setDelegate:", host[].target)

    host[].window = msg(
        msg(cls("NSWindow"), "alloc"),
        "initWithContentRect:styleMask:backing:defer:",
        Float64(0), Float64(0), Float64(480), Float64(360),  # rect as 4 floats (arm64)
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
