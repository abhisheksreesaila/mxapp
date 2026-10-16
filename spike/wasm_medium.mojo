# A more honest sample: structs, List, String building, integer maths, a small loop. No print, no OS.
@fieldwise_init
struct Point(Copyable, Movable):
    var x: Int
    var y: Int

@export
def sum_squares(n: Int32) abi("C") -> Int64:
    var pts = List[Point]()
    for i in range(Int(n)):
        pts.append(Point(i, i * 2))
    var total: Int64 = 0
    for p in pts:
        total += Int64(p.x * p.x + p.y)
    return total

@export
def text_length(n: Int32) abi("C") -> Int32:
    var s = String("")
    for i in range(Int(n)):
        s += String(i) + ","
    return Int32(s.byte_length())
