# TodoMojo: a real little todo app. The same file runs on Linux (GTK), the web
# (FastHTML), Mac (AppKit) and iPhone (UIKit), each with its own native controls.

from mojoui import (
    App, Event, View, VStack, HStack, Text, Button, TextField, Toggle, Dropdown, ProgressBar, Scroll,
    TITLE, CAPTION, PROMINENT, DESTRUCTIVE, BETWEEN,
)

comptime DRAFT = 1  # typing in the field
comptime ADD = 2  # Add button or Return
comptime FILTER = 3  # All / Active / Done
comptime CLEAR_DONE = 4
comptime TICK = 1_000_000  # TICK + task id (ids stay below a million)
comptime REMOVE = 2_000_000  # REMOVE + task id

comptime ALL = 0
comptime ACTIVE = 1
comptime DONE = 2


@fieldwise_init
struct Task(Copyable, Movable):
    var id: Int
    var title: String
    var done: Bool


struct Main(App):
    var tasks: List[Task]
    var draft: String
    var filter: Int
    var next_id: Int

    def __init__(out self):
        self.tasks = List[Task]()
        self.draft = ""
        self.filter = ALL
        self.next_id = 1

    def title(self) -> String:
        return "TodoMojo"

    def update(mut self, event: Event):
        var m = event.message
        if m == DRAFT:
            self.draft = event.text
        elif m == ADD:
            # Return in the field carries its text; the Add button uses the draft.
            var title = String((event.text if event.text != "" else self.draft).strip())
            if title != "":
                self.tasks.append(Task(self.next_id, title, False))
                self.next_id += 1
            self.draft = ""
        elif m == FILTER:
            self.filter = event.number
        elif m == CLEAR_DONE:
            var kept = List[Task]()
            for t in self.tasks:
                if not t.done:
                    kept.append(t.copy())
            self.tasks = kept^
        elif m >= REMOVE:
            for i in range(len(self.tasks)):
                if self.tasks[i].id == m - REMOVE:
                    _ = self.tasks.pop(i)
                    break
        elif m >= TICK:
            for i in range(len(self.tasks)):
                if self.tasks[i].id == m - TICK:
                    self.tasks[i].done = event.number == 1

    def view(self) -> View:
        var rows = List[View]()
        var done = 0
        for t in self.tasks:
            if t.done:
                done += 1
            if self.filter == ALL or (self.filter == ACTIVE and not t.done) or (self.filter == DONE and t.done):
                rows.append(
                    HStack(Toggle(t.title, t.done, on_toggle=TICK + t.id).grow(), Button("Remove", on_tap=REMOVE + t.id), spacing=12).fill()
                )
        if len(rows) == 0:
            rows.append(Text("Nothing here yet", style=CAPTION))
        var left = len(self.tasks) - done
        var percent = 0 if len(self.tasks) == 0 else done * 100 // len(self.tasks)
        var filters: List[String] = ["All", "Active", "Done"]
        return VStack(
            Text("Todo", style=TITLE),
            HStack(
                TextField(self.draft, placeholder="What needs doing?", on_change=DRAFT, on_submit=ADD).grow(),
                Button("Add", on_tap=ADD, style=PROMINENT),
            ).fill(),
            HStack(Text("Show"), Dropdown(filters, self.filter, on_select=FILTER)).justify(BETWEEN).fill(),
            Scroll(VStack(rows, spacing=8).fill(), height=260).fill(),
            HStack(
                Text(String(left) + " left · " + String(done) + " done", style=CAPTION),
                Button("Clear done", on_tap=CLEAR_DONE, style=DESTRUCTIVE),
            ).justify(BETWEEN).fill(),
            ProgressBar(percent).fill(),
            spacing=16,
        ).padding(8).width(340)
