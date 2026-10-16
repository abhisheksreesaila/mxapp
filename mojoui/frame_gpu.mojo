# mojoui.frame_gpu: the shared columns on the GPU, and group-bys whose key, value and filters are
# chosen at run time (bytecode from mojoui.frame), so pivots and formula columns need no recompiling.
#
#   var gf = GpuFrame(addr)                      # once per process: uploads the shared columns (int32)
#   var r = group_sum(frame, gf, key, value, ranges, groups)
#
# The GPU aggregates the shared rows; the session's edits (a sparse overlay) are applied as exact
# deltas on the CPU afterwards: O(edits) per query, no copy of the data per session.

from std.atomic import Atomic, Ordering
from std.memory import Pointer, stack_allocation
from std.math import ceildiv
from max.gpu import global_idx, grid_dim, block_dim, thread_idx, barrier
from max.gpu.host import DeviceContext, DeviceBuffer
from max.gpu.memory import AddressSpace
from mojoui.gpu import Gpu, GPU_BUILD, SHARED_GROUPS, GroupSums
from mojoui.frame import Columns, Frame, Range, Row, MAX_COLS, MAX_DEPTH, eval_program, base_at
from mojoui.clock import now_ns

comptime MAX_FILTERS = 8


@always_inline
def _eval_direct(prog: UnsafePointer[Int64, MutAnyOrigin], n: Int, rows: UnsafePointer[Int32, MutAnyOrigin], at: Int) -> Int64:
    """eval_program for the GPU: columns read straight from the row (no row vector), the stack in
    four registers (no local memory). Programs deeper than four are refused by the compiler."""
    var s0: Int64 = 0
    var s1: Int64 = 0
    var s2: Int64 = 0
    var s3: Int64 = 0
    var sp = 0
    for k in range(n):
        var op = prog[unsafe_offset=2 * k]
        var arg = prog[unsafe_offset=2 * k + 1]
        if op <= 1:  # push
            var v = arg if op == 0 else Int64(rows[unsafe_offset=at + Int(arg)])
            if sp == 0:
                s0 = v
            elif sp == 1:
                s1 = v
            elif sp == 2:
                s2 = v
            else:
                s3 = v
            sp += 1
        else:
            var top = s3 if sp == 4 else (s2 if sp == 3 else (s1 if sp == 2 else s0))
            if op == 10:  # scale
                top *= arg
            elif op == 11:  # unscale
                top //= arg
            elif op == 12:  # negate
                top = -top
            else:
                sp -= 1
                var a = s2 if sp == 3 else (s1 if sp == 2 else (s0 if sp == 1 else 0))
                var b = top
                if op == 2:
                    top = a + b
                elif op == 3:
                    top = a - b
                elif op == 4:
                    top = a * b
                elif op == 5 or op == 8:
                    top = a // b if b != 0 else 0
                elif op == 9:
                    top = a % b if b != 0 else 0
                elif op == 6:
                    top = a if a < b else b
                else:
                    top = a if a > b else b
            if sp == 1:
                s0 = top
            elif sp == 2:
                s1 = top
            elif sp == 3:
                s2 = top
            else:
                s3 = top
    return s0


