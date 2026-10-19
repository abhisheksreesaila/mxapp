"""Builds docs/design/brand/: logo SVG files, the colour mockups and index.html.
Run: python3 docs/design/brand/tools/build.py   (no dependencies; shoot.py then takes the PNGs)"""
import pathlib, html, re
import marks
from contrast import ratio, mix

OUT = pathlib.Path(__file__).resolve().parents[1]
FONTS = '../../../mojoui/hosts/static/fonts'

# ---------- colour directions ----------
DIRS = {
    'A': dict(name='Ledger green', feel='Numbers, Sheets and Excel country: says "spreadsheet" before anything else; calm, trustworthy, a little expected.',
              acc='#0e7a43', hover='#0c6a3a', pressed='#0a5a31', top='#1f9a5c', dark='#4ade80',
              notes='"true" pills and the accent are now the same family; keep the pills a lighter, yellower green (#16a34a on #dcfce7) so a selection never reads as "good".',
              semantic={}),
    'B': dict(name='Signal red', feel='Tableau-style energy: bold, confident, unmistakable in a dock; the loudest of the four. (Spotify\'s own colour is a green, closer to A.)',
              acc='#c8243f', hover='#a91f35', pressed='#8f1a2d', top='#e0465c', dark='#fb7185',
              notes='Red already means "false", "negative" and "error" in a sheet. In this mockup the false pills turn neutral grey; negative numbers and errors would need a second red or an icon. The biggest functional cost of the four.',
              semantic={'bad': '#64748b', 'badbg': 'rgba(100,116,139,.12)'}),
    'C': dict(name='Iris indigo', feel='A confident blue-violet: modern, technical, GPU-night; leaves green and red free to mean yes/no and up/down.',
              acc='#4f46e5', hover='#4338ca', pressed='#3730a3', top='#6d66f0', dark='#818cf8',
              notes='Close to Linear, Stripe and a hundred SaaS apps, so less ownable; the formula-value purple (#6a4fd6) would move to cyan (#0e7490) so formulas never look like links.',
              semantic={}),
    'D': dict(name='Deep lagoon', feel='Today\'s teal, refined: deeper and cleaner (less grey), and it now passes AA as text on its own selection wash.',
              acc='#00707e', hover='#006570', pressed='#005962', top='#0f8f9c', dark='#2dd4bf',
              notes='The least change: if what you disliked was teal itself, this won\'t fix it. The wins are the solid active button and AA on the wash, which every direction gets.',
              semantic={}),
}
CURRENT = '#0e7c86'
WHITE, RAISED = '#ffffff', '#f6f8fb'


def rgb(h):
    h = h.lstrip('#'); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgba(h, a):
    r, g, b = rgb(h); return f'rgba({r},{g},{b},{a})'


for k, d in DIRS.items():
    d['wash'] = rgba(d['acc'], .10)
    d['sel'] = rgba(d['acc'], .08)
    washed = mix(d['acc'], WHITE, .10)
    d['checks'] = [
        ('White text on accent (buttons)', ratio('#ffffff', d['acc']), 4.5),
        ('White text on pressed', ratio('#ffffff', d['pressed']), 4.5),
        ('Accent text on white', ratio(d['acc'], WHITE), 4.5),
        ('Accent text on its wash', ratio(d['acc'], washed), 4.5),
        ('Selection ring vs white (UI, 3:1)', ratio(d['acc'], WHITE), 3.0),
        ('Dark-mode tint on ink #0f172a', ratio(d['dark'], '#0f172a'), 4.5),
    ]
CURRENT_CHECKS = (ratio('#ffffff', CURRENT), ratio(CURRENT, mix(CURRENT, WHITE, .10)))

# Logo default colour (the files) = the recommended direction
REC_LOGO, REC_DIR = 1, 'C'
LOGO_FOR_DIR = {'A': 2, 'B': 3, 'C': 1, 'D': 5}  # each mockup pairs a direction with a logo, so both get seen in place

