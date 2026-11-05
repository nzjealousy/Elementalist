"""Equipment icons -> elementalist/assets/sprites/item_<base>.png (16 x 16), one per gear base in scripts/items/items.gd.
Run: python tools/art/gen_items.py

Weapons (sword, staff, bow, rod, dagger, axe, tome) take the material colours of their family from data/hero_looks.json
("weapons": worn, iron, steel, oak, bone, hunter, battle, scribe); body armour, helms and boots use the same palettes the hero
wears them in, so an icon and the figure always match. Each is drawn on a 14 x 14 grid with five tones (deep, shadow, base,
light, highlight), light from the upper left, then given the selective outline (a deep violet shade of the colour it surrounds),
which makes the 16 x 16 the inventory slots show at 1x.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import style
from pixel import Canvas, hexc, mix, soft_outline

style.use("moonlit")
ROOT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist')
OUT = os.path.join(ROOT, 'assets', 'sprites')
DATA = json.load(open(os.path.join(ROOT, 'data', 'hero_looks.json')))
RAMP = DATA['ramp']
os.makedirs(OUT, exist_ok=True)


def tones(hexstr):
    """[deep, shadow, base, light, highlight] of a colour, shaded the way HeroComposer shades a part."""
    base = hexc(hexstr)
    sc = RAMP['shadow_color'] + [255]
    shadow = mix(tuple(int(c * RAMP['dark_mul']) for c in base[:3]) + (255,), tuple(sc), RAMP['shadow_mix'])
    deep = tuple(int(c * 0.62) for c in shadow[:3]) + (255,)
    light = tuple(min(255, int(c * RAMP['light_mul'])) for c in base[:3]) + (255,)
    hi = mix(base, tuple(RAMP['highlight_color']) + (255,), RAMP['highlight_mix'])
    return [deep, shadow, base, light, hi]


def stick(cv, p0, p1, width, t, taper=False):
    """A shaded rod from p0 to p1: light on the upper-left side, dark on the lower-right."""
    (x0, y0), (x1, y1) = p0, p1
    steps = int(max(abs(x1 - x0), abs(y1 - y0))) * 2 + 1
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy) or 1.0
    nx, ny = dy / length, -dx / length            # a normal pointing to the upper right
    if nx + ny > 0:
        nx, ny = -nx, -ny                          # make the normal point to the lower right (the shaded side)
    for i in range(steps + 1):
        s = i / steps
        half = (width / 2.0) * ((1.0 - 0.75 * s) if taper else 1.0)
        for k in range(-int(width) - 1, int(width) + 2):
            off = k * 0.5
            if abs(off) > half + 0.25:
                continue
            px = int(round(x0 + dx * s + nx * off))
            py = int(round(y0 + dy * s + ny * off))
            rel = off / max(half, 0.5)
            idx = 4 if rel < -0.7 else (3 if rel < -0.2 else (2 if rel < 0.35 else 1))
            if taper and s > 0.94:
                idx = 4
            cv.set(px, py, t[idx])


def ball(cv, cx, cy, r, t, glow=False):
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            nx, ny = (x + 0.5 - cx) / r, (y + 0.5 - cy) / r
            r2 = nx * nx + ny * ny
            if r2 > 1.0:
                continue
            lam = nx * -0.45 + ny * -0.6 + math.sqrt(1 - r2) * 0.66
            cv.set(x, y, t[4] if lam > 0.85 else (t[3] if lam > 0.45 else (t[2] if lam > 0.0 else t[1])))


def poly(cv, pts, t, mode='cyl'):
    """A shaded polygon: light on its left third, dark on its right, a lit top edge."""
    cells = set()
    ys = [p[1] for p in pts]
    n = len(pts)
    for y in range(int(math.floor(min(ys))), int(math.ceil(max(ys)))):
        xs = []
        for i in range(n):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
            if (y0 <= y + 0.5 < y1) or (y1 <= y + 0.5 < y0):
                xs.append(x0 + (y + 0.5 - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(int(round(xs[i])), int(round(xs[i + 1]))):
                cells.add((x, y))
    rows = {}
    for (x, y) in cells:
        lo, hi = rows.get(y, (x, x))
        rows[y] = (min(lo, x), max(hi, x))
    for (x, y) in cells:
        lo, hi = rows[y]
        frac = (x - lo) / max(hi - lo, 1)
        idx = 3 if frac < 0.3 else (1 if frac > 0.72 else 2)
        if mode == 'flat':
            idx = 2
        elif (x, y - 1) not in cells:
            idx = 4 if frac < 0.5 else 3
        elif (x, y + 1) not in cells:
            idx = 1
        cv.set(x, y, t[idx])


def frame(cv):
    """The 14 x 14 drawing becomes the 16 x 16 icon: selective outline."""
    return cv.outline(None)


# ------------------------------------------------------------------------------------------- weapons
def sword(m, w, gem):
    cv = Canvas(14, 14)
    stick(cv, (4, 9), (12, 1), 3, m, taper=True)
    stick(cv, (3, 7), (8, 12), 2, tones('c9a35a'))           # the guard
    stick(cv, (4, 10), (2, 12), 2, w)
    ball(cv, 1.5, 12.5, 1.3, tones('c9a35a'))
    return frame(cv)


def dagger(m, w, gem):
    cv = Canvas(14, 14)
    stick(cv, (6, 8), (11, 3), 2, m, taper=True)
    stick(cv, (4, 7), (8, 11), 2, tones('c9a35a'))
    stick(cv, (5, 10), (3, 12), 2, w)
    cv.set(2, 12, tones('c9a35a')[2])
    return frame(cv)


def axe(m, w, gem):
    cv = Canvas(14, 14)
    stick(cv, (3, 12), (10, 4), 2, w)
    poly(cv, [(8, 3), (10, 0), (12, 0), (13, 3), (13, 7), (11, 9), (9, 7)], m)          # a bearded blade
    for y in range(1, 8):                                    # the bright cutting edge
        cv.set(13 if 2 < y < 7 else 12, y, m[4])
    cv.set(9, 4, m[1])
    cv.set(10, 5, m[1])
    stick(cv, (2, 13), (4, 11), 2, tones('c9a35a'))
    return frame(cv)


def staff(m, w, gem):
    cv = Canvas(14, 14)
    stick(cv, (2, 13), (10, 5), 2, w)
    for p in ((4, 11), (7, 8)):
        cv.set(*p, tones('c9a35a')[3])
    stick(cv, (9, 4), (12, 1), 1, tones('c9a35a'))
    ball(cv, 11.5, 2.5, 2.4, gem)
    cv.set(10, 1, gem[4])
    return frame(cv)


def rod(m, w, gem):
    cv = Canvas(14, 14)
    stick(cv, (3, 12), (9, 6), 2, w)
    stick(cv, (8, 7), (10, 5), 2, tones('c9a35a'))
    ball(cv, 10.5, 3.5, 2.8, gem)
    cv.set(9, 2, gem[4])
    cv.set(10, 2, gem[4])
    return frame(cv)


def bow(m, w, gem):
    cv = Canvas(14, 14)
    for t_ in range(-6, 7):
        x = 11 - int(round(6 * (1 - (t_ / 6.0) ** 2)))
        cv.set(x, 7 + t_, w[3] if t_ < 0 else w[2])
        cv.set(x + 1, 7 + t_, w[1])
    for y in range(1, 14):                                    # the string
        cv.set(11, y, m[4] if y % 2 else m[3])
    for y in (6, 7, 8):                                       # a grip wrap
        cv.set(6, y, tones('c9a35a')[3])
    cv.set(10, 1, w[4])
    cv.set(10, 13, w[1])
    return frame(cv)


def tome(m, w, gem):
    cv = Canvas(14, 14)
    poly(cv, [(2, 1), (11, 1), (11, 13), (2, 13)], w)
    poly(cv, [(11, 2), (13, 2), (13, 12), (11, 13)], tones('e8e0c0'), 'flat')   # the page edge
    stick(cv, (2, 2), (2, 12), 1, tones('c9a35a'))                                # a gilded spine
    poly(cv, [(4, 3), (9, 3), (9, 4), (4, 4)], tones('c9a35a'), 'flat')
    ball(cv, 6.5, 7.5, 2.0, gem)
    cv.set(5, 6, gem[4])
    poly(cv, [(4, 11), (9, 11), (9, 12), (4, 12)], tones('c9a35a'), 'flat')
    return frame(cv)


# ---------------------------------------------------------------------------------------------- armour
def tunic(p):
    cv = Canvas(14, 14)
    o, tr = tones(p['outfit']), tones(p['trim'])
    poly(cv, [(1, 2), (4, 1), (5, 2), (8, 2), (9, 1), (12, 2), (13, 6), (11, 7), (10, 6), (10, 12), (3, 12), (3, 6), (2, 7), (0, 6)], o)
    poly(cv, [(5, 1), (8, 1), (7, 4), (6, 4)], tones('2a1830'), 'flat')            # the neck
    stick(cv, (3, 10), (10, 10), 1, tr)                                              # a belt
    cv.set(6, 10, tr[4])
    cv.set(6, 11, tr[3])
    for y in range(4, 9):
        cv.set(7, y, o[1])
    return frame(cv)


def mail(p):
    cv = Canvas(14, 14)
    o, tr = tones(p['outfit']), tones(p['trim'])
    poly(cv, [(1, 2), (4, 1), (5, 2), (8, 2), (9, 1), (12, 2), (13, 6), (11, 7), (10, 6), (10, 13), (3, 13), (3, 6), (2, 7), (0, 6)], o)
    for y in range(3, 13):                                                           # chain rings
        for x in range(2 + (y % 2), 12, 2):
            if cv.get(x, y)[3]:
                cv.set(x, y, o[1] if (x + y) % 4 else o[3])
    poly(cv, [(5, 1), (8, 1), (7, 3), (6, 3)], tones('2a1830'), 'flat')
    poly(cv, [(0, 1), (4, 0), (5, 3), (1, 4)], tr)                                  # pauldrons
    poly(cv, [(9, 0), (13, 1), (13, 4), (8, 3)], tr)
    stick(cv, (3, 9), (10, 9), 1, tr)
    stick(cv, (3, 12), (10, 12), 1, tr)
    return frame(cv)


def robe(p):
    cv = Canvas(14, 14)
    o, tr = tones(p['outfit']), tones(p['trim'])
    poly(cv, [(2, 1), (5, 0), (8, 0), (11, 1), (13, 8), (11, 9), (11, 13), (2, 13), (2, 9), (0, 8)], o)
    poly(cv, [(5, 0), (8, 0), (7, 3), (6, 3)], tones('2a1830'), 'flat')
    poly(cv, [(6, 3), (8, 3), (9, 13), (5, 13)], o, 'dark')                          # the open front
    stick(cv, (2, 12), (11, 12), 1, tr)                                               # the trimmed hem
    stick(cv, (0, 8), (2, 9), 1, tr)
    stick(cv, (11, 9), (13, 8), 1, tr)
    stick(cv, (3, 7), (10, 7), 1, tr)
    for x in (4, 7, 10):
        cv.set(x, 12, tr[4])
    return frame(cv)


# ------------------------------------------------------------------------------------------ helms, boots
def cap(p):
    cv = Canvas(14, 14)
    h, tr = tones(p['head']), tones(p['headtrim'])
    poly(cv, [(1, 8), (2, 4), (5, 2), (9, 2), (12, 4), (13, 8)], h)
    poly(cv, [(0, 8), (13, 8), (13, 10), (0, 10)], tr)
    for x in range(3, 11, 2):
        cv.set(x, 5, h[1])
    cv.set(4, 3, h[4])
    cv.set(5, 3, h[4])
    return frame(cv)


def helm(p):
    cv = Canvas(14, 14)
    h, tr = tones(p['head']), tones(p['headtrim'])
    poly(cv, [(2, 12), (1, 6), (3, 2), (6, 0), (9, 0), (12, 2), (13, 6), (12, 12), (9, 12), (9, 8), (5, 8), (5, 12)], h)
    poly(cv, [(5, 5), (9, 5), (9, 7), (5, 7)], tones('1a1024'), 'flat')            # the visor slit
    stick(cv, (1, 4), (12, 4), 1, tr)
    stick(cv, (7, 0), (7, 12), 1, tr)
    cv.set(4, 2, h[4])
    cv.set(5, 1, h[4])
    return frame(cv)


def hood(p):
    cv = Canvas(14, 14)
    h, tr = tones(p['head']), tones(p['headtrim'])
    poly(cv, [(2, 13), (1, 8), (3, 3), (7, 0), (11, 3), (13, 8), (12, 13)], h)
    poly(cv, [(4, 6), (10, 6), (10, 11), (4, 11)], tones('140c1c'), 'flat')          # the shadowed opening
    stick(cv, (4, 5), (10, 5), 1, tr)
    stick(cv, (2, 12), (12, 12), 1, tr)
    cv.set(5, 2, h[4])
    cv.set(6, 1, h[4])
    return frame(cv)


def shoes(p):
    cv = Canvas(14, 14)
    b = tones(p['boots'])
    for ox in (0, 7):
        poly(cv, [(ox + 1, 5), (ox + 5, 5), (ox + 5, 9), (ox + 7, 10), (ox + 7, 12), (ox + 1, 12)], b)
        stick(cv, (ox + 1, 12), (ox + 6, 12), 1, tones('2a1830'))
        cv.set(ox + 2, 5, b[4])
    return frame(cv)


def tall_boots(p):
    cv = Canvas(14, 14)
    b = tones(p['boots'])
    tr = tones('d8d0ff')
    for ox in (0, 7):
        poly(cv, [(ox + 1, 1), (ox + 5, 1), (ox + 5, 8), (ox + 7, 9), (ox + 7, 12), (ox + 1, 12)], b)
        stick(cv, (ox + 1, 12), (ox + 6, 12), 1, tones('2a1830'))
        stick(cv, (ox + 1, 2), (ox + 4, 2), 1, tr)
        cv.set(ox + 2, 5, tr[3])
        cv.set(ox + 2, 1, b[4])
    return frame(cv)


# ---------------------------------------------------------------------------------------------- trinkets
def ring(base_hex, gem_hex):
    def draw():
        cv = Canvas(14, 14)
        b = tones(base_hex)
        for y in range(14):
            for x in range(14):
                dx, dy = (x + 0.5 - 7) / 5.2, (y + 0.5 - 8) / 4.6
                r2 = dx * dx + dy * dy
                inner = ((x + 0.5 - 7) / 3.0) ** 2 + ((y + 0.5 - 8) / 2.6) ** 2
                if r2 <= 1.0 and inner > 1.0:
                    lam = dx * -0.5 + dy * -0.7
                    cv.set(x, y, b[4] if lam > 0.55 else (b[3] if lam > 0.15 else (b[2] if lam > -0.35 else b[1])))
        if gem_hex:
            g = tones(gem_hex)
            ball(cv, 7, 3, 2.1, g)
            cv.set(6, 2, g[4])
        return frame(cv)
    return draw


def amulet(pendant_hex, charm):
    def draw():
        cv = Canvas(14, 14)
        cord = tones('785070')
        for t_ in range(-5, 6):
            cv.set(7 + t_, 1 + int(round((t_ / 5.0) ** 2 * 4)), cord[3] if t_ < 0 else cord[2])
        t = tones(pendant_hex)
        if charm == 'bone':
            poly(cv, [(5, 6), (9, 6), (10, 9), (9, 12), (5, 12), (4, 9)], t)
            cv.set(6, 8, t[1])
            cv.set(8, 8, t[1])
            stick(cv, (6, 10), (8, 10), 1, t[:3] + [t[1], t[1]])
        else:  # a four-leaf charm
            for cx, cy in ((5.5, 7.0), (8.5, 7.0), (5.5, 10.0), (8.5, 10.0)):
                ball(cv, cx, cy, 1.7, t)
            cv.set(7, 8, t[4])
            stick(cv, (7, 11), (7, 13), 1, tones('c9a35a'))
        return frame(cv)
    return draw


# ----------------------------------------------------------------------------------------------- build
def material(prefix):
    mats = DATA['weapons']
    return mats.get(prefix, mats['worn'])


WEAPON_DRAW = {'sword': sword, 'staff': staff, 'bow': bow, 'rod': rod, 'dagger': dagger, 'axe': axe, 'tome': tome}
BODY_DRAW = {'padded_tunic': tunic, 'chain_mail': mail, 'mage_robe': robe}
HEAD_DRAW = {'leather_cap': cap, 'iron_helm': helm, 'scholar_hood': hood}
FEET_DRAW = {'travel_boots': shoes, 'runner_boots': tall_boots}
GEM_OF_FAMILY = {'worn': '6ab0ff', 'iron': '6ab0ff', 'steel': '9cf0d8', 'oak': '88e880', 'bone': 'b868ff', 'hunter': '88e880', 'battle': 'ff8040', 'scribe': 'f8d060'}

# the items.gd BASES (id -> weapon type, material prefix), kept in step by tests/combo_selftest.gd
WEAPONS = {
    'worn_sword': 'sword', 'worn_staff': 'staff', 'worn_bow': 'bow', 'worn_rod': 'rod', 'worn_dagger': 'dagger', 'worn_axe': 'axe',
    'worn_tome': 'tome', 'iron_sword': 'sword', 'hunter_bow': 'bow', 'oak_staff': 'staff', 'bone_rod': 'rod', 'steel_dagger': 'dagger',
    'battle_axe': 'axe', 'scribe_tome': 'tome',
}


def main():
    count = 0
    for base, kind in WEAPONS.items():
        prefix = base.split('_')[0]
        mat = material(prefix)
        cv = WEAPON_DRAW[kind](tones(mat['metal']), tones(mat['wood']), tones(GEM_OF_FAMILY.get(prefix, '6ab0ff')))
        cv.save(os.path.join(OUT, 'item_%s.png' % base))
        count += 1
    for table, section in ((BODY_DRAW, 'armor'), (HEAD_DRAW, 'helms'), (FEET_DRAW, 'boots')):
        for base, fn in table.items():
            palette = dict(DATA['classes']['wanderer']['palette'])
            palette.update(DATA[section][base]['palette'])
            fn(palette).save(os.path.join(OUT, 'item_%s.png' % base))
            count += 1
    ring('b87040', None)().save(os.path.join(OUT, 'item_copper_ring.png'))
    ring('c8c8e0', 'ff80e0')().save(os.path.join(OUT, 'item_silver_ring.png'))
    amulet('e8e0c0', 'bone')().save(os.path.join(OUT, 'item_bone_amulet.png'))
    amulet('88e880', 'clover')().save(os.path.join(OUT, 'item_lucky_charm.png'))
    count += 4
    print('item icons ->', os.path.abspath(OUT), count, 'files')


if __name__ == '__main__':
    main()
