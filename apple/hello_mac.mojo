# HelloMojo for macOS: a native AppKit window built entirely from Mojo.
#
# Build and run on an Apple Silicon Mac (see apple/README.md):
#   ./apple/build_mac.sh && open build/HelloMojo.app

from std.ffi import OwnedDLHandle, external_call
from std.memory import Pointer
from std.memory.alloc import alloc, Layout

from hello_core import Hello, greet
from objc import cls, sel, msg, msg_rect, ns_string, new_class, register_class, pool_push

# The heap state the button handler needs: app logic plus the label to update.
@fieldwise_init
struct Screen(Copyable, Movable):
    var hello: Hello
    var label: Int  # NSTextField


def on_greet(target: Int, cmd: Int, sender: Int) abi("C"):
    """Called by AppKit when Greet is clicked. The button's tag holds our state."""
    try:
        var addr = msg(sender, "tag")
        var screen = Pointer[Screen, MutUntrackedOrigin](unsafe_from_address=addr)
        var text = greet(screen[].hello)
        _ = msg(screen[].label, "setStringValue:", ns_string(text))
    except e:
        print("on_greet failed:", e)


def quit_when_closed(target: Int, cmd: Int, app: Int) abi("C") -> Int8:
    """Answers YES to applicationShouldTerminateAfterLastWindowClosed:."""
    return 1  # Objective-C BOOL is a signed char


def make_handler_class() -> Int:
    """A tiny Objective-C class, MojoHandler, whose methods are Mojo functions."""
    var c = new_class("MojoHandler", "NSObject")
    var greet_types = String("v@:@")
    var bool_types = String("c@:@")
    _ = external_call["class_addMethod", Bool](
        c, sel("greet:"), on_greet, greet_types.as_c_string_span()
    )
    _ = external_call["class_addMethod", Bool](
        c,
        sel("applicationShouldTerminateAfterLastWindowClosed:"),
        quit_when_closed,
        bool_types.as_c_string_span(),
    )
    register_class(c)
    return c


def make_menu(app: Int) raises:
    """A minimal menu bar so Cmd+Q works."""
    var bar = msg(cls("NSMenu"), "new")
    var app_item = msg(cls("NSMenuItem"), "new")
    _ = msg(bar, "addItem:", app_item)
    var app_menu = msg(cls("NSMenu"), "new")
    _ = msg(
        app_menu,
        "addItemWithTitle:action:keyEquivalent:",
        ns_string("Quit HelloMojo"),
        sel("terminate:"),
        ns_string("q"),
    )
    _ = msg(app_item, "setSubmenu:", app_menu)
    _ = msg(app, "setMainMenu:", bar)


def main() raises:
    _ = pool_push()
    var app = msg(cls("NSApplication"), "sharedApplication")
    _ = msg(app, "setActivationPolicy:", 0)  # Regular app: Dock icon + menu bar
    make_menu(app)

    var handler = msg(make_handler_class(), "new")
    _ = msg(app, "setDelegate:", handler)

    # Window: titled | closable | miniaturizable | resizable.
    comptime STYLE = 1 | 2 | 4 | 8
    var window = msg(cls("NSWindow"), "alloc")
    var proc = OwnedDLHandle()
    var init_window = proc.get_function[Int]("objc_msgSend")
    window = init_window(
        window,
        sel("initWithContentRect:styleMask:backing:defer:"),
        Float64(0), Float64(0), Float64(420), Float64(240),  # rect
        STYLE,
        2,  # NSBackingStoreBuffered
        0,  # defer: NO
    )
    _ = msg(window, "setTitle:", ns_string("HelloMojo"))
    _ = msg(window, "setReleasedWhenClosed:", 0)

    var title = msg(cls("NSTextField"), "labelWithString:", ns_string("mojo-ui · hello"))
    _ = msg(title, "setFont:", msg[Int, Float64](cls("NSFont"), "boldSystemFontOfSize:", 20.0))
    var label = msg(cls("NSTextField"), "labelWithString:", ns_string("Tap Greet"))
    _ = msg(label, "setFont:", msg[Int, Float64](cls("NSFont"), "systemFontOfSize:", 17.0))
    var footer = msg(cls("NSTextField"), "labelWithString:", ns_string("Everything here is Mojo."))

    # State lives on the heap; the button's tag carries its address.
    var allocation = alloc(Layout[Screen].single())
    var screen = allocation^.unsafe_leak()
    screen.unsafe_write(Screen(Hello("Ada", 0), label))

    var button = msg(
        cls("NSButton"),
        "buttonWithTitle:target:action:",
        ns_string("Greet"),
        handler,
        sel("greet:"),
    )
    _ = msg(button, "setTag:", Int(screen))
    _ = msg(button, "setKeyEquivalent:", ns_string("\r"))  # Return key clicks it

    var stack = msg(cls("NSStackView"), "new")
    _ = msg(stack, "setOrientation:", 1)  # vertical
    _ = msg[Int, Float64](stack, "setSpacing:", 16.0)
    _ = msg(stack, "addArrangedSubview:", title)
    _ = msg(stack, "addArrangedSubview:", label)
    _ = msg(stack, "addArrangedSubview:", button)
    _ = msg(stack, "addArrangedSubview:", footer)
    _ = msg(window, "setContentView:", stack)

    _ = msg(window, "center")
    _ = msg(window, "makeKeyAndOrderFront:", 0)
    _ = msg(app, "activateIgnoringOtherApps:", 1)
    _ = msg(app, "run")
