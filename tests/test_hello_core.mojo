# Tests for the shared app logic. Run: pixi run mojo run -I apple tests/test_hello_core.mojo
from std.testing import assert_equal

from hello_core import Hello, greet


def test_first_tap_greets_by_name() raises:
    var state = Hello("Ada", 0)
    assert_equal(greet(state), "Hello, Ada! (click 1)")


def test_taps_count_up() raises:
    var state = Hello("Grace", 0)
    _ = greet(state)
    _ = greet(state)
    assert_equal(greet(state), "Hello, Grace! (click 3)")
    assert_equal(state.clicks, 3)


def main() raises:
    test_first_tap_greets_by_name()
    test_taps_count_up()
    print("ALL TESTS PASSED")
