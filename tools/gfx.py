#!/usr/bin/env python3
"""
gfx.py - builds the graphics of Polonaise C64 from descriptions in code, like
draw.ts of the browser version builds its sprites from rectangles.

The playing field is a multicolor bitmap: a cell of the field is 16x16 pixels,
8x16 multicolor pixels, 2x2 blocks of 4x8. Every block has the background
colour (black, code 00) and three colours of its own (01 and 10 from the screen
RAM, 11 from the colour RAM). Output (gen/):

  figures.bin   people: per shape 4 frames (bit 0 legs, bit 1 arms up) of 32 bytes
                (blocks top left, top right, bottom left, bottom right)
  cells.bin     floor variants, arrows, furniture, frame LEDs (32 bytes each)
  charset.bin   the character set of the text rows (font, HUD icons, panel, logo)
  sprites.bin   static hardware sprites (DJ, title dancers, sparkles)
  gfx.inc       constants and tables for the assembler
  preview.png   a mock-up of the field (only for looking at)

Usage: tools/gfx.py <polonaise source dir> <out dir>
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SRC = sys.argv[1] if len(sys.argv) > 1 else '/home/dennis/Projekte/polonaise-c64'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'gen'

# Pepto palette
PAL = [(0, 0, 0), (255, 255, 255), (104, 55, 43), (112, 164, 178), (111, 61, 134), (88, 141, 67), (53, 40, 121),
       (184, 199, 111), (111, 79, 37), (67, 57, 0), (154, 103, 89), (68, 68, 68), (108, 108, 108), (154, 210, 132),
       (108, 94, 181), (149, 149, 149)]
BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW, ORANGE, BROWN, LRED, DGREY, GREY, LGREEN, LBLUE, LGREY = range(16)

FLOOR_A, FLOOR_B = BLUE, BLUE

inc = []        # lines of gfx.inc


def const(name, value):
    inc.append('%s = %d' % (name, value))


def table(name, values):
    inc.append('%s:' % name)
    for i in range(0, len(values), 16):
        inc.append('    .byte ' + ','.join(str(v) for v in values[i:i + 16]))


# ---------------------------------------------------------------- people

H_SHORT, H_LONG, H_BUN, H_MOHAWK, H_CURLY, H_CAP, H_PONYTAIL, H_BALD = range(8)

# colours of draw.ts mapped to the C64 palette
SKIN = [LRED, LRED, ORANGE, ORANGE, BROWN, BROWN]
HAIR = [BLACK, BROWN, ORANGE, RED, YELLOW, LGREY]
PUNK = [PURPLE, CYAN, LGREEN]
SHIRT = [PURPLE, CYAN, YELLOW, LGREEN, LBLUE, ORANGE, WHITE, LRED, LBLUE, GREEN]
PANTS = [DGREY, GREY, LBLUE, BROWN, LGREY]
LOOKS = 64


def make_looks():
    looks = [None] * LOOKS
    for i in range(1, LOOKS):
        h = (i * 2654435761) & 0xffffffff
        h = (h ^ (h >> 13)) & 0xffffffff
        lk = dict(skin=SKIN[h % 6], style=(h >> 4) % 8, hair=HAIR[(h >> 8) % 6], shirt=SHIRT[(h >> 14) % 10],
                  pants=PANTS[(h >> 18) % 5], glasses=(h >> 25) % 7 == 0, chain=False)
        if lk['style'] == H_MOHAWK:
            lk['hair'] = PUNK[(h >> 11) % 3]
        if lk['style'] == H_CAP:
            lk['hair'] = SHIRT[(h >> 11) % 10]
        lk['dress'] = lk['style'] in (H_LONG, H_BUN, H_PONYTAIL) and (h >> 23) % 2 == 1
        # a colour must not vanish against its neighbour in the same block
        if lk['hair'] == lk['skin']:
            lk['hair'] = BROWN if lk['skin'] != BROWN else BLACK
        if lk['pants'] == lk['shirt']:
            lk['pants'] = DGREY
        looks[i] = lk
    looks[0] = dict(skin=ORANGE, hair=BLACK, shirt=WHITE, pants=WHITE, style=H_SHORT, glasses=True, chain=True,
                    dress=False)
    return looks


def paint(lk, legs, arms_up):
    """A person as a 8x16 grid of multicolor pixels: F floor, S skin, H hair, T shirt, P pants
    (legs under a dress: L), K black, G gold."""
    g = [['F'] * 8 for _ in range(16)]

    def put(x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if 0 <= xx < 8 and 0 <= yy < 16:
                    g[yy][xx] = c

    leg = 'L' if lk['dress'] else 'P'
    if lk['dress']:
        put(1, 11, 6, 3, 'T')
        put(2, 14, 1, 1, 'L')
        put(5, 14, 1, 1, 'L')
    else:
        put(2, 12, 4, 2, 'P')
        put(2, 14, 1, 1, 'P')
        put(5, 14, 1, 1, 'P')
    # shoes: one foot forward
    if legs:
        put(2, 15, 1, 1, 'K')
        put(5, 14, 2, 1, 'K')
        put(2, 14, 1, 1, leg)
    else:
        put(1, 14, 2, 1, 'K')
        put(5, 15, 1, 1, 'K')
        put(5, 14, 1, 1, leg)
    put(2, 8, 4, 4 if not lk['dress'] else 3, 'T')
    if arms_up:
        put(1, 3, 1, 5, 'S')
        put(6, 3, 1, 5, 'S')
        put(1, 8, 1, 1, 'T')
        put(6, 8, 1, 1, 'T')
    else:
        put(1, 8, 1, 2, 'T')
        put(6, 8, 1, 2, 'T')
        put(1, 10, 1, 1, 'S')
        put(6, 10, 1, 1, 'S')
    if lk['chain']:
        put(3, 8, 2, 1, 'G')
        put(3, 9, 2, 1, 'G')
    # head
    put(2, 1, 4, 7, 'S')
    put(1, 4, 1, 2, 'S')
    put(6, 4, 1, 2, 'S')
    st = lk['style']
    if st == H_SHORT:
        put(2, 0, 4, 2, 'H')
        put(2, 2, 1, 1, 'H')
        put(5, 2, 1, 1, 'H')
    elif st == H_LONG:
        put(2, 0, 4, 2, 'H')
        put(1, 1, 1, 6, 'H')
        put(6, 1, 1, 6, 'H')
        put(2, 2, 1, 1, 'H')
        put(5, 2, 1, 1, 'H')
    elif st == H_BUN:
        put(3, 0, 2, 1, 'H')
        put(2, 1, 4, 1, 'H')
        put(2, 2, 1, 1, 'H')
        put(5, 2, 1, 1, 'H')
    elif st == H_MOHAWK:
        put(3, 0, 2, 2, 'H')
    elif st == H_CURLY:
        put(1, 0, 6, 2, 'H')
        put(1, 2, 1, 2, 'H')
        put(6, 2, 1, 2, 'H')
        put(2, 2, 1, 1, 'H')
        put(5, 2, 1, 1, 'H')
    elif st == H_CAP:
        put(2, 0, 4, 2, 'H')
        put(1, 2, 6, 1, 'H')
    elif st == H_PONYTAIL:
        put(2, 0, 4, 2, 'H')
        put(2, 2, 1, 1, 'H')
        put(6, 1, 1, 2, 'H')
        put(7, 2, 1, 4, 'H')
    if lk['glasses']:
        put(2, 4, 4, 1, 'K')
        put(2, 5, 1, 1, 'K')
        put(5, 5, 1, 1, 'K')
    else:
        put(2, 4, 1, 1, 'K')
        put(5, 4, 1, 1, 'K')
    return g


def outline(g):
    """Floor pixels next to the person become the outline O."""
    out = [row[:] for row in g]
    for y in range(16):
        for x in range(8):
            if g[y][x] != 'F':
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < 8 and 0 <= yy < 16 and g[yy][xx] not in 'FO':
                    out[y][x] = 'O'
                    break
    return out


def codes(g, lk):
    """The 2 bit codes: top blocks 01 floor, 10 skin, 11 hair; bottom blocks 01 floor, 10 shirt,
    11 pants (legs, gold chain)."""
    rows = []
    for y in range(16):
        row = []
        for x in range(8):
            c = g[y][x]
            if c in 'OK':
                v = 0
            elif c == 'F':
                v = 1
            elif y < 8:
                v = 3 if c == 'H' else 2
            else:
                if c == 'T' or (c == 'P' and lk['chain']):
                    v = 2
                elif c == 'S':
                    v = 3 if lk['dress'] else 2
                else:
                    v = 3           # P, L, G
            row.append(v)
        rows.append(row)
    return rows


def blocks(rows):
    """32 bytes: the 4 blocks of a cell from an 8x16 grid of 2 bit codes."""
    out = bytearray()
    for by, bx in ((0, 0), (0, 4), (8, 0), (8, 4)):
        for y in range(by, by + 8):
            v = 0
            for x in range(bx, bx + 4):
                v = (v << 2) | rows[y][x]
            out.append(v)
    return bytes(out)


looks = make_looks()
shape_keys = []
figures = bytearray()
look_shape = []
for lk in looks:
    key = (lk['style'], lk['glasses'], lk['dress'], lk['chain'])
    if key not in shape_keys:
        shape_keys.append(key)
        for f in range(4):
            figures += blocks(codes(outline(paint(lk, f & 1, f >> 1)), lk))
    look_shape.append(shape_keys.index(key))


def bottom_11(lk):
    return YELLOW if lk['chain'] else (lk['skin'] if lk['dress'] else lk['pants'])


const('SHAPES', len(shape_keys))
table('look_skin', [lk['skin'] for lk in looks])
table('look_hair', [lk['hair'] for lk in looks])
table('look_shirt', [lk['shirt'] for lk in looks])
table('look_leg', [bottom_11(lk) for lk in looks])
table('look_shape', look_shape)

# ---------------------------------------------------------------- cells

cells = bytearray()
cell_names = []


def add_cell(name, rows):
    const('CELL_' + name, len(cell_names))
    cell_names.append(name)
    cells.extend(blocks(rows))


def grid(fill=1):
    return [[fill] * 8 for _ in range(16)]


def rect(g, x, y, w, h, v):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 <= xx < 8 and 0 <= yy < 16:
                g[yy][xx] = v


def disc(g, cx, cy, r, v, sx=0.5):
    """A disc in multicolor pixels (horizontal radius halved), centre in hires pixels."""
    for y in range(16):
        for x in range(8):
            px = x * 2 + 1
            if ((px - cx) / 2) ** 2 * 4 + (y - cy) ** 2 <= r * r + 0.5:
                g[y][x] = v


# floor with grain: 01 floor, 10 light grain, 00 dark grain
r = 12345
for variant in range(8):
    g = grid()
    for y in range(16):
        for x in range(8):
            r = (r * 1664525 + 1013904223) & 0xffffffff
            v = r >> 24
            if v < 5:
                g[y][x] = 2
            elif v > 250:
                g[y][x] = 0
    add_cell('FLOOR%d' % variant, g)
    # the darker squares of the checkerboard: the same grain over a fine dither of 00
    for y in range(16):
        for x in range(8):
            if g[y][x] == 1 and (y % 2 == 0) and (x + y // 2) % 2 == 0:
                g[y][x] = 0
    add_cell('FLOORD%d' % variant, g)

# arrows (11 yellow) on the plain floor: right, down, left, up
arrow_rows = {
    0: [(3, 5, 1, 6), (4, 6, 1, 4), (5, 7, 1, 2)],
    2: [(4, 5, 1, 6), (3, 6, 1, 4), (2, 7, 1, 2)],
    1: [(2, 6, 4, 1), (2, 7, 4, 1), (3, 8, 2, 1), (3, 9, 2, 1)],
    3: [(3, 6, 2, 1), (3, 7, 2, 1), (2, 8, 4, 1), (2, 9, 4, 1)],
}
for d in range(4):
    g = grid()
    for x, y, w, h in arrow_rows[d]:
        rect(g, x, y, w, h, 3)
    add_cell('ARROW%d' % d, g)

# DJ desk: rows 0..4 floor, desk from row 5: 00 outline, 10 desk, 11 light top; the bottom blocks
# 01 and 11 are LED colours (they change with the beat)
def desk(turntable, frame):
    g = grid()
    rect(g, 0, 6, 8, 10, 2)
    rect(g, 0, 6, 8, 1, 0)
    rect(g, 0, 7, 8, 1, 3)
    if turntable:
        disc(g, 8, 10, 3, 0)
        # the needle dot goes round
        pos = [(5, 9), (5, 11), (3, 11), (3, 9)][frame]
        g[10][3 + (frame in (1, 2))] = 3 if frame % 2 else 0
        g[10][4 - (frame in (1, 2))] = 3 if frame % 2 == 0 else 0
    else:
        for k in range(3):
            x = 1 + k * 2 + (k > 0)
            if x > 6:
                x = 6
            rect(g, x, 8, 1, 3, 0)
            g[8 + (frame + k) % 3][x] = 3
    rect(g, 0, 15, 8, 1, 0)
    # LEDs in row 13: codes 01 and 11 of the bottom blocks
    for k, x in enumerate((1, 3, 4, 6)):
        g[13][x] = 1 if k % 2 == 0 else 3
    return g


for f in range(3):
    add_cell('MIXER%d' % f, desk(False, f))
for f in range(4):
    add_cell('TURN%d' % f, desk(True, f))

# high table: 01 floor, 10 table, 11 highlight / drink
g = grid()
rect(g, 3, 13, 2, 2, 0)
disc(g, 8, 8, 6.4, 0)
disc(g, 8, 8, 5.4, 2)
disc(g, 7, 7, 3, 3)
rect(g, 4, 4, 1, 3, 0)
g[4][4] = 3
add_cell('TABLE', g)

# speaker: 00 frame, 01 box, 10 cone, 11 centre; the cone pumps to the beat
for f in range(2):
    g = grid(0)
    rect(g, 0, 1, 8, 14, 1)
    rect(g, 0, 1, 8, 1, 3)
    disc(g, 8, 9, 5.4, 2)
    disc(g, 8, 9, 3.4 + f, 0)
    rect(g, 3, 8, 2, 2, 3)
    rect(g, 3, 3, 2, 1, 2)
    add_cell('SPEAKER%d' % f, g)

# bar counter: top blocks 01 floor, 10 wood, 11 bottle/glass; bottom 01 light wood, 10 wood, 11 dark
for f in range(2):
    g = grid()
    rect(g, 0, 5, 8, 11, 2)
    rect(g, 0, 5, 8, 1, 0)
    rect(g, 0, 6, 8, 1, 3)
    if f == 0:
        rect(g, 2, 0, 1, 5, 3)          # bottle
        rect(g, 5, 2, 2, 3, 3)          # glass
        rect(g, 5, 2, 2, 1, 0)
    else:
        rect(g, 3, 0, 1, 5, 3)
        rect(g, 3, 0, 1, 1, 0)
    rect(g, 0, 8, 8, 1, 1)
    rect(g, 0, 15, 8, 1, 0)
    for x in range(0, 8, 3):
        rect(g, x, 10, 1, 5, 3)
    add_cell('BAR%d' % f, g)

# the frame: a column of 4x8 blocks with two LEDs each (01 and 10) - only the left half block is used
g = grid(0)
rect(g, 1, 1, 1, 2, 1)
rect(g, 1, 5, 1, 2, 2)
rect(g, 1, 9, 1, 2, 1)
rect(g, 1, 13, 1, 2, 2)
add_cell('LEDL', g)
g = grid(0)
rect(g, 6, 1, 1, 2, 1)
rect(g, 6, 5, 1, 2, 2)
rect(g, 6, 9, 1, 2, 1)
rect(g, 6, 13, 1, 2, 2)
add_cell('LEDR', g)

# colours of the furniture: per kind the colours of the top and the bottom blocks (01, 10, 11);
# 255 means the floor colour of the cell
DJ_TOP = (255, DGREY, LBLUE)
furn_colors = {
    'MIXER': (DJ_TOP, (PURPLE, DGREY, CYAN)),
    'TURN': (DJ_TOP, (PURPLE, DGREY, CYAN)),
    'TABLE': ((255, PURPLE, CYAN), (255, PURPLE, LBLUE)),
    'SPEAKER': ((BLACK, DGREY, GREY), (BLACK, DGREY, GREY)),
    'BAR': ((255, ORANGE, GREEN), (LRED, BROWN, ORANGE)),
}

# ---------------------------------------------------------------- charset

font = ImageFont.truetype(os.path.join(SRC, 'dist/assets/fonts/PressStart2P-Regular.ttf'), 8)


def glyph(ch):
    img = Image.new('L', (8, 8), 0)
    ImageDraw.Draw(img).text((0, 0), ch, font=font, fill=255)
    return [[1 if img.getpixel((x, y)) > 127 else 0 for x in range(8)] for y in range(8)]


def umlaut(base):
    g = glyph(base)
    # the letter loses a middle row and moves down; the dots sit above
    rows = [g[y] for y in (0, 1, 2, 4, 5, 6)]
    out = [[0, 1, 1, 0, 1, 1, 0, 0], [0] * 8] + [r[:] for r in rows]
    return out


def to_bytes(g):
    return bytes(sum(g[y][x] << (7 - x) for x in range(8)) for y in range(8))


charset = bytearray(2048)
charcodes = {}


def setchar(code, data):
    charset[code * 8:code * 8 + 8] = data


TEXT_CHARS = " ABCDEFGHIJKLMNOPQRSTUVWXYZ"
for i, ch in enumerate(TEXT_CHARS):
    setchar(i, to_bytes(glyph(ch)))
    charcodes[ch] = i
for i, ch in enumerate("ÄÖÜ"):
    setchar(27 + i, to_bytes(umlaut("AOU"[i])))
    charcodes[ch] = 27 + i
for i in range(10):
    setchar(30 + i, to_bytes(glyph(str(i))))
    charcodes[str(i)] = 30 + i
PUNCT = ".,:;!?'-/+()=*#%&<>\""
for i, ch in enumerate(PUNCT):
    setchar(40 + i, to_bytes(glyph(ch)))
    charcodes[ch] = 40 + i


def pix(rows):
    return bytes(int(r.replace('.', '0').replace('X', '1'), 2) for r in rows)


# HUD icons and other graphics, from code 64
ICONS = {
    'HEART': ['.XX.XX..', 'XXXXXXX.', 'XXXXXXX.', '.XXXXX..', '..XXX...', '...X....', '........', '........'],
    'PERSON': ['..XXX...', '..XXX...', '...X....', '.XXXXX..', 'X.XXX.X.', '..X.X...', '..X.X...', '.XX.XX..'],
    'NOTE': ['...XXXX.', '...X..X.', '...X..X.', '...X..X.', '.XXX.XX.', 'XXXXXXX.', 'XXX.XXX.', '........'],
    'LEFT': ['....X...', '...XX...', '..XXX...', '.XXXX...', '..XXX...', '...XX...', '....X...', '........'],
    'RIGHT': ['..X.....', '..XX....', '..XXX...', '..XXXX..', '..XXX...', '..XX....', '..X.....', '........'],
    'UP': ['........', '...X....', '..XXX...', '.XXXXX..', 'XXXXXXX.', '........', '........', '........'],
    'DOWN': ['........', 'XXXXXXX.', '.XXXXX..', '..XXX...', '...X....', '........', '........', '........'],
    'CURSOR': ['........', '........', '........', '........', '........', '........', 'XXXXXXXX', 'XXXXXXXX'],
    'FULL': ['XXXXXXXX'] * 8,
    # panel frame: corners and edges (2 pixel lines)
    'TL': ['........', '........', '........', '...XXXXX', '...XXXXX', '...XX...', '...XX...', '...XX...'],
    'TR': ['........', '........', '........', 'XXXXX...', 'XXXXX...', '...XX...', '...XX...', '...XX...'],
    'BL': ['...XX...', '...XX...', '...XX...', '...XXXXX', '...XXXXX', '........', '........', '........'],
    'BR': ['...XX...', '...XX...', '...XX...', 'XXXXX...', 'XXXXX...', '........', '........', '........'],
    'HZ': ['........', '........', '........', 'XXXXXXXX', 'XXXXXXXX', '........', '........', '........'],
    'VL': ['...XX...'] * 8,
    'LINE': ['........', '........', '........', 'XXXXXXXX', '........', '........', '........', '........'],
}
code = 64
for name, rows in ICONS.items():
    setchar(code, pix(rows))
    const('CH_' + name, code)
    code += 1
# bars: 0..8 pixels filled from the left, in rows 2..5
const('CH_BAR0', code)
for n in range(9):
    rows = ['........'] * 8
    s = 'X' * n + '.' * (8 - n)
    rows = ['........', '........', s, s, s, s, '........', '........']
    setchar(code, pix(rows))
    code += 1
const('CH_FREE', code)

# logo "POLONAISE": the font scaled 3x, multicolor (01 glow, 11 letter), from code LOGO_FIRST
LOGO_FIRST = 128
logo_w = 9 * 3 * 8 // 2
img = [[0] * (9 * 24) for _ in range(24)]
for i, ch in enumerate('POLONAISE'):
    g = glyph(ch)
    for y in range(8):
        for x in range(8):
            if g[y][x]:
                for yy in range(3):
                    for xx in range(3):
                        img[y * 3 + yy][i * 24 + x * 3 + xx] = 1
# to multicolor pixels (pairs of hires pixels)
W = 9 * 12
mc = [[0] * W for _ in range(24)]
for y in range(24):
    for x in range(W):
        if img[y][2 * x] or img[y][2 * x + 1]:
            mc[y][x] = 1
for y in range(24):
    for x in range(W):
        if mc[y][x] == 0:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < W and 0 <= yy < 24 and mc[yy][xx] == 1:
                    mc[y][x] = 3
                    break
logo_map = []
code = LOGO_FIRST
seen = {bytes(8): 0}
for cy in range(3):
    row = []
    for cx in range(27):
        data = bytes(sum(mc[cy * 8 + y][cx * 4 + x] << (6 - 2 * x) for x in range(4)) for y in range(8))
        if data not in seen:
            seen[data] = code
            setchar(code, data)
            code += 1
        row.append(seen[data])
    logo_map.append(row)
const('CH_POOL', code)
table('logo_map', sum(logo_map, []))

# ---------------------------------------------------------------- sprites

sprites = bytearray()
sprite_names = []


def add_sprite(name, rows):
    """rows: 21 strings of 12 multicolor pixels: '.' empty, '1' d025, '2' own colour, '3' d026."""
    const('SPR_' + name, len(sprite_names))
    sprite_names.append(name)
    data = bytearray(64)
    for y, row in enumerate(rows[:21]):
        for x, c in enumerate(row[:12]):
            v = '.123'.index(c) if c in '.123' else 0
            data[y * 3 + x // 4] |= v << (6 - 2 * (x % 4))
    sprites.extend(data)


def figure_sprite(lk, legs, arms_up, top=0):
    """A person as a multicolor sprite: 1 black (outline, hair, pants), 3 skin, 2 shirt."""
    g = outline(paint(lk, legs, arms_up))
    rows = ['.' * 12] * 21
    rows = [list(r) for r in rows]
    for y in range(16):
        for x in range(8):
            c = g[y][x]
            v = '.' if c == 'F' else '3' if c in 'SL' else '2' if c in 'TG' else '1'
            if lk['chain'] and c == 'P':
                v = '2'
            rows[top + y][x + 2] = v
    return [''.join(r) for r in rows]


for f in range(4):
    add_sprite('DANCER%d' % f, figure_sprite(dict(looks[7], glasses=False), f & 1, f >> 1))
for f in range(4):
    add_sprite('LEADER%d' % f, figure_sprite(looks[0], f & 1, f >> 1))

# the DJ behind the desk: head and shoulders, 1 black, 2 pink (headphones), 3 skin
dj = dict(skin=LRED, hair=BLACK, shirt=BLACK, pants=BLACK, style=H_SHORT, glasses=False, chain=False, dress=False)
for f in range(2):
    rows = [list(r) for r in figure_sprite(dj, 0, f == 1, top=4)]
    # headphones: a pink band over the hair and the ear cups (sprite rows = figure rows + 4)
    for x in range(4, 8):
        rows[4][x] = '2'
    for y in (7, 8, 9):
        rows[y][2] = '2'
        rows[y][9] = '2'
    # the shirt in the DJ's colour, cut where the desk begins (figure row 10)
    for y in range(21):
        for x in range(12):
            if y >= 4 + 11:
                rows[y][x] = '.'
            elif y >= 12 and rows[y][x] == '2' and not (x in (2, 9)):
                rows[y][x] = '2'
    add_sprite('DJ%d' % f, [''.join(r) for r in rows])

# sparkles of a star, dizzy stars: generated in code; a 2x2 dot sprite for confetti is drawn at runtime

# ---------------------------------------------------------------- mini font for sprite texts (4x5)

MINI = {
    '0': ['XXX', 'X.X', 'X.X', 'X.X', 'XXX'], '1': ['.X.', 'XX.', '.X.', '.X.', 'XXX'],
    '2': ['XXX', '..X', 'XXX', 'X..', 'XXX'], '3': ['XXX', '..X', '.XX', '..X', 'XXX'],
    '4': ['X.X', 'X.X', 'XXX', '..X', '..X'], '5': ['XXX', 'X..', 'XXX', '..X', 'XXX'],
    '6': ['XXX', 'X..', 'XXX', 'X.X', 'XXX'], '7': ['XXX', '..X', '.X.', '.X.', '.X.'],
    '8': ['XXX', 'X.X', 'XXX', 'X.X', 'XXX'], '9': ['XXX', 'X.X', 'XXX', '..X', 'XXX'],
    '+': ['...', '.X.', 'XXX', '.X.', '...'], '!': ['.X.', '.X.', '.X.', '...', '.X.'],
    ':': ['...', '.X.', '...', '.X.', '...'], ' ': ['...'] * 5, '-': ['...', '...', 'XXX', '...', '...'],
    'A': ['XXX', 'X.X', 'XXX', 'X.X', 'X.X'], 'B': ['XX.', 'X.X', 'XX.', 'X.X', 'XX.'],
    'C': ['XXX', 'X..', 'X..', 'X..', 'XXX'], 'D': ['XX.', 'X.X', 'X.X', 'X.X', 'XX.'],
    'E': ['XXX', 'X..', 'XX.', 'X..', 'XXX'], 'F': ['XXX', 'X..', 'XX.', 'X..', 'X..'],
    'G': ['XXX', 'X..', 'X.X', 'X.X', 'XXX'], 'H': ['X.X', 'X.X', 'XXX', 'X.X', 'X.X'],
    'I': ['XXX', '.X.', '.X.', '.X.', 'XXX'], 'J': ['..X', '..X', '..X', 'X.X', 'XXX'],
    'K': ['X.X', 'X.X', 'XX.', 'X.X', 'X.X'], 'L': ['X..', 'X..', 'X..', 'X..', 'XXX'],
    'M': ['X.X', 'XXX', 'XXX', 'X.X', 'X.X'], 'N': ['XX.', 'X.X', 'X.X', 'X.X', 'X.X'],
    'O': ['XXX', 'X.X', 'X.X', 'X.X', 'XXX'], 'P': ['XXX', 'X.X', 'XXX', 'X..', 'X..'],
    'Q': ['XXX', 'X.X', 'X.X', 'XXX', '..X'], 'R': ['XX.', 'X.X', 'XX.', 'X.X', 'X.X'],
    'S': ['XXX', 'X..', 'XXX', '..X', 'XXX'], 'T': ['XXX', '.X.', '.X.', '.X.', '.X.'],
    'U': ['X.X', 'X.X', 'X.X', 'X.X', 'XXX'], 'V': ['X.X', 'X.X', 'X.X', 'X.X', '.X.'],
    'W': ['X.X', 'X.X', 'XXX', 'XXX', 'X.X'], 'X': ['X.X', 'X.X', '.X.', 'X.X', 'X.X'],
    'Y': ['X.X', 'X.X', '.X.', '.X.', '.X.'], 'Z': ['XXX', '..X', '.X.', 'X..', 'XXX'],
}
MINI_CHARS = "0123456789+!: -ABCDEFGHIJKLMNOPQRSTUVWXYZ"
mini = bytearray()
for ch in MINI_CHARS:
    for row in MINI[ch]:
        mini.append(int(row.replace('.', '0').replace('X', '1'), 2) << 5)
const('MINI_COUNT', len(MINI_CHARS))

# ---------------------------------------------------------------- motion tables

import math


def signed(v):
    return int(round(v)) & 255


# the conga line over the title sways: 3 * sin(t * 2 pi / 128)
table('conga_sin', [signed(3 * math.sin(2 * math.pi * i / 128)) for i in range(128)])
# sparkles around a star (radius 10 x 7) and dizzy stars (7 x 2), 64 steps
table('spark_dx', [signed(10 * math.cos(2 * math.pi * i / 64)) for i in range(64)])
table('spark_dy', [signed(7 * math.sin(2 * math.pi * i / 64)) for i in range(64)])
table('dizzy_dx', [signed(7 * math.cos(2 * math.pi * i / 64)) for i in range(64)])
table('dizzy_dy', [signed(2 * math.sin(2 * math.pi * i / 64)) for i in range(64)])
# confetti: start velocities (8.8) for 4 speeds 0.6 + 0.25 k and 64 angles, y with -0.4
vx, vy = [], []
for k in range(4):
    v = 0.6 + 0.25 * k
    for i in range(64):
        a = 2 * math.pi * i / 64
        vx.append(int(round(math.cos(a) * v * 256)) & 0xffff)
        vy.append(int(round((math.sin(a) * v - 0.4) * 256)) & 0xffff)
table('conf_vx_lo', [v & 255 for v in vx])
table('conf_vx_hi', [v >> 8 for v in vx])
table('conf_vy_lo', [v & 255 for v in vy])
table('conf_vy_hi', [v >> 8 for v in vy])

# ---------------------------------------------------------------- output

os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, 'figures.bin'), 'wb').write(figures)
open(os.path.join(OUT, 'cells.bin'), 'wb').write(cells)
open(os.path.join(OUT, 'charset.bin'), 'wb').write(charset)
open(os.path.join(OUT, 'sprites.bin'), 'wb').write(sprites)
open(os.path.join(OUT, 'mini.bin'), 'wb').write(mini)

const('FLOOR_A', FLOOR_A)
const('FLOOR_B', FLOOR_B)
for kind, (top, bottom) in furn_colors.items():
    table('fcol_' + kind.lower(), list(top) + list(bottom))
open(os.path.join(OUT, 'gfx.inc'), 'w').write('; generated by tools/gfx.py\n' + '\n'.join(inc) + '\n')

# the character codes of the text font for tools/text.py
with open(os.path.join(OUT, 'charcodes.py'), 'w') as f:
    f.write('CODES = %r\nMINI = %r\n' % (charcodes, MINI_CHARS))

# ---------------------------------------------------------------- preview

def render_cell(img, cx, cy, data, top, bottom):
    for b, (by, bx) in enumerate(((0, 0), (0, 4), (8, 0), (8, 4))):
        cols = (BLACK,) + (top if b < 2 else bottom)
        for y in range(8):
            v = data[b * 8 + y]
            for x in range(4):
                c = (v >> (6 - 2 * x)) & 3
                for k in range(2):
                    img.putpixel((cx + (bx + x) * 2 + k, cy + by + y), PAL[cols[c]])


def preview():
    img = Image.new('RGB', (320, 200))
    cellbin = bytes(cells)
    figs = bytes(figures)
    layout = ['SS.....DDDDD.....SS', 'SS...............SS', '..T......T......T..', '...................',
              '...................', '.....T.......T.....', '...................', '.....BBBBBBBBB.....',
              '...................', '...................', '..T......T......T..', '...................']
    n = 0
    for y in range(12):
        for x in range(19):
            px, py = 8 + x * 16, 8 + y * 16
            floor = FLOOR_A if (x + y) % 2 == 0 else FLOOR_B
            ch = layout[y][x]
            fl = lambda t: tuple(floor if c == 255 else c for c in t)
            if ch == 'S':
                k = cell_names.index('SPEAKER0')
                t, b = furn_colors['SPEAKER']
            elif ch == 'T':
                k = cell_names.index('TABLE')
                t, b = furn_colors['TABLE']
            elif ch == 'B':
                k = cell_names.index('BAR%d' % (x % 2))
                t, b = furn_colors['BAR']
            elif ch == 'D':
                i = x - 7
                k = cell_names.index('TURN0' if i % 2 else 'MIXER%d' % (i % 3))
                t, b = furn_colors['TURN']
            else:
                if 3 <= y <= 9 and n < 64 and (x * 7 + y * 3) % 4 == 0:
                    lk = looks[n]
                    s = look_shape[n]
                    f = (x + y) % 4
                    render_cell(img, px, py, figs[(s * 4 + f) * 32:(s * 4 + f + 1) * 32],
                                (floor, lk['skin'], lk['hair']), (floor, lk['shirt'], bottom_11(lk)))
                    n += 1
                    continue
                k = (x * 3 + y * 5) % 8 * 2 + (x + y) % 2
                t = b = (floor, LBLUE if floor == BLUE else GREY, YELLOW)
            render_cell(img, px, py, cellbin[k * 32:(k + 1) * 32], fl(t), fl(b))
    for y in range(24):
        render_cell_half = cells[cell_names.index('LEDL') * 32:]
    img = img.resize((960, 600), Image.NEAREST)
    img.save(os.path.join(OUT, 'preview.png'))


preview()
print('shapes %d, cells %d, chars up to %d, sprites %d' % (len(shape_keys), len(cell_names), code, len(sprite_names)))
