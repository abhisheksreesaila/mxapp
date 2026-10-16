# mojoui.theme: the Omarchy palette is read from the person's theme file (Tokyo Night without one).
#   pixi run mojo build -I . tests/test_theme.mojo -o build/test_theme && build/test_theme
from std.testing import assert_equal, assert_true
from mojoui.theme import Palette, hex_rgba, hex_of, mix
from mojoui.text import MONO, MONO_BOLD, REGULAR


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
    print("THEME TESTS PASSED")
