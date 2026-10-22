# mojoui.sheetjobs: a sheet's slow work off the UI thread, on MX frame's background jobs (23edc59, F-175). A start
# function returns a `Job` the app polls once a display frame (a Canvas's on_frame) for its progress and its result, and
# can cancel. Each job works on what it owns (a snapshot of the sheet, a copy of the object): the app goes on drawing,
# scrolling and editing meanwhile. Builds without job threads (the Mac's, unless built with -D MXFRAME_JOB_THREADS) do the
# work inside the start call: the job comes back done and the app reads it on the next frame, as before.

from mxframe import Job, JobCtl, JobBody, JobProgress, start_job, JOB_RUNNING, JOB_DONE, JOB_FAILED, JOB_CANCELLED
from mojoui.sheet import Sheet
from mojoui.sheetpage import SheetObject, compute, shape_of
from mojoui.csvio import CsvImport, read_table, empty_import
from mojoui.sheet import placeholder_sheet
from mojoui.clock import now_ns


struct ChartJob(JobBody):
    comptime Out = SheetObject
    var sheet: Sheet
    var obj: SheetObject

    def __init__(out self, var sheet: Sheet, var obj: SheetObject):
        self.sheet = sheet^
        self.obj = obj^

    def run(mut self, ctl: JobCtl) raises -> SheetObject:
        ctl.add_total(1)
        ctl.check()
        var t0 = now_ns()
        compute(self.obj, self.sheet)
        self.obj.milliseconds = Float64(now_ns() - t0) / 1e6  # (the whole compute, as the person waited for it)
        ctl.advance(1)
        return self.obj.copy()


def chart_job(sheet: Sheet, obj: SheetObject) -> Job[SheetObject]:
    """A chart's (or pivot's) numbers off the caller's thread, over the sheet as it is now."""
    return start_job(ChartJob(sheet.snapshot(), obj.copy()))


def take_numbers(mut obj: SheetObject, done: SheetObject):
    """A finished job's numbers into the object on screen (its place, size, picked bar and move stay as they are now)."""
    obj.labels = done.labels.copy()
    obj.cols = done.cols.copy()
    obj.sums = done.sums.copy()
    obj.counts = done.counts.copy()
    obj.present = done.present.copy()
    obj.values = done.values.copy()
    obj.stats = done.stats.copy()
    obj.has_stat = done.has_stat.copy()
    obj.milliseconds = done.milliseconds
    obj.selected = done.selected


def progress_share(p: JobProgress) -> Float64:
    """How far along, 0–1 (0 before the work knows how big it is)."""
    if p.total <= 0:
        return 0.0
    return min(Float64(p.done) / Float64(p.total), 1.0)


struct ChartQueue(Movable):
    """Charts waiting for their numbers: one job runs at a time (the GPU does one query well, not three at once), the
    newest spec per chart waits behind it, and a newer spec for the chart that's running cancels it (only the newest
    lands). The app polls it once a frame."""

    var job: Optional[Job[SheetObject]]
    var cref: Int  # the chart the running job is for (-1: none)
    var spec: SheetObject  # what it asked (its words, for the island)
    var started: Int  # ns
    var waiting: List[Tuple[Int, SheetObject]]

    def __init__(out self):
        self.job = None
        self.cref = -1
        self.spec = SheetObject.chart(0, 0, 0, 0)
        self.started = 0
        self.waiting = List[Tuple[Int, SheetObject]]()

    def busy(self) -> Bool:
        return self.cref >= 0

    def ask(mut self, cref: Int, spec: SheetObject, sheet: Sheet):
        """Chart `cref`'s numbers for `spec`: started now if nothing runs, else queued (replacing what that chart had
        queued); a job already running for `cref` is cancelled."""
        var kept = List[Tuple[Int, SheetObject]]()
        for w in self.waiting:
            if w[0] != cref:
                kept.append(w.copy())
        self.waiting = kept^
        if self.cref == cref:
            self.cancel_running()
        if self.cref < 0:
            self.start(cref, spec, sheet)
        else:
            self.waiting.append((cref, spec.copy()))

    def start(mut self, cref: Int, spec: SheetObject, sheet: Sheet):
        self.job = chart_job(sheet, spec)
        self.cref = cref
        self.spec = spec.copy()
        self.started = now_ns()

    def cancel_running(mut self):
        if self.job:
            self.job.value().cancel()
        self.job = None  # (dropping the handle lets its thread finish on its own and free what it owns)
        self.cref = -1

    def forget(mut self):
        """Every job and wait dropped (the document closed, or the objects' refs moved)."""
        self.cancel_running()
        self.waiting = List[Tuple[Int, SheetObject]]()

    def share(self) -> Float64:
        """How far the running job is, 0–1."""
        if not self.job:
            return 0.0
        return progress_share(self.job.value().progress())

    def seconds(self) -> Float64:
        """How long the running job has run."""
        return Float64(now_ns() - self.started) / 1e9 if self.cref >= 0 else 0.0

    def poll(mut self, sheet: Sheet) raises -> Optional[Tuple[Int, SheetObject]]:
        """A chart whose numbers have landed (its cref and the computed object), or None; the next waiting job starts.
        Raises the job's error (the queue moves on regardless)."""
        if self.cref < 0 or not self.job:
            return None
        var state = self.job.value().poll()
        if state == JOB_RUNNING:
            return None
        var cref = self.cref
        var job = self.job.take()
        self.cref = -1
        self.next(sheet)
        if state != JOB_DONE:
            if state == JOB_CANCELLED:
                return None
            _ = job.result()  # (raises the job's error)
            return None
        return (cref, job.result())

    def next(mut self, sheet: Sheet):
        if len(self.waiting) > 0 and self.cref < 0:
            var w = self.waiting.pop(0)
            self.start(w[0], w[1], sheet)


