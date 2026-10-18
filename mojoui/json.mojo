# mojoui.json: a small JSON reader and the string writer, with no Python (the .omx metadata, mojoui.omxfile).
#
#   var j = Json.parse(text)                 # raises "not JSON: …" with the position
#   var cols = j.get(0, "columns")           # a node of the root (0) by key; -1 when absent
#   for k in range(j.size(cols)): j.at(cols, k) …    j.text(node), j.number(node), j.flag(node)
#
# Nodes live in flat lists (no recursive struct); a node is an Int. Numbers are whole numbers (all the metadata holds).

comptime J_NULL = 0
comptime J_BOOL = 1
comptime J_NUMBER = 2
comptime J_STRING = 3
comptime J_ARRAY = 4
comptime J_OBJECT = 5
comptime MAX_DEPTH = 64


def json_string(s: String) -> String:
    """`s` as a JSON string literal."""
    var out = String('"')
    for c in s.codepoint_slices():
        var o = ord(c)
        if c == '"':
            out += '\\"'
        elif c == "\\":
            out += "\\\\"
        elif c == "\n":
            out += "\\n"
        elif c == "\t":
            out += "\\t"
        elif c == "\r":
            out += "\\r"
        elif o < 32:
            var hex = "0123456789abcdef"
            out += "\\u00" + String(hex[byte = o // 16 : o // 16 + 1]) + String(hex[byte = o % 16 : o % 16 + 1])
        else:
            out += c
    return out + '"'


struct Json(Movable):
    var kinds: List[Int]
    var texts: List[String]  # J_STRING: the text
    var numbers: List[Int]  # J_NUMBER: the value; J_BOOL: 0 / 1
    var kids: List[List[Int]]  # J_ARRAY / J_OBJECT: the children
    var keys: List[List[String]]  # J_OBJECT: each child's key
    var src: List[Int]
    var pos: Int

    def __init__(out self):
        self.kinds = List[Int]()
        self.texts = List[String]()
        self.numbers = List[Int]()
        self.kids = List[List[Int]]()
        self.keys = List[List[String]]()
        self.src = List[Int]()
        self.pos = 0

    @staticmethod
    def parse(text: String) raises -> Json:
        var j = Json()
        for b in text.as_bytes():
            j.src.append(Int(b))
        _ = j.value(0)
        j.skip()
        if j.pos != len(j.src):
            raise j.fail("something after the end")
        return j^

    # ---- reading the tree ----

    def kind(self, node: Int) -> Int:
        return self.kinds[node] if node >= 0 else -1

    def size(self, node: Int) -> Int:
        return len(self.kids[node]) if node >= 0 and self.kinds[node] >= J_ARRAY else 0

    def at(self, node: Int, i: Int) -> Int:
        return self.kids[node][i] if 0 <= i < self.size(node) else -1

    def get(self, node: Int, key: String) -> Int:
        if node < 0 or self.kinds[node] != J_OBJECT:
            return -1
        for k in range(len(self.keys[node])):
            if self.keys[node][k] == key:
                return self.kids[node][k]
        return -1

    def text(self, node: Int, default: String = "") -> String:
        return self.texts[node] if node >= 0 and self.kinds[node] == J_STRING else default

    def number(self, node: Int, default: Int = 0) -> Int:
        return self.numbers[node] if node >= 0 and self.kinds[node] == J_NUMBER else default

    def flag(self, node: Int, default: Bool = False) -> Bool:
        return self.numbers[node] == 1 if node >= 0 and self.kinds[node] == J_BOOL else default

    # ---- parsing ----

    def fail(self, why: String) -> Error:
        return Error("not JSON: " + why + " (at character " + String(self.pos) + ")")

    def skip(mut self):
        while self.pos < len(self.src) and (self.src[self.pos] == 32 or self.src[self.pos] == 9 or self.src[self.pos] == 10 or self.src[self.pos] == 13):
            self.pos += 1

    def add(mut self, kind: Int) -> Int:
        self.kinds.append(kind)
        self.texts.append("")
        self.numbers.append(0)
        self.kids.append(List[Int]())
        self.keys.append(List[String]())
        return len(self.kinds) - 1

    def literal(mut self, word: String) -> Bool:
        var b = word.as_bytes()
        if self.pos + len(b) > len(self.src):
            return False
        for i in range(len(b)):
            if self.src[self.pos + i] != Int(b[i]):
                return False
        self.pos += len(b)
        return True

    def value(mut self, depth: Int) raises -> Int:
        if depth > MAX_DEPTH:
            raise self.fail("nested too deeply")
        self.skip()
        if self.pos >= len(self.src):
            raise self.fail("it ends early")
        var c = self.src[self.pos]
        if c == ord("{"):
            self.pos += 1
            var node = self.add(J_OBJECT)
            self.skip()
            if self.pos < len(self.src) and self.src[self.pos] == ord("}"):
                self.pos += 1
                return node
            while True:
                self.skip()
                if self.pos >= len(self.src) or self.src[self.pos] != ord('"'):
                    raise self.fail("a key was expected")
                var key = self.string()
                self.skip()
                if self.pos >= len(self.src) or self.src[self.pos] != ord(":"):
                    raise self.fail("a ':' was expected")
                self.pos += 1
                var child = self.value(depth + 1)
                self.kids[node].append(child)
                self.keys[node].append(key)
                self.skip()
                if self.pos < len(self.src) and self.src[self.pos] == ord(","):
                    self.pos += 1
                    continue
                if self.pos < len(self.src) and self.src[self.pos] == ord("}"):
                    self.pos += 1
                    return node
                raise self.fail("a ',' or '}' was expected")
        if c == ord("["):
            self.pos += 1
            var node = self.add(J_ARRAY)
            self.skip()
            if self.pos < len(self.src) and self.src[self.pos] == ord("]"):
                self.pos += 1
                return node
            while True:
                var child = self.value(depth + 1)
                self.kids[node].append(child)
                self.skip()
                if self.pos < len(self.src) and self.src[self.pos] == ord(","):
                    self.pos += 1
                    continue
                if self.pos < len(self.src) and self.src[self.pos] == ord("]"):
                    self.pos += 1
                    return node
                raise self.fail("a ',' or ']' was expected")
        if c == ord('"'):
            var node = self.add(J_STRING)
            self.texts[node] = self.string()
            return node
        if self.literal("true"):
            var node = self.add(J_BOOL)
            self.numbers[node] = 1
            return node
        if self.literal("false"):
            return self.add(J_BOOL)
        if self.literal("null"):
            return self.add(J_NULL)
        if c == ord("-") or (c >= ord("0") and c <= ord("9")):
            var neg = c == ord("-")
            if neg:
                self.pos += 1
            var v = 0
            var digits = 0
            while self.pos < len(self.src) and self.src[self.pos] >= ord("0") and self.src[self.pos] <= ord("9"):
                if v > 900_000_000_000_000_000:
                    raise self.fail("a number is too big")
                v = v * 10 + self.src[self.pos] - ord("0")
                self.pos += 1
                digits += 1
            if digits == 0:
                raise self.fail("a number was expected")
            if self.pos < len(self.src) and (self.src[self.pos] == ord(".") or self.src[self.pos] == ord("e") or self.src[self.pos] == ord("E")):
                raise self.fail("only whole numbers are read")
            var node = self.add(J_NUMBER)
            self.numbers[node] = -v if neg else v
            return node
        raise self.fail("unexpected '" + chr(c) + "'")

    def hex4(mut self) raises -> Int:
        if self.pos + 4 > len(self.src):
            raise self.fail("a \\u escape ends early")
        var v = 0
        for _ in range(4):
            var b = self.src[self.pos]
            var d: Int
            if b >= ord("0") and b <= ord("9"):
                d = b - ord("0")
            elif b >= ord("a") and b <= ord("f"):
                d = b - ord("a") + 10
            elif b >= ord("A") and b <= ord("F"):
                d = b - ord("A") + 10
            else:
                raise self.fail("a \\u escape needs four hex digits")
            v = v * 16 + d
            self.pos += 1
        return v

    def string(mut self) raises -> String:
        self.pos += 1  # the opening quote
        var out = List[UInt8]()
        while True:
            if self.pos >= len(self.src):
                raise self.fail("a string is not closed")
            var b = self.src[self.pos]
            self.pos += 1
            if b == ord('"'):
                break
            if b != ord("\\"):
                out.append(UInt8(b))
                continue
            if self.pos >= len(self.src):
                raise self.fail("a string is not closed")
            var e = self.src[self.pos]
            self.pos += 1
            if e == ord("n"):
                out.append(10)
            elif e == ord("t"):
                out.append(9)
            elif e == ord("r"):
                out.append(13)
            elif e == ord("b"):
                out.append(8)
            elif e == ord("f"):
                out.append(12)
            elif e == ord('"') or e == ord("\\") or e == ord("/"):
                out.append(UInt8(e))
            elif e == ord("u"):
                var cp = self.hex4()
                if cp >= 0xD800 and cp < 0xDC00:  # a surrogate pair
                    if self.pos + 1 < len(self.src) and self.src[self.pos] == ord("\\") and self.src[self.pos + 1] == ord("u"):
                        self.pos += 2
                        var lo = self.hex4()
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
                    else:
                        raise self.fail("a lone surrogate")
                for x in chr(cp).as_bytes():
                    out.append(x)
            else:
                raise self.fail("a bad escape")
        return String(unsafe_from_utf8=out)
