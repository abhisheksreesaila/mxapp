# HelloMojo for iPhone: a native UIKit screen built entirely from Mojo.
#
# No Swift, no C, no Objective-C: Mojo talks to UIKit through the Objective-C
# runtime (see apple/objc.mojo). Build: apple/build.sh ios (see apple/README.md).
#
# Startup: UIApplicationMain → MojoAppDelegate → the scene from Info.plist's
# scene manifest → MojoSceneDelegate.scene:willConnectToSession:options:,
# which builds the window. All three classes are created here at run time.

from std.ffi import external_call, c_int
from std.memory import Pointer
from std.memory.alloc import alloc, Layout

from hello_core import Hello, greet
from objc import cls, sel, msg, new, ns_string, new_class, add_method, add_protocol, register_class, pool_push


@fieldwise_init
struct Screen(Copyable, Movable):
    """What the Greet handler needs: the app logic plus the label it updates."""

    var hello: Hello
    var label: Int  # UILabel


def on_greet(target: Int, cmd: Int, button: Int) abi("C"):
    """UIKit calls this when Greet is tapped. The button's tag holds our state."""
    var screen = Pointer[Screen, MutUntrackedOrigin](unsafe_from_address=msg(button, "tag"))
    var text = greet(screen[].hello)
    _ = msg(screen[].label, "setText:", ns_string(text))


def did_finish_launching(target: Int, cmd: Int, app: Int, options: Int) abi("C") -> Int8:
    """Answers YES to application:didFinishLaunchingWithOptions:. The scene builds the UI."""
    return 1


def label(text: String, size: Float64, bold: Bool = False) -> Int:
    var l = new("UILabel")
    _ = msg(l, "setText:", ns_string(text))
    var font_name = "boldSystemFontOfSize:" if bold else "systemFontOfSize:"
    _ = msg(l, "setFont:", msg(cls("UIFont"), font_name, size))
    _ = msg(l, "setTextAlignment:", 1)  # NSTextAlignmentCenter
    _ = msg(l, "setNumberOfLines:", 0)
    return l


def greet_button(target: Int, screen: Int) -> Int:
    """A large button: Liquid Glass on iOS 26+, a filled button before that."""
    var config_cls = cls("UIButtonConfiguration")
    var glass = msg[Int8](config_cls, "respondsToSelector:", sel("prominentGlassButtonConfiguration"))
    var config = msg(config_cls, "prominentGlassButtonConfiguration" if glass else "filledButtonConfiguration")
    _ = msg(config, "setTitle:", ns_string("Greet"))
    _ = msg(config, "setButtonSize:", 3)  # UIButtonConfigurationSizeLarge
    _ = msg(config, "setCornerStyle:", 4)  # UIButtonConfigurationCornerStyleCapsule
    var button = msg(cls("UIButton"), "buttonWithConfiguration:primaryAction:", config, 0)
    _ = msg(button, "addTarget:action:forControlEvents:", target, sel("greet:"), 1 << 6)  # touch up inside
    _ = msg(button, "setTag:", screen)
    return button


def pin_center(view: Int, inside: Int):
    """Auto Layout: centre `view` in `inside`, at most its width minus margins."""
    _ = msg(view, "setTranslatesAutoresizingMaskIntoConstraints:", 0)
    for anchor in ["centerXAnchor", "centerYAnchor"]:
        var c = msg(msg(view, anchor), "constraintEqualToAnchor:", msg(inside, anchor))
        _ = msg(c, "setActive:", 1)
    var w = msg(
        msg(view, "widthAnchor"),
        "constraintLessThanOrEqualToAnchor:constant:",
        msg(inside, "widthAnchor"),
        Float64(-48),
    )
    _ = msg(w, "setActive:", 1)


def scene_will_connect(delegate: Int, cmd: Int, scene: Int, session: Int, options: Int) abi("C"):
    """Builds the window and screen when UIKit calls scene:willConnectToSession:options:."""
    var window = msg(msg(cls("UIWindow"), "alloc"), "initWithWindowScene:", scene)  # kept for the app's life
    var controller = new("UIViewController")
    var view = msg(controller, "view")
    _ = msg(view, "setBackgroundColor:", msg(cls("UIColor"), "systemBackgroundColor"))

    var greeting = label("Tap Greet", 28.0, bold=True)
    var screen = alloc(Layout[Screen].single()).unsafe_leak()  # lives as long as the app
    screen.unsafe_write(Screen(Hello("Ada", 0), greeting))

    var stack = new("UIStackView")
    _ = msg(stack, "setAxis:", 1)  # vertical
    _ = msg(stack, "setAlignment:", 3)  # centre
    _ = msg(stack, "setSpacing:", Float64(24))
    _ = msg(stack, "addArrangedSubview:", label("mojo-ui · hello", 15.0))
    _ = msg(stack, "addArrangedSubview:", greeting)
    _ = msg(stack, "addArrangedSubview:", greet_button(delegate, Int(screen)))
    _ = msg(stack, "addArrangedSubview:", label("Every line of this app is Mojo.", 13.0))
    _ = msg(view, "addSubview:", stack)
    pin_center(stack, view)

    _ = msg(window, "setRootViewController:", controller)
    _ = msg(window, "makeKeyAndVisible")


def register_delegates():
    var app_delegate = new_class("MojoAppDelegate", "UIResponder")
    add_protocol(app_delegate, "UIApplicationDelegate")
    add_method(app_delegate, "application:didFinishLaunchingWithOptions:", did_finish_launching, "c@:@@")
    register_class(app_delegate)

    var scene_delegate = new_class("MojoSceneDelegate", "UIResponder")
    add_protocol(scene_delegate, "UIWindowSceneDelegate")
    add_method(scene_delegate, "scene:willConnectToSession:options:", scene_will_connect, "v@:@@@")
    add_method(scene_delegate, "greet:", on_greet, "v@:@")
    register_class(scene_delegate)


@export("mojo_entry")
def entry(argc: c_int, argv: Int) abi("C") -> c_int:
    """The app starts here: the linker's `-e _mojo_entry` points iOS at it."""
    _ = pool_push()
    register_delegates()
    return external_call["UIApplicationMain", c_int](argc, argv, 0, ns_string("MojoAppDelegate"))
