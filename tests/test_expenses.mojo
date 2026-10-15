# Tests for Pocket Expenses' money handling. Run: pixi run mojo run -I examples/expenses -I . tests/test_expenses.mojo
from std.testing import assert_equal

from app import parse_cents, money


def test_parse_cents() raises:
    assert_equal(parse_cents("12.50"), 1250)
    assert_equal(parse_cents("12.5"), 1250)
    assert_equal(parse_cents("12"), 1200)
    assert_equal(parse_cents(" $12 "), 1200)
    assert_equal(parse_cents("1,234.50"), 123450)
    assert_equal(parse_cents(".99"), 99)
    assert_equal(parse_cents("9999999.99"), 999999999)
    for bad in ["", "abc", "1.2.3", "12.345", "99999999", "99999999999999999999", "0", "0.00", "-5", "$", "."]:
        assert_equal(parse_cents(bad), -1, bad)


def test_money() raises:
    assert_equal(money(0), "$0.00")
    assert_equal(money(5), "$0.05")
    assert_equal(money(123450), "$1,234.50")
    assert_equal(money(999999999), "$9,999,999.99")
    assert_equal(parse_cents(money(123450)), 123450)  # what the app shows, it can read back


def main() raises:
    test_parse_cents()
    test_money()
    print("EXPENSES TESTS PASSED")
