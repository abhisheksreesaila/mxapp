# The analytics app's own logic, and its three engines against each other.
# Build it (`mojo run`'s JIT clashes with MX frame's runtime), then run:
#   pixi run mojo build -I examples/analytics -I . tests/test_analytics.mojo -o build/test_analytics && pixi run build/test_analytics
from std.testing import assert_equal, assert_true, assert_false

from app import Main, keep, month_of, by_month, by_category, DAYS, MONTHS
from mojoui import Event, TAP
from mojoui.gpu import Row, Filter
from mojoui.charts import fixed
from mojoui.flint import FlintChart
from mojoui.text import Font

comptime YEAR = 1
comptime CHANNEL = 2
comptime ENGINE = 4


def test_numbers() raises:
    assert_equal(fixed(-5.3, 1), "-5.3")
    assert_equal(fixed(-0.4, 1), "-0.4")
    assert_equal(fixed(-0.04, 1), "0.0")
    assert_equal(fixed(12345.678, 2), "12,345.68")


def test_calendar() raises:
    assert_equal(month_of(0), 0)  # 2023-01-01
    assert_equal(month_of(31), 1)  # 2023-02-01
    assert_equal(month_of(365 + 59), 13)  # 2024-02-29 (leap day) is February
    assert_equal(month_of(365 + 60), 14)  # 2024-03-01
    assert_equal(month_of(DAYS - 1), 35)  # 2025-12-31


def test_crossfilter_rules() raises:
    var r = Row(400, 2, 1, 0, 17, 1, 12345, 13)  # day 400 (2024), Fashion, Europe, Online
    var all = Filter(0, DAYS - 1, -1, -1, -1, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    assert_true(keep(r, all, 0))
    var other_cat = Filter(0, DAYS - 1, -1, 5, -1, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    assert_false(keep(r, other_cat, 0))
    assert_true(keep(r, other_cat, 1))  # the category chart ignores its own filter
    assert_equal(by_category(r, other_cat), 2)
    var year_2023 = Filter(0, 364, -1, -1, -1, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    assert_false(keep(r, year_2023, 0))
    assert_equal(by_month(r, year_2023), 13)  # months ignore the year: comparisons need last year


def test_flint_export_and_hit() raises:
    var c = (FlintChart("Bar Chart", "t").text("category", ["A", "B", "C", "D"]).number("revenue", [123456.0, 50.0, 7.0, 1.0])
             .semantic("revenue", "Price").encode("x", "revenue").encode("y", "category"))
    var j = c.to_json()
    assert_true('"revenue": 1234.56' in j, "money goes to Flint in dollars")
    assert_true('"chartType": "Bar Chart"' in j)
    var font = Font()
    assert_equal(c.hit(400, 200, font, 200, 10), 0)
    assert_equal(c.hit(400, 200, font, 200, 120), 2)
    var line = FlintChart("Area Chart").text("m", ["a", "b", "c", "d", "e"]).number("v", [1.0, 2, 3, 4, 5]).encode("x", "m").encode("y", "v")
    var mid = line.hit(600, 200, font, 330, 100)
    assert_true(mid == 2, "a tap in the middle of a line chart picks the middle point")


def same(a: Main, b: Main) -> Bool:
    return (a.month_rev == b.month_rev and a.month_orders == b.month_orders and a.cat_rev == b.cat_rev
            and a.region_rev == b.region_rev and a.product_rev == b.product_rev and a.size_orders == b.size_orders
            and a.year_rev == b.year_rev and a.year_orders == b.year_orders and a.year_units == b.year_units)


def test_engines_agree_on_every_result() raises:
    var app = Main()
    var steps: List[Tuple[Int, Int]] = [(YEAR, 0), (YEAR, 2), (CHANNEL, 1), (YEAR, 3), (CHANNEL, 0)]
    app.category = 3
    app.region = 1
    var checked = 0
    for step in steps:
        app.update(Event(step[0], "", step[1]))
        var results = List[List[Int]]()
        for engine in [0, 1, 2]:
            app.update(Event(ENGINE, "", engine))
            assert_equal(app.engine, engine)  # no quiet fallback: the engine picked is the one that ran
            if engine == 0:
                assert_true(app.table()[].on_gpu(), "the GPU engine needs a GPU")
            if engine == 2:
                assert_true(app.mx[0].ready, "MX frame didn't run: " + app.mx[0].problem)
            var all = List[Int]()
            for part in [app.month_rev.copy(), app.cat_rev.copy(), app.region_rev.copy(), app.product_rev.copy(),
                         app.size_orders.copy(), app.year_rev.copy(), app.year_orders.copy(), app.year_units.copy(),
                         app.month_orders.copy()]:
                for v in part:
                    all.append(v)
            results.append(all^)
        assert_true(results[0] == results[1], "GPU = CPU on every result")
        assert_true(results[0] == results[2], "GPU = MX frame on every result")
        checked += len(results[0])
    print("ENGINES: identical on " + String(checked) + " numbers per engine, 5 filter settings")


def main() raises:
    test_numbers()
    test_calendar()
    test_crossfilter_rules()
    test_flint_export_and_hit()
    test_engines_agree_on_every_result()
    print("ANALYTICS TESTS PASSED")
