# MX Studio's operations: what the Sheet (and later an agent, through MCP tools) asks the engine.
# Each returns typed results with the counts behind them ("every finding carries its rows").

from mojoui.frame import Frame, Range, OP_COL, OP_CONST, OP_SUB, OP_FLOORDIV, OP_MIN, OP_MAX, TEXT, INT, DECIMAL, DATE
from mojoui.frame_gpu import GpuFrame, group_sum, pivot_program
from orders import CUSTOMER, PRODUCT, REVENUE

comptime BINS = 16


def col_program(c: Int) -> List[Int64]:
    var p = List[Int64]()
    p.append(Int64(OP_COL))
    p.append(Int64(c))
    return p^


def text_groups(frame: Frame, col: Int) -> Int:
    """How many codes a text column can hold now (its dictionary plus words typed into it)."""
    return len(frame.base()[].cols[col].dictionary) + len(frame.words[col])


def normal_key(name: String) -> String:
    """A name with case, punctuation and company suffixes taken away: "ACME Corporation" → "acme"."""
    var spaced = String("")
    for ch in name.lower().codepoint_slices():
        var s = String(ch)
        spaced += " " if (s == "." or s == "," or s == "-" or s == "&") else s
    var out = String("")
    for w in spaced.split(" "):
        var word = String(w)
        if word == "" or word == "corp" or word == "corporation" or word == "inc" or word == "co" or word == "ltd" or word == "llc":
            continue
        out += (" " if out != "" else "") + word
    return out


@fieldwise_init
struct Totals(Copyable, Movable):
    """Per code of a text column: rows and summed value (raw codes; fold() applies merges)."""

    var rows: List[Int]
    var sums: List[Int]
    var milliseconds: Float64


def totals_by(frame: Frame, gf: GpuFrame, col: Int, value: Int) -> Totals:
    var g = text_groups(frame, col)
    var r = group_sum(frame, gf, col_program(col), col_program(value), List[Range](), g)
    return Totals(r.counts.copy(), r.sums.copy(), r.milliseconds)


def fold(frame: Frame, col: Int, values: List[Int]) -> List[Int]:
    """Per-code values with merged codes added into the code they joined (the merged ones become 0)."""
    var out = values.copy()
    for code in range(len(values)):
        var into = Int(frame.alias(col, Int64(code)))
        if into != code and into < len(out):
            out[into] += out[code]
            out[code] = 0
    return out^


@fieldwise_init
struct Finding(Copyable, Movable):
    """Several spellings of one name: the codes, their texts, how many rows each has, and which one the
    others would merge into (the most used)."""

    var codes: List[Int64]
    var names: List[String]
    var rows: List[Int]
    var into: Int64

    def total_rows(self) -> Int:
        var n = 0
        for r in self.rows:
            n += r
        return n

    def other_rows(self) -> Int:
        """Rows under the spellings that would change."""
        var n = 0
        for k in range(len(self.codes)):
            if self.codes[k] != self.into:
                n += self.rows[k]
        return n


def find_duplicate_names(frame: Frame, col: Int, rows_per_code: List[Int]) -> List[Finding]:
    """Text values that differ only by case, punctuation or a company suffix, each still used by some row
    (merged ones count as one). Every finding names its spellings and their row counts."""
    var g = text_groups(frame, col)
    var keys = List[String]()
    for code in range(g):
        keys.append(normal_key(frame.text_of(col, Int64(code))))
    var out = List[Finding]()
    var done = List[Bool](length=g, fill=False)
    for a in range(g):
        if done[a] or keys[a] == "" or Int(frame.alias(col, Int64(a))) != a or a >= len(rows_per_code) or rows_per_code[a] == 0:
            continue
        var codes = List[Int64]()
        var names = List[String]()
        var rows = List[Int]()
        for b in range(a, g):
            if keys[b] == keys[a] and Int(frame.alias(col, Int64(b))) == b and b < len(rows_per_code) and rows_per_code[b] > 0:
                codes.append(Int64(b))
                names.append(frame.text_of(col, Int64(b)))
                rows.append(rows_per_code[b])
                done[b] = True
        if len(codes) > 1:
            var best = 0
            for k in range(len(rows)):
                if rows[k] > rows[best]:
                    best = k
            out.append(Finding(codes^, names^, rows^, Int64(0)))
            out[len(out) - 1].into = out[len(out) - 1].codes[best]
    return out^


