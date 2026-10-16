# Where a run-time group-by spends its time. Build: pixi run mojo build -I . tests/bench_frame.mojo -o build/bench_frame
from mojoui.frame import Frame, Range, share, OP_COL
from mojoui.frame_gpu import GpuFrame, group_sum
from mojoui.contoso import generate_columns, CATEGORY, CENTS, DAY, EPOCH_2023
from mojoui.clock import now_ns


def col(c: Int) -> List[Int64]:
    var p = List[Int64]()
    p.append(Int64(OP_COL))
    p.append(Int64(c))
    return p^


def main() raises:
    var addr = share(generate_columns(20_000_000))
    var gf = GpuFrame(addr)
    var none = List[Range]()
    var day: List[Range] = [Range(DAY, EPOCH_2023 + 365, EPOCH_2023 + 730)]
    for i in range(6):
        var t0 = now_ns()
        var g = gf.base_sums(col(CATEGORY), col(CENTS), none if i % 2 == 0 else day, 8)
        print("call", i, "kernel+copies", g.milliseconds, "ms; wall", Float64(now_ns() - t0) / 1e6, "ms", "filters" if i % 2 else "")
