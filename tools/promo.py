#!/usr/bin/env python3
# promo.py: fake 1980s promotional material for the README (box, manual and disk; magazine ad).
# Draws SVG, renders it with Inkscape and writes docs/packshot.webp and docs/ad.webp.
# The ad uses the screenshots docs/shot-title.png and docs/shot-game*.png (Denise, see README).
# The disco man and the glitter "Polonaise" lettering are cut out of the arcade-system logo artwork.
# Run with tools/venv/bin/python (needs Pillow and numpy).
import base64, io, math, os, random, subprocess, sys, tempfile

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, 'docs')
FONTS = os.path.join(ROOT, '..', 'polonaise', 'public', 'assets', 'fonts')
ARCADE_LOGO = os.path.join(ROOT, '..', 'arcade-system', 'tools', 'logo-polonaise-source.webp')

INK = '#140a2c'

LOGO = 'Fira Sans Compressed Heavy'
COND = 'Fira Sans Condensed'
PIXEL = 'Press Start 2P'


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')


# --- the dancers (cartoon people like the arcade logo's disco man, painted in the light of the ball) ---

def mix(a, b, t):
    a, b = [int(a[i:i + 2], 16) for i in (1, 3, 5)], [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return '#%02x%02x%02x' % tuple(round(x + (y - x) * t) for x, y in zip(a, b))


_ids = [0]


def painted(d, base, sw=2.4):
    """A shape painted like the box art: soft shadow on the side away from the mirror ball (top right),
    a light edge towards it and an outline a little darker than the paint."""
    _ids[0] += 1
    n = _ids[0]
    shade, light, line = mix(base, '#2a1660', .42), mix(base, '#f4f0ff', .5), mix(base, '#140a24', .72)
    return ('<defs><path id="p%d" d="%s"/><clipPath id="c%d"><use href="#p%d"/></clipPath>'
            '<mask id="m%d"><use href="#p%d" fill="#fff"/><use href="#p%d" fill="#000" transform="translate(-3,4)" '
            'filter="url(#soft2)"/></mask></defs>'
            '<g clip-path="url(#c%d)"><use href="#p%d" fill="%s"/>'
            '<use href="#p%d" fill="%s" transform="translate(6,-6)" filter="url(#soft3)"/>'
            '<use href="#p%d" fill="%s" mask="url(#m%d)" opacity=".85"/></g>'
            '<use href="#p%d" fill="none" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>'
            % (n, d, n, n, n, n, n, n, n, shade, n, base, n, light, n, n, line, sw))


def smooth(pts):
    """Catmull-Rom through the points, as cubic segments (without the initial M)."""
    p = [pts[0]] + list(pts) + [pts[-1]]
    o = []
    for i in range(1, len(p) - 2):
        c1 = (p[i][0] + (p[i + 1][0] - p[i - 1][0]) / 6, p[i][1] + (p[i + 1][1] - p[i - 1][1]) / 6)
        c2 = (p[i + 1][0] - (p[i + 2][0] - p[i][0]) / 6, p[i + 1][1] - (p[i + 2][1] - p[i][1]) / 6)
        o.append('C%.1f,%.1f %.1f,%.1f %.1f,%.1f' % (c1 + c2 + p[i + 1]))
    return ' '.join(o)


def tube(pts, ws):
    """A limb through the points, tapering through the widths, with round ends."""
    L, R, T = [], [], []
    for i, (x, y) in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        k = math.hypot(tx, ty) or 1
        tx, ty = tx / k, ty / k
        T.append((tx, ty))
        h = ws[i] / 2
        L.append((x - ty * h, y + tx * h))
        R.append((x + ty * h, y - tx * h))

    def cap(p, q, t, w):
        return 'C%.1f,%.1f %.1f,%.1f %.1f,%.1f' % (p[0] + t[0] * w * .7, p[1] + t[1] * w * .7,
                                                   q[0] + t[0] * w * .7, q[1] + t[1] * w * .7, q[0], q[1])
    return ('M%.1f,%.1f %s %s %s %s Z' % (L[0] + (smooth(L), cap(L[-1], R[-1], T[-1], ws[-1]), smooth(R[::-1]),
                                                 cap(R[0], L[0], (-T[0][0], -T[0][1]), ws[0]))))


def bumpy(cx, cy, r, n, amp, rot=0):
    """A scalloped round shape: curls, an afro, a bun."""
    pt = [(cx + r * math.cos(rot + 2 * math.pi * i / n), cy + r * math.sin(rot + 2 * math.pi * i / n)) for i in range(n + 1)]
    o = ['M%.1f,%.1f' % pt[0]]
    for i in range(n):
        a = rot + 2 * math.pi * (i + .5) / n
        o.append('Q%.1f,%.1f %.1f,%.1f' % ((cx + (r + amp) * math.cos(a), cy + (r + amp) * math.sin(a)) + pt[i + 1]))
    return ' '.join(o) + ' Z'


def strands(paths, col, w=1.4, op=.5):
    return ''.join('<path d="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="round" opacity="%.2f"/>'
                   % (p, col, w, op) for p in paths)


def hand(x, y, angle, skin):
    """A cartoon hand at the wrist (x, y), fingers pointing at angle (degrees)."""
    return ('<g transform="translate(%.1f,%.1f) rotate(%.1f)">%s%s</g>'
            % (x, y, angle, painted('M-3,-6 C4,-8 11,-6 13,-1 C14,3 11,7 4,7 C-1,7 -4,4 -4,0 Z', skin, 2.2),
               '<path d="M3,-6 C3,-11 8,-12 9,-7" fill="%s" stroke="%s" stroke-width="2" stroke-linecap="round"/>'
               % (skin, mix(skin, '#140a24', .72))))


def shoe(ax, ay, col):
    return painted('M%.1f,%.1f C%.1f,%.1f %.1f,%.1f %.1f,%.1f C%.1f,%.1f %.1f,%.1f %.1f,%.1f L%.1f,%.1f Z'
                   % (ax - 8, ay + 1, ax - 9, ay - 8, ax + 3, ay - 9, ax + 9, ay - 6,
                      ax + 17, ay - 4, ax + 22, ay + 1, ax + 20, ay + 6, ax - 8, ay + 6), col, 2.2) + \
        '<path d="M%.1f,%.1f L%.1f,%.1f" stroke="%s" stroke-width="2.5" stroke-linecap="round"/>' \
        % (ax - 7, ay + 5, ax + 19, ay + 5, mix(col, '#000000', .55))


HEAD = ('M-19,-136 C-21,-156 -8,-170 8,-170 C24,-170 32,-158 31,-142 C31,-136 33,-131 33,-127 C33,-122 31,-120 30,-117 '
        'C29,-108 23,-101 13,-100 C3,-99 -7,-103 -13,-110 C-18,-116 -19,-126 -19,-136 Z')


def hair(kind, col):
    """(behind the head, in front of the head)"""
    dark = mix(col, '#000000', .45)
    lite = mix(col, '#ffffff', .45)
    if kind == 'flat':  # the disco man's flat top
        return ('', painted('M-21,-128 C-24,-150 -23,-172 -10,-178 L20,-178 C30,-177 34,-168 32,-152 C30,-148 28,-150 26,-153 '
                            'C20,-158 6,-158 0,-152 C-6,-146 -10,-138 -12,-127 Z', col)
                + strands(['M%d,%d c2,-3 5,-3 6,0' % (x, y) for x, y in
                           [(-16, -168), (-6, -172), (4, -173), (14, -172), (22, -168), (-18, -156), (-8, -162), (2, -164),
                            (12, -164), (22, -160), (-17, -144), (-12, -152)]], '#6a5040', 1.6, .6))
    if kind == 'long':
        return (painted('M-18,-150 C-32,-124 -32,-98 -18,-86 C-9,-80 0,-86 2,-96 L6,-150 Z', col)
                + strands(['M-20,-140 C-26,-120 -24,-100 -16,-90', 'M-12,-138 C-16,-120 -14,-104 -8,-94'], dark),
                painted('M-21,-126 C-26,-160 -8,-176 10,-174 C26,-173 34,-160 32,-140 C28,-150 20,-156 12,-151 '
                        'C6,-158 -4,-156 -10,-148 C-13,-142 -14,-134 -15,-124 Z', col)
                + strands(['M-14,-160 C-6,-168 8,-170 20,-164', 'M-16,-146 C-12,-156 -2,-160 8,-158'], lite, 1.6, .6))
    if kind == 'afro':
        return (painted(bumpy(4, -146, 34, 16, 5), col)
                + strands(['M%d,%d c1,-3 4,-3 5,0' % (x, y) for x, y in
                           [(-14, -164), (-2, -172), (12, -170), (24, -160), (-20, -148), (-18, -132)]], '#6a5040', 1.4, .6), '')
    if kind == 'punk':
        return ('', painted('M-10,-160 C-14,-172 -12,-184 -6,-190 C-4,-182 0,-178 2,-176 C2,-186 8,-194 14,-196 '
                            'C12,-186 14,-180 18,-176 C20,-184 26,-188 32,-188 C28,-180 28,-172 30,-164 '
                            'C20,-169 2,-169 -10,-160 Z', col)
                + strands(['M-4,-166 C-6,-174 -6,-180 -4,-184', 'M10,-170 C10,-178 11,-186 13,-190'], lite, 1.4, .6))
    if kind == 'bun':
        return (painted(bumpy(-14, -170, 11, 9, 2.5), col),
                painted('M-21,-128 C-25,-158 -8,-174 10,-173 C26,-172 34,-160 32,-144 C26,-154 14,-158 4,-155 '
                        'C-6,-152 -12,-144 -14,-128 Z', col)
                + strands(['M-14,-150 C-10,-160 0,-166 12,-166', 'M-8,-140 C-6,-150 2,-156 14,-158'], dark, 1.3, .45))
    return ('', painted('M-21,-128 C-25,-158 -8,-174 10,-173 C26,-172 34,-160 32,-144 C24,-154 6,-158 -12,-140 Z', col))


def face(d):
    skin, ink = d['skin'], mix(d['skin'], '#140a24', .8)
    o = [painted('M-17,-136 C-25,-137 -26,-120 -17,-117 C-13,-117 -12,-122 -12,-127 C-12,-132 -13,-136 -17,-136 Z', skin, 2.2),
         '<path d="M-18,-131 C-15,-129 -15,-124 -18,-122" fill="none" stroke="%s" stroke-width="1.6" opacity=".5"/>' % ink,
         '<ellipse cx="6" cy="-117" rx="6" ry="4" fill="#ff6f8f" opacity=".35" filter="url(#soft2)"/>'
         '<ellipse cx="28" cy="-118" rx="3.5" ry="3.5" fill="#ff6f8f" opacity=".35" filter="url(#soft2)"/>']
    if d.get('shades'):  # aviators like the disco man's
        for lens in ('M2,-139 L19,-139 C20,-130 17,-123 11,-123 C5,-123 1,-130 2,-139 Z',
                     'M21,-139 L33,-139 C34,-131 31,-124 27,-124 C23,-124 20,-130 21,-139 Z'):
            o.append('<path d="%s" fill="url(#lens)" stroke="#0c0c10" stroke-width="2"/>' % lens)
        o.append('<path d="M19,-137 L21,-137 M2,-137 L-14,-131" stroke="#0c0c10" stroke-width="2"/>')
        o.append('<path d="M6,-135 L12,-135 M24,-135 L29,-135" stroke="#fff" stroke-opacity=".55" stroke-width="1.5"/>')
    else:
        for ex, rx in ((11, 3.6), (26, 3.0)):
            o.append('<ellipse cx="%d" cy="-131" rx="%.1f" ry="4.6" fill="#fff"/><ellipse cx="%.1f" cy="-130.5" rx="%.1f" '
                     'ry="3.6" fill="%s"/><circle cx="%.1f" cy="-132" r="1.1" fill="#fff"/>'
                     % (ex, rx, ex + 1, rx * .7, ink, ex + 1.8))
            o.append('<path d="M%.1f,-134 C%.1f,-137 %.1f,-137 %.1f,-134" fill="none" stroke="%s" stroke-width="1.8" '
                     'stroke-linecap="round"/>' % (ex - rx - .5, ex - 1, ex + 1, ex + rx + .5, ink))
        o.append('<path d="M5,-141 C8,-144 13,-144 16,-142 M22,-143 C25,-144 28,-143 30,-141" fill="none" stroke="%s" '
                 'stroke-width="2.2" stroke-linecap="round"/>' % mix(d['haircol'], '#140a24', .4))
        if d.get('glasses'):
            o.append('<circle cx="11" cy="-131" r="7.5" fill="#dff4ff" fill-opacity=".2" stroke="#6a5a7a" stroke-width="1.8"/>'
                     '<circle cx="26.5" cy="-131" r="5.5" fill="#dff4ff" fill-opacity=".2" stroke="#6a5a7a" stroke-width="1.8"/>'
                     '<path d="M18.5,-132 L21,-132 M3.5,-132 L-14,-129" stroke="#6a5a7a" stroke-width="1.8"/>')
    o.append(painted('M29,-132 C34,-129 37,-123 33,-119 C31,-118 28,-119 27,-121 Z', skin, 1.8))
    if d.get('moustache'):
        o.append('<path d="M14,-116 C18,-120 25,-120 31,-116 C32,-114 30,-113 28,-114 C24,-116 19,-116 16,-113 Z" fill="%s" '
                 'stroke="#000" stroke-width=".8"/>' % d['haircol'])
        o.append('<path d="M16,-110 C20,-107 25,-107 28,-110" fill="#a33a46" stroke="%s" stroke-width="1.8"/>' % ink)
    else:
        o.append('<path d="M13,-115 C16,-106 25,-106 29,-115 C23,-113 18,-113 13,-115 Z" fill="#7a2232" stroke="%s" '
                 'stroke-width="1.8" stroke-linejoin="round"/>' % ink)
        o.append('<path d="M15,-114.4 C19,-112.6 23,-112.6 27.5,-114.4 L27,-112.6 C23,-111.6 19,-111.6 15.5,-112.8 Z" fill="#fff"/>')
    return ''.join(o)


# leg poses: (back leg, front leg) as hip, knee, ankle
POSES = [
    ([(-5, -60), (-10, -32), (-16, -6)], [(12, -60), (20, -33), (22, -6)]),   # stepping
    ([(-3, -60), (-3, -32), (-5, -6)], [(12, -60), (29, -43), (31, -17)]),    # kicking forward
    ([(-5, -60), (-15, -36), (-27, -24)], [(12, -60), (14, -32), (14, -6)]),  # heel up behind
]


def dancer(x, y, sc, rot, d, gap, pose, lead=False):
    """One dancer facing right, feet at (x, y); gap: distance to the dancer in front."""
    o = ['<g transform="translate(%.1f,%.1f) rotate(%.1f) scale(%.3f)">' % (x, y, rot, sc)]
    skin, top, bottom = d['skin'], d['top'], d['bottom']
    sleeve = top if d.get('sleeves') else skin
    back_hair, front_hair = hair(d['hair'], d['haircol'])
    g = gap / sc

    def arm(sh, el, wr, hand_angle):
        s = painted(tube([sh, el, wr], [14, 11.5, 9]), sleeve)
        if not d.get('sleeves'):  # short sleeve over the skin
            mid = (sh[0] + (el[0] - sh[0]) * .5, sh[1] + (el[1] - sh[1]) * .5)
            s += painted(tube([sh, mid], [17, 15]), top)
        return s + hand(wr[0], wr[1], hand_angle, skin)

    # back arm (behind the body): on the hip for the leader, else on the shoulder in front
    if lead:
        o.append(arm((-12, -106), (-29, -88), (-15, -72), 30))
    else:
        o.append(arm((-8, -108), (g * .35, -88), (g - 32, -104), 25))
    # legs and shoes
    flare = d.get('flares')
    for leg in POSES[pose]:
        if d.get('dress'):
            o.append(painted(tube(leg, [13, 10.5, 8]), skin))
        else:
            o.append(painted(tube(leg, [18, 15, 19 if flare else 12.5]), bottom))
        o.append(shoe(leg[2][0], leg[2][1], d['shoes']))
    # body
    if d.get('dress'):
        o.append(painted('M-16,-112 C-7,-120 17,-121 25,-113 C28,-102 26,-90 24,-82 C30,-66 36,-52 40,-42 '
                         'C20,-33 -10,-33 -30,-43 C-24,-56 -20,-70 -17,-82 C-20,-94 -20,-104 -16,-112 Z', top))
        o.append(strands(['M4,-80 C2,-64 0,-50 -2,-38', 'M18,-78 C22,-64 26,-52 30,-42'], mix(top, '#000000', .4), 1.6, .4))
    else:
        o.append(painted('M-17,-112 C-8,-120 18,-121 26,-113 C30,-100 29,-82 26,-64 C14,-60 -6,-60 -16,-64 '
                         'C-19,-82 -21,-100 -17,-112 Z', top))
        o.append(painted('M-17,-70 L27,-70 C28,-64 28,-60 27,-56 C14,-52 -6,-52 -17,-56 C-18,-60 -18,-66 -17,-70 Z', bottom))
        o.append(strands(['M-8,-100 C-4,-92 -4,-84 -8,-76', 'M20,-104 C16,-96 18,-88 22,-80'], mix(top, '#000000', .4), 1.5, .35))
        if d.get('collar'):  # the gold v-neck and belt
            o.append('<path d="M2,-117 L12,-92 L22,-117" fill="%s" stroke="%s" stroke-width="4" stroke-linejoin="round"/>'
                     % (skin, d['collar']))
            o.append('<path d="M-17,-68 C-4,-66 14,-66 27,-68" fill="none" stroke="%s" stroke-width="4.5"/>' % d['collar'])
            o.append('<path d="M-17,-69.6 C-4,-67.6 14,-67.6 27,-69.6" fill="none" stroke="#fff6c8" stroke-width="1.2"/>')
    # front arm on the shoulder in front (under the big head)
    if not lead:
        o.append(arm((20, -106), (g * .5, -90), (g - 20, -106), 35))
    # neck and head
    o.append(painted(tube([(5, -118), (6, -104)], [13, 13]), skin))
    o.append(back_hair)
    o.append(painted(HEAD, skin))
    o.append(face(d))
    o.append(front_hair)
    # the leader's front arm points up (the disco pose)
    if lead:
        o.append(painted(tube([(22, -108), (37, -130), (40, -158)], [14, 11.5, 10]), sleeve))
        o.append(painted(tube([(40, -168), (41, -190)], [6.5, 5.5]), skin, 2))
        o.append(painted('M32,-170 C31,-162 33,-156 40,-155 C47,-155 49,-162 48,-170 C46,-174 34,-174 32,-170 Z', skin, 2.2))
    o.append('</g>')
    return ''.join(o)


CAST = [  # leader first, in the colors of the arcade version (a little less neon)
    dict(skin='#7a4a30', top='#f6f4f8', bottom='#f6f4f8', shoes='#f6f4f8', hair='flat', haircol='#1a1210',
         collar='#f0b830', shades=True, moustache=True, sleeves=True, flares=True),
    dict(skin='#f1c9a5', top='#ec3f88', bottom='#ec3f88', shoes='#1c1724', hair='long', haircol='#e8c15a', dress=True),
    dict(skin='#a0673f', top='#38c4e0', bottom='#2a4a86', shoes='#f2f2f2', hair='afro', haircol='#1a1210'),
    dict(skin='#e0ac83', top='#62cc4e', bottom='#3a3a44', shoes='#1c1724', hair='punk', haircol='#ff4fa3', sleeves=True),
    dict(skin='#f6d2b0', top='#9a62d8', bottom='#9a62d8', shoes='#3a2a2a', hair='bun', haircol='#cfcfd8', dress=True,
         glasses=True, sleeves=True),
]


# --- the disco man from the arcade logo, the conga line as silhouettes -------------------------------

def silhouette(svg):
    """The figures as dark silhouettes against the club lights, with pink and cyan rim light."""
    return '<g filter="url(#sil)">%s</g>' % svg


_MAN = None


def man_uri():
    """The disco man with the glitter lettering from the arcade logo, the black background made transparent."""
    global _MAN
    if _MAN is None:
        c = np.asarray(Image.open(ARCADE_LOGO).convert('RGB')).astype(float) / 255
        mx, mn = c.max(2), c.min(2)
        sat = (mx - mn) / np.maximum(mx, 1e-3)
        h = mx.shape[0]

        def img(a):
            return Image.fromarray((a * 255).astype('uint8'))
        m = img(mx > .09).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
        m = np.asarray(m.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))) > 127
        seed = np.zeros_like(m)
        seed[300:700, 300:550] = True
        seed &= m & (mx > .8) & (sat < .2)  # the white suit
        seed |= m & (sat > .35) & (mx > .55) & (np.arange(h)[:, None] > 740)  # the lettering
        k = grow(seed, m)
        # the black sunglasses are holes in the shape: fill the holes around the face
        out = np.zeros_like(k)
        out[0, :] = out[-1, :] = out[:, 0] = out[:, -1] = True
        out = grow(out & ~k, ~k)
        holes = ~out & ~k
        holes[:180, :] = holes[340:, :] = False
        k |= holes
        a = np.asarray(img(k).filter(ImageFilter.GaussianBlur(1.4))).astype(float) / 255
        a = np.clip((a - .5) * 2.2 + .5, 0, 1)
        im = Image.fromarray((np.dstack([c, a]) * 255).astype('uint8'), 'RGBA')
        im = im.crop(im.getbbox())
        buf = io.BytesIO()
        im.save(buf, 'PNG')
        _MAN = ('data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode(), im.size)
    return _MAN


def grow(k, m):
    """k grown inside m until it stops (what of m is connected to k)."""
    while True:
        n = k.copy()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n |= np.roll(np.roll(k, dy, 0), dx, 1)
        n &= m
        if (n == k).all():
            return k
        k = n


def disco_man(x, y, h):
    """The disco man with lettering, top left at (x, y), h high."""
    uri, (iw, ih) = man_uri()
    return ('<image href="%s" x="%.1f" y="%.1f" width="%.1f" height="%.1f"/>%s%s'
            % (uri, x, y, h * iw / ih, h, sparkle(x + h * .07, y + h * .84, h * .03, '#fff6c8'),
               sparkle(x + h * .74, y + h * .86, h * .022, '#fff6c8')))


def conga(x0, y, gap, sc, seed=1):
    r = random.Random(seed)
    parts = []
    for i, d in enumerate(CAST):
        x = x0 - i * gap
        parts.append(dancer(x, y + r.uniform(-3, 3), sc, r.uniform(-3, 3), d, gap, i % 3, lead=(i == 0)))
    return silhouette(''.join(parts))


# --- box art (480 x 620) --------------------------------------------------------------------------

def mirror_ball(cx, cy, r, seed=7, rays=True):
    rnd = random.Random(seed)
    o = []
    if rays:
        for i in range(11):
            a = math.radians(rnd.uniform(20, 340))
            w = math.radians(rnd.uniform(1.5, 4))
            L = rnd.uniform(260, 520)
            p1 = (cx + L * math.cos(a - w), cy + L * math.sin(a - w))
            p2 = (cx + L * math.cos(a + w), cy + L * math.sin(a + w))
            col = rnd.choice(['#ffffff', '#ff7ad9', '#7af0ff', '#fff27a'])
            o.append('<polygon points="%.0f,%.0f %.0f,%.0f %.0f,%.0f" fill="%s" opacity="%.2f"/>'
                     % (cx, cy, p1[0], p1[1], p2[0], p2[1], col, rnd.uniform(.06, .16)))
    o.append('<circle cx="%d" cy="%d" r="%d" fill="url(#glow)"/>' % (cx, cy, r * 2.2))
    if rays:
        o.append('<line x1="%d" y1="-10" x2="%d" y2="%d" stroke="#c9c9d6" stroke-width="2"/>' % (cx, cx, cy - r))
    _ids[0] += 1  # the scene is drawn more than once: unique ids
    o.append('<clipPath id="ballclip%d"><circle cx="%d" cy="%d" r="%d"/></clipPath>' % (_ids[0], cx, cy, r))
    o.append('<g clip-path="url(#ballclip%d)"><rect x="%d" y="%d" width="%d" height="%d" fill="#6f78b8"/>'
             % (_ids[0], cx - r, cy - r, 2 * r, 2 * r))
    n = 14
    f = 2 * r / n
    for j in range(n):
        for i in range(n):
            col = rnd.choice(['#e9ecff', '#b7c0f0', '#8b96d6', '#5e68ad', '#ffffff', '#ffd0f2', '#c8fbff', '#9aa6e6'])
            o.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" stroke="#2c3170" stroke-width="1"/>'
                     % (cx - r + i * f, cy - r + j * f, f, f, col))
    o.append('<circle cx="%d" cy="%d" r="%d" fill="url(#ballshade)"/></g>' % (cx, cy, r))
    o.append('<circle cx="%d" cy="%d" r="%d" fill="none" stroke="%s" stroke-width="3"/>' % (cx, cy, r, INK))
    return ''.join(o)


