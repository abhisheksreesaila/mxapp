# MX frame (a Mojo dataframe engine) as an engine for a mojoui Table: the same group-by sums,
# planned and run by MX frame's native executor. Linux and web for now (it runs through Mojo's
# Python interop; a Python-free Mojo API is specified in docs/mxframe-mojo-api.md).
#
# The small Python bridge below views the Table's memory with numpy (no copy), copies each column
# once into Arrow, and turns filters into MX frame expressions. It's made into a module at run time,
# so it works from any directory.
#
#   var mx = MxFrame(table, ["day", "category", …], [("bin", "cents", 5000, 23)])
#   var totals = mx.group_sum("region", "cents", 5, ranges=[("day", 0, 364)], equals=[("channel", 1)])

from std.python import Python, PythonObject
from mojoui.gpu import Table, GroupSums
from mojoui.clock import now_ns

comptime BRIDGE = """
import ctypes

import numpy as np
import pyarrow as pa


def frame(address, rows, names, derived):
    \"\"\"An MX frame LazyFrame over a mojoui Table's memory (eight int32 columns per row), plus derived
    columns: each [name, source, divisor, cap] is min(source // divisor, cap).\"\"\"
    import mxframe as mx

    raw = (ctypes.c_int32 * (rows * 8)).from_address(int(address))
    grid = np.frombuffer(raw, dtype=np.int32).reshape(int(rows), 8)
    columns = {name: np.ascontiguousarray(grid[:, k]) for k, name in enumerate(names) if name}
    for name, source, divisor, cap in derived:
        columns[name] = np.minimum(columns[source] // int(divisor), int(cap)).astype(np.int32)
    return mx.from_arrow(pa.table({k: pa.array(v) for k, v in columns.items()}))


def group_sum(lf, by, value, groups, ranges, equals):
    \"\"\"Sums of `value` and row counts per `by` group (0 … groups-1), over rows where every
    (column, low, high) in `ranges` holds and every (column, value) in `equals` matches.
    Returns [sums..., counts...] as Python ints.\"\"\"
    import mxframe as mx

    cond = None
    for name, low, high in ranges:
        c = (mx.col(name) >= int(low)) & (mx.col(name) <= int(high))
        cond = c if cond is None else cond & c
    for name, v in equals:
        c = mx.col(name) == int(v)
        cond = c if cond is None else cond & c
    q = lf.filter(cond) if cond is not None else lf
    out = q.groupby(by).agg(mx.col(value).sum().alias("s"), mx.col(value).count().alias("n")).compute(device="cpu")
    sums = [0] * int(groups)
    counts = [0] * int(groups)
    for g, s, n in zip(out.column(by).to_pylist(), out.column("s").to_pylist(), out.column("n").to_pylist()):
        if 0 <= g < groups:
            sums[g] = int(round(s))
            counts[g] = int(n)
    return sums + counts
"""


struct MxFrame(Movable):
    var bridge: PythonObject
    var frame: PythonObject
    var ready: Bool
    var problem: String  # why it isn't ready (or stopped working)

    def __init__(out self, table: Table, names: List[String], derived: List[Tuple[String, String, Int, Int]]):
        self.bridge = PythonObject(None)
        self.frame = PythonObject(None)
        self.ready = False
        self.problem = ""
        try:
            var types = Python.import_module("types")
            var builtins = Python.import_module("builtins")
            self.bridge = types.ModuleType("mojoui_mxframe_bridge")
            _ = builtins.exec(BRIDGE, self.bridge.__dict__)
            var py_names = Python.list()
            for n in names:
                py_names.append(PythonObject(n))
            var py_derived = Python.list()
            for d in derived:
                var item = Python.list()
                item.append(PythonObject(d[0]))
                item.append(PythonObject(d[1]))
                item.append(PythonObject(d[2]))
                item.append(PythonObject(d[3]))
                py_derived.append(item)
            self.frame = self.bridge.frame(Int(table.host.unsafe_ptr()), table.count, py_names, py_derived)
            self.ready = True
        except e:
            self.problem = String(e)

    def group_sum(
        mut self, by: String, value: String, groups: Int,
        ranges: List[Tuple[String, Int, Int]], equals: List[Tuple[String, Int]],
    ) -> GroupSums:
        """Per-group sums of `value` and row counts, over rows inside every range and matching every value."""
        var t0 = now_ns()
        var sums = List[Int](length=groups, fill=0)
        var counts = List[Int](length=groups, fill=0)
        if not self.ready:
            return GroupSums(sums^, counts^, 0)
        try:
            var py_ranges = Python.list()
            for r in ranges:
                var item = Python.list()
                item.append(PythonObject(r[0]))
                item.append(PythonObject(r[1]))
                item.append(PythonObject(r[2]))
                py_ranges.append(item)
            var py_equals = Python.list()
            for e in equals:
                var item = Python.list()
                item.append(PythonObject(e[0]))
                item.append(PythonObject(e[1]))
                py_equals.append(item)
            var out = self.bridge.group_sum(self.frame, by, value, groups, py_ranges, py_equals)
            for g in range(groups):
                sums[g] = Int(py=out[g])
                counts[g] = Int(py=out[groups + g])
        except e:  # say why, and stop using it (zeros would look like real results)
            self.ready = False
            self.problem = String(e)
        return GroupSums(sums^, counts^, Float64(now_ns() - t0) / 1e6)
