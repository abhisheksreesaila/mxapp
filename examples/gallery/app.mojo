# Gallery: every mojoui component, wired to a little state. Same file on every platform.

from mojoui import (
    App, Event, View, VStack, HStack, Text, Button, TextField, Toggle, Dropdown, Slider, ProgressBar, Divider,
    TITLE, HEADLINE, CAPTION, PROMINENT,
)

comptime NAME = 1
comptime RESET = 2
comptime NOTIFY = 3
comptime SIZE = 4
comptime VOLUME = 5
comptime GREET = 6


struct Main(App):
    var name: String
    var greeted: Int
    var notify: Bool
    var size: Int
    var volume: Int

    def __init__(out self):
        self.name = ""
        self.greeted = 0
        self.notify = False
        self.size = 1
        self.volume = 30

    def title(self) -> String:
        return "Gallery"

    def update(mut self, event: Event):
        if event.message == NAME:
            self.name = event.text
        elif event.message == RESET:
            self.name = ""
        elif event.message == GREET:
            self.greeted += 1
        elif event.message == NOTIFY:
            self.notify = event.number == 1
        elif event.message == SIZE:
            self.size = event.number
        elif event.message == VOLUME:
            self.volume = event.number

    def view(self) -> View:
        var sizes: List[String] = ["Small", "Medium", "Large"]
        var hello = "Type your name below" if self.name == "" else "Hello, " + self.name
        return VStack(
            Text("Components", style=TITLE),
            Text(hello, style=HEADLINE),
            HStack(
                TextField(self.name, placeholder="Your name", on_change=NAME, on_submit=GREET),
                Button("Reset", on_tap=RESET),
            ),
            Divider(),
            Toggle("Notifications", self.notify, on_toggle=NOTIFY),
            Text("Notifications are " + ("on" if self.notify else "off"), style=CAPTION),
            HStack(Text("Text size"), Dropdown(sizes, self.size, on_select=SIZE)),
            Divider(),
            Text("Volume " + String(self.volume), style=CAPTION),
            Slider(self.volume, on_change=VOLUME),
            ProgressBar(self.volume),
            Button("Say hello (" + String(self.greeted) + ")", on_tap=GREET, style=PROMINENT),
            spacing=14,
        )
