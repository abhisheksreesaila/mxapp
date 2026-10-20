# mojoui.sheetpage: the objects on a sheet (Numbers): charts and pivots that sit beside the table on a Board, each
# with a title bar (drag it to move the object) and a close button. An object is a small record (what it shows and
# where), its numbers come from one MX frame group-by over the table (the session's edits included), and it reads in its
# value column's format. Apps keep a List[SheetObject], call compute() after changes, and place object_card()s.

from mojoui.view import View, Text, Button, Canvas, VStack, HStack, Spacer, Card, HEADLINE, CAPTION, ICON_ONLY, SUBTLE, CENTER, START, NO_MSG
from mxframe import Expr, col, lit, least, greatest
from mojoui.sheet import Sheet, TEXT, DECIMAL, INT, DATE, BOOL
from mojoui.sentence import Word, Sentence, sentence_text
from mojoui.chartview import ChartView
from mojoui.pivot import PivotTable
from mojoui.numformat import CURRENCY
from mojoui.charts import fixed, grouped

comptime OBJ_CHART = 1
comptime OBJ_PIVOT = 2
comptime CHART_BAR = 0
comptime CHART_LINE = 1
comptime HEADER_H = 44  # an object's title bar (its drag handle)
comptime SENTENCE_H = 52  # a chart's title bar when its title is its sentence (two lines)
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
comptime MOVE_FRAMES = 20  # a spec change moves the bars over this many frames (~330 ms at 60 Hz), on the calm curve


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
    var was_labels: List[String]  # charts: what it showed before its last change, and how many frames it has moved since
    var was_values: List[Float64]
    var moved: Int

    @staticmethod
    def chart(value: Int, group: Int, x: Int, y: Int, w: Int = 520, h: Int = 320) -> SheetObject:
        return SheetObject(OBJ_CHART, x, y, w, h, value, group, -1, CHART_BAR, -1, COMBINE_SUM, ORDER_TABLE, 0, -1, 0,
                           List[String](), List[String](), List[Int](), List[Int](), List[Int](), List[Float64](), 0,
                           List[String](), List[Float64](), MOVE_FRAMES)

    @staticmethod
    def pivot(value: Int, rows: Int, across: Int, x: Int, y: Int, w: Int = 640, h: Int = 320) -> SheetObject:
        return SheetObject(OBJ_PIVOT, x, y, w, h, value, rows, across, CHART_BAR, -1, COMBINE_SUM, ORDER_TABLE, 0, -1, 0,
                           List[String](), List[String](), List[Int](), List[Int](), List[Int](), List[Float64](), 0,
                           List[String](), List[Float64](), MOVE_FRAMES)


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


# The words of a chart's sentence (goal 28 M1): each setting is a token
comptime SLOT_COMBINE = 0
comptime SLOT_VALUE = 1
comptime SLOT_GROUP = 2
comptime SLOT_ORDER = 3
comptime SLOT_TOP = 4
comptime SLOT_FILTER = 5
comptime SLOT_MARK = 6
comptime SLOTS = 7
comptime SLOT_NAMES: List[String] = ["Combine", "Value", "Group by", "Order", "Show", "Rows", "As"]
comptime FILTER_WORDS = 12  # a text column offers its values as filters when it has at most this many


def number_columns(sheet: Sheet) -> List[Int]:
    var out = List[Int]()
    for c in range(sheet.columns()):
        if sheet.kind(c) == INT or sheet.kind(c) == DECIMAL:
            out.append(c)
    return out^


def text_columns(sheet: Sheet) -> List[Int]:
    var out = List[Int]()
    for c in range(sheet.stored()):
        if sheet.kind(c) == TEXT:
            out.append(c)
    return out^


