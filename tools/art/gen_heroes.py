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
Moonlit Glyphwork heroes are 24 x 38 (they were 16 x 26): a head with brows, eyes, nose and mouth, hair with a fringe,
a mantle, an open robe with a placket and rune hem, belts with buckles and pouches, cuffed sleeves, boots with soles,
and weapons with guards, bands and glowing gems. Light comes from the upper left; the figure keeps a 1 px margin so
the composer's ink outline fits inside the frame.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pixel import Canvas, sheet  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'sprites', 'hero')
os.makedirs(OUT, exist_ok=True)

W, H = 24, 38
FRAMES = 4
SKIN, HAIR, OUTFIT, TRIM, PANTS, BOOT, HAT, HATTRIM, CAPE, ACCENT, METAL, WOOD, GEM, EYE, WHITE = range(1, 16)
LIGHT = (-0.45, -0.6, 0.66)
_n = math.sqrt(sum(v * v for v in LIGHT))
LIGHT = tuple(v / _n for v in LIGHT)

HEAD_Y = 13   # centre row of the head when standing
SHOULDER = 20
WAIST = 28
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

    def poly(self, pts, rid, mode='cyl'):
        """A filled polygon shaded like a cylinder lit from the left: light third, mid, dark third, a lit top edge and a
        dark underside. mode 'flat' paints one shade."""
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
            t = (x - lo) / max(hi - lo, 1)
            sh = 3 if t < 0.3 else (1 if t > 0.72 else 2)
            if mode == 'flat':
                sh = 2
            else:
                if (x, y - 1) not in cells:
                    sh = 3
                elif (x, y + 1) not in cells:
                    sh = 1
                elif (x - 1, y) not in cells:
                    sh = 3
            self.px(x, y, rid, sh)

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


# ------------------------------------------------------------------------------------ anatomy anchors
def arms(facing, bob, step):
    """[(x, top_y)] of each visible arm (3 px wide, 9 tall): left then right for the front and back views, the near arm
    only for the side view. Arms swing against the legs."""
    top = SHOULDER + 1 + bob
    if facing == 'side':
        swing = -1 if step == 'L' else (1 if step == 'R' else 0)
        return [(10 + swing, top)]
    return [(3, top + (1 if step == 'R' else 0)), (18, top + (1 if step == 'L' else 0))]


def leg_xs(facing, step):
    """[(x, raised)] of the two legs (3 px wide)."""
    if facing == 'side':
        back = -1 if step == 'L' else (1 if step == 'R' else 0)
        return [(8 + back, step == 'L'), (11 - back, step == 'R')]
    return [(8, step == 'L'), (13, step == 'R')]


# ------------------------------------------------------------------------------------------ the body
def base_body(rc, facing, f, bob, step):
    cy = HEAD_Y + bob
    legs(rc, facing, step, PANTS)
    if facing == 'side':
        rc.ellipse(11.0, cy + 0.5, 5.0, 5.4, SKIN)
        rc.px(16, cy + 2, SKIN, 3)               # nose
        rc.px(16, cy + 3, SKIN, 2)
        rc.px(14, cy + 1, WHITE, 2)               # eye: white, dark, dark
        rc.px(15, cy + 1, EYE, 2)
        rc.px(15, cy + 2, EYE, 2)
        rc.px(14, cy - 1, HAIR, 1)                # brow
        rc.px(15, cy - 1, HAIR, 1)
        rc.px(15, cy + 4, SKIN, 1)                # mouth
        rc.px(9, cy + 2, SKIN, 3)                 # ear
        rc.px(9, cy + 3, SKIN, 1)
    elif facing == 'down':
        rc.ellipse(11.5, cy + 0.5, 5.2, 5.4, SKIN)
        rc.px(6, cy + 2, SKIN, 3)                 # ears
        rc.px(17, cy + 2, SKIN, 1)
        for bx in (8, 14):                        # brows
            rc.rect(bx, cy - 1, 2, 1, HAIR, shaded=False)
        for ex, white_first in ((8, True), (14, False)):   # eyes: white, dark / dark, white and a dark lower row
            rc.px(ex, cy + 1, WHITE if white_first else EYE, 2)
            rc.px(ex + 1, cy + 1, EYE if white_first else WHITE, 2)
            rc.px(ex + (1 if white_first else 0), cy + 2, EYE, 2)
        rc.px(11, cy + 3, SKIN, 1)                # nose
        rc.px(12, cy + 3, SKIN, 3)
        rc.rect(11, cy + 4, 2, 1, SKIN, shaded=False)
        rc.px(11, cy + 4, SKIN, 1)
        rc.px(12, cy + 4, SKIN, 1)
    else:
        rc.ellipse(11.5, cy + 0.5, 5.2, 5.4, SKIN)  # the back of the head (hair covers it)
    rc.rect(10, cy + 5, 3, 2, SKIN, shaded=False)  # neck
    rc.px(10, cy + 5, SKIN, 3)
    rc.px(12, cy + 6, SKIN, 1)
    for ax, ay in arms(facing, bob, step):         # hands
        rc.rect(ax, ay + 8, 3, 3, SKIN)
        rc.px(ax + 1, ay + 10, SKIN, 1)


