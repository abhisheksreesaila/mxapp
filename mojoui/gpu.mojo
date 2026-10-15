# Run a plain Mojo function once per pixel, on the GPU (NVIDIA or AMD, via MAX).
#
#   def shade(x: Int, y: Int, width: Int, height: Int, p: Params) -> UInt32: ...
#   var gpu = Gpu()                                  # once; gpu.available() if there is one
#   var pixels = gpu.render[shade](480, 320, p).pixels
#
# The app writes only ordinary Mojo maths; this module compiles it into a GPU
# kernel and launches one GPU thread per pixel. Needs the `max` package.

from max.gpu import global_idx
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

    def __init__(out self):
        self.ctx = None
        self.name = "no GPU found"
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
