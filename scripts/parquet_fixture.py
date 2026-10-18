"""Parquet files for goal 20's checks, written by pyarrow (an independent writer, so the app's reader is tested on files
it didn't write). Both have the same columns: order (int64), amount (decimal(12,2), ~5% empty), region (text, ~3%
empty), day (date), paid (bool).

  pixi run python scripts/parquet_fixture.py small build/g20/small.parquet          # 5,000 rows, one row group
  pixi run python scripts/parquet_fixture.py big build/g20/big.parquet 100000000    # numpy, row groups of 2^20 rows
"""

import datetime
import decimal
import random
import sys

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq

REGIONS = ["North", "South", "East", "West", "Central"]


def small(path, n=5000):
    rnd = random.Random(20)
    t = pa.table({
        "order": pa.array(range(1, n + 1), pa.int64()),
        "amount": pa.array([None if rnd.random() < 0.05 else decimal.Decimal(rnd.randint(100, 999999)) / 100 for _ in range(n)], pa.decimal128(12, 2)),
        "region": pa.array([None if rnd.random() < 0.03 else rnd.choice(REGIONS) for _ in range(n)], pa.string()),
        "day": pa.array([datetime.date(2025, 1, 1) + datetime.timedelta(days=rnd.randint(0, 364)) for _ in range(n)], pa.date32()),
        "paid": pa.array([rnd.random() < 0.7 for _ in range(n)], pa.bool_()),
    })
    pq.write_table(t, path)


def big(path, n, group=1 << 20):
    rng = np.random.default_rng(20)
    schema = pa.schema([("order", pa.int64()), ("amount", pa.decimal128(12, 2)), ("region", pa.string()),
                        ("day", pa.date32()), ("paid", pa.bool_())])
    words = pa.array(REGIONS, pa.string())
    with pq.ParquetWriter(path, schema, store_decimal_as_integer=True) as w:
        for lo in range(0, n, group):
            k = min(group, n - lo)
            cents = rng.integers(100, 1_000_000, k)
            words16 = np.zeros((k, 2), dtype=np.int64)  # (decimal128: the unscaled value, little-endian, high word 0)
            words16[:, 0] = cents
            valid = np.packbits(rng.random(k) >= 0.05, bitorder="little")
            amount = pa.Array.from_buffers(pa.decimal128(12, 2), k, [pa.py_buffer(valid), pa.py_buffer(words16)])
            codes = pa.array(rng.integers(0, len(REGIONS), k).astype(np.int32), mask=rng.random(k) < 0.03)
            region = pa.DictionaryArray.from_arrays(codes, words).cast(pa.string())
            day = pa.array((rng.integers(0, 365, k) + 20089).astype(np.int32), pa.int32()).cast(pa.date32())
            t = pa.table([pa.array(np.arange(lo + 1, lo + k + 1, dtype=np.int64)), amount, region, day,
                          pa.array(rng.random(k) < 0.7)], schema=schema)
            w.write_table(t, row_group_size=group)


if __name__ == "__main__":
    if sys.argv[1] == "small":
        small(sys.argv[2])
    else:
        big(sys.argv[2], int(sys.argv[3]))
