# mojoui.chartask: a phrase that edits a chart's spec (goal 28 M2, D-255): "top 3, unpaid, as a line", "average by
# region", "only West, smallest first". A keyword reader, not a model: it knows the spec's words (sum, average, count;
# largest first, smallest first, A to Z; top N; bars, a line) and the table's own (its column names, a Yes/No column's
# name and "un…"/"not …", a text column's values). It says what it understood and what it skipped, and changes nothing
# when it understood nothing. An agent (AG-UI) can later write the same sentence.
#
#   var said = ask(chart, sheet, "top 3, unpaid, as a line")   # said.understood, said.skipped, said.changed (slots)

from mojoui.sheet import Sheet, TEXT, BOOL
from mojoui.sheetpage import (SheetObject, COMBINE_SUM, COMBINE_AVERAGE, COMBINE_COUNT, COMBINE_MEDIAN, COMBINE_P90, ORDER_TABLE, ORDER_LARGEST, ORDER_SMALLEST, ORDER_AZ,
                              CHART_BAR, CHART_LINE, SLOT_COMBINE, SLOT_VALUE, SLOT_GROUP, SLOT_ORDER, SLOT_TOP, SLOT_FILTER, SLOT_MARK,
                              FILTER_WORDS, SLOTS, number_columns, text_columns, slot_text)

comptime QUIET: List[String] = ["of", "the", "a", "an", "and", "show", "me", "please", "with", "for", "in", "on", "to", "as", "chart",
                                "only", "just", "make", "it", "per", "each", "into", "then", "now", "values", "value"]
comptime NUMBERS: List[String] = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]


@fieldwise_init
struct AskResult(Copyable, Movable):
    var understood: List[String]  # what it took, in the phrase's order ("top 3", "unpaid", "as a line")
    var skipped: List[String]  # the words it couldn't use
    var changed: List[Int]  # the sentence's slots that changed (SLOT_*), each once


def words_of(phrase: String) -> List[String]:
    """Lower-case words: commas, full stops and semicolons are breaks; "a-z" stays one word."""
    var out = List[String]()
    var cur = String("")
    for ch in phrase.lower().codepoint_slices():
        var c = String(ch)
        if c == " " or c == "," or c == ";" or c == "." or c == "\t" or c == "!" or c == "?":
            if cur != "":
                out.append(cur)
            cur = ""
        else:
            cur += c
    if cur != "":
        out.append(cur)
    return out^


def joined(words: List[String], at: Int, n: Int) -> String:
    """Words at … at+n-1 with single spaces ("" past the end)."""
    if at + n > len(words):
        return ""
    var out = words[at]
    for k in range(at + 1, at + n):
        out += " " + words[k]
    return out


def number_word(w: String) -> Int:
    """ "3" or "three" → 3; -1 if it isn't one."""
    var names = materialize[NUMBERS]()
    for k in range(len(names)):
        if names[k] == w:
            return k
    try:
        var n = Int(w)
        return n if 0 < n <= 1000 else -1
    except:
        return -1


def mark(mut said: AskResult, slot: Int):
    for s in said.changed:
        if s == slot:
            return
    said.changed.append(slot)


def table_word(mut spec: SheetObject, sheet: Sheet, w: List[String], i: Int, mut said: AskResult) -> Tuple[Int, String]:
    """The table's own words at word i (they come before the spec's, so a column called Total or a value called Line
    is that column or value): "by <text column>", a number column, a Yes/No column (or "un…"/"not …" it), a text
    column's value. Returns (words taken, what it understood); (0, "") when none."""
    var took = 0
    var what = String("")
    var one = w[i]
    # the table's words: "by <text column>", a number column, a Yes/No column, a text column's value
    var by = one == "by" and i + 1 < len(w)
    var at = i + 1 if by else i
    var matched = False
    for n in [3, 2, 1]:
        if matched:
            break
        var name = joined(w, at, n)
        if name == "":
            continue
        for c in text_columns(sheet):
            if sheet.name(c).lower() == name:
                spec.group = c
                if spec.only_col == c:
                    spec.only_col = -1
                took = (1 if by else 0) + n
                what = "by " + sheet.name(c)
                mark(said, SLOT_GROUP)
                matched = True
                break
        if matched or by:
            continue
        for c in number_columns(sheet):
            if sheet.name(c).lower() == name:
                spec.value = c
                if spec.combine == COMBINE_COUNT:
                    spec.combine = COMBINE_SUM
                    mark(said, SLOT_COMBINE)
                took = n
                what = sheet.name(c)
                mark(said, SLOT_VALUE)
                matched = True
                break
        if matched:
            continue
        for c in range(sheet.stored()):
            if sheet.kind(c) != BOOL:
                continue
            var b = sheet.name(c).lower()
            var code = -1
            if name == b:
                code = 1
            elif name == "un" + b or name == "not " + b or name == "non " + b or name == "non-" + b:
                code = 0
            if code >= 0:
                spec.only_col = c
                spec.only_code = code
                took = n
                what = ("" if code == 1 else "not ") + sheet.name(c)
                mark(said, SLOT_FILTER)
                matched = True
                break
        if matched:
            continue
        for c in text_columns(sheet):
            if c == spec.group or sheet.word_count(c) > FILTER_WORDS * 20:
                continue
            for code in range(sheet.word_count(c)):
                if sheet.text_of(c, Int64(code)).lower() == name:
                    spec.only_col = c
                    spec.only_code = code
                    took = n
                    what = "only " + sheet.text_of(c, Int64(code))
                    mark(said, SLOT_FILTER)
                    matched = True
                    break
            if matched:
                break
    return (took, what)


