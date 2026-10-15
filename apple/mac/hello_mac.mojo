# HelloMojo for macOS: a native AppKit window built entirely from Mojo.
#
# No Swift, no C, no Objective-C: Mojo talks to AppKit through the Objective-C
# runtime (see apple/objc.mojo). Build: apple/build.sh mac (see apple/README.md).

from std.ffi import c_int
from std.memory import Pointer
from std.memory.alloc import alloc, Layout

from hello_core import Hello, greet
from objc import cls, sel, msg, new, ns_string, new_class, add_method, register_class, pool_push


@fieldwise_init
struct Screen(Copyable, Movable):
    """What the Greet handler needs: the app logic plus the label it updates."""

    var hello: Hello
    var label: Int  # NSTextField


def on_greet(target: Int, cmd: Int, button: Int) abi("C"):
    """AppKit calls this when Greet is clicked. The button's tag holds our state."""
    var screen = Pointer[Screen, MutUntrackedOrigin](unsafe_from_address=msg(button, "tag"))
    var text = greet(screen[].hello)
    _ = msg(screen[].label, "setStringValue:", ns_string(text))


def quit_when_closed(target: Int, cmd: Int, app: Int) abi("C") -> Int8:
    """Answers YES to applicationShouldTerminateAfterLastWindowClosed:."""
    return 1  # Objective-C BOOL is a signed char


def make_handler() -> Int:
    """An Objective-C object, MojoHandler, whose methods are the Mojo functions above."""
    var c = new_class("MojoHandler", "NSObject")
    add_method(c, "greet:", on_greet, "v@:@")
    add_method(c, "applicationShouldTerminateAfterLastWindowClosed:", quit_when_closed, "B@:@")
    register_class(c)
    return msg(c, "new")


def make_menu(app: Int):
    """A minimal menu bar so Cmd+W and Cmd+Q work."""
    var bar = new("NSMenu")
    var app_item = new("NSMenuItem")
    _ = msg(bar, "addItem:", app_item)
    var app_menu = new("NSMenu")
    _ = msg(
        app_menu,
        "addItemWithTitle:action:keyEquivalent:",
        ns_string("Close Window"),
        sel("performClose:"),
        ns_string("w"),
    )
    _ = msg(
        app_menu,
        "addItemWithTitle:action:keyEquivalent:",
        ns_string("Quit HelloMojo"),
        sel("terminate:"),
        ns_string("q"),
    )
    _ = msg(app_item, "setSubmenu:", app_menu)
    _ = msg(app, "setMainMenu:", bar)


def label(text: String, size: Float64, bold: Bool = False) -> Int:
    var field = msg(cls("NSTextField"), "labelWithString:", ns_string(text))
    var font_name = "boldSystemFontOfSize:" if bold else "systemFontOfSize:"
    _ = msg(field, "setFont:", msg(cls("NSFont"), font_name, size))
    return field


@export("mojo_entry")
def entry(argc: c_int, argv: Int) abi("C") -> c_int:
    """The app starts here: the linker's `-e _mojo_entry` points macOS at it."""
    _ = pool_push()
    var app = msg(cls("NSApplication"), "sharedApplication")
    _ = msg(app, "setActivationPolicy:", 0)  # a regular app: Dock icon and menu bar
    make_menu(app)
    var handler = make_handler()
    _ = msg(app, "setDelegate:", handler)

    # Window: titled | closable | miniaturizable | resizable; rect as 4 floats.
    var window = msg(
        msg(cls("NSWindow"), "alloc"),
        "initWithContentRect:styleMask:backing:defer:",
        Float64(0), Float64(0), Float64(460), Float64(280),
        1 | 2 | 4 | 8,
        2,  # NSBackingStoreBuffered
        0,  # defer: NO
    )
    _ = msg(window, "setTitle:", ns_string("HelloMojo"))
    _ = msg(window, "setReleasedWhenClosed:", 0)

    var greeting = label("Tap Greet", 22.0)
    var screen = alloc(Layout[Screen].single()).unsafe_leak()  # lives as long as the app
    screen.unsafe_write(Screen(Hello("Ada", 0), greeting))

    var button = msg(
        cls("NSButton"), "buttonWithTitle:target:action:", ns_string("Greet"), handler, sel("greet:")
    )
    _ = msg(button, "setTag:", Int(screen))
    _ = msg(button, "setKeyEquivalent:", ns_string("\r"))  # Return clicks it too
    _ = msg(button, "setControlSize:", 3)  # NSControlSizeLarge

    var stack = new("NSStackView")
    _ = msg(stack, "setOrientation:", 1)  # vertical
    _ = msg(stack, "setAlignment:", 9)  # NSLayoutAttributeCenterX
    _ = msg(stack, "setSpacing:", Float64(18))
    _ = msg(stack, "setEdgeInsets:", Float64(32), Float64(32), Float64(32), Float64(32))
    _ = msg(stack, "addArrangedSubview:", label("mojo-ui · hello", 13.0, bold=True))
    _ = msg(stack, "addArrangedSubview:", greeting)
    _ = msg(stack, "addArrangedSubview:", button)
    _ = msg(stack, "addArrangedSubview:", label("Every line of this app is Mojo.", 11.0))
    _ = msg(window, "setContentView:", stack)

    _ = msg(window, "center")
    _ = msg(window, "makeKeyAndOrderFront:", 0)
    _ = msg(app, "activateIgnoringOtherApps:", 1)
    _ = msg(app, "run")
    return 0
