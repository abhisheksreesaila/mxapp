# Tests for Canvas, gestures, frames and draw(). Run: pixi run mojo run -I . tests/test_canvas.mojo
from std.testing import assert_equal, assert_true, assert_false

from mojoui import *

comptime GESTURE = 1
comptime FRAME = 2
comptime PLAY = 3


struct Painter(App):
    """Paints its colour; drags move an offset; frames count up while playing."""

    var version: Int
    var offset_x: Float64
    var zoom: Float64
    var frames: Int
    var playing: Bool
    var drawn_at: String  # set by draw(), shown on screen

    def __init__(out self):
        self.version = 0
        self.offset_x = 0
        self.zoom = 1
        self.frames = 0
        self.playing = False
        self.drawn_at = "never"

    def title(self) -> String:
        return "Painter"

    def update(mut self, event: Event):
        if event.message == GESTURE and event.number == PAN:
            self.offset_x += event.dx
            self.version += 1
        elif event.message == GESTURE and event.number == ZOOM:
            self.zoom *= event.zoom
            self.version += 1
        elif event.message == FRAME:
            self.frames += 1
            self.version += 1
        elif event.message == PLAY:
            self.playing = not self.playing

    def view(self) -> View:
        return VStack(
            Text("drawn at " + self.drawn_at),
            Canvas(7, self.version, on_gesture=GESTURE, on_frame=FRAME if self.playing else NO_MSG).grow().fill(),
            Button("Play", on_tap=PLAY),
        )

    def draw(mut self, canvas: Int, mut surface: Surface):
        surface.fill(rgba(10, 20, 30))
        surface.set(0, 0, rgba(255, 0, 0))
        self.drawn_at = String(surface.width) + "x" + String(surface.height)


def test_canvas_node_records_id_version_and_messages() raises:
    var v = Canvas(7, 3, on_gesture=GESTURE, on_frame=FRAME)
    assert_equal(v.nodes[0].kind, CANVAS)
    assert_equal(v.nodes[0].style, 7)
    assert_equal(v.nodes[0].value, 3)
    assert_equal(v.nodes[0].msg, GESTURE)
    assert_equal(v.nodes[0].msg2, FRAME)


def test_surface_set_get_fill_and_points() raises:
    var buf = List[UInt32](length=6, fill=0)
    var s = Surface(Int(buf.unsafe_ptr()), 3, 2, 2.0)
    s.fill(rgba(1, 2, 3))
    s.set(2, 1, rgba(255, 0, 0, 128))
    s.set(5, 5, rgba(9, 9, 9))  # outside: ignored
    assert_equal(buf[0], UInt32(0xFF030201))
    assert_equal(buf[5], UInt32(0x800000FF))
    assert_equal(s.get(2, 1), UInt32(0x800000FF))
    assert_equal(s.get(-1, 0), UInt32(0))
    assert_equal(s.points_width(), 1.5)
    assert_equal(s.points_height(), 1.0)
    _ = len(buf)


def test_draw_paints_and_refreshes_the_rest_of_the_screen() raises:
    var rt = Runtime(Painter())
    var buf = List[UInt32](length=4 * 3, fill=0)
    var s = Surface(Int(buf.unsafe_ptr()), 4, 3, 1.0)
    var d = rt.draw(2, s)  # node 2 is the canvas (0 = VStack, 1 = Text)
    assert_equal(buf[0], rgba(255, 0, 0))
    assert_equal(buf[11], rgba(10, 20, 30))
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 1)
    assert_equal(d.patches[0], Patch(SET_TEXT, 1, "drawn at 4x3", 0))
    var none = rt.draw(1, s)  # not a canvas: nothing drawn or changed
    assert_equal(len(none.patches), 0)
    _ = len(buf)


def test_gestures_carry_position_and_change_version_as_a_patch() raises:
    var rt = Runtime(Painter())
    var d = rt.gesture(2, PAN, 10, 20, 15.5, -3, 1)
    assert_equal(rt.app.offset_x, 15.5)
    assert_false(d.rebuild)
    assert_equal(len(d.patches), 1)
    assert_equal(d.patches[0], Patch(SET_VALUE, 2, "", 1))  # version 0 → 1: redraw
    _ = rt.gesture(2, ZOOM, 50, 50, 0, 0, 2.5)
    assert_equal(rt.app.zoom, 2.5)
    var ignored = rt.gesture(1, PAN, 0, 0, 5, 5, 1)  # a label, not a canvas
    assert_equal(len(ignored.patches), 0)
    assert_equal(rt.app.offset_x, 15.5)


def test_frames_only_while_asked_for_and_starting_them_is_a_patch() raises:
    var rt = Runtime(Painter())
    var idle = rt.frame(2, 16_000)
    assert_equal(rt.app.frames, 0)  # no on_frame: no frame events
    assert_equal(len(idle.patches), 0)
    var start = rt.dispatch(PLAY)
    assert_false(start.rebuild)  # starting frames doesn't rebuild the window
    assert_equal(len(start.patches), 1)
    assert_equal(start.patches[0], Patch(SET_FRAMES, 2, "", FRAME))
    _ = rt.frame(2, 16_000)
    _ = rt.frame(2, 17_000)
    assert_equal(rt.app.frames, 2)
    var stop = rt.dispatch(PLAY)
    assert_equal(stop.patches[0], Patch(SET_FRAMES, 2, "", 0))


def test_events_default_their_pointer_fields() raises:
    var e = Event(5, "x", 1)
    assert_equal(e.x, 0.0)
    assert_equal(e.dx, 0.0)
    assert_equal(e.zoom, 1.0)


def test_window_size_defaults() raises:
    var rt = Runtime(Painter())
    assert_equal(rt.app.window_size()[0], 480)


def main() raises:
    test_canvas_node_records_id_version_and_messages()
    test_surface_set_get_fill_and_points()
    test_draw_paints_and_refreshes_the_rest_of_the_screen()
    test_gestures_carry_position_and_change_version_as_a_patch()
    test_frames_only_while_asked_for_and_starting_them_is_a_patch()
    test_events_default_their_pointer_fields()
    test_window_size_defaults()
    print("CANVAS TESTS PASSED")