def ask(mut obj: SheetObject, sheet: Sheet, phrase: String) -> AskResult:
    """The phrase into the chart's spec. Longest matches first, so "largest first" is one setting and "not paid" one
    filter; a column's name can be several words."""
    var said = AskResult(List[String](), List[String](), List[Int]())
    var w = words_of(phrase)
    var spec = obj.copy()
    var i = 0
    var top_said = False
    var order_said = False
    while i < len(w):
        var took = 0
        var what = String("")
        var one = w[i]
        var two = joined(w, i, 2)
        var three = joined(w, i, 3)
        var table = table_word(spec, sheet, w, i, said)
        if table[0] > 0:
            took = table[0]
            what = table[1]
        # the spec's own words
        elif (three == "as in the" and joined(w, i, 4) == "as in the table") or three == "in data order" or two == "data order" or one == "unsorted":
            spec.order = ORDER_TABLE
            took = 4 if three == "as in the" else (3 if three == "in data order" else (2 if two == "data order" else 1))
            what = "in data order"
            order_said = True
            mark(said, SLOT_ORDER)
        elif two == "largest first" or two == "biggest first" or two == "highest first" or two == "most first" or one == "descending" or one == "largest" or one == "biggest" or one == "highest":
            spec.order = ORDER_LARGEST
            took = 2 if two.endswith("first") else 1
            what = "largest first"
            order_said = True
            mark(said, SLOT_ORDER)
        elif two == "smallest first" or two == "lowest first" or two == "least first" or one == "ascending" or one == "smallest" or one == "lowest":
            spec.order = ORDER_SMALLEST
            took = 2 if two.endswith("first") else 1
            what = "smallest first"
            order_said = True
            mark(said, SLOT_ORDER)
        elif three == "a to z" or one == "a-z" or one == "alphabetical" or one == "alphabetically" or two == "by name":
            spec.order = ORDER_AZ
            took = 3 if three == "a to z" else (2 if two == "by name" else 1)
            what = "A to Z"
            order_said = True
            mark(said, SLOT_ORDER)
        elif (one == "top" or one == "bottom" or one == "first" or one == "last") and i + 1 < len(w) and number_word(w[i + 1]) > 0:
            spec.top = number_word(w[i + 1])
            if one == "bottom" or one == "last":
                spec.order = ORDER_SMALLEST
                mark(said, SLOT_ORDER)
            elif not order_said and spec.order == ORDER_TABLE:
                spec.order = ORDER_LARGEST
                mark(said, SLOT_ORDER)
            took = 2
            what = one + " " + String(spec.top)
            top_said = True
            mark(said, SLOT_TOP)
        elif two == "all groups" or (one == "every" and i + 1 < len(w) and w[i + 1] == sheet.name(spec.group).lower()) or two == "no limit":
            spec.top = 0
            took = 2
            what = "every " + sheet.name(spec.group)
            mark(said, SLOT_TOP)
        elif two == "every row" or two == "all rows" or one == "everything" or two == "no filter" or one == "unfiltered":
            spec.only_col = -1
            took = 1 if one == "everything" or one == "unfiltered" else 2
            what = "every row"
            mark(said, SLOT_FILTER)
        elif one == "sum" or one == "total" or one == "totals":
            spec.combine = COMBINE_SUM
            took = 1
            what = "sum"
            mark(said, SLOT_COMBINE)
        elif one == "average" or one == "avg" or one == "mean":
            spec.combine = COMBINE_AVERAGE
            took = 1
            what = "average"
            mark(said, SLOT_COMBINE)
        elif one == "median" or one == "middle":
            spec.combine = COMBINE_MEDIAN
            took = 1
            what = "median"
        elif one == "p90" or three == "90th percentile" or one == "percentile" or two == "90th percentile":
            spec.combine = COMBINE_P90
            took = 3 if three == "90th percentile" else (2 if two == "90th percentile" else 1)
            what = "p90"
        elif one == "count" or two == "how many" or two == "number of" or one == "rows":
            spec.combine = COMBINE_COUNT
            took = 2 if two == "how many" or two == "number of" else 1
            what = "count"
            mark(said, SLOT_COMBINE)
        elif one == "line" or one == "lines" or two == "line chart":
            spec.style = CHART_LINE
            took = 2 if two == "line chart" else 1
            what = "a line"
            mark(said, SLOT_MARK)
        elif one == "bars" or one == "bar" or two == "bar chart":
            spec.style = CHART_BAR
            took = 2 if two == "bar chart" else 1
            what = "bars"
            mark(said, SLOT_MARK)
        if took > 0:
            said.understood.append(what)
            i += took
            continue
        var quiet = False
        for q in materialize[QUIET]():
            if q == one:
                quiet = True
        if not quiet:
            said.skipped.append(w[i])
        i += 1
    said.changed = List[Int]()  # (the words that changed: the sentence before and after, slot by slot)
    for slot in range(SLOTS):
        if slot_text(spec, sheet, slot) != slot_text(obj, sheet, slot):
            said.changed.append(slot)
    if len(said.changed) > 0:
        spec.selected = -1
        obj = spec^
    return said^


def ask_reply(said: AskResult) -> String:
    """What the field says back: "Took top 3 · not paid · a line" (and "skipped …"), or that it understood nothing."""
    if len(said.understood) == 0:
        return "Didn't understand that: try “top 3, largest first, as a line” or a column's name"
    var out = String("Took " if len(said.changed) > 0 else "Already so: ")
    for k in range(len(said.understood)):
        out += (" · " if k > 0 else "") + said.understood[k]
    if len(said.skipped) > 0:
        out += "; skipped "
        for k in range(len(said.skipped)):
            out += (", " if k > 0 else "") + "“" + said.skipped[k] + "”"
    return out