def rows_with(frame: Frame, col: Int, codes: List[Int64], limit: Int = 1_000_000) -> List[Int]:
    """The rows (in order) whose raw value is one of `codes`: "open the rows" behind a finding."""
    var out = List[Int]()
    var want = List[Bool](length=text_groups(frame, col), fill=False)
    for c in codes:
        if Int(c) < len(want):
            want[Int(c)] = True
    for row in range(frame.rows()):
        if frame.alive(row):
            var v = Int(frame.get(col, row))
            if v < len(want) and want[v]:
                out.append(row)
                if len(out) >= limit:
                    break
    return out^


def histogram(frame: Frame, gf: GpuFrame, col: Int, lo: Int64, hi: Int64) -> List[Float64]:
    """Bar heights (0–1) of a column's distribution over every row, on the GPU: a text column by value,
    a number column in 16 equal bins between lo and hi."""
    var key: List[Int64]
    var groups: Int
    if frame.kind(col) == TEXT:
        key = col_program(col)
        groups = text_groups(frame, col)
    else:
        var width = max((hi - lo + BINS) // BINS, 1)
        key = col_program(col)  # clamp((v - lo) // width, 0, 15)
        key.append(Int64(OP_CONST)); key.append(lo); key.append(Int64(OP_SUB)); key.append(0)
        key.append(Int64(OP_CONST)); key.append(width); key.append(Int64(OP_FLOORDIV)); key.append(0)
        key.append(Int64(OP_CONST)); key.append(0); key.append(Int64(OP_MAX)); key.append(0)
        key.append(Int64(OP_CONST)); key.append(BINS - 1); key.append(Int64(OP_MIN)); key.append(0)
        groups = BINS
    var r = group_sum(frame, gf, key, col_program(col), List[Range](), groups)
    var counts = fold(frame, col, r.counts) if frame.kind(col) == TEXT else r.counts.copy()
    var top = 1
    for c in counts:
        top = max(top, c)
    var out = List[Float64]()
    for c in counts:
        out.append(Float64(c) / Float64(top))
    return out^


@fieldwise_init
struct Pivot(Copyable, Movable):
    """Revenue by customer × product, merged spellings folded, customers by revenue (largest first)."""

    var customers: List[Int]  # codes, in order
    var cells: List[Int]  # len(customers) × products, cents
    var products: Int
    var milliseconds: Float64


def customer_product(frame: Frame, gf: GpuFrame, top: Int) -> Pivot:
    var nc = text_groups(frame, CUSTOMER)
    var np = text_groups(frame, PRODUCT)
    var r = group_sum(frame, gf, pivot_program(col_program(CUSTOMER), np, col_program(PRODUCT)), col_program(REVENUE),
                      List[Range](), nc * np)
    # fold merged customers' rows into the customer they joined
    var cells = r.sums.copy()
    for code in range(nc):
        var into = Int(frame.alias(CUSTOMER, Int64(code)))
        if into != code:
            for p in range(np):
                cells[into * np + p] += cells[code * np + p]
                cells[code * np + p] = 0
    var totals = List[Int](length=nc, fill=0)
    for code in range(nc):
        for p in range(np):
            totals[code] += cells[code * np + p]
    var order = List[Int]()
    var used = List[Bool](length=nc, fill=False)
    for _ in range(min(top, nc)):
        var best = -1
        for code in range(nc):
            if not used[code] and totals[code] > 0 and (best < 0 or totals[code] > totals[best]):
                best = code
        if best < 0:
            break
        used[best] = True
        order.append(best)
    var out = List[Int]()
    for code in order:
        for p in range(np):
            out.append(cells[code * np + p])
    return Pivot(order^, out^, np, r.milliseconds)
