import base64, io, re
from pathlib import Path
from PIL import Image
D = Path("docs/design/mxstudio-app")
import sys
PREFIX = sys.argv[1] if len(sys.argv) > 1 else ""  # "" (relative, for the repo) or an absolute folder
OUT = sys.argv[2] if len(sys.argv) > 2 else "compare.html"
def img(name, w=1280):
    im = Image.open(D / f"{name}.png").convert("RGB")
    w = min(w, im.width)
    im = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
    im.save(D / f"{name}.jpg", "JPEG", quality=82)
    return f"{PREFIX}{name}.jpg"
art = (D / "claude-artboards.html").read_text()
style = re.search(r"<style>.*?</style>", art, re.S).group(0)
boards = {m.group(1): m.group(0) for m in re.finditer(r'<div class="ab" id="claude-(\w+)">.*?(?=\n<!-- =|\Z)', art, re.S)}
def claude(key):
    return f'<div class="scale"><div class="inner">{boards[key]}</div></div>'
def stitch(name, cap=""):
    return f'<figure><img src="{img(name)}" alt="Stitch: {name}"><figcaption>{cap}</figcaption></figure>'
steps = [
 ("1 · Start", "First launch. Stitch: four equal choices plus a drop zone. Claude: one focal drop zone, three smaller starts, and a 'first time here' path through the sample.",
  stitch("01-start"), claude("start")),
 ("2 · Import a CSV", "Check the columns before the table exists. Both show a type chip and a small histogram per column. Claude adds 'before you import' findings (bad dates, duplicate names) and where to put the table.",
  stitch("02-import"), claude("import")),
 ("3 · The sheet", "Numbers-style: a toolbar of icon-over-label buttons, sheet tabs, the table as an object on a canvas, and a docked inspector. Stitch also drew an 'islands' variant (floating chrome, as the app looks today). Claude puts a pivot, a chart and a finding beside the table, and its inspector applies a format to the whole column.",
  stitch("03-sheet-classic", "Stitch · Numbers classic") + stitch("04-sheet-islands", "Stitch · islands"), claude("sheet")),
 ("4 · Insert a chart", "Stitch only for now: an Insert-chart popover (2D, 3D, interactive) and a chart inspector.",
  stitch("05-insert-chart"), '<div class="todo">Claude version: next round, if you want it.</div>'),
 ("5 · A report from scratch", "A Report tab that you build tile by tile from the same table; its filters apply to every tile. Claude keeps an empty 'add a tile' slot and a pin-to-report finding.",
  stitch("06-report"), claude("report")),
 ("6 · Phone", "Stitch only: view and light edits, a bottom sheet for the selected cell, a floating tab bar. The phone and tablet are a later, smaller app.",
  stitch("07-phone-sheet"), '<div class="todo">Phone and tablet come after the desktop app.</div>'),
]
html = ["""<!doctype html><html><head><meta charset="utf-8"><title>MX Studio · the complete app · Stitch and Claude</title>
<style>
body{margin:0;background:#0e0e14;color:#a9b1d6;font:14px/1.5 "JetBrains Mono",ui-monospace,monospace}
header{padding:28px 32px 8px}h1{color:#c0caf5;font-size:22px;margin:0 0 6px}header p{margin:4px 0;max-width:1100px}
section{padding:18px 32px 26px;border-top:1px solid #2a2e40}h2{color:#c0caf5;font-size:17px;margin:0 0 4px}
.note{color:#7f88b0;max-width:1200px;margin:0 0 14px}
.pair{display:grid;grid-template-columns:1fr 1fr;gap:24px;align-items:start}
.col h3{font-size:12px;letter-spacing:.1em;text-transform:uppercase;margin:0 0 8px}.col.st h3{color:#e0af68}.col.cl h3{color:#7aa2f7}
figure{margin:0 0 14px}figure img{width:100%;border:1px solid #2a2e40;border-radius:6px;display:block}figcaption{color:#565f89;font-size:12px;margin-top:4px}
.scale{width:100%;aspect-ratio:1440/900;position:relative;overflow:hidden;border:1px solid #2a2e40;border-radius:6px;container-type:inline-size}
.scale .inner{position:absolute;left:0;top:0;width:1440px;height:900px;transform-origin:0 0}
.todo{border:1px dashed #414868;border-radius:6px;padding:40px;text-align:center;color:#565f89}
.legend{display:flex;gap:18px;margin:8px 0 0}.legend span b{color:#c0caf5}
</style>""" + style + """</head><body>
<header><h1>MX Studio as a complete app: open a CSV, shape it, report on it</h1>
<p>Modelled on Apple Numbers: a toolbar of formatting and insert buttons, a properties inspector, a blank sheet you fill with tables, charts and a report. Desktop first (Linux and macOS); phone and tablet later.</p>
<p class="legend"><span><b style="color:#e0af68">Stitch</b> · Google's design tool, same Omarchy tokens</span><span><b style="color:#7aa2f7">Claude</b> · drawn here as live HTML, same tokens</span></p></header>"""]
for title, note, left, right in steps:
    html.append(f'<section><h2>{title}</h2><p class="note">{note}</p><div class="pair"><div class="col st"><h3>Stitch</h3>{left}</div><div class="col cl"><h3>Claude</h3>{right}</div></div></section>')
html.append("""<script>const fit=()=>document.querySelectorAll('.scale').forEach(s=>s.firstElementChild.style.transform=`scale(${s.clientWidth/1440})`);addEventListener('resize',fit);fit();</script></body></html>""")
(D / OUT).write_text("\n".join(html))
print(len("\n".join(html)) // 1024, "KB")