def legs(rc, facing, step, rid):
    top = WAIST + 1
    for x, raised in leg_xs(facing, step):
        rc.poly([(x, top), (x + 3, top), (x + 3, top + 6 - (1 if raised else 0)), (x, top + 6 - (1 if raised else 0))], rid)


# ------------------------------------------------------------------------------------------ boots
def boots(style):
    def draw(rc, facing, f, bob, step):
        for x, raised in leg_xs(facing, step):
            lift = 1 if raised else 0
            tall = 5 if style == 'boots' else 3
            top = 36 - tall - lift
            toe = 1 if facing == 'side' else 0
            rc.poly([(x - 1, top), (x + 4 + toe, top), (x + 4 + toe, 36 - lift), (x - 1, 36 - lift)], BOOT)
            rc.rect(x - 1, 35 - lift, 5 + toe, 1, BOOT, shaded=False)     # a dark sole
            rc.rect(x - 1, 35 - lift, 5 + toe, 1, BOOT, shaded=False)
            for i in range(x - 1, x + 4 + toe):
                rc.px(i, 35 - lift, BOOT, 1)
            if style == 'boots':
                rc.rect(x - 1, top, 5 + toe, 1, TRIM, shaded=False)        # a cuff
                rc.px(x + 1, top + 2, METAL, 4)                            # a buckle
            else:
                rc.px(x, top + 1, BOOT, 4)
    return draw


# ----------------------------------------------------------------------------------------- outfits
def torso(rc, facing, bob, rid, flare=0):
    top = SHOULDER + bob
    if facing == 'side':
        rc.poly([(8, top + 1), (9, top), (15, top), (16, top + 1), (15 + flare, WAIST + 1 + bob), (8 - flare, WAIST + 1 + bob)], rid)
    else:
        rc.poly([(7, top), (16, top), (18, top + 2), (17 + flare, WAIST + 1 + bob), (6 - flare, WAIST + 1 + bob), (5, top + 2)], rid)


def sleeves(rc, facing, bob, step, rid, length=7, cuff=TRIM, bare=SKIN):
    for ax, ay in arms(facing, bob, step):
        rc.poly([(ax, ay), (ax + 3, ay), (ax + 3, ay + length), (ax, ay + length)], rid)
        if cuff:
            rc.rect(ax, ay + length - 1, 3, 2, cuff)
        if length < 8 and bare is not None:       # a short sleeve leaves the forearm bare
            rc.rect(ax, ay + length + 1, 3, 8 - length - 1, bare)


def belt(rc, facing, bob, rid=TRIM, buckle=METAL):
    y = WAIST - 1 + bob
    if facing == 'side':
        rc.rect(8, y, 8, 2, rid)
        rc.px(15, y, buckle, 4)
        rc.px(15, y + 1, buckle, 2)
    else:
        rc.rect(6, y, 12, 2, rid)
        if facing == 'down':
            rc.rect(11, y, 2, 2, buckle)
            rc.px(11, y, buckle, 4)