def sparkle(x, y, s, col='#ffffff'):
    return ('<path d="M%.1f,%.1f L%.1f,%.1f L%.1f,%.1f L%.1f,%.1f L%.1f,%.1f L%.1f,%.1f L%.1f,%.1f L%.1f,%.1f Z" fill="%s"/>'
            % (x, y - s, x + s * .22, y - s * .22, x + s, y, x + s * .22, y + s * .22,
               x, y + s, x - s * .22, y + s * .22, x - s, y, x - s * .22, y - s * .22, col))


_LETTERS = None


def letters_uri():
    """The glitter lettering of the arcade logo with the black background made transparent."""
    global _LETTERS
    if _LETTERS is None:
        c = np.asarray(Image.open(ARCADE_LOGO).convert('RGB')).astype(float)[730:960, 60:800] / 255
        r, b = c[..., 0], c[..., 2]
        mx, mn = c.max(2), c.min(2)
        sat = (mx - mn) / np.maximum(mx, 1e-3)
        suit = (b >= r - .03) & (((sat < .25) & (mx > .42)) | ((sat < .45) & (mx > .22)))  # white/lavender suit, shoes
        glow = (r > b + .03) & (mx < .5)  # the warm glow of the photo sparkles
        m = (mx > .11) & ~suit & ~glow

        def img(a):
            return Image.fromarray((a * 255).astype('uint8'))
        # close the glitter specks, open away thin lines (the suit's seams)
        mi = img(m).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
        m = np.asarray(mi.filter(ImageFilter.MinFilter(7)).filter(ImageFilter.MaxFilter(7))) > 127
        # keep what is connected to the glitter
        k = (sat > .35) & (mx > .55) & m
        while True:
            n = k.copy()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n |= np.roll(np.roll(k, dy, 0), dx, 1)
            n &= m
            if (n == k).all():
                break
            k = n
        # fill the holes, except the black counters of the letters
        out = np.zeros_like(k)
        out[0, :] = out[-1, :] = out[:, 0] = out[:, -1] = True
        out &= ~k
        while True:
            n = out.copy()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n |= np.roll(np.roll(out, dy, 0), dx, 1)
            n &= ~k
            if (n == out).all():
                break
            out = n
        k |= ~out & (mx > .11)
        # smooth, antialiased edge
        a = np.asarray(img(k).filter(ImageFilter.GaussianBlur(1.6))).astype(float) / 255
        a = np.clip((a - .5) * 2.2 + .5, 0, 1)
        im = Image.fromarray((np.dstack([c, a]) * 255).astype('uint8'), 'RGBA')
        im = im.crop(im.getbbox())
        buf = io.BytesIO()
        im.save(buf, 'PNG')
        _LETTERS = ('data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode(), im.size)
    return _LETTERS


def glitter_logo(cx, cy, w, rot=-4):
    uri, (iw, ih) = letters_uri()
    h = w * ih / iw
    return ('<g transform="rotate(%.1f %.1f %.1f)"><image href="%s" x="%.1f" y="%.1f" width="%.1f" height="%.1f"/></g>%s%s'
            % (rot, cx, cy, uri, cx - w / 2, cy - h / 2, w, h,
               sparkle(cx - w * .43, cy - h * .42, w * .045, '#fff6c8'), sparkle(cx + w * .45, cy - h * .12, w * .03, '#fff6c8')))


def floor(x0, x1, ytop, ybot, vx, vy, seed=3):
    rnd = random.Random(seed)
    o = []
    rows, cols = 6, 14
    base = [x0 - 200 + (x1 - x0 + 400) * j / cols for j in range(cols + 1)]
    ys = [ytop + (ybot - ytop) * ((i / rows) ** 1.6) for i in range(rows + 1)]

    def xa(bx, y):
        return vx + (bx - vx) * (y - vy) / (ybot - vy)
    for i in range(rows):
        for j in range(cols):
            ya, yb = ys[i], ys[i + 1]
            lit = rnd.random() < .22
            col = rnd.choice(['#63d36a', '#ff5fa2', '#58c8e8', '#ffd34d', '#b46cff']) if lit else \
                rnd.choice(['#3a2a8f', '#4b35a8', '#2e2276', '#55309c'])
            o.append('<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f %.1f,%.1f" fill="%s" stroke="#1a1240" stroke-width="2"/>'
                     % (xa(base[j], ya), ya, xa(base[j + 1], ya), ya, xa(base[j + 1], yb), yb, xa(base[j], yb), yb, col))
    o.append('<rect x="%d" y="%d" width="%d" height="%d" fill="url(#floorfade)"/>' % (x0, ytop, x1 - x0, ybot - ytop))
    return ''.join(o)


def scene(h=620):
    """The box art, 480 wide and h high (620 for the ad; the packshot's box is taller)."""
    rnd = random.Random(11)
    dy = (h - 620) // 2
    o = ['<rect width="480" height="%d" fill="url(#sky)"/>' % h]
    for _ in range(70):
        o.append('<circle cx="%.0f" cy="%.0f" r="%.1f" fill="#fff" opacity="%.2f"/>'
                 % (rnd.uniform(0, 480), rnd.uniform(0, 380 + dy), rnd.uniform(.5, 1.8), rnd.uniform(.3, .9)))
    o.append('<g transform="translate(0,%d)">' % dy)
    o.append(mirror_ball(405, 92, 48))
    o.append(sparkle(380, 200, 14) + sparkle(222, 318, 9, '#ffd0f2') + sparkle(410, 330, 7, '#c8fbff'))
    # hill and the club
    o.append('<path d="M0,430 C90,400 170,372 270,386 C350,396 420,372 480,380 L480,%d L0,%d Z" fill="#1d1450"/>'
             % (h - dy, h - dy))
    o.append('<path d="M330,394 L330,330 L360,330 L360,312 L408,312 L408,330 L446,330 L446,392 Z" fill="#120c30"/>')
    for wx, wy in [(338, 344), (352, 344), (418, 344), (432, 344), (338, 364), (432, 364), (418, 364), (372, 324), (392, 324)]:
        o.append('<rect x="%d" y="%d" width="8" height="10" fill="#ffd34d"/>' % (wx, wy))
    o.append('<rect x="366" y="356" width="34" height="38" fill="#ff5fa2" opacity=".85"/>')
    o.append('<text x="388" y="306" font-family="%s" font-size="22" text-anchor="middle" fill="#ff7ad9" '
             'filter="url(#neon)">DISCO</text>' % LOGO)
    # twisted trees like in an old horror ad, but with fairy lights
    for tx, th in [(28, 70), (452, 58)]:
        o.append('<path d="M%d,%d l2,-%d M%d,%d l-14,-14 M%d,%d l12,-16 M%d,%d l-10,-10" stroke="#0f0a2a" stroke-width="4" '
                 'stroke-linecap="round" fill="none"/>' % (tx, 420, th, tx + 1, 420 - th * .5, tx + 1, 420 - th * .7, tx + 2, 420 - th * .9))
    o.append(floor(0, 480, 452, h - dy, 240, 330))
    o.append(disco_man(68, 14, 440))
    o.append(conga(370, 572, 60, .5))
    o.append('<text x="240" y="470" font-family="%s" font-size="17" letter-spacing="3" text-anchor="middle" fill="#7af0ff" '
             'stroke="%s" stroke-width="3" paint-order="stroke">THE DISCO CONGA LINE</text>' % (COND, INK))
    o.append('</g>')
    return ''.join(o)


def box_extras(h=620):
    o = ['<g transform="translate(0,%d)">' % (h - 620)]
    o.append('<text x="300" y="596" font-family="%s" font-size="20" letter-spacing="7" text-anchor="middle" fill="#ffd34d" '
             'stroke="%s" stroke-width="3" paint-order="stroke">DISCOWARE<tspan font-size="9" dy="-9">TM</tspan></text>'
             % (COND, INK))
    o.append('<text x="300" y="614" font-family="%s" font-size="12" letter-spacing="9" text-anchor="middle" fill="#ffd34d" '
             'stroke="%s" stroke-width="3" paint-order="stroke">SOFTWARE</text>' % (COND, INK))
    o.append('<g transform="translate(10,566)"><rect width="104" height="46" fill="#f2d33a" stroke="#222" stroke-width="1"/>'
             '<text font-family="%s" font-size="6.8" fill="#111" text-anchor="middle">'
             '<tspan x="52" y="11">DISK FOR THE</tspan>'
             '<tspan x="52" y="22" font-size="9" font-weight="bold">Commodore 64™/128™</tspan>'
             '<tspan x="52" y="32">WITH 1541/1571</tspan><tspan x="52" y="41">DISK DRIVES</tspan></text></g></g>' % COND)
    return ''.join(o)


# --- shared defs ----------------------------------------------------------------------------------

DEFS = '''
<filter id="sil" x="-5%" y="-5%" width="110%" height="110%">
  <feFlood flood-color="#120a28" result="f"/><feComposite in="f" in2="SourceAlpha" operator="in" result="s"/>
  <feOffset in="SourceAlpha" dx="-2.5" dy="2" result="o1"/><feComposite in="SourceAlpha" in2="o1" operator="out" result="a1"/>
  <feFlood flood-color="#ff7ad9"/><feComposite in2="a1" operator="in" result="r1"/>
  <feOffset in="SourceAlpha" dx="2.5" dy="2" result="o2"/><feComposite in="SourceAlpha" in2="o2" operator="out" result="a2"/>
  <feFlood flood-color="#7af0ff"/><feComposite in2="a2" operator="in" result="r2"/>
  <feMerge><feMergeNode in="s"/><feMergeNode in="r1"/><feMergeNode in="r2"/></feMerge>
</filter>
<filter id="shadow_disk" x="-5%" y="-5%" width="110%" height="110%">
  <feGaussianBlur in="SourceAlpha" stdDeviation="2.5"/><feOffset dx="1.5" dy="3"/>
  <feComponentTransfer><feFuncA type="linear" slope=".4"/></feComponentTransfer>
  <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>
<filter id="soft2" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="2"/></filter>
<filter id="soft3" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="3"/></filter>
<linearGradient id="vol" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#fff" stop-opacity=".45"/><stop offset=".3" stop-color="#fff" stop-opacity="0"/>
  <stop offset=".6" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#1a0a3a" stop-opacity=".35"/>
</linearGradient>
<linearGradient id="lens" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#3a3a4a"/><stop offset=".5" stop-color="#0c0c12"/><stop offset="1" stop-color="#2a2440"/>
</linearGradient>
<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#0a0d3a"/><stop offset=".42" stop-color="#2a2580"/>
  <stop offset=".62" stop-color="#3f62b8"/><stop offset=".72" stop-color="#6fc3d8"/><stop offset="1" stop-color="#1d1450"/>
</linearGradient>
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#fff27a"/><stop offset=".55" stop-color="#ffd400"/><stop offset="1" stop-color="#ff9f1a"/>
</linearGradient>
<radialGradient id="glow"><stop offset="0" stop-color="#c8fbff" stop-opacity=".55"/><stop offset="1" stop-color="#c8fbff" stop-opacity="0"/></radialGradient>
<radialGradient id="ballshade" cx=".38" cy=".34" r=".7">
  <stop offset="0" stop-color="#fff" stop-opacity=".55"/><stop offset=".35" stop-color="#fff" stop-opacity="0"/>
  <stop offset=".8" stop-color="#0a0d3a" stop-opacity=".35"/><stop offset="1" stop-color="#0a0d3a" stop-opacity=".75"/>
</radialGradient>
<linearGradient id="floorfade" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#1d1450" stop-opacity=".85"/><stop offset=".5" stop-color="#1d1450" stop-opacity="0"/>
</linearGradient>
<filter id="neon" x="-30%" y="-60%" width="160%" height="220%">
  <feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>
<filter id="shadow" x="-10%" y="-10%" width="130%" height="130%">
  <feGaussianBlur in="SourceAlpha" stdDeviation="9"/><feOffset dx="7" dy="11"/>
  <feComponentTransfer><feFuncA type="linear" slope=".38"/></feComponentTransfer>
  <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>
<filter id="aged" x="0" y="0" width="100%" height="100%">
  <feColorMatrix in="SourceGraphic" type="saturate" values=".82" result="faded"/>
  <feTurbulence type="fractalNoise" baseFrequency=".85" numOctaves="2" seed="5" result="g"/>
  <feColorMatrix in="g" type="saturate" values="0" result="gg"/>
  <feComponentTransfer in="gg" result="g2">
    <feFuncR type="linear" slope=".4" intercept=".7"/><feFuncG type="linear" slope=".4" intercept=".7"/>
    <feFuncB type="linear" slope=".4" intercept=".66"/>
  </feComponentTransfer>
  <feBlend in="faded" in2="g2" mode="multiply" result="b"/>
  <feComposite in="b" in2="SourceGraphic" operator="in"/>
</filter>
<filter id="wear" x="-2%" y="-2%" width="104%" height="104%">
  <feTurbulence type="fractalNoise" baseFrequency=".025 .04" numOctaves="4" seed="9" result="n"/>
  <feColorMatrix in="n" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  5 0 0 0 -2.55" result="m"/>
  <feComposite in="SourceGraphic" in2="m" operator="in"/>
</filter>
<filter id="scuff" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency=".02 .5" numOctaves="2" seed="21" result="n"/>
  <feColorMatrix in="n" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  9 0 0 0 -6.1"/>
</filter>
<filter id="bw" x="0" y="0" width="100%" height="100%">
  <feColorMatrix type="saturate" values="0"/>
  <feComponentTransfer><feFuncR type="gamma" amplitude="1.15" exponent=".7" offset="0"/><feFuncG type="gamma" amplitude="1.15" exponent=".7" offset="0"/>
  <feFuncB type="gamma" amplitude="1.15" exponent=".7" offset="0"/></feComponentTransfer>
</filter>
<filter id="paper" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency=".7" numOctaves="3" seed="2" result="g"/>
  <feColorMatrix in="g" type="matrix" values="0 0 0 0 .52  0 0 0 0 .46  0 0 0 0 .34  -.9 0 0 0 .52"/>
  <feComposite in2="SourceGraphic" operator="in"/>
</filter>
<radialGradient id="backdrop" cx=".5" cy=".42" r=".75">
  <stop offset="0" stop-color="#f6f5f1"/><stop offset=".7" stop-color="#e7e5df"/><stop offset="1" stop-color="#cfccc4"/>
</radialGradient>
<linearGradient id="gloss" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".42" stop-color="#fff" stop-opacity="0"/>
  <stop offset=".5" stop-color="#fff" stop-opacity=".35"/><stop offset=".58" stop-color="#fff" stop-opacity="0"/>
</linearGradient>
<linearGradient id="fold" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#000" stop-opacity="0"/><stop offset=".47" stop-color="#000" stop-opacity=".12"/>
  <stop offset=".5" stop-color="#fff" stop-opacity=".22"/><stop offset=".53" stop-color="#000" stop-opacity=".06"/>
  <stop offset="1" stop-color="#000" stop-opacity="0"/>
</linearGradient>
'''


def art_defs():
    return ('<clipPath id="artclip"><rect width="480" height="620"/></clipPath>'
            '<g id="scene" clip-path="url(#artclip)">%s</g>'
            '<g id="art" clip-path="url(#artclip)"><use href="#scene"/>%s</g>' % (scene(), box_extras()))


def worn_box(x, y, w, h, art_id, spine=True):
    s = w / 480.0
    o = ['<g filter="url(#shadow)"><g transform="translate(%.1f,%.1f)">' % (x, y)]
    if spine:  # the side of the box, seen a little from the right
        o.append('<g filter="url(#aged)"><path d="M%.1f,0 L%.1f,10 L%.1f,%.1f L%.1f,%.1f Z" fill="#2b3bb0"/>'
                 '<text transform="translate(%.1f,%.1f) rotate(90)" font-family="%s" font-size="%.1f" fill="#ffd34d" '
                 'letter-spacing="3">POLONAISE</text></g>'
                 % (w, w + 20 * s, w + 20 * s, h - 8, w, h, w + 5 * s, 40 * s, LOGO, 18 * s))
    o.append('<g filter="url(#aged)"><g transform="scale(%.4f)"><use href="#%s"/></g>' % (s, art_id))
    # scuffed edges and corners, a few scratches, a crease
    o.append('<rect x="2" y="2" width="%.1f" height="%.1f" fill="none" stroke="#e9e4d6" stroke-width="%.1f" filter="url(#wear)"/>'
             % (w - 4, h - 4, 7 * s))
    for cx, cy in [(0, 0), (w, 0), (0, h), (w, h)]:  # bumped corners
        o.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#e9e4d6" filter="url(#wear)"/>' % (cx, cy, 16 * s))
    o.append('<rect width="%.1f" height="%.1f" fill="#fff" opacity=".22" filter="url(#scuff)"/>' % (w, h))
    o.append('<path d="M%.1f,0 C%.1f,%.1f %.1f,%.1f %.1f,%.1f" stroke="#fff" stroke-opacity=".25" stroke-width="2" fill="none"/>'
             % (w * .62, w * .66, h * .2, w * .58, h * .35, w * .64, h * .42))
    o.append('<path d="M0,%.1f L%.1f,%.1f" stroke="#fff" stroke-opacity=".18" stroke-width="3"/>' % (h * .71, w * .2, h * .69))
    if spine:  # what is left of a price sticker
        o.append('<g transform="translate(%.1f,%.1f) rotate(-8) scale(%.3f)"><path d="M0,0 L70,0 L74,12 L62,18 L66,30 L48,34 '
                 'L30,30 L0,32 Z" fill="#f5f2e6" stroke="#d8d2bf"/><text x="8" y="22" font-family="%s" font-size="17" '
                 'fill="#c62828">$19.99</text></g>' % (w * .05, h * .36, s, COND))
    o.append('</g></g></g>')
    return ''.join(o)


def floppy(x, y, size, side_text):
    s = size / 400.0
    o = ['<g transform="translate(%.1f,%.1f) scale(%.4f)" filter="url(#shadow_disk)">' % (x, y, s)]
    o.append('<path d="M10,0 L390,0 Q400,0 400,10 L400,112 L394,112 L394,138 L400,138 L400,390 Q400,400 390,400 '
             'L10,400 Q0,400 0,390 L0,10 Q0,0 10,0 Z" fill="#141416"/>')
    o.append('<g filter="url(#aged)"><rect x="12" y="8" width="376" height="100" rx="3" fill="#2f45d6"/>'
             '<rect x="12" y="8" width="376" height="20" fill="#fff" opacity=".1"/>')
    o.append('<text x="160" y="27" font-family="%s" font-size="13" letter-spacing="3" text-anchor="middle" fill="#fff">'
             'DISCOWARE<tspan font-size="7" dy="-5">TM</tspan></text>' % COND)
    o.append(glitter_logo(160, 52, 128, rot=-3))
    o.append('<text font-family="%s" font-size="9.5" fill="#fff" text-anchor="middle">'
             '<tspan x="160" y="80">Commodore 64 &amp; 128 (in C64 mode)</tspan>'
             '<tspan x="160" y="91">To Load: LOAD"*",8,1   %s</tspan>'
             '<tspan x="160" y="102" font-size="7.5">™ and © 1988 Discoware. All rights reserved.   DW-PL1-04</tspan></text>'
             % (COND, esc(side_text)))
    o.append(mirror_ball(340, 58, 30, seed=8, rays=False))
    o.append('</g>')
    o.append('<circle cx="200" cy="230" r="58" fill="#3a3a40"/><circle cx="200" cy="230" r="44" fill="url(#backdrop)"/>')
    o.append('<circle cx="200" cy="230" r="58" fill="none" stroke="#000" stroke-opacity=".4" stroke-width="3"/>')
    o.append('<circle cx="268" cy="214" r="7" fill="#3a3a40"/>')
    o.append('<rect x="182" y="300" width="36" height="96" rx="18" fill="#2c2c32"/>')
    o.append('<rect x="190" y="310" width="20" height="78" rx="10" fill="#4a4550"/>')
    o.append('</g>')
    return ''.join(o)


def manual(x, y, w, h, art_id):
    s = w / 480.0
    ah = h - 46
    o = ['<g transform="translate(%.1f,%.1f) rotate(-1.4)" filter="url(#shadow)">' % (x, y)]
    o.append('<rect width="%.1f" height="%.1f" fill="#f3f1ea"/>' % (w, h))
    o.append('<clipPath id="manclip"><rect width="%.1f" height="%.1f"/></clipPath>' % (w, ah))
    o.append('<g clip-path="url(#manclip)" filter="url(#bw)"><g transform="scale(%.4f)"><use href="#%s"/></g></g>' % (s, art_id))
    o.append('<rect y="%.1f" width="%.1f" height="%.1f" fill="#f3f1ea"/>' % (ah, w, h - ah))
    o.append('<text x="%.1f" y="%.1f" font-family="%s" font-size="15" letter-spacing="8" text-anchor="middle" fill="#222">'
             'D I S C O W A R E</text>' % (w / 2, ah + 30, COND))
    o.append('<rect width="%.1f" height="%.1f" fill="url(#fold)"/>' % (w, h))
    o.append('<rect width="%.1f" height="%.1f" fill="#fff" filter="url(#paper)" opacity=".7"/>' % (w, h))
    o.append('<rect x="2" y="2" width="%.1f" height="%.1f" fill="none" stroke="#fbfaf5" stroke-width="5" filter="url(#wear)"/>'
             % (w - 4, h - 4))
    o.append('</g>')
    return ''.join(o)


def sleeve(x, y, w, h, inner):
    o = ['<g transform="translate(%.1f,%.1f)">' % (x, y)]
    o.append('<rect width="%.1f" height="%.1f" rx="22" fill="#fff" fill-opacity=".45" stroke="#bdbab2" stroke-width="2" '
             'filter="url(#shadow)"/>' % (w, h))
    o.append('<rect x="10" y="10" width="%.1f" height="%.1f" rx="16" fill="none" stroke="#d8d5ce" stroke-width="2"/>' % (w - 20, h - 20))
    o.append('<path d="M%.1f,26 L%.1f,190 L%.1f,190 Z" fill="none" stroke="#cfccc4" stroke-width="3" stroke-linejoin="round"/>'
             % (w / 2, w * .2, w * .8))
    o.append('</g>')
    o.append(inner)
    o.append('<g transform="translate(%.1f,%.1f)"><rect x="%.1f" y="10" width="6" height="%.1f" rx="3" fill="#fff" '
             'opacity=".35"/></g>' % (x, y, w - 16, h - 20))
    return ''.join(o)


def packshot():
    W, H = 1600, 900
    o = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 70 %d %d"><defs>%s'
         '%s</defs>' % (W, H - 140, W, H - 140, DEFS, art_defs())]
    o.append('<rect width="%d" height="%d" fill="url(#backdrop)"/>' % (W, H))
    o.append(worn_box(70, 120, 480, 620, 'art', spine=False))  # the same box as in the ad
    o.append(manual(650, 175, 380, 540, 'scene'))
    o.append(sleeve(1090, 110, 450, 640, floppy(1115, 300, 400, 'This is Side 1.')))
    o.append('</svg>')
    return ''.join(o)


