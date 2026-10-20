"""Goal 27: every themed screen as a picture, so moving the themes out of the hosts can be proven to change nothing.

  pixi run python scripts/theme_shots.py shoot build/g27/before      (GTK and the web, every theme)
  pixi run python scripts/theme_shots.py compare build/g27/before build/g27/after   (share of pixels that differ, per shot)
"""

import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


g25 = load("goal25", "docs/goals/25-check.py")
run, BUILD = g25.g20.run, g25.g20.BUILD
import drive  # noqa: E402

SKINS = ["liquid", "ledger", "graphite", "blueprint"]
OMX = [  # (name, steps): omxplorer's screens
    ("start", ""),
    ("sheet", "pick:Choose a file={f};tap:Create table"),
    ("report", "pick:Choose a file={f};tap:Create table;tap:Report;tap:Sum tile;tap:Chart tile"),
    ("settings", "menu:File>Settings…"),
]
OTHERS = [  # (example, name, steps): the other examples' themes (Fluent, Omarchy, kit's switchable skins, native)
    ("hello", "native", ""),
    ("kit", "kit", ""),
    ("kit", "kit-graphite", "tap:Open dialog;radio:0=Graphite;tap:Done"),
    ("analytics", "fluent", ""),
    ("mxstudio", "omarchy", ""),
]
SIZE = (1440, 900)


def omx_env(out, tag, skin):
    g25.OUT = out
    e = g25.env(tag)
    (out / tag / "config" / "settings.txt").write_text(f"skin={skin}\ntimings=no\n")
    return e


def shoot(out: Path, others_only=False):
    out.mkdir(parents=True, exist_ok=True)
    problems = []
    for skin in ([] if others_only else SKINS):
        for name, steps in OMX:
            tag = f"omx-{skin}-{name}"
            e = omx_env(out, tag, skin)
            steps = steps.format(f=g25.small())
            r = run([str(BUILD / "omxplorer" / "linux" / "omxplorer")], env=dict(e, MOJOUI_TEST=steps, MOJOUI_WINDOW=f"{SIZE[0]}x{SIZE[1]}",
                                                                              MOJOUI_SHOT=str(out / f"{tag}-gtk.png")), timeout=600)
            if r.returncode != 0:
                problems.append(f"{tag} gtk exit {r.returncode}")
            saved = {k: os.environ.get(k) for k in e}
            os.environ.update(e)
            try:
                w, log = drive.web_run(BUILD / "omxplorer" / "web", steps, shot=str(out / f"{tag}-web.png"), viewport=SIZE)
                if w.returncode != 0:
                    problems.append(f"{tag} web: {log[-200:]}")
            finally:
                for k, v in saved.items():
                    if v is None:
                        os.environ.pop(k, None)
                    else:
                        os.environ[k] = v
    for ex, name, steps in OTHERS:
        r = run([str(BUILD / ex / "linux" / ex)], env={"MOJOUI_TEST": steps, "MOJOUI_WINDOW": f"{SIZE[0]}x{SIZE[1]}",
                                                       "MOJOUI_SHOT": str(out / f"{name}-gtk.png")}, timeout=600)
        if r.returncode != 0:
            problems.append(f"{name} gtk exit {r.returncode}: {(r.stdout + r.stderr)[-200:]}")
        w, log = drive.web_run(BUILD / ex / "web", steps, shot=str(out / f"{name}-web.png"), viewport=SIZE)
        if w.returncode != 0:
            problems.append(f"{name} web: {log[-200:]}")
    return problems


def differ(a: Path, b: Path, tol=12):
    """The share of pixels whose colour moved by more than `tol` in any one channel (1.0 when the sizes differ)."""
    from PIL import Image, ImageChops
    x, y = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if x.size != y.size:
        return 1.0
    r, g, bl = ImageChops.difference(x, y).split()
    d = ImageChops.lighter(ImageChops.lighter(r, g), bl).point(lambda v: 255 if v > tol else 0)
    return d.histogram()[255] / (x.size[0] * x.size[1])


def compare(a: Path, b: Path):
    rows = []
    for shot in sorted(a.glob("*.png")):
        other = b / shot.name
        rows.append((shot.name, differ(shot, other) if other.exists() else None))
    return rows


if __name__ == "__main__":
    if sys.argv[1] in ("shoot", "shoot-others"):
        import headless
        headless.ensure()
        p = shoot(Path(sys.argv[2]), others_only=sys.argv[1] == "shoot-others")
        print("\n".join(p) or "all shot")
    else:
        for name, share in compare(Path(sys.argv[2]), Path(sys.argv[3])):
            print(f"{'missing' if share is None else f'{share * 100:6.2f}%'}  {name}")
