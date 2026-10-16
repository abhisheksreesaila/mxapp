# mojoui.workbook: a workbook on disk, a folder `name.mxwb/`:
#   workbook.json    the tables (their source or Parquet file, formulas, the session's edits), the objects, the layout
#   table-<k>.parquet  a table's stored columns (only when it has no reproducible source)
# Parquet is written and read through pyarrow (Python) on Linux and the web; the Mojo-level MX frame
# API (docs/mxframe-mojo-api.md, item 19) replaces that later. The JSON is plain enough for an agent to write.

from std.python import Python, PythonObject
from mojoui.frame import Column, Columns, Frame, Row, Edit, share, base_at, INT, DECIMAL, TEXT, DATE, MAX_COLS

comptime BRIDGE = """
import ctypes, json, os

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq


def write_parquet(path, names, addresses, rows):
    cols = {}
    for name, address in zip(names, addresses):
        raw = (ctypes.c_int64 * int(rows)).from_address(int(address))
        cols[name] = pa.array(np.frombuffer(raw, dtype=np.int64))
    pq.write_table(pa.table(cols), path)


def read_parquet(path):
    \"\"\"[names, arrays] where each array is a contiguous int64 numpy array (kept alive by the caller).\"\"\"
    t = pq.read_table(path)
    arrays = [np.ascontiguousarray(t.column(n).to_numpy().astype(np.int64)) for n in t.column_names]
    return [list(t.column_names), arrays, [a.ctypes.data for a in arrays], [len(a) for a in arrays]]


def read_json(path):
    with open(path) as f:
        return json.load(f)


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
"""


def json_string(s: String) -> String:
    var out = String('"')
    for c in s.codepoint_slices():
        if c == '"':
            out += '\\"'
        elif c == "\\":
            out += "\\\\"
        elif c == "\n":
            out += "\\n"
        elif c == "\t":
            out += "\\t"
        elif c == "\r":
            out += "\\r"
        elif ord(c) < 32:
            out += "\\u00" + ("0" if ord(c) < 16 else "1") + String(ord(c) % 16) if ord(c) % 16 < 10 else "\\u00" + ("0" if ord(c) < 16 else "1") + chr(ord("a") + ord(c) % 16 - 10)
        else:
            out += c
    return out + '"'


struct Bridge(Movable):
    var py: PythonObject

    def __init__(out self) raises:
        var types = Python.import_module("types")
        var builtins = Python.import_module("builtins")
        self.py = types.ModuleType("mojoui_workbook_bridge")
        _ = builtins.exec(BRIDGE, self.py.__dict__)


@fieldwise_init
struct ObjectSpec(Copyable, Movable):
    """One object on the page, as the file holds it."""

    var kind: Int
    var title: String
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var a: Int
    var b: Int
    var c: Int
    var text: String
    var selected: Int

    def to_json(self) -> String:
        return ('{"kind": ' + String(self.kind) + ', "title": ' + json_string(self.title) + ', "x": ' + String(self.x) + ', "y": ' + String(self.y)
                + ', "w": ' + String(self.w) + ', "h": ' + String(self.h) + ', "a": ' + String(self.a) + ', "b": ' + String(self.b)
                + ', "c": ' + String(self.c) + ', "text": ' + json_string(self.text) + ', "selected": ' + String(self.selected) + "}")


