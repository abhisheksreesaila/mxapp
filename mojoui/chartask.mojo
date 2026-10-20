# mojoui.chartask: a phrase that edits a chart's spec (goal 28 M2, D-255): "top 3, unpaid, as a line", "average by
# region", "only West, smallest first". A keyword reader, not a model: it knows the spec's words (sum, average, count;
# largest first, smallest first, A to Z; top N; bars, a line) and the table's own (its column names, a Yes/No column's
# name and "un…"/"not …", a text column's values). It says what it understood and what it skipped, and changes nothing
# when it understood nothing. An agent (AG-UI) can later write the same sentence.
#
#   var said = ask(chart, sheet, "top 3, unpaid, as a line")   # said.understood, said.skipped, said.changed (slots)

from mojoui.sheet import Sheet, TEXT, BOOL, DECIMAL
from mojoui.numformat import parse_decimal
from mojoui.sheetpage import (SheetObject, COMBINE_SUM, COMBINE_AVERAGE, COMBINE_COUNT, COMBINE_MEDIAN, COMBINE_P90, ORDER_TABLE, ORDER_LARGEST, ORDER_SMALLEST, ORDER_AZ,
                              CHART_BAR, CHART_LINE, SLOT_COMBINE, SLOT_VALUE, SLOT_GROUP, SLOT_ORDER, SLOT_TOP, SLOT_FILTER, SLOT_MARK,
                              FILTER_WORDS, SLOTS, number_columns, text_columns, slot_text, number_words, NUM_OVER, NUM_UNDER, NUM_BETWEEN, NUM_ANY, NUM_AT_LEAST, NUM_AT_MOST,
                              PART_NONE, PART_MONTH, PART_QUARTER, PART_WEEKDAY, PARTS, date_columns)

comptime QUIET: List[String] = ["of", "the", "a", "an", "and", "show", "me", "please", "with", "for", "in", "on", "to", "as", "chart",
                                "only", "just", "make", "it", "per", "each", "into", "then", "now", "values", "value"]
comptime NUMBERS: List[String] = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]


@fieldwise_init
struct AskResult(Copyable, Movable):
    var understood: List[String]  # what it took, in the phrase's order ("top 3", "unpaid", "as a line")
    var skipped: List[String]  # the words it couldn't use
    var changed: List[Int]  # the sentence's slots that changed (SLOT_*), each once


def words_of(phrase: String) -> List[String]:
    """Lower-case words: commas, full stops and semicolons are breaks, except inside a number ("1,000", "2.5");
    "a-z" stays one word."""
    var out = List[String]()
    var cur = String("")
    var chars = List[String]()
    for ch in phrase.lower().codepoint_slices():
        chars.append(String(ch))
    for i in range(len(chars)):
        var c = chars[i]
        var in_number = (c == "," or c == ".") and i > 0 and i + 1 < len(chars) and is_digit(chars[i - 1]) and is_digit(chars[i + 1])
        if in_number:
            cur += c
            continue
        if c == " " or c == "," or c == ";" or c == "." or c == "\t" or c == "!" or c == "?":
            if cur != "":
                out.append(cur)
            cur = ""
        else:
            cur += c
    if cur != "":
        out.append(cur)
    return out^


def is_digit(c: String) -> Bool:
    return c.byte_length() == 1 and c >= "0" and c <= "9"


