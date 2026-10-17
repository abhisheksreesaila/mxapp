# mojoui.reportpage: a Report built from scratch (Stitch 06): a title, KPI tiles (sum, average or count of a
# column), chart tiles (a column by a text column), an empty "add" row, and filters that apply to every tile.
# Every number is a GPU group-by with the filter as a range, so a filter change recomputes the whole page.

from mojoui.view import (View, Text, Button, Canvas, VStack, HStack, Grid, Spacer, Card, TITLE, HEADLINE, CAPTION, SUBTLE,
                         ICON_ONLY, CENTER, START, NO_MSG)
from mojoui.frame import Frame, Range, TEXT, DECIMAL, INT, OP_COL, OP_CONST
from mojoui.frame_gpu import GpuFrame, group_sum
from mojoui.kpi import KpiView
from mojoui.sheetpage import SheetObject, compute, chart_view, readout, value_program, groups_of
from mojoui.charts import grouped

comptime TILE_SUM = 0
comptime TILE_AVERAGE = 1
comptime TILE_COUNT = 2
comptime TILE_CHART = 3
comptime TILE_NAMES: List[String] = ["Sum", "Average", "Count", "Chart"]


@fieldwise_init
struct ReportTile(Copyable, Movable):
    var kind: Int  # TILE_SUM, TILE_AVERAGE, TILE_COUNT, TILE_CHART
    var col: Int  # the value column
    var group: Int  # charts: group by
    var total: Int  # (computed) the sum over the filtered rows
    var count: Int  # (computed) how many rows
    var chart: SheetObject  # (charts) the chart's numbers


@fieldwise_init
struct ReportFilter(Copyable, Movable):
    var col: Int  # a text column (-1: every row)
    var code: Int  # its value's code

    def ranges(self) -> List[Range]:
        var out = List[Range]()
        if self.col >= 0:
            out.append(Range(self.col, Int64(self.code), Int64(self.code)))
        return out^

    def words(self, frame: Frame) -> String:
        return "every row" if self.col < 0 else frame.name(self.col) + " = " + frame.text_of(self.col, Int64(self.code))


def new_tile(kind: Int, col: Int, group: Int) -> ReportTile:
    return ReportTile(kind, col, group, 0, 0, SheetObject.chart(col, group, 0, 0))


def compute_tile(mut t: ReportTile, frame: Frame, gf: GpuFrame, filter: ReportFilter):
    """The tile's number (or chart) over the rows the filter keeps, on the GPU."""
    var ranges = filter.ranges()
    if t.kind == TILE_CHART:
        t.chart.value = t.col
        t.chart.group = t.group
        compute(t.chart, frame, gf, ranges)
        return
    var key = List[Int64]()
    key.append(Int64(OP_CONST))
    key.append(0)
    var r = group_sum(frame, gf, key, value_program(frame, t.col), ranges, 1)
    t.total = r.sums[0]
    t.count = r.counts[0]


def tile_value(t: ReportTile, frame: Frame) -> String:
    """The KPI's number in its column's format (an average as the status bar shows it; counts are plain)."""
    if t.kind == TILE_COUNT:
        return grouped(t.count)
    if t.kind == TILE_SUM:
        return frame.format_value(t.col, Int64(t.total), total=True)
    return frame.format_average(t.col, t.total, t.count)


def tile_label(t: ReportTile, frame: Frame) -> String:
    if t.kind == TILE_COUNT:
        return "Count of rows"
    return materialize[TILE_NAMES]()[t.kind] + " of " + frame.name(t.col)


def kpi_of(t: ReportTile, frame: Frame, filter: ReportFilter, accent: Bool) -> KpiView:
    return KpiView(tile_label(t, frame), tile_value(t, frame), filter.words(frame), List[Float64](), accent, 0)


def ReportPage(title: String, subtitle: String, kpis: List[View], charts: List[View], add_row: View) -> View:
    """The page: title, the KPI row (four across), the charts (two across), then the row that adds tiles."""
    var parts = List[View]()
    parts.append(HStack(Text(title, TITLE), Text(subtitle, CAPTION), spacing=14).align(CENTER))
    if len(kpis) > 0:
        parts.append(Grid(kpis, max(1, min(4, len(kpis))), spacing=14).fill())  # (packed: as many across as there are, up to four)
    if len(charts) > 0:
        parts.append(Grid(charts, 2, spacing=14).fill())
    parts.append(add_row.copy())
    return VStack(parts^, spacing=16).fill().align(START)
