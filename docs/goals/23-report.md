# Goal 23 report: the GPU for streamed files (MX frame 1889b7f)

**End goal (owner, 2026-10-18):** "please continue with tickets that depends on mxframe - and proceed on autopilot." MX frame 1889b7f (F-146) runs queries over a streamed file on the GPU. The owner also settled text order: case ignored, bytes breaking ties.

## Result

M1–M3 PASS. Reviewer: PASS, and its should-fixes are done (D-224).

```
PASS  M1  vendored from 1889b7f; streamed sheets ask for AUTO; the GPU's totals, chart and pivot over a streamed file with edits equal the CPU's (test_streamed); 100M rows: total: CPU 217 ms, GPU 351 ms, AUTO 206 ms on the CPU; group-by: CPU 328 ms, GPU 433 ms, AUTO 346 ms on the CPU
PASS  M2  a text column sorts Apple, apple, Banana, banana, cherry, Zebra (and back), in memory and streamed, in the app and the engine
PASS  M3  goal 22's M1–M4 (goals 3–21 inside them) pass; needs-mxframe.md is current  (2221 s)
```

## What changed

- **Streamed sheets let the engine choose the device (AUTO).** Before, they always used the CPU.
  - On the GPU, totals, charts and pivots over a streamed file, edits included, are identical to the CPU's.
  - On this 12-core machine the CPU is faster, so AUTO keeps it. For 100M rows: a total takes 0.21 s on the CPU and 0.39 s on the GPU, and a group-by 0.34 s and 0.44 s.
  - The engine picks the GPU when a plan's work per row is more than 3 × the columns it reads × the cores. A plain total does that on 2 cores; this app's group-by stays on the CPU even there.
  - The status bar and the chart message name the device that ran.
- **Text sorts ignore case**, with bytes breaking ties: Apple, apple, Banana, banana, cherry, Zebra. Tests pin this order in memory and streamed, through the app and the engine.

## Three decisions worth a second look

- **D-221: AUTO, not "always the GPU".** On this machine the GPU is slower for streamed files, because moving the file to it costs more than it saves.
- **D-222: cached totals of a streamed column are keyed by device too.** A test that switched to the GPU caught a stale CPU answer.
- **D-223: charts and pivots keep the file's word order.** Only sorting uses the new order.

## Next

MX frame's M8, SQL and joins (F-150 onwards), which opens Query mode, Explore mode and a second table. I'll plan that when its first pieces are vendorable.
