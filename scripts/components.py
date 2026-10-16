"""The component × platform matrix, generated from the code (docs/components.md), so it can't drift.

  pixi run python scripts/components.py          # rewrite docs/components.md
  pixi run python scripts/components.py --check  # exit 1 if docs/components.md is out of date (scripts/check runs this)

A cell is:
  ✅  implemented in that host AND run by a check on that platform (the example that proves it is listed)
  🔨  implemented in that host, builds, never run there (Mac and iPhone: no hardware yet; some Android screens)
  ❌  not implemented in that host (an app using it there would get nothing)

"Implemented" is read from the host source; "run" comes from which examples each platform's checks drive
(EVIDENCE below). Components that live inside one app (not in mojoui yet) are listed separately: they are
the debt to pay before the next app reuses them.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOSTS = [("Linux (GTK)", "mojoui/hosts/gtk.mojo"), ("Web", "mojoui/hosts/web.py"), ("Android", "mojoui/hosts/android.mojo"),
         ("Mac (AppKit)", "mojoui/hosts/appkit.mojo"), ("iPhone (UIKit)", "mojoui/hosts/uikit.mojo")]

# The public constructor for each node kind (mojoui/view.mojo).
COMPONENTS = [
    ("Text", "TEXT"), ("Button", "BUTTON"), ("VStack", "VSTACK"), ("HStack", "HSTACK"), ("Spacer", "SPACER"),
    ("Card", "VSTACK"), ("Scroll", "SCROLL"), ("Grid", "GRID"), ("Divider", "DIVIDER"),
    ("TextField", "FIELD"), ("TextArea", "TEXTAREA"), ("Toggle", "TOGGLE"), ("Dropdown", "DROPDOWN"), ("Slider", "SLIDER"),
    ("Segmented", "SEGMENTED"), ("Radio", "RADIO"), ("DatePicker", "DATE"), ("ProgressBar", "PROGRESS"),
    ("Image", "IMAGE"), ("Icon", "ICON"), ("Alert", "ALERT"), ("Tabs", "TABS"), ("NavBar", "NAVBAR"),
    ("LazyList", "LAZYLIST"), ("Canvas", "CANVAS"), ("Board", "BOARD"), ("Overlay", "OVERLAY"),
]

# Which examples each platform's checks actually run (docs/goals/*-check.py): GTK and the web run every
# example; the Android checks (goal 7) drive these on the emulator; Mac and iPhone only build and sign.
RUN_ON = {
    "Linux (GTK)": ["hello", "gallery", "todo", "gpu", "kitchen", "expenses", "layout", "lens", "analytics", "workbook"],
    "Web": ["hello", "gallery", "todo", "gpu", "kitchen", "expenses", "layout", "lens", "analytics", "workbook"],
    "Android": ["hello", "gallery", "layout", "lens", "todo"],
    "Mac (AppKit)": [],
    "iPhone (UIKit)": [],
}

# Variants, gestures, layout and design languages: (name, the API, a pattern that shows a host implements it,
# the example whose checks exercise it).
FEATURES = [
    ("Button with an icon", "Button(icon=…)", r"node\.hint != \"\"|n\[\"hint\"\]|adw_button_content", "workbook"),
    ("Quiet buttons", "style=SUBTLE / ICON_ONLY", r"\bSUBTLE\b|\bICON_ONLY\b", "workbook"),
    ("Lucide icon set", "Button(icon=\"table\")…", r"lucide|mojoui-", "workbook"),
    ("In-place editor", "TextField(…).focused()", r"value == 1|cell-editor", "workbook"),
    ("Layout modifiers", ".padding .width .grow .fill .align .justify", r"pad_v", "layout"),
    ("Canvas: pan, zoom, tap", "on_gesture: PAN, ZOOM, TAP", r"\bPAN\b|PAN =", "lens"),
    ("Canvas: press, release, double", "PRESS, RELEASE, DOUBLE", r"\bDOUBLE\b|DOUBLE =", "workbook"),
    ("Canvas frames (animation)", "on_frame", r"tick|SET_FRAMES|on_frame", "lens"),
    ("Board: drag, resize, snap", "Board(on_move, on_resize)", r"\bBOARD\b", "workbook"),
    ("Board: scrolls, reveals a child", "Board(reveal=, reveal_count=)", r"reveal", "workbook"),
    ("Board: phone-width list", "(automatic under 720 pt)", r"board_list|max-width: 719px", "workbook"),
    ("Overlay islands", "Overlay(base, *islands) + .pin(h, v)", r"\bOVERLAY\b", "workbook"),
    ("Design: Fluent 2", "design() = FLUENT", r"\bFLUENT\b|fluent", "analytics"),
    ("Design: Omarchy (your theme)", "design() = OMARCHY", r"\bOMARCHY\b|omarchy", "workbook"),
    ("Shared data per process", "App.init_shared()", r"init_shared", "workbook"),
]

# Built inside one app, not in mojoui yet: each should become a component before another app needs it.
APP_LOCAL = [
    ("DataGrid", "examples/workbook", "virtualised grid over millions of rows: scroll bar, column select, resize, fit, sideways scroll, "
     "sort marker, in-place editor, selection; today ~400 lines of the Workbook drawing on a Canvas"),
    ("PivotTable", "examples/workbook", "rows × columns × value pickers over a group-by, with its result grid"),
    ("Chart", "examples/workbook, examples/analytics", "a Flint spec on a Canvas with tap-to-filter; each app wires Canvas + draw() + hit() itself"),
    ("KPI tile", "examples/analytics", "a headline number with a sparkline (mojoui.charts.KpiTile, but placed by the app on a Canvas)"),
    ("FormulaBar", "examples/workbook", "what's selected, its value, a formula field"),
    ("Toolbar / StatusBar islands", "examples/workbook", "the island contents (title, Insert buttons, status) are assembled by the app"),
]


def host_text(path):
    return (ROOT / path).read_text()


def implemented(src, kind):
    """A host implements a kind if the kind's constant appears beyond its import line."""
    lines = [l for l in src.splitlines() if re.search(rf"\b{kind}\b", l)]
    lines = [l for l in lines if not re.match(r"\s*(from |\(TEXT|TEXT, |    [A-Z_, ]+,?$|\s*[A-Z_]+(, [A-Z_]+)+,?\)?( = range.*)?$)", l)]
    return bool(lines)