def amount_of(word: String, sheet: Sheet, c: Int) -> Optional[Int]:
    """A number the person typed ("1,000", "$1,000", "2.5", "1k", "1.5m") in column c's stored units, exactly; none if it
    isn't one, or if it has more places than the column keeps (2.5 on a whole-number column: not rounded behind
    their back)."""
    var t = word
    var extra = 0
    if t.endswith("k") or t.endswith("m"):
        extra = 3 if t.endswith("k") else 6
        var digits = String(t[byte = : t.byte_length() - 1])
        t = digits
    if t == "" or not (is_digit(String(t[byte=0:1])) or t.startswith("$") or t.startswith("-")):
        return None
    var scale = sheet.scale(c) if sheet.kind(c) == DECIMAL else 0
    try:
        var fine = parse_decimal(t, scale + extra + 6)  # (six more places than needed: a fraction the column can't keep shows)
        var unit = Int64(10) ** Int64(6)
        if fine % unit != 0:
            return None
        return Int(fine // unit)
    except:
        return None


def is_comparison(w: String) -> Bool:
    return w == "over" or w == "above" or w == "under" or w == "below" or w == "between" or w == ">" or w == "<" or w == ">=" or w == "<="


def number_condition(mut spec: SheetObject, sheet: Sheet, c: Int, w: List[String], i: Int) -> Int:
    """ "over 1,000", "more than 5", "under 500", "between 100 and 200" at word i, on number column c: how many words it
    took (0: none there)."""
    if i >= len(w):
        return 0
    var one = w[i]
    var two = joined(w, i, 2)
    var over = one == "over" or one == "above" or one == ">" or two == "more than" or two == "greater than" or two == "at least" or one == ">="
    var under = one == "under" or one == "below" or one == "<" or two == "less than" or two == "at most" or one == "<="
    var skip = 2 if (two == "more than" or two == "greater than" or two == "less than" or two == "at least" or two == "at most") else 1
    if over or under:
        var v = amount_of(w[i + skip], sheet, c) if i + skip < len(w) else Optional[Int](None)
        if not v:
            return 0
        var inclusive = two == "at least" or two == "at most" or one == ">=" or one == "<="
        spec.num_col = c
        spec.num_op = (NUM_AT_LEAST if inclusive else NUM_OVER) if over else (NUM_AT_MOST if inclusive else NUM_UNDER)
        if over:
            spec.num_lo = v.value()
        else:
            spec.num_hi = v.value()
        return skip + 1
    if one == "between" and i + 3 < len(w) and w[i + 2] == "and":
        var lo = amount_of(w[i + 1], sheet, c)
        var hi = amount_of(w[i + 3], sheet, c)
        if lo and hi:
            spec.num_col = c
            spec.num_op = NUM_BETWEEN
            spec.num_lo = min(lo.value(), hi.value())
            spec.num_hi = max(lo.value(), hi.value())
            return 4
    return 0


def date_part(w: String) -> Int:
    """ "month", "monthly", "quarter", "weekday", "day of week" words → PART_*; 0 if it isn't one."""
    if w == "month" or w == "months" or w == "monthly":
        return PART_MONTH
    if w == "quarter" or w == "quarters" or w == "quarterly":
        return PART_QUARTER
    if w == "weekday" or w == "weekdays" or w == "dow":
        return PART_WEEKDAY
    return 0


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
                spec.part = PART_NONE
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
                var cmp = number_condition(spec, sheet, c, w, at + n)  # ("qty over 2": the column is the condition's, not the value)
                if cmp > 0:
                    took = n + cmp
                    what = number_words(spec, sheet)
                    matched = True
                    break
                if at + n < len(w) and is_comparison(w[at + n]):  # ("qty under 2.5" on whole numbers: the whole condition is skipped)
                    took = n + 2 if at + n + 1 < len(w) else n + 1
                    what = ""
                    matched = True
                    break
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
    var number_said = False
    var order_said = False
    while i < len(w):
        var took = 0
        var what = String("")
        var one = w[i]
        var two = joined(w, i, 2)
        var three = joined(w, i, 3)
        var table = table_word(spec, sheet, w, i, said)
        var before_num = (spec.num_col, spec.num_op, spec.num_lo, spec.num_hi)
        var cmp = number_condition(spec, sheet, spec.value, w, i) if table[0] == 0 else 0  # ("over 1,000": on the chart's value)
        if cmp > 0 and number_said:  # (one number condition a chart: a second in the same phrase is skipped, said so)
            spec.num_col = before_num[0]
            spec.num_op = before_num[1]
            spec.num_lo = before_num[2]
            spec.num_hi = before_num[3]
            for k in range(cmp):
                said.skipped.append(w[i + k])
            i += cmp
            continue
        if cmp > 0:
            number_said = True
        if table[0] > 0 and table[1] == "":  # (words it recognised but couldn't use: said as skipped)
            for k in range(table[0]):
                said.skipped.append(w[i + k])
            i += table[0]
            continue
        if table[0] > 0:
            took = table[0]
            what = table[1]
        elif cmp > 0:
            took = cmp
            what = number_words(spec, sheet)
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
            spec.num_op = NUM_ANY
            spec.num_col = -1
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
        elif one == "p90" or two == "90th percentile":
            spec.combine = COMBINE_P90
            took = 2 if two == "90th percentile" else 1
            what = "p90"
        elif one == "count" or two == "how many" or two == "number of" or one == "rows":
            spec.combine = COMBINE_COUNT
            took = 2 if two == "how many" or two == "number of" else 1
            what = "count"
            mark(said, SLOT_COMBINE)
        elif date_part(one) > 0 or (one == "by" and i + 1 < len(w) and date_part(w[i + 1]) > 0):
            var by = 1 if one == "by" else 0
            var part = date_part(w[i + by])
            var dc = -1
            var named = 0
            if i + by + 2 < len(w) and w[i + by + 1] == "of":  # ("by month of day": the date column named)
                for c in date_columns(sheet):
                    if sheet.name(c).lower() == w[i + by + 2]:
                        dc = c
                        named = 2
            if dc < 0:
                dc = spec.group if spec.part != PART_NONE else (date_columns(sheet)[0] if len(date_columns(sheet)) > 0 else -1)
            if dc >= 0:
                spec.group = dc
                spec.part = part
                if spec.order == ORDER_AZ:
                    spec.order = ORDER_TABLE
                took = by + 1 + named
                what = "by " + materialize[PARTS]()[part] + " of " + sheet.name(dc)
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
