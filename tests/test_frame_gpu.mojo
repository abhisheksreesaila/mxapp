# Frame on the GPU: run-time group-bys (key, value, filters as bytecode) over the shared Contoso columns,
# exact against the CPU, a 2-D pivot, and a session's edits reaching the next group-by as deltas.
# Build it (mojo run can't start the GPU runtime): pixi run mojo build -I . tests/test_frame_gpu.mojo -o build/test_frame_gpu
from std.testing import assert_equal, assert_true
from mojoui.frame import Frame, Range, share, OP_COL, OP_CONST, OP_SUB
from mojoui.frame_gpu import GpuFrame, group_sum, pivot_program
from mojoui.contoso import generate_columns, DAY, CATEGORY, REGION, CHANNEL, PRODUCT, QUANTITY, CENTS, COST, YEAR, EPOCH_2023
from mojoui.gpu import gpu_present


def col(c: Int) -> List[Int64]:
    var p = List[Int64]()
    p.append(Int64(OP_COL))
    p.append(Int64(c))
    return p^


def main() raises:
    var n = 20_000_000 if gpu_present() else 2_000_000
    var addr = share(generate_columns(n))
    var gf = GpuFrame(addr)
    if gpu_present():
        assert_true(gf.on_gpu(), "the GPU must be used when there is one")
    var frame = Frame(addr)
    var margin = frame.formula("margin = cents - cost")
    var bin = frame.formula("bin = min(cents // 50, 23)")
    var year_index = frame.formula("yi = year - 2023")

    # the dashboard's kind of queries: (key, value, filters, groups)
    var keys = List[List[Int64]]()
    var values = List[List[Int64]]()
    var filters = List[List[Range]]()
    var sizes = List[Int]()
    var day_2024: List[Range] = [Range(DAY, EPOCH_2023 + 365, EPOCH_2023 + 730)]
    var online_2024: List[Range] = [Range(DAY, EPOCH_2023 + 365, EPOCH_2023 + 730), Range(CHANNEL, 0, 0)]
    var europe: List[Range] = [Range(REGION, 1, 1)]
    keys.append(col(CATEGORY)); values.append(col(CENTS)); filters.append(day_2024.copy()); sizes.append(8)
    keys.append(col(REGION)); values.append(col(CENTS)); filters.append(online_2024.copy()); sizes.append(5)
    keys.append(col(PRODUCT)); values.append(col(CENTS)); filters.append(List[Range]()); sizes.append(64)
    keys.append(frame.program_for(bin)); values.append(col(QUANTITY)); filters.append(europe.copy()); sizes.append(24)
    keys.append(frame.program_for(year_index)); values.append(frame.program_for(margin)); filters.append(List[Range]()); sizes.append(3)
    keys.append(col(CHANNEL)); values.append(col(QUANTITY)); filters.append(day_2024.copy()); sizes.append(3)
    keys.append(pivot_program(col(CATEGORY), 3, frame.program_for(year_index))); values.append(col(CENTS)); filters.append(europe.copy()); sizes.append(24)

    var compared = 0
    var worst = 0.0
    var nonzero = 0
    for q in range(len(keys)):
        var g = gf.base_sums(keys[q], values[q], filters[q], sizes[q])
        var c = gf.base_sums(keys[q], values[q], filters[q], sizes[q], use_gpu=False)
        for k in range(sizes[q]):
            assert_equal(g.sums[k], c.sums[k], "query " + String(q) + " group " + String(k) + " sums")
            assert_equal(g.counts[k], c.counts[k], "query " + String(q) + " group " + String(k) + " counts")
            compared += 2
            if g.counts[k] > 0:
                nonzero += 1
        worst = max(worst, g.milliseconds)
        if q == 6:
            print("PIVOT: 2-D agrees with the CPU (" + String(sizes[q]) + " cells, " + String(g.milliseconds) + " ms)")
    assert_true(nonzero > 100, "the queries should hit real groups")

    # a session's edits: a changed amount, a removed row, an appended row; exact deltas
    var before = group_sum(frame, gf, col(CATEGORY), col(CENTS), List[Range](), 8)
    var row = 1234
    var cat = Int(frame.get(CATEGORY, row))
    var old = frame.get(CENTS, row)
    frame.set(CENTS, row, old + 100_000)
    var removed = 777
    var rcat = Int(frame.get(CATEGORY, removed))
    var rcents = Int(frame.get(CENTS, removed))
    frame.remove(removed)
    var added = frame.append(["2025-03-04", "Toys", "Europe", "Online", "RC car", "2", "99.00", "40.00", "2025"])
    var after = group_sum(frame, gf, col(CATEGORY), col(CENTS), List[Range](), 8)
    for k in range(8):
        var expect = before.sums[k]
        var expect_n = before.counts[k]
        if k == cat:
            expect += 100_000
        if k == rcat:
            expect -= rcents
            expect_n -= 1
        if k == 5:  # Toys
            expect += 9900
            expect_n += 1
        assert_equal(after.sums[k], expect, "edited sums, group " + String(k))
        assert_equal(after.counts[k], expect_n, "edited counts, group " + String(k))
    # the formula column sees the edit too, through the same path
    var m_before = group_sum(frame, gf, col(CATEGORY), frame.program_for(margin), List[Range](), 8)
    frame.set(COST, row, frame.get(COST, row) - 5000)
    var m_after = group_sum(frame, gf, col(CATEGORY), frame.program_for(margin), List[Range](), 8)
    assert_equal(m_after.sums[cat] - m_before.sums[cat], 5000)
    assert_true(frame.undo() and frame.undo() and frame.undo() and frame.undo())
    var back = group_sum(frame, gf, col(CATEGORY), col(CENTS), List[Range](), 8)
    for k in range(8):
        assert_equal(back.sums[k], before.sums[k])
        assert_equal(back.counts[k], before.counts[k])
    # the awkward overlays: edited then removed; appended then edited; a row moved to another group;
    # an edit undone back to the shared value; a chained formula flattened for the kernel
    var r2 = 4321
    var c2 = Int(frame.get(CATEGORY, r2))
    frame.set(CENTS, r2, frame.get(CENTS, r2) + 50_000)
    frame.remove(r2)  # its old value must leave the total and its new one never enter
    var r3 = frame.append(["2025-01-02", "Home", "Europe", "Stores", "Desk lamp", "1", "10.00", "4.00", "2025"])
    frame.set(CENTS, r3, 2500)  # appended, then edited: the edited value counts
    var r4 = 777
    var c4 = Int(frame.get(CATEGORY, r4))
    var v4 = Int(frame.get(CENTS, r4))
    frame.set(CATEGORY, r4, Int64((c4 + 1) % 8))  # moved to the next group
    var r5 = 999
    var v5 = frame.get(CENTS, r5)
    frame.set(CENTS, r5, v5 + 1)
    frame.set(CENTS, r5, v5)  # back to the shared value: nothing should change
    var now = group_sum(frame, gf, col(CATEGORY), col(CENTS), List[Range](), 8)
    for k in range(8):
        var e = before.sums[k]
        var n_ = before.counts[k]
        if k == c2:
            e -= Int(frame.base()[].cols[CENTS].values[r2])
            n_ -= 1
        if k == 1:  # Home
            e += 2500
            n_ += 1
        if k == c4:
            e -= v4
            n_ -= 1
        if k == (c4 + 1) % 8:
            e += v4
            n_ += 1
        assert_equal(now.sums[k], e, "overlay sums, group " + String(k))
        assert_equal(now.counts[k], n_, "overlay counts, group " + String(k))
    var chained = frame.formula("four = quantity + cost * margin")  # 4 slots once flattened: the kernel's whole stack
    var gpu_c = group_sum(frame, gf, col(CATEGORY), frame.program_for(chained), List[Range](), 8)
    var cpu_c = group_sum(frame, gf, col(CATEGORY), frame.program_for(chained), List[Range](), 8, use_gpu=False)
    for k in range(8):
        assert_equal(gpu_c.sums[k], cpu_c.sums[k], "chained formula, group " + String(k))
    _ = r3
    print("PATCH: edit visible in the next group-by (" + String(after.milliseconds) + " ms with deltas); undo restores")
    _ = added
    print("GROUPBY: " + String(n) + " rows, GPU = CPU on " + String(compared) + " numbers, max " + String(worst) + " ms, device " + gf.device_name())
    print("FRAME GPU TESTS PASSED")
