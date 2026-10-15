# HelloMojo: the whole app. The same file runs on Linux (GTK), Mac (AppKit) and
# iPhone (UIKit); each platform draws it with its own native controls.

from mojoui import App, Event, View, VStack, Text, Button, TITLE, CAPTION, PROMINENT

comptime GREET = 1


struct Main(App):
    var name: String
    var clicks: Int

    def __init__(out self):
        self.name = "Ada"
        self.clicks = 0

    def title(self) -> String:
        return "HelloMojo"

    def update(mut self, event: Event):
        if event.message == GREET:
            self.clicks += 1

    def view(self) -> View:
        var greeting = "Tap Greet" if self.clicks == 0 else "Hello, " + self.name + "! (click " + String(self.clicks) + ")"
        return VStack(
            Text("mojo-ui · hello", style=CAPTION),
            Text(greeting, style=TITLE),
            Button("Greet", on_tap=GREET, style=PROMINENT),
            Text("Every line of this app is Mojo.", style=CAPTION),
            spacing=20,
        )
