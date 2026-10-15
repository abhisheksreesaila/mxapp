# iPhone host: draws a mojoui View with real UIKit controls.
#
# Start-up: UIApplicationMain → MojoAppDelegate → the scene from Info.plist →
# MojoSceneDelegate.scene:willConnectToSession:options:, which creates the app
# (A()) and its window. Taps: each UIButton's tag packs the host's address and
# the node index, as on the Mac.

from std.ffi import external_call, c_int
from std.memory import Pointer
from std.memory.alloc import alloc, Layout

from mojoui.view import TEXT, BUTTON, VSTACK, HSTACK, SPACER, TITLE, HEADLINE, CAPTION, PROMINENT
from mojoui.diff import Diff, SET_TEXT
from mojoui.app import App, Runtime
from mojoui.hosts.objc import (
    cls, sel, msg, new, ns_string, new_class, add_method, add_protocol, register_class, pool_push,
)

comptime NODE_BITS = 16


struct UIKitHost[A: App](Movable):
    var rt: Runtime[Self.A]
    var window: Int
    var view: Int  # the root view controller's view
    var root: Int  # our top stack view inside it
    var target: Int  # the scene delegate, which receives every tap
    var widgets: List[Int]

    def __init__(out self):
        self.rt = Runtime(Self.A())
        self.window = 0
        self.view = 0
        self.root = 0
        self.target = 0
        self.widgets = List[Int]()

    def build(mut self, i: Int, self_addr: Int) -> Int:
        var node = self.rt.shown.nodes[i].copy()  # copy: building children mutates self
        var w: Int
        if node.kind == TEXT:
            w = new("UILabel")
            _ = msg(w, "setText:", ns_string(node.text))
            var style = "UICTFontTextStyleBody"  # Dynamic Type: follows the user's text size
            if node.style == TITLE:
                style = "UICTFontTextStyleTitle0"  # large title
            elif node.style == HEADLINE:
                style = "UICTFontTextStyleHeadline"
            elif node.style == CAPTION:
                style = "UICTFontTextStyleFootnote"
                _ = msg(w, "setTextColor:", msg(cls("UIColor"), "secondaryLabelColor"))
            _ = msg(w, "setFont:", msg(cls("UIFont"), "preferredFontForTextStyle:", ns_string(style)))
            _ = msg(w, "setAdjustsFontForContentSizeCategory:", 1)
            _ = msg(w, "setTextAlignment:", 1)  # centre
            _ = msg(w, "setNumberOfLines:", 0)
        elif node.kind == BUTTON:
            w = make_button(node.text, node.style == PROMINENT)
            _ = msg(w, "addTarget:action:forControlEvents:", self.target, sel("tap:"), 1 << 6)  # touch up inside
            _ = msg(w, "setTag:", (self_addr << NODE_BITS) | i)
        elif node.kind == SPACER:
            w = new("UIView")
        else:
            w = new("UIStackView")
            _ = msg(w, "setAxis:", 1 if node.kind == VSTACK else 0)
            _ = msg(w, "setAlignment:", 3)  # centre
            _ = msg(w, "setSpacing:", Float64(node.spacing))
            for c in node.children:
                _ = msg(w, "addArrangedSubview:", self.build(c, self_addr))
        self.widgets[i] = w
        return w

    def show(mut self, self_addr: Int):
        # Old controls are deliberately never released: that keeps a tapped button
        # alive while the screen is replaced in the middle of its own action.
        if len(self.rt.shown.nodes) >= (1 << NODE_BITS):
            print("mojoui: screen has", len(self.rt.shown.nodes), "nodes; the limit is 65535")
            return
        if self.root != 0:
            _ = msg(self.root, "removeFromSuperview")
        self.widgets = List[Int](length=len(self.rt.shown.nodes), fill=0)
        self.root = self.build(0, self_addr)
        _ = msg(self.view, "addSubview:", self.root)
        pin_center(self.root, self.view)

    def apply(mut self, d: Diff, self_addr: Int):
        if d.rebuild:
            self.show(self_addr)
            return
        for p in d.patches:
            if p.op == SET_TEXT:
                var w = self.widgets[p.node]
                if self.rt.shown.nodes[p.node].kind == TEXT:
                    _ = msg(w, "setText:", ns_string(p.text))
                else:
                    var config = msg(msg(w, "configuration"), "copy")
                    _ = msg(config, "setTitle:", ns_string(p.text))
                    _ = msg(w, "setConfiguration:", config)