def outfit(style):
    def draw(rc, facing, f, bob, step):
        top = SHOULDER + bob
        if style == 'tunic':
            torso(rc, facing, bob, OUTFIT, 1)
            sleeves(rc, facing, bob, step, OUTFIT, 6, cuff=TRIM)
            belt(rc, facing, bob)
            if facing != 'side':
                rc.rect(7, WAIST + 1 + bob, 10, 3, OUTFIT)       # a short skirt below the belt
                rc.px(11, WAIST + 2 + bob, OUTFIT, 1)
                rc.px(12, WAIST + 3 + bob, OUTFIT, 1)
                rc.rect(7, WAIST + 3 + bob, 10, 1, TRIM, shaded=False)
            else:
                rc.rect(8, WAIST + 1 + bob, 8, 3, OUTFIT)
                rc.rect(8, WAIST + 3 + bob, 8, 1, TRIM, shaded=False)
            if facing == 'down':
                rc.rect(9, top, 6, 1, TRIM, shaded=False)         # a laced collar
                rc.px(11, top + 1, TRIM, 3)
                rc.px(12, top + 2, TRIM, 3)
                rc.px(11, top + 3, TRIM, 3)
        elif style == 'robe':
            mantle = [(5, top - 1), (18, top - 1), (20, top + 3), (3, top + 3)]
            hem_top = WAIST + bob
            skirt = [(6, hem_top), (17, hem_top), (20, 36), (3, 36)] if facing != 'side' else [(8, hem_top), (16, hem_top), (19, 36), (6, 36)]
            rc.poly(skirt, OUTFIT)
            torso(rc, facing, bob, OUTFIT)
            sleeves(rc, facing, bob, step, OUTFIT, 7, cuff=TRIM)
            if facing == 'down':
                rc.poly([(11, top + 1), (13, top + 1), (14, 36), (10, 36)], OUTFIT, 'flat')    # the open front
                rc.rect(11, top + 1, 1, 36 - top - 1, TRIM)                                   # a placket edge
                for y in (top + 4, top + 8):
                    rc.px(12, y, TRIM, 4)                                                    # studs
                for fx in (7, 15, 17):                                                       # skirt folds
                    rc.line(fx, hem_top + 2, fx - 1, 35, OUTFIT, 1)
            elif facing == 'up':
                for fx in (9, 12, 15):
                    rc.line(fx, hem_top + 2, fx, 35, OUTFIT, 1)
            else:
                for fx in (9, 12):
                    rc.line(fx, hem_top + 2, fx - 1, 35, OUTFIT, 1)
            belt(rc, facing, bob)
            hx0, hx1 = (6, 17) if facing == 'side' else (3, 20)
            rc.rect(hx0, 35, hx1 - hx0 + 1, 1, TRIM, shaded=False)                            # hem trim
            for x in range(hx0 + 1, hx1, 3):                                                  # rune marks on the hem
                rc.px(x, 34, TRIM, 4)
            rc.poly(mantle, CAPE) if facing != 'side' else rc.poly([(6, top - 1), (16, top - 1), (17, top + 3), (5, top + 3)], CAPE)
            rc.rect(3 if facing != 'side' else 5, top + 3, 18 if facing != 'side' else 12, 1, TRIM, shaded=False)
            for x in ((6, 11, 16) if facing != 'side' else (7, 11, 15)):
                rc.px(x, top + 3, TRIM, 4)
        elif style == 'mail':
            torso(rc, facing, bob, OUTFIT, 1)
            sleeves(rc, facing, bob, step, OUTFIT, 7, cuff=TRIM)
            for y in range(top + 2, WAIST - 1, 2):                # a chain pattern: shade 1 flecks
                for x in range(7 + (y % 4 == 0), 17, 2):
                    if rc.has(x, y):
                        rc.px(x, y, OUTFIT, 1)
            belt(rc, facing, bob)
            rc.rect(6 if facing != 'side' else 8, WAIST + 1 + bob, 12 if facing != 'side' else 8, 4, OUTFIT)   # a mail skirt
            rc.rect(6 if facing != 'side' else 8, WAIST + 4 + bob, 12 if facing != 'side' else 8, 1, TRIM, shaded=False)
            if facing == 'side':
                rc.poly([(8, top - 1), (14, top - 1), (15, top + 2), (7, top + 2)], TRIM)
            else:
                rc.poly([(2, top - 1), (8, top - 1), (9, top + 2), (3, top + 3)], TRIM)       # pauldrons
                rc.poly([(15, top - 1), (21, top - 1), (20, top + 3), (14, top + 2)], TRIM)
            if facing == 'down':                                   # a gorget and a chest crest
                rc.rect(9, top, 6, 2, TRIM)
                rc.rect(11, top + 3, 2, 4, TRIM)
                rc.px(11, top + 3, TRIM, 4)
                rc.rect(10, top + 5, 4, 1, TRIM, shaded=False)
        elif style == 'leather':
            torso(rc, facing, bob, OUTFIT)
            sleeves(rc, facing, bob, step, OUTFIT, 4, cuff=None)
            for ax, ay in arms(facing, bob, step):
                rc.rect(ax, ay + 5, 3, 3, TRIM)                      # bracers
            if facing == 'down':
                rc.line(6, top, 16, top + 8, TRIM, 3)                 # a cross strap
                rc.line(6, top + 1, 15, top + 8, TRIM, 2)
                rc.rect(10, top, 4, 2, SKIN)
            belt(rc, facing, bob)
            if facing != 'side':
                rc.rect(6, WAIST + 1 + bob, 2, 3, TRIM)               # pouches
                rc.rect(16, WAIST + 1 + bob, 2, 3, TRIM)
            rc.rect(7 if facing != 'side' else 8, WAIST + 1 + bob, 10 if facing != 'side' else 8, 3, OUTFIT)   # a short tasset
            rc.rect(7 if facing != 'side' else 8, WAIST + 3 + bob, 10 if facing != 'side' else 8, 1, TRIM, shaded=False)
        elif style == 'fur':  # berserker: bare chest, a fur mantle and a heavy belt
            torso(rc, facing, bob, SKIN)
            sleeves(rc, facing, bob, step, SKIN, 8, cuff=TRIM, bare=None)
            for ax, ay in arms(facing, bob, step):
                rc.rect(ax, ay + 5, 3, 3, TRIM)                      # arm bands
            if facing == 'side':
                rc.poly([(7, top - 1), (16, top - 1), (17, top + 3), (6, top + 3)], OUTFIT)
            else:
                rc.poly([(3, top - 1), (20, top - 1), (21, top + 3), (2, top + 3)], OUTFIT)
                for x in range(3, 21, 3):                            # a ragged lower edge
                    rc.px(x, top + 4, OUTFIT, 1)
                    rc.px(x + 1, top + 4, OUTFIT, 2)
            rc.rect(6 if facing != 'side' else 8, WAIST - 1 + bob, 12 if facing != 'side' else 8, 3, TRIM)
            if facing == 'down':
                rc.rect(11, WAIST - 1 + bob, 2, 3, WHITE)             # a skull buckle
                rc.px(11, WAIST + bob, EYE, 2)
                rc.px(12, WAIST + bob, EYE, 2)
            rc.rect(7 if facing != 'side' else 8, WAIST + 2 + bob, 10 if facing != 'side' else 8, 3, OUTFIT)   # a fur loincloth
            for x in range(7 if facing != 'side' else 8, 17 if facing != 'side' else 16, 2):
                rc.px(x, WAIST + 5 + bob, OUTFIT, 1)
    return draw


