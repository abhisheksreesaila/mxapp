# A Canvas's picture as a display list (goal 26, D-252): the drawing code says *what* goes where (rects, lines,
# circles, text runs, in layers) and each host draws it with its own GPU renderer (GTK: render nodes; the web:
# Canvas2D; Apple: Metal). The same drawing code also paints today's CPU Surface, through SurfacePainter, which stays
# the reference (tests, screenshots) and the fallback.
#
#   def draw[P: Painter](mut self, mut p: P, ...):
#       p.begin_layer("cells")
#       p.rect(0, 0, w, h, CARD, 0)
#       p.text(font, "1,204.50", x, baseline, 13, INK, REGULAR, RIGHT, 0)
#       p.begin_layer("ring")        # a layer that moves on its own: the host reuses the cells' nodes untouched
#       ...

from mojoui.canvas import Surface
from mojoui.draw import rect, line, circle, hline
from mojoui.text import Font, REGULAR, LEFT

comptime OP_RECT = 1  # x, y, w, h, radius
comptime OP_CIRCLE = 2  # x, y, radius
comptime OP_LINE = 3  # x0, y0, x1, y1, width
comptime OP_TEXT = 4  # x, baseline, size, slant, weight, align (+ the text)
comptime OP_FILL = 5  # the whole canvas, one colour (set, not blended)
comptime STRIDE = 6  # floats per op


trait Painter:
    """What drawing code paints with: pixels (SurfacePainter) or a display list (Scene). Sizes are pixels."""

    def width(self) -> Int:
        ...

    def height(self) -> Int:
        ...

    def scale(self) -> Float64:
        ...

    def still(self) -> Bool:
        """The person asked for less motion (or a still picture is wanted): animations jump to their end."""
        ...

    def set_again(mut self):
        """Mid-animation: the host draws the next frame too."""
        ...

    def begin_layer(mut self, key: String):
        """What follows (until the next layer) is one layer: a host can keep it when it comes again unchanged."""
        ...

    def fill(mut self, color: UInt32):
        ...

    def rect(mut self, x: Float64, y: Float64, w: Float64, h: Float64, color: UInt32, radius: Float64):
        ...

    def line(mut self, x0: Float64, y0: Float64, x1: Float64, y1: Float64, width: Float64, color: UInt32):
        ...

    def circle(mut self, x: Float64, y: Float64, radius: Float64, color: UInt32):
        ...

    def text(mut self, font: Font, text: String, x: Float64, baseline: Float64, size: Float64, color: UInt32, weight: Int, align: Int,
             slant: Float64):
        """`text` with its baseline at `baseline`, starting at x (or centred on it, or ending at it: `align`)."""
        ...


struct SurfacePainter(Painter, Movable):
    """Paints into pixels, exactly as before the Scene (the reference and the fallback)."""

    var s: Surface

    def __init__(out self, var s: Surface):
        self.s = s^

    def width(self) -> Int:
        return self.s.width

    def height(self) -> Int:
        return self.s.height

    def scale(self) -> Float64:
        return self.s.scale

    def still(self) -> Bool:
        return self.s.still

    def set_again(mut self):
        self.s.again = True

    def begin_layer(mut self, key: String):
        pass

    def fill(mut self, color: UInt32):
        self.s.fill(color)

    def rect(mut self, x: Float64, y: Float64, w: Float64, h: Float64, color: UInt32, radius: Float64):
        rect(self.s, x, y, w, h, color, radius)

    def line(mut self, x0: Float64, y0: Float64, x1: Float64, y1: Float64, width: Float64, color: UInt32):
        line(self.s, x0, y0, x1, y1, width, color)

    def circle(mut self, x: Float64, y: Float64, radius: Float64, color: UInt32):
        circle(self.s, x, y, radius, color)

    def text(mut self, font: Font, text: String, x: Float64, baseline: Float64, size: Float64, color: UInt32, weight: Int, align: Int,
             slant: Float64):
        font.draw(self.s, text, x, baseline, size, color, weight, align, slant)


