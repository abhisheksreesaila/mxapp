# mojoui.sheetpage: the objects on a sheet (Numbers): charts and pivots that sit beside the table on a Board, each
# with a title bar (drag it to move the object) and a close button. An object is a small record (what it shows and
# where), its numbers come from one MX frame group-by over the table (the session's edits included), and it reads in its
# value column's format. Apps keep a List[SheetObject], call compute() after changes, and place object_card()s.

from mojoui.view import View, Text, Button, Canvas, VStack, HStack, Spacer, Card, HEADLINE, CAPTION, ICON_ONLY, SUBTLE, CENTER, START, NO_MSG
from mxframe import Expr, col, lit, least, greatest
from mojoui.sheet import Sheet, TEXT, DECIMAL, INT, DATE
from mojoui.chartview import ChartView
from mojoui.pivot import PivotTable
from mojoui.numformat import CURRENCY
from mojoui.charts import fixed, grouped

comptime OBJ_CHART = 1
comptime OBJ_PIVOT = 2
comptime CHART_BAR = 0
comptime CHART_LINE = 1
comptime HEADER_H = 44  # an object's title bar (its drag handle)
# A chart's spec (goal 28): how its groups combine, their order, how many show, the rows it reads
comptime COMBINE_SUM = 0
comptime COMBINE_AVERAGE = 1
comptime COMBINE_COUNT = 2  # (rows: the value column doesn't matter)
comptime COMBINES: List[String] = ["Sum", "Average", "Count"]
comptime ORDER_TABLE = 0  # (the groups as the table first met them)
comptime ORDER_LARGEST = 1
comptime ORDER_SMALLEST = 2
comptime ORDER_AZ = 3
comptime ORDERS: List[String] = ["as in the table", "largest first", "smallest first", "A to Z"]
comptime TOPS: List[Int] = [0, 3, 5, 10]  # (0: every group)


@fieldwise_init
struct SheetObject(Copyable, Movable):
    var kind: Int  # OBJ_CHART, OBJ_PIVOT
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var value: Int  # the value column (summed)
    var group: Int  # charts: group by; pivots: rows
    var across: Int  # pivots: columns (-1: none)
    var style: Int  # charts: CHART_BAR, CHART_LINE
    var selected: Int  # charts: the picked bar or point (-1)
    var combine: Int  # charts: COMBINE_SUM, COMBINE_AVERAGE, COMBINE_COUNT
    var order: Int  # charts: ORDER_TABLE … ORDER_AZ
    var top: Int  # charts: how many groups show (0: all)
    var only_col: Int  # charts: the rows it reads: this text or Yes/No column's value `only_code` (-1: every row)
    var only_code: Int
    var labels: List[String]  # (computed) the groups' texts (charts: in the chart's order, cut to its top N)
    var cols: List[String]  # (computed) pivots: the columns' texts
    var sums: List[Int]  # (computed) per group (pivots: rows × columns), in the value column's stored units
    var counts: List[Int]  # (computed) how many rows fell in each
    var present: List[Int]  # (computed) charts: how many of them have a value (an average divides by this)
    var values: List[Float64]  # (computed) charts: what each bar shows, in the column's own units (a count: rows)
    var milliseconds: Float64

    @staticmethod
    def chart(value: Int, group: Int, x: Int, y: Int, w: Int = 520, h: Int = 320) -> SheetObject:
        return SheetObject(OBJ_CHART, x, y, w, h, value, group, -1, CHART_BAR, -1, COMBINE_SUM, ORDER_TABLE, 0, -1, 0,
                           List[String](), List[String](), List[Int](), List[Int](), List[Int](), List[Float64](), 0)

    @staticmethod
    def pivot(value: Int, rows: Int, across: Int, x: Int, y: Int, w: Int = 640, h: Int = 320) -> SheetObject:
        return SheetObject(OBJ_PIVOT, x, y, w, h, value, rows, across, CHART_BAR, -1, COMBINE_SUM, ORDER_TABLE, 0, -1, 0,
                           List[String](), List[String](), List[Int](), List[Int](), List[Int](), List[Float64](), 0)