# ------------------------------------------------------------------------------------------- hair
def hair(style):
    def draw(rc, facing, f, bob, step):
        cy = HEAD_Y + bob
        if facing == 'down':
            rc.ellipse(11.5, cy - 0.6, 5.5, 4.6, HAIR)
            rc.erase_where(lambda x, y: y > cy + 0.4 and 7 < x < 16)             # the face shows
            rc.erase_where(lambda x, y: y > cy - 1.6 and 7 < x < 16 and (x < 8 or x > 15) and False)
            for x in (8, 10, 12, 14):                                           # a fringe with points
                rc.px(x, cy - 1, HAIR, 3)
                rc.px(x + 1, cy, HAIR, 2) if x in (8, 12) else None
            rc.rect(7, cy - 1, 2, 4, HAIR)
            rc.rect(15, cy - 1, 2, 4, HAIR)
            if style == 'long':
                rc.poly([(5, cy), (8, cy), (8, cy + 10), (5, cy + 10)], HAIR)
                rc.poly([(15, cy), (18, cy), (18, cy + 10), (15, cy + 10)], HAIR)
            elif style == 'bun':
                rc.ellipse(11.5, cy - 6, 2.4, 2.0, HAIR)
                rc.rect(10, cy - 5, 3, 1, HAIR, shaded=False)
        elif facing == 'up':
            rc.ellipse(11.5, cy + 0.3, 5.7, 5.5, HAIR)
            for x in (8, 11, 14):
                rc.line(x, cy, x, cy + 4, HAIR, 1)
            if style == 'long':
                rc.poly([(5, cy), (18, cy), (19, cy + 12), (4, cy + 12)], HAIR)
                rc.line(11, cy + 3, 11, cy + 11, HAIR, 1)
                rc.line(14, cy + 3, 15, cy + 11, HAIR, 1)
            elif style == 'bun':
                rc.ellipse(11.5, cy - 6, 2.4, 2.0, HAIR)
        else:
            rc.ellipse(10.5, cy - 0.4, 5.2, 4.8, HAIR)
            rc.erase_where(lambda x, y: x > 13 and y > cy + 0.2)                 # the face
            rc.erase_where(lambda x, y: x > 14 and y > cy - 1.2)
            rc.px(14, cy - 1, HAIR, 3)
            rc.px(13, cy, HAIR, 3)
            rc.poly([(6, cy), (10, cy), (10, cy + 5), (6, cy + 4)], HAIR)
            if style == 'long':
                rc.poly([(5, cy + 2), (10, cy + 2), (10, cy + 12), (5, cy + 11)], HAIR)
            elif style == 'bun':
                rc.ellipse(7, cy - 5.5, 2.4, 2.0, HAIR)
    return draw