# --- magazine ad ----------------------------------------------------------------------------------

def png_uri(path, scale):
    out = tempfile.mktemp(suffix='.png')
    subprocess.run(['magick', path, '-filter', 'point', '-resize', '%d%%' % (scale * 100), out], check=True)
    data = base64.b64encode(open(out, 'rb').read()).decode()
    os.unlink(out)
    return 'data:image/png;base64,' + data


def tv(x, y, w, uri, caption, rot):
    h = w * 272 / 384
    o = ['<g transform="translate(%.1f,%.1f) rotate(%.1f)">' % (x, y, rot)]
    o.append('<rect x="-16" y="-16" width="%.1f" height="%.1f" rx="22" fill="#2a2420"/>' % (w + 32, h + 32))
    o.append('<rect x="-16" y="-16" width="%.1f" height="%.1f" rx="22" fill="none" stroke="#000" stroke-width="3"/>' % (w + 32, h + 32))
    o.append('<image href="%s" width="%.1f" height="%.1f" preserveAspectRatio="none" style="image-rendering:pixelated"/>'
             % (uri, w, h))
    o.append('<rect width="%.1f" height="%.1f" rx="8" fill="url(#gloss)" opacity=".6"/>' % (w, h))
    o.append('<text x="%.1f" y="%.1f" font-family="%s" font-size="19" text-anchor="middle" fill="#1a1a1a" font-style="italic">%s</text>'
             % (w / 2, h + 46, COND, esc(caption)))
    o.append('</g>')
    return ''.join(o)


