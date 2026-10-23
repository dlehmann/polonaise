#!/usr/bin/env python3
"""d64dir.py - lists a D64 image and extracts a file: d64dir.py image [name out]"""
import sys
SECTORS = [21] * 17 + [19] * 7 + [18] * 6 + [17] * 5
def off(t, s):
    return (sum(SECTORS[:t - 1]) + s) * 256
img = open(sys.argv[1], 'rb').read()
t, s = 18, 1
files = {}
while t:
    o = off(t, s)
    for i in range(8):
        e = o + i * 32
        if img[e + 2] & 7:
            name = img[e + 5:e + 21].rstrip(b'\xa0').decode('latin1')
            files[name] = (img[e + 3], img[e + 4])
            print('%-16s type %02x blocks %d' % (name, img[e + 2], img[e + 30] | img[e + 31] << 8))
    t, s = img[o], img[o + 1]
if len(sys.argv) > 3:
    t, s = files[sys.argv[2]]
    data = b''
    while t:
        o = off(t, s)
        if img[o]:
            data += img[o + 2:o + 256]
        else:
            data += img[o + 2:o + img[o + 1] + 1]
        t, s = img[o], img[o + 1]
    open(sys.argv[3], 'wb').write(data)
    print('extracted', len(data), 'bytes')
