# Benchmark + correctness for the Data Lens pipeline (scripts/check M4/M5).
# Build: pixi run mojo build -I examples/lens -I . tests/bench_lens.mojo -o build/bench_lens
from std.time import perf_counter_ns
from std.math import log

from mojoui import Surface
from mojoui.gpu import PointCloud, Knobs
from app import place, colour, trip, hubs, BASE_UNITS_PER_POINT, HOUR_HALF_WIDTH

comptime N = 20_000_000
comptime W = 1920
comptime H = 1080


def frame(mut cloud: PointCloud, mut surface: Surface, var k: Knobs) -> Int:
    var matched = cloud.bin[place](surface.width, surface.height, k)
    var average = Float64(cloud.shown) / Float64(surface.width * surface.height)
    k[6] = Float32(log(1.0 + max(average * 40.0, 6.0)))
    cloud.shade[colour](surface, k)
    return matched


def main() raises:
    var x = List[Float32](length=N, fill=0)
    var y = List[Float32](length=N, fill=0)
    var hour = List[Float32](length=N, fill=0)
    var kind = List[Float32](length=N, fill=0)
    var places = hubs()
    for i in range(N):
        var t = trip(i, places)
        x[i] = t[0]
        y[i] = t[1]
        hour[i] = t[2]
        kind[i] = t[3]
    # An independent count: Bike trips at the hour-30 slider setting (7.2 h ± 1.5 h), by a plain loop.
    var bike_hour30 = 0
    var centre = Float32(30.0 * 24.0 / 100.0)
    for i in range(N):
        var d = abs(hour[i] - centre)
        d = min(d, 24 - d)
        if kind[i] == 2 and d <= HOUR_HALF_WIDTH:
            bike_hour30 += 1
    var gpu = PointCloud(x, y, hour, kind)
    var cpu = PointCloud(x, y, hour, kind, use_gpu=False)
    if not gpu.on_gpu():
        raise Error("no GPU")
    # Zoom 1 on a 2× screen, rideshares in the evening: a typical frame.
    var k = Knobs(0.5, 0.5, Float32(BASE_UNITS_PER_POINT / 2.0), 19.0, HOUR_HALF_WIDTH, 1.0, 1.0, 0.0)
    var a = List[UInt32](length=W * H, fill=0)
    var b = List[UInt32](length=W * H, fill=0)
    var sa = Surface(Int(a.unsafe_ptr()), W, H, 2.0)
    var sb = Surface(Int(b.unsafe_ptr()), W, H, 2.0)
    var times = List[Float64]()
    var matched_gpu = 0
    for _ in range(31):
        var t0 = perf_counter_ns()
        matched_gpu = frame(gpu, sa, k)
        times.append(Float64(perf_counter_ns() - t0) / 1e6)
    sort(times)
    var t1 = perf_counter_ns()
    var matched_cpu = frame(cpu, sb, k)
    var cpu_ms = Float64(perf_counter_ns() - t1) / 1e6
    var same = 0
    for i in range(W * H):
        if a[i] == b[i]:
            same += 1
    print(
        "BENCH: points=" + String(N) + " size=" + String(W) + "x" + String(H)
        + " gpu_median_ms=" + String(times[15]) + " cpu_ms=" + String(cpu_ms)
        + " matched_gpu=" + String(matched_gpu) + " matched_cpu=" + String(matched_cpu)
        + " same_pixels=" + String(Float64(same) / Float64(W * H)) + " uploads=" + String(gpu.uploads)
        + " naive_bike_hour30=" + String(bike_hour30) + " device=" + gpu.device_name().replace(" ", "_")
    )
    _ = len(a)
    _ = len(b)
