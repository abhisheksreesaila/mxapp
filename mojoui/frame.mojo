# mojoui.frame: a table of typed columns, Numbers-style (columns, never cell addresses).
#
#   Stored columns live in a `Columns` block that is shared, read-only, by every session of a process
#   (`share()` once, `Frame(addr)` per session). A Frame adds what one session changed on top:
#   edited cells, appended rows, removed rows (a sparse overlay, never a copy of the data), plus
#   formula columns ("margin = cents - cost"), which are virtual: a small bytecode evaluated per row,
#   on the CPU for the rows on screen and inside the GPU group-by kernel (mojoui.frame_gpu).
#
#   Types: INT, DECIMAL (a scaled integer: scale 2 = cents, so sums stay exact), TEXT (dictionary codes),
#   DATE (days since 1970-01-01). Every value is an Int64 underneath; a row is a SIMD[int64, 16] vector.

from std.collections import Dict, Set
from std.memory import Pointer, stack_allocation
from std.memory.alloc import alloc, Layout
from mojoui.datagrid import GridSource

comptime INT = 0
comptime DECIMAL = 1
comptime TEXT = 2
comptime DATE = 3

comptime MAX_COLS = 16  # stored columns a frame can hold (its row vector)
comptime Row = SIMD[DType.int64, MAX_COLS]

# bytecode: pairs (op, arg)
comptime OP_CONST = 0
comptime OP_COL = 1
comptime OP_ADD = 2
comptime OP_SUB = 3
comptime OP_MUL = 4
comptime OP_DIV = 5  # integer division of scaled values (the compiler pre-scales the numerator)
comptime OP_MIN = 6
comptime OP_MAX = 7
comptime OP_FLOORDIV = 8  # //: integer division, unscaled
comptime OP_MOD = 9
comptime OP_SCALE = 10  # multiply the top by arg
comptime OP_UNSCALE = 11  # divide the top by arg
comptime OP_NEG = 12
comptime MAX_PROGRAM = 64  # (op, arg) pairs
comptime MAX_DEPTH = 4  # stack depth (GPU kernels keep the stack in four registers)

# edits
comptime SET = 0
comptime APPEND = 1
comptime REMOVE = 2
comptime MERGE = 3  # a text value folded into another (an alias): col, row = the merge's number, old = the code, new = the code it joins


@always_inline
def eval_program[origin: Origin](prog: Pointer[Int64, origin], n: Int, r: Row) -> Int64:
    """Runs n (op, arg) pairs over row vector r. Pure: the same code runs on the CPU and in GPU kernels.
    (The stack is stack_allocation, not a SIMD vector: a SIMD indexed at run time crashes Mojo 1.1's compiler.)"""
    var stack = stack_allocation[8, Int64]()
    var sp = 0
    for k in range(n):
        var op = prog[unsafe_offset=2 * k]
        var arg = prog[unsafe_offset=2 * k + 1]
        if op == OP_CONST:
            stack[sp] = arg
            sp += 1
        elif op == OP_COL:
            stack[sp] = r[Int(arg)]
            sp += 1
        elif op == OP_SCALE:
            stack[sp - 1] = stack[sp - 1] * arg
        elif op == OP_UNSCALE:
            stack[sp - 1] = stack[sp - 1] // arg
        elif op == OP_NEG:
            stack[sp - 1] = -stack[sp - 1]
        else:
            var b = stack[sp - 1]
            var a = stack[sp - 2]
            sp -= 1
            var v: Int64
            if op == OP_ADD:
                v = a + b
            elif op == OP_SUB:
                v = a - b
            elif op == OP_MUL:
                v = a * b
            elif op == OP_DIV or op == OP_FLOORDIV:
                v = a // b if b != 0 else 0
            elif op == OP_MOD:
                v = a % b if b != 0 else 0
            elif op == OP_MIN:
                v = a if a < b else b
            else:
                v = a if a > b else b
            stack[sp - 1] = v
    return stack[0] if sp > 0 else 0


