# mojoui.reportpage: a Report built from scratch (Stitch 06): a title, KPI tiles (sum, average or count of a
# column), chart tiles (a column by a text column), an empty "add" row, and filters that apply to every tile.
# Every number is a group-by with the filter as a condition, so a filter change recomputes the whole page.

from mojoui.view import (View, Text, Button, Canvas, VStack, HStack, Grid, Spacer, Card, TITLE, HEADLINE, CAPTION, SUBTLE,
                         ICON_ONLY, CENTER, START, NO_MSG)
from mxframe import Expr
from mojoui.sheet import Sheet, TEXT, DECIMAL, INT
from mojoui.kpi import KpiView
from mojoui.sheetpage import SheetObject, compute, chart_view, readout, groups_of
from mojoui.charts import grouped

comptime TILE_SUM = 0
comptime TILE_AVERAGE = 1
comptime TILE_COUNT = 2
comptime TILE_CHART = 3
comptime TILE_DISTINCT = 4  # different values of any column (text too): the engine's count_distinct
comptime TILE_MEDIAN = 5  # the middle value of a number column: the engine's median
comptime TILE_LAST = TILE_MEDIAN
comptime TILE_NAMES: List[String] = ["Sum", "Average", "Count", "Chart", "Distinct", "Median"]


@fieldwise_init
struct ReportTile(Copyable, Movable):
    var kind: Int  # TILE_SUM … TILE_MEDIAN
    var col: Int  # the value column
    var group: Int  # charts: group by
    var total: Int  # (computed) the sum over the filtered rows
    var count: Int  # (computed) how many rows
    var present: Int  # (computed) how many of them have a value (an average divides by this; a median: 1 when there is one)
    var chart: SheetObject  # (charts) the chart's numbers


@fieldwise_init
struct ReportFilter(Copyable, Movable):
    var col: Int  # a text column (-1: every row)
    var code: Int  # its value's code

    def condition(self, sheet: Sheet) -> Optional[Expr]:
        """The rows the filter keeps: its column equals its value (none: every row)."""
        if self.col < 0:
            return None
        return sheet.where_is(self.col, self.code)

    def words(self, sheet: Sheet) -> String:
        return "every row" if self.col < 0 else sheet.name(self.col) + " = " + sheet.text_of(self.col, Int64(self.code))


def new_tile(kind: Int, col: Int, group: Int) -> ReportTile:
    return ReportTile(kind, col, group, 0, 0, 0, SheetObject.chart(col, group, 0, 0))


def compute_tile(mut t: ReportTile, sheet: Sheet, filter: ReportFilter) raises:
    """The tile's number (or chart) over the rows the filter keeps."""
    var condition = filter.condition(sheet)
    if t.kind == TILE_CHART:
        t.chart.value = t.col
        t.chart.group = t.group
        compute(t.chart, sheet, condition^)
        return
    if t.kind == TILE_DISTINCT:
        t.total = sheet.distinct(t.col, condition^)
        return
    if t.kind == TILE_MEDIAN:
        var m = sheet.median(t.col, condition^)
        t.total = Int(m[0])
        t.present = 1 if m[1] else 0
        return
    var r = sheet.totals(t.col, None, 1, condition^)
    t.total = r.sums[0]
    t.count = r.counts[0]
    t.present = r.present[0]


def tile_value(t: ReportTile, sheet: Sheet) -> String:
    """The KPI's number in its column's format (an average as the status bar shows it; counts are plain)."""
    if t.kind == TILE_COUNT:
        return grouped(t.count)
    if t.kind == TILE_DISTINCT:
        return grouped(t.total)
    if t.kind == TILE_MEDIAN:
        return sheet.format_median(t.col, Int64(t.total)) if t.present > 0 else "—"
    if t.kind == TILE_SUM:
        return sheet.format_value(t.col, Int64(t.total), total=True)
    return sheet.format_average(t.col, t.total, t.present)


def tile_label(t: ReportTile, sheet: Sheet) -> String:
    if t.kind == TILE_COUNT:
        return "Count of rows"
    if t.kind == TILE_DISTINCT:
        return "Different " + sheet.name(t.col)
    return materialize[TILE_NAMES]()[t.kind] + " of " + sheet.name(t.col)


def kpi_of(t: ReportTile, sheet: Sheet, filter: ReportFilter, accent: Bool) -> KpiView:
    return KpiView(tile_label(t, sheet), tile_value(t, sheet), filter.words(sheet), List[Float64](), accent, 0)


def ReportPage(title: String, subtitle: String, kpis: List[View], charts: List[View]) -> View:
    """The page: title, the KPI tiles in a grid of equal widths (three across), the charts (two across, one alone across
    the page). Tiles are added from the app's toolbar."""
    var parts = List[View]()
    parts.append(HStack(Text(title, TITLE), Text(subtitle, CAPTION), spacing=14).align(CENTER))
    if len(kpis) > 0:
        var cells = kpis.copy()
        while len(cells) % 3 != 0:  # (empty cells keep a lone tile a third wide)
            cells.append(Spacer())
        parts.append(Grid(cells^, 3, spacing=14).fill())
    if len(charts) > 0:
        parts.append(Grid(charts, min(2, len(charts)), spacing=14).fill())  # (one chart: the full width)
    return VStack(parts^, spacing=16).fill().align(START)
