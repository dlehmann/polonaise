#!/usr/bin/env python3
"""mkd64.py - writes a 35 track D64 disk image with PRG files.

Usage: mkd64.py out.d64 "DISK NAME" "ID" file.prg:NAME[:INTERLEAVE] ...

The sectors of a file follow each other with the interleave (default 10, as the DOS does),
on the tracks nearest to the directory first.
"""
import sys

SECTORS = [21] * 17 + [19] * 7 + [18] * 6 + [17] * 5


def offset(track, sector):
    return (sum(SECTORS[:track - 1]) + sector) * 256


def petscii(s, n):
    b = s.upper().encode('ascii')[:n]
    return b + b'\xa0' * (n - len(b))


def main():
    out, name, ident = sys.argv[1:4]
    files = []
    for a in sys.argv[4:]:
        p = a.split(':')
        files.append((p[0], p[1], int(p[2]) if len(p) > 2 else 10))
    img = bytearray(sum(SECTORS) * 256)
    used = {t: set() for t in range(1, 36)}
    used[18] |= {0, 1}
    entries = []
    order = [t for pair in zip(range(17, 0, -1), range(19, 36)) for t in pair]   # near track 18 first

    def alloc(n, il):
        out = []
        ti, s = 0, 0
        while len(out) < n:
            t = order[ti]
            free = [x for x in range(SECTORS[t - 1]) if x not in used[t]]
            if not free:
                ti += 1
                s = 0
                continue
            k = SECTORS[t - 1]
            while s in used[t]:
                s = (s + 1) % k
            used[t].add(s)
            out.append((t, s))
            s = (s + il) % k
        return out

    for path, fname, il in files:
        data = open(path, 'rb').read()
        chunks = [data[i:i + 254] for i in range(0, len(data), 254)] or [b'']
        secs = alloc(len(chunks), il)
        for i, (c, (t, s)) in enumerate(zip(chunks, secs)):
            o = offset(t, s)
            if i + 1 < len(secs):
                img[o], img[o + 1] = secs[i + 1]
            else:
                img[o], img[o + 1] = 0, len(c) + 1
            img[o + 2:o + 2 + len(c)] = c
        entries.append((fname, secs[0], len(secs)))
    # BAM
    b = offset(18, 0)
    img[b:b + 4] = bytes([18, 1, 0x41, 0])
    for t in range(1, 36):
        n = SECTORS[t - 1]
        bits = sum(1 << s for s in range(n) if s not in used[t])
        img[b + 4 * t:b + 4 * t + 4] = bytes([n - len(used[t]), bits & 255, (bits >> 8) & 255, (bits >> 16) & 255])
    img[b + 0x90:b + 0xa0] = petscii(name, 16)
    img[b + 0xa0:b + 0xa2] = b'\xa0\xa0'
    img[b + 0xa2:b + 0xa4] = petscii(ident, 2)
    img[b + 0xa4] = 0xa0
    img[b + 0xa5:b + 0xa7] = b'2A'
    img[b + 0xa7:b + 0xab] = b'\xa0' * 4
    # directory (one sector, up to 8 files)
    d = offset(18, 1)
    img[d], img[d + 1] = 0, 0xff
    for i, (fname, (t, s), n) in enumerate(entries):
        e = d + i * 32
        img[e + 2] = 0x82
        img[e + 3], img[e + 4] = t, s
        img[e + 5:e + 21] = petscii(fname, 16)
        img[e + 30], img[e + 31] = n & 255, n >> 8
    open(out, 'wb').write(img)


if __name__ == '__main__':
    main()