# ---------- icons (Lucide paths, 24 grid, 1.5 stroke) ----------
I = {
    'save': '<path d="M15.2 3a2 2 0 0 1 1.4.6l3.8 3.8a2 2 0 0 1 .6 1.4V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path d="M17 21v-7a1 1 0 0 0-1-1H8a1 1 0 0 0-1 1v7"/><path d="M7 3v4a1 1 0 0 0 1 1h7"/>',
    'undo': '<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>',
    'addrow': '<path d="M11 12H3"/><path d="M16 6H3"/><path d="M16 18H3"/><path d="M18 9v6"/><path d="M21 12h-6"/>',
    'sigma': '<path d="M18 7V5a1 1 0 0 0-1-1H6.5a.5.5 0 0 0-.4.8l4.5 6a2 2 0 0 1 0 2.4l-4.5 6a.5.5 0 0 0 .4.8H17a1 1 0 0 0 1-1v-2"/>',
    'sort': '<path d="m21 16-4 4-4-4"/><path d="M17 20V4"/><path d="m3 8 4-4 4 4"/><path d="M7 4v16"/>',
    'pivot': '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 9h18"/><path d="M3 15h18"/><path d="M9 3v18"/>',
    'chart': '<path d="M3 3v16a2 2 0 0 0 2 2h16"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/>',
    'bold': '<path d="M6 12h9a4 4 0 0 1 0 8H7a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h7a4 4 0 0 1 0 8"/>',
    'italic': '<path d="M19 4h-9"/><path d="M14 20H5"/><path d="M15 4 9 20"/>',
    'underline': '<path d="M6 4v6a6 6 0 0 0 12 0V4"/><path d="M4 20h16"/>',
    'strike': '<path d="M16 4H9a3 3 0 0 0-2.83 4"/><path d="M14 12a4 4 0 0 1 0 8H6"/><path d="M4 12h16"/>',
    'textcolor': '<path d="M4 20h16"/><path d="m6 16 6-12 6 12"/><path d="M8 12h8"/>',
    'fill': '<path d="m19 11-8-8-8.6 8.6a2 2 0 0 0 0 2.8l5.2 5.2c.8.8 2 .8 2.8 0L19 11Z"/><path d="m5 2 5 5"/><path d="M2 13h15"/><path d="M22 20a2 2 0 1 1-4 0c0-1.6 1.7-2.4 2-4 .3 1.6 2 2.4 2 4Z"/>',
    'al': '<path d="M15 12H3"/><path d="M17 18H3"/><path d="M21 6H3"/>',
    'ac': '<path d="M17 12H7"/><path d="M19 18H5"/><path d="M21 6H3"/>',
    'ar': '<path d="M21 12H9"/><path d="M21 18H7"/><path d="M21 6H3"/>',
    'dollar': '<path d="M12 2v20"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>',
    'percent': '<path d="M19 5 5 19"/><circle cx="6.5" cy="6.5" r="2.5"/><circle cx="17.5" cy="17.5" r="2.5"/>',
    'decless': '<path d="M3 21h.01"/><path d="M10 18H7a3 3 0 0 1 0-6h0"/><path d="m13 15-3 3 3 3"/><path d="M14 7a3 3 0 0 0-6 0"/>',
    'decmore': '<path d="M3 21h.01"/><path d="M18 18h3"/><path d="m18 15 3 3-3 3"/><path d="M10 6a2 2 0 1 1 4 0v4a2 2 0 1 1-4 0z"/><path d="M15 6a2 2 0 1 1 4 0v4a2 2 0 1 1-4 0z"/>',
    'clear': '<path d="M4 7V4h16v3"/><path d="M5 20h6"/><path d="M13 4 8 20"/><path d="m15 15 5 5"/><path d="m20 15-5 5"/>',
    'brush': '<path d="m14.6 17.9-10.7-2.9"/><path d="M18.4 2.6a1 1 0 1 1 3 3L17.4 9.6a.5.5 0 0 0 0 .7l.9.9a2.4 2.4 0 0 1 0 3.4l-.9.9a.5.5 0 0 1-.7 0L8.4 7.3a.5.5 0 0 1 0-.7l.9-.9a2.4 2.4 0 0 1 3.4 0l.9.9a.5.5 0 0 0 .7 0z"/><path d="M9 8c-1.8 2.7-4 3.5-6.6 3.9a.5.5 0 0 0-.3.8l7.3 8.9a1 1 0 0 0 1.2.2C12.7 20.4 16 16.8 16 15"/>',
    'open': '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M12 12v6"/><path d="m15 15-3-3-3 3"/>',
    'plus': '<path d="M5 12h14"/><path d="M12 5v14"/>',
    'chev': '<path d="m6 9 6 6 6-6"/>',
    'x': '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    'check': '<path d="M20 6 9 17l-5-5"/>',
    'sheet': '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 9h18"/><path d="M3 15h18"/><path d="M9 3v18"/>',
    'fx': '<path d="M10 4h-1.5a2 2 0 0 0-2 2l-1 12a2 2 0 0 1-2 2H2"/><path d="M4 11h7"/><path d="m14 9 6 8"/><path d="m20 9-6 8"/>',
}


def ic(name, size=17):
    return (f'<svg class="ic" width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
            f'stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">{I[name]}</svg>')


# ---------- the mockups ----------
ROWS = [(1, '7196.89', 'North', '2025-06-26', 'false'), (2, '9228.08', 'North', '2025-05-10', 'false'),
        (3, '2725.48', 'Central', '2025-11-25', 'false'), (4, '8906.97', 'East', '2025-05-31', 'true'),
        (5, '9145.94', 'West', '2025-03-19', 'true'), (6, '9495.12', 'East', '2025-02-13', 'true'),
        (7, '4316.13', 'East', '2025-07-05', 'true'), (8, '787.51', 'East', '2025-04-10', 'false'),
        (9, '3347.41', 'West', '2025-03-03', 'true'), (10, '6089.71', 'Central', '2025-07-13', 'true'),
        (11, '2188.88', 'South', '2025-12-27', 'true'), (12, '6558.51', 'South', '2025-01-27', 'true'),
        (13, '3519.69', 'West', '2025-09-26', 'true'), (14, '973.28', 'Central', '2025-03-28', 'true')]

BASE_CSS = """
@font-face { font-family: Inter; font-weight: 400; src: url(FONTS/Inter-Regular.ttf); }
@font-face { font-family: Inter; font-weight: 500; src: url(FONTS/Inter-Medium.ttf); }
@font-face { font-family: Inter; font-weight: 600; src: url(FONTS/Inter-SemiBold.ttf); }
@font-face { font-family: "JetBrains Mono"; font-weight: 400; src: url(FONTS/JetBrainsMono-Regular.ttf); }
""".replace('FONTS', FONTS)

