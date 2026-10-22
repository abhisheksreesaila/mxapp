# The island's five faces, stacked, as one PNG (for looking at): tools/island_shots.mojo OUT.png [dark]
from std.sys import argv
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Palette
from mojoui.png import encode_png
from mojoui.island import Island, Activity, ISLAND_W, ISLAND_H


def main() raises:
    var font = Font()
    var pal = Palette.plain()
    var faces: List[Activity] = [Activity.idle("big", "100,000,000 rows · RTX 3090"), Activity.running("Median of revenue by region", 0.43, "43% · 1.4B rows/s"),
                                 Activity.done("Median of revenue by region", "0.69 s on RTX 3090"), Activity.undo("Bold applied to 21 cells"),
                                 Activity.error("region: 3 rows aren't text")]
    var w = ISLAND_W * 2
    var h = ISLAND_H * 2
    var all = List[UInt32]()
    for f in faces:
        var one = Island()
        one.show(f.copy(), font, 0)
        var buf = List[UInt32](length=w * h, fill=0)
        var s = Surface(Int(buf.unsafe_ptr()), w, h, 2.0)
        one.draw(s, font, pal, 1500 * 1_000_000)
        for p in buf:
            all.append(p)
    var png = encode_png(all, w, h * len(faces))
    with open(String(argv()[1]), "w") as out:
        out.write_bytes(Span(png))