def groups_of(sheet: Sheet, c: Int) -> Int:
    """How many codes a text column can hold now (its dictionary and the words typed into it)."""
    return sheet.word_count(c)


comptime BLANK = "(blank)"


def total_of(xs: List[Int]) -> Int:
    var t = 0
    for x in xs:
        t += x
    return t


def with_blanks(cells: List[Int], by_row: List[Int], by_col: List[Int], total: Int, ng: Int, nc: Int, blank_row: Bool, blank_col: Bool) -> List[Int]:
    """The grid of `cells` (ng rows × nc columns, rows whose row and column are both known) with a "(blank)" row
    and/or column added, so every row of the table lands in some cell: a row with an empty column value is the row's
    total (`by_row`) less its cells, one with an empty row value is the column's total (`by_col`) less its cells, and
    one with both empty is what is left of the table's `total`."""
    var cols = nc + (1 if blank_col else 0)
    var rows = ng + (1 if blank_row else 0)
    var out = List[Int](length=rows * cols, fill=0)
    var corner = total - total_of(by_row) - total_of(by_col) + total_of(cells)
    for r in range(ng):
        var seen = 0
        for c in range(nc):
            out[r * cols + c] = cells[r * nc + c]
            seen += cells[r * nc + c]
        if blank_col:
            out[r * cols + nc] = by_row[r] - seen
    if blank_row:
        for c in range(nc):
            var seen = 0
            for r in range(ng):
                seen += cells[r * nc + c]
            out[ng * cols + c] = by_col[c] - seen
        if blank_col:
            out[ng * cols + nc] = corner
    return out^


def compute(mut obj: SheetObject, sheet: Sheet, filter: Optional[Expr] = None) raises:
    """The object's numbers: one group-by of its value column by its text column(s), on the GPU for a big table.
    Rows whose group is empty make a "(blank)" group (a row and/or a column of a pivot), as in a spreadsheet's pivot
    table, so the numbers add up to the column's total."""
    var cond = filter.copy()
    if obj.kind == OBJ_CHART and obj.only_col >= 0:  # (the chart's own rows, within any the caller keeps: a Report's filter)
        var own = sheet.where_is(obj.only_col, obj.only_code)
        cond = Optional[Expr]((cond.value().copy() & own^) if cond else own^)
    var ng = groups_of(sheet, obj.group)
    obj.labels = List[String]()
    for code in range(ng):
        obj.labels.append(sheet.text_of(obj.group, Int64(code)))
    obj.cols = List[String]()
    var all = sheet.totals(obj.value, None, 1, cond)
    var by_row = sheet.totals(obj.value, col(sheet.name(obj.group)), ng, cond)
    var blank_row = all.counts[0] > total_of(by_row.counts)
    var pivot = obj.kind == OBJ_PIVOT and obj.across >= 0
    if not pivot:
        obj.sums = by_row.sums.copy()
        obj.counts = by_row.counts.copy()
        obj.present = by_row.present.copy()
        if blank_row:
            obj.labels.append(BLANK)
            obj.sums.append(all.sums[0] - total_of(by_row.sums))
            obj.counts.append(all.counts[0] - total_of(by_row.counts))
            obj.present.append(all.present[0] - total_of(by_row.present))
        obj.milliseconds = all.milliseconds + by_row.milliseconds
        shape(obj, sheet)
        return
    var nc = groups_of(sheet, obj.across)
    for code in range(nc):
        obj.cols.append(sheet.text_of(obj.across, Int64(code)))
    var across = col(sheet.name(obj.across))
    var key = col(sheet.name(obj.group)) * lit(nc) + across  # (row × columns + column: one dense key)
    var cells = sheet.totals(obj.value, key^, ng * nc, cond)
    var by_col = sheet.totals(obj.value, across.copy(), nc, cond)
    var blank_col = all.counts[0] > total_of(by_col.counts)
    obj.sums = with_blanks(cells.sums, by_row.sums, by_col.sums, all.sums[0], ng, nc, blank_row, blank_col)
    obj.counts = with_blanks(cells.counts, by_row.counts, by_col.counts, all.counts[0], ng, nc, blank_row, blank_col)
    if blank_row:
        obj.labels.append(BLANK)
    if blank_col:
        obj.cols.append(BLANK)
    obj.milliseconds = all.milliseconds + by_row.milliseconds + cells.milliseconds + by_col.milliseconds


