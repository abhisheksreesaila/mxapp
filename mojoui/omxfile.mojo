# mojoui.omxfile: an omxplorer document on disk, one file `name.omx` (format 2): a Parquet file written by MX frame
# (no Python) whose columns are the table as it stands (the session's edits, added and removed rows baked in; kinds,
# decimal scales, dictionaries and empty cells are Parquet's own) and whose metadata ("omx") is JSON: each column's
# format, the formula columns (their text and format), the sheet's charts and pivots, and the Report (its tiles and
# its filter, as a column and a word). Other tools can read its columns.
#
# Format 1 (the pyarrow shim's files) is refused with a message that says so.

from mxframe import write_parquet, read_parquet, Table
from mojoui.sheet import Sheet, INT, DECIMAL, TEXT
from mojoui.json import Json, json_string
from mojoui.numformat import ColumnFormat
from mojoui.sheetpage import SheetObject, OBJ_CHART, OBJ_PIVOT
from mojoui.reportpage import ReportTile, ReportFilter, new_tile, TILE_SUM, TILE_CHART

comptime FORMAT = 2


def format_json(f: ColumnFormat) -> String:
    return ('{"style": ' + String(f.style) + ', "decimals": ' + String(f.decimals) + ', "thousands": ' + ("true" if f.thousands else "false")
            + ', "parens": ' + ("true" if f.parens else "false") + ', "symbol": ' + json_string(f.symbol) + "}")


def metadata(sheet: Sheet, objects: List[SheetObject], tiles: List[ReportTile], filter: ReportFilter) -> String:
    var stored = sheet.stored()
    var meta = String('{"omx": ' + String(FORMAT) + ', "columns": [')
    for c in range(stored):
        meta += ("," if c > 0 else "") + '{"name": ' + json_string(sheet.name(c)) + ', "format": ' + format_json(sheet.format_of(c)) + "}"
    meta += '], "formulas": ['
    for f in range(sheet.columns() - stored):
        meta += ("," if f > 0 else "") + '{"text": ' + json_string(sheet.frame.formula_text(stored + f))
        meta += ', "format": ' + format_json(sheet.format_of(stored + f)) + "}"
    meta += '], "objects": ['
    for k in range(len(objects)):
        ref o = objects[k]
        meta += ("," if k > 0 else "") + ('{"kind": ' + String(o.kind) + ', "x": ' + String(o.x) + ', "y": ' + String(o.y) + ', "w": ' + String(o.w)
                                          + ', "h": ' + String(o.h) + ', "value": ' + String(o.value) + ', "group": ' + String(o.group)
                                          + ', "across": ' + String(o.across) + ', "style": ' + String(o.style) + "}")
    meta += '], "report": {"tiles": ['
    for k in range(len(tiles)):
        meta += ("," if k > 0 else "") + '{"kind": ' + String(tiles[k].kind) + ', "col": ' + String(tiles[k].col) + ', "group": ' + String(tiles[k].group) + "}"
    meta += '], "filter": {"col": ' + String(filter.col) + ', "word": '
    meta += json_string(sheet.text_of(filter.col, Int64(filter.code)) if filter.col >= 0 else "") + "}}}"
    return meta


def save_omx(path: String, sheet: Sheet, objects: List[SheetObject] = [], tiles: List[ReportTile] = [],
             filter: ReportFilter = ReportFilter(-1, 0)) raises:
    """Writes the table as it stands (every alive row, the edits applied), the sheet's charts and pivots, and the
    Report (its tiles and filter) to `path` (.omx)."""
    write_parquet(path, sheet.frame.bake(), metadata(sheet, objects, tiles, filter))


def format_from(j: Json, node: Int) -> ColumnFormat:
    """A saved format, or Automatic if it isn't one this code can draw."""
    if node < 0:
        return ColumnFormat.auto()
    var f = ColumnFormat(j.number(j.get(node, "style")), j.number(j.get(node, "decimals"), -1), j.flag(j.get(node, "thousands"), True),
                         j.flag(j.get(node, "parens")), j.text(j.get(node, "symbol"), "$"))
    return f^ if f.valid() else ColumnFormat.auto()


def is_number(sheet: Sheet, c: Int) -> Bool:
    return 0 <= c < sheet.columns() and (sheet.kind(c) == INT or sheet.kind(c) == DECIMAL)


def is_text(sheet: Sheet, c: Int) -> Bool:
    return 0 <= c < sheet.stored() and sheet.kind(c) == TEXT


