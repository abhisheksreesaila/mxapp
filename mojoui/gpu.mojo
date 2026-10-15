# Run a plain Mojo function once per pixel, on the GPU (NVIDIA or AMD, via MAX).
#
#   def shade(x: Int, y: Int, width: Int, height: Int, p: Params) -> UInt32: ...
#   var gpu = Gpu()                                  # once; gpu.available() if there is one
#   var pixels = gpu.render[shade](480, 320, p).pixels
#
# The app writes only ordinary Mojo maths; this module compiles it into a GPU
# kernel and launches one GPU thread per pixel. Needs the `max` package.

from max.gpu import global_idx
from std.sys import CompilationTarget
from max.gpu.host import DeviceContext
from std.math import ceildiv
from std.time import perf_counter_ns

comptime Params = SIMD[DType.float32, 4]  # four numbers your pixel function can use
comptime PixelFn = def(Int, Int, Int, Int, Params) thin -> UInt32


# (GPU kernels still take UnsafePointer in MAX 26.6; the deprecation warning is expected.)
def _pixels_kernel[f: PixelFn](dst: UnsafePointer[UInt32, MutAnyOrigin], w32: Int32, h32: Int32, p: Params):
    var w = Int(w32)
    var h = Int(h32)
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    if x < w and y < h:
        dst.unsafe_offset(y * w + x)[] = f(x, y, w, h, p)


@fieldwise_init
struct Rendered(Copyable, Movable):
    var pixels: List[UInt32]
    var milliseconds: Float64  # time taken (GPU: kernel launch to results ready)


struct Gpu(Movable):
    """The machine's first GPU, if it has a supported one. Keep one and reuse it.

    Checks the device count first: creating a device context with no GPU present
    crashes rather than raising, so `available` must be checked (render() does).
    """

    var ctx: Optional[DeviceContext]
    var name: String

    def __init__(out self, use: Bool = True):
        """use=False: act as if there were no GPU (to compare with the CPU)."""
        self.ctx = None
        self.name = "no GPU found"
        if not use:
            return
        comptime if CompilationTarget.is_linux():  # (Apple builds: the CPU path; MAX's Apple GPU runtime isn't linked)
            try:
                if DeviceContext.number_of_devices() > 0:
                    var ctx = DeviceContext()
                    self.name = ctx.name()
                    self.ctx = ctx^
            except:
                self.ctx = None

    def available(self) -> Bool:
        return Bool(self.ctx)

    def render[f: PixelFn](self, width: Int, height: Int, p: Params) raises -> Rendered:
        """Runs f for every pixel on the GPU; returns the pixels and how long it took."""
        if not self.ctx:
            raise Error("no GPU found")
        ref ctx = self.ctx.value()
        var buf = ctx.enqueue_create_buffer[DType.uint32](width * height)
        ctx.synchronize()
        var t0 = perf_counter_ns()
        ctx.enqueue_function[_pixels_kernel[f]](
            buf.unsafe_ptr(), Int32(width), Int32(height), p,
            grid_dim=(ceildiv(width, 16), ceildiv(height, 16)), block_dim=(16, 16),
        )
        ctx.synchronize()
        var ms = Float64(perf_counter_ns() - t0) / 1e6
        var out = List[UInt32](capacity=width * height)
        with buf.map_to_host() as host:
            for i in range(width * height):
                out.append(host[i])
        return Rendered(out^, ms)


def render_on_cpu[f: PixelFn](width: Int, height: Int, p: Params) -> Rendered:
    """The same, one pixel at a time on the CPU (for checking and comparing)."""
    var t0 = perf_counter_ns()
    var out = List[UInt32](capacity=width * height)
    for y in range(height):
        for x in range(width):
            out.append(f(x, y, width, height, p))
    return Rendered(out^, Float64(perf_counter_ns() - t0) / 1e6)


def gpu_present() -> Bool:
    """Whether this machine has a GPU mojoui can use (cheap: doesn't start it)."""
    comptime if CompilationTarget.is_linux():
        try:
            return DeviceContext.number_of_devices() > 0
        except:
            return False
    return False


