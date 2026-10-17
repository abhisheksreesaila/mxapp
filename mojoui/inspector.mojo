# mojoui.inspector: a properties panel like Numbers' Format inspector. It's built from the native controls
# (Segmented, Dropdown, Toggle, Button, Text), so it runs on every host that has them.
#
#   Inspector(["Table", "Cell"], tab, ON_TAB, [
#       Section("Data format", [Dropdown(FORMATS, f, ON_FORMAT).fill(),
#                               Row("Decimals", Stepper("2", ON_LESS, ON_MORE)),
#                               Row("Thousands", Toggle("", on, ON_THOUSANDS))]),
#   ])

from mojoui.view import (View, Text, Button, Segmented, HStack, VStack, Spacer, Divider, Card, CAPTION, HEADLINE, SUBTLE,
                         ICON_ONLY, CENTER, STRETCH, START)


def Section(title: String, items: List[View]) -> View:
    """A titled group of controls (the title in small caps on the hosts that have them)."""
    var all = List[View]()
    all.append(Text(title.upper(), CAPTION))
    for v in items:
        all.append(v.copy())
    return VStack(all^, spacing=8).fill().align(START)


def Row(label: String, control: View) -> View:
    """A label on the left, its control on the right."""
    return HStack(Text(label), Spacer(), control.copy(), spacing=8).fill().align(CENTER)


def Stepper(value: String, on_less: Int, on_more: Int) -> View:
    """− value +: a number nudged one step at a time (decimal places, font size, gap)."""
    return HStack(Button("−", on_less, SUBTLE), Text(value), Button("+", on_more, SUBTLE), spacing=4).align(CENTER)


def Inspector(tabs: List[String], selected: Int, on_tab: Int, sections: List[View], width: Int = 300) -> View:
    """The panel: tabs across the top (Table · Cell · Text · Arrange), then sections divided by hairlines."""
    var all = List[View]()
    all.append(Segmented(tabs, selected, on_tab).fill())
    for k in range(len(sections)):
        if k > 0:
            all.append(Divider())
        all.append(sections[k].copy())
    return Card(all^, spacing=14).width(width).grow()