def shown_value(obj: SheetObject, sheet: Sheet, k: Int) -> Float64:
    """Group k's bar in the column's own units: its sum, its average, or its rows."""
    if obj.combine == COMBINE_COUNT:
        return Float64(obj.counts[k])
    var scale = 10.0 ** Float64(sheet.scale(obj.value) if sheet.kind(obj.value) == DECIMAL else 0)
    if obj.combine == COMBINE_AVERAGE:
        var n = obj.present[k] if k < len(obj.present) else 0
        return Float64(obj.sums[k]) / Float64(n) / scale if n > 0 else 0.0
    return Float64(obj.sums[k]) / scale


def before(obj: SheetObject, a: Int, b: Int) -> Bool:
    """Whether group a comes before group b in the chart's order (ties: as in the table)."""
    if obj.order == ORDER_LARGEST and obj.values[a] != obj.values[b]:
        return obj.values[a] > obj.values[b]
    if obj.order == ORDER_SMALLEST and obj.values[a] != obj.values[b]:
        return obj.values[a] < obj.values[b]
    if obj.order == ORDER_AZ:
        if (obj.labels[a] == BLANK) != (obj.labels[b] == BLANK):  # ("(blank)" last, as spreadsheets put it)
            return obj.labels[b] == BLANK
        var x = obj.labels[a].lower()
        var y = obj.labels[b].lower()
        if x != y:
            return x < y
    return a < b


def shape(mut obj: SheetObject, sheet: Sheet):
    """The spec's shape over the computed groups: each bar's value (its combine), then its order and top N."""
    var n = len(obj.labels)
    obj.values = List[Float64]()
    for k in range(n):
        obj.values.append(shown_value(obj, sheet, k))
    var idx = List[Int]()
    for k in range(n):
        idx.append(k)
    if obj.order != ORDER_TABLE:  # (a merge sort of the group numbers: groups can be thousands, a customer column)
        var width = 1
        var tmp = List[Int](length=n, fill=0)
        while width < n:
            var lo = 0
            while lo < n:
                var mid = min(lo + width, n)
                var hi = min(lo + 2 * width, n)
                var i = lo
                var j = mid
                var o = lo
                while i < mid and j < hi:
                    if before(obj, idx[j], idx[i]):
                        tmp[o] = idx[j]
                        j += 1
                    else:
                        tmp[o] = idx[i]
                        i += 1
                    o += 1
                while i < mid:
                    tmp[o] = idx[i]
                    i += 1
                    o += 1
                while j < hi:
                    tmp[o] = idx[j]
                    j += 1
                    o += 1
                lo += 2 * width
            for k in range(n):
                idx[k] = tmp[k]
            width *= 2
    var keep = min(obj.top, n) if obj.top > 0 else n
    var labels = List[String]()
    var sums = List[Int]()
    var counts = List[Int]()
    var present = List[Int]()
    var values = List[Float64]()
    for k in range(keep):
        var g = idx[k]
        labels.append(obj.labels[g])
        sums.append(obj.sums[g])
        counts.append(obj.counts[g])
        present.append(obj.present[g] if g < len(obj.present) else 0)
        values.append(obj.values[g])
    obj.labels = labels^
    obj.sums = sums^
    obj.counts = counts^
    obj.present = present^
    obj.values = values^
    if obj.selected >= keep:
        obj.selected = -1


