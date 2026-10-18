# mojoui.csvio: a CSV file → MX frame's typed columns, for "open your data".
#
# MX frame's own reader (`mxframe.read_csv`, no Python): memory-mapped, parsed in parallel, types inferred from the
# first rows. Types: integers → INT; decimals → DECIMAL (2 places if every value has at most 2, else 4); ISO dates
# and times → DATE; true/false → BOOL; anything else → TEXT (a dictionary). An empty cell is a null.

from mxframe import read_csv as mx_read_csv, CsvOptions, CsvResult, Table, SharedTable, ColumnKind
from mojoui.sheet import INT, DECIMAL, TEXT, DATE, BOOL


@fieldwise_init
struct CsvColumn(Copyable, Movable):
    """What the Import step shows about one column."""

    var name: String
    var kind: Int  # INT, DECIMAL, TEXT, DATE, BOOL
    var scale: Int
    var empty: Int  # empty cells (nulls)
    var distinct: Int  # TEXT: values in its dictionary (0 for numbers)
    var sample: List[String]  # the first rows, as written in the file
    var failed: Int  # cells that didn't fit the column's type (now empty)


@fieldwise_init
struct CsvImport(Movable):
    var path: String
    var rows: Int
    var columns: List[CsvColumn]
    var skipped: List[String]  # columns past the limit (none: the limit is 4,096)
    var seconds: Float64  # read + parse
    var table: SharedTable  # the columns; the app builds its Sheet from it, then lets go (let_go)
    var parse_seconds: Float64

    def let_go(mut self) raises:
        """Drops this import's hold on the table, so a replaced document's memory is freed."""
        self.table = SharedTable(Table.empty())


def kind_name(kind: Int) -> String:
    if kind == INT:
        return "Integer"
    if kind == DECIMAL:
        return "Decimal"
    if kind == DATE:
        return "Date"
    if kind == BOOL:
        return "Yes/No"
    return "Text"


def empty_import() -> CsvImport:
    return CsvImport("", 0, List[CsvColumn](), List[String](), 0, SharedTable(Table.empty()), 0)


def read_csv(path: String) raises -> CsvImport:
    """Reads the file into shared columns. Raises with a readable message if it isn't a table."""
    var r: CsvResult
    try:
        r = mx_read_csv(path, CsvOptions())
    except e:
        raise Error("couldn't read " + path + " as CSV: " + String(e))
    var info = List[CsvColumn]()
    for c in r.columns:
        info.append(CsvColumn(c.name, c.kind.value, c.scale, c.empty, c.distinct, c.sample.copy(), c.failed_count))
    var skipped = r.skipped.copy()
    var table = Table()
    swap(table, r.table)  # (r.table^ can't be moved out while the rest of r is still read)
    return CsvImport(path, r.rows, info^, skipped^, r.seconds, table^.share(), r.seconds)
