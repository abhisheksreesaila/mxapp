# How omxplorer's engine path scales: a CSV of N orders → import → GPU upload → sum on the GPU → sort → a format
# change redrawn → the first screen drawn. Prints one Markdown row for docs/scale.md.
#   scripts/mxbuild.sh tools/scale.mojo -o build/scale && pixi run build/scale build/data/orders_10m.csv
from std.sys import argv
from std.python import Python
from std.time import perf_counter_ns
from mojoui.csvio import read_csv
from mojoui.sheet import Sheet
from mojoui.datagrid import DataGrid
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.numformat import ColumnFormat, CURRENCY
from mojoui.charts import fixed, grouped


def seconds_since(t0: Int) -> Float64:
    return Float64(perf_counter_ns() - t0) / 1e9


def main() raises:
    var args = argv()
    var path = String(args[1])
    var t = perf_counter_ns()
    var imp = read_csv(path)
    var import_s = seconds_since(t)
    t = perf_counter_ns()
    var frame = Sheet(imp.table)  # (the GPU copy is made here)
    var upload_s = seconds_since(t)
    var revenue = frame.index("revenue")
    _ = frame.totals(revenue)  # (warm)
    t = perf_counter_ns()
    var r = frame.totals(revenue)
    var sum_ms = seconds_since(t) * 1000.0
    t = perf_counter_ns()
    var order = frame.permutation(revenue, True)
    var sort_s = seconds_since(t)
    var font = Font()
    var pal = Palette.omarchy()
    var grid = DataGrid()
    var w = 1084
    var h = 676
    var px = List[UInt32](length=w * h, fill=0)
    var s = Surface(Int(px.unsafe_ptr()), w, h, 1.0)
    t = perf_counter_ns()
    grid.draw(s, frame, font, pal)
    var draw_ms = seconds_since(t) * 1000.0
    grid.set_order(order^, revenue, True)
    t = perf_counter_ns()
    frame.set_format(revenue, ColumnFormat(CURRENCY, 2, True, False, "$"))
    grid.redraw()
    grid.draw(s, frame, font, pal)
    var format_ms = seconds_since(t) * 1000.0
    var rows = frame.rows()
    var size = String(rows // 1_000_000) + "M"
    print("parse " + fixed(imp.parse_seconds, 2) + " s of " + fixed(import_s, 2) + " s")
    var os = Python.import_module("os")
    var bytes = Int(py=os.path.getsize(path))
    var gb = Float64(bytes) / 1e9
    var csv_size = (fixed(gb, 2) + " GB") if gb >= 1.0 else (String(bytes // 1_000_000) + " MB")
    print("| " + size + " | " + fixed(import_s, 2) + " s | " + fixed(sort_s, 2) + " s | " + fixed(format_ms, 1) + " ms | "
          + fixed(sum_ms, 1) + " ms | " + fixed(upload_s, 2) + " s | " + fixed(draw_ms, 1) + " ms | " + csv_size + " |")
    print("GPU: " + frame.device_name + " · " + grouped(r.counts[0]) + " rows summed")
