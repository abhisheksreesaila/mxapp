# mojoui.theme: the vocabulary a theme speaks, not any theme. A Palette is the colours (and canvas font weights) drawn
# views use, so a canvas (a grid, a chart) matches the controls around it; a Theme is what an app hands its hosts:
# a name (CSS classes), a palette, a GTK style sheet and a web style sheet. Themes themselves (this repo's,
# yours) live outside the framework (`themes/` in this repo, D-260); an app that names none gets each
# platform's own look (Theme.native()).

from mojoui.canvas import rgba
from mojoui.text import REGULAR, MEDIUM


def hex_rgba(text: String, fallback: UInt32) -> UInt32:
    """ "#7aa2f7" → rgba (fallback if it doesn't parse)."""
    var t = String(text.strip())
    if t.startswith("#"):
        var rest = String(t[byte=1:])
        t = rest
    if t.byte_length() != 6:
        return fallback
    var v = 0
    for c in t.codepoint_slices():
        var o = ord(c)
        var d: Int
        if 48 <= o <= 57:
            d = o - 48
        elif 97 <= o <= 102:
            d = o - 87
        elif 65 <= o <= 70:
            d = o - 55
        else:
            return fallback
        v = v * 16 + d
    return rgba((v >> 16) & 255, (v >> 8) & 255, v & 255)


def mix(a: UInt32, b: UInt32, t: Float64) -> UInt32:
    """a blended toward b by t (0 = a, 1 = b), opaque."""
    var out = UInt32(255) << 24
    for shift in [0, 8, 16]:
        var x = Float64(Int((a >> UInt32(shift)) & 255))
        var y = Float64(Int((b >> UInt32(shift)) & 255))
        out |= UInt32(Int(x + (y - x) * t + 0.5) & 255) << UInt32(shift)
    return out


