# mojoui.omxfile: a document round-trips everything a session can do to a table (edits, a new word, added and
# removed rows, merged spellings, formulas, formats), and a file that isn't what its metadata says is refused
# before it reaches the engine's memory.
#   pixi run mojo build -I . tests/test_omx_files.mojo -o build/test_omx_files && pixi run build/test_omx_files build/omx-files
from std.testing import assert_equal, assert_true, assert_false
from std.python import Python
from std.sys import argv
from mojoui.frame import Frame, Column, Columns, share, INT, DECIMAL, TEXT, DATE
from mojoui.numformat import ColumnFormat, CURRENCY
from mojoui.omxfile import save_omx, open_omx
from mojoui.shared import make_dir

comptime BAD_FILES = """
import json, numpy as np, pyarrow as pa, pyarrow.parquet as pq

def col(name, kind, scale=0, words=None):
    spec = {"name": name, "kind": kind, "scale": scale, "format": {"style": 0, "decimals": -1, "thousands": True, "parens": False, "symbol": "$"}}
    if words is not None:
        spec["dictionary"] = words
    return spec

def write(path, arrays, specs, version=1, raw_meta=None):
    meta = raw_meta if raw_meta is not None else json.dumps({"omx": version, "columns": specs, "formulas": []})
    pq.write_table(pa.table(arrays).replace_schema_metadata({"omx": meta}), path)

def make(folder):
    ok = {"name": pa.array([0, 1], pa.int64()), "amount": pa.array([100, 250], pa.int64())}
    good = [col("name", 2, 0, ["Acme", "Beta"]), col("amount", 1, 2)]
    out = {}
    out["too-many-columns"] = (dict((f"c{i}", pa.array([1], pa.int64())) for i in range(17)), [col(f"c{i}", 0) for i in range(17)], 1, None)
    out["described-not-stored"] = (ok, good + [col("missing", 0)], 1, None)
    out["code-past-dictionary"] = ({"name": pa.array([0, 2], pa.int64()), "amount": ok["amount"]}, good, 1, None)
    out["negative-code"] = ({"name": pa.array([0, -1], pa.int64()), "amount": ok["amount"]}, good, 1, None)
    out["nulls"] = ({"name": ok["name"], "amount": pa.array([100, None], pa.int64())}, good, 1, None)
    out["not-integers"] = ({"name": ok["name"], "amount": pa.array([1.5, 2.5])}, good, 1, None)
    out["unknown-type"] = (ok, [col("name", 2, 0, ["Acme", "Beta"]), col("amount", 9)], 1, None)
    out["wrong-version"] = (ok, good, 2, None)
    out["not-json"] = (ok, good, 1, "{not json")
    out["good"] = (ok, good, 1, None)
    paths = {}
    for name, (arrays, specs, version, raw) in out.items():
        p = f"{folder}/{name}.omx"
        write(p, arrays, specs, version, raw)
        paths[name] = p
    return paths
"""


def main() raises:
    var args = argv()
    var folder = String(args[1]) if len(args) > 1 else String("build/omx-files")
    make_dir(folder)

    # ---- a round trip of everything a session does ----
    var cols = Columns()
    var name = Column("customer", TEXT)
    for w in ["Acme Corp", "ACME Corporation", "Beta"]:
        name.dictionary.append(w)
    var amount = Column("amount", DECIMAL)
    var day = Column("day", DATE)
    for k in range(6):
        name.values.append(Int64(k % 3))
        amount.values.append(Int64(1000 * (k + 1)))
        day.values.append(Int64(20089 + k))
    cols.add(name^)
    cols.add(amount^)
    cols.add(day^)
    var frame = Frame(share(cols^))
    frame.set_text(1, 0, "12.34")  # an edit
    frame.set_text(0, 2, "Gamma")  # a word the dictionary didn't have
    var codes = List[Int64]()
    codes.append(1)
    _ = frame.merge(0, codes, 0)  # "ACME Corporation" reads as "Acme Corp"
    frame.remove(3)  # a removed row
    var values: List[String] = ["Delta", "7.00", "2025-03-01"]
    _ = frame.append(values)  # an added row (and another new word)
    _ = frame.formula("double = amount * 2")
    frame.set_format(1, ColumnFormat(CURRENCY, 2, True, True, "€"))
    var path = folder + "/roundtrip.omx"
    save_omx(path, frame)
    var back = open_omx(path)
    assert_equal(back.rows(), 6)  # 6 − 1 removed + 1 added
    var names = List[String]()
    var amounts = List[String]()
    for r in range(back.rows()):
        names.append(back.display(0, r))
        amounts.append(back.plain_text(1, r))
    var shown_names = String("")
    for n in names:
        shown_names += n + "|"
    assert_equal(shown_names, "Acme Corp|Acme Corp|Gamma|Acme Corp|Beta|Delta|")  # (row 3 gone; merged; new words)
    assert_equal(amounts[0], "12.34")
    assert_equal(amounts[5], "7.00")
    assert_equal(back.display(2, 5), "2025-03-01")
    assert_equal(back.display(1, 0), "€12.34")  # the format came back
    assert_equal(back.name(3), "double")
    assert_equal(back.plain_text(3, 0), "24.68")  # the formula came back and computes

    # ---- files that aren't what they say ----
    var types = Python.import_module("types")
    var builtins = Python.import_module("builtins")
    var mod = types.ModuleType("bad_files")
    _ = builtins.exec(BAD_FILES, mod.__dict__)
    var paths = mod.make(folder)
    var good = open_omx(String(py=paths["good"]))
    assert_equal(good.rows(), 2)
    var refused = 0
    for bad in ["too-many-columns", "described-not-stored", "code-past-dictionary", "negative-code", "nulls", "not-integers",
                "unknown-type", "wrong-version", "not-json"]:
        var raised = False
        try:
            _ = open_omx(String(py=paths[bad]))
        except e:
            raised = True
            assert_true(String(e).startswith("can't open"), bad + ": " + String(e))
        assert_true(raised, bad + " was opened")
        refused += 1
    print("OMX FILE TESTS PASSED · round trip + " + String(refused) + " bad files refused")