APP_CSS = BASE_CSS + """
* { box-sizing: border-box; margin: 0; }
html, body { width: 1280px; height: 720px; overflow: hidden; }
body { font: 13px/1.35 Inter, system-ui, sans-serif; font-feature-settings: "tnum"; color: #334155;
  background: linear-gradient(#eef2f7, #e6ebf2); position: relative; }
.glass { position: absolute; background: rgba(255,255,255,.62); backdrop-filter: blur(24px) saturate(1.6);
  border: 1px solid rgba(255,255,255,.75); box-shadow: inset 0 1px 0 rgba(255,255,255,.9), 0 8px 32px rgba(15,23,42,.10), 0 1px 2px rgba(15,23,42,.06); }
.ic { flex: none; }
.menubar { left: 10px; right: 10px; top: 8px; height: 38px; border-radius: 14px; display: flex; align-items: center; padding: 0 8px 0 10px; gap: 2px; }
.brand { display: flex; align-items: center; gap: 7px; font-weight: 600; color: #0f172a; font-size: 14px; letter-spacing: -.2px; margin-right: 14px; }
.brand svg { display: block; }
.menu { padding: 5px 10px; border-radius: 8px; color: #334155; }
.chip { font-size: 12px; padding: 3px 10px; border-radius: 99px; background: rgba(15,23,42,.06); color: #64748b; white-space: nowrap; }
.gpu { background: rgba(22,163,74,.10); color: #166534; border: 1px solid rgba(22,163,74,.25); display: flex; align-items: center; gap: 6px; }
.dot { width: 7px; height: 7px; border-radius: 50%; background: #16a34a; display: inline-block; }
.toolbar { left: 10px; right: 10px; top: 52px; border-radius: 18px; display: flex; align-items: center; padding: 6px 8px; gap: 2px; }
.tb { display: flex; align-items: center; gap: 6px; height: 34px; padding: 0 9px; border-radius: 12px; color: #334155; font-weight: 500; font-size: 12.5px; white-space: nowrap; }
.tb.hover { background: rgba(15,23,42,.05); }
.tb.on { background: var(--acc); color: var(--on); box-shadow: 0 1px 2px rgba(15,23,42,.18), inset 0 1px 0 rgba(255,255,255,.18); }
.sep { width: 1px; height: 20px; background: rgba(15,23,42,.10); margin: 0 6px; }
.grow { flex: 1; }
.formula { left: 20px; width: 902px; top: 106px; height: 36px; display: flex; align-items: center; gap: 14px; position: absolute; }
.formula .ref { color: #64748b; width: 110px; padding-left: 36px; font-size: 12.5px; }
.formula .fx { position: absolute; left: 10px; top: 10px; color: #64748b; }
.formula .in { flex: 1; height: 30px; border-radius: 10px; background: #fff; border: 1px solid rgba(15,23,42,.10); font: 13px "JetBrains Mono", monospace; color: #0f172a; display: flex; align-items: center; padding-left: 10px; }
.card { position: absolute; background: #fff; border-radius: 16px; box-shadow: 0 1px 2px rgba(15,23,42,.06), 0 4px 16px rgba(15,23,42,.05); }
.sheetcard { left: 20px; top: 152px; width: 924px; height: 460px; padding: 16px 12px 0; overflow: hidden; }
.sheetcard h2 { font-size: 15px; font-weight: 600; color: #0f172a; margin: 2px 0 12px 0; padding-left: 0; display: flex; gap: 10px; align-items: baseline; }
.sheetcard h2 span { font-size: 12.5px; font-weight: 500; color: var(--acc); }
table { border-collapse: collapse; width: 100%; font-size: 13px; }
th { background: #f6f8fb; text-align: left; font-weight: 500; color: #0f172a; height: 30px; padding: 0 8px; border-right: 1px solid rgba(15,23,42,.07); }
th small { font: 10px "JetBrains Mono", monospace; color: #94a3b8; margin-left: 6px; padding: 1px 4px; border-radius: 4px; background: rgba(15,23,42,.05); }
td { height: 26px; padding: 0 8px; border-bottom: 1px solid rgba(15,23,42,.07); border-right: 1px solid rgba(15,23,42,.07); color: #0f172a; white-space: nowrap; }
td.n { text-align: right; } td.g { color: #94a3b8; text-align: right; width: 64px; font-size: 12px; border-right: none; }
tr.selrow td { background: var(--sel); } tr.selrow td.g { color: var(--acc); font-weight: 500; }
td.cur { position: relative; }
td.cur::after { content: ""; position: absolute; inset: -1px; border: 2px solid var(--acc); border-radius: 4px; }
td.cur::before { content: ""; position: absolute; right: -5px; bottom: -5px; width: 8px; height: 8px; border-radius: 50%; background: var(--acc); border: 1.5px solid #fff; z-index: 2; }
.pill { font-size: 11.5px; font-weight: 500; padding: 1px 7px; border-radius: 99px; }
.p-true { color: #15803d; background: #dcfce7; } .p-false { color: var(--bad); background: var(--badbg); }
.insp { right: 20px; top: 104px; width: 300px; height: 528px; border-radius: 18px; padding: 12px; }
.seg { display: flex; background: rgba(15,23,42,.06); border-radius: 99px; padding: 3px; }
.seg div { flex: 1; text-align: center; padding: 5px 0; border-radius: 99px; color: #334155; font-weight: 500; font-size: 12.5px; }
.seg .on { background: #fff; color: #0f172a; box-shadow: 0 1px 3px rgba(15,23,42,.14); }
.cap { font-size: 11px; font-weight: 500; letter-spacing: .4px; text-transform: uppercase; color: #64748b; margin: 16px 0 6px; }
.insp h3 { font-size: 15px; font-weight: 600; color: #0f172a; }
.insp p { font-size: 12px; color: #64748b; margin-top: 6px; }
.hr { height: 1px; background: rgba(15,23,42,.08); margin: 14px 0 0; }
.select { height: 32px; border-radius: 10px; background: #fff; border: 1px solid rgba(15,23,42,.12); display: flex; align-items: center; justify-content: space-between; padding: 0 10px; color: #0f172a; }
.row { display: flex; align-items: center; justify-content: space-between; margin-top: 12px; color: #0f172a; }
.step { display: flex; gap: 18px; color: #0f172a; }
.cb { width: 22px; height: 22px; border-radius: 6px; background: var(--acc); color: var(--on); display: grid; place-items: center; }
.negs { display: flex; background: rgba(15,23,42,.06); border-radius: 99px; padding: 3px; font-size: 12px; }
.negs div { padding: 4px 12px; border-radius: 99px; } .negs .on { background: #fff; box-shadow: 0 1px 3px rgba(15,23,42,.14); }
.stats { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.stat { background: #fff; border: 1px solid rgba(15,23,42,.07); border-radius: 12px; padding: 8px 10px; }
.stat b { display: block; color: #0f172a; font-size: 15px; font-weight: 600; margin-top: 2px; } .stat { font-size: 12px; color: #64748b; }
.tabs { left: 10px; right: 10px; top: 638px; height: 36px; border-radius: 14px; display: flex; align-items: center; padding: 0 4px; gap: 4px; }
.tab { display: flex; align-items: center; gap: 7px; padding: 5px 14px; border-radius: 99px; font-weight: 500; color: #334155; }
.tab.on { background: #fff; color: #0f172a; box-shadow: 0 1px 3px rgba(15,23,42,.14); }
.tab.on .ic { color: var(--acc); }
.status { left: 10px; right: 10px; top: 680px; height: 30px; border-radius: 12px; display: flex; align-items: center; padding: 0 14px; gap: 18px; font-size: 12px; color: #64748b; }
.gpuline { color: #475569; display: flex; align-items: center; gap: 6px; font-size: 12.5px; padding-right: 8px; }
/* report */
.rtool { height: 64px; }
.lbl { display: flex; flex-direction: column; gap: 2px; font-size: 11.5px; color: #64748b; padding: 0 6px; }
.dd { height: 30px; border-radius: 10px; background: #fff; border: 1px solid rgba(15,23,42,.12); display: flex; align-items: center; gap: 8px; padding: 0 8px; color: #0f172a; font-size: 13px; }
.title { position: absolute; left: 28px; top: 128px; display: flex; align-items: baseline; gap: 14px; }
.title h1 { font-size: 22px; font-weight: 700; letter-spacing: -.3px; color: #0f172a; }
.title span { font-size: 12.5px; color: #64748b; } .title .ms { color: #15803d; }
.tile { width: 295px; height: 150px; padding: 18px 18px 14px; display: flex; flex-direction: column; }
.tile .h { display: flex; justify-content: space-between; color: #64748b; font-size: 13px; }
.tile .h .ic { color: #94a3b8; }
.tile .num { font-size: 34px; font-weight: 600; letter-spacing: -.6px; color: #0f172a; margin-top: 10px; padding-bottom: 6px; border-bottom: 1px solid rgba(15,23,42,.08); }
.tile .num.acc { color: var(--acc); }
.tile .f { display: flex; justify-content: space-between; align-items: center; margin-top: 10px; font-size: 12.5px; color: #64748b; }
.tile .f .chip { color: #475569; }
.addtile { width: 295px; height: 150px; border: 1.5px dashed rgba(15,23,42,.16); border-radius: 16px; position: absolute; display: grid; place-items: center; color: #64748b; }
.addtile div { display: flex; gap: 8px; align-items: center; }
.rinsp { right: 20px; top: 124px; width: 300px; height: 506px; border-radius: 18px; padding: 12px; }
.kv { display: flex; justify-content: space-between; margin-top: 8px; color: #0f172a; }
.kv span:first-child { color: #334155; }
"""


