# Checks mojoui's PNG encoder against Python's zlib and a PNG parser written from the spec.
# Run: pixi run mojo run -I . tests/test_png.mojo
from std.python import Python
from std.testing import assert_equal

from mojoui.png import encode_png


def test_png_decodes_to_the_same_pixels() raises:
    var pixels = List[UInt32]()
    for i in range(300 * 250):  # big enough to need several stored blocks
        pixels.append(UInt32(i * 2654435761) | (UInt32(255) << 24))
    var png = encode_png(pixels, 300, 250)
    var py = Python.import_module("builtins")
    var data = py.bytearray()
    for b in png:
        _ = data.append(Int(b))
    var check = Python.evaluate(
        """lambda data, w, h: (lambda zlib, struct: (
            int(data[:8] == bytes([137,80,78,71,13,10,26,10])),
            int(struct.unpack('>II', bytes(data[16:24])) == (w, h)),
            int(all(zlib.crc32(bytes(data[i+4:i+8+struct.unpack('>I', bytes(data[i:i+4]))[0]])) & 0xffffffff
                == struct.unpack('>I', bytes(data[i+8+struct.unpack('>I', bytes(data[i:i+4]))[0]:i+12+struct.unpack('>I', bytes(data[i:i+4]))[0]]))[0]
                for i in [8, 33])),
            zlib.decompress(bytes(data[41:len(data)-12-4]))
        ))(__import__('zlib'), __import__('struct'))"""
    )
    var result = check(data, 300, 250)
    assert_equal(Int(py=result[0]), 1, "signature")
    assert_equal(Int(py=result[1]), 1, "size")
    assert_equal(Int(py=result[2]), 1, "chunk CRCs")
    var raw = result[3]
    assert_equal(Int(py=py.len(raw)), 250 * (1 + 300 * 4))
    for (x, y) in [(0, 0), (299, 0), (17, 123), (299, 249)]:
        var p = pixels[y * 300 + x]
        var at = y * (1 + 300 * 4) + 1 + x * 4
        assert_equal(Int(py=raw[at]), Int(p & 0xFF))
        assert_equal(Int(py=raw[at + 1]), Int((p >> 8) & 0xFF))
        assert_equal(Int(py=raw[at + 3]), Int((p >> 24) & 0xFF))


def main() raises:
    test_png_decodes_to_the_same_pixels()
    print("PNG TESTS PASSED")
