"""Layered hero parts -> elementalist/assets/sprites/hero/<part>_<variant>_<facing>.png. Run: python tools/art/gen_heroes.py

A hero is drawn from interchangeable PARTS (body, boots, outfit, hair, head gear, back item, accent, weapon)
so the sprite can change with class, subclass and every equipped item. The parts are not coloured:
each pixel stores a REGION and a SHADE, and the game paints them with a palette when it composes the
hero (scripts/character/hero_composer.gd), so one set of shapes serves every colour scheme.

Pixel encoding:  R = region * 16,  G = shade * 60,  B = 0,  A = 255
Regions: 1 skin  2 hair  3 outfit  4 trim  5 pants  6 boots  7 headgear  8 headgear trim  9 cape/back
         10 accent  11 metal  12 wood  13 gem  14 eyes  15 white
Shades:  1 dark  2 mid  3 light  4 highlight (0 is the outline, which the composer adds around the whole hero)

Every part is a strip of FRAMES frames (W x H each) for the three facings: down, up and side (facing right).
Style: chibi proportions (big head), soft coloured outlines and warm light / cool shadow tones, the way
Stardew Valley and Witchbrook draw their villagers.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pixel import Canvas, sheet  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'sprites', 'hero')
os.makedirs(OUT, exist_ok=True)

W, H = 16, 26
FRAMES = 4
SKIN, HAIR, OUTFIT, TRIM, PANTS, BOOT, HAT, HATTRIM, CAPE, ACCENT, METAL, WOOD, GEM, EYE, WHITE = range(1, 16)
LIGHT = (-0.45, -0.6, 0.66)
_n = math.sqrt(sum(v * v for v in LIGHT))
LIGHT = tuple(v / _n for v in LIGHT)

OY = 4  # the figure's top margin: head gear stays inside the canvas
# per frame: how far the body dips (rows) and which leg is raised
BOB = [0, 1, 0, 1]
STEP = ['', 'L', '', 'R']


class RC:
    """A region canvas: W x H cells of (region, shade) or None."""

    def __init__(self):
        self.g = [[None] * W for _ in range(H)]

    def px(self, x, y, rid, sh=2):
        x, y = int(x), int(y)
        if 0 <= x < W and 0 <= y < H:
            self.g[y][x] = (rid, sh)

    def has(self, x, y):
        return 0 <= x < W and 0 <= y < H and self.g[y][x] is not None

    def rect(self, x, y, w, h, rid, shaded=True):
        x, y, w, h = int(x), int(y), int(w), int(h)
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                sh = 2
                if shaded:
                    if yy == y or xx == x:
                        sh = 3
                    if yy == y + h - 1 or xx == x + w - 1:
                        sh = 1
                    if yy == y and xx == x:
                        sh = 4
                    if (yy == y + h - 1 and xx == x) or (yy == y and xx == x + w - 1):
                        sh = 2
                    if w <= 1 or h <= 1:
                        sh = 3 if (yy == y or xx == x) else 2
                self.px(xx, yy, rid, sh)

    def ellipse(self, cx, cy, rx, ry, rid):
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                nx = (x + 0.5 - cx) / rx
                ny = (y + 0.5 - cy) / ry
                r2 = nx * nx + ny * ny
                if r2 > 1.0:
                    continue
                lam = nx * LIGHT[0] + ny * LIGHT[1] + math.sqrt(1.0 - r2) * LIGHT[2]
                self.px(x, y, rid, 4 if lam > 0.82 else (3 if lam > 0.38 else (2 if lam > -0.05 else 1)))

    def line(self, x0, y0, x1, y1, rid, sh=2):
        steps = int(max(abs(x1 - x0), abs(y1 - y0)))
        for i in range(steps + 1):
            t = i / max(steps, 1)
            self.px(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), rid, sh)

    def erase_where(self, fn):
        for y in range(H):
            for x in range(W):
                if self.g[y][x] is not None and fn(x, y):
                    self.g[y][x] = None

    def to_canvas(self):
        cv = Canvas(W, H)
        for y in range(H):
            for x in range(W):
                cell = self.g[y][x]
                if cell:
                    cv.set(x, y, (cell[0] * 16, cell[1] * 60, 0, 255))
        return cv


def save_part(name, frames_by_facing):
    for facing, frames in frames_by_facing.items():
        sheet([f.to_canvas() for f in frames], os.path.join(OUT, '%s_%s.png' % (name, facing)))


def for_all(draw):
    """draw(rc, facing, frame, bob, step) for each facing and frame -> {facing: [RC]}."""
    out = {}
    for facing in ('down', 'up', 'side'):
        frames = []
        for f in range(FRAMES):
            rc = RC()
            draw(rc, facing, f, BOB[f], STEP[f])
            frames.append(rc)
        out[facing] = frames
    return out


# --------------------------------------------------------------------------------------- the body
def head_y(bob):
    return OY + 4 + bob  # centre row of the head


def base_body(rc, facing, f, bob, step):
    cy = head_y(bob) + 0.5
    if facing == 'side':
        rc.ellipse(8.5, cy, 4.3, 4.1, SKIN)
        rc.px(12, cy + 1.2, SKIN, 3)   # a hint of nose
        rc.px(10, cy + 0.2, EYE, 2)
        rc.px(10, cy + 1.0, EYE, 2)
    elif facing == 'down':
        rc.ellipse(8, cy, 4.6, 4.1, SKIN)
        for ex in (5.5, 9.5):
            rc.px(ex, cy + 0.2, EYE, 2)
            rc.px(ex, cy + 1.0, EYE, 2)
        rc.px(4.5, cy + 2.2, SKIN, 4)
        rc.px(11, cy + 2.2, SKIN, 4)
    else:
        rc.ellipse(8, cy, 4.6, 4.1, SKIN)  # the back of the head (hair covers it)
    legs(rc, facing, bob, step, PANTS)
    hands(rc, facing, bob)


def legs(rc, facing, bob, step, rid):
    top = OY + 14
    if facing == 'side':
        back = -1 if step == 'L' else (1 if step == 'R' else 0)
        front = -back
        rc.rect(6 + back, top, 2, 4, rid)
        rc.rect(8 + front, top, 2, 4 - (1 if front < 0 else 0), rid)
    else:
        l_len = 4 - (1 if step == 'L' else 0)
        r_len = 4 - (1 if step == 'R' else 0)
        rc.rect(5, top, 2, l_len, rid)
        rc.rect(9, top, 2, r_len, rid)


def hands(rc, facing, bob):
    y = OY + 13 + bob
    if facing == 'side':
        rc.px(10, y, SKIN, 3)
    else:
        rc.px(4, y, SKIN, 3)
        rc.px(11, y, SKIN, 2)


# ------------------------------------------------------------------------------------------ boots
def boots(style):
    def draw(rc, facing, f, bob, step):
        top = OY + 18
        extra = 2 if style == 'boots' else 0
        if facing == 'side':
            back = -1 if step == 'L' else (1 if step == 'R' else 0)
            front = -back
            rc.rect(5 + back, top - extra, 3, 2 + extra, BOOT)
            lift = 1 if front < 0 else 0
            rc.rect(8 + front, top - extra - lift, 3, 2 + extra, BOOT)
        else:
            for x, raised in ((5, step == 'L'), (9, step == 'R')):
                lift = 1 if raised else 0
                rc.rect(x - 1, top - extra - lift, 3, 2 + extra, BOOT)
    return draw


# ----------------------------------------------------------------------------------------- outfits
def torso_box(rc, facing, bob, rid, wide=0):
    top = OY + 9 + bob
    if facing == 'side':
        rc.rect(6 - wide // 2, top, 5 + wide // 2, 6, rid)
    else:
        rc.rect(4 - wide, top, 8 + wide * 2, 6, rid)


def sleeves(rc, facing, bob, rid, long=3):
    y = OY + 10 + bob
    if facing == 'side':
        rc.rect(8, y, 2, long + 1, rid)
    else:
        rc.rect(3, y, 2, long + 1, rid)
        rc.rect(11, y, 2, long + 1, rid)


def outfit(style):
    def draw(rc, facing, f, bob, step):
        top = OY + 9 + bob
        belt_y = top + 5
        if style == 'tunic':
            torso_box(rc, facing, bob, OUTFIT)
            sleeves(rc, facing, bob, OUTFIT)
            rc.rect(4, belt_y, 8, 1, TRIM) if facing != 'side' else rc.rect(6, belt_y, 5, 1, TRIM)
            rc.rect(4, belt_y + 1, 8, 1, OUTFIT) if facing != 'side' else rc.rect(6, belt_y + 1, 5, 1, OUTFIT)
        elif style == 'robe':
            torso_box(rc, facing, bob, OUTFIT)
            sleeves(rc, facing, bob, OUTFIT, 3)
            hem_top = top + 6
            for i in range(0, 6):
                spread = 1 + i // 2
                if facing == 'side':
                    rc.rect(6 - spread // 2, hem_top + i, 5 + spread // 2, 1, OUTFIT, shaded=False)
                else:
                    rc.rect(4 - spread, hem_top + i, 8 + spread * 2, 1, OUTFIT, shaded=False)
            rc.rect(4, belt_y, 8, 1, TRIM) if facing != 'side' else rc.rect(6, belt_y, 5, 1, TRIM)
            # shade the folds
            for i in range(1, 6):
                if facing != 'side':
                    rc.px(8, hem_top + i, OUTFIT, 1)
            # hem trim
            span = 1 + 5 // 2
            if facing == 'side':
                rc.rect(6 - span // 2, hem_top + 5, 5 + span // 2, 1, TRIM, shaded=False)
            else:
                rc.rect(4 - span, hem_top + 5, 8 + span * 2, 1, TRIM, shaded=False)
        elif style == 'mail':
            torso_box(rc, facing, bob, OUTFIT)
            sleeves(rc, facing, bob, OUTFIT, 3)
            # shoulder plates, skirt of mail, chest cross
            if facing == 'side':
                rc.rect(7, top - 1, 4, 2, TRIM)
            else:
                rc.rect(2, top - 1, 4, 2, TRIM)
                rc.rect(10, top - 1, 4, 2, TRIM)
            rc.rect(4, belt_y, 8, 1, TRIM) if facing != 'side' else rc.rect(6, belt_y, 5, 1, TRIM)
            rc.rect(4, belt_y + 1, 8, 2, OUTFIT) if facing != 'side' else rc.rect(6, belt_y + 1, 5, 2, OUTFIT)
            if facing == 'down':
                rc.px(7, top + 2, TRIM, 4)
                rc.px(8, top + 2, TRIM, 4)
                rc.px(7, top + 3, TRIM, 3)
                rc.px(8, top + 3, TRIM, 3)
        elif style == 'leather':
            torso_box(rc, facing, bob, OUTFIT)
            sleeves(rc, facing, bob, OUTFIT, 2)
            if facing == 'down':
                rc.line(5, top, 10, top + 4, TRIM, 3)       # a cross strap
                rc.px(7, top + 1, SKIN, 3)
                rc.px(8, top + 1, SKIN, 2)
            rc.rect(4, belt_y, 8, 1, TRIM) if facing != 'side' else rc.rect(6, belt_y, 5, 1, TRIM)
            rc.rect(3, top + 4, 2, 1, TRIM) if facing != 'side' else None
            rc.rect(11, top + 4, 2, 1, TRIM) if facing != 'side' else None
        elif style == 'fur':  # berserker: bare chest, a fur mantle and belt
            torso_box(rc, facing, bob, SKIN)
            sleeves(rc, facing, bob, SKIN, 3)
            if facing == 'side':
                rc.rect(6, top, 5, 2, OUTFIT)
            else:
                rc.rect(3, top - 1, 10, 3, OUTFIT)
                for x in (3, 5, 7, 9, 11):
                    rc.px(x, top + 2, OUTFIT, 1)
            rc.rect(4, belt_y, 8, 2, TRIM) if facing != 'side' else rc.rect(6, belt_y, 5, 2, TRIM)
    return draw


# ------------------------------------------------------------------------------------------- hair
def hair(style):
    def draw(rc, facing, f, bob, step):
        cy = head_y(bob) + 0.5
        if facing == 'down':
            rc.ellipse(8, cy - 0.8, 4.9, 3.6, HAIR)
            rc.erase_where(lambda x, y: y > cy + 0.8 and 5 < x < 11)  # the face shows
            rc.erase_where(lambda x, y: y >= cy - 0.2 and (5 < x < 11) and (x in (6, 7, 9, 10)) and False)
            for x in (5, 7, 9):                                       # a fringe
                rc.px(x, cy + 0.0, HAIR, 3)
            if style == 'long':
                rc.rect(3, cy + 1, 2, 5, HAIR)
                rc.rect(11, cy + 1, 2, 5, HAIR)
            elif style == 'bun':
                rc.ellipse(8, cy - 4.3, 1.8, 1.5, HAIR)
        elif facing == 'up':
            rc.ellipse(8, cy, 4.9, 4.3, HAIR)
            if style == 'long':
                rc.rect(3, cy + 1, 10, 6, HAIR)
            elif style == 'bun':
                rc.ellipse(8, cy - 4.3, 1.8, 1.5, HAIR)
        else:
            rc.ellipse(8, cy - 0.5, 4.5, 3.9, HAIR)
            rc.erase_where(lambda x, y: x > 9 and y > cy + 0.2)       # the face
            rc.erase_where(lambda x, y: x > 10 and y > cy - 1.2)
            rc.px(10, cy - 1, HAIR, 3)
            if style == 'long':
                rc.rect(4, cy + 1, 3, 6, HAIR)
            elif style == 'bun':
                rc.ellipse(5, cy - 3.8, 1.8, 1.5, HAIR)
    return draw


# ---------------------------------------------------------------------------------------- headgear
def headgear(style):
    def draw(rc, facing, f, bob, step):
        cy = head_y(bob) + 0.5
        fx = 8
        if style == 'cap':
            rc.ellipse(fx, cy - 1.4, 4.9, 3.2, HAT)
            rc.erase_where(lambda x, y: y > cy)
            rc.rect(3 if facing != 'side' else 5, int(cy), 10 if facing != 'side' else 7, 1, HATTRIM)
            if facing == 'side':
                rc.rect(10, int(cy), 3, 1, HATTRIM)  # a brim
        elif style == 'helm':
            rc.ellipse(fx, cy - 0.6, 5.0, 4.0, HAT)
            if facing == 'down':
                rc.erase_where(lambda x, y: y > cy - 0.5 and 6 <= x <= 9)   # the visor opening
                rc.rect(7, int(cy - 3), 2, 5, HATTRIM)                       # nose guard
            elif facing == 'side':
                rc.erase_where(lambda x, y: y > cy - 0.3 and x >= 10)
            else:
                rc.erase_where(lambda x, y: y > cy + 3)
            rc.erase_where(lambda x, y: y > cy + 2.5)
            rc.rect(3, int(cy - 1), 10, 1, HATTRIM) if facing != 'side' else rc.rect(4, int(cy - 1), 8, 1, HATTRIM)
        elif style == 'hood':
            rc.ellipse(fx, cy - 0.4, 5.2, 4.5, HAT)
            if facing == 'down':
                rc.erase_where(lambda x, y: y > cy - 0.6 and 5 < x < 11 and y < cy + 3)
                rc.erase_where(lambda x, y: y > cy + 1.5 and 5 < x < 11)
            elif facing == 'side':
                rc.erase_where(lambda x, y: x >= 10 and y > cy - 1.2 and y < cy + 3)
            rc.rect(4 if facing != 'side' else 5, int(cy + 3.5), 8 if facing != 'side' else 6, 2, HAT)
        elif style == 'hat':  # a pointed hat with a brim
            cone_top = int(cy - 8)
            for i in range(0, 6):
                half = 1 + i * 0.6
                rc.rect(int(fx - half), cone_top + i + 1, max(2, int(half * 2)), 1, HAT, shaded=False)
            rc.rect(int(fx - 1), cone_top, 2, 1, HAT, 3)
            rc.px(fx - 1, cone_top + 1, HAT, 4)
            rc.rect(2, int(cy - 2), 12, 2, HAT)
            rc.rect(2, int(cy - 1), 12, 1, HATTRIM)
        elif style == 'circlet':
            rc.rect(4 if facing != 'side' else 5, int(cy - 3), 8 if facing != 'side' else 6, 1, HATTRIM)
            if facing == 'down':
                rc.px(fx, int(cy - 3), WHITE, 4)
                rc.px(fx - 1, int(cy - 3), GEM, 3)
                rc.px(fx, int(cy - 4), GEM, 4)
        elif style == 'mask':  # a hood plus a cloth over the lower face
            rc.ellipse(fx, cy - 0.4, 5.2, 4.5, HAT)
            if facing == 'down':
                rc.erase_where(lambda x, y: y > cy - 0.6 and 5 < x < 11 and y < cy + 1.4)
                rc.rect(5, int(cy + 1.4), 6, 2, HATTRIM)
            elif facing == 'side':
                rc.erase_where(lambda x, y: x >= 10 and y > cy - 1.2 and y < cy + 1.2)
                rc.rect(10, int(cy + 1.4), 3, 2, HATTRIM)
            rc.rect(4 if facing != 'side' else 5, int(cy + 3.5), 8 if facing != 'side' else 6, 2, HAT)
        elif style == 'horns':
            rc.ellipse(fx, cy - 0.6, 5.0, 4.0, HAT)
            rc.erase_where(lambda x, y: y > cy - 0.2)
            rc.rect(3 if facing != 'side' else 5, int(cy - 0.5), 10 if facing != 'side' else 7, 1, HATTRIM)
            for sx, d in ((3, -1), (12, 1)):
                rc.line(sx, cy - 2, sx + d * 2, cy - 5, WHITE, 3)
                rc.px(sx + d * 2, cy - 6, WHITE, 4)
        elif style == 'antlers':
            rc.line(5, cy - 3, 3, cy - 6, WOOD, 3)
            rc.line(11, cy - 3, 13, cy - 6, WOOD, 3)
            rc.line(4, cy - 4, 2, cy - 4, WOOD, 3)
            rc.line(12, cy - 4, 14, cy - 4, WOOD, 3)
            rc.px(3, cy - 7, WOOD, 4)
            rc.px(13, cy - 7, WOOD, 4)
        elif style == 'feather':  # a ranger's cap with a feather
            rc.ellipse(fx, cy - 1.4, 4.9, 3.2, HAT)
            rc.erase_where(lambda x, y: y > cy)
            rc.rect(3 if facing != 'side' else 5, int(cy), 10 if facing != 'side' else 7, 1, HATTRIM)
            rc.line(11, cy - 3, 14, cy - 7, WHITE, 3)
            rc.px(14, cy - 7, WHITE, 4)
    return draw


# ------------------------------------------------------------------------------------- back items
def back(style):
    def draw(rc, facing, f, bob, step):
        top = OY + 9 + bob
        if style == 'cape':
            if facing == 'up':
                rc.rect(3, top, 10, 11, CAPE)
                rc.px(8, top + 5, CAPE, 1)
            elif facing == 'down':
                rc.rect(2, top + 1, 2, 9, CAPE)
                rc.rect(12, top + 1, 2, 9, CAPE)
            else:
                rc.rect(3, top, 4, 11, CAPE)
        elif style == 'quiver':
            if facing == 'up':
                rc.line(5, top, 11, top + 6, WOOD, 3)
                rc.line(6, top, 12, top + 6, WOOD, 2)
                for x in (4, 6):
                    rc.px(x, top - 1, WHITE, 3)
            elif facing == 'side':
                rc.line(5, top, 7, top + 5, WOOD, 3)
                rc.px(4, top - 1, WHITE, 3)
            else:
                rc.px(11, top - 1, WHITE, 3)
                rc.px(12, top, WOOD, 2)
        elif style == 'satchel':
            if facing == 'side':
                rc.rect(4, top + 3, 3, 3, WOOD)
            elif facing == 'up':
                rc.rect(9, top + 4, 4, 3, WOOD)
            else:
                rc.line(4, top, 11, top + 6, WOOD, 3)
                rc.rect(10, top + 5, 3, 3, WOOD)
    return draw


# ----------------------------------------------------------------------------------------- accents
def accent(style):
    def draw(rc, facing, f, bob, step):
        top = OY + 9 + bob
        if style == 'sash':
            if facing == 'down':
                rc.line(4, top, 11, top + 5, ACCENT, 3)
                rc.line(4, top + 1, 10, top + 5, ACCENT, 2)
            elif facing == 'side':
                rc.line(6, top, 10, top + 5, ACCENT, 3)
        elif style == 'pauldrons':
            if facing == 'side':
                rc.rect(7, top - 1, 4, 2, ACCENT)
            else:
                rc.rect(2, top - 1, 4, 2, ACCENT)
                rc.rect(10, top - 1, 4, 2, ACCENT)
        elif style == 'collar':
            if facing == 'side':
                rc.rect(7, top - 1, 4, 2, ACCENT)
            else:
                rc.rect(4, top - 1, 8, 2, ACCENT)
                if facing == 'down':
                    rc.px(8, top + 1, ACCENT, 2)
        elif style == 'gem':
            if facing == 'down':
                rc.px(7, top + 2, GEM, 4)
                rc.px(8, top + 2, GEM, 3)
                rc.px(7, top + 3, GEM, 2)
                rc.px(8, top + 3, GEM, 2)
            elif facing == 'side':
                rc.px(9, top + 2, GEM, 4)
        elif style == 'tabard':
            if facing == 'down':
                rc.rect(6, top, 4, 9, ACCENT)
                rc.px(7, top + 3, WHITE, 3)
                rc.px(8, top + 3, WHITE, 3)
            elif facing == 'up':
                rc.rect(6, top, 4, 9, ACCENT)
            else:
                rc.rect(7, top, 3, 9, ACCENT)
    return draw


# ---------------------------------------------------------------------------------------- weapons
def hand(facing, bob):
    y = OY + 13 + bob
    return {'down': (12, y), 'up': (12, y), 'side': (11, y)}[facing]


def weapon(kind):
    def draw(rc, facing, f, bob, step):
        hx, hy = hand(facing, bob)
        s = 1 if facing != 'side' else 1
        if kind == 'sword':
            rc.rect(hx, hy - 1, 1, 3, WOOD)
            rc.rect(hx - 1, hy - 2, 3, 1, METAL, 2)
            rc.rect(hx, hy - 9, 1, 7, METAL)
            rc.px(hx, hy - 10, METAL, 4)
            rc.px(hx + 1, hy - 8, METAL, 4)
        elif kind == 'staff':
            rc.rect(hx, hy - 12, 1, 15, WOOD)
            rc.ellipse(hx + 0.5, hy - 13, 2.0, 2.0, GEM)
            rc.px(hx, hy - 14, WHITE, 4)
        elif kind == 'bow':
            for i in range(-6, 7):
                bend = int(round((1 - (i / 6.0) ** 2) * 2.2))
                rc.px(hx + 1 + bend, hy - 3 + i, WOOD, 3 if i < 0 else 2)
            rc.line(hx + 1, hy - 9, hx + 1, hy + 3, WHITE, 2)
        elif kind == 'rod':
            rc.rect(hx, hy - 5, 1, 8, WOOD)
            rc.ellipse(hx + 0.5, hy - 6, 1.7, 1.7, GEM)
            rc.px(hx, hy - 7, WHITE, 4)
        elif kind == 'dagger':
            rc.rect(hx, hy - 1, 1, 2, WOOD)
            rc.rect(hx - 1, hy - 2, 3, 1, METAL, 2)
            rc.rect(hx, hy - 6, 1, 4, METAL)
            rc.px(hx, hy - 7, METAL, 4)
        elif kind == 'axe':
            rc.rect(hx, hy - 8, 1, 12, WOOD)
            rc.rect(hx + 1, hy - 8, 3, 4, METAL)
            rc.px(hx + 4, hy - 7, METAL, 4)
            rc.px(hx + 4, hy - 6, METAL, 3)
            rc.px(hx + 1, hy - 8, METAL, 4)
        elif kind == 'tome':
            rc.rect(hx - 2, hy - 3, 5, 5, WOOD)
            rc.rect(hx - 1, hy - 2, 3, 3, WHITE)
            rc.px(hx, hy - 1, GEM, 4)
    return draw


# ------------------------------------------------------------------------------------------- build
OUTFITS = ['tunic', 'robe', 'mail', 'leather', 'fur']
HAIRS = ['short', 'long', 'bun']
HEADS = ['cap', 'helm', 'hood', 'hat', 'circlet', 'mask', 'horns', 'antlers', 'feather']
BACKS = ['cape', 'quiver', 'satchel']
ACCENTS = ['sash', 'pauldrons', 'collar', 'gem', 'tabard']
WEAPONS = ['sword', 'staff', 'bow', 'rod', 'dagger', 'axe', 'tome']
BOOTS = ['shoes', 'boots']


def main():
    save_part('base_body', for_all(base_body))
    for b in BOOTS:
        save_part('boots_' + b, for_all(boots(b)))
    for o in OUTFITS:
        save_part('outfit_' + o, for_all(outfit(o)))
    for h in HAIRS:
        save_part('hair_' + h, for_all(hair(h)))
    for hd in HEADS:
        save_part('head_' + hd, for_all(headgear(hd)))
    for b in BACKS:
        save_part('back_' + b, for_all(back(b)))
    for a in ACCENTS:
        save_part('accent_' + a, for_all(accent(a)))
    for w in WEAPONS:
        save_part('weapon_' + w, for_all(weapon(w)))
    print('hero parts ->', os.path.abspath(OUT), len(os.listdir(OUT)), 'files')


if __name__ == '__main__':
    main()