def make_button(title: String, prominent: Bool) -> Int:
    """Liquid Glass on iOS 26+, filled/gray buttons before that."""
    var config_cls = cls("UIButtonConfiguration")
    var glass = msg[Int8](config_cls, "respondsToSelector:", sel("prominentGlassButtonConfiguration")) != 0
    var maker: String
    if prominent:
        maker = "prominentGlassButtonConfiguration" if glass else "filledButtonConfiguration"
    else:
        maker = "glassButtonConfiguration" if glass else "grayButtonConfiguration"
    var config = msg(config_cls, maker)
    _ = msg(config, "setTitle:", ns_string(title))
    _ = msg(config, "setButtonSize:", 3)  # large: comfortable touch targets for every button
    _ = msg(config, "setCornerStyle:", 4)  # capsule
    return msg(cls("UIButton"), "buttonWithConfiguration:primaryAction:", config, 0)


def pin_center(view: Int, inside: Int):
    """Auto Layout: centre `view` in the safe area (clear of the Dynamic Island and
    home indicator), at most its width minus margins."""
    var guide = msg(inside, "safeAreaLayoutGuide")
    _ = msg(view, "setTranslatesAutoresizingMaskIntoConstraints:", 0)
    for anchor in ["centerXAnchor", "centerYAnchor"]:
        var c = msg(msg(view, anchor), "constraintEqualToAnchor:", msg(guide, anchor))
        _ = msg(c, "setActive:", 1)
    var w = msg(
        msg(view, "widthAnchor"), "constraintLessThanOrEqualToAnchor:constant:", msg(guide, "widthAnchor"), Float64(-48)
    )
    _ = msg(w, "setActive:", 1)
    var h = msg(msg(view, "heightAnchor"), "constraintLessThanOrEqualToAnchor:", msg(guide, "heightAnchor"))
    _ = msg(h, "setActive:", 1)


def on_tap[A: App](target: Int, cmd: Int, button: Int) abi("C"):
    """UIKit calls this for every button: run update(), then patch the controls."""
    var tag = msg(button, "tag")
    var host_addr = tag >> NODE_BITS
    var node = tag & ((1 << NODE_BITS) - 1)
    var host = Pointer[UIKitHost[A], MutUntrackedOrigin](unsafe_from_address=host_addr)
    var d = host[].rt.dispatch(host[].rt.shown.nodes[node].msg)
    host[].apply(d, host_addr)


def did_finish_launching(target: Int, cmd: Int, app: Int, options: Int) abi("C") -> Int8:
    return 1  # YES; the scene builds the UI


def scene_will_connect[A: App](delegate: Int, cmd: Int, scene: Int, session: Int, options: Int) abi("C"):
    """Creates the app and its window when UIKit connects the scene."""
    var host = alloc(Layout[UIKitHost[A]].single()).unsafe_leak()  # lives as long as the app
    host.unsafe_write(UIKitHost[A]())
    var addr = Int(host)
    if (addr >> (63 - NODE_BITS)) != 0:
        print("mojoui: can't pack host address into a button tag")
        return
    host[].target = delegate
    host[].window = msg(msg(cls("UIWindow"), "alloc"), "initWithWindowScene:", scene)  # kept for the app's life
    var controller = new("UIViewController")
    host[].view = msg(controller, "view")
    _ = msg(host[].view, "setBackgroundColor:", msg(cls("UIColor"), "systemBackgroundColor"))
    host[].show(addr)
    _ = msg(host[].window, "setRootViewController:", controller)
    _ = msg(host[].window, "makeKeyAndVisible")


def run[A: App](argc: c_int, argv: Int) -> c_int:
    """Starts UIKit; the scene delegate then creates the app. Never returns."""
    _ = pool_push()
    var app_delegate = new_class("MojoAppDelegate", "UIResponder")
    add_protocol(app_delegate, "UIApplicationDelegate")
    add_method(app_delegate, "application:didFinishLaunchingWithOptions:", did_finish_launching, "B@:@@")
    register_class(app_delegate)

    var scene_delegate = new_class("MojoSceneDelegate", "UIResponder")
    add_protocol(scene_delegate, "UIWindowSceneDelegate")
    add_method(scene_delegate, "scene:willConnectToSession:options:", scene_will_connect[A], "v@:@@@")
    add_method(scene_delegate, "tap:", on_tap[A], "v@:@")
    register_class(scene_delegate)
    return external_call["UIApplicationMain", c_int](argc, argv, 0, ns_string("MojoAppDelegate"))
