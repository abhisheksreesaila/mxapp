"""Draws the launch page's isometric diagram (one app.mojo -> three layers -> five platforms + agent tools).
Prints an <svg> to paste into docs/index.html's hero. Each part has data-o, its place in the build on load
(plate, layers bottom up, each platform's wire and tile, agent tools). Run: python3 docs/launch/iso.py"""
S = 24
C, H = 0.8660254, 0.5

def P(x, y, z=0.0):
    return ((x - y) * C * S, (x + y) * H * S - z * S)

def pts(*ps):
    return " ".join(f"{a:.1f},{b:.1f}" for a, b in ps)

def box(x0, y0, x1, y1, z0, z1, cls):
    """Top, +x face (down-right) and +y face (down-left) of a box."""
    top = pts(P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1))
    fx = pts(P(x1, y0, z1), P(x1, y1, z1), P(x1, y1, z0), P(x1, y0, z0))
    fy = pts(P(x0, y1, z1), P(x1, y1, z1), P(x1, y1, z0), P(x0, y1, z0))
    return (f'<polygon class="fy {cls}" points="{fy}"/><polygon class="fx {cls}" points="{fx}"/>'
            f'<polygon class="tp {cls}" points="{top}"/>')

def floor_text(x, y, z, s, cls, anchor="middle"):
    """Text lying on a horizontal plane, running along +x."""
    X, Y = P(x, y, z)
    return (f'<text class="{cls}" text-anchor="{anchor}" transform="matrix({C:.4f},{H:.4f},{-C:.4f},{H:.4f},{X:.1f},{Y:.1f})">{s}</text>')

def floor_text_y(x, y, z, s, cls, anchor="middle"):
    """Text lying on a horizontal plane, running along -y (up-right on screen)."""
    X, Y = P(x, y, z)
    return (f'<text class="{cls}" text-anchor="{anchor}" transform="matrix({C:.4f},{-H:.4f},{C:.4f},{H:.4f},{X:.1f},{Y:.1f})">{s}</text>')

def side_text(x, y, z, s, cls):
    """Text on a +x face, running along -y, upright."""
    X, Y = P(x, y, z)
    return f'<text class="{cls}" text-anchor="middle" transform="matrix({C:.4f},{-H:.4f},0,1,{X:.1f},{Y:.1f})">{s}</text>'

out = []
# wires on the floor, under everything: base plate edge -> bus at x=7 -> tile
PLATS = [("Linux", "runs", -7.6, 4), ("Web", "runs", -3.8, 5), ("Android", "runs", 0.0, 6),
         ("Mac", "builds", 3.8, 7), ("iPhone", "builds", 7.6, 8)]
TX = 12.0  # tile centre x
for name, st, y, w in PLATS:
    d = "M{:.1f},{:.1f} L{:.1f},{:.1f} L{:.1f},{:.1f} L{:.1f},{:.1f}".format(*P(4.2, 0), *P(6.6, 0), *P(6.6, y), *P(TX - 1.7, y))
    out.append(f'<g class="wire" data-o="{w}"><path pathLength="1" d="{d}"/></g>')
d = "M{:.1f},{:.1f} L{:.1f},{:.1f}".format(*P(0, 4.2), *P(0, 9.6))
out.append(f'<g class="wire" data-o="9"><path pathLength="1" d="{d}"/></g>')
# the file: a thin violet-edged plate
out.append('<g class="plate" data-o="0">' + box(-4.2, -4.2, 4.2, 4.2, 0, 0.35, "pl")
           + floor_text(0, 3.75, 0.35, "app.mojo", "t-file") + "</g>")
# three layers, exploded upwards until their word lights
LAYERS = [("GPU code", 1, 0.75), ("data engine", 2, 1.95), ("controls", 3, 3.15)]
for name, w, z in LAYERS:
    out.append(f'<g class="slab" data-o="{w}">' + box(-3.3, -3.3, 3.3, 3.3, z, z + 0.85, "sl")
               + side_text(3.3, 0, z + 0.32, name.upper(), "t-side") + "</g>")
# platform tiles, back to front
for name, st, y, w in PLATS:
    out.append(f'<g class="tile" data-o="{w}">' + box(TX - 1.7, y - 1.7, TX + 1.7, y + 1.7, 0, 0.4, "tl")
               + floor_text_y(TX + 0.1, y, 0.4, name, "t-tile")
               + floor_text_y(TX + 1.0, y, 0.4, st, "t-st " + ("ok" if st == "runs" else "info")) + "</g>")
out.append('<g class="tile agent" data-o="9">' + box(-2.6, 9.6, 2.6, 12.6, 0, 0.4, "tl ag")
           + floor_text(0, 11.0, 0.4, "agent tools", "t-tile") + floor_text(0, 11.9, 0.4, "buttons · fields", "t-st") + "</g>")

xs, ys = [], []
import re
for m in re.finditer(r'points="([^"]+)"', "".join(out)):
    for p in m.group(1).split():
        a, b = map(float, p.split(",")); xs.append(a); ys.append(b)
pad = 12
x0, y0, x1, y1 = min(xs) - pad, min(ys) - pad - 40, max(xs) + pad, max(ys) + pad
print(f'<svg class="iso" viewBox="{x0:.0f} {y0:.0f} {x1 - x0:.0f} {y1 - y0:.0f}" role="img" '
      f'aria-label="One app.mojo file holds three layers, the controls, the data engine and the GPU code. '
      f'Wires run from it to Linux, Web and Android, which run, Mac and iPhone, which build, and to agent tools.">'
      + "".join(out) + "</svg>")
