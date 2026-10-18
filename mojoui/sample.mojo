# mojoui.sample: the sample orders (mojoui.orders, made for the stand-in engine) as an MX frame table.

from mxframe import Table, ColumnKind
from mojoui.frame import Columns
from mojoui.orders import order_columns


def to_table(cols: Columns) raises -> Table:
    """The stand-in's columns as a package table: kinds and scales as they are, text columns with the same codes."""
    var t = Table.empty()
    for c in range(len(cols.cols)):
        ref src = cols.cols[c]
        var at = t.add_column(src.name, ColumnKind(src.kind), src.scale if src.kind == 1 else 0)
        for w in src.dictionary:
            _ = t.add_word(at, w)
        for v in src.values:
            t.append(at, v)
    return t^


def sample_table(rows: Int) raises -> Table:
    return to_table(order_columns(rows))
