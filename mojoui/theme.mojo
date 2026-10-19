# mojoui.theme: the colours (and canvas font) a design language draws with, so a canvas (the
# Workbook's grid, Flint charts) matches the native controls around it.
#
#   Palette.fluent()   Fluent 2 light (the analytics showcase)
#   Palette.omarchy()  the person's current Omarchy theme (~/.local/state/omarchy/current/theme/colors.toml),
#                      Tokyo Night when there's none: dark surfaces, the theme's accent, JetBrains Mono
#   Palette.ledger(), graphite(), blueprint()  omxplorer's own skins (docs/design/universal/): the same colours on
#                      every platform, Inter for words and JetBrains Mono for figures; skin_palette(design) picks one

from mojoui.canvas import rgba
from mojoui.text import REGULAR, MEDIUM, MONO, MONO_BOLD
from mojoui.shared import environment
from mojoui.view import FLUENT, OMARCHY, LEDGER, GRAPHITE, BLUEPRINT, LIQUID
from std.sys import CompilationTarget

# omxplorer's brand (owner, D-254): indigo for the app itself, a tint per mode
comptime BRAND_INDIGO: UInt32 = 0xFFE5464F  # #4f46e5 (R in the low byte)
comptime SHEET_GREEN: UInt32 = 0xFF437A0E  # #0e7a43
comptime REPORT_RED: UInt32 = 0xFF3F24C8  # #c8243f

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


def derived(keys: List[String], vals: List[String], name: String, otherwise: UInt32) -> UInt32:
    """The theme's colour for `name`, or `otherwise` (derived from its background and foreground)."""
    for i in range(len(keys)):
        if keys[i] == name:
            return hex_rgba(vals[i], otherwise)
    return otherwise


def hx(text: StringLiteral) -> UInt32:
    """A design token ("#0e7c86") as a colour."""
    return hex_rgba(String(text), 0)


def luminance(c: UInt32) -> Float64:
    """Relative brightness 0–1 (rough: for light vs dark)."""
    var r = Float64(Int(c & 255))
    var g = Float64(Int((c >> 8) & 255))
    var b = Float64(Int((c >> 16) & 255))
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0


