#!/usr/bin/env python3
"""screendump.py shot.png row count: reads screen codes back from a Denise screenshot of the
text screen (glyphs of the character ROM), for tests."""
import sys
from PIL import Image
rom = open('/usr/share/denise/data/Char', 'rb').read()
glyphs = {}
for c in range(256):
    g = tuple(rom[c * 8 + y] for y in range(8))
    glyphs.setdefault(g, c)
im = Image.open(sys.argv[1]).convert('RGB')
bg = (0, 0, 0)
# the 320x200 screen inside a 384x272 shot starts at (32, 35)
ox, oy = 32, 35
row, n = int(sys.argv[2]), int(sys.argv[3])
out = []
for i in range(n):
    r, c = row + i // 40, i % 40
    g = []
    for y in range(8):
        v = 0
        for x in range(8):
            p = im.getpixel((ox + c * 8 + x, oy + r * 8 + y))
            v = v << 1 | (p != bg)
        g.append(v)
    out.append(glyphs.get(tuple(g), -1))
print(' '.join('%02x' % v if v >= 0 else '??' for v in out))
