# mojoui.pivot: a pivot table: rows × columns of values, with optional totals and highlighted rows.
# Built from native labels in a Grid (accessible, selectable, identical on every host); the numbers come
# from the engine (a group-by); this only lays them out.
#
#   PivotTable(["Acme", "Globex"], ["Trail Pack", "Tent 2P"], cells, totals=True, highlight=[True, False])

from mojoui.view import View, Text, Grid, Scroll, CAPTION, BODY, TONE_WARN, TONE_STRONG


def PivotTable(row_labels: List[String], col_labels: List[String], cells: List[String], totals: Bool = False,
               row_totals: List[String] = [], col_totals: List[String] = [], grand: String = "",
               highlight: List[Bool] = [], height: Int = 220, corner: String = "", total_label: String = "Total") -> View:
    """cells: row-major (len(row_labels) × len(col_labels)) formatted values. totals: a Total column and a
    Total row (row_totals, col_totals, grand). highlight: rows drawn in the warning tone (e.g. near-duplicates)."""
    var n_cols = len(col_labels) + 1 + (1 if totals else 0)
    var items = List[View]()
    items.append(Text(corner, style=CAPTION))
    for c in col_labels:
        items.append(Text(c, style=CAPTION))
    if totals:
        items.append(Text("Total", style=CAPTION).tone(TONE_STRONG))
    for r in range(len(row_labels)):
        var warn = r < len(highlight) and highlight[r]
        items.append(Text(row_labels[r], style=CAPTION).tone(TONE_WARN if warn else 0))
        for c in range(len(col_labels)):
            var k = r * len(col_labels) + c
            items.append(Text(cells[k] if k < len(cells) else "—").tone(TONE_WARN if warn else 0))
        if totals:
            items.append(Text(row_totals[r] if r < len(row_totals) else "").tone(TONE_STRONG))
    if totals:
        items.append(Text(total_label, style=CAPTION).tone(TONE_STRONG))  # (e.g. "Top 8" when the rows are a top-n)
        for c in range(len(col_labels)):
            items.append(Text(col_totals[c] if c < len(col_totals) else "").tone(TONE_STRONG))
        items.append(Text(grand).tone(TONE_STRONG))
    return Scroll(Grid(items, n_cols, spacing=6).tag("pivot"), height=height).fill()