# ---------------------------------------------------------------------------------------- headgear
def headgear(style):
    def draw(rc, facing, f, bob, step):
        cy = HEAD_Y + bob
        fx = 11.5 if facing != 'side' else 10.5
        x0 = 6 if facing != 'side' else 6
        wide = 11 if facing != 'side' else 10
        if style == 'cap':
            rc.ellipse(fx, cy - 1.8, 5.8, 4.2, HAT)
            rc.erase_where(lambda x, y: y > cy)
            rc.rect(x0 - 1, cy - 1, wide + 2, 2, HATTRIM)
            if facing == 'side':
                rc.rect(14, cy - 1, 4, 2, HATTRIM)       # a short peak
            rc.px(int(fx), cy - 6, HATTRIM, 4)
        elif style == 'helm':
            rc.ellipse(fx, cy - 0.5, 5.9, 5.6, HAT)
            if facing == 'down':
                rc.erase_where(lambda x, y: y > cy - 1 and 8 <= x <= 14 and y < cy + 5)   # the visor opening
                rc.rect(11, cy - 5, 2, 8, HATTRIM)                                         # a nose guard
                rc.rect(8, cy - 1, 7, 1, HATTRIM, shaded=False)
            elif facing == 'side':
                rc.erase_where(lambda x, y: y > cy - 1 and x >= 13 and y < cy + 5)
                rc.rect(12, cy - 1, 5, 1, HATTRIM, shaded=False)
            else:
                rc.erase_where(lambda x, y: y > cy + 4)
            rc.erase_where(lambda x, y: y > cy + 4)
            rc.rect(x0 - 1, cy - 3, wide + 2, 1, HATTRIM, shaded=False)
            rc.px(int(fx), cy - 6, HATTRIM, 4)
            rc.rect(int(fx) - 1, cy - 7, 2, 1, HATTRIM, shaded=False)   # a crest
        elif style == 'hood':
            rc.ellipse(fx, cy - 0.2, 6.3, 6.2, HAT)
            if facing == 'down':
                rc.erase_where(lambda x, y: y > cy - 1 and 7 < x < 16 and y < cy + 5)
            elif facing == 'side':
                rc.erase_where(lambda x, y: x >= 13 and y > cy - 1.5 and y < cy + 5)
            rc.poly([(x0 - 1, cy + 5), (x0 + wide + 1, cy + 5), (x0 + wide + 2, cy + 8), (x0 - 2, cy + 8)], HAT)   # the cowl on the shoulders
            rc.rect(x0 + 1, cy + 8, wide - 2, 1, HATTRIM, shaded=False)
        elif style == 'hat':  # a pointed hat with a brim, a band and a gem
            rc.poly([(2, cy - 2), (21, cy - 2), (19, cy - 4), (4, cy - 4)], HAT)
            rc.rect(2, cy - 2, 20, 1, HAT, 1)
            rc.poly([(7, cy - 3), (16, cy - 3), (15, cy - 8), (17, cy - 11), (13, cy - 12), (11, cy - 10), (9, cy - 6)], HAT)
            rc.rect(7, cy - 5, 10, 2, HATTRIM)
            rc.rect(11, cy - 6, 3, 3, GEM)
            rc.px(12, cy - 5, WHITE, 4)
            rc.px(15, cy - 11, HATTRIM, 4)
        elif style == 'circlet':
            rc.rect(x0, cy - 3, wide, 1, HATTRIM, shaded=False)
            rc.rect(x0 + 1, cy - 4, wide - 2, 1, HATTRIM, shaded=False) if facing != 'side' else None
            if facing == 'down':
                rc.rect(11, cy - 5, 2, 3, GEM)
                rc.px(11, cy - 5, WHITE, 4)
                rc.px(8, cy - 4, HATTRIM, 4)
                rc.px(15, cy - 4, HATTRIM, 4)
            elif facing == 'side':
                rc.rect(13, cy - 5, 2, 3, GEM)
                rc.px(13, cy - 5, WHITE, 4)
        elif style == 'mask':  # a hood plus a cloth over the lower face
            rc.ellipse(fx, cy - 0.2, 6.3, 6.2, HAT)
            if facing == 'down':
                rc.erase_where(lambda x, y: y > cy - 1 and 7 < x < 16 and y < cy + 3)
                rc.rect(7, cy + 3, 9, 3, HATTRIM)
                rc.px(11, cy + 3, HATTRIM, 4)
            elif facing == 'side':
                rc.erase_where(lambda x, y: x >= 13 and y > cy - 1.5 and y < cy + 3)
                rc.rect(12, cy + 3, 5, 3, HATTRIM)
            rc.poly([(x0 - 1, cy + 6), (x0 + wide + 1, cy + 6), (x0 + wide + 2, cy + 8), (x0 - 2, cy + 8)], HAT)
        elif style == 'horns':
            rc.ellipse(fx, cy - 0.8, 5.9, 5.0, HAT)
            rc.erase_where(lambda x, y: y > cy - 0.5)
            rc.rect(x0 - 1, cy - 1, wide + 2, 2, HATTRIM)
            for sx, d in ((x0 - 1, -1), (x0 + wide, 1)):
                rc.line(sx, cy - 3, sx + d * 3, cy - 8, WHITE, 3)
                rc.line(sx + d, cy - 3, sx + d * 3, cy - 7, WHITE, 1)
                rc.px(sx + d * 3, cy - 9, WHITE, 4)
        elif style == 'antlers':
            for sx, d in ((8, -1), (15, 1)):
                rc.line(sx, cy - 4, sx + d * 3, cy - 9, WOOD, 3)
                rc.line(sx + d, cy - 5, sx + d * 5, cy - 6, WOOD, 3)
                rc.line(sx + d * 2, cy - 7, sx + d * 4, cy - 11, WOOD, 3)
                rc.px(sx + d * 3, cy - 10, WOOD, 4)
            rc.rect(7, cy - 4, 10, 1, WOOD, shaded=False)
        elif style == 'feather':  # a ranger's cap with a feather
            rc.ellipse(fx, cy - 1.8, 5.8, 4.2, HAT)
            rc.erase_where(lambda x, y: y > cy)
            rc.rect(x0 - 1, cy - 1, wide + 2, 2, HATTRIM)
            rc.line(16, cy - 4, 20, cy - 12, WHITE, 3)
            rc.line(17, cy - 4, 20, cy - 10, WHITE, 2)
            rc.px(20, cy - 12, WHITE, 4)
    return draw


