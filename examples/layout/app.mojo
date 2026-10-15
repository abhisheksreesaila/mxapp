# Layout: every layout setting, with tagged boxes the checker measures on each host.
# The settings are flexbox names; each platform's own layout system does the work.

from mojoui import (
    App, Event, View, VStack, HStack, Text, Button, Tabs, Scroll, TITLE, CAPTION, PROMINENT,
    START, CENTER, END, STRETCH, BETWEEN,
)

comptime TAB = 1


def row(l: String, r: String, how: Int, name: String) -> View:
    """A 320-wide row of two short labels, justified `how`."""
    return HStack(Text("L").tag(l), Text("R").tag(r)).justify(how).width(320).tag(name)


def column(child: String, how: Int, name: String) -> View:
    """A 320-wide column with one short label, aligned `how`."""
    return VStack(Text("short").tag(child)).align(how).width(320).tag(name)


struct Main(App):
    var tab: Int

    def __init__(out self):
        self.tab = 0

    def title(self) -> String:
        return "Layout"

    def update(mut self, event: Event):
        if event.message == TAB:
            self.tab = event.number

    def view(self) -> View:
        var tabs: List[String] = ["Boxes", "About"]
        if self.tab == 1:
            return VStack(
                Tabs(tabs, self.tab, on_select=TAB),
                Text("Padding, sizes, fill, grow, justify and align: flexbox names, native layout.").max_width(300),
            )
        return VStack(
            Tabs(tabs, self.tab, on_select=TAB),
            Text("Layout", style=TITLE),
            # padding
            VStack(Text("Padded").tag("pad_child")).padding(16).width(300).align(START).tag("pad_box"),
            # sizes
            Button("Fixed", on_tap=0).width(200).height(60).tag("fixed"),
            Text("A long sentence that wraps because its maximum width is limited.").max_width(200).tag("maxw"),
            Text("x").min_width(150).tag("minw"),
            VStack(Text("short").fill().max_width(200).tag("fm_c")).width(320).tag("fm_col"),
            # fill
            VStack(Button("Fill", on_tap=0, style=PROMINENT).fill().tag("fill_child")).padding(10).width(320).tag("fill_box"),
            # grow
            HStack(Text("Label").tag("g_a"), Button("Grow", on_tap=0).grow().tag("g_b"), spacing=8).width(320).tag("grow_row"),
            # justify
            row("js_l", "js_r", START, "js_row"),
            row("jc_l", "jc_r", CENTER, "jc_row"),
            row("je_l", "je_r", END, "je_row"),
            row("jb_l", "jb_r", BETWEEN, "jb_row"),
            # align
            column("as_c", START, "as_col"),
            column("ac_c", CENTER, "ac_col"),
            column("ae_c", END, "ae_col"),
            column("ast_c", STRETCH, "ast_col"),
            spacing=10,
        )
