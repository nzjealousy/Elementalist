"""Contact sheets for eyeballing generated art (x SCALE, nearest neighbour, on a dark floor).
python tools/art/preview.py monsters|heroes|props  ->  tools/art/preview_<name>.png"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import gen_sprites as g
from pixel import Canvas, hexc

SCALE = 4
BG = hexc('2a2430')


def sheet_of(rows, path, gap=3):
    """rows: list of lists of Canvas."""
    width = max(sum(c.w + gap for c in row) for row in rows) + gap
    height = sum(max(c.h for c in row) + gap for row in rows) + gap
    cv = Canvas(width, height, BG)
    y = gap
    for row in rows:
        x = gap
        for c in row:
            cv.blit(c, x, y)
            x += c.w + gap
        y += max(c.h for c in row) + gap
    big = Canvas(cv.w * SCALE, cv.h * SCALE)
    for yy in range(cv.h):
        for xx in range(cv.w):
            p = cv.px[yy * cv.w + xx]
            for dy in range(SCALE):
                for dx in range(SCALE):
                    big.px[(yy * SCALE + dy) * big.w + xx * SCALE + dx] = p
    big.save(path)
    print(path, big.w, big.h)


what = sys.argv[1] if len(sys.argv) > 1 else 'monsters'
out = os.path.join(os.path.dirname(__file__), 'preview_%s.png' % what)
if what == 'monsters':
    names = list(g.MONSTERS)
    rows = []
    for i in range(0, len(names), 4):
        row = []
        for n in names[i:i + 4]:
            row += [g.finish(g.MONSTERS[n](ph)) for ph in range(2)]
        rows.append(row)
    sheet_of(rows, out)
elif what == 'heroes':
    rows = []
    for cls, pal in g.CLASS_PALETTES.items():
        rows.append([g.hero(f, fr, pal) for f in ('down', 'up', 'side') for fr in (0, 1)])
    sheet_of(rows, out)
else:
    rows = [[g.chest(False), g.chest(True), g.forge(), g.board(), g.door('locked'), g.door('open'), g.door('sealed')]]
    sheet_of(rows, out)
