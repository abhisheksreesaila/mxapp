# MX Studio's Report operations: the dashboard's numbers as GPU group-bys over the same ledger the Sheet
# edits (the session's edits and merges included), each with the time it took.

from mojoui.frame import Frame, Range, OP_COL, OP_CONST, OP_SUB, OP_ADD, OP_MUL, OP_FLOORDIV, OP_MIN, OP_MAX
from mojoui.frame_gpu import GpuFrame, group_sum, pivot_program
from orders import (DAY, CUSTOMER, REGION, PRODUCT, REVENUE, COST, FREIGHT, WEIGHT, YEAR_START, RATE_CHANGE, DAYS)
from ops import col_program, text_groups, fold

comptime WEEKS = 41  # Jan 1 … Oct 14: whole weeks only (a part week would look like a fall)
comptime QUARTER_START: List[Int] = [0, 90, 181, 273, 365]  # days of 2025


def op(mut p: List[Int64], code: Int, arg: Int64 = 0):
    p.append(Int64(code))
    p.append(arg)


def margin_program() -> List[Int64]:
    """revenue - cost - freight (cents)."""
    var p = col_program(REVENUE)
    op(p, OP_COL, COST)
    op(p, OP_SUB)
    op(p, OP_COL, FREIGHT)
    op(p, OP_SUB)
    return p^


def week_program() -> List[Int64]:
    var p = col_program(DAY)
    op(p, OP_CONST, YEAR_START)
    op(p, OP_SUB)
    op(p, OP_CONST, 7)
    op(p, OP_FLOORDIV)
    return p^


def quarter_range(q: Int) -> Range:
    """Days of quarter q (0–3) of 2025."""
    var start = materialize[QUARTER_START]()
    return Range(DAY, Int64(YEAR_START + start[q]), Int64(YEAR_START + start[q + 1] - 1))


@fieldwise_init
struct Kpis(Copyable, Movable):
    var revenue: Int
    var orders: Int
    var margin: Int
    var customers: Int  # distinct after merges
    var milliseconds: Float64

    def margin_share(self) -> Float64:
        return Float64(self.margin) / Float64(max(self.revenue, 1))


def kpis(frame: Frame, gf: GpuFrame, ranges: List[Range]) -> Kpis:
    var nc = text_groups(frame, CUSTOMER)
    var rev = group_sum(frame, gf, col_program(CUSTOMER), col_program(REVENUE), ranges, nc)
    var mar = group_sum(frame, gf, col_program(CUSTOMER), margin_program(), ranges, nc)
    var revenue = 0
    var orders = 0
    var margin = 0
    for k in range(nc):
        revenue += rev.sums[k]
        orders += rev.counts[k]
        margin += mar.sums[k]
    var customers = 0
    for c in fold(frame, CUSTOMER, rev.counts):
        if c > 0:
            customers += 1
    return Kpis(revenue, orders, margin, customers, rev.milliseconds + mar.milliseconds)


@fieldwise_init
struct Weekly(Copyable, Movable):
    var revenue: List[Float64]  # cents, per week
    var margin: List[Float64]  # share 0–1, per week
    var milliseconds: Float64


def weekly(frame: Frame, gf: GpuFrame, ranges: List[Range]) -> Weekly:
    var rev = group_sum(frame, gf, week_program(), col_program(REVENUE), ranges, WEEKS)
    var mar = group_sum(frame, gf, week_program(), margin_program(), ranges, WEEKS)
    var r = List[Float64]()
    var m = List[Float64]()
    for w in range(WEEKS):
        r.append(Float64(rev.sums[w]))
        m.append(Float64(mar.sums[w]) / Float64(rev.sums[w]) if rev.sums[w] > 0 else 0.0)
    return Weekly(r^, m^, rev.milliseconds + mar.milliseconds)


@fieldwise_init
struct Grid2(Copyable, Movable):
    """A rows × columns result (shares or sums) with the time it took."""

    var values: List[Float64]
    var milliseconds: Float64


