# mojoui.theme: the colours (and canvas font) a design language draws with, so a canvas (the
# Workbook's grid, Flint charts) matches the native controls around it.
#
#   Palette.fluent()   Fluent 2 light (the analytics showcase)
#   Palette.omarchy()  the person's current Omarchy theme (~/.local/state/omarchy/current/theme/colors.toml),
#                      Tokyo Night when there's none: dark surfaces, the theme's accent, JetBrains Mono

from mojoui.canvas import rgba
from mojoui.text import REGULAR, MEDIUM, MONO, MONO_BOLD
from mojoui.shared import environment

comptime OMARCHY_COLORS = "/.local/state/omarchy/current/theme/colors.toml"


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


def lookup(keys: List[String], vals: List[String], name: String, fallback: String) -> UInt32:
    for i in range(len(keys)):
        if keys[i] == name:
            return hex_rgba(vals[i], hex_rgba(fallback, 0))
    return hex_rgba(fallback, 0)


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
    var regular: Int  # canvas text weights (Noto Sans or JetBrains Mono)
    var medium: Int

    @staticmethod
    def fluent() -> Palette:
        return Palette(False, rgba(245, 245, 245), rgba(255, 255, 255), rgba(250, 250, 250), rgba(36, 36, 36), rgba(97, 97, 97),
                       rgba(140, 140, 140), rgba(235, 235, 235), rgba(209, 209, 209), rgba(15, 108, 189), rgba(255, 255, 255),
                       rgba(199, 224, 244), rgba(235, 243, 252), rgba(17, 94, 163), rgba(16, 124, 16), rgba(197, 15, 31),
                       REGULAR, MEDIUM)

    @staticmethod
    def omarchy() -> Palette:
        """The current Omarchy theme's colours (Tokyo Night if the file isn't there)."""
        var keys = List[String]()
        var vals = List[String]()
        try:
            with open(environment("HOME", ".") + OMARCHY_COLORS, "r") as f:
                for line in f.read().split("\n"):
                    var kv = line.split("=")
                    if len(kv) == 2:
                        keys.append(String(kv[0].strip()))
                        vals.append(String(kv[1].strip()).replace('"', ""))
        except:
            pass

        var mode = String("dark")
        for i in range(len(keys)):
            if keys[i] == "mode":
                mode = vals[i]
        var dark = mode != "light"
        var bg = lookup(keys, vals, "background", "#1a1b26")
        var card = lookup(keys, vals, "lighter_background", "#24283b")
        var page = lookup(keys, vals, "dark_background", "#13141c")
        var fg = lookup(keys, vals, "foreground", "#a9b1d6")
        var accent = lookup(keys, vals, "accent", "#7aa2f7")
        var bright = lookup(keys, vals, "bright_foreground", "#c0caf5")
        var quiet = mix(lookup(keys, vals, "dark_foreground", "#565f89"), fg, 0.35)  # a step brighter than the theme's comment colour: readable captions
        return Palette(dark, page, bg, card, bright, fg, quiet, mix(bg, fg, 0.10), mix(bg, fg, 0.22),
                       accent, bg, mix(bg, accent, 0.35), mix(bg, accent, 0.16), lookup(keys, vals, "magenta", "#ad8ee6"),
                       lookup(keys, vals, "green", "#9ece6a"), lookup(keys, vals, "red", "#f7768e"), MONO, MONO_BOLD)

    def data(self, i: Int) -> UInt32:
        """The i-th series colour (the accent first)."""
        if not self.dark:
            var fluent: List[UInt32] = [rgba(15, 108, 189), rgba(42, 160, 164), rgba(147, 115, 192), rgba(202, 80, 16), rgba(87, 129, 27),
                                        rgba(227, 0, 140), rgba(58, 150, 221), rgba(174, 140, 0)]
            return fluent[i % 8]
        var tokyo: List[UInt32] = [self.accent, rgba(68, 157, 171), rgba(173, 142, 230), rgba(224, 175, 104), rgba(158, 206, 106),
                                   rgba(247, 118, 142), rgba(13, 185, 215), rgba(235, 146, 123)]
        return tokyo[i % 8]