def hex_of(c: UInt32) -> String:
    """rgba → "#rrggbb" (for CSS)."""
    var digits = "0123456789abcdef"
    var out = String("#")
    for shift in [0, 8, 16]:
        var v = Int((c >> UInt32(shift)) & 255)
        out += String(digits[byte = v // 16]) + String(digits[byte = v % 16])
    return out


def hx(text: StringLiteral) -> UInt32:
    """A design token ("#0e7c86") as a colour."""
    return hex_rgba(String(text), 0)


def luminance(c: UInt32) -> Float64:
    """Relative brightness 0–1 (rough: for light vs dark)."""
    var r = Float64(Int(c & 255))
    var g = Float64(Int((c >> 8) & 255))
    var b = Float64(Int((c >> 16) & 255))
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0


comptime PLAIN_SERIES: List[UInt32] = [rgba(15, 108, 189), rgba(42, 160, 164), rgba(147, 115, 192), rgba(202, 80, 16), rgba(87, 129, 27),
                                      rgba(227, 0, 140), rgba(58, 150, 221), rgba(174, 140, 0)]


@fieldwise_init
struct Palette(Copyable, Movable):
    var dark: Bool
    var page: UInt32  # behind everything
    var card: UInt32  # panels (and canvases)
    var raised: UInt32  # headers, tracks: a step off the card
    var ink: UInt32  # text
    var ink2: UInt32  # secondary text
    var ink3: UInt32  # quiet text (row numbers, dimmed bars)
    var line: UInt32  # gridlines
    var line_strong: UInt32
    var accent: UInt32
    var accent_ink: UInt32  # text on the accent
    var accent_tint: UInt32  # dimmed bars
    var accent_wash: UInt32  # selection background
    var formula: UInt32  # formula columns' text
    var good: UInt32
    var bad: UInt32
    var warn: UInt32  # findings that ask for attention
    var regular: Int  # canvas text weights (Inter or JetBrains Mono)
    var medium: Int
    var series: List[UInt32]  # a chart's series colours, the first first (a theme's own; colour-blind safe where it can)
    var chrome: UInt32  # the window's band: title bar, toolbar, bottom bar (the page colour unless a theme says otherwise)
    var chrome_ink: UInt32
    var chrome_line: UInt32

    def __init__(out self, dark: Bool, page: UInt32, card: UInt32, raised: UInt32, ink: UInt32, ink2: UInt32, ink3: UInt32,
                 line: UInt32, line_strong: UInt32, accent: UInt32, accent_ink: UInt32, accent_tint: UInt32, accent_wash: UInt32,
                 formula: UInt32, good: UInt32, bad: UInt32, warn: UInt32, regular: Int, medium: Int):
        """A palette whose chrome is its page, with the default series (light: plain's; dark: the accent first)."""
        var series = materialize[PLAIN_SERIES]() if not dark else [accent, rgba(68, 157, 171), rgba(173, 142, 230), rgba(224, 175, 104), rgba(158, 206, 106),
                                                                    rgba(247, 118, 142), rgba(13, 185, 215), rgba(235, 146, 123)]
        self = Self(dark, page, card, raised, ink, ink2, ink3, line, line_strong, accent, accent_ink, accent_tint, accent_wash,
                    formula, good, bad, warn, regular, medium, series^, page, ink, line)

    @staticmethod
    def plain() -> Palette:
        """The framework's own neutral palette (light greys, one blue): what drawn views use when the app names no theme."""
        return Palette(False, rgba(245, 245, 245), rgba(255, 255, 255), rgba(250, 250, 250), rgba(36, 36, 36), rgba(97, 97, 97),
                       rgba(140, 140, 140), rgba(235, 235, 235), rgba(209, 209, 209), rgba(15, 108, 189), rgba(255, 255, 255),
                       rgba(199, 224, 244), rgba(235, 243, 252), rgba(17, 94, 163), rgba(16, 124, 16), rgba(197, 15, 31),
                       rgba(234, 88, 12), REGULAR, MEDIUM)

    @staticmethod
    def plain_dark() -> Palette:
        """The plain palette for a system in dark mode (the platform's own dark greys, a lighter blue)."""
        return Palette(True, hx("#1e1e1e"), hx("#262626"), hx("#303030"), hx("#ffffff"), hx("#deddda"), hx("#a8a6a2"),
                       hx("#363636"), hx("#4a4a4a"), hx("#78aeed"), hx("#1e1e1e"), mix(hx("#262626"), hx("#78aeed"), 0.40),
                       mix(hx("#262626"), hx("#78aeed"), 0.16), hx("#dc8add"), hx("#8ff0a4"), hx("#ff7b63"), hx("#f8e45c"), REGULAR, MEDIUM)

    def with_accent(self, accent: UInt32) -> Palette:
        """The same palette with another accent (0: unchanged): a mode's tint (an app's sheet green, its report red)."""
        if accent == 0:
            return self.copy()
        var p = self.copy()
        p.accent = accent
        p.accent_tint = mix(p.card, accent, 0.40)
        p.accent_wash = mix(p.card, accent, 0.10)
        return p^

    def data(self, i: Int) -> UInt32:
        """The i-th series colour."""
        return self.series[i % len(self.series)] if len(self.series) > 0 else self.accent


@fieldwise_init
struct Theme(Copyable, Movable):
    """What an app hands its hosts (App.theme()): hosts apply it as given and know no theme by name."""
    var id: String  # a short name ("" native): DESIGN lines, the icons' cache folder
    var classes: String  # CSS classes on the GTK window and the web page's body (space-separated)
    var palette: Palette  # drawn views; the web page's --o-* variables; Apple hosts' tints when paint_native
    var gtk_css: String  # a GTK style sheet (over libadwaita), rules scoped to `window.<class>`
    var web_css: String  # a web style sheet, rules scoped to `body.<class>`, reading the palette's --o-* variables
    var icon_ink: UInt32  # the icons' ink, and on filled (accent) buttons
    var icon_on_accent: UInt32
    var paint_native: Bool  # Apple hosts: colour their native controls with the palette and set Inter (a skin), else system colours

    @staticmethod
    def native(dark: Bool = False) -> Theme:
        """No theme: each platform's own look (libadwaita, the system's web font and colours, AppKit, UIKit); drawn views
        take the plain palette, dark when the system is (App.appearance)."""
        return Theme("", "", Palette.plain_dark() if dark else Palette.plain(), "", "", rgba(66, 66, 66), rgba(255, 255, 255), False)

    def key(self) -> String:
        """Changes whenever what hosts show would (the theme, its palette's accent, page, error tone and light or dark, its
        style sheets): hosts restyle then. (A sheet edited in place to the same length goes unnoticed: change its id too.)"""
        return (self.id + hex_of(self.palette.accent) + hex_of(self.palette.page) + hex_of(self.palette.bad) + ("d" if self.palette.dark else "l")
                + String(self.gtk_css.byte_length()) + "/" + String(self.web_css.byte_length()))
