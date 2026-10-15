# Tiny JNI helpers, so Mojo can drive Android's own views directly.
#
# JNI is Java's C interface. Every native call gets a JNIEnv: a pointer to a table of
# functions (FindClass, NewObjectA, CallVoidMethodA…). We call them by their slot in that
# table, cast to the exact C signature of each call: the same trick as objc.mojo's msg().
# Method arguments go in a jvalue array (8 bytes each), the non-variadic "…A" functions.
#
# Slots are from the JDK's include/jni.h (struct JNINativeInterface_), which every
# Android release keeps unchanged.

from std.ffi import external_call, c_int
from std.memory import Pointer, bitcast

comptime FIND_CLASS = 6
comptime EXCEPTION_DESCRIBE = 16
comptime EXCEPTION_CLEAR = 17
comptime NEW_GLOBAL_REF = 21
comptime DELETE_GLOBAL_REF = 22
comptime DELETE_LOCAL_REF = 23
comptime NEW_OBJECT_A = 30
comptime GET_METHOD_ID = 33
comptime CALL_OBJECT_METHOD_A = 36
comptime CALL_BOOLEAN_METHOD_A = 39
comptime CALL_INT_METHOD_A = 51
comptime CALL_VOID_METHOD_A = 63
comptime GET_FIELD_ID = 94
comptime GET_FLOAT_FIELD = 102
comptime SET_BOOLEAN_FIELD = 105
comptime GET_STATIC_METHOD_ID = 113
comptime CALL_STATIC_OBJECT_METHOD_A = 116
comptime GET_STATIC_FIELD_ID = 144
comptime GET_STATIC_OBJECT_FIELD = 145
comptime GET_STATIC_INT_FIELD = 150
comptime NEW_STRING_UTF = 167
comptime GET_STRING_UTF_CHARS = 169
comptime RELEASE_STRING_UTF_CHARS = 170
comptime NEW_OBJECT_ARRAY = 172
comptime SET_OBJECT_ARRAY_ELEMENT = 174
comptime NEW_INT_ARRAY = 179
comptime SET_INT_ARRAY_REGION = 211
comptime EXCEPTION_CHECK = 228


def log(text: String):
    """A line in Android's log (adb logcat -s mojoui)."""
    var tag = String("mojoui")
    var t = text
    _ = external_call["__android_log_write", c_int](c_int(4), tag.as_c_string_span(), t.as_c_string_span())  # INFO


def fbits(x: Float64) -> Int:
    """A Java float argument: its 32 bits in the low half of a jvalue."""
    return Int(bitcast[DType.uint32](Float32(x)))


def jcall[T: RegisterPassable = Int, *A: AnyType](env: Int, index: Int, *args: *A) -> T:
    """Calls JNIEnv function `index` with (env, args...)."""
    var table = Pointer[Int, MutUntrackedOrigin](unsafe_from_address=env)[]
    var addr = Pointer[Int, MutUntrackedOrigin](unsafe_from_address=table + index * 8)[]
    var raw = Pointer[NoneType, MutUntrackedOrigin](unsafe_from_address=addr)
    var f = Pointer(to=raw).unsafe_bitcast[def(e: Int, *a: *A) thin abi("C") -> T]()[]
    return f(env, *args)


