"""The eight omxplorer logo marks, drawn on a 100-unit grid.

Every mark is the letter o as a magnifying lens (centre 42,42) plus a handle, except where noted.
glyph(n, fg, uid, d) returns SVG markup in fg only (tints are opacity of fg), so a mark works in any
one colour: accent on white, white on the accent tile, white on dark. d = +1 handle down-right,
d = -1 handle down-left (used when the mark stands in for the o at the start of the wordmark)."""
import json, math, pathlib

C = 42.0          # lens centre
R = 25.0          # ring centre line
W = 9.0           # ring stroke
IN = R - W / 2    # inside radius (20.5)

CONCEPTS = [
    (1, 'Lens · bars', 'Three bars rising inside the lens: "look into your numbers". The most literal; reads at 16 px as a magnifier with something inside.'),
    (2, 'Lens · cell', 'A 3x3 grid with the centre cell filled: the spreadsheet seen through the lens. The filled cell survives at 32 px, the grid lines do not.'),
    (3, 'Lens · spark', 'A sparkline with a soft area under it: reports, trends. Friendly, closest to the analytics (Tableau) side.'),
    (4, 'Lens · chip', 'Pins round the ring and a die inside: the lens is a GPU chip. Says "hardware-fast"; the pins blur below 24 px.'),
    (5, 'Selection lens', 'Wildcard. The lens is the sheet\'s own selection ring and the handle is its fill handle: only a spreadsheet person sees the joke, everyone sees a magnifier.'),
    (6, 'Lens · rows', 'Three rows of data of different lengths: reading rows through the glass. Calm and quiet, a little generic.'),
    (7, 'Magnified points', 'Wildcard. A field of small points; inside the lens they are bigger: magnification you can see, and the GPU point cloud of the Data Lens.'),
    (8, 'Pixel lens', 'Wildcard. The lens drawn in 9x9 pixels with one data point in the middle: GPU, pixels, exact. Crisp at 16 px by construction; more playful, a bit retro.'),
]


def hx(x, d):
    """Mirror x around the lens centre when the handle goes left."""
    return x if d > 0 else 2 * C - x


def ring(fg):
    return f'<circle cx="{C}" cy="{C}" r="{R}" fill="none" stroke="{fg}" stroke-width="{W}"/>'


def handle(fg, d, x0=None, w=12):
    a = (C + R * math.cos(math.pi / 4)) if x0 is None else x0
    return (f'<line x1="{hx(a, d):.2f}" y1="{a:.2f}" x2="{hx(80, d)}" y2="80" stroke="{fg}" '
            f'stroke-width="{w}" stroke-linecap="round"/>')


def clip(uid, r=IN):
    return f'<clipPath id="{uid}c"><circle cx="{C}" cy="{C}" r="{r}"/></clipPath>'


