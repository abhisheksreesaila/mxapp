# mojoui.sheetjobs: a sheet's slow work off the UI thread, on MX frame's background jobs (23edc59, F-175). A start
# function returns a `Job` the app polls once a display frame (a Canvas's on_frame) for its progress and its result, and
# can cancel. Each job works on what it owns (a snapshot of the sheet, a copy of the object): the app goes on drawing,
# scrolling and editing meanwhile. Builds without job threads (the Mac's, unless built with -D MXFRAME_JOB_THREADS) do the
# work inside the start call: the job comes back done and the app reads it on the next frame, as before.

from mxframe import Job, JobCtl, JobBody, JobProgress, start_job, JOB_RUNNING, JOB_DONE, JOB_FAILED, JOB_CANCELLED
from mojoui.sheet import Sheet
from mojoui.sheetpage import SheetObject, compute
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
