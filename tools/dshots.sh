#!/bin/sh
# dshots.sh <d64> <out.png> <100k cycles>...: like shots.sh, each run on a fresh copy of the image
f=$1; out=$2; shift 2
S=$(mktemp -d)
for c in "$@"; do
  cp "$f" $S/$c.d64
  timeout 300 denise -debugcart -no-driver -limitcycles ${c}00000 -exitscreenshot $S/$c.png $S/$c.d64 >/dev/null 2>&1 &
done
wait
tools/venv/bin/python - "$S" "$out" "$@" <<'PY'
import sys
from PIL import Image, ImageDraw
d, out, cs = sys.argv[1], sys.argv[2], sys.argv[3:]
ims = [Image.open('%s/%s.png' % (d, c)).convert('RGB') for c in cs]
cols = min(3, len(ims)); rows = (len(ims) + cols - 1) // cols
w, h = ims[0].size
o = Image.new('RGB', (w * cols, h * rows))
for i, im in enumerate(ims):
    ImageDraw.Draw(im).text((2, 2), cs[i], fill=(255, 255, 0))
    o.paste(im, ((i % cols) * w, (i // cols) * h))
o.save(out)
PY
cp $S/*.d64 /tmp/claude-1000/-home-dennis-Projekte-polonaise-c64/94b1f0bd-6da3-425f-b2e5-63869eab5e57/scratchpad/ 2>/dev/null
rm -rf $S
