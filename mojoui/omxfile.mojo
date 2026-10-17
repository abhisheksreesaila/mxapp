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
from mojoui.sheetpage import SheetObject, OBJ_CHART, OBJ_PIVOT
from mojoui.reportpage import ReportTile, ReportFilter, new_tile, TILE_SUM, TILE_CHART

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


def read(path, max_cols):
    \"\"\"The file's columns in the metadata's order, refused unless every column is what the metadata says it is
    (a file from somewhere else, or edited by hand, must not reach the engine's raw memory).\"\"\"
    t = pq.read_table(path)
    try:
        meta = json.loads((t.schema.metadata or {}).get(b"omx", b"{}"))
    except ValueError:
        raise ValueError("its omx metadata isn't JSON")
    if meta.get("omx") != 1:
        raise ValueError("it isn't an omxplorer document")
    specs = meta.get("columns", [])
    if not 1 <= len(specs) <= max_cols:
        raise ValueError(f"it has {len(specs)} columns (1 to {max_cols} can be opened)")
    KEEP.clear()
    for spec in specs:
        name, kind = spec.get("name"), spec.get("kind")
        if name not in t.column_names:
            raise ValueError(f"column {name!r} is described but not stored")
        if kind not in (0, 1, 2, 3) or not 0 <= int(spec.get("scale", 0)) <= 6:
            raise ValueError(f"column {name!r} has an unknown type")
        col = t.column(name)
        if col.null_count:
            raise ValueError(f"column {name!r} has empty values")
        if not pa.types.is_integer(col.type):
            raise ValueError(f"column {name!r} isn't stored as integers")
        arr = np.ascontiguousarray(col.to_numpy().astype(np.int64))
        if kind == 2 and len(arr) and (arr.min() < 0 or arr.max() >= len(spec.get("dictionary", []))):
            raise ValueError(f"column {name!r} names texts it doesn't have")
        KEEP.append(arr)
    return {"rows": t.num_rows, "addresses": [a.ctypes.data for a in KEEP], "meta": meta}


def done():
    KEEP.clear()


def meta_of(path):
    \"\"\"The document's metadata alone (the sheet's objects and the Report).\"\"\"
    t = pq.read_schema(path)
    return json.loads((t.metadata or {}).get(b"omx", b"{}"))
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


def save_omx(path: String, frame: Frame, objects: List[SheetObject] = [], tiles: List[ReportTile] = [],
             filter: ReportFilter = ReportFilter(-1, 0)) raises:
    """Writes the table as it stands (every alive row, the edits applied), the sheet's charts and pivots, and the
    Report (its tiles and filter) to `path` (.omx)."""
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
    meta += '], "objects": ['
    for k in range(len(objects)):
        ref o = objects[k]
        meta += ("," if k > 0 else "") + ('{"kind": ' + String(o.kind) + ', "x": ' + String(o.x) + ', "y": ' + String(o.y) + ', "w": ' + String(o.w)
                                          + ', "h": ' + String(o.h) + ', "value": ' + String(o.value) + ', "group": ' + String(o.group)
                                          + ', "across": ' + String(o.across) + ', "style": ' + String(o.style) + "}")
    meta += '], "report": {"tiles": ['
    for k in range(len(tiles)):
        meta += ("," if k > 0 else "") + '{"kind": ' + String(tiles[k].kind) + ', "col": ' + String(tiles[k].col) + ', "group": ' + String(tiles[k].group) + "}"
    meta += '], "filter": {"col": ' + String(filter.col) + ', "code": ' + String(filter.code) + "}}}"
    var names = Python.list()
    var addresses = Python.list()
    for c in range(stored):
        names.append(base.cols[c].name)
        addresses.append(Int(columns[c].unsafe_ptr()))
    var py = bridge()
    _ = py.write(path, rows, names, addresses, meta)
    _ = len(columns)


def format_from(o: PythonObject) raises -> ColumnFormat:
    """A saved format, or Automatic if it isn't one this code can draw."""
    var f = ColumnFormat(Int(py=o["style"]), Int(py=o["decimals"]), Bool(py=o["thousands"]), Bool(py=o["parens"]), String(py=o["symbol"]))
    return f^ if f.valid() else ColumnFormat.auto()


def open_document(path: String, mut objects: List[SheetObject], mut tiles: List[ReportTile], mut filter: ReportFilter) raises -> Frame:
    """Reads `path` (.omx): returns the table and fills in the sheet's objects and the Report. An object or tile
    that names a column the table doesn't have (or a kind this code doesn't know) is left out rather than trusted."""
    var py = bridge()
    var frame = open_omx(path)
    var meta = py.meta_of(path)
    var columns = frame.columns()
    var stored = frame.stored()
    objects = List[SheetObject]()
    var specs = meta.get("objects", Python.list())
    for k in range(Int(py=specs.__len__())):
        var o = specs[k]
        var kind = Int(py=o["kind"])
        var value = Int(py=o["value"])
        var group = Int(py=o["group"])
        var across = Int(py=o["across"])
        if (kind != OBJ_CHART and kind != OBJ_PIVOT) or not (0 <= value < columns) or not (0 <= group < stored) or not (-1 <= across < stored):
            continue
        var obj = SheetObject.chart(value, group, Int(py=o["x"]), Int(py=o["y"]), Int(py=o["w"]), Int(py=o["h"]))
        obj.kind = kind
        obj.across = across
        obj.style = Int(py=o["style"])
        objects.append(obj^)
    tiles = List[ReportTile]()
    var report = meta.get("report", Python.dict())
    var tile_specs = report.get("tiles", Python.list())
    for k in range(Int(py=tile_specs.__len__())):
        var t = tile_specs[k]
        var kind = Int(py=t["kind"])
        var col = Int(py=t["col"])
        var group = Int(py=t["group"])
        if not (TILE_SUM <= kind <= TILE_CHART) or not (0 <= col < columns) or (kind == TILE_CHART and not (0 <= group < stored)):
            continue
        tiles.append(new_tile(kind, col, group))
    var f = report.get("filter", Python.dict())
    filter = ReportFilter(Int(py=f.get("col", -1)), Int(py=f.get("code", 0)))
    if not (-1 <= filter.col < stored):
        filter = ReportFilter(-1, 0)
    return frame^


def open_omx(path: String) raises -> Frame:
    """Reads `path` (.omx): the table, its formula columns and every column's format."""
    var py = bridge()
    var read: PythonObject
    try:
        read = py.read(path, MAX_COLS)
    except e:
        raise Error("can't open " + path + ": " + String(e))
    var meta = read["meta"]
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