def value_text(obj: SheetObject, sheet: Sheet, k: Int) -> String:
    """Group k's figure as the chart states it: a sum in the column's format, an average in it (two more places for
    whole numbers), a count of rows."""
    if obj.combine == COMBINE_COUNT:
        return grouped(obj.counts[k])
    if obj.combine == COMBINE_AVERAGE:
        var n = obj.present[k] if k < len(obj.present) else 0
        return sheet.format_average(obj.value, obj.sums[k], n) if n > 0 else String("—")  # (no values: no average, not 0)
    return sheet.format_value(obj.value, Int64(obj.sums[k]), total=True)


comptime BINS = 16


def shape_of(sheet: Sheet, c: Int) raises -> List[Float64]:
    """Bar heights (0 to 1) of a column's distribution over every row: a text column by value, a number column in
    16 equal bins between its smallest and largest value. Empty cells aren't counted."""
    var present: List[Int]
    if sheet.kind(c) == TEXT:
        present = sheet.totals(c, col(sheet.name(c)), sheet.word_count(c)).present.copy()
    else:
        var span = sheet.span(c)
        if not span[2]:
            return List[Float64]()
        var width = max((Int(span[1]) - Int(span[0]) + BINS) // BINS, 1)
        var bin = least(greatest((col(sheet.name(c)) - lit(Int(span[0]))) // lit(width), lit(0)), lit(BINS - 1))
        present = sheet.totals(c, bin^, BINS).present.copy()
    var top = 1
    for n in present:
        top = max(top, n)
    var out = List[Float64]()
    for n in present:
        out.append(Float64(n) / Float64(top))
    return out^


def object_title(obj: SheetObject, sheet: Sheet) -> String:
    if obj.kind == OBJ_PIVOT:
        return sheet.name(obj.value) + " · " + sheet.name(obj.group) + (" × " + sheet.name(obj.across) if obj.across >= 0 else "")
    if obj.combine == COMBINE_COUNT:
        return "rows by " + sheet.name(obj.group)
    return ("average " if obj.combine == COMBINE_AVERAGE else "") + sheet.name(obj.value) + " by " + sheet.name(obj.group)


def chart_view(obj: SheetObject, sheet: Sheet) -> ChartView:
    """The chart, drawn by mojoui.charts: values in the column's units (money as cents when it's Currency)."""
    var scale = sheet.scale(obj.value) if sheet.kind(obj.value) == DECIMAL else 0
    var money = sheet.format_of(obj.value).style == CURRENCY and obj.combine != COMBINE_COUNT
    var values = List[Float64]()
    if obj.kind == OBJ_CHART and len(obj.values) == len(obj.labels):
        for v in obj.values:  # (money: cents)
            values.append(v * 100.0 if money else v)
    else:
        for s in obj.sums:  # (money: cents, whatever the column's own scale)
            values.append(Float64(s) * (10.0 ** Float64(2 - scale)) if money else Float64(s) / Float64(10 ** scale))
    var cv = ChartView(object_title(obj, sheet), obj.labels.copy(), values^, "rows" if obj.combine == COMBINE_COUNT else sheet.name(obj.value), money, obj.selected)
    if obj.style == CHART_LINE:
        cv.kind = "Line Chart"
    return cv^


def chart_text(obj: SheetObject, sheet: Sheet) -> String:
    """The chart's numbers as tab-separated text (its group column, the value column; a line per bar or point, in
    the value column's format): what an agent reads (App.describe, D-163)."""
    var out = sheet.name(obj.group) + "\t" + (sheet.name(obj.value) if obj.combine == COMBINE_SUM else (("average " + sheet.name(obj.value)) if obj.combine == COMBINE_AVERAGE else "rows"))
    for k in range(min(len(obj.labels), len(obj.sums))):
        out += "\n" + obj.labels[k] + "\t" + value_text(obj, sheet, k)
    return out


def readout(obj: SheetObject, sheet: Sheet) -> String:
    """The picked bar or point, in the value column's format ("West · $72,061,236.00"); a hint when none is."""
    if 0 <= obj.selected < len(obj.sums) and obj.selected < len(obj.labels):
        return obj.labels[obj.selected] + " · " + value_text(obj, sheet, obj.selected)
    return "Tap a bar to read it"


def pivot_view(obj: SheetObject, sheet: Sheet, height: Int) -> View:
    """The pivot's cells, row and column totals, in the value column's format."""
    var nc = max(len(obj.cols), 1)
    var rows = List[String]()
    var cells = List[String]()
    var row_totals = List[String]()
    var col_sums = List[Int](length=nc, fill=0)
    var grand = 0
    for r in range(len(obj.labels)):
        var row_sum = 0
        var rows_in = 0
        for c in range(nc):
            var v = obj.sums[r * nc + c] if r * nc + c < len(obj.sums) else 0
            rows_in += obj.counts[r * nc + c] if r * nc + c < len(obj.counts) else 0
            row_sum += v
            col_sums[c] += v
        if rows_in == 0:
            continue  # (a value no row uses any more; a row whose values cancel out still shows)
        rows.append(obj.labels[r])
        for c in range(nc):
            var v = obj.sums[r * nc + c] if r * nc + c < len(obj.sums) else 0
            cells.append(sheet.format_value(obj.value, Int64(v), total=True))
        row_totals.append(sheet.format_value(obj.value, Int64(row_sum), total=True))
        grand += row_sum
    var col_totals = List[String]()
    for c in range(nc):
        col_totals.append(sheet.format_value(obj.value, Int64(col_sums[c]), total=True))
    var heads = obj.cols.copy() if len(obj.cols) > 0 else [sheet.name(obj.value)]
    return PivotTable(rows, heads, cells, totals=True, row_totals=row_totals, col_totals=col_totals,
                      grand=sheet.format_value(obj.value, Int64(grand), total=True), height=height,
                      corner=sheet.name(obj.group))


def object_card(obj: SheetObject, sheet: Sheet, canvas: Int, version: Int, on_tap: Int, on_close: Int, on_pick: Int) -> View:
    """The object as it sits on the sheet: a title bar (its drag handle) with a close button, then the chart (on
    Canvas `canvas`) and its readout, or the pivot."""
    var head = HStack(Button(object_title(obj, sheet), on_pick, style=SUBTLE), Spacer(),
                      Text(fixed(obj.milliseconds, 1) + " ms", CAPTION),
                      Button("Remove", on_close, ICON_ONLY, icon="close"), spacing=8).fill().align(CENTER).height(HEADER_H - 8)
    var body: View
    if obj.kind == OBJ_CHART:
        body = VStack(Canvas(canvas, version, on_gesture=on_tap).fill().height(obj.h - HEADER_H - 40).tag("chart-" + String(canvas - 9)),
                      Text(readout(obj, sheet), CAPTION).tag("readout"), spacing=4).fill()
    else:
        body = pivot_view(obj, sheet, obj.h - HEADER_H - 24)
    return Card(head, body, spacing=4)


def free_spot(objects: List[SheetObject], table_bottom: Int, width: Int, w: Int, h: Int) -> Tuple[Int, Int]:
    """Where a new object goes: the top-most, then left-most place below the table where it overlaps nothing.
    Candidates are the left edge and just right of / below each object already there (16 points apart)."""
    var xs = List[Int]()
    var ys = List[Int]()
    xs.append(0)
    ys.append(table_bottom + 16)
    for o in objects:
        xs.append(o.x + o.w + 16)
        ys.append(o.y + o.h + 16)
    var best_x = 0
    var best_y = -1
    for y in ys:
        for x in xs:
            if x + w > max(width, w) or (best_y >= 0 and (y > best_y or (y == best_y and x >= best_x))):
                continue
            var clear = True
            for o in objects:
                if x < o.x + o.w + 16 and o.x < x + w + 16 and y < o.y + o.h + 16 and o.y < y + h + 16:
                    clear = False
                    break
            if clear:
                best_x = x
                best_y = y
    if best_y < 0:  # (nothing fits beside: below everything)
        var bottom = table_bottom
        for o in objects:
            bottom = max(bottom, o.y + o.h)
        return (0, bottom + 16)
    return (best_x, best_y)
