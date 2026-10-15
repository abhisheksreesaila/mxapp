# Tiny Objective-C runtime helpers, so Mojo can drive AppKit and UIKit directly.
#
# Every Apple UI call is a message: objc_msgSend(object, selector, args...).
# Mojo can't declare one C symbol with several signatures in a module, so we
# look objc_msgSend's address up once per call and cast it to the exact C
# signature of that call: msg(button, "setTag:", 42), msg[Float64](view, "alpha").
#
# Apple Silicon only (arm64). There, a CGRect/NSRect (or edge insets) passed by
# value travels in four float registers, exactly like four Float64 arguments,
# so we pass rects as x, y, width, height. That would be wrong on Intel Macs.
#
# Pass Objective-C BOOLs as Int 1 or 0, not Mojo Bool, so the whole register is set.

from std.ffi import external_call

comptime RTLD_DEFAULT = -2  # Apple's "search every loaded library" handle


def cls(name: String) -> Int:
    """Looks up an Objective-C class, e.g. cls("NSButton")."""
    var n = name
    return external_call["objc_getClass", Int](n.as_c_string_span())


def sel(name: String) -> Int:
    """Looks up a selector (method name), e.g. sel("setTitle:")."""
    var n = name
    return external_call["sel_registerName", Int](n.as_c_string_span())


def protocol(name: String) -> Int:
    var n = name
    return external_call["objc_getProtocol", Int](n.as_c_string_span())


def msg[T: RegisterPassable = Int, *A: AnyType](obj: Int, name: String, *args: *A) -> T:
    """Sends a message: [obj name:args...]. T is the C return type (default: an object/Int)."""
    var fn_name = String("objc_msgSend")
    var addr = external_call["dlsym", Int](RTLD_DEFAULT, fn_name.as_c_string_span())
    var raw = Pointer[NoneType, MutUntrackedOrigin](unsafe_from_address=addr)
    var send = Pointer(to=raw).unsafe_bitcast[
        def(o: Int, s: Int, *a: *A) thin abi("C") -> T
    ]()[]
    return send(obj, sel(name), *args)


def new(class_name: String) -> Int:
    """[[Class alloc] init], e.g. new("NSStackView")."""
    return msg(cls(class_name), "new")


def ns_string(text: String) -> Int:
    """Makes an NSString from a Mojo String (UTF-8; no terminator needed)."""
    comptime UTF8 = 4  # NSUTF8StringEncoding
    var s = msg(cls("NSString"), "alloc")
    s = msg(s, "initWithBytes:length:encoding:", Int(text.unsafe_ptr()), text.byte_length(), UTF8)
    return msg(s, "autorelease")


def new_class(name: String, superclass: String) -> Int:
    """Creates (but doesn't register yet) a new Objective-C class at runtime."""
    var n = name
    return external_call["objc_allocateClassPair", Int](cls(superclass), n.as_c_string_span(), 0)


def add_method[F: AnyType](c: Int, selector: String, imp: F, types: String):
    """Adds a method whose body is a Mojo `abi("C")` function.

    `types` is the Objective-C type encoding, e.g. "v@:@" = returns void, takes (self, _cmd, id).
    """
    var t = types
    _ = external_call["class_addMethod", Int8](c, sel(selector), imp, t.as_c_string_span())


def add_protocol(c: Int, name: String):
    var p = protocol(name)
    if p != 0:  # unknown protocol: skip rather than add a null entry
        _ = external_call["class_addProtocol", Int8](c, p)


def register_class(c: Int):
    external_call["objc_registerClassPair", NoneType](c)


def pool_push() -> Int:
    return external_call["objc_autoreleasePoolPush", Int]()