# ------------------------------------------------------------------------------------- back items
def back(style):
    def draw(rc, facing, f, bob, step):
        top = SHOULDER + bob
        sway = 1 if step else 0
        if style == 'cape':
            if facing == 'up':
                rc.poly([(5, top), (18, top), (21, 35), (2, 35)], CAPE)
                rc.line(11, top + 5, 10, 34, CAPE, 1)
                rc.line(15, top + 4, 17, 34, CAPE, 1)
                rc.rect(2, 35, 20, 1, TRIM, shaded=False)
            elif facing == 'down':
                rc.poly([(3, top + 1), (6, top + 1), (5, 34 - sway), (2, 34 - sway)], CAPE)
                rc.poly([(17, top + 1), (20, top + 1), (21, 34 - sway), (18, 34 - sway)], CAPE)
            else:
                rc.poly([(5, top), (9, top), (7 - sway, 35), (2 - sway, 35)], CAPE)
                rc.line(6, top + 4, 4 - sway, 34, CAPE, 1)
        elif style == 'quiver':
            if facing == 'up':
                rc.poly([(8, top - 1), (12, top - 1), (17, top + 12), (13, top + 12)], WOOD)
                for x in (8, 10, 11):
                    rc.px(x, top - 2, WHITE, 3)
                    rc.px(x, top - 3, ACCENT, 3)
                rc.line(6, top + 1, 17, top + 9, TRIM, 2)
            elif facing == 'side':
                rc.poly([(5, top), (8, top), (9, top + 10), (6, top + 10)], WOOD)
                rc.px(6, top - 1, WHITE, 3)
                rc.px(7, top - 2, ACCENT, 3)
            else:
                rc.px(16, top - 2, WHITE, 3)
                rc.px(17, top - 3, ACCENT, 3)
                rc.px(17, top - 1, WOOD, 2)
        elif style == 'satchel':
            if facing == 'side':
                rc.rect(5, top + 6, 4, 5, WOOD)
                rc.rect(5, top + 6, 4, 1, TRIM, shaded=False)
            elif facing == 'up':
                rc.rect(13, top + 7, 6, 5, WOOD)
                rc.rect(13, top + 7, 6, 1, TRIM, shaded=False)
                rc.line(6, top, 16, top + 7, WOOD, 3)
            else:
                rc.line(6, top, 16, top + 9, WOOD, 3)
                rc.rect(15, top + 8, 5, 5, WOOD)
                rc.px(17, top + 9, TRIM, 4)
    return draw


