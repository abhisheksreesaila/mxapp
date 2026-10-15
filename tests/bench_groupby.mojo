# GPU group-by: exact against the CPU, and timing. Build: pixi run mojo build -I . tests/bench_groupby.mojo -o build/bench_groupby
from mojoui.gpu import Table, Row, Filter

comptime N = 20_000_000


def region(r: Row, f: Filter) -> Int:
    if f[0] >= 0 and r[3] != f[0]:  # a channel filter
        return -1
    return Int(r[2])


def month(r: Row, f: Filter) -> Int:
    return Int(r[0]) // 31 if r[0] >= 0 else -1


def product(r: Row, f: Filter) -> Int:
    """200 groups: more than fit in shared memory (the global-memory path)."""
    return (Int(r[0]) * 7 + Int(r[2])) % 200


def cents(r: Row, f: Filter) -> Int:
    return Int(r[6])


def main() raises:
    var cols = List[List[Int32]]()
    for _ in range(8):
        cols.append(List[Int32](length=N, fill=0))
    var s = UInt64(7)
    for i in range(N):
        s = s * 6364136223846793005 + 1442695040888963407
        cols[0][i] = Int32(Int(s >> 33) % 1096)  # day
        cols[2][i] = Int32(Int(s >> 20) % 5)  # region
        cols[3][i] = Int32(Int(s >> 13) % 3)  # channel
        cols[6][i] = Int32(Int(s >> 40) % 250_000)  # cents
    var gpu = Table(cols)
    var cpu = Table(cols, use_gpu=False)
    var f = Filter(-1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var f2 = Filter(1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var best = 1e9
    for _ in range(5):
        var g = gpu.group_sum[region, cents](5, f)
        best = min(best, g.milliseconds)
    var best36 = 1e9
    for _ in range(5):
        var g = gpu.group_sum[month, cents](36, f)
        best36 = min(best36, g.milliseconds)
    var exact = True
    for filt in [f, f2]:
        var a = gpu.group_sum[region, cents](5, filt)
        var b = cpu.group_sum[region, cents](5, filt)
        for k in range(5):
            if a.sums[k] != b.sums[k] or a.counts[k] != b.counts[k]:
                exact = False
    var m1 = gpu.group_sum[month, cents](36, f)
    var m2 = cpu.group_sum[month, cents](36, f)
    for k in range(36):
        if m1.sums[k] != m2.sums[k] or m1.counts[k] != m2.counts[k]:
            exact = False
    var p1 = gpu.group_sum[product, cents](200, f2)
    var p2 = cpu.group_sum[product, cents](200, f2)
    for k in range(200):
        if p1.sums[k] != p2.sums[k] or p1.counts[k] != p2.counts[k]:
            exact = False
    print("GROUPBY: rows=" + String(N) + " gpu_ms_5_groups=" + String(best) + " gpu_ms_36_groups=" + String(best36)
          + " cpu_ms=" + String(m2.milliseconds) + " exact=" + ("1" if exact else "0") + " uploads=" + String(gpu.uploads)
          + " device=" + gpu.device_name().replace(" ", "_"))