def table_json(frame: Frame, source: String, parquet: String) raises -> String:
    """A table: where its stored columns come from, its formulas and the session's edits."""
    ref base = frame.base()[]
    var out = String('{"source": ') + json_string(source) + ', "parquet": ' + json_string(parquet) + ', "columns": ['
    for c in range(len(base.cols)):
        ref col = base.cols[c]
        out += ("," if c > 0 else "") + '{"name": ' + json_string(col.name) + ', "kind": ' + String(col.kind) + ', "scale": ' + String(col.scale)
        if col.kind == TEXT:
            out += ', "dictionary": ['
            for k in range(len(col.dictionary)):
                out += ("," if k > 0 else "") + json_string(col.dictionary[k])
            out += "]"
        out += "}"
    out += '], "formulas": ['
    for f in range(len(frame.formulas)):
        out += ("," if f > 0 else "") + json_string(frame.formulas[f].name + " = " + frame.formulas[f].formula)
    out += '], "words": ['
    var first = True
    for c in range(len(frame.words)):
        for w in frame.words[c]:
            out += ("" if first else ",") + "[" + String(c) + ", " + json_string(w) + "]"
            first = False
    out += '], "edits": ['
    first = True
    for item in frame.cells.items():
        out += ("" if first else ",") + "[" + String(item.key % MAX_COLS) + ", " + String(item.key // MAX_COLS) + ", " + String(item.value) + "]"
        first = False
    out += '], "added": ['
    for i in range(len(frame.added)):
        out += ("," if i > 0 else "") + "["
        for c in range(len(base.cols)):
            out += ("," if c > 0 else "") + String(frame.added[i][c])
        out += "]"
    out += '], "removed": ['
    first = True
    for row in frame.removed:
        out += ("" if first else ",") + String(row)
        first = False
    return out + "]}"


def save_workbook(path: String, frame: Frame, source: String, objects: List[ObjectSpec], widths: List[Int] = []) raises:
    """Writes `path` (a folder ending in .mxwb). Tables with a source name aren't copied: the JSON
    says how to rebuild them; others get a Parquet file beside the JSON."""
    var bridge = Bridge()
    var parquet = String("") if source != "" else String("table-0.parquet")
    if parquet != "":
        ref base = frame.base()[]
        var names = Python.list()
        var addresses = Python.list()
        for c in range(len(base.cols)):
            names.append(PythonObject(base.cols[c].name))
            addresses.append(PythonObject(Int(base.cols[c].values.unsafe_ptr())))
        _ = bridge.py.write_text(path + "/workbook.json", "")  # (makes the folder)
        _ = bridge.py.write_parquet(path + "/" + parquet, names, addresses, base.rows)
    var out = String('{"mojoui_workbook": 1, "tables": [') + table_json(frame, source, parquet) + '], "widths": ['
    for k in range(len(widths)):  # the grid's column widths in points (0 = the default for its type)
        out += ("," if k > 0 else "") + String(widths[k])
    out += '], "objects": ['
    for k in range(len(objects)):
        out += ("," if k > 0 else "") + objects[k].to_json()
    out += "]}\n"
    _ = bridge.py.write_text(path + "/workbook.json", out)


def py_str(o: PythonObject) raises -> String:
    return String(o)


def open_workbook(path: String, shared_source: String, shared_addr: Int, mut objects: List[ObjectSpec], mut base_addr: Int) raises -> Frame:
    """Reads `path`: returns the frame (its session edits applied), fills `objects` and sets `base_addr`.
    A table whose source matches the process's shared data reuses it; otherwise its Parquet file is
    loaded (and shared for the rest of the process)."""
    var bridge = Bridge()
    var doc = bridge.py.read_json(path + "/workbook.json")
    var t = doc["tables"][0]
    var source = py_str(t["source"])
    var addr = shared_addr
    if source == "" or source != shared_source:
        if py_str(t["parquet"]) == "":
            raise Error("the workbook's table has no source and no Parquet file")
        var read = bridge.py.read_parquet(path + "/" + py_str(t["parquet"]))
        var cols = Columns()
        var n = Int(py=read[0].__len__())
        for c in range(n):
            var spec = t["columns"][c]
            var col = Column(py_str(spec["name"]), Int(py=spec["kind"]), Int(py=spec["scale"]))
            var rows = Int(py=read[3][c])
            var p = Pointer[Int64, MutUntrackedOrigin](unsafe_from_address=Int(py=read[2][c]))
            col.values = List[Int64](capacity=rows)
            for i in range(rows):
                col.values.append(p[unsafe_offset=i])
            if col.kind == TEXT:
                var words = spec["dictionary"]
                for k in range(Int(py=words.__len__())):
                    col.dictionary.append(py_str(words[k]))
            cols.add(col^)
        addr = share(cols^)
    var frame = Frame(addr)
    var stored = frame.stored()
    var rows = frame.base()[].rows
    var formulas = t["formulas"]
    for k in range(Int(py=formulas.__len__())):
        _ = frame.formula(py_str(formulas[k]))
    var words = t["words"]
    for k in range(Int(py=words.__len__())):
        var c = Int(py=words[k][0])
        if c < 0 or c >= stored:
            raise Error("words: column " + String(c) + " doesn't exist")
        frame.words[c].append(py_str(words[k][1]))
    var added = t["added"]
    for k in range(Int(py=added.__len__())):
        var r = Row(0)
        var width = Int(py=added[k].__len__())
        if width > stored:
            raise Error("added row " + String(k) + " has " + String(width) + " values for " + String(stored) + " columns")
        for c in range(width):
            r[c] = Int64(Int(py=added[k][c]))
        frame.added.append(r)
    var edits = t["edits"]
    for k in range(Int(py=edits.__len__())):
        var c = Int(py=edits[k][0])
        var row = Int(py=edits[k][1])
        if c < 0 or c >= stored or row < 0 or row >= frame.rows():
            raise Error("edit " + String(k) + " names column " + String(c) + ", row " + String(row) + ": not in the table")
        frame.set(c, row, Int64(Int(py=edits[k][2])))
    var removed = t["removed"]
    for k in range(Int(py=removed.__len__())):
        var row = Int(py=removed[k])
        if row < 0 or row >= frame.rows():
            raise Error("removed row " + String(row) + ": not in the table")
        frame.remove(row)
    _ = rows
    frame.log = List[Edit]()  # what the file holds isn't undoable
    objects = List[ObjectSpec]()
    var objs = doc["objects"]
    for k in range(Int(py=objs.__len__())):
        var o = objs[k]
        objects.append(ObjectSpec(Int(py=o["kind"]), py_str(o["title"]), Int(py=o["x"]), Int(py=o["y"]), Int(py=o["w"]), Int(py=o["h"]),
                                  Int(py=o["a"]), Int(py=o["b"]), Int(py=o["c"]), py_str(o["text"]), Int(py=o["selected"])))
    base_addr = addr
    return frame^


def read_widths(path: String) raises -> List[Int]:
    """The grid's column widths saved with the workbook (empty if it has none: older files)."""
    var bridge = Bridge()
    var doc = bridge.py.read_json(path + "/workbook.json")
    var out = List[Int]()
    if Bool(py=doc.__contains__("widths")):
        var w = doc["widths"]
        for k in range(Int(py=w.__len__())):
            out.append(max(0, min(Int(py=w[k]), 2000)))
    return out^