def margin_heatmap(frame: Frame, gf: GpuFrame, ranges: List[Range]) -> Grid2:
    """Gross margin share by region × product."""
    var nr = text_groups(frame, REGION)
    var np = text_groups(frame, PRODUCT)
    var key = pivot_program(col_program(REGION), np, col_program(PRODUCT))
    var rev = group_sum(frame, gf, key, col_program(REVENUE), ranges, nr * np)
    var mar = group_sum(frame, gf, key, margin_program(), ranges, nr * np)
    var out = List[Float64]()
    for i in range(nr * np):
        out.append(Float64(mar.sums[i]) / Float64(rev.sums[i]) if rev.sums[i] > 0 else 0.0)
    return Grid2(out^, rev.milliseconds + mar.milliseconds)


def shares(frame: Frame, gf: GpuFrame, col: Int, ranges: List[Range]) -> Grid2:
    """Revenue per value of a text column (merged values folded), in cents."""
    var g = text_groups(frame, col)
    var r = group_sum(frame, gf, col_program(col), col_program(REVENUE), ranges, g)
    var folded = fold(frame, col, r.sums)
    var out = List[Float64]()
    for v in folded:
        out.append(Float64(v))
    return Grid2(out^, r.milliseconds)


@fieldwise_init
struct Anomaly(Copyable, Movable):
    """The biggest margin fall between before and after the rate change, by region × parcel weight."""

    var region: Int
    var heavy: Bool
    var before: Float64  # margin share
    var after: Float64
    var rows: Int  # rows after the change in that group
    var milliseconds: Float64

    def points(self) -> Float64:
        return (self.before - self.after) * 100.0


def worst_margin_fall(frame: Frame, gf: GpuFrame) -> Anomaly:
    """Margin by region × (parcel over 4 kg) × (before / after Jul 14), on the GPU; the group that fell most."""
    var key = col_program(REGION)  # region * 4 + heavy * 2 + after
    op(key, OP_CONST, 4)
    op(key, OP_MUL)
    var heavy = col_program(WEIGHT)
    op(heavy, OP_CONST, 4001)
    op(heavy, OP_FLOORDIV)
    op(heavy, OP_CONST, 1)
    op(heavy, OP_MIN)
    op(heavy, OP_CONST, 2)
    op(heavy, OP_MUL)
    for v in heavy:
        key.append(v)
    op(key, OP_ADD)
    var after = col_program(DAY)
    op(after, OP_CONST, YEAR_START + RATE_CHANGE)
    op(after, OP_SUB)
    op(after, OP_CONST, 1000)
    op(after, OP_ADD)  # (positive: 1000 + days since)
    op(after, OP_CONST, 1000)
    op(after, OP_FLOORDIV)
    op(after, OP_CONST, 1)
    op(after, OP_MIN)
    for v in after:
        key.append(v)
    op(key, OP_ADD)
    var groups = text_groups(frame, REGION) * 4
    var rev = group_sum(frame, gf, key, col_program(REVENUE), List[Range](), groups)
    var mar = group_sum(frame, gf, key, margin_program(), List[Range](), groups)
    var best = Anomaly(0, False, 0, 0, 0, rev.milliseconds + mar.milliseconds)
    var worst = -1e9
    for region in range(text_groups(frame, REGION)):
        for h in range(2):
            var b = region * 4 + h * 2
            if rev.sums[b] == 0 or rev.sums[b + 1] == 0:
                continue
            var before = Float64(mar.sums[b]) / Float64(rev.sums[b])
            var after_share = Float64(mar.sums[b + 1]) / Float64(rev.sums[b + 1])
            if before - after_share > worst:
                worst = before - after_share
                best = Anomaly(region, h == 1, before, after_share, rev.counts[b + 1], rev.milliseconds + mar.milliseconds)
    return best^


def shares_by_region_product(frame: Frame, gf: GpuFrame) -> List[Int]:
    """Revenue (cents) by region × product over every row: inserted pivots and charts read it."""
    var nr = text_groups(frame, REGION)
    var np = text_groups(frame, PRODUCT)
    var r = group_sum(frame, gf, pivot_program(col_program(REGION), np, col_program(PRODUCT)), col_program(REVENUE), List[Range](), nr * np)
    return r.sums.copy()
