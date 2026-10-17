"""Downloads the Stitch screens, renders the Claude artboards per option at actual size, and writes compare.html."""
import json, pathlib, subprocess, urllib.request
here = pathlib.Path(__file__).parent
out = here / "img"; out.mkdir(exist_ok=True)
OPTS = [("ledger", "A · Ledger"), ("graphite", "B · Graphite"), ("blueprint", "C · Blueprint")]
SCREENS = ["sheet", "report", "phone"]
src = (here / "claude.html").read_text()
links = {}
for opt, _ in OPTS:
    for s in SCREENS:
        j = here / f"stitch-{opt}-{s}.json"
        try:
            d = json.loads(j.read_text())["data"]
            urllib.request.urlretrieve(d["imageUrl"] + ("=w1440" if s != "phone" else "=w780"), out / f"stitch-{opt}-{s}.png")
            urllib.request.urlretrieve(d["htmlCode"]["downloadUrl"], out / f"stitch-{opt}-{s}.html")
            links[(opt, s)] = d["canvasUrl"]
        except Exception as e:
            print("stitch", opt, s, "missing:", e)
    # Claude: one page per screen at actual size
    for k, (fn, w, h) in enumerate([("sheet()", 1440, 900), ("report()", 1440, 900), ("phone()", 390, 844)]):
        page = src.replace('<body>', '<body class="big" style="margin:0;background:#fff">').replace(
            'document.getElementById("main").innerHTML = OPTIONS.map',
            f'document.querySelector("header").remove(); document.getElementById("main").innerHTML = `<div class="{opt}">${{{fn}}}</div>`; [].map')
        tmp = here / f".claude-{opt}-{k}.html"; tmp.write_text(page)
        subprocess.run(["chromium", "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--window-size={w},{h}",
                        "--virtual-time-budget=4000", f"--screenshot={out}/claude-{opt}-{SCREENS[k]}.png", f"file://{tmp}"],
                       stderr=subprocess.DEVNULL, check=True)
        tmp.unlink()
cell = lambda f, cap: f'<figure><a href="img/{f}" target="_blank"><img src="img/{f}"></a><figcaption>{cap}</figcaption></figure>' if (out / f).exists() else f'<figure class="none"><figcaption>{cap}: not generated</figcaption></figure>'
rows = ""
for opt, name in OPTS:
    rows += f'<section><h2>{name}</h2>'
    for s in SCREENS:
        st = links.get((opt, s), "")
        rows += f'<div class="pair {s}">{cell(f"stitch-{opt}-{s}.png", "Stitch · " + s + (f" · <a href={st} target=_blank>open in Stitch</a>" if st else ""))}{cell(f"claude-{opt}-{s}.png", "Claude · " + s)}</div>'
    rows += "</section>"
(here / "compare.html").write_text(f"""<!doctype html><meta charset=utf-8><title>omxplorer · universal theme · Stitch vs Claude</title>
<style>body{{margin:0;background:#0b0c0e;color:#ddd;font:14px Inter,system-ui,sans-serif}} header{{padding:16px 28px;border-bottom:1px solid #222}}
h1{{font-size:16px;margin:0}} header p{{margin:4px 0 0;color:#8a8c93}} section{{padding:22px 28px;border-bottom:1px solid #1d1e22}} h2{{margin:0 0 12px;font-size:18px}}
.pair{{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin-bottom:18px}} .pair.phone{{grid-template-columns:repeat(2,300px)}}
figure{{margin:0}} img{{width:100%;border-radius:8px;box-shadow:0 0 0 1px #2a2b30;display:block}} figcaption{{font-size:12px;color:#8a8c93;margin-top:6px}} a{{color:#9ab}}
.none{{border:1px dashed #333;border-radius:8px;padding:20px}}</style>
<header><h1>omxplorer · one theme on every platform · Stitch (left) vs Claude (right)</h1>
<p>Three directions, each the sheet, the Report and the phone. Click any image for full size. Live Claude artboards: claude.html.</p></header>{rows}""")
print("wrote", here / "compare.html")
