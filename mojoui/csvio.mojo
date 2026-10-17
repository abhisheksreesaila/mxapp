# mojoui.csvio: a CSV file → the engine's typed columns (mojoui.frame), for "open your data".
#
# SHIM (labelled, docs/plans/needs-mxframe.md): the file is parsed by pyarrow (Python) on Linux and the web: fast,
# multi-threaded, correct quoting and type inference. MX frame's own readers replace it; the columns it produces
# are the engine's own (int64 values, dictionaries for text), so nothing above this module changes then.
#
# Types: integers → INT; decimals → DECIMAL (2 places if every value has at most 2, else 4); dates and times → DATE
# (days); true/false → INT 0/1; anything else → TEXT (a dictionary). Empty cells read as 0 / "" and are counted.

from std.python import Python, PythonObject
from std.ffi import external_call
from mojoui.frame import Column, Columns, share, INT, DECIMAL, TEXT, DATE, MAX_COLS

comptime CSV_BRIDGE = """
import time
import numpy as np
import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.csv as pv

KEEP = []  # the arrays Mojo is copying from, alive until it says done


def _decimal_scale(col):
    a = pc.fill_null(col, 0.0).to_numpy(zero_copy_only=False)
    if a.size == 0:
        return 2
    cents = a * 100.0
    return 2 if np.all(np.abs(cents - np.round(cents)) < 1e-6) else 4


def read(path, max_cols):
    t0 = time.perf_counter()
    table = pv.read_csv(path, convert_options=pv.ConvertOptions(timestamp_parsers=["%Y-%m-%d", "%Y/%m/%d", "%d/%m/%Y"]))
    read_s = time.perf_counter() - t0
    KEEP.clear()
    out = {"rows": table.num_rows, "read_s": read_s, "names": [], "kinds": [], "scales": [], "addresses": [],
           "dictionaries": [], "empty": [], "samples": [], "skipped": []}
    for i, name in enumerate(table.column_names):
        if len(out["names"]) >= max_cols:
            out["skipped"].append(name)
            continue
        col = table.column(i).combine_chunks()
        empty = col.null_count
        t = col.type
        dictionary = []
        if pa.types.is_integer(t) or pa.types.is_boolean(t):
            kind, scale = 0, 0
            arr = pc.fill_null(col.cast(pa.int64()), 0).to_numpy(zero_copy_only=False)
        elif pa.types.is_floating(t) or pa.types.is_decimal(t):
            kind = 1
            col = col.cast(pa.float64())
            scale = _decimal_scale(col)
            arr = np.round(pc.fill_null(col, 0.0).to_numpy(zero_copy_only=False) * (10 ** scale)).astype(np.int64)
        elif pa.types.is_date(t) or pa.types.is_timestamp(t):
            kind, scale = 3, 0
            days = col.cast(pa.date32()).cast(pa.int32())
            arr = pc.fill_null(days, 0).to_numpy(zero_copy_only=False).astype(np.int64)
        else:
            kind, scale = 2, 0
            enc = pc.fill_null(col.cast(pa.string()), "").dictionary_encode()
            dictionary = enc.dictionary.to_pylist()
            arr = enc.indices.to_numpy(zero_copy_only=False).astype(np.int64)
        arr = np.ascontiguousarray(arr)
        KEEP.append(arr)
        sample = [("" if v is None else str(v)) for v in col.slice(0, 8).to_pylist()]
        for key, value in (("names", name), ("kinds", kind), ("scales", scale), ("addresses", arr.ctypes.data),
                           ("dictionaries", dictionary), ("empty", empty), ("samples", sample)):
            out[key].append(value)
    out["convert_s"] = time.perf_counter() - t0 - read_s
    return out


def done():
    KEEP.clear()


def count_rows(path):
    \"\"\"An independent count and two sums (tests): plain Python csv, no pyarrow.\"\"\"
    import csv
    rows = 0
    sums = {}
    with open(path, newline="") as f:
        r = csv.DictReader(f)
        for rec in r:
            rows += 1
            for k, v in rec.items():
                try:
                    sums[k] = sums.get(k, 0.0) + float(v)
                except ValueError:
                    pass
    return {"rows": rows, "sums": sums}
"""


@fieldwise_init
struct CsvColumn(Copyable, Movable):
    """What the Import step shows about one column."""

    var name: String
    var kind: Int  # INT, DECIMAL, TEXT, DATE
    var scale: Int
    var empty: Int  # empty cells (read as 0 or "")
    var distinct: Int  # TEXT: values in its dictionary (0 for numbers)
    var sample: List[String]  # the first rows, as written in the file


@fieldwise_init
struct CsvImport(Movable):
    var path: String
    var rows: Int
    var columns: List[CsvColumn]
    var skipped: List[String]  # columns past the engine's limit (MAX_COLS)
    var seconds: Float64  # read + convert + copy
    var base_addr: Int  # the shared columns (mojoui.frame.share); Frame(base_addr) is the table


def kind_name(kind: Int) -> String:
    if kind == INT:
        return "Integer"
    if kind == DECIMAL:
        return "Decimal"
    if kind == DATE:
        return "Date"
    return "Text"


def py_text(o: PythonObject) raises -> String:
    return String(py=o)


def read_csv(path: String) raises -> CsvImport:
    """Reads the file into shared columns. Raises with a readable message if it isn't a table."""
    var types = Python.import_module("types")
    var builtins = Python.import_module("builtins")
    var time = Python.import_module("time")
    var start = Float64(py=time.perf_counter())
    var mod = types.ModuleType("mojoui_csv_bridge")
    _ = builtins.exec(CSV_BRIDGE, mod.__dict__)
    var out: PythonObject
    try:
        out = mod.read(path, MAX_COLS)
    except e:
        raise Error("couldn't read " + path + " as CSV: " + String(e))
    var rows = Int(py=out["rows"])
    var cols = Columns()
    var info = List[CsvColumn]()
    var n = Int(py=out["names"].__len__())
    for c in range(n):
        var col = Column(py_text(out["names"][c]), Int(py=out["kinds"][c]), Int(py=out["scales"][c]))
        if col.kind == DECIMAL:
            col.scale = Int(py=out["scales"][c])
        col.values = List[Int64](length=rows, fill=0)
        if rows > 0:
            _ = external_call["memcpy", Int](Int(col.values.unsafe_ptr()), Int(py=out["addresses"][c]), rows * 8)
        var words = out["dictionaries"][c]
        for k in range(Int(py=words.__len__())):
            col.dictionary.append(py_text(words[k]))
        var sample = List[String]()
        var s = out["samples"][c]
        for k in range(Int(py=s.__len__())):
            sample.append(py_text(s[k]))
        info.append(CsvColumn(col.name, col.kind, col.scale, Int(py=out["empty"][c]), len(col.dictionary), sample^))
        cols.add(col^)
    _ = mod.done()
    var skipped = List[String]()
    for k in range(Int(py=out["skipped"].__len__())):
        skipped.append(py_text(out["skipped"][k]))
    var addr = share(cols^)
    return CsvImport(path, rows, info^, skipped^, Float64(py=time.perf_counter()) - start, addr)


def csv_oracle(path: String) raises -> PythonObject:
    """An independent pass over the file (Python's csv module): {"rows": n, "sums": {column: float}} (tests)."""
    var types = Python.import_module("types")
    var builtins = Python.import_module("builtins")
    var mod = types.ModuleType("mojoui_csv_bridge")
    _ = builtins.exec(CSV_BRIDGE, mod.__dict__)
    return mod.count_rows(path)