def menubar(d, logo):
    m = marks.tile(logo, d['acc'], d['top'], f'mb{logo}', size=20)
    menus = ''.join(f'<div class="menu">{x}</div>' for x in ('File', 'Edit', 'View', 'Insert', 'Data', 'Format', 'Help'))
    return (f'<div class="glass menubar"><div class="brand">{m}omxplorer</div>{menus}<div class="grow"></div>'
            f'<div class="chip">small · 5,000 rows</div>&nbsp;<div class="chip gpu"><span class="dot"></span>NVIDIA GeForce RTX 3090 · ready</div></div>')


def tabs_status(report=False):
    t = (f'<div class="glass tabs"><div class="tab{"" if report else " on"}">{ic("sheet", 16)}small</div>'
         f'<div class="tab{" on" if report else ""}">{ic("chart", 16)}Report</div><div class="grow"></div>'
         f'<div class="gpuline"><span class="dot"></span>NVIDIA GeForce RTX 3090 · ready</div></div>')
    s = ('<div class="glass status"><span>Selection amount · row 1 · 7196.89</span><span>Rows 5,000</span><span>Columns 5</span>'
         '<span>Sum 23,792,793.42</span><span>Average 5,009.01</span><span>Imported 5,000 rows from small.parquet</span>'
         '<span class="grow"></span><span>0.1 ms on the GPU</span></div>')
    return t + s


def vars_css(d):
    bad = d['semantic'].get('bad', '#dc2626'); badbg = d['semantic'].get('badbg', '#fee2e2')
    return (f':root {{ --acc: {d["acc"]}; --acc-hover: {d["hover"]}; --acc-pressed: {d["pressed"]}; --wash: {d["wash"]}; '
            f'--sel: {d["sel"]}; --on: #ffffff; --bad: {bad}; --badbg: {badbg}; }}')


def page(title, d, body):
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><title>{html.escape(title)}</title>'
            f'<style>{APP_CSS}{vars_css(d)}</style></head><body>{body}</body></html>')


