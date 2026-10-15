# MX frame (a Mojo dataframe engine) as an engine for a mojoui Table: the same group-by sums,
# planned and run by MX frame's native executor. Linux and web for now (it runs through Mojo's
# Python interop; a Python-free Mojo API is specified in docs/mxframe-mojo-api.md).
#
#   var mx = MxFrame(table, ["day", "category", …], [("bin", "cents", 5000, 23)])
#   var totals = mx.group_sum("region", "cents", 5, ranges=[("day", 0, 364)], equals=[("channel", 1)])

from std.python import Python, PythonObject
from mojoui.gpu import Table, GroupSums
from mojoui.clock import now_ns


struct MxFrame(Movable):
    var bridge: PythonObject
    var frame: PythonObject
    var ready: Bool
    var problem: String  # why it isn't ready

    def __init__(out self, table: Table, names: List[String], derived: List[Tuple[String, String, Int, Int]]):
        self.bridge = PythonObject(None)
        self.frame = PythonObject(None)
        self.ready = False
        self.problem = ""
        try:
            Python.add_to_path("mojoui")
            self.bridge = Python.import_module("mxframe_bridge")
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
        self, by: String, value: String, groups: Int,
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
        except e:
            print("mojoui.mxframe: " + String(e))
        return GroupSums(sums^, counts^, Float64(now_ns() - t0) / 1e6)
