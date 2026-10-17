# mojoui.finding: what an agent noticed, as a card: a title, what it is (with the rows behind it), and what
# you can do about it. Warning tone while it's open, the good tone once it's resolved.
#
#   FindingCard("Agent noticed", "3 spellings of one customer…", ["Merge into “Acme Corp”", "Show the rows"],
#               [MERGE, SHOW_ROWS], note="or fix the cells by hand", again=FIND)

from mojoui.view import (View, Text, Button, Card, HStack, Spacer, HEADLINE, CAPTION, PROMINENT, SUBTLE, CARD_WARN, CARD_GOOD,
                         TONE_WARN, TONE_GOOD, NO_MSG)


def FindingCard(title: String, text: String, actions: List[String] = [], messages: List[Int] = [], note: String = "",
                resolved: Bool = False, again: Int = NO_MSG, again_title: String = "Look again") -> View:
    """actions/messages: buttons (the first is the main one). again: a quiet button that asks the agent to look again."""
    var head = HStack(Text(title, style=HEADLINE).tone(TONE_GOOD if resolved else TONE_WARN), Spacer(),
                      Button(again_title, on_tap=again, style=SUBTLE) if again != NO_MSG else Spacer(), spacing=8).fill().height(32)
    var buttons = List[View]()
    for k in range(min(len(actions), len(messages))):
        buttons.append(Button(actions[k], on_tap=messages[k], style=PROMINENT if k == 0 else SUBTLE))
    if len(buttons) > 0 and note != "":
        return Card(head^, Text(text).tag("finding"), HStack(buttons, spacing=8), Text(note, style=CAPTION), spacing=8,
                    tone=CARD_GOOD if resolved else CARD_WARN)
    if len(buttons) > 0:
        return Card(head^, Text(text).tag("finding"), HStack(buttons, spacing=8), spacing=8, tone=CARD_GOOD if resolved else CARD_WARN)
    return Card(head^, Text(text).tag("finding"), spacing=8, tone=CARD_GOOD if resolved else CARD_WARN)
