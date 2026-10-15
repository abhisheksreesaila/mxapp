# Kitchen sink: every component added in goal 4, in four tabs plus a details screen.
# The same file runs on Linux (GTK), the web, Mac (AppKit) and iPhone (UIKit).

from mojoui import (
    App, Event, View, VStack, HStack, Text, Button, Segmented, Radio, TextArea, Alert, Tabs, NavBar,
    DatePicker, Icon, Grid, LazyList, Divider, TITLE, HEADLINE, CAPTION, PROMINENT, DESTRUCTIVE,
)

comptime TAB = 1
comptime PERIOD = 2
comptime SIZE = 3
comptime NOTES = 4
comptime DATE_CHANGED = 5
comptime ASK = 6
comptime ANSWER = 7
comptime OPEN = 8
comptime BACK = 9
comptime ROW = 10
comptime ROWS_LIST = 1
comptime BUMP = 11


def times(n: Int) -> String:
    return String(n) + (" time" if n == 1 else " times")


struct Main(App):
    var tab: Int
    var period: Int
    var size: Int
    var notes: String
    var date: String
    var asking: Bool
    var deleted: Int
    var in_details: Bool
    var details_opened: Int
    var tapped: Int
    var bumped: Int

    def __init__(out self):
        self.tab = 0
        self.period = 0
        self.size = 1
        self.notes = ""
        self.date = "2026-10-15"
        self.asking = False
        self.deleted = 0
        self.in_details = False
        self.details_opened = 0
        self.tapped = -1
        self.bumped = 0

    def title(self) -> String:
        return "Kitchen sink"

    def update(mut self, event: Event):
        var m = event.message
        if m == TAB:
            self.tab = event.number
        elif m == PERIOD:
            self.period = event.number
        elif m == SIZE:
            self.size = event.number
        elif m == NOTES:
            self.notes = event.text
        elif m == DATE_CHANGED:
            self.date = event.text
        elif m == ASK:
            self.asking = True
        elif m == ANSWER:
            self.asking = False
            if event.number == 1:  # "Delete"
                self.deleted += 1
        elif m == OPEN:
            self.in_details = True
            self.details_opened += 1
        elif m == BACK:
            self.in_details = False
        elif m == ROW:
            self.tapped = event.number
        elif m == BUMP:
            self.bumped += 1

    def row(self, list_id: Int, index: Int) -> String:
        var text = "Row " + String(index) + " · " + String(index * index % 997) + " points"
        if index == 0:
            text += " · bumped " + String(self.bumped)
        return text

    def lines(self) -> Int:
        if self.notes == "":
            return 0
        return len(self.notes.split("\n"))

    def view(self) -> View:
        var periods: List[String] = ["Day", "Week", "Month"]
        var sizes: List[String] = ["Small", "Medium", "Large"]
        var sections: List[String] = ["Choices", "Text", "More", "List"]
        var summary = (
            periods[self.period] + " · " + sizes[self.size] + " · " + String(self.lines()) + " lines · " + self.date
            + " · deleted " + String(self.deleted) + " · details " + String(self.details_opened)
            + " · row " + (String(self.tapped) if self.tapped >= 0 else "-")
        )
        if self.in_details:
            return VStack(
                NavBar("Details", on_back=BACK),
                Text("This is the details screen."),
                Text(summary, style=CAPTION),
                spacing=20,
            )
        var body: View
        if self.tab == 0:
            body = VStack(
                Text("Period"),
                Segmented(periods, self.period, on_select=PERIOD),
                Text("Size"),
                Radio(sizes, self.size, on_select=SIZE),
                Text("Period: " + periods[self.period] + " · Size: " + sizes[self.size], style=CAPTION),
                Button("Open details", on_tap=OPEN),
                spacing=12,
            )
        elif self.tab == 1:
            var chars = self.notes.byte_length()
            body = VStack(
                TextArea(self.notes, placeholder="Notes", on_change=NOTES, height=140),
                Text(String(self.lines()) + " lines, " + String(chars) + " characters", style=CAPTION),
                spacing=12,
            )
        elif self.tab == 2:
            var cells = List[View]()
            for i in range(6):
                cells.append(Text("Cell " + String(i + 1)))
            var parts = List[View]()
            parts.append(DatePicker(self.date, on_change=DATE_CHANGED))
            parts.append(Text("Date: " + self.date, style=CAPTION))
            parts.append(HStack(Icon("star"), Icon("trash"), Icon("gear"), spacing=16))
            parts.append(Grid(cells, 3))
            parts.append(Divider())
            parts.append(Button("Delete everything", on_tap=ASK, style=DESTRUCTIVE))
            parts.append(Text("Deleted " + times(self.deleted), style=CAPTION))
            parts.append(Text("Details opened " + times(self.details_opened), style=CAPTION))
            if self.asking:
                var buttons: List[String] = ["Cancel", "Delete"]
                parts.append(Alert("Delete everything?", "This can't be undone.", buttons, on_choose=ANSWER))
            body = VStack(parts, spacing=12)
        else:
            body = VStack(
                LazyList(10000, ROWS_LIST, on_tap=ROW, height=320),
                Button("Bump row 0", on_tap=BUMP),
                Text("Tapped row " + (String(self.tapped) if self.tapped >= 0 else "none"), style=CAPTION),
                spacing=12,
            )
        return VStack(
            Text("Kitchen sink", style=TITLE),
            Text(summary, style=CAPTION),
            Tabs(sections, self.tab, on_select=TAB),
            body,
            spacing=16,
        )
