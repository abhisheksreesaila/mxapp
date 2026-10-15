# Tiny Objective-C runtime helpers, so Mojo can drive AppKit and UIKit directly.
#
# Every Apple UI call is a message: objc_msgSend(object, selector, args...).
# Mojo can't declare one C symbol with several signatures in a module, so we
# look objc_msgSend up at runtime and call it with whatever arguments we pass.
#
# Apple Silicon only (arm64). There, a CGRect/NSRect passed by value travels in
# four float registers, exactly like four Float64 arguments, so we pass rects as
# x, y, width, height. That would be wrong on Intel Macs.
#
# Pass Objective-C BOOLs as Int 1 or 0, not Mojo Bool, so the whole register is set.

from std.ffi import OwnedDLHandle, external_call


def cls(name: String) -> Int:
    """Looks up an Objective-C class, e.g. cls("NSButton")."""
    var n = name
    return external_call["objc_getClass", Int](n.as_c_string_span())


def sel(name: String) -> Int:
    """Looks up a selector (method name), e.g. sel("setTitle:")."""
    var n = name
    return external_call["sel_registerName", Int](n.as_c_string_span())


def msg[T: RegisterPassable = Int](obj: Int, name: String) raises -> T:
    """Sends a message with no arguments: [obj name]."""
    var proc = OwnedDLHandle()
    var send = proc.get_function[T]("objc_msgSend")
    return send(obj, sel(name))


def msg[
    T: RegisterPassable = Int, A: RegisterPassable = Int
](obj: Int, name: String, a: A) raises -> T:
    """Sends a message with one argument."""
    var proc = OwnedDLHandle()
    var send = proc.get_function[T]("objc_msgSend")
    return send(obj, sel(name), a)


def msg[
    T: RegisterPassable = Int,
    A: RegisterPassable = Int,
    B: RegisterPassable = Int,
](obj: Int, name: String, a: A, b: B) raises -> T:
    """Sends a message with two arguments."""
    var proc = OwnedDLHandle()
    var send = proc.get_function[T]("objc_msgSend")
    return send(obj, sel(name), a, b)


def msg[
    T: RegisterPassable = Int,
    A: RegisterPassable = Int,
    B: RegisterPassable = Int,
    C: RegisterPassable = Int,
](obj: Int, name: String, a: A, b: B, c: C) raises -> T:
    """Sends a message with three arguments."""
    var proc = OwnedDLHandle()
    var send = proc.get_function[T]("objc_msgSend")
    return send(obj, sel(name), a, b, c)


def msg_rect[
    T: RegisterPassable = Int
](
    obj: Int,
    name: String,
    x: Float64,
    y: Float64,
    w: Float64,
    h: Float64,
) raises -> T:
    """Sends a message whose only argument is a rect, e.g. initWithFrame:."""
    var proc = OwnedDLHandle()
    var send = proc.get_function[T]("objc_msgSend")
    return send(obj, sel(name), x, y, w, h)


def ns_string(text: String) raises -> Int:
    """Makes an NSString from a Mojo String (UTF-8, no copy of the terminator needed)."""
    comptime UTF8 = 4  # NSUTF8StringEncoding
    var s = msg(cls("NSString"), "alloc")
    s = msg(s, "initWithBytes:length:encoding:", Int(text.unsafe_ptr()), text.byte_length(), UTF8)
    return msg(s, "autorelease")


def new_class(name: String, superclass: String) -> Int:
    """Creates (but doesn't register yet) a new Objective-C class at runtime."""
    var n = name
    return external_call["objc_allocateClassPair", Int](cls(superclass), n.as_c_string_span(), 0)


def register_class(c: Int):
    external_call["objc_registerClassPair", NoneType](c)


def pool_push() -> Int:
    return external_call["objc_autoreleasePoolPush", Int]()


def pool_pop(p: Int):
    external_call["objc_autoreleasePoolPop", NoneType](p)
