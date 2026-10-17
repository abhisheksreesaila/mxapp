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


def _scaled(col):
    \"\"\"A float column as integers: hundredths if every value has at most 2 decimals, else ten-thousandths.
    Arrow's kernels, a few passes and no Python-level temporaries (it matters at 100M rows).\"\"\"
    col = pc.fill_null(col, 0.0)
    for scale in (2, 4):
        scaled = pc.multiply(col, float(10 ** scale))
        rounded = pc.round(scaled)
        worst = pc.max(pc.abs(pc.subtract(scaled, rounded))).as_py() if len(col) else 0.0
        if scale == 4 or (worst or 0.0) < 1e-6:
            return scale, pc.cast(rounded, pa.int64()).to_numpy(zero_copy_only=False)


COLUMNS = []  # the parsed file's columns, each dropped once Mojo has its copy (one column's extra memory at a time)
STATE = {}


def open_file(path, max_cols):
    \"\"\"Parses the file; returns the row count, the columns it will hand over, and those past the limit.\"\"\"
    t0 = time.perf_counter()
    table = pv.read_csv(path)  # (ISO dates are found by default; extra date formats doubled the read time at 50M rows)
    COLUMNS.clear()
    KEEP.clear()
    names = table.column_names[:max_cols]
    COLUMNS.extend(table.column(i) for i in range(len(names)))
    STATE["read_s"] = time.perf_counter() - t0
    STATE["convert_s"] = 0.0
    return {"rows": table.num_rows, "names": list(names), "skipped": table.column_names[max_cols:]}


def column(i):
    \"\"\"Column i as the engine's int64 values (kind, scale, address, dictionary…); the parsed column is let go.\"\"\"
    t0 = time.perf_counter()
    col = COLUMNS[i].combine_chunks()
    COLUMNS[i] = None
    empty = col.null_count
    t = col.type
    dictionary = []
    if pa.types.is_integer(t) or pa.types.is_boolean(t):
        kind, scale = 0, 0
        arr = pc.fill_null(col.cast(pa.int64()), 0).to_numpy(zero_copy_only=False)
    elif pa.types.is_floating(t) or pa.types.is_decimal(t):
        kind = 1
        scale, arr = _scaled(col.cast(pa.float64()))
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
    KEEP.clear()
    KEEP.append(arr)
    sample = [("" if v is None else str(v)) for v in col.slice(0, 8).to_pylist()]
    STATE["convert_s"] += time.perf_counter() - t0
    return {"kind": kind, "scale": scale, "address": arr.ctypes.data, "dictionary": dictionary, "empty": empty, "sample": sample}


def seconds():
    return STATE.get("read_s", 0.0) + STATE.get("convert_s", 0.0)


def done():
    KEEP.clear()
    COLUMNS.clear()


def release(i):
    \"\"\"Column i is copied: its array can go (so a 100M-row file never holds two copies of every column).\"\"\"
    KEEP[i] = None


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
    var base_addr: Int
    var parse_seconds: Float64  # of which: the file read and typed (pyarrow)  # the shared columns (mojoui.frame.share); Frame(base_addr) is the table


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
    var head: PythonObject
    try:
        head = mod.open_file(path, MAX_COLS)
    except e:
        raise Error("couldn't read " + path + " as CSV: " + String(e))
    var rows = Int(py=head["rows"])
    var cols = Columns()
    var info = List[CsvColumn]()
    var n = Int(py=head["names"].__len__())
    for c in range(n):
        var one = mod.column(c)
        var col = Column(py_text(head["names"][c]), Int(py=one["kind"]), Int(py=one["scale"]))
        col.scale = Int(py=one["scale"])
        col.values = List[Int64](length=rows, fill=0)
        if rows > 0:
            _ = external_call["memcpy", Int](Int(col.values.unsafe_ptr()), Int(py=one["address"]), rows * 8)
        var words = one["dictionary"]
        for k in range(Int(py=words.__len__())):
            col.dictionary.append(py_text(words[k]))
        var sample = List[String]()
        var s = one["sample"]
        for k in range(Int(py=s.__len__())):
            sample.append(py_text(s[k]))
        info.append(CsvColumn(col.name, col.kind, col.scale, Int(py=one["empty"]), len(col.dictionary), sample^))
        cols.add(col^)
    var parse = Float64(py=mod.seconds())
    _ = mod.done()
    var skipped = List[String]()
    for k in range(Int(py=head["skipped"].__len__())):
        skipped.append(py_text(head["skipped"][k]))
    var addr = share(cols^)
    return CsvImport(path, rows, info^, skipped^, Float64(py=time.perf_counter()) - start, addr, parse)


def csv_oracle(path: String) raises -> PythonObject:
    """An independent pass over the file (Python's csv module): {"rows": n, "sums": {column: float}} (tests)."""
    var types = Python.import_module("types")
    var builtins = Python.import_module("builtins")
    var mod = types.ModuleType("mojoui_csv_bridge")
    _ = builtins.exec(CSV_BRIDGE, mod.__dict__)
    return mod.count_rows(path)
