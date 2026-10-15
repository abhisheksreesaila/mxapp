"""MX frame from mojoui (framework code, called from mojoui/mxframe.mojo through Mojo's Python interop).

A mojoui Table keeps rows as eight interleaved int32 columns; this views that memory with numpy (no
copy), copies each column once into Arrow, and runs group-by sums through MX frame's native executor.
"""

import ctypes

import numpy as np
import pyarrow as pa


def frame(address, rows, names, derived):
    """An MX frame LazyFrame over a mojoui Table's memory (eight int32 columns per row), plus derived
    columns: each [name, source, divisor, cap] is min(source // divisor, cap)."""
    import mxframe as mx

    raw = (ctypes.c_int32 * (rows * 8)).from_address(int(address))
    grid = np.frombuffer(raw, dtype=np.int32).reshape(int(rows), 8)
    columns = {name: np.ascontiguousarray(grid[:, k]) for k, name in enumerate(names) if name}
    for name, source, divisor, cap in derived:
        columns[name] = np.minimum(columns[source] // int(divisor), int(cap)).astype(np.int32)
    return mx.from_arrow(pa.table({k: pa.array(v) for k, v in columns.items()}))


def group_sum(lf, by, value, groups, ranges, equals):
    """Sums of `value` and row counts per `by` group (0 … groups-1), over rows where every
    (column, low, high) in `ranges` holds and every (column, value) in `equals` matches.
    Returns [sums..., counts...] as Python ints."""
    import mxframe as mx

    cond = None
    for name, low, high in ranges:
        c = (mx.col(name) >= int(low)) & (mx.col(name) <= int(high))
        cond = c if cond is None else cond & c
    for name, v in equals:
        c = mx.col(name) == int(v)
        cond = c if cond is None else cond & c
    q = lf.filter(cond) if cond is not None else lf
    out = q.groupby(by).agg(mx.col(value).sum().alias("s"), mx.col(value).count().alias("n")).compute(device="cpu")
    sums = [0] * int(groups)
    counts = [0] * int(groups)
    for g, s, n in zip(out.column(by).to_pylist(), out.column("s").to_pylist(), out.column("n").to_pylist()):
        if 0 <= g < groups:
            sums[g] = int(round(s))
            counts[g] = int(n)
    return sums + counts