def _read_omarchy(mut keys: List[String], mut vals: List[String]):
    """Reads ~/.local/state/omarchy/current/theme/colors.toml as key=value lines (Linux only: the iPad and Mac hosts
    never see an Omarchy theme, and file IO doesn't compile for their targets)."""
    comptime if CompilationTarget.is_linux():
        try:
            with open(environment("HOME", ".") + OMARCHY_COLORS, "r") as f:
                for line in f.read().split("\n"):
                    var text = String(line.strip())
                    var eq = text.find("=")
                    if text.startswith("#") or eq < 0:
                        continue
                    # the value: a quoted string, or the first word (either way a trailing # comment is dropped)
                    var value = String(String(text[byte=eq + 1:]).strip())
                    if value.startswith('"') or value.startswith("'"):
                        var quote = String(value[byte=0:1])
                        var end = value.find(quote, 1)
                        var inner = String(value[byte=1:end]) if end > 0 else String(value[byte=1:])
                        value = inner
                    else:
                        var space = value.find(" ")
                        if space > 0:
                            var word = String(value[byte=0:space])
                            value = word
                    keys.append(String(String(text[byte=0:eq]).strip()))
                    vals.append(value)
        except:
            pass


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
    var skin: Int  # the design this palette is for (LEDGER, GRAPHITE, BLUEPRINT, LIQUID), else 0
    var chrome: UInt32  # the window's band: title bar, toolbar, bottom bar (the page colour unless a skin says otherwise)
    var chrome_ink: UInt32
    var chrome_line: UInt32

    def __init__(out self, dark: Bool, page: UInt32, card: UInt32, raised: UInt32, ink: UInt32, ink2: UInt32, ink3: UInt32,
                 line: UInt32, line_strong: UInt32, accent: UInt32, accent_ink: UInt32, accent_tint: UInt32, accent_wash: UInt32,
                 formula: UInt32, good: UInt32, bad: UInt32, warn: UInt32, regular: Int, medium: Int):
        """A palette whose chrome is its page (Fluent, Omarchy)."""
        self = Self(dark, page, card, raised, ink, ink2, ink3, line, line_strong, accent, accent_ink, accent_tint, accent_wash,
                    formula, good, bad, warn, regular, medium, 0, page, ink, line)

    @staticmethod
    def fluent() -> Palette:
        return Palette(False, rgba(245, 245, 245), rgba(255, 255, 255), rgba(250, 250, 250), rgba(36, 36, 36), rgba(97, 97, 97),
                       rgba(140, 140, 140), rgba(235, 235, 235), rgba(209, 209, 209), rgba(15, 108, 189), rgba(255, 255, 255),
                       rgba(199, 224, 244), rgba(235, 243, 252), rgba(17, 94, 163), rgba(16, 124, 16), rgba(197, 15, 31),
                       rgba(234, 88, 12), REGULAR, MEDIUM)

    # omxplorer's skins: the exact tokens of docs/design/universal/omx.css (ledger.md, graphite.md, blueprint.md)

    @staticmethod
    def ledger() -> Palette:
        """Light and classic: a white sheet, quiet grey chrome, one deep teal accent (the default)."""
        return Palette(False, hx("#eef0f3"), hx("#ffffff"), hx("#f0f2f5"), hx("#1b1f24"), hx("#3d434c"), hx("#6b7380"),
                       hx("#e1e4e8"), hx("#c9ced6"), hx("#0e7c86"), hx("#ffffff"), mix(hx("#ffffff"), hx("#0e7c86"), 0.45), hx("#e3f2f3"),
                       hx("#6a4fd6"), hx("#1f8a4c"), hx("#c8364c"), hx("#b7791f"), REGULAR, MEDIUM, LEDGER, hx("#f5f6f8"), hx("#1b1f24"), hx("#e1e4e8"))

    def with_accent(self, accent: UInt32) -> Palette:
        """The same palette with another accent (0: unchanged): a mode's tint (the sheet's green, the report's red)."""
        if accent == 0:
            return self.copy()
        var p = self.copy()
        p.accent = accent
        p.accent_tint = mix(p.card, accent, 0.40)
        p.accent_wash = mix(p.card, accent, 0.10)
        if accent == REPORT_RED:  # (in a report, red only means "a report": false and errors take other tones, D-254)
            p.bad = hx("#9f6b75")
        return p^

    @staticmethod
    def liquid() -> Palette:
        """Liquid, light (docs/design/liquid.md): a white sheet, glass islands over a soft cool backdrop, teal (the default).
        The chrome is the glass as it looks over the backdrop (GTK can't blur what's behind a widget)."""
        return Palette(False, hx("#e9eef4"), hx("#ffffff"), hx("#f6f8fb"), hx("#0f172a"), hx("#334155"), hx("#64748b"),
                       hx("#edf0f4"), hx("#d9dee6"), hx("#0e7c86"), hx("#ffffff"), mix(hx("#ffffff"), hx("#0e7c86"), 0.40), hx("#e6f2f3"),
                       hx("#6a4fd6"), hx("#16a34a"), hx("#dc2626"), hx("#d97706"), REGULAR, MEDIUM, LIQUID, hx("#f7f9fc"), hx("#334155"), hx("#ffffff"))

    @staticmethod
    def graphite() -> Palette:
        """Dark and neutral (no blue tint), crisp white figures, a warm amber accent."""
        return Palette(True, hx("#161618"), hx("#1d1e21"), hx("#26272b"), hx("#ececee"), hx("#c2c4ca"), hx("#858892"),
                       hx("#2e3034"), hx("#44464c"), hx("#f5a524"), hx("#1d1e21"), mix(hx("#1d1e21"), hx("#f5a524"), 0.45), hx("#3a2f17"),
                       hx("#b48cff"), hx("#3ddc97"), hx("#ff6b6b"), hx("#f5a524"), REGULAR, MEDIUM, GRAPHITE, hx("#121214"), hx("#ececee"), hx("#2e3034"))

    @staticmethod
    def blueprint() -> Palette:
        """Light with a navy band over a white sheet, blue accent."""
        return Palette(False, hx("#f3f5f9"), hx("#ffffff"), hx("#f1f4f9"), hx("#111827"), hx("#374151"), hx("#6b7280"),
                       hx("#e0e5ee"), hx("#c5cede"), hx("#2f6fed"), hx("#ffffff"), mix(hx("#ffffff"), hx("#2f6fed"), 0.45), hx("#e5eefe"),
                       hx("#7b3fe4"), hx("#138a52"), hx("#d23f57"), hx("#b7791f"), REGULAR, MEDIUM, BLUEPRINT, hx("#14213d"), hx("#e8edf7"), hx("#2a3a63"))

    @staticmethod
    def omarchy() -> Palette:
        """The current Omarchy theme's colours (Tokyo Night if the file isn't there)."""
        var keys = List[String]()
        var vals = List[String]()
        _read_omarchy(keys, vals)

        # Missing keys are derived from the two every theme has (background, foreground), so a partial theme
        # still reads well; light or dark comes from `mode`, else from how bright the background is.
        var bg = lookup(keys, vals, "background", "#1a1b26")
        var fg = lookup(keys, vals, "foreground", "#a9b1d6")
        var dark = luminance(bg) < 0.5
        for i in range(len(keys)):
            if keys[i] == "mode":
                dark = vals[i] != "light"
        var toward = rgba(0, 0, 0) if dark else rgba(255, 255, 255)
        var away = rgba(255, 255, 255) if dark else rgba(0, 0, 0)
        var page = derived(keys, vals, "dark_background", mix(bg, toward, 0.25))
        var raised = derived(keys, vals, "lighter_background", mix(bg, fg, 0.08))
        var ink = derived(keys, vals, "bright_foreground", mix(fg, away, 0.25))
        # no theme file at all: Tokyo Night's own blue (a partial file still derives its accent from its colours)
        var fallback_accent = rgba(122, 162, 247) if len(keys) == 0 else mix(fg, rgba(64, 128, 255), 0.6)
        var accent = derived(keys, vals, "accent", derived(keys, vals, "blue", fallback_accent))
        var quiet = mix(derived(keys, vals, "dark_foreground", mix(fg, bg, 0.45)), fg, 0.5)  # captions: ≥ 4.5:1 on the card
        return Palette(dark, page, bg, raised, ink, fg, quiet, mix(bg, fg, 0.10), mix(bg, fg, 0.22),
                       accent, bg, mix(bg, accent, 0.35), mix(bg, accent, 0.16), derived(keys, vals, "magenta", mix(fg, rgba(173, 142, 230), 0.6)),
                       derived(keys, vals, "green", rgba(158, 206, 106)), derived(keys, vals, "red", rgba(247, 118, 142)),
                       derived(keys, vals, "orange", derived(keys, vals, "yellow", rgba(255, 158, 100))), MONO, MONO_BOLD)

    def data(self, i: Int) -> UInt32:
        """The i-th series colour (the accent first); the skins' series are colour-blind safe."""
        if self.skin == LEDGER:
            var s: List[UInt32] = [hx("#0e7c86"), hx("#e8833a"), hx("#5b5fc7"), hx("#d6455d"), hx("#2e9e5b"), hx("#b8892d"), hx("#7a8594"), hx("#c45cb5")]
            return s[i % 8]
        if self.skin == LIQUID:
            var s: List[UInt32] = [hx("#0e7c86"), hx("#f59e0b"), hx("#6366f1"), hx("#ec4899"), hx("#22c55e"), hx("#a16207"), hx("#64748b"), hx("#c026d3")]
            return s[i % 8]
        if self.skin == GRAPHITE:
            var s: List[UInt32] = [hx("#4cc2ff"), hx("#f5a524"), hx("#b48cff"), hx("#3ddc97"), hx("#ff6b6b"), hx("#e8833a"), hx("#9aa3b2"), hx("#d86fc9")]
            return s[i % 8]
        if self.skin == BLUEPRINT:
            var s: List[UInt32] = [hx("#2f6fed"), hx("#f08c2e"), hx("#13a39a"), hx("#d9485f"), hx("#7b61ff"), hx("#b8892d"), hx("#7a8594"), hx("#c45cb5")]
            return s[i % 8]
        if not self.dark:
            var fluent: List[UInt32] = [rgba(15, 108, 189), rgba(42, 160, 164), rgba(147, 115, 192), rgba(202, 80, 16), rgba(87, 129, 27),
                                        rgba(227, 0, 140), rgba(58, 150, 221), rgba(174, 140, 0)]
            return fluent[i % 8]
        var tokyo: List[UInt32] = [self.accent, rgba(68, 157, 171), rgba(173, 142, 230), rgba(224, 175, 104), rgba(158, 206, 106),
                                   rgba(247, 118, 142), rgba(13, 185, 215), rgba(235, 146, 123)]
        return tokyo[i % 8]


def skin_palette(design: Int) -> Palette:
    """The palette a design draws with: the skins, Omarchy's file, else Fluent."""
    if design == LIQUID:
        return Palette.liquid()
    if design == LEDGER:
        return Palette.ledger()
    if design == GRAPHITE:
        return Palette.graphite()
    if design == BLUEPRINT:
        return Palette.blueprint()
    if design == OMARCHY:
        return Palette.omarchy()
    return Palette.fluent()


def skin_name(design: Int) -> String:
    """The skin's name for CSS classes and settings ("ledger"), "" for the other designs."""
    if design == LIQUID:
        return "liquid"
    if design == LEDGER:
        return "ledger"
    if design == GRAPHITE:
        return "graphite"
    if design == BLUEPRINT:
        return "blueprint"
    return ""


def skin_of(name: String) -> Int:
    """A settings.txt skin name back to its design (LIQUID when unknown: the default, D-225)."""
    if name == "ledger":
        return LEDGER
    if name == "graphite":
        return GRAPHITE
    if name == "blueprint":
        return BLUEPRINT
    return LIQUID
