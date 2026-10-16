# mojoui.theme: the Omarchy palette is read from the person's theme file (Tokyo Night without one).
#   pixi run mojo build -I . tests/test_theme.mojo -o build/test_theme && build/test_theme
from std.testing import assert_equal, assert_true
from mojoui.theme import Palette, hex_rgba, hex_of, mix
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
    var p = Palette.omarchy()
    print("OMARCHY: dark=" + String(p.dark) + " accent=" + hex_of(p.accent) + " card=" + hex_of(p.card) + " ink=" + hex_of(p.ink))
    assert_equal(p.regular, MONO)
    assert_equal(p.medium, MONO_BOLD)
    assert_equal(Palette.fluent().regular, REGULAR)
    # contrast: captions on the card must be readable (WCAG 4.5:1)
    assert_true(contrast(p.ink3, p.card) >= 4.5, "captions: " + String(contrast(p.ink3, p.card)))
    assert_true(contrast(p.ink, p.card) >= 7.0, "text")
    print("THEME TESTS PASSED")
