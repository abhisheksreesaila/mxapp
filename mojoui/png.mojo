# A small PNG encoder in Mojo, so every host can show an Image from raw pixels
# with nothing but its platform's "image from PNG bytes" call.
#
# The pixel data is stored uncompressed (zlib "stored" blocks): simple, fast,
# and fine for app-sized pictures (a 480x320 image is about 600 KB).


def _crc_table() -> List[UInt32]:
    var table = List[UInt32](capacity=256)
    for n in range(256):
        var c = UInt32(n)
        for _ in range(8):
            c = (UInt32(0xEDB88320) ^ (c >> 1)) if (c & 1) != 0 else (c >> 1)
        table.append(c)
    return table^


def _crc32(table: List[UInt32], data: List[UInt8], start: Int, end: Int) -> UInt32:
    var c = UInt32(0xFFFFFFFF)
    for i in range(start, end):
        c = table[Int((c ^ UInt32(data[i])) & 0xFF)] ^ (c >> 8)
    return c ^ UInt32(0xFFFFFFFF)


def _u32be(mut out: List[UInt8], v: UInt32):
    out.append(UInt8((v >> 24) & 0xFF))
    out.append(UInt8((v >> 16) & 0xFF))
    out.append(UInt8((v >> 8) & 0xFF))
    out.append(UInt8(v & 0xFF))


def _chunk(mut out: List[UInt8], table: List[UInt32], kind: String, data: List[UInt8]):
    _u32be(out, UInt32(len(data)))
    var start = len(out)
    for b in kind.as_bytes():
        out.append(b)
    for b in data:
        out.append(b)
    _u32be(out, _crc32(table, out, start, len(out)))


def encode_png(pixels: List[UInt32], width: Int, height: Int) -> List[UInt8]:
    """PNG bytes for RGBA pixels (row by row; each UInt32 holds R, G, B, A from the low byte up)."""
    var table = _crc_table()
    # Raw scanlines: a 0 ("no filter") byte, then the row's RGBA bytes.
    var raw = List[UInt8](capacity=height * (1 + width * 4))
    for y in range(height):
        raw.append(0)
        for x in range(width):
            var p = pixels[y * width + x] if y * width + x < len(pixels) else UInt32(0)
            raw.append(UInt8(p & 0xFF))
            raw.append(UInt8((p >> 8) & 0xFF))
            raw.append(UInt8((p >> 16) & 0xFF))
            raw.append(UInt8((p >> 24) & 0xFF))
    # zlib stream with stored (uncompressed) deflate blocks, then the Adler-32 checksum.
    var z = List[UInt8](capacity=len(raw) + len(raw) // 65535 * 5 + 16)
    z.append(0x78)
    z.append(0x01)
    var pos = 0
    while True:
        var n = min(65535, len(raw) - pos)
        var last = pos + n >= len(raw)
        z.append(UInt8(1) if last else UInt8(0))
        z.append(UInt8(n & 0xFF))
        z.append(UInt8((n >> 8) & 0xFF))
        z.append(UInt8((~n) & 0xFF))
        z.append(UInt8(((~n) >> 8) & 0xFF))
        for i in range(pos, pos + n):
            z.append(raw[i])
        pos += n
        if last:
            break
    var a = UInt32(1)
    var b = UInt32(0)
    for v in raw:
        a = (a + UInt32(v)) % 65521
        b = (b + a) % 65521
    _u32be(z, (b << 16) | a)

    var out = List[UInt8](capacity=len(z) + 64)
    for v in [137, 80, 78, 71, 13, 10, 26, 10]:
        out.append(UInt8(v))
    var ihdr = List[UInt8]()
    _u32be(ihdr, UInt32(width))
    _u32be(ihdr, UInt32(height))
    for v in [8, 6, 0, 0, 0]:  # 8 bits per channel, RGBA, deflate, no filter, no interlace
        ihdr.append(UInt8(v))
    _chunk(out, table, "IHDR", ihdr)
    _chunk(out, table, "IDAT", z)
    _chunk(out, table, "IEND", List[UInt8]())
    return out^
