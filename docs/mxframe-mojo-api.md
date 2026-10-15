# MX frame: the Mojo-level API mojo-ui needs

**For:** the MX frame project (the owner's). **From:** the analytics showcase (`examples/analytics/app.mojo`, goal 8).
**Why:** today the dashboard reaches MX frame through Python (`mojoui/mxframe.mojo` → `mojoui/mxframe_bridge.py` → `mxframe` → `libmxexec_cpu.so`). That works on Linux and the web, but the Mac, iPhone and Android builds can't embed Python. A Mojo-level API removes Python from the path, so the same dashboard runs natively on every platform, and lets MX frame share GPU memory with the app.

## What the app does today (the real call sites)

Each time a filter changes, the dashboard runs **seven group-by sums over the same 20M rows** (`compute()` and `mx_sum()` in `examples/analytics/app.mojo`):

| Chart | Group by | Sum | Filters (crossfiltering: each chart skips its own) |
|---|---|---|---|
| Revenue by month | `month` (36) | `cents` | day range, channel, category, region |
| Revenue by category | `category` (8) | `cents` | day range, channel, region, month |
| Revenue by region | `region` (5) | `cents` | day range, channel, category, month |
| Top products | `product` (64) | `cents` | all |
| Orders by size | `bin` = min(cents // 5000, 23) | count | all |
| Year-on-year KPIs | `year` = month // 12 | `cents`, `quantity` | all but the day range |

All columns are int32; sums must be **exact** (64-bit integers: the dashboard compares engines to the cent). Measured on 20M rows:

| Engine | 7 aggregations |
|---|---|
| mojoui's GPU kernels (`mojoui/gpu.mojo`, `Table.group_sum`) | 5.9 ms |
| MX frame through Python (planning + native CPU executor) | 114 ms |
| Plain Mojo loops, one CPU core | 746 ms |

## The API we need

A Mojo package (`.mojopkg`) with no Python and no libpython dependency. A sketch in Mojo (names are suggestions; shape matters more):

```mojo
from mxframe import Frame, Column, col, sum, count, CPU, GPU

# 1. Borrow columns the app already has: no copies.
var frame = Frame([
    Column.int32("day", ptr, rows, stride=8),        # strided views over row-major memory are fine,
    Column.int32("category", ptr + 1, rows, stride=8),  # or contiguous buffers
    ...
])
# or, on the GPU: columns already in device memory (shared DeviceContext, uploaded once by the app)
var gframe = Frame.on_device(ctx, [Column.int32_device("day", device_buffer, rows), ...])

# 2. Derived columns: integer expressions
frame = frame.with_column("bin", (col("cents") // 5000).min(23))

# 3. Queries: filter, group by one key, several aggregates
var q = (frame.filter((col("day") >= 365) & (col("day") <= 730) & (col("channel") == 0))
              .group_by("region", groups=5)            # small dense keys: a known group count helps
              .agg(sum("cents").alias("revenue"), count().alias("orders")))
var result = q.compute(device=GPU)                     # or CPU; raises on errors

# 4. Results as typed columns the app reads directly
var revenue = result.int64("revenue")                  # List-like / Span[Int64], index = group key
```

### Must have (the dashboard needs these)
1. **Borrowed columns:** int32/int64/float64 views over the caller's memory (pointer, length, optional stride), owned by the caller; no copy on the CPU path.
2. **Filters:** integer comparisons (`>=`, `<=`, `==`), `&`; ideally `is_in` for multi-select.
3. **Group by one integer key** with a known small group count (dense output: index = key; missing groups = 0).
4. **Aggregates:** `sum` (exact 64-bit for integer inputs), `count`; later `mean`, `min`, `max`.
5. **Derived integer columns:** `//`, `min`, `max`, `+`, `*` on columns and constants.
6. **Devices:** `compute(device=CPU)` with the native executor, and `compute(device=GPU)` on a **DeviceContext shared with the app**, so data the app uploaded once (`mojoui.gpu.Table`) is reused, not copied again.
7. **Errors:** `raises` with a readable message (unknown column, type mismatch).

### Should have (makes it fast)
8. **Batched queries:** run several group-bys over the same filtered base in one pass (`compute_many([q1, q2, …])`). The dashboard's seven queries share most of their filters, so a fused pass is several times cheaper.
9. **Plan reuse:** compile a query shape once, rerun it with new filter constants (`q.bind(day_low=365, …)`), so a slider drag doesn't replan.
10. **Arrow C Data Interface** import/export (`ArrowArray` / `ArrowSchema` pointers), so Parquet files (MX frame's `read_parquet`) and other engines hand over columns zero-copy.

### Later
11. String/dictionary keys (category names), date/time bucketing (`month(day)`), top-k (`sort` + `limit`), joins (TPC-H-style dashboards).
12. Apple GPUs (Metal) once MAX's Apple support can run inside a Mojo app without Python.

## Memory rules
- The app owns borrowed columns; they must outlive the `Frame` (the app keeps them for its life).
- `Result` owns its buffers and frees them when dropped.
- Device columns belong to the app's `DeviceContext`; MX frame never frees them.

## Done means
`mojoui/mxframe.mojo` swaps `std.python` for `from mxframe import …`, keeps its `MxFrame.group_sum(by, value, groups, ranges, equals)` signature, and the dashboard's "MX frame" engine then builds for the Mac (`scripts/build.sh analytics mac`) with only Apple system functions, matching the GPU totals exactly (the check in `scripts/check` M6).
