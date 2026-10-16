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
    # sorting the table: a permutation of 20M rows, by a text column (8 values), an amount, a formula
    var frame = Frame(addr)
    var margin = frame.formula("margin = cents - cost")
    frame.set(CENTS, 5, 1)
    var cols: List[Int] = [CATEGORY, CENTS, margin]
    var names: List[String] = ["category", "cents", "margin"]
    for k in range(3):
        var t0 = now_ns()
        var order = frame.permutation(cols[k], descending=k == 1)
        var ms = Float64(now_ns() - t0) / 1e6
        var ok = True
        for i in range(1, min(len(order), 200_000)):
            var a = frame.get(cols[k], order[i - 1])
            var b = frame.get(cols[k], order[i])
            if (a < b) if k == 1 else (a > b):
                ok = False
        print("SORT: " + names[k] + " " + String(len(order)) + " rows in " + String(ms) + " ms, " + ("ordered" if ok else "WRONG ORDER"))
