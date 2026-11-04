"""Floor, wall, pillar and background tiles for the three places (camp, vault, crypt).
Run: python tools/art/gen_tiles.py -> elementalist/assets/sprites/tile_*.png and bg_*.png

Per theme: tile_floor_<theme>_0..3, tile_wall_<theme>_0..2, tile_pillar_<theme>, bg_<theme> (32x32, tiles
seamlessly under the whole screen as the void behind a room).
"""
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(__file__))
from pixel import Canvas, Rng, hexc, mix, shade

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'sprites')
os.makedirs(OUT, exist_ok=True)
T = 16


def _seed(*parts):
    """A stable seed (Python's hash() of strings changes every run, which would change the art)."""
    return zlib.crc32('|'.join(str(p) for p in parts).encode()) & 0xffff or 1

THEMES = {
    'vault': {'floor': '4a4540', 'floor_hi': '5a544d', 'floor_lo': '332f2b', 'wall': '6b5a4a', 'wall_hi': '8a7762',
              'wall_lo': '3a2f26', 'accent': 'a05a2a', 'bg': '0e0b0c'},
    'crypt': {'floor': '3a4650', 'floor_hi': '4a5a66', 'floor_lo': '262e36', 'wall': '4a5a62', 'wall_hi': '6a8088',
              'wall_lo': '28343a', 'accent': '4a8a6a', 'bg': '070b10'},
    'camp': {'floor': '5a6a3a', 'floor_hi': '7a8a4a', 'floor_lo': '3a4a2a', 'wall': '7a5a3a', 'wall_hi': '9a7a4a',
             'wall_lo': '3f2c1a', 'accent': 'e8c84a', 'bg': '0b100a'},
}