def glyph(n, fg='#000', uid='g', d=1, field=True):
    if n == 1:
        bars = ''.join(f'<rect x="{x}" y="{y}" width="7.5" height="60" rx="2" fill="{fg}"/>'
                       for x, y in ((28.5, 47), (38.3, 37.5), (48, 28)))
        return f'<defs>{clip(uid)}</defs>{ring(fg)}<g clip-path="url(#{uid}c)">{bars}</g>{handle(fg, d)}'
    if n == 2:
        a, b = 35.5, 48.5
        lines = ''.join(f'<line x1="{v}" y1="10" x2="{v}" y2="80" />' for v in (a, b)) + \
                ''.join(f'<line x1="10" y1="{v}" x2="80" y2="{v}" />' for v in (a, b))
        return (f'<defs>{clip(uid)}</defs>{ring(fg)}<g clip-path="url(#{uid}c)">'
                f'<g stroke="{fg}" stroke-width="3.4" opacity=".5">{lines}</g>'
                f'<rect x="{a - 1}" y="{a - 1}" width="{b - a + 2}" height="{b - a + 2}" rx="2" fill="{fg}"/></g>{handle(fg, d)}')
    if n == 3:
        pts = [(14, 55), (25, 50), (32, 55), (41, 40), (48, 46), (57, 31), (72, 25)]
        # a trend still rises left to right, whichever way the handle goes
        p = ' '.join(f'{x},{y}' for x, y in pts)
        area = p + ' 72,80 14,80'
        return (f'<defs>{clip(uid)}</defs><g clip-path="url(#{uid}c)"><polygon points="{area}" fill="{fg}" opacity=".28"/>'
                f'<polyline points="{p}" fill="none" stroke="{fg}" stroke-width="5.5" stroke-linejoin="round" stroke-linecap="round"/></g>'
                f'{ring(fg)}{handle(fg, d)}')
    if n == 4:
        skip = 45 if d > 0 else 135
        pins = ''
        for ang in range(0, 360, 45):
            if ang == skip:
                continue
            t = math.radians(ang)
            x1, y1 = C + 31 * math.cos(t), C + 31 * math.sin(t)
            x2, y2 = C + 37.5 * math.cos(t), C + 37.5 * math.sin(t)
            pins += f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}"/>'
        return (f'{ring(fg)}<g stroke="{fg}" stroke-width="5" stroke-linecap="round">{pins}</g>'
                f'<rect x="{C - 9}" y="{C - 9}" width="18" height="18" rx="3.5" fill="{fg}"/>{handle(fg, d)}')
    if n == 5:
        k = 66  # corner of the selection square, on the ring's centre line
        x0 = 18 if d > 0 else 2 * C - 66
        sq = f'<rect x="{x0}" y="18" width="48" height="48" rx="9" fill="none" stroke="{fg}" stroke-width="{W}"/>'
        hxk = hx(k, d)
        return (f'<defs><mask id="{uid}m"><rect x="-10" y="-10" width="120" height="120" fill="#fff"/>'
                f'<circle cx="{hxk}" cy="{k}" r="15.5" fill="#000"/></mask></defs>'
                f'<rect x="{x0 + 6}" y="24" width="36" height="36" rx="4" fill="{fg}" opacity=".2"/>'
                f'<g mask="url(#{uid}m)">{sq}</g>'
                f'<line x1="{hxk}" y1="{k}" x2="{hx(82, d)}" y2="82" stroke="{fg}" stroke-width="11" stroke-linecap="round"/>'
                f'<circle cx="{hxk}" cy="{k}" r="9.5" fill="{fg}"/>')
    if n == 6:
        rows = ''.join(f'<line x1="27" y1="{y}" x2="{e}" y2="{y}"/>' for y, e in ((33, 55), (42, 47), (51, 58)))
        return (f'{ring(fg)}<g stroke="{fg}" stroke-width="5.2" stroke-linecap="round">{rows}</g>{handle(fg, d)}')
    if n == 7:
        small = ''
        for i in range(7):
            for j in range(7):
                x, y = 8 + 14 * i, 8 + 14 * j
                small += f'<circle cx="{x}" cy="{y}" r="2.3"/>'
        big = ''.join(f'<circle cx="{C + a}" cy="{C + b}" r="4"/>' for a in (-11, 0, 11) for b in (-11, 0, 11))
        a = C + R * math.cos(math.pi / 4)
        return (f'<defs><mask id="{uid}m"><rect x="-10" y="-10" width="120" height="120" fill="#fff"/>'
                f'<circle cx="{C}" cy="{C}" r="{R + W / 2 + 4}" fill="#000"/>'
                f'<line x1="{hx(a, d)}" y1="{a}" x2="{hx(80, d)}" y2="80" stroke="#000" stroke-width="20" stroke-linecap="round"/></mask>'
                f'{clip(uid, IN - 1.5)}</defs>'
                + (f'<g fill="{fg}" opacity=".45" mask="url(#{uid}m)">{small}</g>' if field else '') +
                f'<g fill="{fg}" clip-path="url(#{uid}c)">{big}</g>{ring(fg)}{handle(fg, d)}')
    if n == 8:
        pat = ['..###....', '.#...#...', '#.....#..', '#..#..#..', '#.....#..', '.#...#...', '..###.#..', '.......#.', '........#']
        s, o = 9.6, 0.0
        px = ''
        for r, row in enumerate(pat):
            for c, ch in enumerate(row):
                if ch == '#':
                    cc = c if d > 0 else 6 - c  # mirror around the ring's centre column (3)
                    px += f'<rect x="{o + cc * s + 6.5:.2f}" y="{r * s + 6.5:.2f}" width="{s + .3:.2f}" height="{s + .3:.2f}" rx="1"/>'
        return f'<g fill="{fg}">{px}</g>'
    raise ValueError(n)


