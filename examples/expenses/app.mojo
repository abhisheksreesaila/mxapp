# Pocket Expenses: a small but real app using every kind of component, from one
# Mojo file: tabs, a navigation stack, text field + text area, segmented choice,
# date picker, a 5,000-row list that only draws what's on screen, an alert to
# confirm deleting, icons and a grid. Runs on Linux, the web, Mac and iPhone.

from mojoui import (
    App, Event, View, VStack, HStack, Text, Button, TextField, TextArea, Segmented, DatePicker, Tabs, NavBar,
    LazyList, Alert, Icon, Grid, ProgressBar, Divider, TITLE, HEADLINE, CAPTION, PROMINENT, DESTRUCTIVE,
)

comptime TAB = 1
comptime AMOUNT = 2
comptime CATEGORY = 3
comptime DATE_SET = 4
comptime NOTE = 5
comptime ADD = 6
comptime OPEN = 7
comptime BACK = 8
comptime ASK_DELETE = 9
comptime CONFIRM = 10
comptime HISTORY = 1  # the LazyList's id
comptime SEED = 5000


@fieldwise_init
struct Expense(Copyable, Movable):
    var id: Int
    var cents: Int
    var category: Int
    var date: String
    var note: String


def categories() -> List[String]:
    return ["Food", "Travel", "Home", "Fun"]


def category_icon(c: Int) -> String:
    var icons: List[String] = ["food", "travel", "home", "fun"]
    return icons[c]


