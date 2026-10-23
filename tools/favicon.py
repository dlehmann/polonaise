#!/usr/bin/env python3
"""
favicon.py - the favicon of the Polonaise pages: a mirror ball. Draws the ball as
SVG (tiles of a sphere seen from the front, lit from the top left, a few tiles
catching the coloured lights of the dance floor) and renders favicon.ico (16, 32,
48 pixels) with rsvg-convert and ImageMagick.

Usage: tools/favicon.py <out dir>   (writes favicon.svg and favicon.ico)
"""
import math
import os
import subprocess
import sys
import tempfile

OUT = sys.argv[1] if len(sys.argv) > 1 else 'docs'
S = 64                      # the view box
CX, CY, R = 32, 33, 27
BANDS, SLICES = 8, 10       # tiles: latitude bands, longitude slices of the front half
LIGHT = (-0.55, 0.65, 0.52)     # towards the light (x right, y up, z to the viewer)
SPARKS = {(2, 3): '#3df0ff', (4, 6): '#ff3d9a', (5, 2): '#ffe03d', (3, 7): '#7dff5a', (6, 5): '#3df0ff'}


def point(lat, lon):
    return (CX + R * math.cos(lat) * math.sin(lon), CY - R * math.sin(lat))


def shade(lat, lon):
    n = (math.cos(lat) * math.sin(lon), math.sin(lat), math.cos(lat) * math.cos(lon))
    d = max(0.0, sum(a * b for a, b in zip(n, LIGHT)))
    v = 0.25 + 0.75 * d ** 1.4
    lo, hi = (52, 44, 98), (238, 234, 255)
    return '#%02x%02x%02x' % tuple(round(a + (b - a) * v) for a, b in zip(lo, hi))


tiles = []
for b in range(BANDS):
    la0 = -math.pi / 2 + math.pi * b / BANDS
    la1 = la0 + math.pi / BANDS
    for s in range(SLICES):
        lo0 = -math.pi / 2 + math.pi * s / SLICES
        lo1 = lo0 + math.pi / SLICES
        pts = [point(la0, lo0), point(la0, lo1), point(la1, lo1), point(la1, lo0)]
        col = SPARKS.get((b, s)) or shade((la0 + la1) / 2, (lo0 + lo1) / 2)
        tiles.append('<path d="M%s Z" fill="%s"/>' % (' L'.join('%.2f,%.2f' % p for p in pts), col))

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}">
  <defs><clipPath id="ball"><circle cx="{CX}" cy="{CY}" r="{R}"/></clipPath></defs>
  <g clip-path="url(#ball)" stroke="#1d1546" stroke-width="1.1" stroke-linejoin="round">
    {"".join(tiles)}
  </g>
  <circle cx="{CX}" cy="{CY}" r="{R}" fill="none" stroke="#140a2c" stroke-width="2.5"/>
  <ellipse cx="{CX - 9}" cy="{CY - 11}" rx="6" ry="4" fill="#fff" opacity=".85" transform="rotate(-30 {CX - 9} {CY - 11})"/>
  <path d="M53 4 L55 10 L61 12 L55 14 L53 20 L51 14 L45 12 L51 10 Z" fill="#fff" stroke="#140a2c" stroke-width="1"/>
</svg>
'''
os.makedirs(OUT, exist_ok=True)
svg_path = os.path.join(OUT, 'favicon.svg')
open(svg_path, 'w').write(svg)
with tempfile.TemporaryDirectory() as tmp:
    pngs = []
    for size in (16, 32, 48):
        p = os.path.join(tmp, '%d.png' % size)
        subprocess.run(['rsvg-convert', '-w', str(size), '-h', str(size), '-o', p, svg_path], check=True)
        pngs.append(p)
    subprocess.run(['magick', *pngs, os.path.join(OUT, 'favicon.ico')], check=True)
print('wrote', svg_path, os.path.join(OUT, 'favicon.ico'))
