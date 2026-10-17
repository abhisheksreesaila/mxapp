# mojoui.sheetchrome: the frame around a spreadsheet, as in Numbers: a toolbar of icon-over-label tools,
# sheet tabs, a formula bar and a status bar. Built from native controls, so every host that has them draws it.

from mojoui.view import (View, Text, Button, TextField, Tabs, HStack, VStack, Spacer, CAPTION, TOOL, TOOL_ON, ICON_ONLY,
                         SUBTLE, CENTER, NO_MSG)


@fieldwise_init
struct Tool(Copyable, Movable):
    """One toolbar button: its title, Lucide icon name, message, and whether it's the active tool."""

    var title: String
    var icon: String
    var message: Int
    var on: Bool


def tool_views(tools: List[Tool]) -> List[View]:
    var out = List[View]()
    for t in tools:
        out.append(Button(t.title, t.message, TOOL_ON if t.on else TOOL, icon=t.icon))
    return out^


def Toolbar(left: List[Tool], middle: List[Tool], right: List[Tool], extra: List[View] = []) -> View:
    """Three groups, as in Numbers: view controls on the left, insert tools in the middle, organise and
    format on the right. `extra` (a status chip, say) sits at the far right."""
    var items = tool_views(left)
    items.append(Spacer())
    for v in tool_views(middle):
        items.append(v.copy())
    items.append(Spacer())
    for v in tool_views(right):
        items.append(v.copy())
    for v in extra:
        items.append(v.copy())
    return HStack(items^, spacing=2).fill().align(CENTER).padding(4, 10).tag("toolbar")


def SheetTabs(names: List[String], selected: Int, on_select: Int, on_add: Int) -> View:
    """The sheets of a document, with + to add one."""
    return HStack(Tabs(names, selected, on_select), Button("Add sheet", on_add, ICON_ONLY, icon="plus"), Spacer(),
                  spacing=4).fill().align(CENTER).padding(0, 12).tag("sheet-tabs")


def FormulaBar(cell: String, text: String, on_submit: Int, on_cancel: Int = NO_MSG) -> View:
    """ƒx, the selected cell's name, and its value or formula (Enter writes it, Escape puts it back)."""
    return HStack(Text("ƒx").tone(4), Text(cell, CAPTION).width(72),
                  TextField(text, placeholder="Value or =formula", on_submit=on_submit, on_cancel=on_cancel).grow(),
                  spacing=10).fill().align(CENTER).padding(4, 12).tag("formula-bar")


def StatusBar(items: List[String], right: String = "") -> View:
    """Small facts about the selection and the engine, along the bottom of the window."""
    var views = List[View]()
    for t in items:
        views.append(Text(t, CAPTION))
    views.append(Spacer())
    if right != "":
        views.append(Text(right, CAPTION))
    return HStack(views^, spacing=18).fill().align(CENTER).padding(4, 14).tag("status-bar")
