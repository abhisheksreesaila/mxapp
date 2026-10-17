# mojoui.sheetpage: the objects on a sheet (Numbers): charts and pivots that sit beside the table on a Board, each
# with a title bar (drag it to move the object) and a close button. An object is a small record (what it shows and
# where), its numbers come from one GPU group-by over the table (the session's edits included), and it reads in its
# value column's format. Apps keep a List[SheetObject], call compute() after changes, and place object_card()s.

from mojoui.view import View, Text, Button, Canvas, VStack, HStack, Spacer, Card, HEADLINE, CAPTION, ICON_ONLY, SUBTLE, CENTER, START, NO_MSG
from mojoui.frame import Frame, Range, TEXT, DECIMAL, INT, DATE, OP_COL
from mojoui.frame_gpu import GpuFrame, group_sum, pivot_program
from mojoui.chartview import ChartView
from mojoui.pivot import PivotTable
from mojoui.numformat import CURRENCY
from mojoui.charts import fixed

comptime OBJ_CHART = 1
comptime OBJ_PIVOT = 2
comptime CHART_BAR = 0
comptime CHART_LINE = 1
comptime HEADER_H = 44  # an object's title bar (its drag handle)


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
    var labels: List[String]  # (computed) the groups' texts
    var cols: List[String]  # (computed) pivots: the columns' texts
    var sums: List[Int]  # (computed) per group (pivots: rows × columns), in the value column's stored units
    var counts: List[Int]  # (computed) how many rows fell in each
    var milliseconds: Float64

    @staticmethod
    def chart(value: Int, group: Int, x: Int, y: Int, w: Int = 520, h: Int = 320) -> SheetObject:
        return SheetObject(OBJ_CHART, x, y, w, h, value, group, -1, CHART_BAR, -1, List[String](), List[String](), List[Int](), List[Int](), 0)

    @staticmethod
    def pivot(value: Int, rows: Int, across: Int, x: Int, y: Int, w: Int = 640, h: Int = 320) -> SheetObject:
        return SheetObject(OBJ_PIVOT, x, y, w, h, value, rows, across, CHART_BAR, -1, List[String](), List[String](), List[Int](), List[Int](), 0)


def value_program(frame: Frame, col: Int) -> List[Int64]:
    """A column as a GPU program (a formula column inlined into the stored columns it reads)."""
    var p = List[Int64]()
    p.append(Int64(OP_COL))
    p.append(Int64(col))
    return frame.flatten(p)


def groups_of(frame: Frame, col: Int) -> Int:
    """How many codes a text column can hold now (its dictionary and the words typed into it)."""
    return len(frame.base()[].cols[col].dictionary) + len(frame.words[col]) if col < frame.stored() else 0


def compute(mut obj: SheetObject, frame: Frame, gf: GpuFrame, ranges: List[Range] = []):
    """The object's numbers: one GPU group-by of its value column by its text column(s)."""
    var ng = groups_of(frame, obj.group)
    obj.labels = List[String]()
    for code in range(ng):
        obj.labels.append(frame.text_of(obj.group, Int64(code)))
    var key = List[Int64]()
    key.append(Int64(OP_COL))
    key.append(Int64(obj.group))
    var groups = ng
    obj.cols = List[String]()
    if obj.kind == OBJ_PIVOT and obj.across >= 0:
        var nc = groups_of(frame, obj.across)
        for code in range(nc):
            obj.cols.append(frame.text_of(obj.across, Int64(code)))
        var col_key = List[Int64]()
        col_key.append(Int64(OP_COL))
        col_key.append(Int64(obj.across))
        key = pivot_program(key, nc, col_key)
        groups = ng * nc
    var r = group_sum(frame, gf, key, value_program(frame, obj.value), ranges, groups)
    obj.sums = r.sums.copy()
    obj.counts = r.counts.copy()
    obj.milliseconds = r.milliseconds


def object_title(obj: SheetObject, frame: Frame) -> String:
    if obj.kind == OBJ_PIVOT:
        return frame.name(obj.value) + " · " + frame.name(obj.group) + (" × " + frame.name(obj.across) if obj.across >= 0 else "")
    return frame.name(obj.value) + " by " + frame.name(obj.group)


def chart_view(obj: SheetObject, frame: Frame) -> ChartView:
    """The chart, drawn by mojoui.charts: values in the column's units (money as cents when it's Currency)."""
    var scale = frame.scale(obj.value) if frame.kind(obj.value) == DECIMAL else 0
    var money = frame.format_of(obj.value).style == CURRENCY
    var values = List[Float64]()
    for s in obj.sums:  # (money: cents, whatever the column's own scale)
        values.append(Float64(s) * (10.0 ** Float64(2 - scale)) if money else Float64(s) / Float64(10 ** scale))
    var cv = ChartView(object_title(obj, frame), obj.labels.copy(), values^, frame.name(obj.value), money, obj.selected)
    if obj.style == CHART_LINE:
        cv.kind = "Line Chart"
    return cv^


def readout(obj: SheetObject, frame: Frame) -> String:
    """The picked bar or point, in the value column's format ("West · $72,061,236.00"); a hint when none is."""
    if 0 <= obj.selected < len(obj.sums) and obj.selected < len(obj.labels):
        return obj.labels[obj.selected] + " · " + frame.format_value(obj.value, Int64(obj.sums[obj.selected]), total=True)
    return "Tap a bar to read it"


def pivot_view(obj: SheetObject, frame: Frame, height: Int) -> View:
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
            cells.append(frame.format_value(obj.value, Int64(v), total=True))
        row_totals.append(frame.format_value(obj.value, Int64(row_sum), total=True))
        grand += row_sum
    var col_totals = List[String]()
    for c in range(nc):
        col_totals.append(frame.format_value(obj.value, Int64(col_sums[c]), total=True))
    var heads = obj.cols.copy() if len(obj.cols) > 0 else [frame.name(obj.value)]
    return PivotTable(rows, heads, cells, totals=True, row_totals=row_totals, col_totals=col_totals,
                      grand=frame.format_value(obj.value, Int64(grand), total=True), height=height,
                      corner=frame.name(obj.group))


def object_card(obj: SheetObject, frame: Frame, canvas: Int, version: Int, on_tap: Int, on_close: Int, on_pick: Int) -> View:
    """The object as it sits on the sheet: a title bar (its drag handle) with a close button, then the chart (on
    Canvas `canvas`) and its readout, or the pivot."""
    var head = HStack(Button(object_title(obj, frame), on_pick, style=SUBTLE), Spacer(),
                      Text(fixed(obj.milliseconds, 1) + " ms", CAPTION),
                      Button("Remove", on_close, ICON_ONLY, icon="close"), spacing=8).fill().align(CENTER).height(HEADER_H - 8)
    var body: View
    if obj.kind == OBJ_CHART:
        body = VStack(Canvas(canvas, version, on_gesture=on_tap).fill().height(obj.h - HEADER_H - 40),
                      Text(readout(obj, frame), CAPTION).tag("readout"), spacing=4).fill()
    else:
        body = pivot_view(obj, frame, obj.h - HEADER_H - 24)
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