def sheet_html(k):
    d = DIRS[k]; logo = LOGO_FOR_DIR[k]
    tools = (f'<div class="tb">{ic("save")}</div><div class="tb">{ic("undo")}</div><div class="grow"></div>'
             + ''.join(f'<div class="tb">{ic(n)}</div>' for n in ('addrow', 'sigma', 'sort', 'pivot', 'chart')) + '<div class="sep"></div>'
             + ''.join(f'<div class="tb">{ic(n)}</div>' for n in ('bold', 'italic', 'underline', 'strike')) + '<div class="sep"></div>'
             + ''.join(f'<div class="tb">{ic(n)}</div>' for n in ('textcolor', 'fill')) + '<div class="sep"></div>'
             + ''.join(f'<div class="tb">{ic(n)}</div>' for n in ('al', 'ac', 'ar')) + '<div class="sep"></div>'
             + ''.join(f'<div class="tb">{ic(n)}</div>' for n in ('dollar', 'percent', 'decless', 'decmore', 'clear'))
             + f'<div class="grow"></div><div class="tb on">{ic("brush")}Format</div><div class="tb">{ic("open")}Open</div>')
    rows = ''
    for i, (n, amt, reg, day, paid) in enumerate(ROWS):
        rows += (f'<tr class="{"selrow" if i == 0 else ""}"><td class="g">{n}</td><td class="n">{n}</td>'
                 f'<td class="n{" cur" if i == 0 else ""}">{amt}</td><td>{reg}</td><td>{day}</td>'
                 f'<td><span class="pill p-{paid}">{paid}</span></td><td style="border-right:none;width:40%"></td></tr>')
    body = (menubar(d, logo) + f'<div class="glass toolbar">{tools}</div>'
            f'<div class="formula"><span class="fx">{ic("fx", 15)}</span><span class="ref">amount 1</span><div class="in">7196.89</div></div>'
            f'<div class="card sheetcard"><h2>small <span>5,000 rows</span></h2><table><tr><th style="width:64px"></th><th style="width:80px">order<small>#</small></th>'
            f'<th style="width:106px">amount<small>0.0</small></th><th style="width:104px">region<small>Aa</small></th><th style="width:104px">day<small>date</small></th>'
            f'<th style="width:92px">paid<small>bool</small></th><th style="border-right:none"></th></tr>{rows}</table></div>'
            f'<div class="glass insp"><div class="seg"><div>Table</div><div class="on">Cell</div></div>'
            f'<div class="cap">Column</div><h3>amount · Decimal</h3><p>A format applies to the whole column: the cells, the totals below, and everything that reads it.</p>'
            f'<div class="hr"></div><div class="cap">Data format</div><div class="select">Automatic {ic("chev", 15)}</div>'
            f'<div class="row">Decimals<div class="step"><span>–</span><span>2</span><span>+</span></div></div>'
            f'<div class="row">Thousands separator<div class="cb">{ic("check", 15)}</div></div>'
            f'<div class="row">Negatives<div class="negs"><div class="on">−1,234</div><div>(1,234)</div></div></div>'
            f'<div class="hr"></div><div class="cap">Column stats</div><div class="stats">'
            f'<div class="stat">Mean<b>5,009.01</b></div><div class="stat">Median<b>5,005.54</b></div>'
            f'<div class="stat">Empty<b>250</b></div><div class="stat">Distinct<b>4,741</b></div></div></div>'
            + tabs_status())
    return page(f'omxplorer · sheet · {k} {d["name"]}', d, body)


def report_html(k):
    d = DIRS[k]; logo = LOGO_FOR_DIR[k]
    tools = (f'<div class="tb">{ic("save")}Save</div><div class="tb">{ic("undo")}Undo</div><div class="sep"></div>'
             f'<div class="lbl">Tiles of<div class="dd">amount {ic("chev", 15)}</div></div>'
             + ''.join(f'<div class="tb">{ic("plus", 16)}{x} tile</div>' for x in ('Sum', 'Average', 'Median', 'Distinct', 'Count'))
             + f'<div class="tb">{ic("chart", 16)}Chart tile</div><div class="sep"></div>'
             f'<div class="lbl">Filter · every tile<div class="dd">Every row {ic("chev", 15)}</div></div><div class="grow"></div>'
             f'<div class="tb on">{ic("brush")}Format</div><div class="tb">{ic("open")}Open</div>')
    tiles = [('Sum of amount', '23,792,793.42', 'every row', '5,000 matched', True),
             ('Median of amount', '5,005.54', 'every row', 'p50 exact', False),
             ('Average of amount', '5,009.01', 'every row', 'of 4,750 values', False),
             ('Count of rows', '5,000', 'every row', '100.0% of rows', False)]
    pos = [(28, 162), (336, 162), (643, 162), (28, 324)]
    t = ''
    for (lab, num, chip, fact, acc), (x, y) in zip(tiles, pos):
        t += (f'<div class="card tile" style="left:{x}px;top:{y}px"><div class="h">{lab}{ic("x", 15)}</div>'
              f'<div class="num{" acc" if acc else ""}">{num}</div><div class="f"><span class="chip">{chip}</span>{fact}</div></div>')
    t += f'<div class="addtile" style="left:336px;top:324px"><div>{ic("plus", 16)}Add a tile from the toolbar</div></div>'
    body = (menubar(d, logo) + f'<div class="glass toolbar rtool">{tools}</div>'
            f'<div class="title"><h1>Report</h1><span>small · every row</span><span>5,000 of 5,000 rows · <span class="ms">0.1 ms on the GPU</span></span></div>'
            + t +
            f'<div class="glass rinsp"><div class="seg"><div class="on">Report</div></div><div class="cap">Data</div>'
            f'<div class="kv"><span>Source</span><span>small</span></div><div class="kv"><span>Rows</span><span>5,000</span></div>'
            f'<div class="kv"><span>Filter</span><span>every row</span></div><p style="font-size:12px;color:#64748b;margin-top:10px">Edits in the table show here at once. Add tiles and set the filter in the toolbar.</p></div>'
            + tabs_status(report=True))
    return page(f'omxplorer · report · {k} {d["name"]}', d, body)