def floor_tile(theme, variant):
    p = THEMES[theme]
    rng = Rng(_seed(theme, variant, 'f'))
    base, hi, lo = hexc(p['floor']), hexc(p['floor_hi']), hexc(p['floor_lo'])
    cv = Canvas(T, T, base)
    if theme == 'camp':  # grass and dirt
        for _ in range(60):
            x, y = rng.rint(0, T - 1), rng.rint(0, T - 1)
            cv.set(x, y, hi if rng.next() > 0.45 else lo)
        for _ in range(3 if variant % 2 else 1):  # blades
            x, y = rng.rint(1, T - 2), rng.rint(2, T - 2)
            cv.set(x, y, hexc('8aa84a')); cv.set(x, y - 1, hexc('a8c85a'))
        if variant == 2:
            for _ in range(2):
                x, y = rng.rint(2, T - 3), rng.rint(2, T - 3)
                cv.set(x, y, hexc(p['accent'])); cv.set(x + 1, y, hexc('ffffff'))
        if variant == 3:
            for _ in range(10):
                cv.set(rng.rint(0, T - 1), rng.rint(0, T - 1), hexc('7a6a4a'))
        return cv
    # stone slabs: 8x8 with a dark joint and a bevel
    for sx in range(0, T, 8):
        for sy in range(0, T, 8):
            tone = mix(base, hi if rng.next() > 0.5 else lo, 0.25 + rng.next() * 0.15)
            for x in range(sx, sx + 8):
                for y in range(sy, sy + 8):
                    cv.set(x, y, tone)
            for i in range(8):
                cv.set(sx + i, sy, shade(tone, 1.15)); cv.set(sx, sy + i, shade(tone, 1.15))
                cv.set(sx + i, sy + 7, lo); cv.set(sx + 7, sy + i, lo)
    for _ in range(14):  # grit
        cv.set(rng.rint(0, T - 1), rng.rint(0, T - 1), hi if rng.next() > 0.5 else lo)
    if variant in (1, 3):  # a crack
        x, y = rng.rint(2, 12), rng.rint(2, 12)
        for i in range(rng.rint(3, 6)):
            cv.set(x + i, y + (i * 2) // 3, lo)
    if variant == 2:
        col = hexc(p['accent'])
        for _ in range(4 if theme == 'crypt' else 2):  # moss or embers
            x, y = rng.rint(1, T - 2), rng.rint(1, T - 2)
            cv.set(x, y, col); cv.set(x + 1, y, shade(col, 0.8))
    return cv


def wall_tile(theme, variant):
    p = THEMES[theme]
    rng = Rng(_seed(theme, variant, 'w'))
    base, hi, lo = hexc(p['wall']), hexc(p['wall_hi']), hexc(p['wall_lo'])
    cv = Canvas(T, T, lo)
    if theme == 'camp':  # a log palisade
        for x in range(0, T, 4):
            tone = mix(base, hi if rng.next() > 0.5 else lo, 0.2)
            for xx in range(x, x + 3):
                for y in range(T):
                    cv.set(xx, y, tone)
            for y in range(T):
                cv.set(x, y, shade(tone, 1.2)); cv.set(x + 2, y, shade(tone, 0.75))
            cv.set(x, 0, hexc('d8c090')); cv.set(x + 1, 0, hexc('c8a870')); cv.set(x + 2, 0, hexc('a88850'))
            if rng.next() > 0.6:
                cv.set(x + 1, rng.rint(4, 12), lo)
        return cv
    for row in range(4):  # brick courses, each 4px tall, alternate courses offset by half a brick
        y0 = row * 4
        off = 4 if row % 2 else 0
        for bx in range(-8, T, 8):
            x0 = bx + off
            tone = mix(base, hi if rng.next() > 0.5 else lo, 0.2 + rng.next() * 0.2)
            for x in range(max(x0, 0), min(x0 + 7, T)):
                for y in range(y0, y0 + 3):
                    cv.set(x, y, tone)
                cv.set(x, y0, shade(tone, 1.2))
                cv.set(x, y0 + 2, shade(tone, 0.8))
    for x in range(T):  # a lit top edge: the wall's top face catches the light
        cv.set(x, 0, hi)
    for _ in range(6):
        cv.set(rng.rint(0, T - 1), rng.rint(1, T - 1), shade(base, 0.65))
    if variant == 2:
        col = hexc(p['accent'])
        for _ in range(3):
            x, y = rng.rint(1, T - 3), rng.rint(2, T - 2)
            cv.set(x, y, col); cv.set(x + 1, y + 1, shade(col, 0.8))
    return cv


def pillar_tile(theme):
    p = THEMES[theme]
    base, hi, lo = hexc(p['wall']), hexc(p['wall_hi']), hexc(p['wall_lo'])
    cv = floor_tile(theme, 0)
    from pixel import shaded_ellipse, ellipse, OUTLINE
    for y in range(T):  # a soft shadow: darken the floor under and beside the column
        for x in range(T):
            if ((x - 8.5) / 7.0) ** 2 + ((y - 9.5) / 6.0) ** 2 <= 1.0:
                cv.set(x, y, shade(cv.get(x, y), 0.6))
    shaded_ellipse(cv, 8, 7, 6, 6, mix(base, hi, 0.3))
    for x in range(4, 12):
        cv.set(x, 7, shade(base, 0.8))
    ellipse(cv, 8, 6, 2.4, 2.0, shade(hi, 1.1))
    return cv


def bg_tile(theme):
    p = THEMES[theme]
    rng = Rng(_seed(theme, 'bg'))
    base = hexc(p['bg'])
    cv = Canvas(32, 32, base)
    for _ in range(24):
        x, y = rng.rint(0, 31), rng.rint(0, 31)
        cv.set(x, y, shade(base, 1.9 + rng.next()))
    for _ in range(3):
        x, y = rng.rint(0, 28), rng.rint(0, 28)
        cv.set(x, y, shade(base, 2.6)); cv.set(x + 1, y, shade(base, 2.1)); cv.set(x, y + 1, shade(base, 2.1))
    return cv


for theme in THEMES:
    for v in range(4):
        floor_tile(theme, v).save(os.path.join(OUT, 'tile_floor_%s_%d.png' % (theme, v)))
    for v in range(3):
        wall_tile(theme, v).save(os.path.join(OUT, 'tile_wall_%s_%d.png' % (theme, v)))
    pillar_tile(theme).save(os.path.join(OUT, 'tile_pillar_%s.png' % theme))
    bg_tile(theme).save(os.path.join(OUT, 'bg_%s.png' % theme))
# the old single-tile ids stay (the vault look) so nothing that still asks for them breaks
floor_tile('vault', 0).save(os.path.join(OUT, 'tile_floor.png'))
wall_tile('vault', 0).save(os.path.join(OUT, 'tile_wall.png'))
print('tiles ->', os.path.abspath(OUT))
