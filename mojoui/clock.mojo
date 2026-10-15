# A monotonic clock in nanoseconds. Mojo's perf_counter_ns() calls Apple's
# clock_gettime_nsec_np even when building for Android (built with -D MOJOUI_ANDROID),
# whose libc doesn't have it; there, ask clock_gettime(CLOCK_MONOTONIC) directly.
from std.ffi import external_call, c_int
from std.sys import is_defined
from std.time import perf_counter_ns


def now_ns() -> Int:
    comptime if is_defined["MOJOUI_ANDROID"]():
        var ts = List[Int](length=2, fill=0)  # struct timespec { seconds; nanoseconds }
        _ = external_call["clock_gettime", c_int](c_int(1), Int(ts.unsafe_ptr()))  # CLOCK_MONOTONIC
        var ns = ts[0] * 1_000_000_000 + ts[1]
        _ = len(ts)
        return ns
    else:
        return Int(perf_counter_ns())
