# mojoui.island: the window's living status (D-255, direction B): one capsule where the document and GPU chips were,
# tinted by what's happening. It rests on the document ("big · 100,000,000 rows · RTX 3090"); a query running shows
# its progress and pace, a result its time, an edit an Undo with a countdown, an error stays until it's seen. Between
# states the capsule's width and height move on the calm curve (320 ms) and its face cross-fades; with less motion asked
# it jumps. Drawn on a Canvas, so every host draws the same pixels; right-aligned in its canvas (it grows leftwards).
#
#   Canvas(ISLAND, version, on_gesture=ISLAND_TAP, on_frame=ISLAND_FRAME if island.wants_frames(now) else NO_MSG)
#       .width(ISLAND_W).height(ISLAND_H).tag("island")                                       # in view()
#   island.show(Activity.running("Median of revenue by region", 0.43, "1.2B rows/s"), font, now_ns())   # in update()
#   island.draw(surface, font, pal, now_ns())                                                  # in draw()
#   var hit = island.hit(event.x, event.y)                                                     # HIT_BODY: open the panel; HIT_ACTION: its action

from std.math import sin, cos, pi
from mojoui.view import View, Canvas, NO_MSG
from mojoui.canvas import Surface
from mojoui.text import Font, LEFT, CENTRE, REGULAR, MEDIUM
from mojoui.theme import Palette
from mojoui.draw import rect, line, circle, with_alpha, blend

comptime IDLE = 0  # the document at rest
comptime RUNNING = 1  # work under way: a spinner, its share done (when known) and pace
comptime DONE = 2  # a result: a tick and its time, then back to rest
comptime UNDO = 3  # an edit: what it did, Undo, a countdown ring
comptime ERROR = 4  # a problem: stays until it's seen (tapped) or replaced

comptime ISLAND_W = 460  # the canvas, points (the capsule inside it grows leftwards from its right edge)
comptime ISLAND_H = 40
comptime MORPH_MS = 320.0  # the capsule's size moves to the new face's over this long (the calm curve)
comptime FADE_OUT_MS = 150.0  # the old face fades out, then the new one in
comptime FADE_IN_MS = 220.0
comptime TEXT_PT = 13.0
comptime PAD = 12.0
comptime ICON = 14.0
comptime GAP = 8.0

comptime HIT_NONE = 0
comptime HIT_BODY = 1  # the capsule: open its panel
comptime HIT_ACTION = 2  # its action (Undo, Show)


@fieldwise_init
struct Activity(Copyable, Movable):
    """One face of the island: its kind, a strong lead ("Median of revenue by region"), the rest ("43% · 1.2B rows/s"),
    a share done (0–1; -1 unknown), an action ("Undo", "Show", "") and how long it stays (seconds; 0: until replaced)."""

    var kind: Int
    var lead: String
    var text: String
    var progress: Float64
    var action: String
    var seconds: Float64

    @staticmethod
    def idle(lead: String, text: String) -> Activity:
        return Activity(IDLE, lead, text, -1.0, "", 0.0)

    @staticmethod
    def running(lead: String, progress: Float64 = -1.0, text: String = "") -> Activity:
        return Activity(RUNNING, lead, text, progress, "", 0.0)

    @staticmethod
    def done(lead: String, text: String, seconds: Float64 = 4.0) -> Activity:
        return Activity(DONE, lead, text, -1.0, "", seconds)

    @staticmethod
    def undo(lead: String, text: String = "", seconds: Float64 = 5.0) -> Activity:
        return Activity(UNDO, lead, text, -1.0, "Undo", seconds)

    @staticmethod
    def error(lead: String, text: String = "") -> Activity:
        return Activity(ERROR, lead, text, -1.0, "Show", 0.0)


def calm(t: Float64) -> Float64:
    """The calm curve: fast out of the start, settling without overshoot (a cubic ease-out), t clamped to 0–1."""
    var u = 1.0 - min(max(t, 0.0), 1.0)
    return 1.0 - u * u * u


