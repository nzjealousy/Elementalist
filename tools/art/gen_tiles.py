"""Floor, wall, pillar and background tiles for the places (camp and the five dungeons: vault, crypt, hollow, ember, spire),
in the Moonlit Glyphwork style: dark obsidian tinted per place, calm floors so sprites read on top, and thin glowing rune
seams in the place's own element colour (the glow is kept low on floors: it must never compete with a bolt).
Run: python tools/art/gen_tiles.py -> elementalist/assets/sprites/tile_*.png and bg_*.png

Per theme: tile_floor_<theme>_0..3, tile_wall_<theme>_0..2, tile_pillar_<theme>, bg_<theme> (32x32, tiles
seamlessly under the whole screen as the void behind a room).
Floor variants: 0 plain slabs, 1 a cracked slab with a faint glow, 2 a rune seam, 3 a small glyph. Wall variant 2 has a glowing glyph.
"""
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(__file__))
import style
from pixel import Canvas, Rng, mix

style.use("moonlit")

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'sprites')
os.makedirs(OUT, exist_ok=True)
T = 16
STONE = style.ramp("stone")
INK = style.INK


def _seed(*parts):
    """A stable seed (Python's hash() of strings changes every run, which would change the art)."""
    return zlib.crc32('|'.join(str(p) for p in parts).encode()) & 0xffff or 1


# tint: the ramp step the obsidian leans toward; amount: how far; accent: the element ramp of the place's runes
THEMES = {
    'vault': {'tint': style.ramp("mineral")[1], 'amount': 0.3, 'accent': 'mineral'},
    'crypt': {'tint': style.ramp("moss")[2], 'amount': 0.3, 'accent': 'air'},
    'hollow': {'tint': style.ramp("earth")[1], 'amount': 0.32, 'accent': 'earth'},
    'ember': {'tint': style.ramp("fire")[1], 'amount': 0.4, 'accent': 'fire'},
    'spire': {'tint': style.ramp("brass")[2], 'amount': 0.3, 'accent': 'light'},
    'camp': {'tint': style.ramp("moss")[2], 'amount': 0.5, 'accent': 'light'},
}


def _tones(theme):
    t = THEMES[theme]
    k = t['amount']
    return {
        'base': mix(STONE[1], t['tint'], k),
        'hi': mix(STONE[2], t['tint'], k * 0.8),
        'lit': mix(STONE[3], t['tint'], k * 0.5),
        'lo': mix(STONE[0], t['tint'], k * 0.4),
        'accent': style.ramp(t['accent']),
    }


def _seam(cv, x, y, length, vertical, accent):
    """A glowing rune seam: a dim halo, a body and a lit centre (kept to the dim end of the ramp on floors)."""
    for i in range(length):
        px, py = (x, y + i) if vertical else (x + i, y)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if (dx, dy) in ((0, 0),):
                continue
            c = cv.get(px + dx, py + dy)
            cv.set(px + dx, py + dy, mix(c, accent[1], 0.45))
        cv.set(px, py, accent[2] if i % 3 != 1 else accent[3])


def _glyph(cv, x, y, accent, big=False):
    """A tiny diamond sigil: a lit heart with four arms."""
    cv.set(x, y, accent[3])
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        cv.set(x + dx, y + dy, accent[2])
        if big:
            cv.set(x + dx * 2, y + dy * 2, accent[1])
    for dx, dy in ((1, 1), (-1, -1), (1, -1), (-1, 1)):
        cv.set(x + dx, y + dy, mix(cv.get(x + dx, y + dy), accent[1], 0.6))


