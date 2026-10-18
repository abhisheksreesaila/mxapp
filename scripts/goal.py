"""Runs milestones of an archived goal checker without rebuilding (they ignore arguments when loaded as scripts):
    pixi run python scripts/goal.py 14 M2 M3     goal 14's m2 and m3, headless, printing PASS/FAIL and the message
"""

import importlib.util
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import headless  # noqa: E402

headless.ensure()
number = sys.argv[1]
spec = importlib.util.spec_from_file_location("goal" + number, next((ROOT / "docs/goals").glob(f"{number}-check.py")))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
ok_all = True
for name in sys.argv[2:]:
    t0 = time.time()
    try:
        ok, msg = getattr(mod, name.lower())()
    except Exception as e:
        ok, msg = False, f"crashed: {e!r}"
    ok_all &= ok
    print(f"{'PASS' if ok else 'FAIL'}  {name}  {msg}  ({time.time() - t0:.0f} s)", flush=True)
sys.exit(0 if ok_all else 1)