def slot_text(obj: SheetObject, sheet: Sheet, slot: Int) -> String:
    """What a token reads now."""
    if slot == SLOT_COMBINE:
        return materialize[COMBINES]()[obj.combine]
    if slot == SLOT_VALUE:
        return "rows" if obj.combine == COMBINE_COUNT else sheet.name(obj.value)
    if slot == SLOT_GROUP:
        return sheet.name(obj.group)
    if slot == SLOT_ORDER:
        return materialize[ORDERS]()[obj.order]
    if slot == SLOT_TOP:
        return ("every " + sheet.name(obj.group)) if obj.top == 0 else ("top " + String(obj.top))
    if slot == SLOT_FILTER:
        if obj.only_col < 0:
            return "every row"
        if sheet.kind(obj.only_col) == BOOL:
            return ("only " if obj.only_code == 1 else "not ") + sheet.name(obj.only_col)
        return "only " + sheet.text_of(obj.only_col, Int64(obj.only_code))
    return "a line" if obj.style == CHART_LINE else "bars"


def chart_words(obj: SheetObject, sheet: Sheet, on_word: Int, cref: Int, lit: List[Int] = []) -> List[Word]:
    """The chart's title as a sentence: "Sum of amount by region, largest first, top 5, every row, as bars". Token
    `slot` sends `on_word + slot` and is tagged "word-<cref>-<slot>" (its popover's anchor)."""
    var out = List[Word]()
    var glue: List[String] = ["", " of ", " by ", ", ", ", ", ", ", ", as "]
    for slot in range(SLOTS):
        if glue[slot] != "":
            out.append(Word(glue[slot]))
        var changed = False
        for s in lit:
            changed = changed or s == slot
        out.append(Word(slot_text(obj, sheet, slot), on_word + slot, "word-" + String(cref) + "-" + String(slot), changed))
    return out^


def chart_sentence(obj: SheetObject, sheet: Sheet) -> String:
    return sentence_text(chart_words(obj, sheet, 1, 0))


def chart_choices(obj: SheetObject, sheet: Sheet, slot: Int) -> List[String]:
    """What a token offers (apply_choice takes the index)."""
    var out = List[String]()
    if slot == SLOT_COMBINE:
        return materialize[COMBINES]()
    if slot == SLOT_VALUE:
        for c in number_columns(sheet):
            out.append(sheet.name(c))
        out.append("rows")
    elif slot == SLOT_GROUP:
        for c in text_columns(sheet):
            out.append(sheet.name(c))
    elif slot == SLOT_ORDER:
        return materialize[ORDERS]()
    elif slot == SLOT_TOP:
        out.append("every " + sheet.name(obj.group))
        for n in materialize[TOPS]()[1:]:
            out.append("top " + String(n))
    elif slot == SLOT_FILTER:
        out.append("every row")
        for c in range(sheet.stored()):
            if sheet.kind(c) == BOOL:
                out.append("only " + sheet.name(c))
                out.append("not " + sheet.name(c))
            elif sheet.kind(c) == TEXT and c != obj.group and 2 <= sheet.word_count(c) <= FILTER_WORDS:
                for code in range(sheet.word_count(c)):
                    out.append("only " + sheet.text_of(c, Int64(code)))
    else:
        out.append("bars")
        out.append("a line")
    return out^


def apply_choice(mut obj: SheetObject, sheet: Sheet, slot: Int, k: Int) -> Bool:
    """Choice k of chart_choices(slot) into the spec; False when it isn't one."""
    var choices = chart_choices(obj, sheet, slot)
    if k < 0 or k >= len(choices):
        return False
    if slot == SLOT_COMBINE:
        obj.combine = k
    elif slot == SLOT_VALUE:
        var nums = number_columns(sheet)
        if k == len(nums):
            obj.combine = COMBINE_COUNT
        else:
            obj.value = nums[k]
            if obj.combine == COMBINE_COUNT:
                obj.combine = COMBINE_SUM  # (a column to count rows of reads as its sum)
    elif slot == SLOT_GROUP:
        obj.group = text_columns(sheet)[k]
        if obj.only_col == obj.group:
            obj.only_col = -1
    elif slot == SLOT_ORDER:
        obj.order = k
    elif slot == SLOT_TOP:
        obj.top = materialize[TOPS]()[k]
        if obj.top > 0 and obj.order == ORDER_TABLE:
            obj.order = ORDER_LARGEST  # ("top 5" means the five largest unless an order says otherwise)
    elif slot == SLOT_FILTER:
        obj.only_col = -1
        var at = 1
        for c in range(sheet.stored()):
            if sheet.kind(c) == BOOL:
                if k == at or k == at + 1:
                    obj.only_col = c
                    obj.only_code = 1 if k == at else 0
                at += 2
            elif sheet.kind(c) == TEXT and c != obj.group and 2 <= sheet.word_count(c) <= FILTER_WORDS:
                if at <= k < at + sheet.word_count(c):
                    obj.only_col = c
                    obj.only_code = k - at
                at += sheet.word_count(c)
    else:
        obj.style = CHART_LINE if k == 1 else CHART_BAR
    obj.selected = -1
    return True