def camp_floor(variant):
    """A moonlit clearing: teal grass with pale blades; variant 2 has fireflies, variant 3 pebbles."""
    rng = Rng(_seed('camp', variant, 'f'))
    moss = style.ramp("moss")
    base = mix(moss[1], moss[2], 0.4)
    cv = Canvas(T, T, base)
    for _ in range(64):
        x, y = rng.rint(0, T - 1), rng.rint(0, T - 1)
        cv.set(x, y, moss[2] if rng.next() > 0.45 else moss[0])
    for _ in range(3 if variant % 2 else 2):   # blades
        x, y = rng.rint(1, T - 2), rng.rint(2, T - 2)
        cv.set(x, y, moss[3])
        cv.set(x, y - 1, moss[4])
    if variant == 2:
        light = style.ramp("light")
        for _ in range(2):
            x, y = rng.rint(2, T - 3), rng.rint(2, T - 3)
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                cv.set(x + dx, y + dy, mix(cv.get(x + dx, y + dy), light[2], 0.35))
            cv.set(x, y, light[3])
    if variant == 3:
        for _ in range(7):
            x, y = rng.rint(1, T - 3), rng.rint(1, T - 3)
            cv.set(x, y, STONE[3])
            cv.set(x + 1, y, STONE[2])
            cv.set(x, y + 1, STONE[1])
    return cv