def money(cents: Int) -> String:
    """$1,234.50"""
    var whole = String(cents // 100)
    var grouped = String("")
    var n = whole.byte_length()
    for i in range(n):
        if i > 0 and (n - i) % 3 == 0:
            grouped += ","
        grouped += String(whole[byte = i : i + 1])
    var c = cents % 100
    return "$" + grouped + "." + ("0" if c < 10 else "") + String(c)


def parse_cents(text: String) -> Int:
    """ "12.5", "$12.50" or "1,234.50" → cents; -1 if it isn't a sensible amount (max $9,999,999.99)."""
    var cents = 0
    var digits = 0
    var decimals = -1
    var since_comma = -1  # digits since the last comma (-1: no comma yet)
    for byte in String(text.strip()).as_bytes():
        var b = Int(byte)
        if b == ord("$") and digits == 0 and decimals < 0:
            continue
        if b == ord(","):  # only as a thousands separator: 1,234 or 12,345
            if decimals >= 0 or digits == 0 or (since_comma >= 0 and since_comma != 3) or (since_comma < 0 and digits > 3):
                return -1
            since_comma = 0
            continue
        if b == ord("."):
            if decimals >= 0 or (since_comma >= 0 and since_comma != 3):
                return -1
            decimals = 0
        elif ord("0") <= b <= ord("9"):
            if decimals >= 2 or (decimals < 0 and digits >= 7):
                return -1
            cents = cents * 10 + b - ord("0")
            if decimals >= 0:
                decimals += 1
            else:
                digits += 1
                if since_comma >= 0:
                    since_comma += 1
        else:
            return -1
    if digits == 0 and decimals <= 0:
        return -1
    if decimals < 0 and since_comma >= 0 and since_comma != 3:
        return -1
    if decimals <= 0:
        cents *= 100
    elif decimals == 1:
        cents *= 10
    return cents if cents > 0 else -1


def two(n: Int) -> String:
    return ("0" if n < 10 else "") + String(n)


struct Main(App):
    var expenses: List[Expense]  # oldest first; shown newest first
    var next_id: Int
    var tab: Int
    var amount: String
    var category: Int
    var date: String
    var note: String
    var status: String
    var open_id: Int  # the expense on the detail screen (-1: none)
    var confirming: Bool

    def __init__(out self):
        self.expenses = List[Expense](capacity=SEED + 16)
        var seed = 12345
        for i in range(SEED):  # a year of believable sample data
            seed = (seed * 1103515245 + 12345) % 2147483648
            var month = 1 + i * 9 // SEED
            var day = 1 + (seed // 7) % 28
            var cat = (seed // 97) % 4
            var cents = 200 + (seed // 13) % (6000 if cat != 1 else 14000)
            self.expenses.append(Expense(i + 1, cents, cat, "2026-" + two(month) + "-" + two(day), ""))
        self.next_id = SEED + 1
        self.tab = 0
        self.amount = ""
        self.category = 0
        self.date = "2026-10-15"
        self.note = ""
        self.status = "Track what you spend: everything here is Mojo."
        self.open_id = -1
        self.confirming = False

    def title(self) -> String:
        return "Pocket Expenses"

    def find(self, id: Int) -> Int:
        for i in range(len(self.expenses) - 1, -1, -1):
            if self.expenses[i].id == id:
                return i
        return -1

    def update(mut self, event: Event):
        var m = event.message
        if m == TAB:
            self.tab = event.number
        elif m == AMOUNT:
            self.amount = event.text
        elif m == CATEGORY:
            self.category = event.number
        elif m == DATE_SET:
            self.date = event.text
        elif m == NOTE:
            self.note = event.text
        elif m == ADD:
            var cents = parse_cents(event.text if event.text != "" else self.amount)
            if cents < 0:
                self.status = "Enter an amount like 12.50"
                return
            self.expenses.append(Expense(self.next_id, cents, self.category, self.date, String(self.note.strip())))
            self.next_id += 1
            self.status = "Added " + money(cents) + " · " + categories()[self.category]
            self.amount = ""
            self.note = ""
        elif m == OPEN:  # event.number = row (newest first)
            var i = len(self.expenses) - 1 - event.number
            if 0 <= i < len(self.expenses):
                self.open_id = self.expenses[i].id
        elif m == BACK:
            self.open_id = -1
            self.confirming = False
        elif m == ASK_DELETE:
            self.confirming = True
        elif m == CONFIRM:
            self.confirming = False
            if event.number == 1:  # "Delete"
                var i = self.find(self.open_id)
                if i >= 0:
                    _ = self.expenses.pop(i)
                self.open_id = -1

    def row(self, list_id: Int, index: Int) -> String:
        var i = len(self.expenses) - 1 - index  # newest first
        if i < 0 or i >= len(self.expenses):
            return ""
        ref e = self.expenses[i]
        var text = e.date + " · " + categories()[e.category] + " · " + money(e.cents)
        if e.note != "":
            text += " · " + e.note
        return text

    def view(self) -> View:
        var cats = categories()
        if self.open_id >= 0:
            var i = self.find(self.open_id)
            if i >= 0:
                ref e = self.expenses[i]
                var parts = List[View]()
                parts.append(NavBar("Expense", on_back=BACK))
                parts.append(Icon(category_icon(e.category), size=40))
                parts.append(Text(money(e.cents), style=TITLE))
                parts.append(Text(cats[e.category] + " · " + e.date, style=HEADLINE))
                parts.append(Text(e.note if e.note != "" else "No note", style=CAPTION))
                parts.append(Button("Delete", on_tap=ASK_DELETE, style=DESTRUCTIVE))
                if self.confirming:
                    var buttons: List[String] = ["Cancel", "Delete"]
                    parts.append(Alert("Delete this expense?", money(e.cents) + " · " + cats[e.category], buttons, on_choose=CONFIRM))
                return VStack(parts, spacing=16)
        var sections: List[String] = ["Add", "History", "Insights"]
        var body: View
        if self.tab == 0:
            body = VStack(
                TextField(self.amount, placeholder="Amount", on_change=AMOUNT, on_submit=ADD),
                Segmented(cats, self.category, on_select=CATEGORY),
                DatePicker(self.date, on_change=DATE_SET),
                TextArea(self.note, placeholder="Note", on_change=NOTE, height=90),
                Button("Add expense", on_tap=ADD, style=PROMINENT),
                Text(self.status, style=CAPTION),
                spacing=14,
            )
        elif self.tab == 1:
            var latest = String("No expenses yet")
            if len(self.expenses) > 0:
                latest = "Latest: " + self.row(HISTORY, 0)
            body = VStack(
                Text(latest, style=CAPTION),
                LazyList(len(self.expenses), HISTORY, on_tap=OPEN, height=380),
                Text(String(len(self.expenses)) + " expenses · tap one for details", style=CAPTION),
                spacing=10,
            )
        else:
            var totals = List[Int](length=4, fill=0)
            var all = 0
            for e in self.expenses:
                totals[e.category] += e.cents
                all += e.cents
            var cards = List[View]()
            var biggest = 0
            for c in range(4):
                if totals[c] > totals[biggest]:
                    biggest = c
                cards.append(VStack(Icon(category_icon(c), size=28), Text(cats[c], style=HEADLINE), Text(money(totals[c]), style=CAPTION), spacing=6))
            var share = 0 if all == 0 else totals[biggest] * 100 // all
            body = VStack(
                Grid(cards, 2, spacing=20),
                Divider(),
                Text("Total: " + money(all) + " across " + String(len(self.expenses)) + " expenses", style=HEADLINE),
                Text("Biggest: " + cats[biggest] + " (" + String(share) + "%)", style=CAPTION),
                ProgressBar(share),
                spacing=14,
            )
        return VStack(
            Text("Pocket Expenses", style=TITLE),
            Tabs(sections, self.tab, on_select=TAB),
            body,
            spacing=16,
        )
