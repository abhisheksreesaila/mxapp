# mojoui.cellstyle: how a cell looks, as a spreadsheet's Home tab sets it: bold, italic, underline, strikethrough, a
# text colour, a fill and an alignment. One small integer, so a column's style and a sparse map of cell overrides cost
# next to nothing on 100M rows (docs/plans/formatting.md): it's read only for the cells on screen.
#
#   var s = CellStyle()                       # plain: the theme's ink, no fill, numbers right and text left
#   s = s.with_part(BOLD, True)               # or s.set(INK_MASK, ink_bits(RED))
#   if s.bold(): …                            # DataGrid draws it (GridSource.grid_style)

from mojoui.canvas import rgba
from mojoui.draw import blend

comptime BOLD = 1
comptime ITALIC = 2
comptime UNDERLINE = 4
comptime STRIKE = 8
comptime INK_SHIFT = 4  # bits 4–7: the text colour (0: the theme's ink, 1–8: SWATCHES)
comptime FILL_SHIFT = 8  # bits 8–11: the fill (0: none)
comptime ALIGN_SHIFT = 12  # bits 12–13: AUTO_ALIGN (numbers right, text left), ALIGN_LEFT, ALIGN_CENTRE, ALIGN_RIGHT
comptime INK_MASK = 0xF << INK_SHIFT
comptime FILL_MASK = 0xF << FILL_SHIFT
comptime ALIGN_MASK = 0x3 << ALIGN_SHIFT
comptime ALL_PARTS = BOLD | ITALIC | UNDERLINE | STRIKE | INK_MASK | FILL_MASK | ALIGN_MASK
comptime AUTO_ALIGN = 0
comptime ALIGN_LEFT = 1
comptime ALIGN_CENTRE = 2
comptime ALIGN_RIGHT = 3
comptime ITALIC_SLANT = 0.21  # (the grid's italic: the regular face, leaned)

# Eight colours that read on a light and a dark card (D-200); a fill is the same colour at FILL_STRENGTH.
comptime SWATCH_NAMES: List[String] = ["Red", "Orange", "Amber", "Green", "Teal", "Blue", "Purple", "Grey"]
comptime FILL_STRENGTH = 0.26


def swatch(k: Int) -> UInt32:
    """Swatch k (1–8) as a colour; 0 (automatic) is never asked for."""
    if k == 1:
        return rgba(222, 60, 60)
    if k == 2:
        return rgba(232, 120, 30)
    if k == 3:
        return rgba(214, 160, 20)
    if k == 4:
        return rgba(46, 160, 80)
    if k == 5:
        return rgba(20, 150, 150)
    if k == 6:
        return rgba(50, 110, 230)
    if k == 7:
        return rgba(140, 80, 210)
    return rgba(128, 128, 128)


def swatch_name(k: Int) -> String:
    return materialize[SWATCH_NAMES]()[k - 1] if 1 <= k <= 8 else "Automatic"


def fill_over(card: UInt32, k: Int) -> UInt32:
    """Fill k over the card colour: the swatch at FILL_STRENGTH, opaque."""
    return blend(card, swatch(k), FILL_STRENGTH)


@fieldwise_init
struct CellStyle(Copyable, Equatable, Movable):
    var bits: Int

    def __init__(out self):
        self.bits = 0

    def __eq__(self, other: Self) -> Bool:
        return self.bits == other.bits

    def plain(self) -> Bool:
        return self.bits == 0

    def bold(self) -> Bool:
        return self.bits & BOLD != 0

    def italic(self) -> Bool:
        return self.bits & ITALIC != 0

    def underline(self) -> Bool:
        return self.bits & UNDERLINE != 0

    def strike(self) -> Bool:
        return self.bits & STRIKE != 0

    def ink(self) -> Int:
        return (self.bits & INK_MASK) >> INK_SHIFT

    def fill(self) -> Int:
        return (self.bits & FILL_MASK) >> FILL_SHIFT

    def align(self) -> Int:
        return (self.bits & ALIGN_MASK) >> ALIGN_SHIFT

    def set(self, mask: Int, value: Int) -> CellStyle:
        """This style with the parts under `mask` taken from `value` (the rest kept)."""
        return CellStyle((self.bits & ~mask) | (value & mask))

    def words(self) -> String:
        """What it does, in words ("bold, italic, red, fill blue, centred"; "plain")."""
        var parts = List[String]()
        if self.bold():
            parts.append("bold")
        if self.italic():
            parts.append("italic")
        if self.underline():
            parts.append("underlined")
        if self.strike():
            parts.append("struck through")
        if self.ink() > 0:
            parts.append(swatch_name(self.ink()).lower())
        if self.fill() > 0:
            parts.append("fill " + swatch_name(self.fill()).lower())
        var a = self.align()
        if a != AUTO_ALIGN:
            parts.append("left" if a == ALIGN_LEFT else ("centred" if a == ALIGN_CENTRE else "right"))
        if len(parts) == 0:
            return "plain"
        var out = parts[0]
        for k in range(1, len(parts)):
            out += ", " + parts[k]
        return out^


def ink_bits(k: Int) -> Int:
    return (k & 0xF) << INK_SHIFT


def fill_bits(k: Int) -> Int:
    return (k & 0xF) << FILL_SHIFT


def align_bits(a: Int) -> Int:
    return (a & 0x3) << ALIGN_SHIFT
