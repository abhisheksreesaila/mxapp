# Themes (themes/, D-260): the Omarchy palette is read from the person's theme file (Tokyo Night without one); the skins'
# tokens; the framework's own plain palette; Theme.native() is no theme at all.
#   pixi run mojo build -I . tests/test_theme.mojo -o build/test_theme && build/test_theme
from std.testing import assert_equal, assert_true
from mojoui.theme import Palette, Theme, hex_rgba, hex_of, mix
from themes.omarchy import omarchy_palette, omarchy
from themes.skins import ledger_palette, graphite_palette, blueprint_palette, ledger as ledger_theme
from themes.liquid import liquid_palette, liquid as liquid_theme
from themes.fluent import fluent
from mojoui.text import MONO, MONO_BOLD, REGULAR


def channel(c: UInt32, shift: Int) -> Float64:
    var v = Float64(Int((c >> UInt32(shift)) & 255)) / 255.0
    return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4


def contrast(a: UInt32, b: UInt32) -> Float64:
    var la = 0.2126 * channel(a, 0) + 0.7152 * channel(a, 8) + 0.0722 * channel(a, 16)
    var lb = 0.2126 * channel(b, 0) + 0.7152 * channel(b, 8) + 0.0722 * channel(b, 16)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def main() raises:
    assert_equal(hex_of(hex_rgba("#7aa2f7", 0)), "#7aa2f7")
    assert_equal(hex_of(hex_rgba("7AA2F7", 0)), "#7aa2f7")
    assert_equal(hex_rgba("#zzzzzz", 5), UInt32(5))
    assert_equal(hex_of(mix(hex_rgba("#000000", 0), hex_rgba("#ffffff", 0), 0.5)), "#808080")
    var p = omarchy_palette()
    print("OMARCHY: dark=" + String(p.dark) + " accent=" + hex_of(p.accent) + " card=" + hex_of(p.card) + " ink=" + hex_of(p.ink))
    assert_equal(p.regular, MONO)
    assert_equal(p.medium, MONO_BOLD)
    assert_equal(Palette.plain().regular, REGULAR)
    # contrast: captions on the card must be readable (WCAG 4.5:1)
    assert_true(contrast(p.ink3, p.card) >= 4.5, "captions: " + String(contrast(p.ink3, p.card)))
    assert_true(contrast(p.ink, p.card) >= 7.0, "text")
    # omxplorer's skins: the kit's exact tokens (docs/design/universal/omx.css), readable, and picked by design
    var ledger = ledger_palette()
    assert_equal(hex_of(ledger.accent), "#0e7c86")
    assert_equal(hex_of(ledger.page), "#eef0f3")
    assert_equal(hex_of(ledger.card), "#ffffff")
    assert_equal(hex_of(ledger.chrome), "#f5f6f8")
    assert_equal(hex_of(ledger.formula), "#6a4fd6")
    assert_equal(ledger.regular, REGULAR)
    assert_true(not ledger.dark)
    var graphite = graphite_palette()
    assert_equal(hex_of(graphite.accent), "#f5a524")
    assert_equal(hex_of(graphite.card), "#1d1e21")
    assert_equal(hex_of(graphite.chrome), "#121214")
    assert_true(graphite.dark)
    var blueprint = blueprint_palette()
    assert_equal(hex_of(blueprint.accent), "#2f6fed")
    assert_equal(hex_of(blueprint.chrome), "#14213d")
    assert_equal(hex_of(blueprint.card), "#ffffff")
    var liquid = liquid_palette()  # the default since goal 24 (D-225)
    assert_equal(hex_of(liquid.accent), "#0e7c86")
    assert_equal(hex_of(liquid.card), "#ffffff")
    assert_true(not liquid.dark)
    for skin in [ledger.copy(), graphite.copy(), blueprint.copy(), liquid.copy()]:
        assert_true(contrast(skin.ink3, skin.card) >= 4.5, "skin captions: " + String(contrast(skin.ink3, skin.card)))
        assert_true(contrast(skin.ink, skin.card) >= 7.0, "skin text")
        assert_true(contrast(skin.chrome_ink, skin.chrome) >= 7.0, "skin chrome")
        assert_true(contrast(skin.accent_ink, skin.accent) >= 3.0, "text on the accent")
        assert_true(skin.data(0) != skin.data(1) and skin.data(1) != skin.data(2), "series differ")
    # a theme is a value hosts apply as given: no theme is the platform's own look
    var native = Theme.native()
    assert_equal(native.id, "")
    assert_equal(native.gtk_css, "")
    assert_equal(native.web_css, "")
    var l = liquid_theme()
    assert_equal(l.classes, "skin liquid")
    assert_true("window.liquid" in l.gtk_css, "Liquid's GTK rules")
    assert_true("body.liquid" in l.web_css and "body.skin" in l.web_css, "Liquid's web rules, on the skins'")
    assert_true(l.key() != liquid_theme(liquid_palette().with_accent(hex_rgba("#0e7a43", 0))).key(), "a new tint is a new key (hosts restyle)")
    assert_equal(ledger_theme().classes, "skin ledger")
    assert_equal(omarchy().id, "omarchy")
    assert_equal(fluent().classes, "fluent")
    assert_true(ledger_theme().paint_native and not fluent().paint_native and not omarchy().paint_native)
    from themes.paper import paper_palette
    assert_true(paper_palette().data(0) != Palette.plain().data(0) and paper_palette().data(1) != Palette.plain().data(1), "Paper draws charts in its own series (P11)")
    assert_true(Palette.plain_dark().dark and contrast(Palette.plain_dark().ink3, Palette.plain_dark().card) >= 4.5, "no theme in dark mode: readable captions")
    print("THEME TESTS PASSED")