def ad(shots):
    W, H = 1000, 1400
    uris = [png_uri(p, 2) for p in shots]
    o = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><defs>%s'
         '%s'
         '<linearGradient id="band" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0a0d3a"/>'
         '<stop offset="1" stop-color="#3a2a8f"/></linearGradient></defs>' % (W, H, W, H, DEFS, art_defs())]
    o.append('<rect width="%d" height="%d" fill="#f1ead8"/>' % (W, H))
    # top band: night sky, mirror ball, the conga line
    o.append('<clipPath id="bandclip"><rect width="%d" height="520"/></clipPath><g clip-path="url(#bandclip)">' % W)
    o.append('<rect width="%d" height="520" fill="url(#band)"/>' % W)
    rnd = random.Random(5)
    for _ in range(110):
        o.append('<circle cx="%.0f" cy="%.0f" r="%.1f" fill="#fff" opacity="%.2f"/>'
                 % (rnd.uniform(0, W), rnd.uniform(0, 380), rnd.uniform(.6, 2), rnd.uniform(.3, .9)))
    o.append(mirror_ball(800, 150, 86, seed=12))
    o.append(floor(0, W, 380, 520, 500, 260, seed=9))
    o.append(conga(930, 505, 74, .85, seed=3))
    o.append('</g>')
    o.append(disco_man(30, 14, 500))
    o.append('<text x="700" y="330" font-family="%s" font-size="26" letter-spacing="5" text-anchor="middle" fill="#7af0ff" '
             'stroke="%s" stroke-width="4" paint-order="stroke">THE DISCO CONGA LINE</text>' % (COND, INK))
    # headline and copy
    o.append('<text x="%d" y="600" font-family="%s" font-size="54" text-anchor="middle" fill="#111">'
             'GRAB A SHOULDER. JOIN THE LINE!</text>' % (W / 2, LOGO))
    o.append('<text font-family="%s" font-size="21" fill="#222" text-anchor="middle">'
             '<tspan x="%d" y="642">The club is packed, the DJ is spinning and the mirror ball is turning.</tspan>'
             '<tspan x="%d" y="670">Lead the polonaise across the dance floor, touch the guests and they join the end'
             ' of the line.</tspan><tspan x="%d" y="698">But watch out for the furniture, the walls and your own tail!'
             '</tspan></text>' % (COND, W / 2, W / 2, W / 2))
    o.append(tv(70, 760, 250, uris[0], 'Pick your language and go', -2.5))
    o.append(tv(375, 760, 250, uris[1], 'Every guest joins the line', 1.5))
    o.append(tv(680, 760, 250, uris[2], 'Endless songs, faster beats', -1.5))
    # features and the box
    feats = ['Disco soundtrack on all three SID voices',
             'Endless songs and 63 different party guests',
             'Top 10 high scores saved to your disk',
             'German & English on one disk']
    o.append('<text font-family="%s" font-size="22" fill="#1a1a1a">' % COND)
    for i, f in enumerate(feats):
        o.append('<tspan x="110" y="%d">%s</tspan>' % (1078 + i * 36, esc(f)))
    o.append('</text>')
    for i in range(len(feats)):
        o.append(sparkle(88, 1070 + i * 36, 11, '#e5243b'))
    o.append('<g transform="rotate(4 820 1170)">%s</g>' % worn_box(690, 1000, 230, 297, 'art', spine=False))
    o.append('<g transform="translate(590,1215) rotate(-12)"><circle r="62" fill="#ffd400" stroke="#111" stroke-width="3"/>'
             '<text font-family="%s" text-anchor="middle" fill="#111"><tspan x="0" y="-12" font-size="17">ONLY</tspan>'
             '<tspan x="0" y="20" font-size="36">$19.99</tspan><tspan x="0" y="40" font-size="12">on disk</tspan></text></g>' % LOGO)
    o.append('<rect x="0" y="1320" width="%d" height="80" fill="#111"/>' % W)
    o.append('<text x="60" y="1368" font-family="%s" font-size="17" fill="#f1ead8">Commodore 64/128 disk for 1541/1571 drives. '
             'Joystick required. Dancing shoes recommended.</text>' % COND)
    o.append('<text x="940" y="1368" font-family="%s" font-size="22" letter-spacing="6" text-anchor="end" fill="#ffd34d">'
             'DISCOWARE</text>' % COND)
    # old magazine paper: grain, yellowing at the edges, a fold
    o.append('<rect width="%d" height="%d" fill="#fff" filter="url(#paper)" opacity=".9"/>' % (W, H))
    o.append('<rect width="%d" height="%d" fill="url(#yellow)"/>' % (W, H))
    o.append('<radialGradient id="yellow" cx=".5" cy=".5" r=".75"><stop offset=".6" stop-color="#c8a050" stop-opacity="0"/>'
             '<stop offset="1" stop-color="#a87a2a" stop-opacity=".35"/></radialGradient>')
    o.append('<rect x="%d" width="10" height="%d" fill="#000" opacity=".08"/>' % (W / 2 - 5, H))
    o.append('</svg>')
    return ''.join(o)