def used_by(example, ctor):
    p = ROOT / "examples" / example / "app.mojo"
    return p.exists() and re.search(rf"\b{ctor}\(", p.read_text()) is not None


def cell(host, src, ctor, kind):
    web_stacks = host == "Web" and kind in ("HSTACK", "VSTACK")  # (the web renders stacks in its default branch)
    if not (web_stacks or implemented(src, kind)):
        return "❌"
    proof = [e for e in RUN_ON[host] if used_by(e, ctor)]
    return "✅" if proof else "🔨"


def feature_cell(host, src, pattern, example):
    if not re.search(pattern, src):
        return "❌"
    return "✅" if example in RUN_ON[host] else "🔨"


def render():
    srcs = {h: host_text(p) for h, p in HOSTS}
    names = [h for h, _ in HOSTS]
    out = ["# Components × platforms",
           "",
           "Generated by `scripts/components.py` from the host code and the checks (don't edit by hand; `scripts/check` fails when it's stale).",
           "",
           "✅ implemented and run by a check on that platform · 🔨 implemented, builds, never run there · ❌ not implemented",
           "",
           "Mac and iPhone builds are signed but haven't run on hardware yet; Android runs on the emulator.",
           "",
           "## Components",
           "",
           "| Component | " + " | ".join(names) + " | Proven by |",
           "|---|" + "---|" * len(names) + "---|"]
    for ctor, kind in COMPONENTS:
        row = [cell(h, srcs[h], ctor, kind) for h in names]
        proof = [e for e in RUN_ON["Linux (GTK)"] if used_by(e, ctor)]
        out.append(f"| `{ctor}` | " + " | ".join(row) + f" | {', '.join(proof) or '—'} |")
    out += ["", "## Variants, gestures, layout, design languages", "",
            "| Feature | API | " + " | ".join(names) + " |",
            "|---|---|" + "---|" * len(names)]
    for name, api, pattern, example in FEATURES:
        row = [feature_cell(h, srcs[h], pattern, example) for h in names]
        out.append(f"| {name} | `{api}` | " + " | ".join(row) + " |")
    totals = {h: [cell(h, srcs[h], c, k) for c, k in COMPONENTS] + [feature_cell(h, srcs[h], p, e) for _, _, p, e in FEATURES] for h in names}
    out += ["", "## Totals", "", "| Platform | ✅ | 🔨 | ❌ |", "|---|---|---|---|"]
    for h in names:
        t = totals[h]
        out.append(f"| {h} | {t.count('✅')} | {t.count('🔨')} | {t.count('❌')} |")
    out += ["", "## Inside one app, not components yet (the debt)", "",
            "| Should become | Lives in | What it is |", "|---|---|---|"]
    for name, where, what in APP_LOCAL:
        out.append(f"| `{name}` | {where} | {what} |")
    out += ["", "## The rule", "",
            "Before building a feature: list the components it needs, mark each ✅ / 🔨 / ❌ here, build or extend the "
            "component in `mojoui/` first (its own test, every host it can reach), then build the app from it. An app never "
            "draws something another app would need; if it does, it goes in the table above until it's extracted.", ""]
    return "\n".join(out)


def main():
    doc = render()
    path = ROOT / "docs" / "components.md"
    if "--check" in sys.argv:
        if not path.exists() or path.read_text() != doc:
            print("docs/components.md is stale: run pixi run python scripts/components.py")
            return 1
        print("docs/components.md is current")
        return 0
    path.write_text(doc)
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