# ---------- tiles and lockups ----------

def tile(n, acc, acc2, uid, size=100, light=False):
    """App icon: rounded square (Apple-ish 22.4% radius) with the mark centred. light=True: white tile, accent mark."""
    g = glyph(n, '#fff' if not light else acc, uid + 'g')
    bg = (f'<rect width="100" height="100" rx="22.4" fill="url(#{uid}t)"/>'
          f'<rect x=".75" y=".75" width="98.5" height="98.5" rx="21.7" fill="none" stroke="#fff" stroke-opacity=".22" stroke-width="1.5"/>')
    grad = f'<linearGradient id="{uid}t" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{acc2}"/><stop offset="1" stop-color="{acc}"/></linearGradient>'
    if light:
        bg = ('<rect width="100" height="100" rx="22.4" fill="#fff"/>'
              '<rect x=".5" y=".5" width="99" height="99" rx="21.9" fill="none" stroke="#0f172a" stroke-opacity=".10"/>')
    # the mark's box is ~12..88; nudge so the lens, the visual mass, sits near the centre
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="{size}" height="{size}">'
            f'<defs>{grad}</defs>{bg}<g transform="translate(15.5 15.5) scale(.69)">{g}</g></svg>')


WM = json.loads((pathlib.Path(__file__).with_name('wordmark.json')).read_text())


def lockup_beside(n, acc, acc2, ink, uid, height=64, weight='SemiBold'):
    """Tile + the full word omxplorer."""
    w = WM[f'{weight}:omxplorer']
    s = 46 / 1490  # ascender of l = 46 units
    base = 72
    wx = 116
    width = wx + (w['xmax']) * s + 4
    t = tile(n, acc, acc2, uid).replace('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">', '<g>').replace('</svg>', '</g>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:.0f} 100" height="{height}">{t}'
            f'<path transform="translate({wx} {base}) scale({s:.5f})" d="{w["d"]}" fill="{ink}"/></svg>')


def lockup_inline(n, acc, ink, uid, height=64, weight='SemiBold'):
    """The mark is the o: lens on the x-height, handle down-left into the descender space."""
    w = WM[f'{weight}:mxplorer']
    s = 50 / 1118  # x-height = 50 units
    base = 80
    k = 1.0  # lens outer diameter 59 vs x-height 50: a touch larger than an o, as a logo should be
    # mark (handle left) box x: 2*42-86=-2 .. 71.5 ; place lens centre at x=46, y=base-25
    gx, gy = 46 - C * k, base - 25 - C * k
    g = glyph(n, acc, uid, d=-1, field=False)
    wx = gx + (C + R + W / 2) * k + 5 - w['xmin'] * s
    x0 = -14 if n == 8 else 0  # the pixel handle reaches further left
    width = wx + w['xmax'] * s + 4 - x0
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0} 0 {width:.0f} 100" height="{height}">'
            f'<g transform="translate({gx:.2f} {gy:.2f}) scale({k})">{g}</g>'
            f'<path transform="translate({wx:.2f} {base}) scale({s:.5f})" d="{w["d"]}" fill="{ink}"/></svg>')


def mark(n, fg, uid, size=100):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="{size}" height="{size}">'
            f'<g transform="translate(6 6) scale(.97)">{glyph(n, fg, uid)}</g></svg>')
