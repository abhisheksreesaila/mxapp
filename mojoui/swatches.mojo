# mojoui.swatches: a colour picker drawn on a Canvas: "automatic" (a square with a slash) and mojoui.cellstyle's
# eight colours, in one row; a tap picks one. As text colours they show as a letter in the colour; as fills, as the
# tint a cell gets. Put it in a Popover under the tool that opened it.
#
#   Popover("fill-colour", "Fill", SwatchPicker(5, version, on_gesture=SWATCH), on_close=PICK_CLOSE)   # in view()
#   draw_swatches(surface, picked, fill=True, font, pal)                                                 # in draw()
#   var k = swatch_at(event.x, event.y)                                                                  # in update(): 0 auto, 1–8, -1 none

from mojoui.view import View, Canvas
from mojoui.canvas import Surface
from mojoui.text import Font, CENTRE
from mojoui.theme import Palette
from mojoui.draw import rect, line
from mojoui.cellstyle import swatch, fill_over

comptime SWATCH_SIZE = 30.0  # points
comptime SWATCH_GAP = 6.0
comptime SWATCH_COUNT = 9  # automatic, then the eight colours
comptime SWATCH_W = 6 + 9 * (30 + 6)  # points: SWATCH_GAP + SWATCH_COUNT × (SWATCH_SIZE + SWATCH_GAP)
comptime SWATCH_H = 30 + 2 * 6


def SwatchPicker(id: Int, version: Int, on_gesture: Int) -> View:
    """The picker's canvas (its size is fixed: SWATCH_W × SWATCH_H points)."""
    return Canvas(id, version, on_gesture=on_gesture).width(SWATCH_W).height(SWATCH_H).tag("swatches")


def swatch_at(x: Float64, y: Float64) -> Int:
    """Which swatch a tap at (x, y) points hit: 0 automatic, 1–8 a colour, -1 between them."""
    if y < SWATCH_GAP or y > SWATCH_GAP + SWATCH_SIZE:
        return -1
    var k = Int((x - SWATCH_GAP) // (SWATCH_SIZE + SWATCH_GAP))
    var into = x - SWATCH_GAP - Float64(k) * (SWATCH_SIZE + SWATCH_GAP)
    if k < 0 or k >= SWATCH_COUNT or into > SWATCH_SIZE:
        return -1
    return k


def draw_swatches(mut s: Surface, picked: Int, fill: Bool, font: Font, p: Palette):
    """The row of swatches, `picked` (0–8) ringed in the accent."""
    var k = s.scale
    s.fill(p.card)
    for i in range(SWATCH_COUNT):
        var x = (SWATCH_GAP + Float64(i) * (SWATCH_SIZE + SWATCH_GAP)) * k
        var y = SWATCH_GAP * k
        var size = SWATCH_SIZE * k
        if i == picked:
            rect(s, x - 3 * k, y - 3 * k, size + 6 * k, size + 6 * k, p.accent, 5 * k)
            rect(s, x - 1 * k, y - 1 * k, size + 2 * k, size + 2 * k, p.card, 4 * k)
        rect(s, x, y, size, size, p.line_strong, 4 * k)
        if i == 0:  # automatic: the card with a slash (no colour of its own)
            rect(s, x + 1 * k, y + 1 * k, size - 2 * k, size - 2 * k, p.card, 3 * k)
            line(s, x + 5 * k, y + size - 5 * k, x + size - 5 * k, y + 5 * k, 1.5 * k, p.ink3)
        elif fill:
            rect(s, x + 1 * k, y + 1 * k, size - 2 * k, size - 2 * k, fill_over(p.card, i), 3 * k)
        else:
            rect(s, x + 1 * k, y + 1 * k, size - 2 * k, size - 2 * k, p.card, 3 * k)
            font.draw(s, "A", x + size / 2, y + size / 2 + 5 * k, 15 * k, swatch(i), p.medium, CENTRE)
            rect(s, x + 6 * k, y + size - 7 * k, size - 12 * k, 3 * k, swatch(i))