# ---------- logo files ----------
def write_logos():
    rec = DIRS[REC_DIR]
    for n, name, _ in marks.CONCEPTS:
        (OUT / f'logo-{n}-icon.svg').write_text(marks.tile(n, rec['acc'], rec['top'], f'L{n}', size=1024))
        (OUT / f'logo-{n}-icon-light.svg').write_text(marks.tile(n, rec['acc'], rec['top'], f'L{n}', size=1024, light=True))
        (OUT / f'logo-{n}-mark.svg').write_text(marks.mark(n, rec['acc'], f'L{n}'))
        (OUT / f'logo-{n}-wordmark.svg').write_text(marks.lockup_inline(n, rec['acc'], '#0f172a', f'L{n}', height=100))
        (OUT / f'logo-{n}-lockup.svg').write_text(marks.lockup_beside(n, rec['acc'], rec['top'], '#0f172a', f'L{n}', height=100))


# ---------- index ----------
INDEX_CSS = BASE_CSS + """
* { box-sizing: border-box; }
html { background: linear-gradient(#eef2f7, #e6ebf2); min-height: 100%; }
body { margin: 0; font: 14px/1.5 Inter, system-ui, sans-serif; color: #334155; }
main { max-width: 1320px; margin: 0 auto; padding: 36px 28px 80px; }
h1 { font-size: 30px; letter-spacing: -.5px; color: #0f172a; margin: 0 0 6px; }
h2 { font-size: 20px; color: #0f172a; margin: 48px 0 6px; letter-spacing: -.2px; }
.lead { color: #64748b; max-width: 860px; margin: 0; }
.k { display: inline-grid; place-items: center; min-width: 28px; height: 28px; padding: 0 8px; border-radius: 99px; background: #0f172a; color: #fff; font-weight: 600; font-size: 13px; margin-right: 8px; }
.grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 14px; margin-top: 18px; }
.card { background: #fff; border-radius: 16px; box-shadow: 0 1px 2px rgba(15,23,42,.06), 0 4px 16px rgba(15,23,42,.05); padding: 16px; }
.card h3 { margin: 0 0 4px; font-size: 15px; color: #0f172a; display: flex; align-items: center; }
.card p { font-size: 12.5px; color: #64748b; margin: 6px 0 0; }
.sizes { display: flex; align-items: flex-end; gap: 14px; margin: 12px 0; }
.sizes svg { display: block; }
.lab { font-size: 10.5px; color: #94a3b8; text-align: center; margin-top: 3px; }
.duo { display: grid; grid-template-columns: 1fr 1fr; border-radius: 12px; overflow: hidden; border: 1px solid rgba(15,23,42,.07); }
.duo > div { padding: 12px 10px; display: flex; flex-direction: column; gap: 10px; align-items: flex-start; justify-content: center; min-height: 110px; }
.duo .dk { background: #0f172a; }
.duo svg { max-width: 100%; height: auto; }
.duo > div > svg:first-child { width: 100%; }
.duo .mini { display: flex; align-items: center; gap: 8px; }
.picker { display: flex; gap: 8px; margin-top: 14px; flex-wrap: wrap; align-items: center; font-size: 13px; }
.picker button { font: inherit; border: 1px solid rgba(15,23,42,.12); background: #fff; border-radius: 99px; padding: 5px 12px 5px 6px; display: flex; gap: 8px; align-items: center; cursor: pointer; color: #0f172a; }
.picker button.on { border-color: #0f172a; box-shadow: 0 0 0 1px #0f172a; }
.picker i { width: 18px; height: 18px; border-radius: 50%; display: inline-block; }
.cols { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 14px; margin-top: 18px; }
.sw { display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; margin: 12px 0; }
.sw div { height: 56px; border-radius: 10px; color: #fff; font-size: 11px; padding: 6px 8px; display: flex; flex-direction: column; justify-content: space-between; }
.sw2 { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; }
.sw2 div { min-height: 44px; overflow-wrap: anywhere; border-radius: 10px; font-size: 11px; padding: 6px 8px; border: 1px solid rgba(15,23,42,.07); }
code { font: 11.5px "JetBrains Mono", monospace; }
.feel { font-size: 13px; color: #334155; margin: 6px 0 0; }
.btns { display: flex; gap: 8px; margin: 12px 0; align-items: center; flex-wrap: wrap; }
.btn { border-radius: 99px; padding: 6px 14px; font-weight: 500; font-size: 13px; }
.cell { position: relative; padding: 4px 10px; border-radius: 4px; font-size: 13px; color: #0f172a; }
table.ct { width: 100%; border-collapse: collapse; font-size: 12px; margin-top: 8px; }
.ct td { padding: 4px 0; border-top: 1px solid rgba(15,23,42,.06); }
.ct td:nth-child(2) { text-align: right; font-weight: 600; color: #0f172a; font-feature-settings: "tnum"; }
.ct td:nth-child(3) { text-align: right; width: 54px; }
.ok { color: #15803d; font-weight: 600; } .no { color: #b91c1c; font-weight: 600; }
.note { font-size: 12px; color: #64748b; margin-top: 10px; }
.mock { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-top: 14px; }
.mock img { width: 100%; display: block; border-radius: 12px; box-shadow: 0 1px 2px rgba(15,23,42,.08), 0 8px 24px rgba(15,23,42,.08); }
.mock a { color: inherit; text-decoration: none; } .mock figcaption { font-size: 12.5px; color: #64748b; margin-top: 6px; }
.dirhead { display: flex; align-items: center; gap: 10px; margin-top: 34px; }
.dirhead b { font-size: 16px; color: #0f172a; }
.rec { background: #0f172a; color: #cbd5e1; border-radius: 18px; padding: 24px 26px; margin-top: 18px; display: grid; grid-template-columns: 300px 1fr; gap: 28px; align-items: center; }
.rec h3 { color: #fff; margin: 0 0 8px; font-size: 18px; }
.rec p { margin: 0 0 10px; font-size: 14px; }
.rec b { color: #fff; }
.ref img { width: 100%; border-radius: 12px; margin-top: 12px; }
.now { background: #fff; border-radius: 12px; padding: 12px; display: flex; gap: 14px; align-items: center; margin-top: 14px; font-size: 13px; }
.now img { height: 60px; border-radius: 8px; }
"""


