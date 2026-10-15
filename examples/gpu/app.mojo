# GPU fractal: the picture is computed by a Mojo function running on the GPU,
# one GPU thread per pixel, and shown with each platform's native image view.
# (Needs an NVIDIA or AMD GPU, so it builds for Linux and the web.)

from mojoui import (
    App, Event, View, VStack, HStack, Text, Button, Slider, Dropdown, Image, TITLE, CAPTION, PROMINENT,
)
from mojoui.gpu import Gpu, Params, render_on_cpu

comptime WIDTH = 480
comptime HEIGHT = 320
comptime ZOOM = 1
comptime DETAIL = 2
comptime RUN = 3


def mandelbrot(x: Int, y: Int, w: Int, h: Int, p: Params) -> UInt32:
    """Colour of one pixel. p = (scale, centre x, centre y, max iterations)."""
    var cx = p[1] + (Float32(x) - Float32(w) / 2) * p[0] / Float32(h)
    var cy = p[2] + (Float32(y) - Float32(h) / 2) * p[0] / Float32(h)
    var zx = Float32(0)
    var zy = Float32(0)
    var i = 0
    var limit = Int(p[3])
    while i < limit and zx * zx + zy * zy < 4.0:
        var t = zx * zx - zy * zy + cx
        zy = 2.0 * zx * zy + cy
        zx = t
        i += 1
    if i == limit:
        return UInt32(0xFF000000)  # inside the set: black
    var t = Float32(i) / Float32(limit)
    var r = UInt32(9.0 * (1 - t) * t * t * t * 255)
    var g = UInt32(15.0 * (1 - t) * (1 - t) * t * t * 255)
    var b = UInt32(8.5 * (1 - t) * (1 - t) * (1 - t) * t * 255)
    return r | (g << 8) | (b << 16) | (UInt32(255) << 24)


def two_decimals(x: Float64) -> String:
    var hundredths = Int(x * 100 + 0.5)
    var frac = hundredths % 100
    return String(hundredths // 100) + "." + ("0" if frac < 10 else "") + String(frac)


struct Main(App):
    var gpu: Gpu
    var zoom: Int  # 0–100
    var detail: Int  # index into DETAILS
    var pixels: List[UInt32]
    var result: String

    def __init__(out self):
        self.gpu = Gpu()
        self.zoom = 0
        self.detail = 1
        self.pixels = List[UInt32]()
        self.result = "Drag the zoom, or press Run on GPU." if self.gpu.available() else "This machine has no supported GPU (NVIDIA or AMD)."
        self.pixels = List[UInt32](length=WIDTH * HEIGHT, fill=UInt32(0xFF202020))  # grey until rendered
        self.render(False)

    def params(self) -> Params:
        var details: List[Int] = [64, 256, 1024]
        var scale = Float32(2.6) / (1.0 + Float32(self.zoom * self.zoom) / 12.0)
        # Always centred on a spiral at the edge of the set, so zooming in stays colourful.
        return Params(scale, Float32(-0.7436439), Float32(0.1318259), Float32(details[self.detail]))

    def render(mut self, check: Bool):
        if not self.gpu.available():
            return
        try:
            var gpu = self.gpu.render[mandelbrot](WIDTH, HEIGHT, self.params())
            self.pixels = gpu.pixels.copy()
            if check:
                var cpu = render_on_cpu[mandelbrot](WIDTH, HEIGHT, self.params())
                var same = 0
                for i in range(len(cpu.pixels)):
                    if cpu.pixels[i] == gpu.pixels[i]:
                        same += 1
                var verdict = "✓ matches CPU" if same == len(cpu.pixels) else String(same) + "/" + String(len(cpu.pixels)) + " match CPU"
                self.result = (
                    "Result: " + String(WIDTH * HEIGHT) + " pixels in " + two_decimals(gpu.milliseconds)
                    + " ms on GPU · CPU took " + two_decimals(cpu.milliseconds) + " ms · " + verdict
                )
        except e:
            self.result = "GPU error: " + String(e)

    def title(self) -> String:
        return "GPU fractal"

    def update(mut self, event: Event):
        if event.message == ZOOM:
            self.zoom = event.number
            self.render(False)
        elif event.message == DETAIL:
            self.detail = event.number
            self.render(False)
        elif event.message == RUN:
            self.render(True)

    def view(self) -> View:
        var details: List[String] = ["Fast", "Detailed", "Very detailed"]
        return VStack(
            Text("GPU fractal", style=TITLE),
            Text("GPU: " + self.gpu.name, style=CAPTION),
            Image(self.pixels, WIDTH, HEIGHT),
            HStack(Text("Zoom"), Slider(self.zoom, on_change=ZOOM), spacing=12),
            HStack(Text("Detail"), Dropdown(details, self.detail, on_select=DETAIL), spacing=12),
            Button("Run on GPU", on_tap=RUN, style=PROMINENT),
            Text(self.result, style=CAPTION),
            spacing=14,
        )