# ---------- point clouds: millions of points → a density picture ----------
#
#   def place(p: Point, w: Int, h: Int, k: Knobs) -> Int: ...   # pixel index, or OUTSIDE / FILTERED
#   def colour(count: UInt32, k: Knobs) -> UInt32: ...          # a pixel's colour from its count
#   var cloud = PointCloud(x^, y^, a^, b^)                       # columns; uploaded to the GPU once
#   var hits = cloud.bin[place](surface.width, surface.height, k)
#   cloud.shade[colour](surface, k)
#
# Both functions are plain Mojo. On a machine with a supported GPU they run as GPU
# kernels (one thread per point, then one per pixel); otherwise the same functions
# run on the CPU. The data stays on the GPU between frames.

from std.atomic import Atomic, Ordering
from max.gpu import grid_dim, block_dim
from max.gpu.host import DeviceBuffer
from mojoui.canvas import Surface

comptime Point = SIMD[DType.float32, 4]  # one point's four columns (x, y, a, b)
comptime Knobs = SIMD[DType.float32, 8]  # eight numbers the app's functions can use
comptime OUTSIDE = -1  # place(): matches, but falls outside the picture
comptime FILTERED = -2  # place(): doesn't match
comptime PlaceFn = def(Point, Int, Int, Knobs) thin -> Int
comptime ColourFn = def(UInt32, Knobs) thin -> UInt32


def _bin_kernel[f: PlaceFn](
    pts: UnsafePointer[Float32, MutAnyOrigin], n: Int32, counts: UnsafePointer[UInt32, MutAnyOrigin],
    w32: Int32, h32: Int32, k: Knobs,
):
    # Grid-stride loop: each thread takes many points, then adds its totals once.
    var w = Int(w32)
    var h = Int(h32)
    var stride = Int(grid_dim.x) * Int(block_dim.x)
    var matched = UInt32(0)
    var shown = UInt32(0)
    var i = Int(global_idx.x)
    while i < Int(n):
        var p = pts.unsafe_offset(4 * i).unsafe_load[width=4]()
        var at = f(p, w, h, k)
        if at >= OUTSIDE:
            matched += 1
        if at >= 0:
            shown += 1
            _ = Atomic.fetch_add[ordering=Ordering.RELAXED](counts.unsafe_offset(at), UInt32(1))
        i += stride
    if matched > 0:
        _ = Atomic.fetch_add[ordering=Ordering.RELAXED](counts.unsafe_offset(w * h), matched)
    if shown > 0:
        _ = Atomic.fetch_add[ordering=Ordering.RELAXED](counts.unsafe_offset(w * h + 1), shown)


def _shade_kernel[g: ColourFn](
    counts: UnsafePointer[UInt32, MutAnyOrigin], dst: UnsafePointer[UInt32, MutAnyOrigin], total: Int32, k: Knobs,
):
    var i = Int(global_idx.x)
    if i < Int(total):
        dst.unsafe_offset(i)[] = g(counts.unsafe_offset(i)[], k)


