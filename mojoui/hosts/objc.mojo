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
from std.memory import Pointer
from std.memory.alloc import unsafe_alloc

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
    if p == 0:  # never add a null entry; say so, since UIKit may then reject the class
        print("mojo-ui: Objective-C protocol not found:", name)
        return
    _ = external_call["class_addProtocol", Int8](c, p)


def register_class(c: Int):
    external_call["objc_registerClassPair", NoneType](c)


def pool_push() -> Int:
    return external_call["objc_autoreleasePoolPush", Int]()


def from_ns(ns: Int) -> String:
    """Copies an NSString into a Mojo String (via its UTF-8 bytes)."""
    if ns == 0:
        return ""
    var utf8 = msg(ns, "UTF8String")
    if utf8 == 0:
        return ""
    return String(unsafe_from_utf8_ptr=Pointer[Int8, MutUntrackedOrigin](unsafe_from_address=utf8))


def constrain(view: Int, anchor: String, points: Float64):
    """Auto Layout: fix a view's width or height (anchor = "widthAnchor"/"heightAnchor")."""
    var c = msg(msg(view, anchor), "constraintEqualToConstant:", points)
    _ = msg(c, "setActive:", 1)


def fn_address[F: ImplicitlyCopyable & Deinitable](f: F) -> Int:
    """The machine address of a Mojo `abi("C")` function."""
    var copy = f
    return Pointer(to=copy).unsafe_bitcast[Int]()[]


def global_block[F: ImplicitlyCopyable & Deinitable](invoke: F, signature: String) -> Int:
    """An Objective-C block whose body is a Mojo `abi("C")` function.

    Built by hand as a *global* block (the kind the compiler emits for blocks that
    capture nothing): {isa, flags+reserved, invoke, descriptor} (32 bytes) with a descriptor
    {reserved, size, signature}. Copying a global block returns it unchanged, so
    APIs that keep the block (like UIAction's handler) are safe. It lives forever.
    `invoke` must take the block itself first, then the block's arguments.
    """
    comptime BLOCK_IS_GLOBAL = 1 << 28
    comptime BLOCK_HAS_SIGNATURE = 1 << 30
    var isa_name = String("_NSConcreteGlobalBlock")
    var isa = external_call["dlsym", Int](RTLD_DEFAULT, isa_name.as_c_string_span())
    var sig = unsafe_alloc[Int8](signature.byte_length() + 1)  # C string, kept forever
    for i in range(signature.byte_length()):
        sig.unsafe_offset(i).unsafe_write(Int8(signature.as_bytes()[i]))
    sig.unsafe_offset(signature.byte_length()).unsafe_write(Int8(0))
    var desc = unsafe_alloc[Int](3)
    desc.unsafe_write(0)  # reserved
    desc.unsafe_offset(1).unsafe_write(32)  # sizeof the block literal
    desc.unsafe_offset(2).unsafe_write(Int(sig))
    var block = unsafe_alloc[Int](4)
    block.unsafe_write(isa)
    block.unsafe_offset(1).unsafe_write(BLOCK_IS_GLOBAL | BLOCK_HAS_SIGNATURE)  # flags (low 32 bits), reserved = 0
    block.unsafe_offset(2).unsafe_write(fn_address(invoke))
    block.unsafe_offset(3).unsafe_write(Int(desc))
    return Int(block)
