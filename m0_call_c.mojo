from std.ffi import external_call


def main() raises:
    var v = external_call["mui_version", Int32]()
    print("[Mojo] mui_version() =", v)

    var s = String("Hello from Mojo")
    var n = external_call["mui_echo", Int32](s.unsafe_ptr(), Int32(s.byte_length()))
    print("[Mojo] C saw", n, "bytes")
