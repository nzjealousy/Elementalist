"""Preview the tile sets as little rooms: python tools/art/preview_tiles.py"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import gen_tiles as t
from pixel import Canvas, hexc
SCALE = 3
rooms = []
for theme in ('camp', 'vault', 'crypt'):
    cv = Canvas(16 * 10, 16 * 6)
    rng = __import__('pixel').Rng(5)
    for y in range(6):
        for x in range(10):
            wall = x in (0, 9) or y in (0, 5)
            tile = t.wall_tile(theme, rng.rint(0, 2)) if wall else t.floor_tile(theme, rng.rint(0, 3))
            if (x, y) in ((3, 2), (6, 3)):
                tile = t.pillar_tile(theme)
            cv.blit(tile, x * 16, y * 16)
    rooms.append(cv)
w = max(r.w for r in rooms) + 4
h = sum(r.h + 4 for r in rooms) + 4
sheet = Canvas(w, h, hexc('101010'))
y = 4
for r in rooms:
    sheet.blit(r, 4, y)
    y += r.h + 4
big = Canvas(sheet.w * SCALE, sheet.h * SCALE)
for yy in range(sheet.h):
    for xx in range(sheet.w):
        p = sheet.px[yy * sheet.w + xx]
        for dy in range(SCALE):
            for dx in range(SCALE):
                big.px[(yy * SCALE + dy) * big.w + xx * SCALE + dx] = p
big.save(os.path.join(os.path.dirname(__file__), 'preview_tiles.png'))