def fmt(r, need):
    return f'<td>{r:.2f}:1</td><td class="{"ok" if r >= need else "no"}">{"AA" if r >= need else "fails"}</td>'


def cssify(svg):
    """var() is not allowed in SVG presentation attributes; move those into style."""
    return re.sub(r'(fill|stroke|stop-color)="(var\([^)]*\))"', r'style="\1:\2"', svg)


def index_html():
    rec = DIRS[REC_DIR]
    # logo cards
    cards = ''
    for n, name, desc in marks.CONCEPTS:
        big = marks.tile(n, 'var(--acc)', 'var(--top)', f'i{n}a', size=112)
        s32 = marks.tile(n, 'var(--acc)', 'var(--top)', f'i{n}b', size=32)
        s16 = marks.tile(n, 'var(--acc)', 'var(--top)', f'i{n}c', size=16)
        light = marks.tile(n, 'var(--acc)', 'var(--top)', f'i{n}d', size=48, light=True)
        inline_l = marks.lockup_inline(n, 'var(--acc)', '#0f172a', f'i{n}e', height=34)
        inline_d = marks.lockup_inline(n, 'var(--dark)', '#ffffff', f'i{n}f', height=34)
        beside_l = marks.lockup_beside(n, 'var(--acc)', 'var(--top)', '#0f172a', f'i{n}g', height=26)
        beside_d = marks.lockup_beside(n, 'var(--acc)', 'var(--top)', '#ffffff', f'i{n}h', height=26)
        mark_d = marks.mark(n, '#fff', f'i{n}i', size=32)
        cards += (f'<div class="card" id="logo-{n}"><h3><span class="k">{n}</span>{name}</h3>'
                  f'<div class="sizes"><div>{big}<div class="lab">1024 tile</div></div><div>{light}<div class="lab">light</div></div>'
                  f'<div>{s32}<div class="lab">32</div></div><div>{s16}<div class="lab">16</div></div></div>'
                  f'<div class="duo"><div>{inline_l}{beside_l}</div><div class="dk">{inline_d}<div class="mini">{beside_d}</div></div></div>'
                  f'<p>{html.escape(desc)}</p></div>')
    picker = ''.join(f'<button data-k="{k}" class="{"on" if k == REC_DIR else ""}"><i style="background:{d["acc"]}"></i>{k} · {d["name"]}</button>'
                     for k, d in DIRS.items())
    # colour columns
    cols = ''
    for k, d in DIRS.items():
        rows = ''.join(f'<tr><td>{html.escape(lab)}</td>{fmt(r, need)}</tr>' for lab, r, need in d['checks'])
        cols += (f'<div class="card" id="colour-{k}"><h3><span class="k">{k}</span>{d["name"]}</h3><p class="feel">{html.escape(d["feel"])}</p>'
                 f'<div class="sw"><div style="background:{d["acc"]}"><span>accent</span><code>{d["acc"]}</code></div>'
                 f'<div style="background:{d["hover"]}"><span>hover</span><code>{d["hover"]}</code></div>'
                 f'<div style="background:{d["pressed"]}"><span>pressed</span><code>{d["pressed"]}</code></div></div>'
                 f'<div class="sw2"><div style="background:{d["wash"]};color:{d["acc"]}">wash (active, selected row)<br><code>{d["wash"]}</code></div>'
                 f'<div style="background:#0f172a;color:{d["dark"]}">on dark (logo, focus)<br><code>{d["dark"]}</code></div></div>'
                 f'<div class="btns"><span class="btn" style="background:{d["acc"]};color:#fff">Format</span>'
                 f'<span class="btn" style="background:{d["wash"]};color:{d["acc"]}">5,000 rows</span>'
                 f'<span class="cell" style="background:{d["sel"]};outline:2px solid {d["acc"]};outline-offset:-2px">7196.89</span></div>'
                 f'<div style="font-size:12px">text on accent <code>#ffffff</code> · selection ring <code>2px {d["acc"]}</code> · selection fill <code>{d["sel"]}</code></div>'
                 f'<table class="ct">{rows}</table><p class="note"><b>Con:</b> {html.escape(d["notes"])}</p></div>')
    # mockups
    mocks = ''
    for k, d in DIRS.items():
        lg = LOGO_FOR_DIR[k]
        mocks += (f'<div class="dirhead" id="mock-{k}"><span class="k" style="background:{d["acc"]}">{k}</span><b>{d["name"]}</b>'
                  f'<span style="color:#64748b;font-size:13px">with logo {lg} in the menu bar · <code>{d["acc"]}</code></span></div>'
                  f'<div class="mock"><figure style="margin:0"><a href="mockups/{k}-sheet.html"><img src="mockups/{k}-sheet.png" alt="{k} sheet"></a>'
                  f'<figcaption>{k}1 · Sheet (click for the live HTML)</figcaption></figure>'
                  f'<figure style="margin:0"><a href="mockups/{k}-report.html"><img src="mockups/{k}-report.png" alt="{k} report"></a>'
                  f'<figcaption>{k}2 · Report</figcaption></figure></div>')
    rec_tile = marks.tile(REC_LOGO, rec['acc'], rec['top'], 'rec', size=120)
    rec_word = marks.lockup_inline(REC_LOGO, rec['dark'], '#ffffff', 'recw', height=44)
    dvars = ''.join(f'body.dir-{k} {{ --acc: {d["acc"]}; --top: {d["top"]}; --dark: {d["dark"]}; }}' for k, d in DIRS.items())
    js = ("document.querySelectorAll('.picker button').forEach(b=>b.onclick=()=>{document.body.className='dir-'+b.dataset.k;"
          "document.querySelectorAll('.picker button').forEach(x=>x.classList.toggle('on',x===b));});")
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>omxplorer · logo and colour</title><style>{INDEX_CSS}{dvars}</style></head><body class="dir-{REC_DIR}"><main>
<h1>omxplorer · logo and colour</h1>
<p class="lead">Eight logo concepts (numbers 1–8) and four accent colours (letters A–D), each colour shown on the real Sheet and Report screens. Reply with something like <b>"logo 1 + colour C"</b>, or mix: "logo 5's idea, logo 8's pixels". Everything here is Liquid light, Inter, the same layout; only the accent and the mark change.</p>
<div class="now"><img src="../../goals/25/after-report-1280x720.jpg" alt="today"><div><b>Today:</b> teal <code>{CURRENT}</code>, no mark, and the active button is a grey-teal wash. White on it is {CURRENT_CHECKS[0]:.2f}:1 (passes), but teal text on its own wash is {CURRENT_CHECKS[1]:.2f}:1 (<span class="no">fails AA</span>), which is part of why the active "Format" button looks muddy. Every direction below makes the active button a <b>solid accent pill with white text</b> and keeps accent text above 4.5:1 on its wash.</div></div>