# ----------------------------------------------------------------------------------------- accents
def accent(style):
    def draw(rc, facing, f, bob, step):
        top = SHOULDER + bob
        if style == 'sash':
            if facing == 'down':
                rc.line(6, top + 1, 16, top + 9, ACCENT, 3)
                rc.line(6, top + 2, 15, top + 9, ACCENT, 2)
                rc.rect(14, top + 8, 3, 4, ACCENT)
            elif facing == 'side':
                rc.line(8, top + 1, 15, top + 8, ACCENT, 3)
                rc.line(8, top + 2, 14, top + 8, ACCENT, 2)
            else:
                rc.line(6, top + 1, 16, top + 9, ACCENT, 3)
        elif style == 'pauldrons':
            if facing == 'side':
                rc.poly([(7, top - 2), (14, top - 2), (16, top + 2), (6, top + 3)], ACCENT)
                rc.px(10, top - 1, ACCENT, 4)
            else:
                rc.poly([(1, top - 1), (8, top - 2), (9, top + 2), (2, top + 4)], ACCENT)
                rc.poly([(15, top - 2), (22, top - 1), (21, top + 4), (14, top + 2)], ACCENT)
                rc.px(4, top - 1, ACCENT, 4)
                rc.px(19, top - 1, ACCENT, 4)
        elif style == 'collar':
            if facing == 'side':
                rc.poly([(8, top - 2), (15, top - 2), (16, top + 2), (7, top + 2)], ACCENT)
            else:
                rc.poly([(6, top - 2), (17, top - 2), (18, top + 2), (5, top + 2)], ACCENT)
                if facing == 'down':
                    rc.rect(11, top + 2, 2, 2, ACCENT)
                    rc.px(11, top + 3, GEM, 4)
        elif style == 'gem':
            if facing == 'down':
                rc.poly([(11.5, top + 3), (14, top + 5), (11.5, top + 8), (9, top + 5)], GEM, 'flat')
                rc.px(11, top + 4, WHITE, 4)
                rc.px(12, top + 5, GEM, 3)
                rc.rect(8, top + 2, 8, 1, ACCENT, shaded=False)    # a chain
            elif facing == 'side':
                rc.rect(14, top + 4, 2, 3, GEM)
                rc.px(14, top + 4, WHITE, 4)
        elif style == 'tabard':
            if facing == 'down':
                rc.poly([(9, top), (15, top), (15, 33), (12, 35), (9, 33)], ACCENT)
                rc.rect(11, top + 3, 2, 4, WHITE)
                rc.px(11, top + 3, WHITE, 4)
                rc.rect(9, top + 12, 6, 1, ACCENT, 1)
            elif facing == 'up':
                rc.poly([(9, top), (15, top), (15, 33), (12, 35), (9, 33)], ACCENT)
            else:
                rc.poly([(10, top), (14, top), (14, 33), (12, 35), (10, 33)], ACCENT)
    return draw


# ---------------------------------------------------------------------------------------- weapons
def hand(facing, bob):
    y = SHOULDER + 11 + bob
    return {'down': (19, y), 'up': (19, y), 'side': (13, y)}[facing]


