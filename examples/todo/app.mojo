# TodoMojo: rows come and go, so the screen's structure changes on every tap.
# The same file runs on Linux (GTK), Mac (AppKit) and iPhone (UIKit).

from mojoui import App, View, VStack, HStack, Text, Button, TITLE, CAPTION, PROMINENT

comptime ADD = 1
comptime REMOVE = 1000  # REMOVE + task number


struct Main(App):
    var tasks: List[Int]  # task numbers, in order
    var next: Int

    def __init__(out self):
        self.tasks = List[Int]()
        self.next = 1

    def title(self) -> String:
        return "TodoMojo"

    def update(mut self, message: Int):
        if message == ADD:
            self.tasks.append(self.next)
            self.next += 1
        elif message > REMOVE:
            for i in range(len(self.tasks)):
                if self.tasks[i] == message - REMOVE:
                    _ = self.tasks.pop(i)
                    break

    def view(self) -> View:
        var rows = List[View]()
        for t in self.tasks:
            rows.append(HStack(Text("Task " + String(t)), Button("Remove", on_tap=REMOVE + t), spacing=12))
        var n = len(self.tasks)
        var count = "No tasks yet" if n == 0 else ("1 task" if n == 1 else String(n) + " tasks")
        return VStack(
            Text("Todo", style=TITLE),
            Text(count, style=CAPTION),
            VStack(rows, spacing=8),
            Button("Add task", on_tap=ADD, style=PROMINENT),
            spacing=20,
        )
