# How omxplorer's engine path scales: a CSV of N orders → import → GPU upload → sum on the GPU → sort → a format
# change redrawn → the first screen drawn. Prints one Markdown row for docs/scale.md.
#   pixi run mojo build -I . tools/scale.mojo -o build/scale && pixi run build/scale build/data/orders_10m.csv
from std.sys import argv
from std.time import perf_counter_ns
from mojoui.csvio import read_csv
from mojoui.frame import Frame, Range
from mojoui.frame_gpu import GpuFrame, group_sum
from mojoui.datagrid import DataGrid
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.numformat import ColumnFormat, CURRENCY
from mojoui.orders_ops import col_program
from mojoui.charts import fixed, grouped


def seconds_since(t0: Int) -> Float64:
    return Float64(perf_counter_ns() - t0) / 1e9


def main() raises:
    var args = argv()
    var path = String(args[1])
    var t = perf_counter_ns()
    var imp = read_csv(path)
    var import_s = seconds_since(t)
    var frame = Frame(imp.base_addr)
    t = perf_counter_ns()
    var gf = GpuFrame(imp.base_addr)
    var upload_s = seconds_since(t)
    var revenue = frame.index("revenue")
    var key = List[Int64]()
    key.append(0)
    key.append(0)
    _ = group_sum(frame, gf, key, col_program(revenue), List[Range](), 1)  # (warm)
    t = perf_counter_ns()
    var r = group_sum(frame, gf, key, col_program(revenue), List[Range](), 1)
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
    print("| " + size + " | " + fixed(import_s, 2) + " s | " + fixed(sort_s, 2) + " s | " + fixed(format_ms, 1) + " ms | "
          + fixed(sum_ms, 1) + " ms (" + gf.device_name() + ") | " + fixed(upload_s, 2) + " s | " + fixed(draw_ms, 1) + " ms | "
          + grouped(r.counts[0]) + " rows summed |")
