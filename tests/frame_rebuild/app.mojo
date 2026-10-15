# Test app (scripts/check M6): a frame event that changes the screen's shape.
# Playing counts frames; after 30 a Replay button appears (a rebuild) while frames keep coming.
from mojoui import App, Event, View, Surface, VStack, Text, Button, Toggle, Canvas, rgba, NO_MSG

comptime FRAME = 1
comptime PLAY = 2
comptime REPLAY = 3


struct Main(App):
    var frames: Int
    var playing: Bool
    var done: Bool

    def __init__(out self):
        self.frames = 0
        self.playing = False
        self.done = False

    def title(self) -> String:
        return "Frame rebuild"

    def update(mut self, event: Event):
        if event.message == PLAY:
            self.playing = event.number == 1
        elif event.message == FRAME and self.playing:
            self.frames += 1
            if self.frames >= 30:
                self.done = True
        elif event.message == REPLAY:
            self.frames = 0
            self.done = False
            self.playing = False

    def view(self) -> View:
        var items = List[View]()
        items.append(Text("Frames: " + String(self.frames)))
        items.append(Toggle("Play", self.playing, on_toggle=PLAY))
        if self.done:
            items.append(Button("Replay", on_tap=REPLAY))
        items.append(Canvas(0, self.frames, on_frame=FRAME if self.playing else NO_MSG).width(200).height(120))
        return VStack(items)

    def draw(mut self, canvas: Int, mut surface: Surface):
        surface.fill(rgba(self.frames * 8, 40, 120))