def program_depth(code: List[Int64]) -> Int:
    """The deepest the stack gets while running the bytecode."""
    var depth = 0
    var sp = 0
    for k in range(len(code) // 2):
        var op = code[2 * k]
        if op == OP_CONST or op == OP_COL:
            sp += 1
            depth = max(depth, sp)
        elif op != OP_SCALE and op != OP_UNSCALE and op != OP_NEG:
            sp -= 1
    return depth


def pow10(k: Int) -> Int64:
    var v: Int64 = 1
    for _ in range(k):
        v *= 10
    return v


# ---------- dates (days since 1970-01-01 ↔ YYYY-MM-DD; Howard Hinnant's civil algorithms) ----------

def days_from_civil(y: Int, m: Int, d: Int) -> Int:
    var yy = y - (1 if m <= 2 else 0)
    var era = (yy if yy >= 0 else yy - 399) // 400
    var yoe = yy - era * 400
    var doy = (153 * (m + (-3 if m > 2 else 9)) + 2) // 5 + d - 1
    var doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468


def civil_from_days(z0: Int) -> Tuple[Int, Int, Int]:
    var z = z0 + 719468
    var era = (z if z >= 0 else z - 146096) // 146097
    var doe = z - era * 146097
    var yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    var y = yoe + era * 400
    var doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    var mp = (5 * doy + 2) // 153
    var d = doy - (153 * mp + 2) // 5 + 1
    var m = mp + (3 if mp < 10 else -9)
    return (y + (1 if m <= 2 else 0), m, d)


def two(n: Int) -> String:
    return ("0" if n < 10 else "") + String(n)


def date_text(days: Int64) -> String:
    var ymd = civil_from_days(Int(days))
    return String(ymd[0]) + "-" + two(ymd[1]) + "-" + two(ymd[2])


def parse_date(text: String) raises -> Int64:
    var parts = text.strip().split("-")
    if len(parts) != 3:
        raise Error("dates look like 2024-07-01")
    var y = Int(String(parts[0]))
    var m = Int(String(parts[1]))
    var d = Int(String(parts[2]))
    if m < 1 or m > 12 or d < 1 or d > 31:
        raise Error("not a date: '" + text + "'")
    var days = days_from_civil(y, m, d)
    var back = civil_from_days(days)
    if back[1] != m or back[2] != d:
        raise Error("not a date: '" + text + "'")
    return Int64(days)


def parse_decimal(text: String, scale: Int) raises -> Int64:
    """"12.5" with scale 2 → 1250; rounds extra digits away."""
    var t = text.strip().replace(",", "").replace("$", "")
    var neg = t.startswith("-")
    if neg:
        var rest = String(t[byte=1:])
        t = rest
    var dot = t.find(".")
    var whole = t if dot < 0 else String(t[byte=:dot])
    var frac = String("") if dot < 0 else String(t[byte=dot + 1:])
    for c in (whole + frac).codepoint_slices():
        if not (ord("0") <= ord(c) <= ord("9")):
            raise Error("not a number: '" + text + "'")
    var v = (Int64(Int(whole)) if whole != "" else 0) * pow10(scale)
    var f: Int64 = 0
    var digits = 0
    for c in frac.codepoint_slices():
        if digits < scale:
            f = f * 10 + Int64(ord(c) - ord("0"))
            digits += 1
    for _ in range(scale - digits):
        f *= 10
    v += f
    return -v if neg else v


def decimal_text(v: Int64, scale: Int) -> String:
    if scale == 0:
        return String(v)
    var p = pow10(scale)
    var a = v if v >= 0 else -v
    var frac = String(a % p)
    while frac.byte_length() < scale:
        frac = "0" + frac
    return ("-" if v < 0 else "") + String(a // p) + "." + frac


# ---------- columns ----------

struct Column(Copyable, Movable):
    var name: String
    var kind: Int
    var scale: Int  # DECIMAL: digits after the point
    var values: List[Int64]  # stored columns (empty for formulas)
    var dictionary: List[String]  # TEXT: code → text
    var formula: String  # formula columns: the expression text
    var program: List[Int64]  # formula columns: (op, arg) pairs; OP_COL args may name other formulas

    def __init__(out self, name: String, kind: Int = INT, scale: Int = 0):
        self.name = name
        self.kind = kind
        self.scale = 2 if kind == DECIMAL and scale == 0 else scale
        self.values = List[Int64]()
        self.dictionary = List[String]()
        self.formula = ""
        self.program = List[Int64]()

    def is_formula(self) -> Bool:
        return self.formula != ""


struct Columns(Movable):
    """The stored data: shared by every session of a process, read-only once shared."""

    var cols: List[Column]
    var rows: Int

    def __init__(out self):
        self.cols = List[Column]()
        self.rows = 0

    def add(mut self, var c: Column):
        if len(self.cols) == 0:
            self.rows = len(c.values)
        self.cols.append(c^)

    def index(self, name: String) -> Int:
        for k in range(len(self.cols)):
            if self.cols[k].name == name:
                return k
        return -1


def share(var columns: Columns) -> Int:
    """Moves the columns to the heap for the life of the process; the address is what sessions hold."""
    var p = alloc(Layout[Columns].single()).unsafe_leak()
    p.unsafe_write(columns^)
    return Int(p)


def base_at(addr: Int) -> Pointer[Columns, MutUntrackedOrigin]:
    return Pointer[Columns, MutUntrackedOrigin](unsafe_from_address=addr)


@fieldwise_init
struct Edit(Copyable, Movable):
    var kind: Int  # SET, APPEND, REMOVE, MERGE
    var col: Int
    var row: Int
    var old: Int64
    var new: Int64


@fieldwise_init
struct Range(Copyable, Movable):
    """A filter: keep rows whose column value is within [lo, hi]."""

    var col: Int
    var lo: Int64
    var hi: Int64


def radix_sort(mut keys: List[UInt64], mut idx: List[Int32], bits: Int):
    """Sorts idx by keys (stable), 16 bits a pass, only the passes the keys' range needs."""
    var n = len(keys)
    var k2 = List[UInt64](length=n, fill=0)
    var i2 = List[Int32](length=n, fill=0)
    var shift = 0
    while shift < bits:
        var counts = List[Int](length=65537, fill=0)
        for i in range(n):
            counts[Int((keys[i] >> UInt64(shift)) & 0xFFFF) + 1] += 1
        for d in range(65536):
            counts[d + 1] += counts[d]
        for i in range(n):
            var d = Int((keys[i] >> UInt64(shift)) & 0xFFFF)
            var at = counts[d]
            counts[d] = at + 1
            k2[at] = keys[i]
            i2[at] = idx[i]
        swap(keys, k2)
        swap(idx, i2)
        shift += 16



# ---------- the expression compiler ----------

struct Compiler:
    """name = expr → bytecode with decimal scales tracked (DECIMAL columns are scaled integers)."""

    var text: String
    var pos: Int
    var code: List[Int64]
    var names: List[String]
    var scales: List[Int]
    var used: List[Int]

    def __init__(out self, text: String, names: List[String], scales: List[Int]):
        self.text = text
        self.pos = 0
        self.code = List[Int64]()
        self.names = names.copy()
        self.scales = scales.copy()
        self.used = List[Int]()

    def peek(mut self) -> String:
        self.skip()
        if self.pos >= self.text.byte_length():
            return ""
        return String(self.text[byte=self.pos:self.pos + 1])

    def skip(mut self):
        while self.pos < self.text.byte_length() and String(self.text[byte=self.pos:self.pos + 1]) == " ":
            self.pos += 1

    def emit(mut self, op: Int, arg: Int64 = 0):
        self.code.append(Int64(op))
        self.code.append(arg)


    def expr(mut self) raises -> Int:
        var s = self.term()
        while self.peek() == "+" or self.peek() == "-":
            var op = self.peek()
            self.pos += 1
            var rhs = len(self.code)  # where the right operand's code starts
            var s2 = self.term()
            s = self.align2(s, s2, rhs)
            self.emit(OP_ADD if op == "+" else OP_SUB)
        return s

    def align2(mut self, s_left: Int, s_right: Int, rhs: Int) -> Int:
        """Brings both operands to one scale: the right one by a SCALE at the end, the left one by a
        SCALE inserted just before the right operand's code (at rhs)."""
        if s_right < s_left:
            self.emit(OP_SCALE, pow10(s_left - s_right))
            return s_left
        if s_left < s_right:
            self.code.insert(rhs, pow10(s_right - s_left))
            self.code.insert(rhs, Int64(OP_SCALE))
            return s_right
        return s_right

    def term(mut self) raises -> Int:
        var s = self.factor()
        while True:
            var c = self.peek()
            if c == "*":
                self.pos += 1
                var s2 = self.factor()
                self.emit(OP_MUL)
                s = s + s2
                if s > 2:  # keep money at cents
                    self.emit(OP_UNSCALE, pow10(s - 2))
                    s = 2
            elif c == "/":
                self.pos += 1
                if self.pos < self.text.byte_length() and String(self.text[byte=self.pos:self.pos + 1]) == "/":
                    self.pos += 1
                    var rhs = len(self.code)
                    var s2 = self.factor()
                    _ = self.align2(s, s2, rhs)
                    self.emit(OP_FLOORDIV)
                    s = 0
                else:
                    var rhs = len(self.code)
                    var s2 = self.factor()
                    # result scale 2: (a · 10^k) / b where k = 2 - s + s2
                    var k = 2 - s + s2
                    if k > 0:
                        self.code.insert(rhs, pow10(k))
                        self.code.insert(rhs, Int64(OP_SCALE))
                    elif k < 0:
                        self.emit(OP_SCALE, pow10(-k))
                    self.emit(OP_DIV)
                    s = 2
            elif c == "%":
                self.pos += 1
                var rhs = len(self.code)
                var s2 = self.factor()
                s = self.align2(s, s2, rhs)
                self.emit(OP_MOD)
            else:
                return s

    def factor(mut self) raises -> Int:
        var c = self.peek()
        if c == "":
            raise Error("expression ends early")
        if c == "-":
            self.pos += 1
            var s = self.factor()
            self.emit(OP_NEG)
            return s
        if c == "(":
            self.pos += 1
            var s = self.expr()
            if self.peek() != ")":
                raise Error("missing )")
            self.pos += 1
            return s
        var o = ord(c)
        if (ord("0") <= o <= ord("9")) or c == ".":
            var start = self.pos
            while self.pos < self.text.byte_length():
                var ch = String(self.text[byte=self.pos:self.pos + 1])
                var oc = ord(ch)
                if (ord("0") <= oc <= ord("9")) or ch == ".":
                    self.pos += 1
                else:
                    break
            var num = String(self.text[byte=start:self.pos])
            var dot = num.find(".")
            var scale = 0 if dot < 0 else num.byte_length() - dot - 1
            self.emit(OP_CONST, parse_decimal(num, scale))
            return scale
        if o == ord("_") or (ord("a") <= o <= ord("z")) or (ord("A") <= o <= ord("Z")):
            var start = self.pos
            while self.pos < self.text.byte_length():
                var ch = String(self.text[byte=self.pos:self.pos + 1])
                var oc = ord(ch)
                if oc == ord("_") or (ord("a") <= oc <= ord("z")) or (ord("A") <= oc <= ord("Z")) or (ord("0") <= oc <= ord("9")):
                    self.pos += 1
                else:
                    break
            var word = String(self.text[byte=start:self.pos])
            if word == "min" or word == "max":
                if self.peek() != "(":
                    raise Error(word + " needs (a, b)")
                self.pos += 1
                var s1 = self.expr()
                if self.peek() != ",":
                    raise Error(word + " needs two values")
                self.pos += 1
                var rhs = len(self.code)
                var s2 = self.expr()
                if self.peek() != ")":
                    raise Error("missing )")
                self.pos += 1
                var s = self.align2(s1, s2, rhs)
                self.emit(OP_MIN if word == "min" else OP_MAX)
                return s
            for k in range(len(self.names)):
                if self.names[k] == word:
                    self.emit(OP_COL, Int64(k))
                    self.used.append(k)
                    return self.scales[k]
            raise Error("unknown column '" + word + "'")
        raise Error("unexpected '" + c + "'")


# ---------- the frame ----------

struct Frame(Movable, GridSource):
    """One session's view of shared columns: its edits, added and removed rows, and formula columns."""

    var base_addr: Int
    var formulas: List[Column]  # virtual columns, after the stored ones
    var cells: Dict[Int, Int64]  # row * MAX_COLS + col → edited value
    var added: List[Row]  # appended rows (row numbers continue after the base)
    var removed: Set[Int]
    var words: List[List[String]]  # per stored column: texts added by this session (codes continue after the dictionary)
    var log: List[Edit]
    var aliases: Dict[Int, Int64]  # col * 65536 + code → the code it was merged into (a text column's spellings)
    var edits: Int  # count of edits applied (for hosts to know when to re-aggregate)

    def __init__(out self, base_addr: Int):
        self.base_addr = base_addr
        self.formulas = List[Column]()
        self.cells = Dict[Int, Int64]()
        self.added = List[Row]()
        self.removed = Set[Int]()
        self.words = List[List[String]]()
        for _ in range(len(base_at(base_addr)[].cols)):
            self.words.append(List[String]())
        self.log = List[Edit]()
        self.aliases = Dict[Int, Int64]()
        self.edits = 0

    def base(self) -> Pointer[Columns, MutUntrackedOrigin]:
        return base_at(self.base_addr)

    # ---- shape ----

    # ---------- as a DataGrid's source (mojoui.datagrid) ----------

    def grid_rows(self) -> Int:
        return self.rows()

    def grid_alive(self, row: Int) -> Bool:
        return self.alive(row)

    def grid_columns(self) -> Int:
        return self.columns()

    def grid_name(self, c: Int) -> String:
        return self.name(c)

    def grid_numeric(self, c: Int) -> Bool:
        return self.kind(c) == INT or self.kind(c) == DECIMAL

    def grid_editable(self, c: Int) -> Bool:
        return c < self.stored()

    def grid_text(self, c: Int, row: Int) -> String:
        return self.display(c, row)

    def grid_type_width(self, c: Int) -> Float64:
        var kind = self.kind(c)
        if kind == DATE:
            return 104
        if kind == TEXT and c < self.stored():
            var longest = 0
            for v in self.base()[].cols[c].dictionary:
                longest = max(longest, v.byte_length())
            return 190 if longest > 20 else 118  # (long names, such as products, get a wider column)
        if kind == DECIMAL:
            return 96
        return 72

    def stored(self) -> Int:
        return len(self.base()[].cols)

    def columns(self) -> Int:
        return self.stored() + len(self.formulas)

    def rows(self) -> Int:
        """Row numbers (including removed ones); alive() tells which are shown."""
        return self.base()[].rows + len(self.added)

    def alive(self, row: Int) -> Bool:
        return 0 <= row < self.rows() and row not in self.removed

    def name(self, col: Int) -> String:
        return self.base()[].cols[col].name if col < self.stored() else self.formulas[col - self.stored()].name

    def kind(self, col: Int) -> Int:
        return self.base()[].cols[col].kind if col < self.stored() else self.formulas[col - self.stored()].kind

    def scale(self, col: Int) -> Int:
        return self.base()[].cols[col].scale if col < self.stored() else self.formulas[col - self.stored()].scale

    def index(self, name: String) -> Int:
        var k = self.base()[].index(name)
        if k >= 0:
            return k
        for f in range(len(self.formulas)):
            if self.formulas[f].name == name:
                return self.stored() + f
        return -1

    def names(self) -> List[String]:
        var out = List[String]()
        for c in range(self.columns()):
            out.append(self.name(c))
        return out^

    # ---- values ----

    def stored_value(self, col: Int, row: Int) -> Int64:
        var key = row * MAX_COLS + col
        var hit = self.cells.get(key)
        if hit:
            return hit.value()
        var n = self.base()[].rows
        if row < n:
            return self.base()[].cols[col].values[row]
        return self.added[row - n][col]

    def row_vector(self, row: Int) -> Row:
        var r = Row(0)
        var n = self.base()[].rows
        if row >= n:
            r = self.added[row - n]
        else:
            for c in range(self.stored()):
                r[c] = self.base()[].cols[c].values[row]
        for c in range(self.stored()):
            var hit = self.cells.get(row * MAX_COLS + c)
            if hit:
                r[c] = hit.value()
        return r

    def get(self, col: Int, row: Int) -> Int64:
        if col < self.stored():
            return self.stored_value(col, row)
        return self.evaluate(col - self.stored(), self.row_vector(row))

    def evaluate(self, f: Int, r: Row) -> Int64:
        """A formula over a row vector; formulas referring to other formulas are evaluated first."""
        var flat = self.flat_program(f)
        return eval_program(flat.unsafe_ptr(), len(flat) // 2, r)

    def flat_program(self, f: Int) -> List[Int64]:
        """The formula's bytecode with references to other formulas inlined (what GPU kernels run)."""
        return self.flatten(self.formulas[f].program)

    def text_of(self, col: Int, code: Int64) -> String:
        ref dictionary = self.base()[].cols[col].dictionary
        var c = Int(code)
        if c < len(dictionary):
            return dictionary[c]
        var extra = c - len(dictionary)
        return self.words[col][extra] if extra < len(self.words[col]) else "?"

    def display(self, col: Int, row: Int) -> String:
        var v = self.get(col, row)
        var kind = self.kind(col)
        if kind == TEXT and col < self.stored():
            return self.text_of(col, self.alias(col, v))
        if kind == DATE:
            return date_text(v)
        if kind == DECIMAL:
            return decimal_text(v, self.scale(col))
        return String(v)

    def parse(mut self, col: Int, text: String) raises -> Int64:
        """A typed value from what the person typed (TEXT: a dictionary code, added if new)."""
        var kind = self.kind(col)
        if kind == TEXT:
            ref dictionary = self.base()[].cols[col].dictionary
            for k in range(len(dictionary)):
                if dictionary[k] == text:
                    return Int64(k)
            for k in range(len(self.words[col])):
                if self.words[col][k] == text:
                    return Int64(len(dictionary) + k)
            self.words[col].append(text)
            return Int64(len(dictionary) + len(self.words[col]) - 1)
        if kind == DATE:
            return parse_date(text)
        if kind == DECIMAL:
            return parse_decimal(text, self.scale(col))
        return parse_decimal(text, 0)

    # ---- edits ----

    def set(mut self, col: Int, row: Int, value: Int64):
        if col < 0 or col >= self.stored() or row < 0 or row >= self.rows():
            return  # formulas aren't edited; their inputs are; rows past the end don't exist
        var old = self.stored_value(col, row)
        self.cells[row * MAX_COLS + col] = value
        self.log.append(Edit(SET, col, row, old, value))
        self.edits += 1

    def set_text(mut self, col: Int, row: Int, text: String) raises:
        self.set(col, row, self.parse(col, text))

    def append(mut self, values: List[String]) raises -> Int:
        """A new row from typed values (one per stored column, missing ones empty); returns its row number."""
        var r = Row(0)
        for c in range(self.stored()):
            if c < len(values) and String(values[c].strip()) != "":
                r[c] = self.parse(c, values[c])
        self.added.append(r)
        var row = self.rows() - 1
        self.log.append(Edit(APPEND, -1, row, 0, 0))
        self.edits += 1
        return row

    def remove(mut self, row: Int):
        if self.alive(row):
            self.removed.add(row)
            self.log.append(Edit(REMOVE, -1, row, 0, 0))
            self.edits += 1

    def undo(mut self) -> Bool:
        if len(self.log) == 0:
            return False
        var e = self.log.pop()
        if e.kind == SET:
            var n = self.base()[].rows
            var key = e.row * MAX_COLS + e.col
            if e.row < n and e.old == self.base()[].cols[e.col].values[e.row]:
                _ = self.cells.pop(key, 0)  # back to the shared value
            elif e.row >= n and e.old == self.added[e.row - n][e.col]:
                _ = self.cells.pop(key, 0)
            else:
                self.cells[key] = e.old
        elif e.kind == MERGE:  # the whole merge comes undone (its spellings share e.row)
            _ = self.aliases.pop(e.col * 65536 + Int(e.old), 0)
            while len(self.log) > 0 and self.log[len(self.log) - 1].kind == MERGE and self.log[len(self.log) - 1].row == e.row:
                var more = self.log.pop()
                _ = self.aliases.pop(more.col * 65536 + Int(more.old), 0)
        elif e.kind == APPEND:
            _ = self.added.pop()
        else:
            self.removed.discard(e.row)
        self.edits += 1
        return True

    def alias(self, col: Int, code: Int64) -> Int64:
        """The code a text value shows as (itself, or the one it was merged into)."""
        if len(self.aliases) == 0:
            return code
        var hit = self.aliases.get(col * 65536 + Int(code))
        return hit.value() if hit else code

    def merge(mut self, col: Int, codes: List[Int64], into: Int64) -> Int:
        """Folds text values `codes` of column col into `into` (e.g. three spellings of one customer): every row
        reads as `into` from now on. One operation in the edit log (undo brings the spellings back), no matter
        how many rows; aggregations fold the groups (alias()). Returns how many values were merged."""
        var number = 0
        for e in self.log:
            if e.kind == MERGE:
                number = max(number, e.row + 1)
        var count = 0
        for c in codes:
            if c == into or (col * 65536 + Int(c)) in self.aliases:
                continue
            self.aliases[col * 65536 + Int(c)] = into
            self.log.append(Edit(MERGE, col, number, c, into))
            count += 1
        if count > 0:
            self.edits += 1
        return count

    def changed_rows(self) -> List[Int]:
        """Rows that differ from the shared data (edited, appended or removed), each once."""
        var seen = Set[Int]()
        var out = List[Int]()
        for key in self.cells.keys():
            var row = key // MAX_COLS
            if row not in seen:
                seen.add(row)
                out.append(row)
        for i in range(len(self.added)):
            var row = self.base()[].rows + i
            if row not in seen:
                seen.add(row)
                out.append(row)
        for row in self.removed:
            if row not in seen:
                seen.add(row)
                out.append(row)
        return out^

    # ---- formulas ----

    def formula(mut self, text: String) raises -> Int:
        """Adds (or replaces) a formula column from "name = expression"; returns its column index."""
        var eq = text.find("=")
        if eq < 0:
            raise Error("a formula looks like: margin = cents - cost")
        var name = String(text[byte=:eq]).strip()
        var expr = String(text[byte=eq + 1:])
        if name == "":
            raise Error("the formula needs a name")
        var names = self.names()
        var scales = List[Int]()
        for c in range(self.columns()):
            scales.append(self.scale(c))
        var existing = self.index(String(name))
        if existing >= 0 and existing < self.stored():
            raise Error("'" + String(name) + "' is a stored column")
        var comp = Compiler(String(expr), names, scales)
        var scale = comp.expr()
        if comp.peek() != "":
            raise Error("unexpected '" + comp.peek() + "'")
        for u in comp.used:
            if u == existing or (u >= self.stored() and self.depends(u - self.stored(), existing)):
                raise Error("'" + String(name) + "' would depend on itself")
        var flat = self.flatten(comp.code)  # what the kernels run: other formulas inlined
        if len(flat) > 2 * MAX_PROGRAM:
            raise Error("formula too long")
        if program_depth(flat) > MAX_DEPTH:
            raise Error("formula too deeply nested: split it into two columns")
        var col = Column(String(name), DECIMAL if scale > 0 else INT, scale)
        col.formula = String(String(expr).strip())
        col.program = comp.code.copy()
        if existing >= 0:
            # the formulas built on this one recompile against its new scale and depth; if any of
            # them can't (too deep now), nothing changes
            var before = self.formulas.copy()
            self.formulas[existing - self.stored()] = col^
            var texts = List[String]()
            for f in range(len(self.formulas)):
                if self.depends(f, existing):
                    texts.append(self.formulas[f].name + " = " + self.formulas[f].formula)
            for t in texts:
                try:
                    _ = self.formula(t)
                except e:
                    self.formulas = before^
                    raise Error("'" + String(name) + "' can't change: " + String(e))
            self.edits += 1
            return existing
        self.formulas.append(col^)
        self.edits += 1
        return self.columns() - 1

    def flatten(self, code: List[Int64]) -> List[Int64]:
        var out = List[Int64]()
        for k in range(len(code) // 2):
            var op = code[2 * k]
            var arg = code[2 * k + 1]
            if op == OP_COL and Int(arg) >= self.stored():
                for v in self.flat_program(Int(arg) - self.stored()):
                    out.append(v)
            else:
                out.append(op)
                out.append(arg)
        return out^

    def depends(self, f: Int, col: Int) -> Bool:
        """Does formula f read column col (directly or through other formulas)?"""
        if col < 0:
            return False
        ref p = self.formulas[f].program
        for k in range(len(p) // 2):
            if p[2 * k] == OP_COL:
                var c = Int(p[2 * k + 1])
                if c == col or (c >= self.stored() and self.depends(c - self.stored(), col)):
                    return True
        return False

    def dependants(self, col: Int) -> List[String]:
        """Formula columns that change when column col changes, in evaluation order."""
        var out = List[String]()
        for f in range(len(self.formulas)):
            if self.depends(f, col):
                out.append(self.formulas[f].name)
        return out^

    def program_for(self, col: Int) -> List[Int64]:
        """Bytecode producing column col (stored: one OP_COL; formula: flattened)."""
        if col < self.stored():
            var p = List[Int64]()
            p.append(Int64(OP_COL))
            p.append(Int64(col))
            return p^
        return self.flat_program(col - self.stored())

    # ---- queries (CPU; mojoui.frame_gpu runs the same over the shared data on the GPU) ----

    def matches(self, r: Row, ranges: List[Range]) -> Bool:
        for g in ranges:
            var v = r[g.col]
            if v < g.lo or v > g.hi:
                return False
        return True

    def column_values(self, col: Int) -> List[Int64]:
        """Every row's value in column col (removed rows included), the session's overlay applied.
        Reads the shared column straight through; only changed rows go through the overlay."""
        var n = self.base()[].rows
        var out = List[Int64]()
        if col < self.stored():
            out = self.base()[].cols[col].values.copy()
            for i in range(len(self.added)):
                out.append(self.added[i][col])
            for item in self.cells.items():
                if item.key % MAX_COLS == col:
                    out[item.key // MAX_COLS] = item.value
            return out^
        var flat = self.flat_program(col - self.stored())
        var ops = len(flat) // 2
        out = List[Int64](capacity=self.rows())
        var stored = self.stored()
        for row in range(n):
            var r = Row(0)
            for c in range(stored):
                r[c] = self.base()[].cols[c].values[row]
            out.append(eval_program(flat.unsafe_ptr(), ops, r))
        for i in range(len(self.added)):
            out.append(eval_program(flat.unsafe_ptr(), ops, self.row_vector(n + i)))
        for row in self.changed_rows():
            out[row] = eval_program(flat.unsafe_ptr(), ops, self.row_vector(row))
        return out^

    def permutation(self, col: Int, descending: Bool = False) -> List[Int]:
        """Alive rows ordered by column col (ties keep row order); the data never moves.
        A radix sort: linear in the rows however few distinct values the column has (a comparison
        sort goes quadratic on 20M rows of 8 categories)."""
        var values = self.column_values(col)
        var rows = List[Int32](capacity=len(values))
        for row in range(len(values)):
            if len(self.removed) == 0 or row not in self.removed:
                rows.append(Int32(row))
        if len(rows) == 0:
            return List[Int]()
        var lo = values[Int(rows[0])]
        var hi = lo
        for i in rows:
            var v = values[Int(i)]
            lo = min(lo, v)
            hi = max(hi, v)
        var keys = List[UInt64](capacity=len(rows))
        for i in rows:
            var v = values[Int(i)]
            keys.append(UInt64(hi - v) if descending else UInt64(v - lo))
        var span = UInt64(hi - lo)
        var bits = 0
        while bits < 64 and (span >> UInt64(bits)) != 0:
            bits += 1
        radix_sort(keys, rows, bits)
        var out = List[Int](capacity=len(rows))
        for i in rows:
            out.append(Int(i))
        return out^

    def group_sum(self, key: List[Int64], value: List[Int64], ranges: List[Range], groups: Int) -> Tuple[List[Int], List[Int]]:
        """Per group (key program → 0…groups-1, others skipped): sum of the value program and the row count. CPU."""
        var sums = List[Int](length=groups, fill=0)
        var counts = List[Int](length=groups, fill=0)
        for row in range(self.rows()):
            if not self.alive(row):
                continue
            var r = self.row_vector(row)
            if not self.matches(r, ranges):
                continue
            var g = Int(eval_program(key.unsafe_ptr(), len(key) // 2, r))
            if g >= 0 and g < groups:
                sums[g] += Int(eval_program(value.unsafe_ptr(), len(value) // 2, r))
                counts[g] += 1
        return (sums^, counts^)
