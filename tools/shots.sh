#!/bin/sh
# shots.sh <prg> <out.png> <millions of cycles>...: screenshots of one run at several times (one run each)
f=$1; out=$2; shift 2
S=$(mktemp -d)
for c in "$@"; do
  timeout 120 denise -debugcart -no-driver -limitcycles ${c}00000 -exitscreenshot $S/$c.png "$f" >/dev/null 2>&1 &
done
wait
tools/venv/bin/python - "$S" "$out" "$@" <<'PY'
import sys
from PIL import Image, ImageDraw
d, out, cs = sys.argv[1], sys.argv[2], sys.argv[3:]
ims = [Image.open('%s/%s.png' % (d, c)).convert('RGB') for c in cs]
cols = min(3, len(ims))
rows = (len(ims) + cols - 1) // cols
w, h = ims[0].size
o = Image.new('RGB', (w * cols, h * rows))
for i, im in enumerate(ims):
    ImageDraw.Draw(im).text((2, 2), cs[i], fill=(255, 255, 0))
    o.paste(im, ((i % cols) * w, (i // cols) * h))
o.save(out)
PY
rm -rf $S