def _frame_kernel(
    rows: UnsafePointer[Int32, MutAnyOrigin], n: Int32, stride: Int32,
    prog: UnsafePointer[Int64, MutAnyOrigin], nkey: Int32, nvalue: Int32,
    filters: UnsafePointer[Int64, MutAnyOrigin], nfilters: Int32,
    acc: UnsafePointer[UInt64, MutAnyOrigin], groups: Int32,
):
    var local = stack_allocation[2 * SHARED_GROUPS, UInt64, address_space=AddressSpace.SHARED]()
    var shared = Int(groups) <= SHARED_GROUPS
    var t = Int(thread_idx.x)
    var k = t
    while k < 2 * SHARED_GROUPS:
        local[k] = 0
        k += Int(block_dim.x)
    barrier()
    var value = prog + 2 * Int(nkey)
    var stride_n = Int(grid_dim.x) * Int(block_dim.x)
    var i = Int(global_idx.x)
    while i < Int(n):
        var at = Int(stride) * i
        var keep = True
        for f in range(Int(nfilters)):
            var v = Int64(rows[unsafe_offset=at + Int(filters[unsafe_offset=3 * f])])
            if v < filters[unsafe_offset=3 * f + 1] or v > filters[unsafe_offset=3 * f + 2]:
                keep = False
        if keep:
            var grp = Int(_eval_direct(prog, Int(nkey), rows, at))
            if grp >= 0 and grp < Int(groups):
                var amount = UInt64(_eval_direct(value, Int(nvalue), rows, at))  # two's complement: negatives add up right
                if shared:
                    _ = Atomic.fetch_add[ordering=Ordering.RELAXED](local + 2 * grp, amount)
                    _ = Atomic.fetch_add[ordering=Ordering.RELAXED](local + (2 * grp + 1), UInt64(1))
                else:
                    _ = Atomic.fetch_add[ordering=Ordering.RELAXED](acc.unsafe_offset(2 * grp), amount)
                    _ = Atomic.fetch_add[ordering=Ordering.RELAXED](acc.unsafe_offset(2 * grp + 1), UInt64(1))
        i += stride_n
    barrier()
    if shared:
        k = t
        while k < 2 * Int(groups):
            if local[k] != 0:
                _ = Atomic.fetch_add[ordering=Ordering.RELAXED](acc.unsafe_offset(k), local[k])
            k += Int(block_dim.x)


def signed(u: UInt64) -> Int:
    return Int(u.cast[DType.int64]())