def render(svg, out, width):
    tmp = tempfile.mkdtemp()
    conf = os.path.join(tmp, 'fonts.conf')
    open(conf, 'w').write('<?xml version="1.0"?><fontconfig><include ignore_missing="yes">/etc/fonts/fonts.conf</include>'
                          '<dir>%s</dir><cachedir>%s</cachedir></fontconfig>' % (os.path.abspath(FONTS), tmp))
    src = os.path.join(tmp, 'in.svg')
    png = os.path.join(tmp, 'out.png')
    open(src, 'w').write(svg)
    if os.environ.get('KEEP_SVG'):
        open(out + '.svg', 'w').write(svg)
    env = dict(os.environ, FONTCONFIG_FILE=conf)
    subprocess.run(['inkscape', src, '-o', png, '-w', str(width)], check=True, env=env,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['magick', png, '-quality', '88', out], check=True)
    subprocess.run(['rm', '-rf', tmp])


if __name__ == '__main__':
    os.makedirs(DOCS, exist_ok=True)
    what = sys.argv[1:] or ['packshot', 'ad']
    if 'packshot' in what:
        render(packshot(), os.path.join(DOCS, 'packshot.webp'), 1600)
    if 'ad' in what:
        shots = [os.path.join(DOCS, n) for n in ('shot-title.png', 'shot-game1.png', 'shot-game2.png')]
        render(ad(shots), os.path.join(DOCS, 'ad.webp'), 1000)