def weapon(kind):
    def draw(rc, facing, f, bob, step):
        hx, hy = hand(facing, bob)
        if kind == 'sword':
            rc.rect(hx, hy - 1, 2, 4, WOOD)                    # grip
            rc.rect(hx - 2, hy - 3, 6, 2, METAL)               # guard
            rc.px(hx - 2, hy - 3, METAL, 4)
            rc.rect(hx, hy + 3, 2, 1, METAL, 3)                # pommel
            rc.poly([(hx, hy - 4), (hx + 2, hy - 4), (hx + 2, hy - 15), (hx + 1, hy - 17), (hx, hy - 15)], METAL)
            rc.line(hx, hy - 5, hx, hy - 15, METAL, 4)         # a bright edge
        elif kind == 'staff':
            rc.rect(hx, hy - 18, 2, 22, WOOD)
            for y in (hy - 6, hy):
                rc.rect(hx - 1, y, 4, 1, TRIM, shaded=False)
            rc.poly([(hx + 1, hy - 28), (hx + 4, hy - 24), (hx + 1, hy - 19), (hx - 2, hy - 24)], GEM, 'flat')   # a crystal head
            rc.px(hx, hy - 25, WHITE, 4)
            rc.px(hx, hy - 24, GEM, 4)
            rc.px(hx + 2, hy - 22, GEM, 1)
            rc.px(hx - 2, hy - 18, TRIM, 3)
            rc.px(hx + 3, hy - 18, TRIM, 2)
        elif kind == 'bow':
            for i in range(-8, 9):
                bend = int(round((1 - (i / 8.0) ** 2) * 2.0))
                rc.px(hx + 1 + bend, hy - 5 + i, WOOD, 3 if i < 0 else 2)
                if abs(i) > 6:
                    rc.px(hx + bend, hy - 5 + i, WOOD, 1)
            rc.line(hx + 1, hy - 13, hx + 1, hy + 3, WHITE, 2)   # the string
            rc.px(hx + 3, hy - 5, TRIM, 4)                       # a grip wrap
            rc.px(hx + 3, hy - 4, TRIM, 2)
        elif kind == 'rod':
            rc.rect(hx, hy - 8, 2, 12, WOOD)
            rc.rect(hx - 1, hy - 1, 4, 1, TRIM, shaded=False)
            rc.ellipse(hx + 1, hy - 11, 3.0, 3.0, GEM)
            rc.px(hx, hy - 12, WHITE, 4)
            rc.px(hx - 3, hy - 11, GEM, 4)
            rc.px(hx + 5, hy - 11, GEM, 1)
            rc.px(hx + 1, hy - 15, GEM, 3)
        elif kind == 'dagger':
            rc.rect(hx, hy - 1, 2, 3, WOOD)
            rc.rect(hx - 2, hy - 3, 6, 2, METAL)
            rc.rect(hx, hy + 2, 2, 1, METAL, 3)
            rc.poly([(hx, hy - 4), (hx + 2, hy - 4), (hx + 2, hy - 9), (hx + 1, hy - 11), (hx, hy - 9)], METAL)
            rc.line(hx, hy - 5, hx, hy - 9, METAL, 4)
        elif kind == 'axe':
            rc.rect(hx, hy - 14, 2, 19, WOOD)
            rc.rect(hx - 1, hy + 1, 4, 1, TRIM, shaded=False)
            d = 1 if facing == 'side' else -1        # the blade points forward in profile; seen head on it hangs to the left, inside the frame
            if d == 1:
                rc.poly([(hx + 2, hy - 15), (hx + 8, hy - 17), (hx + 9, hy - 9), (hx + 8, hy - 7), (hx + 2, hy - 9)], METAL)
                rc.line(hx + 9, hy - 16, hx + 9, hy - 8, METAL, 4)     # the cutting edge
                rc.poly([(hx, hy - 13), (hx - 3, hy - 12), (hx, hy - 10)], METAL)
                rc.px(hx + 4, hy - 13, METAL, 1)
            else:
                rc.poly([(hx, hy - 15), (hx - 6, hy - 17), (hx - 7, hy - 9), (hx - 6, hy - 7), (hx, hy - 9)], METAL)
                rc.line(hx - 7, hy - 16, hx - 7, hy - 8, METAL, 4)
                rc.poly([(hx + 2, hy - 13), (hx + 3, hy - 12), (hx + 2, hy - 10)], METAL)
                rc.px(hx - 4, hy - 13, METAL, 1)
        elif kind == 'tome':
            hx -= 1
            rc.rect(hx - 3, hy - 6, 8, 9, WOOD)
            rc.rect(hx - 2, hy - 5, 6, 7, WHITE)
            rc.rect(hx - 3, hy - 6, 1, 9, TRIM)
            rc.rect(hx - 1, hy - 4, 4, 1, WOOD, 1)
            rc.rect(hx - 1, hy - 2, 4, 1, WOOD, 1)
            rc.px(hx + 1, hy - 3, GEM, 4)
            rc.px(hx + 4, hy - 1, TRIM, 4)
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