struct PointCloud(Movable):
    """Up to four float32 columns of the same length, kept on the GPU (uploaded once) when there
    is one, and always on the CPU. Columns are what a dataframe hands over (e.g. MX frame)."""

    var gpu: Gpu
    var count: Int
    var host: List[Float32]  # four floats per point (x, y, a, b), the layout the GPU reads fastest
    var device: Optional[DeviceBuffer[DType.float32]]
    var counts: Optional[DeviceBuffer[DType.uint32]]  # w*h counts + matched + shown
    var image: Optional[DeviceBuffer[DType.uint32]]
    var host_counts: List[UInt32]
    var w: Int
    var h: Int
    var matched: Int  # points that matched in the last bin()
    var shown: Int  # of those, points inside the picture
    var uploads: Int
    var milliseconds: Float64  # last bin() + shade(), including the copy to the screen's memory

    def __init__(out self, x: List[Float32], y: List[Float32], a: List[Float32], b: List[Float32], use_gpu: Bool = True):
        self.gpu = Gpu(use_gpu)
        self.count = min(min(len(x), len(y)), min(len(a), len(b)))
        self.host = List[Float32](length=4 * self.count, fill=0)
        for i in range(self.count):
            self.host[4 * i] = x[i]
            self.host[4 * i + 1] = y[i]
            self.host[4 * i + 2] = a[i]
            self.host[4 * i + 3] = b[i]
        self.device = None
        self.counts = None
        self.image = None
        self.host_counts = List[UInt32]()
        self.w = 0
        self.h = 0
        self.matched = 0
        self.shown = 0
        self.uploads = 0
        self.milliseconds = 0
        comptime if CompilationTarget.is_linux():
            if self.gpu.available() and self.count > 0:
                try:
                    ref ctx = self.gpu.ctx.value()
                    var buf = ctx.enqueue_create_buffer[DType.float32](4 * self.count)
                    ctx.enqueue_copy(dst_buf=buf, src_ptr=self.host.unsafe_ptr())
                    ctx.synchronize()
                    self.device = buf^
                    self.uploads += 1
                except:
                    self.device = None

    def on_gpu(self) -> Bool:
        return Bool(self.device)

    def device_name(self) -> String:
        return self.gpu.name if self.on_gpu() else String("CPU")

    def bin[f: PlaceFn](mut self, w: Int, h: Int, k: Knobs) -> Int:
        """Counts the points landing on each of w × h pixels; returns how many matched."""
        var t0 = perf_counter_ns()
        self.w = w
        self.h = h
        comptime if CompilationTarget.is_linux():
            if self.on_gpu():
                try:
                    ref ctx = self.gpu.ctx.value()
                    if not self.counts or len(self.counts.value()) != w * h + 2:
                        self.counts = ctx.enqueue_create_buffer[DType.uint32](w * h + 2)
                        self.image = ctx.enqueue_create_buffer[DType.uint32](w * h)
                    ref counts = self.counts.value()
                    ctx.enqueue_memset(counts, 0)
                    var threads = 256
                    var blocks = min(ceildiv(self.count, threads), 82 * 16)
                    ctx.enqueue_function[_bin_kernel[f]](
                        self.device.value().unsafe_ptr(), Int32(self.count), counts.unsafe_ptr(), Int32(w), Int32(h), k,
                        grid_dim=blocks, block_dim=threads,
                    )
                    var totals = List[UInt32](length=2, fill=0)
                    ctx.enqueue_copy(dst_ptr=totals.unsafe_ptr(), src_buf=counts.create_sub_buffer[DType.uint32](w * h, 2))
                    ctx.synchronize()
                    self.matched = Int(totals[0])
                    self.shown = Int(totals[1])
                    self.milliseconds = Float64(perf_counter_ns() - t0) / 1e6
                    return self.matched
                except:
                    pass  # fall back to the CPU below
        if len(self.host_counts) != w * h:
            self.host_counts = List[UInt32](length=w * h, fill=0)
        else:
            for i in range(w * h):
                self.host_counts[i] = 0
        var matched = 0
        var shown = 0
        var pts = self.host.unsafe_ptr()
        for i in range(self.count):
            var p = pts.unsafe_offset(4 * i).unsafe_load[width=4]()
            var at = f(p, w, h, k)
            if at >= OUTSIDE:
                matched += 1
            if at >= 0:
                shown += 1
                self.host_counts[at] += 1
        self.matched = matched
        self.shown = shown
        self.milliseconds = Float64(perf_counter_ns() - t0) / 1e6
        return matched

    def shade[g: ColourFn](mut self, mut surface: Surface, k: Knobs):
        """Colours the surface from the last bin() (which must have used its width and height)."""
        var t0 = perf_counter_ns()
        var total = surface.width * surface.height
        if surface.width != self.w or surface.height != self.h:
            surface.fill(0)
            return
        comptime if CompilationTarget.is_linux():
            if self.on_gpu() and self.counts and self.image:
                try:
                    ref ctx = self.gpu.ctx.value()
                    ref image = self.image.value()
                    ctx.enqueue_function[_shade_kernel[g]](
                        self.counts.value().unsafe_ptr(), image.unsafe_ptr(), Int32(total), k,
                        grid_dim=ceildiv(total, 256), block_dim=256,
                    )
                    var dst = UnsafePointer[UInt32, MutAnyOrigin](unsafe_from_address=surface.address)
                    ctx.enqueue_copy(dst_ptr=dst, src_buf=image)
                    ctx.synchronize()
                    self.milliseconds += Float64(perf_counter_ns() - t0) / 1e6
                    return
                except:
                    pass
        var p = surface.pixels()
        for i in range(total):
            p.unsafe_offset(i)[] = g(self.host_counts[i] if i < len(self.host_counts) else 0, k)
        self.milliseconds += Float64(perf_counter_ns() - t0) / 1e6