def read_meta(path: String, mut table: Table) raises -> Json:
    """The file's table (moved into `table`) and its metadata, refused unless it is a format-2 omxplorer document."""
    var r = read_parquet(path)
    table = r.take_table()
    if table.columns() == 0:
        raise Error("it has no columns")
    if r.metadata == "":
        raise Error("it isn't an omxplorer document")
    var j = Json.parse(r.metadata)
    var version = j.number(j.get(0, "omx"))
    if version == 1:
        raise Error("it was saved by an older omxplorer (format 1); open the original CSV and save it again")
    if version != FORMAT:
        raise Error("it isn't an omxplorer document")
    return j^


def open_omx(path: String, use_gpu: Bool = True) raises -> Sheet:
    """Reads `path` (.omx): the table, its formula columns and every column's format."""
    var j = Json()
    return read_document(path, j, use_gpu)


def read_document(path: String, mut j: Json, use_gpu: Bool) raises -> Sheet:
    """The table with its formulas and formats; `j` is the file's metadata (the objects and the Report are in it)."""
    var table = Table()
    try:
        j = read_meta(path, table)
    except e:
        raise Error("can't open " + path + ": " + String(e))
    var specs = j.get(0, "columns")
    if j.size(specs) != table.columns():
        raise Error("can't open " + path + ": it describes " + String(j.size(specs)) + " columns but stores " + String(table.columns()))
    for c in range(table.columns()):
        if j.text(j.get(j.at(specs, c), "name")) != table.name(c):
            raise Error("can't open " + path + ": column " + String(c + 1) + " is described as another name than it is stored under")
    var sheet = Sheet(table^.share(), use_gpu)
    for c in range(sheet.stored()):
        sheet.set_format(c, format_from(j, j.get(j.at(specs, c), "format")))
    var formulas = j.get(0, "formulas")
    for k in range(j.size(formulas)):
        var c: Int
        try:
            c = sheet.formula(j.text(j.get(j.at(formulas, k), "text")))
        except e:
            raise Error("can't open " + path + ": a formula column can't be rebuilt: " + String(e))
        sheet.set_format(c, format_from(j, j.get(j.at(formulas, k), "format")))
    return sheet^


def open_document(path: String, mut objects: List[SheetObject], mut tiles: List[ReportTile], mut filter: ReportFilter) raises -> Sheet:
    """Reads `path` (.omx): returns the table and fills in the sheet's objects and the Report. An object or tile
    that names a column the table doesn't have (or a kind this code doesn't know) is left out rather than trusted."""
    var j = Json()
    var sheet = read_document(path, j, True)
    objects = List[SheetObject]()
    var specs = j.get(0, "objects")
    for k in range(j.size(specs)):
        var o = j.at(specs, k)
        var kind = j.number(j.get(o, "kind"))
        var value = j.number(j.get(o, "value"), -1)
        var group = j.number(j.get(o, "group"), -1)
        var across = j.number(j.get(o, "across"), -1)
        if (kind != OBJ_CHART and kind != OBJ_PIVOT) or not is_number(sheet, value) or not is_text(sheet, group) or not (across == -1 or is_text(sheet, across)):
            continue
        var obj = SheetObject.chart(value, group, j.number(j.get(o, "x")), j.number(j.get(o, "y")), j.number(j.get(o, "w"), 520), j.number(j.get(o, "h"), 340))
        obj.kind = kind
        obj.across = across
        obj.style = j.number(j.get(o, "style"))
        objects.append(obj^)
    tiles = List[ReportTile]()
    var report = j.get(0, "report")
    var tile_specs = j.get(report, "tiles")
    for k in range(j.size(tile_specs)):
        var t = j.at(tile_specs, k)
        var kind = j.number(j.get(t, "kind"), -1)
        var col = j.number(j.get(t, "col"), -1)
        var group = j.number(j.get(t, "group"), -1)
        if not (TILE_SUM <= kind <= TILE_CHART) or not is_number(sheet, col) or (kind == TILE_CHART and not is_text(sheet, group)):
            continue
        tiles.append(new_tile(kind, col, group))
    var f = j.get(report, "filter")
    var fcol = j.number(j.get(f, "col"), -1)
    filter = ReportFilter(-1, 0)
    if is_text(sheet, fcol):
        var code = sheet.code_of(fcol, j.text(j.get(f, "word")))
        if code >= 0:
            filter = ReportFilter(fcol, code)
    return sheet^