struct Jni(Movable):
    """One thread's JNIEnv plus caches of classes (global references) and method IDs."""

    var env: Int
    var class_names: List[String]
    var classes: List[Int]
    var method_keys: List[String]
    var methods: List[Int]

    def __init__(out self, env: Int):
        self.env = env
        self.class_names = List[String]()
        self.classes = List[Int]()
        self.method_keys = List[String]()
        self.methods = List[Int]()

    def check(self) -> Bool:
        """True if the last call threw; the exception goes to the log and is cleared."""
        if jcall[UInt8](self.env, EXCEPTION_CHECK) != 0:
            jcall[NoneType](self.env, EXCEPTION_DESCRIBE)
            jcall[NoneType](self.env, EXCEPTION_CLEAR)
            return True
        return False

    def cls(mut self, name: String) -> Int:
        """A class by its JNI name, e.g. "android/widget/TextView" (cached)."""
        for k in range(len(self.class_names)):
            if self.class_names[k] == name:
                return self.classes[k]
        var n = name
        var local = jcall(self.env, FIND_CLASS, n.as_c_string_span())
        _ = self.check()
        var g = jcall(self.env, NEW_GLOBAL_REF, local)
        jcall[NoneType](self.env, DELETE_LOCAL_REF, local)
        self.class_names.append(name)
        self.classes.append(g)
        return g

    def method(mut self, class_name: String, name: String, sig: String, static: Bool = False) -> Int:
        var key = class_name + "." + name + sig + ("!" if static else "")
        for k in range(len(self.method_keys)):
            if self.method_keys[k] == key:
                return self.methods[k]
        var c = self.cls(class_name)
        var n = name
        var s = sig
        var id = jcall(self.env, GET_STATIC_METHOD_ID if static else GET_METHOD_ID, c, n.as_c_string_span(), s.as_c_string_span())
        if self.check():
            log("no method " + key)
        self.method_keys.append(key)
        self.methods.append(id)
        return id

    def new(mut self, class_name: String, sig: String, args: List[Int]) -> Int:
        """new ClassName(args) → a local reference."""
        var m = self.method(class_name, "<init>", sig)
        var o = jcall(self.env, NEW_OBJECT_A, self.cls(class_name), m, Int(args.unsafe_ptr()))
        _ = len(args)
        _ = self.check()
        return o

    def call(mut self, obj: Int, class_name: String, name: String, sig: String, args: List[Int] = []) -> Int:
        """An instance method returning an object (a local reference) or nothing."""
        var m = self.method(class_name, name, sig)
        var r: Int
        if sig.endswith("V"):
            jcall[NoneType](self.env, CALL_VOID_METHOD_A, obj, m, Int(args.unsafe_ptr()))
            r = 0
        else:
            r = jcall(self.env, CALL_OBJECT_METHOD_A, obj, m, Int(args.unsafe_ptr()))
        _ = len(args)
        _ = self.check()
        return r

    def call_int(mut self, obj: Int, class_name: String, name: String, sig: String, args: List[Int] = []) -> Int:
        var m = self.method(class_name, name, sig)
        var r = Int(jcall[Int32](self.env, CALL_INT_METHOD_A, obj, m, Int(args.unsafe_ptr())))
        _ = len(args)
        _ = self.check()
        return r

    def call_bool(mut self, obj: Int, class_name: String, name: String, sig: String, args: List[Int] = []) -> Bool:
        var m = self.method(class_name, name, sig)
        var r = jcall[UInt8](self.env, CALL_BOOLEAN_METHOD_A, obj, m, Int(args.unsafe_ptr())) != 0
        _ = len(args)
        _ = self.check()
        return r

    def static_call(mut self, class_name: String, name: String, sig: String, args: List[Int] = []) -> Int:
        var m = self.method(class_name, name, sig, static=True)
        var r = jcall(self.env, CALL_STATIC_OBJECT_METHOD_A, self.cls(class_name), m, Int(args.unsafe_ptr()))
        _ = len(args)
        _ = self.check()
        return r

    def static_int(mut self, class_name: String, name: String) -> Int:
        var c = self.cls(class_name)
        var n = name
        var s = String("I")
        var f = jcall(self.env, GET_STATIC_FIELD_ID, c, n.as_c_string_span(), s.as_c_string_span())
        _ = self.check()
        return Int(jcall[Int32](self.env, GET_STATIC_INT_FIELD, c, f))

    def static_object(mut self, class_name: String, name: String, sig: String) -> Int:
        var c = self.cls(class_name)
        var n = name
        var s = sig
        var f = jcall(self.env, GET_STATIC_FIELD_ID, c, n.as_c_string_span(), s.as_c_string_span())
        _ = self.check()
        return jcall(self.env, GET_STATIC_OBJECT_FIELD, c, f)

    def float_field(mut self, obj: Int, class_name: String, name: String) -> Float64:
        var n = name
        var s = String("F")
        var f = jcall(self.env, GET_FIELD_ID, self.cls(class_name), n.as_c_string_span(), s.as_c_string_span())
        _ = self.check()
        return Float64(jcall[Float32](self.env, GET_FLOAT_FIELD, obj, f))

    def set_bool_field(mut self, obj: Int, class_name: String, name: String, value: Bool):
        var n = name
        var s = String("Z")
        var f = jcall(self.env, GET_FIELD_ID, self.cls(class_name), n.as_c_string_span(), s.as_c_string_span())
        _ = self.check()
        jcall[NoneType](self.env, SET_BOOLEAN_FIELD, obj, f, UInt8(1 if value else 0))

    def string(self, text: String) -> Int:
        """A java.lang.String (local reference). JNI wants modified UTF-8; plain text is the same."""
        var t = text
        return jcall(self.env, NEW_STRING_UTF, t.as_c_string_span())

    def text(self, jstring: Int) -> String:
        if jstring == 0:
            return ""
        var chars = jcall(self.env, GET_STRING_UTF_CHARS, jstring, 0)
        var out = String(unsafe_from_utf8_ptr=Pointer[Int8, MutUntrackedOrigin](unsafe_from_address=chars))
        jcall[NoneType](self.env, RELEASE_STRING_UTF_CHARS, jstring, chars)
        return out

    def strings(mut self, items: List[String]) -> Int:
        """A String[] (local reference)."""
        var arr = jcall(self.env, NEW_OBJECT_ARRAY, Int32(len(items)), self.cls("java/lang/String"), 0)
        for k in range(len(items)):
            var s = self.string(items[k])
            jcall[NoneType](self.env, SET_OBJECT_ARRAY_ELEMENT, arr, Int32(k), s)
            self.drop(s)
        return arr

    def ints(self, values: List[Int32]) -> Int:
        """An int[] (local reference) copied from `values`."""
        var arr = jcall(self.env, NEW_INT_ARRAY, Int32(len(values)))
        jcall[NoneType](self.env, SET_INT_ARRAY_REGION, arr, Int32(0), Int32(len(values)), Int(values.unsafe_ptr()))
        _ = len(values)
        return arr

    def keep(self, local: Int) -> Int:
        """A global reference (lives until forget()) for a local one."""
        return jcall(self.env, NEW_GLOBAL_REF, local) if local != 0 else 0

    def forget(self, global_ref: Int):
        if global_ref != 0:
            jcall[NoneType](self.env, DELETE_GLOBAL_REF, global_ref)

    def drop(self, local: Int):
        if local != 0:
            jcall[NoneType](self.env, DELETE_LOCAL_REF, local)