def floor_tile(theme, variant):
    if theme == 'camp':
        return camp_floor(variant)
    c = _tones(theme)
    rng = Rng(_seed(theme, variant, 'f'))
    cv = Canvas(T, T, c['base'])
    for sx in range(0, T, 8):          # stone slabs, 8x8: a lit top-left bevel, a dark joint bottom-right
        for sy in range(0, T, 8):
            tone = mix(c['base'], c['hi'] if rng.next() > 0.5 else c['lo'], 0.25 + rng.next() * 0.2)
            for x in range(sx, sx + 8):
                for y in range(sy, sy + 8):
                    cv.set(x, y, tone)
            for i in range(8):
                cv.set(sx + i, sy, mix(tone, c['lit'], 0.4))
                cv.set(sx, sy + i, mix(tone, c['lit'], 0.4))
                cv.set(sx + i, sy + 7, c['lo'])
                cv.set(sx + 7, sy + i, c['lo'])
    for _ in range(12):                # grit
        cv.set(rng.rint(0, T - 1), rng.rint(0, T - 1), c['hi'] if rng.next() > 0.5 else c['lo'])
    acc = c['accent']
    if variant == 1:                   # a crack with a faint glow in it
        x, y = rng.rint(2, 11), rng.rint(2, 11)
        for i in range(rng.rint(4, 6)):
            cv.set(x + i, y + (i * 2) // 3, c['lo'])
            cv.set(x + i, y + (i * 2) // 3 + 1, mix(cv.get(x + i, y + (i * 2) // 3 + 1), acc[1], 0.5))
    elif variant == 2:                 # a rune seam along a slab joint
        if rng.next() > 0.5:
            _seam(cv, rng.rint(1, 6), 7, rng.rint(6, 9), False, acc)
        else:
            _seam(cv, 7, rng.rint(1, 6), rng.rint(6, 9), True, acc)
    elif variant == 3:                 # a small glyph set in a slab
        _glyph(cv, rng.rint(4, 11), rng.rint(4, 11), acc, big=theme in ('spire', 'ember'))
    return cv


def camp_wall(variant):
    """A palisade of dark logs, lit on the left, with a pale cap."""
    rng = Rng(_seed('camp', variant, 'w'))
    wood = style.ramp("wood")
    cv = Canvas(T, T, wood[0])
    for x in range(0, T, 4):
        tone = mix(wood[2], wood[3] if rng.next() > 0.5 else wood[1], 0.35)
        for xx in range(x, x + 3):
            for y in range(T):
                cv.set(xx, y, tone)
        for y in range(T):
            cv.set(x, y, wood[3])
            cv.set(x + 2, y, wood[1])
        cv.set(x, 0, wood[4])
        cv.set(x + 1, 0, wood[3])
        cv.set(x + 2, 0, wood[2])
        if rng.next() > 0.6:
            cv.set(x + 1, rng.rint(4, 12), wood[0])
    if variant == 2:                   # a hung rune charm
        light = style.ramp("light")
        _glyph(cv, 6, 8, light)
    return cv


def wall_tile(theme, variant):
    if theme == 'camp':
        return camp_wall(variant)
    c = _tones(theme)
    rng = Rng(_seed(theme, variant, 'w'))
    wall = mix(STONE[1], c['lo'], 0.35)
    wall_hi = mix(STONE[2], c['lo'], 0.15)
    cv = Canvas(T, T, c['lo'])
    for row in range(4):               # brick courses, each 4 px tall, alternate courses offset by half a brick
        y0 = row * 4
        off = 4 if row % 2 else 0
        for bx in range(-8, T, 8):
            x0 = bx + off
            tone = mix(wall, wall_hi if rng.next() > 0.5 else c['lo'], 0.2 + rng.next() * 0.2)
            for x in range(max(x0, 0), min(x0 + 7, T)):
                for y in range(y0, y0 + 3):
                    cv.set(x, y, tone)
                cv.set(x, y0, mix(tone, c['lit'], 0.35))
                cv.set(x, y0 + 2, mix(tone, c['lo'], 0.5))
    for x in range(T):                 # the wall's top face catches the moon
        cv.set(x, 0, c['lit'])
    for _ in range(6):
        cv.set(rng.rint(0, T - 1), rng.rint(1, T - 1), mix(wall, c['lo'], 0.6))
    if variant == 2:                   # a glowing glyph carved into a brick
        _glyph(cv, rng.rint(4, 11), rng.rint(5, 10), c['accent'])
    return cv


def pillar_tile(theme):
    """A round obsidian column on the theme's floor, a ring of rune light around its top."""
    c = _tones(theme)
    cv = floor_tile(theme, 0)
    for y in range(T):                 # a soft cast shadow under and beside the column
        for x in range(T):
            if ((x - 8.5) / 7.0) ** 2 + ((y - 9.5) / 6.0) ** 2 <= 1.0:
                cv.set(x, y, mix(cv.get(x, y), INK, 0.55))
    ramp = [c['lo'], mix(STONE[1], c['lo'], 0.3), mix(STONE[2], c['base'], 0.4), c['lit']]
    cx, cy, rx, ry = 8.0, 7.0, 6.0, 6.0
    for y in range(T):                 # the column: four bands from a top-left light
        for x in range(T):
            nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            r2 = nx * nx + ny * ny
            if r2 > 1.0:
                continue
            lam = nx * -0.45 + ny * -0.6 + (1.0 - r2) ** 0.5 * 0.66
            cv.set(x, y, ramp[3] if lam > 0.78 else (ramp[2] if lam > 0.32 else (ramp[1] if lam > -0.1 else ramp[0])))
    for k in range(10):                # the rune ring at the column's top
        import math
        a = k / 10 * math.tau
        cv.set(int(round(cx + math.cos(a) * 3.6)), int(round(cy - 0.5 + math.sin(a) * 2.6)), c['accent'][2 if k % 2 else 3])
    return cv


def bg_tile(theme):
    """The void behind a room: near-black tinted per theme, a few cold stars."""
    c = _tones(theme)
    rng = Rng(_seed(theme, 'bg'))
    base = mix(INK, c['base'], 0.22)
    cv = Canvas(32, 32, base)
    for _ in range(26):
        x, y = rng.rint(0, 31), rng.rint(0, 31)
        cv.set(x, y, mix(base, STONE[2], 0.4 + rng.next() * 0.3))
    for _ in range(3):
        x, y = rng.rint(0, 28), rng.rint(0, 28)
        cv.set(x, y, c['accent'][3] if theme != 'camp' else STONE[4])
        cv.set(x + 1, y, mix(base, c['accent'][2], 0.5))
        cv.set(x, y + 1, mix(base, c['accent'][2], 0.5))
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