def chosen(obj: SheetObject, sheet: Sheet, slot: Int) -> Int:
    """Which choice is set now (the popover marks it)."""
    var current = slot_text(obj, sheet, slot)
    var choices = chart_choices(obj, sheet, slot)
    for k in range(len(choices)):
        if choices[k] == current:
            return k
    return -1


def object_title(obj: SheetObject, sheet: Sheet) -> String:
    if obj.kind == OBJ_PIVOT:
        return sheet.name(obj.value) + " · " + sheet.name(obj.group) + (" × " + sheet.name(obj.across) if obj.across >= 0 else "")
    if obj.combine == COMBINE_COUNT:
        return "rows by " + sheet.name(obj.group)
    return ("average " if obj.combine == COMBINE_AVERAGE else "") + sheet.name(obj.value) + " by " + sheet.name(obj.group)


def start_move(mut obj: SheetObject, before: SheetObject):
    """The chart will move from what `before` showed (call before computing its new numbers' view)."""
    obj.was_labels = before.labels.copy()
    obj.was_values = before.values.copy()
    obj.moved = 0


def ease(t: Float64) -> Float64:
    """The calm curve: fast out of the start, settling without overshoot (a cubic ease-out)."""
    var u = 1.0 - min(max(t, 0.0), 1.0)
    return 1.0 - u * u * u


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
    if obj.kind == OBJ_CHART and obj.moved < MOVE_FRAMES:  # (mid-move: from the old bars, in the same units)
        var was = List[Float64]()
        for v in obj.was_values:
            was.append(v * 100.0 if money else v)
        cv.moving_from(obj.was_labels.copy(), was^, ease(Float64(obj.moved) / Float64(MOVE_FRAMES)))
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
    return "Tap a point to read it" if obj.style == CHART_LINE else "Tap a bar to read it"


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


def object_card(obj: SheetObject, sheet: Sheet, canvas: Int, version: Int, on_tap: Int, on_close: Int, on_pick: Int, on_word: Int = NO_MSG, cref: Int = 0,
                lit: List[Int] = [], under: List[View] = [], under_h: Int = 0) -> View:
    """The object as it sits on the sheet: a title bar (its drag handle) with a close button, then the chart (on
    Canvas `canvas`) and its readout, or the pivot. With `on_word`, a chart's title is its sentence (chart_words)."""
    var title = Sentence(chart_words(obj, sheet, on_word, cref, lit), width=max(24, (obj.w - 130) // 8), tag="sentence-" + String(cref)) if obj.kind == OBJ_CHART and on_word != NO_MSG else Button(object_title(obj, sheet), on_pick, style=SUBTLE)
    var head_h = SENTENCE_H if obj.kind == OBJ_CHART and on_word != NO_MSG else HEADER_H - 8  # (a sentence takes two lines)
    var head = HStack(title^, Spacer(),
                      Text(fixed(obj.milliseconds, 1) + " ms", CAPTION),
                      Button("Remove", on_close, ICON_ONLY, icon="close"), spacing=8).fill().align(START if on_word != NO_MSG else CENTER).height(head_h)
    var body: View
    if obj.kind == OBJ_CHART:
        var parts = under.copy()  # (an ask field under the sentence, when the app gives one: the canvas gives up its height)
        parts.append(Canvas(canvas, version, on_gesture=on_tap).fill().height(obj.h - head_h - 48 - under_h).tag("chart-" + String(canvas - 9)))
        parts.append(Text(readout(obj, sheet), CAPTION).tag("readout"))
        body = VStack(parts^, spacing=4).fill()
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