struct Island(Copyable, Movable):
    var rest: Activity  # what it shows when nothing's happening
    var now: Activity
    var was: Activity  # the face before (cross-fading out)
    var since: Int  # ns: when `now` began
    var from_w: Float64  # the capsule's size (points) when `now` began, and where it's going
    var from_h: Float64
    var to_w: Float64
    var to_h: Float64
    var still: Bool  # less motion asked: sizes and faces jump

    def __init__(out self):
        self.rest = Activity.idle("", "")
        self.now = self.rest.copy()
        self.was = self.rest.copy()
        self.since = 0
        self.from_w = 120.0
        self.from_h = 28.0
        self.to_w = 120.0
        self.to_h = 28.0
        self.still = False

    def size_of(self, a: Activity, font: Font, k: Float64 = 1.0) -> Tuple[Float64, Float64]:
        """The capsule a face needs, points: its texts, icon and action, with padding; never wider than the canvas."""
        var w = PAD + ICON + GAP + font.measure(a.lead, TEXT_PT * k, MEDIUM) / k
        if a.text != "":
            w += 6.0 + font.measure(a.text, TEXT_PT * k) / k
        if a.action != "":
            w += GAP + 14.0 + font.measure(a.action, TEXT_PT * k, MEDIUM) / k
        if a.kind == UNDO:
            w += GAP + 16.0  # (the countdown ring)
        w += PAD + 4.0  # (and a little air at the end: the capsule's curve takes it)
        var h = 28.0 if a.kind == IDLE else 32.0
        return (min(w, Float64(ISLAND_W) - 4.0), h)

    def size_at(self, t: Int) -> Tuple[Float64, Float64]:
        """The capsule's size at time t (ns)."""
        var f = 1.0 if self.still else calm(Float64(t - self.since) / 1e6 / MORPH_MS)
        return (self.from_w + (self.to_w - self.from_w) * f, self.from_h + (self.to_h - self.from_h) * f)

    def show(mut self, var a: Activity, font: Font, t: Int):
        """A new face from time t (ns): the capsule moves from where it is now to the size this one needs."""
        var size = self.size_at(t)
        var target = self.size_of(a, font)
        self.from_w = size[0]
        self.from_h = size[1]
        self.to_w = target[0]
        self.to_h = target[1]
        self.was = self.now.copy()
        self.now = a^
        self.since = t

    def set_rest(mut self, var a: Activity, font: Font, t: Int):
        """The resting face (the document); shown now if the island is resting."""
        var resting = self.now.kind == IDLE
        self.rest = a^
        if resting and (self.rest.lead != self.now.lead or self.rest.text != self.now.text):
            self.show(self.rest.copy(), font, t)

    def progress(mut self, share: Float64, text: String):
        """A running face's share done and pace, without a new morph (its width follows on the next show)."""
        if self.now.kind == RUNNING:
            self.now.progress = share
            self.now.text = text

    def tick(mut self, font: Font, t: Int) -> Bool:
        """Time passing: a result or an undo that has stayed its time gives way to the rest. True when it changed."""
        if (self.now.kind == DONE or self.now.kind == UNDO) and self.now.seconds > 0 and Float64(t - self.since) / 1e9 >= self.now.seconds:
            self.show(self.rest.copy(), font, t)
            return True
        return False

    def seen(mut self, font: Font, t: Int):
        """An error (or anything) acknowledged: back to the rest."""
        self.show(self.rest.copy(), font, t)

    def wants_frames(self, t: Int) -> Bool:
        """Whether its canvas should draw every display frame: mid-morph or mid-fade, or a face that moves (the spinner,
        the countdown) or waits to give way (a result)."""
        if self.still:
            return self.now.kind == RUNNING or self.now.kind == DONE or self.now.kind == UNDO  # (no motion, but still polled and timed)
        if Float64(t - self.since) / 1e6 < max(MORPH_MS, FADE_OUT_MS + FADE_IN_MS):
            return True
        return self.now.kind == RUNNING or self.now.kind == DONE or self.now.kind == UNDO

    def capsule(self, t: Int, canvas_w: Float64, canvas_h: Float64) -> Tuple[Float64, Float64, Float64, Float64]:
        """Where the capsule is at time t, points: x, y, w, h (right-aligned, centred vertically)."""
        var size = self.size_at(t)
        return (canvas_w - size[0] - 2.0, (canvas_h - size[1]) / 2, size[0], size[1])

    def hit(self, x: Float64, y: Float64, canvas_w: Float64 = Float64(ISLAND_W), canvas_h: Float64 = Float64(ISLAND_H), t: Int = -1) -> Int:
        """What a tap at (x, y) points touched: the action (its right end), the capsule, or nothing."""
        var c = self.capsule(t if t >= 0 else self.since + 321_000_000, canvas_w, canvas_h)
        if x < c[0] or x > c[0] + c[2] or y < c[1] - 4 or y > c[1] + c[3] + 4:
            return HIT_NONE
        if self.now.action != "" and x > c[0] + c[2] - self.action_w():
            return HIT_ACTION
        return HIT_BODY

    def action_w(self) -> Float64:
        """The action's share of the capsule, from its right end (points)."""
        return PAD + 8.0 * Float64(len(self.now.action.codepoints())) + (24.0 if self.now.kind == UNDO else 0.0)

    def tint(self, kind: Int, p: Palette) -> Tuple[UInt32, UInt32]:
        """A face's capsule colour and its icon colour: neutral at rest, the accent's wash at work, green done, red wrong."""
        if kind == RUNNING or kind == UNDO:
            return (blend(p.raised, p.accent, 0.16), p.accent)
        if kind == DONE:
            return (blend(p.raised, p.good, 0.16), p.good)
        if kind == ERROR:
            return (blend(p.raised, p.bad, 0.16), p.bad)
        return (p.raised, p.good)

    def draw(self, mut s: Surface, font: Font, p: Palette, t: Int):
        """The capsule at time t (ns) on its canvas (the band behind it in the chrome colour)."""
        var k = s.scale
        s.fill(p.chrome)
        var c = self.capsule(t, s.points_width(), s.points_height())
        var x = c[0] * k
        var y = c[1] * k
        var w = c[2] * k
        var h = c[3] * k
        var f = 1.0 if self.still else calm(Float64(t - self.since) / 1e6 / MORPH_MS)
        var old = self.tint(self.was.kind, p)
        var new = self.tint(self.now.kind, p)
        var fill = blend(old[0], new[0], f)
        rect(s, x, y + 1 * k, w, h, with_alpha(p.ink, 0.06), h / 2)  # (one soft shadow, a point under it)
        rect(s, x, y, w, h, fill, h / 2)
        var ms = Float64(t - self.since) / 1e6
        if self.still or ms >= FADE_OUT_MS:  # the new face fades in after the old one's out
            var a = 1.0 if self.still else calm((ms - FADE_OUT_MS) / FADE_IN_MS)
            self.face(s, font, p, self.now, x, y, w, h, a, t)
        else:
            self.face(s, font, p, self.was, x, y, w, h, 1.0 - ms / FADE_OUT_MS, t)

    def face(self, mut s: Surface, font: Font, p: Palette, a: Activity, x: Float64, y: Float64, w: Float64, h: Float64, alpha: Float64, t: Int):
        """One face's icon, texts and action inside the capsule (x, y, w, h in pixels), at `alpha`."""
        var k = s.scale
        var ink = blend(p.raised, p.ink, alpha)
        var ink2 = blend(p.raised, p.ink2, alpha)
        var tone = blend(p.raised, self.tint(a.kind, p)[1], alpha)
        var cx = x + (PAD + ICON / 2) * k
        var cy = y + h / 2
        if a.kind == IDLE:
            circle(s, cx, cy, 3.5 * k, tone)
        elif a.kind == RUNNING:  # a spinner: a quarter-turn arc going round
            var turn = Float64(t // 1_000_000 % 900) / 900.0 * 2.0 * pi
            for i in range(10):
                var u = turn + Float64(i) * 0.16
                circle(s, cx + cos(u) * 5.5 * k, cy + sin(u) * 5.5 * k, 1.3 * k, with_alpha(tone, Float64(i + 1) / 10.0))
        elif a.kind == DONE:  # a tick
            line(s, cx - 4.5 * k, cy, cx - 1.5 * k, cy + 3.5 * k, 1.8 * k, tone)
            line(s, cx - 1.5 * k, cy + 3.5 * k, cx + 4.5 * k, cy - 4 * k, 1.8 * k, tone)
        elif a.kind == UNDO:  # a curved arrow, as a hook
            line(s, cx - 4 * k, cy - 1 * k, cx + 3 * k, cy - 1 * k, 1.6 * k, tone)
            line(s, cx - 4 * k, cy - 1 * k, cx - 1 * k, cy - 4 * k, 1.6 * k, tone)
            line(s, cx - 4 * k, cy - 1 * k, cx - 1 * k, cy + 2 * k, 1.6 * k, tone)
        else:  # an error: a filled circle with "!"
            circle(s, cx, cy, 6.5 * k, tone)
            font.draw(s, "!", cx, cy + 4 * k, 11 * k, blend(tone, p.card, alpha), p.medium, CENTRE)
        var pen = x + (PAD + ICON + GAP) * k
        var base = cy + 4.5 * k
        var right = x + w - PAD * k
        if a.action != "":
            right -= (font.measure(a.action, TEXT_PT * k, p.medium) + 14 * k + (24 * k if a.kind == UNDO else 0))
        font.draw(s, fit(a.lead, font, TEXT_PT * k, p.medium, right - pen), pen, base, TEXT_PT * k, ink, p.medium)
        pen += font.measure(a.lead, TEXT_PT * k, p.medium) + 6 * k
        if a.text != "" and pen < right:
            font.draw(s, fit(a.text, font, TEXT_PT * k, p.regular, right - pen), pen, base, TEXT_PT * k, ink2, p.regular)
        if a.action != "":  # the action as a small pill at the right end
            var aw = font.measure(a.action, TEXT_PT * k, p.medium) + 14 * k
            var ax = x + w - PAD * k - aw - (24 * k if a.kind == UNDO else 0)
            rect(s, ax, y + 5 * k, aw, h - 10 * k, blend(p.raised, p.card, alpha), (h - 10 * k) / 2)
            font.draw(s, a.action, ax + aw / 2, base, TEXT_PT * k, tone, p.medium, CENTRE)
            if a.kind == UNDO and a.seconds > 0:  # the countdown: a ring that empties
                var left = 1.0 - min(Float64(t - self.since) / 1e9 / a.seconds, 1.0)
                var rx = x + w - PAD * k - 8 * k
                var steps = Int(36.0 * left)
                for i in range(steps):
                    var u = -pi / 2 + Float64(i) / 36.0 * 2.0 * pi
                    circle(s, rx + cos(u) * 6 * k, cy + sin(u) * 6 * k, 1.1 * k, tone)
        if a.kind == RUNNING and a.progress >= 0:  # the share done: a thin bar along the capsule's foot
            var bw = (w - h) * min(a.progress, 1.0)
            rect(s, x + h / 2, y + h - 3.5 * k, w - h, 2 * k, blend(p.raised, p.line, alpha), 1 * k)
            rect(s, x + h / 2, y + h - 3.5 * k, bw, 2 * k, tone, 1 * k)


def fit(text: String, font: Font, size: Float64, weight: Int, room: Float64) -> String:
    """`text`, cut with "…" to fit `room` pixels."""
    if font.measure(text, size, weight) <= room:
        return text
    var chars = List[String]()
    for c in text.codepoints():
        chars.append(String(c))
    while len(chars) > 1:
        _ = chars.pop()
        var cut = String("").join(chars)
        if font.measure(cut + "…", size, weight) <= room:
            return cut + "…"
    return "…"


def IslandView(id: Int, version: Int, on_tap: Int, on_frame: Int = NO_MSG) -> View:
    """The island's canvas (its size is fixed: ISLAND_W × ISLAND_H points). Pass on_frame while island.wants_frames()."""
    return Canvas(id, version, on_gesture=on_tap, on_frame=on_frame).width(ISLAND_W).height(ISLAND_H).tag("island")
