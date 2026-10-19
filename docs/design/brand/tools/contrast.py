"""WCAG 2.x contrast for the omxplorer accent candidates. Usage: python contrast.py #hex [#hex ...]"""
import sys
def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
def lum(h):
    h = h.lstrip('#'); r, g, b = (int(h[i:i+2], 16) for i in (0, 2, 4))
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)
def mix(fg, bg, a):
    f = [int(fg.lstrip('#')[i:i+2], 16) for i in (0, 2, 4)]; g = [int(bg.lstrip('#')[i:i+2], 16) for i in (0, 2, 4)]
    return '#' + ''.join(f'{round(x * a + y * (1 - a)):02x}' for x, y in zip(f, g))
if __name__ == '__main__':
    for h in sys.argv[1:]:
        print(h, 'white-on', round(ratio(h, '#ffffff'), 2), ' on #f6f8fb', round(ratio(h, '#f6f8fb'), 2),
              ' on wash12', round(ratio(h, mix(h, '#ffffff', .12)), 2), ' on backdrop #eef2f7', round(ratio(h, '#eef2f7'), 2))