struct GpuFrame(Movable):
    """The shared columns as int32, row-major, on the GPU (uploaded once per process). Read-only."""

    var gpu: Gpu
    var base_addr: Int
    var rows: Int
    var stride: Int  # stored columns per row
    var device: Optional[DeviceBuffer[DType.int32]]
    var uploads: Int

    def __init__(out self, base_addr: Int, use_gpu: Bool = True):
        self.gpu = Gpu(use_gpu)
        self.base_addr = base_addr
        ref base = base_at(base_addr)[]
        self.rows = base.rows
        self.stride = len(base.cols)
        self.device = None
        self.uploads = 0
        comptime if GPU_BUILD:
            if self.gpu.available() and self.rows > 0 and self.stride <= MAX_COLS:
                try:
                    var host = List[Int32](length=self.stride * self.rows, fill=0)
                    for c in range(self.stride):
                        ref values = base.cols[c].values
                        for i in range(self.rows):
                            host[self.stride * i + c] = Int32(values[i])
                    ref ctx = self.gpu.ctx.value()
                    var buf = ctx.enqueue_create_buffer[DType.int32](self.stride * self.rows)
                    ctx.enqueue_copy(dst_buf=buf, src_ptr=host.unsafe_ptr())
                    ctx.synchronize()
                    self.device = buf^
                    self.uploads += 1
                except e:
                    print("mojoui.frame_gpu: couldn't upload the columns (" + String(e) + "); using the CPU")
                    self.device = None

    def on_gpu(self) -> Bool:
        return Bool(self.device)

    def device_name(self) -> String:
        return self.gpu.name if self.on_gpu() else String("CPU")

    def base_sums(self, key: List[Int64], value: List[Int64], ranges: List[Range], groups: Int, use_gpu: Bool = True) -> GroupSums:
        """Per-group sums and counts over the shared rows only (no session edits)."""
        var t0 = now_ns()
        var sums = List[Int](length=groups, fill=0)
        var counts = List[Int](length=groups, fill=0)
        comptime if GPU_BUILD:
            if self.on_gpu() and use_gpu and len(ranges) <= MAX_FILTERS:
                try:
                    ref ctx = self.gpu.ctx.value()
                    var prog = List[Int64]()
                    for v in key:
                        prog.append(v)
                    for v in value:
                        prog.append(v)
                    var flt = List[Int64]()
                    for g in ranges:
                        flt.append(Int64(g.col))
                        flt.append(g.lo)
                        flt.append(g.hi)
                    if len(flt) == 0:
                        flt.append(0)
                    var dprog = ctx.enqueue_create_buffer[DType.int64](len(prog))
                    ctx.enqueue_copy(dst_buf=dprog, src_ptr=prog.unsafe_ptr())
                    var dflt = ctx.enqueue_create_buffer[DType.int64](len(flt))
                    ctx.enqueue_copy(dst_buf=dflt, src_ptr=flt.unsafe_ptr())
                    var acc = ctx.enqueue_create_buffer[DType.uint64](2 * groups)
                    ctx.enqueue_memset(acc, 0)
                    ctx.enqueue_function[_frame_kernel](
                        self.device.value().unsafe_ptr(), Int32(self.rows), Int32(self.stride),
                        dprog.unsafe_ptr(), Int32(len(key) // 2), Int32(len(value) // 2),
                        dflt.unsafe_ptr(), Int32(len(ranges)),
                        acc.unsafe_ptr(), Int32(groups),
                        grid_dim=min(ceildiv(self.rows, 256), 4096), block_dim=256,
                    )
                    var out = List[UInt64](length=2 * groups, fill=0)
                    ctx.enqueue_copy(dst_ptr=out.unsafe_ptr(), src_buf=acc)
                    ctx.synchronize()
                    for k in range(groups):
                        sums[k] = signed(out[2 * k])
                        counts[k] = signed(out[2 * k + 1])
                    return GroupSums(sums^, counts^, Float64(now_ns() - t0) / 1e6)
                except e:
                    print("mojoui.frame_gpu: group-by failed (" + String(e) + "); using the CPU")
        # the CPU: the same programs over the shared columns
        ref base = base_at(self.base_addr)[]
        for i in range(self.rows):
            var r = Row(0)
            for c in range(self.stride):
                r[c] = base.cols[c].values[i]
            var keep = True
            for g in ranges:
                var v = r[g.col]
                if v < g.lo or v > g.hi:
                    keep = False
            if not keep:
                continue
            var grp = Int(eval_program(key.unsafe_ptr(), len(key) // 2, r))
            if grp >= 0 and grp < groups:
                sums[grp] += Int(eval_program(value.unsafe_ptr(), len(value) // 2, r))
                counts[grp] += 1
        return GroupSums(sums^, counts^, Float64(now_ns() - t0) / 1e6)


def group_sum(frame: Frame, gf: GpuFrame, key: List[Int64], value: List[Int64], ranges: List[Range], groups: Int,
              use_gpu: Bool = True) -> GroupSums:
    """The session's view: the shared rows on the GPU, then its edits as exact deltas on the CPU."""
    var r = gf.base_sums(key, value, ranges, groups, use_gpu)
    var t0 = now_ns()
    var n = frame.base()[].rows
    for row in frame.changed_rows():
        if row < n:  # take the shared row out …
            var old = Row(0)
            for c in range(frame.stored()):
                old[c] = frame.base()[].cols[c].values[row]
            if frame.matches(old, ranges):
                var g = Int(eval_program(key.unsafe_ptr(), len(key) // 2, old))
                if g >= 0 and g < groups:
                    r.sums[g] -= Int(eval_program(value.unsafe_ptr(), len(value) // 2, old))
                    r.counts[g] -= 1
        if frame.alive(row):  # … and put the session's row in
            var now = frame.row_vector(row)
            if frame.matches(now, ranges):
                var g = Int(eval_program(key.unsafe_ptr(), len(key) // 2, now))
                if g >= 0 and g < groups:
                    r.sums[g] += Int(eval_program(value.unsafe_ptr(), len(value) // 2, now))
                    r.counts[g] += 1
    r.milliseconds += Float64(now_ns() - t0) / 1e6
    return r^


def pivot_program(row_key: List[Int64], columns: Int, col_key: List[Int64]) -> List[Int64]:
    """A key program for a 2-D pivot: row_key × columns + col_key (groups = rows × columns)."""
    var p = List[Int64]()
    for v in row_key:
        p.append(v)
    p.append(0)  # OP_CONST
    p.append(Int64(columns))
    p.append(4)  # OP_MUL
    p.append(0)
    for v in col_key:
        p.append(v)
    p.append(2)  # OP_ADD
    p.append(0)
    return p^
