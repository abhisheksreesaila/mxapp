# Text on canvases. Run: pixi run mojo run -I . tests/test_text.mojo
# Prints WIDTH lines (text|size|pixels) that scripts/check compares with the font's own metrics,
# and writes build/text.png to look at.
from std.testing import assert_true, assert_equal

from mojoui import Surface, rgba
from mojoui.text import Font, REGULAR, MEDIUM, CENTRE, RIGHT
from mojoui.png import encode_png

comptime SAMPLES: List[String] = ["Revenue by month", "$1.24B", "Electronics · 22%", "Jan Feb Mar", "4,512,903 orders"]


def main() raises:
    var font = Font()
    for s in materialize[SAMPLES]():
        for size in [20.8, 26.0, 41.6]:
            print("WIDTH: " + s + "|" + String(size) + "|" + String(font.measure(s, size, REGULAR)))
    var w = 640
    var h = 220
    var px = List[UInt32](length=w * h, fill=rgba(255, 255, 255))
    var surface = Surface(Int(px.unsafe_ptr()), w, h, 1.6)
    font.draw(surface, "Revenue by month", 16, 40, 20.8, rgba(36, 36, 36), MEDIUM)
    font.draw(surface, "Electronics · 22% of revenue", 16, 76, 20.8, rgba(97, 97, 97))
    font.draw(surface, "$1.24B", 16, 150, 64, rgba(15, 108, 189), MEDIUM)
    font.draw(surface, "centred", 320, 200, 16, rgba(36, 36, 36), REGULAR, CENTRE)
    font.draw(surface, "right", 624, 200, 16, rgba(36, 36, 36), REGULAR, RIGHT)
    # Ink landed where the text is, and nowhere near the empty top-right corner.
    var ink = 0
    for y in range(20, 45):
        for x in range(16, 220):
            if surface.get(x, y) != rgba(255, 255, 255):
                ink += 1
    assert_true(ink > 300, "the heading has ink")
    for y in range(0, 15):
        for x in range(500, 640):
            assert_equal(surface.get(x, y), rgba(255, 255, 255))
    assert_true(font.measure("$1.24B", 64, MEDIUM) > font.measure("$1.24B", 32, MEDIUM) * 1.9)
    var png = encode_png(px, w, h)
    with open("build/text.png", "w") as f:
        f.write_bytes(Span(png))
    _ = len(px)
    print("TEXT TESTS PASSED")
