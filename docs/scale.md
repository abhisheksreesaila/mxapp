# omxplorer at scale: 1M → 100M rows (2026-10-17, measured)

The same orders ledger written as a CSV at each size (`tools/orders_csv.mojo`), opened the way omxplorer opens it and
timed by `tools/scale.mojo`. The engine is the same code the app runs, without a window.

| Rows | Import (CSV → table) | Sort 1 column | Format change (redraw) | GPU sum, every row | GPU upload | First screen drawn | CSV size |
|---|---|---|---|---|---|---|---|
| 1M | 0.71 s | 0.02 s | 8.3 ms | 0.3 ms | 0.41 s | 8.3 ms | 96 MB |
| 10M | 3.17 s | 0.22 s | 8.3 ms | 2.2 ms | 1.24 s | 8.1 ms | 0.97 GB |
| 50M | 42.46 s | 1.69 s | 28.8 ms | 9.9 ms | 6.38 s | 8.5 ms | 4.9 GB |
| 100M | 106.30 s | 3.68 s | 54.2 ms | 18.9 ms | 12.25 s | 8.4 ms | 9.8 GB |

GPU: NVIDIA GeForce RTX 3090. Peak memory at 100M: 26 GB.

## What it means
- **Everything after the import keeps up at 100M rows.** Sorting takes under 4 s. A format change redraws in about 50 ms. A sum over every row takes 19 ms on the GPU. Drawing the first screen takes 8 ms at any size, because only what's on screen is read.
- **The import is the slow part above 10M.** At 50M and 100M, more than 90% of it is pyarrow parsing and typing the text, the stand-in until MX frame's readers land. It grows faster than the row count because this machine was short of memory: the owner's other projects had 32 GB of swap in use and a load of 9–12 during these runs. On a quiet machine, the 10M rate (3 s) projects to about 15 s at 50M and about 30 s at 100M. That projection is not measured.
- **The 1M budget is met.** Import takes 0.7 s (budget 5 s), sort 0.02 s (budget 1 s), and a format change 8 ms (budget 50 ms).

## What changed to get here (D-136)
- **Dropped the custom date formats.** Parsing them doubled the read time at 50M rows. ISO dates are still found.
- **Money columns convert through Arrow's kernels.** Before, numpy made six whole-column temporaries per column.
- **Columns are handed over one at a time.** Each is copied into the engine, then let go, so the import never holds every column twice. That kept 100M at a 26 GB peak.

## Next for scale (logged in docs/plans/needs-mxframe.md)
- **MX frame's own CSV and Parquet readers** replace the pyarrow stand-in. They're streaming and typed in Mojo, so there's no copy through Python.
- **Opening a saved `.omx` (Parquet) skips CSV parsing entirely.** It's the fast path at 100M rows today.
- **The GPU upload converts to int32 row by row** (12 s at 100M). A column-wise upload is the obvious next step.
