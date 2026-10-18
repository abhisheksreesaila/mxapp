"""Makes tests/fixtures/format1.omx with the OLD writer: the pyarrow bridge of mojoui/omxfile.mojo as it was before F-138c
(commit c31d8da), run unchanged, so the refusal of format-1 files is tested against a file the app really wrote.

    pixi run python tests/fixtures/make_v1.py
"""

import ctypes
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
old = subprocess.run(["git", "show", "c31d8da:mojoui/omxfile.mojo"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
bridge = old.split('comptime OMX_BRIDGE = """')[1].split('"""')[0].replace('\\"', '"')
ns = {}
exec(bridge, ns)

names = ["name", "amount"]
columns = [(ctypes.c_int64 * 3)(0, 1, 0), (ctypes.c_int64 * 3)(100, 250, 975)]
fmt = {"style": 0, "decimals": -1, "thousands": True, "parens": False, "symbol": "$"}
meta = json.dumps({"omx": 1, "columns": [{"name": "name", "kind": 2, "scale": 0, "format": fmt, "dictionary": ["Acme", "Beta"]},
                                         {"name": "amount", "kind": 1, "scale": 2, "format": fmt}], "formulas": [], "objects": [],
                   "report": {"tiles": [], "filter": {"col": -1, "code": 0}}})
ns["write"](str(ROOT / "tests/fixtures/format1.omx"), 3, names, [ctypes.addressof(c) for c in columns], meta)
