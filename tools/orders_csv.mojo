# Writes the planted orders ledger (mojoui/orders.mojo) as a CSV file, the way a person would bring their data
# to omxplorer: plain text, dates as YYYY-MM-DD, money with two decimals, names as text.
#   pixi run mojo build -I . tools/orders_csv.mojo -o build/orders_csv && build/orders_csv 1000000 build/data/orders_1m.csv
from std.python import Python
from std.sys import argv
from mojoui.orders import order_columns
from mojoui.frame import INT, DECIMAL, TEXT, DATE

comptime WRITER = """
import os, numpy as np, pyarrow as pa, pyarrow.csv as pv
def write(path, rows, names, kinds, scales, addresses, dictionaries):
    import ctypes
    cols = {}
    for name, kind, scale, address, words in zip(names, kinds, scales, addresses, dictionaries):
        raw = np.frombuffer((ctypes.c_int64 * int(rows)).from_address(int(address)), dtype=np.int64)
        if kind == 1:
            cols[name] = pa.array(raw / (10 ** scale)).cast(pa.decimal128(18, scale))
        elif kind == 3:
            cols[name] = pa.array(raw.astype(np.int32), pa.int32()).cast(pa.date32())
        elif kind == 2:
            cols[name] = pa.DictionaryArray.from_arrays(pa.array(raw.astype(np.int32)), pa.array(words)).cast(pa.string())
        else:
            cols[name] = pa.array(raw)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    pv.write_csv(pa.table(cols), path)
"""


def main() raises:
    var args = argv()
    var rows = Int(String(args[1])) if len(args) > 1 else 1_000_000
    var path = String(args[2]) if len(args) > 2 else String("build/data/orders_1m.csv")
    var cols = order_columns(rows)
    var types = Python.import_module("types")
    var builtins = Python.import_module("builtins")
    var mod = types.ModuleType("orders_csv_writer")
    _ = builtins.exec(WRITER, mod.__dict__)
    var names = Python.list()
    var kinds = Python.list()
    var scales = Python.list()
    var addresses = Python.list()
    var dictionaries = Python.list()
    for c in cols.cols:
        names.append(c.name)
        kinds.append(c.kind)
        scales.append(c.scale)
        addresses.append(Int(c.values.unsafe_ptr()))
        var words = Python.list()
        for w in c.dictionary:
            words.append(w)
        dictionaries.append(words)
    _ = mod.write(path, cols.rows, names, kinds, scales, addresses, dictionaries)
    print("wrote", path, cols.rows, "rows")