@fieldwise_init
struct ColumnFigures(Copyable, Movable):
    """A number column's figures for the status bar and the inspector: its total and how many values (empties aren't
    averaged), its median (stored units, one place finer; `has_median`), how many distinct values; what it cost."""

    var col: Int
    var sum: Int
    var present: Int
    var median: Int
    var has_median: Bool
    var distinct: Int
    var milliseconds: Float64
    var on_gpu: Bool


struct ColumnJob(JobBody):
    comptime Out = ColumnFigures
    var sheet: Sheet
    var col: Int
    var stats: Bool  # the median and the distinct count too (the inspector is open)

    def __init__(out self, var sheet: Sheet, col: Int, stats: Bool):
        self.sheet = sheet^
        self.col = col
        self.stats = stats

    def run(mut self, ctl: JobCtl) raises -> ColumnFigures:
        ctl.add_total(3 if self.stats else 1)
        var t0 = now_ns()
        var r = self.sheet.totals(self.col)
        ctl.advance(1)
        var med = (0, False)
        var distinct = -1
        if self.stats and not self.sheet.streamed():  # (a streamed file's median and distinct read every row group: they wait for a tile)
            ctl.check()
            var m = self.sheet.median(self.col)
            med = (Int(m[0]), m[1])
            ctl.advance(1)
            ctl.check()
            distinct = self.sheet.distinct(self.col)
            ctl.advance(1)
        return ColumnFigures(self.col, r.sums[0], r.present[0], med[0], med[1], distinct, Float64(now_ns() - t0) / 1e6, r.on_gpu)


def column_job(sheet: Sheet, col: Int, stats: Bool) -> Job[ColumnFigures]:
    """Column `col`'s total (and, with `stats`, its median and distinct count) off the caller's thread."""
    return start_job(ColumnJob(sheet.snapshot(), col, stats))


struct Opened(Movable):
    """What an open job made: the import (what the Import step shows), the sheet over its table (its GPU copy made),
    and each column's distribution for the headers' histograms (none for a streamed file: they read every row)."""

    var imp: CsvImport
    var sheet: Sheet
    var shapes: List[List[Float64]]
    var milliseconds: Float64

    def __init__(out self, var imp: CsvImport, var sheet: Sheet, var shapes: List[List[Float64]], milliseconds: Float64):
        self.imp = imp^
        self.sheet = sheet^
        self.shapes = shapes^
        self.milliseconds = milliseconds

    def take_import(mut self) -> CsvImport:
        var out = self.imp^
        self.imp = empty_import()
        return out^

    def take_sheet(mut self) -> Sheet:
        var out = self.sheet^
        self.sheet = placeholder_sheet()
        return out^

    def take_shapes(mut self) -> List[List[Float64]]:
        var out = self.shapes^
        self.shapes = List[List[Float64]]()
        return out^


struct OpenJob(JobBody):
    comptime Out = Opened
    var path: String

    def __init__(out self, var path: String):
        self.path = path^

    def run(mut self, ctl: JobCtl) raises -> Opened:
        var t0 = now_ns()
        var imp = read_table(self.path, ctl)
        ctl.check()
        var sheet = Sheet(imp.scan.value()) if imp.streamed() else Sheet(imp.table)
        imp.let_go()  # (the sheet holds the table now; the import keeps only what it showed)
        var shapes = List[List[Float64]]()
        if not sheet.streamed():
            for c in range(sheet.stored()):
                ctl.check()
                try:
                    shapes.append(shape_of(sheet, c))
                except:
                    shapes.append(List[Float64]())
        return Opened(imp^, sheet^, shapes^, Float64(now_ns() - t0) / 1e6)


def open_job(path: String) -> Job[Opened]:
    """Reads a CSV or Parquet file (as the Import step shows it) into a sheet, off the caller's thread."""
    return start_job(OpenJob(path))
