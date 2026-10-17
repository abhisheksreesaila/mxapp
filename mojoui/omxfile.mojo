# mojoui.omxfile: an omxplorer document on disk, one file `name.omx`: a Parquet file whose columns are the table
# as it stands (the session's edits, added and removed rows baked in) and whose metadata ("omx") is JSON: each
# column's kind, scale, dictionary and format, and the formula columns. Other tools can read its columns.
#
# SHIM (labelled): Parquet is written and read by pyarrow (Python) until MX frame's own writer lands.

from std.python import Python, PythonObject
from std.ffi import external_call
from mojoui.frame import Frame, Column, Columns, Edit, share, INT, DECIMAL, TEXT, DATE, MAX_COLS
from mojoui.numformat import ColumnFormat
from mojoui.workbook import json_string

comptime OMX_BRIDGE = """
import ctypes, json
import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq

KEEP = []


def write(path, rows, names, addresses, meta):
    cols = {}
    for name, address in zip(names, addresses):
        raw = (ctypes.c_int64 * int(rows)).from_address(int(address))
        cols[name] = pa.array(np.frombuffer(raw, dtype=np.int64).copy())
    table = pa.table(cols).replace_schema_metadata({"omx": meta})
    pq.write_table(table, path)


def read(path):
    t = pq.read_table(path)
    meta = json.loads((t.schema.metadata or {}).get(b"omx", b"{}"))
    KEEP.clear()
    arrays = [np.ascontiguousarray(t.column(n).to_numpy().astype(np.int64)) for n in t.column_names]
    KEEP.extend(arrays)
    return {"rows": t.num_rows, "names": list(t.column_names), "addresses": [a.ctypes.data for a in arrays], "meta": meta}


def done():
    KEEP.clear()
"""


def bridge() raises -> PythonObject:
    var types = Python.import_module("types")
    var builtins = Python.import_module("builtins")
    var mod = types.ModuleType("mojoui_omx_bridge")
    _ = builtins.exec(OMX_BRIDGE, mod.__dict__)
    return mod


def format_json(f: ColumnFormat) -> String:
    return ('{"style": ' + String(f.style) + ', "decimals": ' + String(f.decimals) + ', "thousands": ' + ("true" if f.thousands else "false")
            + ', "parens": ' + ("true" if f.parens else "false") + ', "symbol": ' + json_string(f.symbol) + "}")


def save_omx(path: String, frame: Frame) raises:
    """Writes the table as it stands (every alive row, the edits applied) to `path` (.omx)."""
    ref base = frame.base()[]
    var stored = frame.stored()
    var alive = List[Int]()
    var dense = len(frame.removed) == 0
    if not dense:
        for r in range(frame.rows()):
            if frame.alive(r):
                alive.append(r)
    var rows = frame.rows() if dense else len(alive)
    var columns = List[List[Int64]]()
    var meta = String('{"omx": 1, "columns": [')
    for c in range(stored):
        var values = List[Int64](length=rows, fill=0)
        if dense:
            var base_rows = base.rows
            if base_rows > 0:
                _ = external_call["memcpy", Int](Int(values.unsafe_ptr()), Int(base.cols[c].values.unsafe_ptr()), base_rows * 8)
            for i in range(len(frame.added)):
                values[base_rows + i] = frame.added[i][c]
            for item in frame.cells.items():
                if item.key % MAX_COLS == c:
                    values[item.key // MAX_COLS] = item.value
        else:
            for i in range(rows):
                values[i] = frame.get(c, alive[i])
        ref col = base.cols[c]
        if col.kind == TEXT:  # merged spellings read as the one they joined
            for i in range(rows):
                values[i] = frame.alias(c, values[i])
        meta += ("," if c > 0 else "") + '{"name": ' + json_string(col.name) + ', "kind": ' + String(col.kind) + ', "scale": ' + String(col.scale)
        meta += ', "format": ' + format_json(frame.format_of(c))
        if col.kind == TEXT:
            meta += ', "dictionary": ['
            var k = 0
            for w in col.dictionary:
                meta += ("," if k > 0 else "") + json_string(w)
                k += 1
            for w in frame.words[c]:
                meta += ("," if k > 0 else "") + json_string(w)
                k += 1
            meta += "]"
        meta += "}"
        columns.append(values^)
    meta += '], "formulas": ['
    for f in range(len(frame.formulas)):
        meta += ("," if f > 0 else "") + '{"text": ' + json_string(frame.formulas[f].name + " = " + frame.formulas[f].formula)
        meta += ', "format": ' + format_json(frame.format_of(stored + f)) + "}"
    meta += "]}"
    var names = Python.list()
    var addresses = Python.list()
    for c in range(stored):
        names.append(base.cols[c].name)
        addresses.append(Int(columns[c].unsafe_ptr()))
    var py = bridge()
    _ = py.write(path, rows, names, addresses, meta)
    _ = len(columns)


def format_from(o: PythonObject) raises -> ColumnFormat:
    return ColumnFormat(Int(py=o["style"]), Int(py=o["decimals"]), Bool(py=o["thousands"]), Bool(py=o["parens"]), String(py=o["symbol"]))


def open_omx(path: String) raises -> Frame:
    """Reads `path` (.omx): the table, its formula columns and every column's format."""
    var py = bridge()
    var read = py.read(path)
    var meta = read["meta"]
    if Int(py=meta.get("omx", 0)) != 1:
        raise Error(path + " isn't an omxplorer document")
    var rows = Int(py=read["rows"])
    var cols = Columns()
    var specs = meta["columns"]
    var n = Int(py=specs.__len__())
    for c in range(n):
        var spec = specs[c]
        var col = Column(String(py=spec["name"]), Int(py=spec["kind"]), Int(py=spec["scale"]))
        col.scale = Int(py=spec["scale"])
        col.values = List[Int64](length=rows, fill=0)
        if rows > 0:
            _ = external_call["memcpy", Int](Int(col.values.unsafe_ptr()), Int(py=read["addresses"][c]), rows * 8)
        if col.kind == TEXT:
            var words = spec["dictionary"]
            for k in range(Int(py=words.__len__())):
                col.dictionary.append(String(py=words[k]))
        cols.add(col^)
    _ = py.done()
    var frame = Frame(share(cols^))
    for c in range(n):
        frame.set_format(c, format_from(specs[c]["format"]))
    var formulas = meta["formulas"]
    for k in range(Int(py=formulas.__len__())):
        var c = frame.formula(String(py=formulas[k]["text"]))
        frame.set_format(c, format_from(formulas[k]["format"]))
    frame.log = List[Edit]()  # (what the file holds isn't undoable)
    return frame^