<h2>1 · Logo concepts</h2>
<p class="lead">The o is a magnifying lens in all but the wildcards' twists. Each card: the 1024 app-icon tile (shown at 112 px), the light tile, the tile at its real 32 and 16 px, then the wordmark on light and dark: the mark as the o ("·mxplorer", handle down-left so it never hits the m) and the tile beside "omxplorer". Pick a colour to recolour every mark:</p>
<div class="picker">{picker}</div>
<div class="grid">{cards}</div>
<details class="ref" style="margin-top:16px"><summary style="cursor:pointer;color:#64748b;font-size:13px">Stitch's draft of the same brief (reference only: its marks are stock Material icons, not ownable logos; it did suggest the mark-as-the-o wordmark, used above)</summary><img src="stitch/stitch-logos.png" alt="Stitch logo board"></details>

<h2>2 · Accent colours</h2>
<p class="lead">Each direction: accent, hover, pressed, the wash for the active tool and selected row, the dark-mode tint, and WCAG 2 contrast (AA = 4.5:1 for text, 3:1 for the selection ring). Good green #16a34a, warning #d97706 and the Inter/Liquid tokens stay as they are unless the con says otherwise.</p>
<div class="cols">{cols}</div>

<h2>3 · Mockups</h2>
<p class="lead">The goal-25 Sheet and Report screens at 1280×720, rebuilt in HTML from the screenshots and the Liquid tokens. Each colour is paired with a different logo so you see four marks in place; any logo goes with any colour.</p>
{mocks}

<h2>4 · Recommendation</h2>
<div class="rec"><div style="display:flex;flex-direction:column;gap:18px;align-items:flex-start">{rec_tile}{rec_word}</div><div>
<h3>Logo 1 (Lens · bars) + colour C (Iris indigo, {rec['acc']})</h3>
<p><b>Why logo 1:</b> it is the idea you described, a magnifying glass as the o, showing data, and it is the one that still reads at 16 px: a ring, a handle and three bars are three shapes, nothing finer. It also works as the o in the wordmark. <b>Cons:</b> it is the most literal; a lens over a bar chart is a common "analytics" icon (Stitch drew a stock one), so on its own it is not very ownable. If you want something only omxplorer could have, logo 5 (the selection ring with the fill handle) is the cleverer runner-up, at the price of reading less instantly as a magnifier.</p>
<p><b>Why colour C:</b> in a spreadsheet, green and red are already taken: they mean true/false, up/down, good/error. A green accent (A) blends into every "true" pill and into Excel; a red one (B) makes the selection ring look like an error and forces the "false" pills grey. Indigo leaves both free, has the most contrast headroom of the four (6.3:1 white on accent, 5.3:1 on its own wash) and looks distinct from Numbers, Sheets and Excel. <b>Cons:</b> it is the house colour of many SaaS tools, so it is less ownable than red; the formula-value purple has to move to cyan; and it is not the green or red you leaned towards. If being recognised as "a spreadsheet" matters more than the yes/no colours, A is the honest second choice.</p>
</div></div>
</main><script>{js}</script></body></html>"""


if __name__ == '__main__':
    write_logos()
    (OUT / 'mockups').mkdir(exist_ok=True)
    for k in DIRS:
        (OUT / 'mockups' / f'{k}-sheet.html').write_text(sheet_html(k).replace(FONTS, '../' + FONTS))
        (OUT / 'mockups' / f'{k}-report.html').write_text(report_html(k).replace(FONTS, '../' + FONTS))
    (OUT / 'index.html').write_text(cssify(index_html()))
    for k, d in DIRS.items():
        print(k, d['name'], d['acc'], ' '.join(f'{r:.2f}' for _, r, _ in d['checks']))
    print('current', CURRENT, [round(x, 2) for x in CURRENT_CHECKS])