struct Scene(Painter, Movable, Copyable):
    """A display list: ops in order, STRIDE floats each, a colour each, a text for text ops; layers are runs of ops."""

    var w: Int
    var h: Int
    var k: Float64
    var is_still: Bool
    var again: Bool
    var kinds: List[UInt8]
    var nums: List[Float32]
    var colors: List[UInt32]
    var text_of: List[Int32]  # the op's text (index into texts), or -1
    var texts: List[String]
    var layer_keys: List[String]
    var layer_starts: List[Int]  # the first op of each layer

    def __init__(out self, width: Int, height: Int, scale: Float64):
        self.w = width
        self.h = height
        self.k = scale
        self.is_still = False
        self.again = False
        self.kinds = List[UInt8](capacity=4096)
        self.nums = List[Float32](capacity=4096 * STRIDE)
        self.colors = List[UInt32](capacity=4096)
        self.text_of = List[Int32](capacity=4096)
        self.texts = List[String](capacity=1024)
        self.layer_keys = List[String]()
        self.layer_starts = List[Int]()

    def width(self) -> Int:
        return self.w

    def height(self) -> Int:
        return self.h

    def scale(self) -> Float64:
        return self.k

    def still(self) -> Bool:
        return self.is_still

    def set_again(mut self):
        self.again = True

    def ops(self) -> Int:
        return len(self.kinds)

    def begin_layer(mut self, key: String):
        self.layer_keys.append(key)
        self.layer_starts.append(len(self.kinds))

    def layers(self) -> Int:
        return len(self.layer_keys)

    def layer_range(self, i: Int) -> Tuple[Int, Int]:
        """Layer i's ops: [first, end). Ops before the first layer belong to layer 0 (a scene with no layers is one)."""
        var first = 0 if i == 0 else self.layer_starts[i]
        var end = self.layer_starts[i + 1] if i + 1 < len(self.layer_starts) else len(self.kinds)
        return (first, end)

    def _op(mut self, kind: Int, a: Float64, b: Float64, c: Float64, d: Float64, e: Float64, f: Float64, color: UInt32, text: Int32):
        if len(self.layer_keys) == 0:
            self.begin_layer("")
        self.kinds.append(UInt8(kind))
        self.nums.append(Float32(a))
        self.nums.append(Float32(b))
        self.nums.append(Float32(c))
        self.nums.append(Float32(d))
        self.nums.append(Float32(e))
        self.nums.append(Float32(f))
        self.colors.append(color)
        self.text_of.append(text)

    def fill(mut self, color: UInt32):
        self._op(OP_FILL, 0, 0, Float64(self.w), Float64(self.h), 0, 0, color, -1)

    def rect(mut self, x: Float64, y: Float64, w: Float64, h: Float64, color: UInt32, radius: Float64):
        if w <= 0 or h <= 0:
            return
        self._op(OP_RECT, x, y, w, h, radius, 0, color, -1)

    def line(mut self, x0: Float64, y0: Float64, x1: Float64, y1: Float64, width: Float64, color: UInt32):
        self._op(OP_LINE, x0, y0, x1, y1, width, 0, color, -1)

    def circle(mut self, x: Float64, y: Float64, radius: Float64, color: UInt32):
        self._op(OP_CIRCLE, x, y, radius, 0, 0, 0, color, -1)

    def text(mut self, font: Font, text: String, x: Float64, baseline: Float64, size: Float64, color: UInt32, weight: Int, align: Int,
             slant: Float64):
        if text == "":
            return
        self.texts.append(text)
        self._op(OP_TEXT, x, baseline, size, slant, Float64(weight), Float64(align), color, Int32(len(self.texts) - 1))

    def num(self, op: Int, j: Int) -> Float64:
        return Float64(self.nums[op * STRIDE + j])

    def text_at(self, op: Int) -> String:
        var t = Int(self.text_of[op])
        return self.texts[t] if t >= 0 else String("")

    def same_layer(self, i: Int, other: Scene, j: Int) -> Bool:
        """Whether layer i of this scene draws exactly what layer j of `other` does (same ops, numbers, colours, texts)."""
        var a = self.layer_range(i)
        var b = other.layer_range(j)
        if a[1] - a[0] != b[1] - b[0] or self.layer_keys[i] != other.layer_keys[j]:
            return False
        for n in range(a[1] - a[0]):
            var p = a[0] + n
            var q = b[0] + n
            if self.kinds[p] != other.kinds[q] or self.colors[p] != other.colors[q]:
                return False
            for x in range(STRIDE):
                if self.nums[p * STRIDE + x] != other.nums[q * STRIDE + x]:
                    return False
            if self.text_of[p] >= 0 and self.text_at(p) != other.text_at(q):
                return False
        return True

    def raster(self, mut s: Surface, font: Font):
        """Plays the list into pixels (the CPU reference: tests, screenshots, hosts without a GPU path)."""
        for op in range(len(self.kinds)):
            var kind = Int(self.kinds[op])
            var c = self.colors[op]
            if kind == OP_FILL:
                s.fill(c)
            elif kind == OP_RECT:
                rect(s, self.num(op, 0), self.num(op, 1), self.num(op, 2), self.num(op, 3), c, self.num(op, 4))
            elif kind == OP_CIRCLE:
                circle(s, self.num(op, 0), self.num(op, 1), self.num(op, 2), c)
            elif kind == OP_LINE:
                line(s, self.num(op, 0), self.num(op, 1), self.num(op, 2), self.num(op, 3), self.num(op, 4), c)
            elif kind == OP_TEXT:
                font.draw(s, self.text_at(op), self.num(op, 0), self.num(op, 1), self.num(op, 2), c, Int(self.num(op, 4)), Int(self.num(op, 5)),
                          self.num(op, 3))
