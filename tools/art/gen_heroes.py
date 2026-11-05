"""Layered hero parts -> elementalist/assets/sprites/hero/<part>_<variant>_<facing>.png. Run: python tools/art/gen_heroes.py

A hero is drawn from interchangeable PARTS (body, boots, outfit, hair, head gear, back item, accent, weapon)
so the sprite can change with class, subclass and every equipped item. The parts are not coloured:
each pixel stores a REGION and a SHADE, and the game paints them with a palette when it composes the
hero (scripts/character/hero_composer.gd), so one set of shapes serves every colour scheme.

Pixel encoding:  R = region * 16,  G = shade * 60,  B = 0,  A = 255
Regions: 1 skin  2 hair  3 outfit  4 trim  5 pants  6 boots  7 headgear  8 headgear trim  9 cape/back
         10 accent  11 metal  12 wood  13 gem  14 eyes  15 white
Shades:  1 dark  2 mid  3 light  4 highlight (0 is the outline, which the composer adds around the whole hero)

Every part is a strip of FRAMES frames (W x H each) for the three facings: down, up and side (facing right). The frames are poses
(POSES): 4 walk, 2 idle, 3 attack, 2 dodge, 4 swirl, 3 cast, 2 stun and 1 hurt. Arms are drawn along an angle, weapons are drawn upright
and rotated about the hand, legs can spread, and the body can crouch (bob), so every part follows the pose.

The figure is drawn with natural proportions, in the soft, detailed manner of cosy village RPGs: a head about a quarter of the
height, a neck, shoulders, a waist, arms that end in hands, legs that end in shoes, hair with volume and highlight clusters,
clothes with folds, hems, cuffs and belts. The canvas is 24 x 38 and the figure keeps a 1 px margin so the composer's selective
outline fits inside the frame. Light comes from the upper left.

Anatomy (rows from the top, standing): hair 3-6, head 4-14, neck 14-15, shoulders 16, waist 24, hips 25, knees 30, shoes 34-36.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pixel import Canvas, sheet  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'sprites', 'hero')
os.makedirs(OUT, exist_ok=True)

W, H = 40, 38
OX = 8          # the figure is drawn in 24-wide coordinates; the grid has 8 spare columns on each side for swings and raised arms
CELL = 24      # width of the figure's own cell (portraits and enemies are cut to it)
SKIN, HAIR, OUTFIT, TRIM, PANTS, BOOT, HAT, HATTRIM, CAPE, ACCENT, METAL, WOOD, GEM, EYE, WHITE = range(1, 16)
LIGHT = (-0.45, -0.6, 0.66)
_n = math.sqrt(sum(v * v for v in LIGHT))
LIGHT = tuple(v / _n for v in LIGHT)

HEAD_Y = 9      # centre row of the head when standing
SHOULDER = 16
HIP = 25
FOOT = 36       # last row of the shoes
# the walk cycle (the enemies that use the rig still walk it): how far the body dips (rows) and which leg is raised
BOB = [0, 1, 0, 1]
STEP = ['', 'L', '', 'R']


def pose(bob=0, step='', af=0, ab=0, spread=0, wa=0):
    """One frame's pose: body dip (rows), raised leg, front (right) and back (left) arm angles in degrees from hanging (positive swings
    out and up, 90 is horizontal, 180 straight up), how far the legs spread, and the weapon's turn in degrees (clockwise, 0 is upright)."""
    return dict(bob=bob, step=step, af=af, ab=ab, spread=spread, wa=wa)


POSES = [
    pose(0, ''), pose(1, 'L'), pose(0, ''), pose(1, 'R'),                                                       # 0-3 walk
    pose(0, '', af=4, ab=4), pose(1, '', af=6, ab=6),                                                           # 4-5 idle
    pose(1, '', af=-35, ab=15, spread=1, wa=-50), pose(1, '', af=62, ab=-20, spread=2, wa=70), pose(0, '', af=38, ab=-10, spread=1, wa=105),   # 6-8 attack
    pose(4, '', af=-40, ab=-40, spread=2, wa=-30), pose(6, '', af=25, ab=25, spread=0, wa=-20),                   # 9-10 dodge
    pose(2, '', af=55, ab=55, spread=2, wa=0), pose(2, '', af=55, ab=55, spread=2, wa=45),
    pose(2, '', af=55, ab=55, spread=2, wa=0), pose(2, '', af=55, ab=55, spread=2, wa=-45),                       # 11-14 swirl
    pose(0, '', af=70, ab=70, wa=10), pose(0, '', af=120, ab=120, wa=5), pose(0, '', af=150, ab=150, wa=0),      # 15-17 cast
    pose(3, '', af=12, ab=-12, spread=1, wa=15), pose(2, '', af=-12, ab=12, wa=-15),                              # 18-19 stun
    pose(2, '', af=55, ab=55, spread=1, wa=40),                                                                 # 20 hurt
]
FRAMES = len(POSES)
POSE = dict(POSES[0])
CLIPS = {'walk': (0, 4), 'idle': (4, 2), 'attack': (6, 3), 'dodge': (9, 2), 'swirl': (11, 4), 'cast': (15, 3), 'stun': (18, 2), 'hurt': (20, 1)}


class RC:
    """A region canvas: W x H cells of (region, shade) or None."""

    def __init__(self):
        self.g = [[None] * W for _ in range(H)]

    def px(self, x, y, rid, sh=2):
        x, y = int(x) + OX, int(y)
        if 0 <= x < W and 0 <= y < H:
            self.g[y][x] = (rid, sh)

    def has(self, x, y):
        x += OX
        return 0 <= x < W and 0 <= y < H and self.g[y][x] is not None

    def get(self, x, y):
        x += OX
        return self.g[y][x] if 0 <= x < W and 0 <= y < H else None

    def merge(self, other):
        for y in range(H):
            for x in range(W):
                if other.g[y][x] is not None:
                    self.g[y][x] = other.g[y][x]

    def rotated(self, pivot, degrees):
        """A copy turned clockwise by `degrees` about `pivot` (figure coordinates), nearest-pixel."""
        out = RC()
        if abs(degrees) < 0.5:
            out.g = [row[:] for row in self.g]
            return out
        a = math.radians(degrees)
        ca, sa = math.cos(a), math.sin(a)
        cx, cy = pivot[0] + OX, pivot[1]
        for y in range(H):
            for x in range(W):
                dx, dy = x - cx, y - cy
                sx = int(round(cx + dx * ca + dy * sa))
                sy = int(round(cy - dx * sa + dy * ca))
                if 0 <= sx < W and 0 <= sy < H:
                    out.g[y][x] = self.g[sy][sx]
        return out

    def trim_edges(self):
        """Nothing may sit on the frame's edge cells (the outline needs them): drop what swings that far."""
        for y in range(H):
            for x in range(W):
                if x == 0 or y == 0 or x == W - 1 or y == H - 1:
                    self.g[y][x] = None

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
        dark underside. mode 'flat' paints one shade (2); 'dark' paints shade 1; 'light' shade 3."""
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
            if mode == 'flat':
                sh = 2
            elif mode == 'dark':
                sh = 1
            elif mode == 'light':
                sh = 3
            else:
                sh = 3 if t < 0.3 else (1 if t > 0.7 else 2)
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
                if self.g[y][x] is not None and fn(x - OX, y):
                    self.g[y][x] = None

    def to_canvas(self):
        self.trim_edges()
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
    """draw(rc, facing, frame, bob, step) for each facing and pose frame -> {facing: [RC]}."""
    out = {}
    for facing in ('down', 'up', 'side'):
        frames = []
        for f, pose in enumerate(POSES):
            POSE.clear()
            POSE.update(pose)
            rc = RC()
            draw(rc, facing, f, pose['bob'], pose['step'])
            frames.append(rc)
        out[facing] = frames
    POSE.clear()
    POSE.update(POSES[0])
    return out


# ------------------------------------------------------------------------------------ anatomy anchors
def arm_boxes(facing, bob, step, width=2):
    """[(x, top_y)] of each visible arm. Arms swing against the legs: the arm opposite the raised leg dips one row; in
    profile the near arm swings forward and back."""
    top = SHOULDER + 1 + bob
    if facing == 'side':
        swing = -1 if step == 'L' else (1 if step == 'R' else 0)
        return [(10 + swing, top)]
    return [(6 - width + 1, top + (1 if step == 'R' else 0)), (17, top + (1 if step == 'L' else 0))]


def leg_cols(facing, step):
    """[(x, raised)] of the two legs (3 px wide each, touching in the front and back views); the pose can spread them."""
    sp = POSE['spread']
    if facing == 'side':
        back = -1 if step == 'L' else (1 if step == 'R' else 0)
        return [(8 + back - sp, step == 'L'), (12 - back + sp, step == 'R')]
    return [(9 - sp, step == 'L'), (12 + sp, step == 'R')]


def arm_segs(facing, bob, step, width=2):
    """The arms of the current pose as segments: [{sx, sy, ex, ey, w, front}] (figure coordinates, ey is the wrist). Walking dips the arm
    opposite the raised leg a row and swings the side view's near arm; the pose angles do the rest."""
    top = SHOULDER + 1 + bob
    length = 9.0
    if facing == 'side':
        a = math.radians(POSE['af'] + (-18 if step == 'L' else (18 if step == 'R' else 0)))
        return [dict(sx=11.0, sy=float(top), ex=11.0 + math.sin(a) * length, ey=top + math.cos(a) * length, w=3, front=True)]
    segs = []
    for side, cx, angle in (('l', 6.0, POSE['ab']), ('r', 18.0, POSE['af'])):
        sign = -1.0 if side == 'l' else 1.0
        sy = top + (1 if (side == 'l' and step == 'R') or (side == 'r' and step == 'L') else 0)
        a = math.radians(angle)
        segs.append(dict(sx=cx, sy=float(sy), ex=cx + sign * math.sin(a) * length, ey=sy + math.cos(a) * length, w=width, front=(side == 'r')))
    return segs


def limb(rc, seg, rid, w=None, t0=0.0, t1=1.0, mode='cyl'):
    """A stretch (t0..t1 of its length) of an arm segment, drawn as a shaded band of width w."""
    w = w or seg['w']
    dx, dy = seg['ex'] - seg['sx'], seg['ey'] - seg['sy']
    ln = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / ln * w / 2.0, dx / ln * w / 2.0
    ax, ay = seg['sx'] + dx * t0, seg['sy'] + dy * t0
    bx, by = seg['sx'] + dx * t1, seg['sy'] + dy * t1
    rc.poly([(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)], rid, mode)


def hand_blob(rc, seg):
    """The hand at the end of an arm."""
    w = seg['w']
    rc.ellipse(seg['ex'], seg['ey'] + 1.0, w / 2.0 + 0.5, 1.6, SKIN)


# ------------------------------------------------------------------------------------------ the body
def base_body(rc, facing, f, bob, step):
    cy = HEAD_Y + bob
    for x, raised in leg_cols(facing, step):          # trousers by default; outfits and boots cover them
        lift = 1 if raised else 0
        rc.poly([(x, HIP), (x + 3, HIP), (x + 3, FOOT - 1 - lift), (x, FOOT - 1 - lift)], PANTS)
    if facing == 'side':
        rc.ellipse(11.2, cy + 0.5, 5.0, 5.4, SKIN)
        rc.px(16, cy + 2, SKIN, 3)                    # nose
        rc.px(16, cy + 3, SKIN, 1)
        rc.px(15, cy + 1, EYE, 2)                     # eye: two dark pixels and a brow
        rc.px(15, cy + 2, EYE, 2)
        rc.px(14, cy + 1, SKIN, 1)
        rc.px(14, cy - 1, HAIR, 1)
        rc.px(15, cy - 1, HAIR, 1)
        rc.px(15, cy + 4, SKIN, 1)                    # mouth
        rc.px(14, cy + 3, SKIN, 4)                    # cheek light
        rc.px(9, cy + 2, SKIN, 3)                     # ear
        rc.px(9, cy + 3, SKIN, 1)
    elif facing == 'down':
        rc.ellipse(11.5, cy + 0.5, 5.2, 5.4, SKIN)
        rc.px(6, cy + 2, SKIN, 3)                     # ears
        rc.px(17, cy + 2, SKIN, 1)
        for bx in (8, 14):                            # brows
            rc.rect(bx, cy, 2, 1, HAIR, shaded=False)
            rc.px(bx, cy, HAIR, 1)
        for ex in (9, 14):                            # eyes: two dark rows with a soft lid shadow
            rc.px(ex, cy + 1, EYE, 2)
            rc.px(ex, cy + 2, EYE, 2)
            rc.px(ex + 1, cy + 2, SKIN, 1)
        rc.px(11, cy + 3, SKIN, 1)                    # nose: a shadow and a light
        rc.px(12, cy + 3, SKIN, 3)
        rc.px(11, cy + 4, SKIN, 1)                    # mouth
        rc.px(12, cy + 4, SKIN, 1)
        rc.px(8, cy + 3, SKIN, 4)                     # cheeks catch the light
        rc.px(15, cy + 3, SKIN, 3)
    else:
        rc.ellipse(11.5, cy + 0.5, 5.2, 5.4, SKIN)    # the back of the head (hair covers it)
    if facing == 'side':
        rc.rect(10, cy + 5, 3, 2, SKIN, shaded=False)
        rc.px(10, cy + 5, SKIN, 1)
        rc.px(11, cy + 5, SKIN, 1)
    else:
        rc.rect(10, cy + 5, 4, 2, SKIN, shaded=False)  # neck, shaded under the chin
        for x in (10, 11, 12, 13):
            rc.px(x, cy + 5, SKIN, 1)
    for seg in arm_segs(facing, bob, step):           # hands
        hand_blob(rc, seg)


# ------------------------------------------------------------------------------------------ boots
def boots(style):
    def draw(rc, facing, f, bob, step):
        for x, raised in leg_cols(facing, step):
            lift = 1 if raised else 0
            tall = 6 if style == 'boots' else 3
            top = FOOT + 1 - tall - lift
            toe = 2 if facing == 'side' else 0
            left = x - 1
            right = x + 4 + toe
            rc.poly([(left, top), (right, top), (right, FOOT + 1 - lift), (left, FOOT + 1 - lift)], BOOT)
            for i in range(left, right):
                rc.px(i, FOOT - lift, BOOT, 1)             # a dark sole
            if style == 'boots':
                rc.rect(left, top, right - left, 1, TRIM, shaded=False)    # a folded cuff
                rc.px(x + 1, top + 3, METAL, 4)                           # a buckle
            rc.px(left, top + 1, BOOT, 3)
    return draw


# ----------------------------------------------------------------------------------------- outfits
def torso_poly(facing, bob, flare=0):
    top = SHOULDER + bob
    if facing == 'side':
        return [(9, top + 1), (10, top), (14, top), (15, top + 1), (15 + flare, HIP + bob), (9 - flare, HIP + bob)]
    return [(6, top + 1), (7, top), (16, top), (17, top + 1), (16 + flare, HIP + bob), (7 - flare, HIP + bob)]


def sleeves(rc, facing, bob, step, rid, length=9, width=2, cuff=TRIM, cuff_h=1):
    for seg in arm_segs(facing, bob, step, width):
        w = width if facing != 'side' else 3
        limb(rc, seg, rid, w, 0.0, min(1.0, length / 9.0))
        if cuff:
            limb(rc, seg, cuff, w, max(0.0, (length - cuff_h) / 9.0), min(1.0, length / 9.0))


def belt(rc, facing, bob, rid=TRIM, buckle=METAL, y=None):
    y = (HIP - 2 + bob) if y is None else y
    if facing == 'side':
        rc.rect(9, y, 7, 2, rid)
        rc.px(15, y, buckle, 4)
        rc.px(15, y + 1, buckle, 2)
    else:
        rc.rect(7, y, 10, 2, rid)
        if facing == 'down':
            rc.rect(11, y, 2, 2, buckle)
            rc.px(11, y, buckle, 4)
            rc.px(12, y + 1, buckle, 1)


def folds(rc, xs, y0, y1, rid):
    for x in xs:
        for y in range(y0, y1):
            c = rc.get(x, y)
            if c and c[0] == rid and (y - y0) % 4 != 3:
                rc.px(x, y, rid, 1)


def outfit(style):
    def draw(rc, facing, f, bob, step):
        top = SHOULDER + bob
        if style == 'tunic':
            rc.poly(torso_poly(facing, bob, 1), OUTFIT)
            sleeves(rc, facing, bob, step, OUTFIT, 8, 2, cuff=TRIM)
            hem = HIP + 3 + bob
            if facing == 'side':
                rc.poly([(9, HIP - 1 + bob), (15, HIP - 1 + bob), (16, hem), (8, hem)], OUTFIT)
            else:
                rc.poly([(7, HIP - 1 + bob), (16, HIP - 1 + bob), (18, hem), (5, hem)], OUTFIT)
            belt(rc, facing, bob)
            if facing == 'down':
                rc.px(11, top, SKIN, 3)                                    # a V neck, laced
                rc.px(12, top, SKIN, 3)
                rc.px(11, top + 1, SKIN, 2)
                for y in (top + 1, top + 3):
                    rc.px(11, y, TRIM, 4)
                    rc.px(12, y + 1, TRIM, 2)
                folds(rc, (9, 14), top + 3, HIP - 2, OUTFIT)
        elif style == 'robe':
            hem_y = FOOT - 2
            if facing == 'side':
                skirt = [(9, HIP - 3 + bob), (15, HIP - 3 + bob), (18, hem_y), (6, hem_y)]
            else:
                skirt = [(7, HIP - 3 + bob), (16, HIP - 3 + bob), (19, hem_y), (4, hem_y)]
            rc.poly(skirt, OUTFIT)
            rc.poly(torso_poly(facing, bob), OUTFIT)
            sleeves(rc, facing, bob, step, OUTFIT, 8, 3, cuff=TRIM, cuff_h=2)
            if facing == 'down':
                rc.poly([(11, top + 2), (13, top + 2), (14, hem_y), (10, hem_y)], OUTFIT, 'dark')   # the open front in shadow
                for y in (top + 4, top + 8):
                    rc.px(11, y, TRIM, 4)                                                 # two clasps
            folds(rc, (7, 9, 14, 16, 18), HIP - 1, hem_y, OUTFIT)
            belt(rc, facing, bob, TRIM, METAL, HIP - 3 + bob)
            x0, x1 = (6, 18) if facing == 'side' else (4, 19)
            rc.rect(x0, hem_y - 1, x1 - x0, 2, TRIM, shaded=False)                    # a hem band with a few rune marks
            for x in range(x0 + 2, x1 - 1, 4):
                rc.px(x, hem_y - 1, TRIM, 4)
            if facing == 'side':                                                      # a mantle over the shoulders
                rc.poly([(7, top - 1), (16, top - 1), (17, top + 3), (6, top + 3)], CAPE)
            else:
                rc.poly([(4, top - 1), (19, top - 1), (21, top + 4), (2, top + 4)], CAPE)
                rc.rect(2, top + 4, 20, 1, TRIM, shaded=False)
                for x in (5, 11, 17):
                    rc.px(x, top + 4, TRIM, 4)
        elif style == 'mail':
            rc.poly(torso_poly(facing, bob, 1), OUTFIT)
            sleeves(rc, facing, bob, step, OUTFIT, 8, 2, cuff=TRIM)
            for y in range(top + 2, HIP - 1, 2):                                      # a chain pattern
                for x in range(7 + (y % 4 == 0), 17, 2):
                    if rc.has(x, y) and rc.get(x, y)[0] == OUTFIT:
                        rc.px(x, y, OUTFIT, 1)
            belt(rc, facing, bob)
            lo = HIP + 4 + bob
            if facing == 'side':
                rc.poly([(9, HIP - 1 + bob), (16, HIP - 1 + bob), (16, lo), (8, lo)], OUTFIT)
            else:
                rc.poly([(7, HIP - 1 + bob), (17, HIP - 1 + bob), (19, lo), (4, lo)], OUTFIT)
            rc.rect(6 if facing != 'side' else 8, lo - 1, 12 if facing != 'side' else 8, 1, TRIM, shaded=False)
            if facing == 'side':
                rc.poly([(8, top - 1), (14, top - 1), (15, top + 3), (8, top + 3)], TRIM)
            else:
                rc.poly([(2, top - 1), (8, top - 1), (9, top + 3), (3, top + 4)], TRIM)       # pauldrons
                rc.poly([(15, top - 1), (21, top - 1), (20, top + 4), (14, top + 3)], TRIM)
            if facing == 'down':                                                      # a gorget and a crest
                rc.rect(9, top, 6, 2, TRIM)
                rc.rect(11, top + 3, 2, 5, TRIM)
                rc.px(11, top + 3, TRIM, 4)
                rc.rect(9, top + 5, 6, 1, TRIM, shaded=False)
        elif style == 'leather':
            rc.poly(torso_poly(facing, bob), OUTFIT)
            sleeves(rc, facing, bob, step, OUTFIT, 5, 2, cuff=None)
            for seg in arm_segs(facing, bob, step, 2):
                limb(rc, seg, TRIM, 2 if facing != 'side' else 3, 0.6, 1.0)                # bracers
            if facing == 'down':
                rc.line(7, top, 16, top + 8, TRIM, 3)                                 # a cross strap
                rc.line(7, top + 1, 15, top + 8, TRIM, 2)
                rc.rect(10, top, 4, 2, SKIN)                                          # an open collar
                rc.px(10, top, SKIN, 1)
            belt(rc, facing, bob)
            lo = HIP + 2 + bob
            if facing != 'side':
                rc.poly([(8, HIP - 1 + bob), (15, HIP - 1 + bob), (17, lo), (6, lo)], OUTFIT)   # a short tasset
                rc.rect(6, HIP - 1 + bob, 2, 4, TRIM)                                           # pouches
                rc.rect(16, HIP - 1 + bob, 2, 4, TRIM)
            else:
                rc.poly([(9, HIP - 1 + bob), (15, HIP - 1 + bob), (16, lo), (8, lo)], OUTFIT)
                rc.rect(8, HIP - 1 + bob, 2, 4, TRIM)
        elif style == 'fur':  # berserker: bare chest and arms, a fur mantle, a heavy belt and a loincloth
            rc.poly(torso_poly(facing, bob), SKIN)
            sleeves(rc, facing, bob, step, SKIN, 8, 2, cuff=TRIM, cuff_h=2)
            if facing == 'side':
                rc.poly([(7, top - 1), (16, top - 1), (17, top + 4), (6, top + 4)], OUTFIT)
            else:
                rc.poly([(3, top - 1), (20, top - 1), (21, top + 4), (2, top + 4)], OUTFIT)
                for x in range(3, 21, 3):                                             # a ragged lower edge
                    rc.px(x, top + 5, OUTFIT, 1)
                    rc.px(x + 1, top + 5, OUTFIT, 2)
            rc.rect(7 if facing != 'side' else 9, HIP - 3 + bob, 10 if facing != 'side' else 7, 3, TRIM)
            if facing == 'down':
                rc.rect(11, HIP - 3 + bob, 2, 3, WHITE)                               # a skull buckle
                rc.px(11, HIP - 2 + bob, EYE, 2)
                rc.px(12, HIP - 2 + bob, EYE, 2)
            lo = HIP + 3 + bob
            loin = [(8, HIP + bob), (15, HIP + bob), (16, lo), (7, lo)] if facing != 'side' else [(9, HIP + bob), (15, HIP + bob), (16, lo), (8, lo)]
            rc.poly(loin, OUTFIT)
            for x in range(7 if facing != 'side' else 8, 17):
                if x % 2 == 0:
                    rc.px(x, lo, OUTFIT, 1)
    return draw


# ------------------------------------------------------------------------------------------- hair
def hair(style):
    def draw(rc, facing, f, bob, step):
        cy = HEAD_Y + bob
        if facing == 'down':
            rc.ellipse(11.5, cy - 0.7, 5.8, 5.2, HAIR)
            rc.erase_where(lambda x, y: y > cy - 0.4 and 8 <= x <= 15)                    # the face shows below the fringe
            for x in (8, 10, 12, 14):                                                     # a fringe in points
                rc.px(x, cy - 1, HAIR, 3)
            rc.px(9, cy, HAIR, 2)
            rc.px(13, cy, HAIR, 1)
            rc.rect(6, cy - 2, 2, 6, HAIR)                                                # side locks past the ears
            rc.rect(16, cy - 2, 2, 6, HAIR)
            for x, y in ((9, cy - 4), (10, cy - 4), (13, cy - 3)):                        # highlight clusters
                rc.px(x, y, HAIR, 4)
            if style == 'long':
                rc.poly([(5, cy), (8, cy), (8, cy + 11), (5, cy + 11)], HAIR)
                rc.poly([(15, cy), (18, cy), (18, cy + 11), (15, cy + 11)], HAIR)
                for y in range(cy + 3, cy + 11, 3):
                    rc.px(6, y, HAIR, 4)
            elif style == 'bun':
                rc.ellipse(11.5, cy - 5.6, 2.6, 2.2, HAIR)
                rc.px(10, cy - 6, HAIR, 4)
                rc.rect(10, cy - 4, 3, 1, HAIR, shaded=False)
        elif facing == 'up':
            rc.ellipse(11.5, cy + 0.2, 5.9, 5.8, HAIR)
            for x in (8, 11, 14):
                rc.line(x, cy - 1, x, cy + 5, HAIR, 1)
            for x, y in ((9, cy - 3), (10, cy - 3), (13, cy - 2)):
                rc.px(x, y, HAIR, 4)
            if style == 'long':
                rc.poly([(5, cy), (18, cy), (19, cy + 13), (4, cy + 13)], HAIR)
                rc.line(11, cy + 4, 10, cy + 12, HAIR, 1)
                rc.line(14, cy + 4, 15, cy + 12, HAIR, 1)
                rc.px(7, cy + 6, HAIR, 4)
            elif style == 'bun':
                rc.ellipse(11.5, cy - 5.6, 2.6, 2.2, HAIR)
        else:
            rc.ellipse(10.5, cy - 0.5, 5.4, 5.3, HAIR)
            rc.erase_where(lambda x, y: x > 13 and y > cy - 0.4)                          # the face
            rc.px(14, cy - 1, HAIR, 3)
            rc.px(13, cy, HAIR, 2)
            rc.poly([(5, cy), (10, cy), (10, cy + 6), (5, cy + 5)], HAIR)
            for x, y in ((8, cy - 4), (9, cy - 4), (12, cy - 3)):
                rc.px(x, y, HAIR, 4)
            if style == 'long':
                rc.poly([(4, cy + 2), (10, cy + 2), (10, cy + 13), (4, cy + 12)], HAIR)
                rc.px(6, cy + 7, HAIR, 4)
            elif style == 'bun':
                rc.ellipse(7, cy - 5.6, 2.6, 2.2, HAIR)
    return draw


# ---------------------------------------------------------------------------------------- headgear
def headgear(style):
    def draw(rc, facing, f, bob, step):
        cy = HEAD_Y + bob
        fx = 11.5 if facing != 'side' else 10.5
        x0 = 6
        wide = 11 if facing != 'side' else 10
        if style == 'cap':
            rc.ellipse(fx, cy - 1.8, 5.9, 4.5, HAT)
            rc.erase_where(lambda x, y: y > cy)
            rc.rect(x0 - 1, cy - 1, wide + 2, 2, HATTRIM)
            if facing == 'side':
                rc.rect(14, cy - 1, 4, 2, HATTRIM)                                       # a short peak
            rc.px(int(fx), cy - 6, HATTRIM, 4)
            rc.px(int(fx) - 2, cy - 5, HAT, 4)
        elif style == 'helm':
            rc.ellipse(fx, cy - 0.5, 6.0, 5.8, HAT)
            if facing == 'down':
                rc.erase_where(lambda x, y: y > cy - 1 and 8 <= x <= 15 and y < cy + 5)  # the visor opening
                rc.rect(11, cy - 5, 2, 8, HATTRIM)                                       # a nose guard
                rc.rect(8, cy - 1, 8, 1, HATTRIM, shaded=False)
            elif facing == 'side':
                rc.erase_where(lambda x, y: y > cy - 1 and x >= 13 and y < cy + 5)
                rc.rect(12, cy - 1, 5, 1, HATTRIM, shaded=False)
            else:
                rc.erase_where(lambda x, y: y > cy + 4)
            rc.erase_where(lambda x, y: y > cy + 4)
            rc.rect(x0 - 1, cy - 3, wide + 2, 1, HATTRIM, shaded=False)
            rc.px(int(fx), cy - 6, HATTRIM, 4)
            rc.rect(int(fx) - 1, cy - 7, 2, 1, HATTRIM, shaded=False)                    # a crest
        elif style == 'hood':
            rc.ellipse(fx, cy - 0.2, 6.4, 6.3, HAT)
            if facing == 'down':
                rc.erase_where(lambda x, y: y > cy - 1 and 7 < x < 16 and y < cy + 5)
            elif facing == 'side':
                rc.erase_where(lambda x, y: x >= 13 and y > cy - 1.5 and y < cy + 5)
            rc.poly([(x0 - 1, cy + 5), (x0 + wide + 1, cy + 5), (x0 + wide + 2, cy + 8), (x0 - 2, cy + 8)], HAT)   # the cowl
            rc.rect(x0 + 1, cy + 8, wide - 2, 1, HATTRIM, shaded=False)
        elif style == 'hat':  # a pointed hat with a brim, a band and a gem
            rc.poly([(2, cy - 3), (21, cy - 3), (19, cy - 5), (4, cy - 5)], HAT)
            rc.rect(2, cy - 3, 20, 1, HAT, 1)
            rc.poly([(7, cy - 4), (16, cy - 4), (15, cy - 6), (17, cy - 8), (12, cy - 8), (9, cy - 7)], HAT)
            rc.rect(7, cy - 5, 10, 2, HATTRIM)
            rc.rect(11, cy - 6, 3, 3, GEM)
            rc.px(12, cy - 5, WHITE, 4)
            rc.px(16, cy - 8, HATTRIM, 4)
            for x, y in ((9, cy - 7), (11, cy - 8)):
                rc.px(x, y, HAT, 4)
        elif style == 'circlet':
            rc.rect(x0, cy - 3, wide, 1, HATTRIM, shaded=False)
            if facing != 'side':
                rc.rect(x0 + 1, cy - 4, wide - 2, 1, HATTRIM, shaded=False)
            if facing == 'down':
                rc.rect(11, cy - 5, 2, 3, GEM)
                rc.px(11, cy - 5, WHITE, 4)
                rc.px(8, cy - 4, HATTRIM, 4)
                rc.px(15, cy - 4, HATTRIM, 4)
            elif facing == 'side':
                rc.rect(13, cy - 5, 2, 3, GEM)
                rc.px(13, cy - 5, WHITE, 4)
        elif style == 'mask':  # a hood plus a cloth over the lower face
            rc.ellipse(fx, cy - 0.2, 6.4, 6.3, HAT)
            if facing == 'down':
                rc.erase_where(lambda x, y: y > cy - 1 and 7 < x < 16 and y < cy + 3)
                rc.rect(7, cy + 3, 9, 3, HATTRIM)
                rc.px(11, cy + 3, HATTRIM, 4)
            elif facing == 'side':
                rc.erase_where(lambda x, y: x >= 13 and y > cy - 1.5 and y < cy + 3)
                rc.rect(12, cy + 3, 5, 3, HATTRIM)
            rc.poly([(x0 - 1, cy + 6), (x0 + wide + 1, cy + 6), (x0 + wide + 2, cy + 8), (x0 - 2, cy + 8)], HAT)
        elif style == 'horns':
            rc.ellipse(fx, cy - 0.8, 6.0, 5.2, HAT)
            rc.erase_where(lambda x, y: y > cy - 0.5)
            rc.rect(x0 - 1, cy - 1, wide + 2, 2, HATTRIM)
            for sx, d in ((x0 - 1, -1), (x0 + wide, 1)):
                rc.line(sx, cy - 3, sx + d * 3, cy - 7, WHITE, 3)
                rc.line(sx + d, cy - 3, sx + d * 3, cy - 6, WHITE, 1)
                rc.px(sx + d * 3, cy - 8, WHITE, 4)
        elif style == 'antlers':
            for sx, d in ((8, -1), (15, 1)):
                rc.line(sx, cy - 4, sx + d * 3, cy - 7, WOOD, 3)
                rc.line(sx + d, cy - 5, sx + d * 4, cy - 5, WOOD, 3)
                rc.line(sx + d * 2, cy - 6, sx + d * 4, cy - 8, WOOD, 3)
                rc.px(sx + d * 3, cy - 8, WOOD, 4)
            rc.rect(7, cy - 4, 10, 1, WOOD, shaded=False)
        elif style == 'feather':  # a ranger's cap with a feather
            rc.ellipse(fx, cy - 1.8, 5.9, 4.5, HAT)
            rc.erase_where(lambda x, y: y > cy)
            rc.rect(x0 - 1, cy - 1, wide + 2, 2, HATTRIM)
            rc.line(16, cy - 4, 20, cy - 8, WHITE, 3)
            rc.line(17, cy - 4, 20, cy - 7, WHITE, 2)
            rc.px(20, cy - 8, WHITE, 4)
    return draw


# ------------------------------------------------------------------------------------- back items
def back(style):
    def draw(rc, facing, f, bob, step):
        top = SHOULDER + bob
        sway = 1 if step else 0
        if style == 'cape':
            if facing == 'up':
                rc.poly([(5, top), (18, top), (21, FOOT - 2), (2, FOOT - 2)], CAPE)
                rc.line(11, top + 5, 10, FOOT - 3, CAPE, 1)
                rc.line(15, top + 4, 17, FOOT - 3, CAPE, 1)
                rc.rect(2, FOOT - 2, 20, 1, TRIM, shaded=False)
            elif facing == 'down':
                rc.poly([(3, top + 1), (6, top + 1), (5, FOOT - 3 - sway), (2, FOOT - 3 - sway)], CAPE)
                rc.poly([(17, top + 1), (20, top + 1), (21, FOOT - 3 - sway), (18, FOOT - 3 - sway)], CAPE)
            else:
                rc.poly([(5, top), (9, top), (7 - sway, FOOT - 2), (2 - sway, FOOT - 2)], CAPE)
                rc.line(6, top + 4, 4 - sway, FOOT - 3, CAPE, 1)
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
                rc.rect(5, top + 7, 4, 5, WOOD)
                rc.rect(5, top + 7, 4, 1, TRIM, shaded=False)
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
                rc.line(7, top + 1, 16, top + 9, ACCENT, 3)
                rc.line(7, top + 2, 15, top + 9, ACCENT, 2)
                rc.rect(14, top + 8, 3, 4, ACCENT)
            elif facing == 'side':
                rc.line(9, top + 1, 15, top + 8, ACCENT, 3)
                rc.line(9, top + 2, 14, top + 8, ACCENT, 2)
            else:
                rc.line(7, top + 1, 16, top + 9, ACCENT, 3)
        elif style == 'pauldrons':
            if facing == 'side':
                rc.poly([(8, top - 2), (15, top - 2), (16, top + 2), (7, top + 3)], ACCENT)
                rc.px(11, top - 1, ACCENT, 4)
            else:
                rc.poly([(1, top - 1), (8, top - 2), (9, top + 2), (2, top + 4)], ACCENT)
                rc.poly([(15, top - 2), (22, top - 1), (21, top + 4), (14, top + 2)], ACCENT)
                rc.px(4, top - 1, ACCENT, 4)
                rc.px(19, top - 1, ACCENT, 4)
        elif style == 'collar':
            if facing == 'side':
                rc.poly([(9, top - 2), (15, top - 2), (16, top + 2), (8, top + 2)], ACCENT)
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
                rc.rect(8, top + 2, 8, 1, ACCENT, shaded=False)                          # a chain
            elif facing == 'side':
                rc.rect(14, top + 4, 2, 3, GEM)
                rc.px(14, top + 4, WHITE, 4)
        elif style == 'tabard':
            if facing == 'down':
                rc.poly([(9, top), (15, top), (15, FOOT - 4), (12, FOOT - 2), (9, FOOT - 4)], ACCENT)
                rc.rect(11, top + 3, 2, 4, WHITE)
                rc.px(11, top + 3, WHITE, 4)
                rc.rect(9, top + 12, 6, 1, ACCENT, 1)
            elif facing == 'up':
                rc.poly([(9, top), (15, top), (15, FOOT - 4), (12, FOOT - 2), (9, FOOT - 4)], ACCENT)
            else:
                rc.poly([(10, top), (14, top), (14, FOOT - 4), (12, FOOT - 2), (10, FOOT - 4)], ACCENT)
    return draw


# ---------------------------------------------------------------------------------------- weapons
def hand(facing, bob):
    """Where the front hand grips (figure coordinates): the end of the front arm of the current pose."""
    seg = [g for g in arm_segs(facing, bob, '') if g['front']][0]
    x = int(round(seg['ex'])) + (2 if facing == 'side' else 0)
    return (x, int(round(seg['ey'])) + 1)


def weapon(kind):
    def draw(rc, facing, f, bob, step):
        """The weapon drawn upright in the hand, then turned about the hand by the pose's weapon angle."""
        hx, hy = hand(facing, bob)
        raw = RC()
        render(raw, facing, f, bob, step, hx, hy)
        rc.merge(raw.rotated((hx + 1, hy), POSE['wa']))

    def render(rc, facing, f, bob, step, hx, hy):
        if kind == 'sword':
            rc.rect(hx, hy - 1, 2, 4, WOOD)                    # grip
            rc.rect(hx - 2, hy - 3, 6, 2, METAL)               # guard
            rc.px(hx - 2, hy - 3, METAL, 4)
            rc.rect(hx, hy + 3, 2, 1, METAL, 3)                # pommel
            rc.poly([(hx, hy - 4), (hx + 2, hy - 4), (hx + 2, hy - 15), (hx + 1, hy - 17), (hx, hy - 15)], METAL)
            rc.line(hx, hy - 5, hx, hy - 15, METAL, 4)         # a bright edge
        elif kind == 'staff':
            rc.rect(hx, hy - 16, 2, 20, WOOD)
            for y in (hy - 6, hy):
                rc.rect(hx - 1, y, 4, 1, TRIM, shaded=False)
            rc.poly([(hx + 1, hy - 26), (hx + 4, hy - 22), (hx + 1, hy - 17), (hx - 2, hy - 22)], GEM, 'flat')
            rc.px(hx, hy - 23, WHITE, 4)
            rc.px(hx, hy - 22, GEM, 4)
            rc.px(hx + 2, hy - 20, GEM, 1)
            rc.px(hx - 2, hy - 16, TRIM, 3)
            rc.px(hx + 3, hy - 16, TRIM, 2)
        elif kind == 'bow':
            for i in range(-8, 9):
                bend = int(round((1 - (i / 8.0) ** 2) * 2.0))
                rc.px(hx + 1 + bend, hy - 5 + i, WOOD, 3 if i < 0 else 2)
                if abs(i) > 6:
                    rc.px(hx + bend, hy - 5 + i, WOOD, 1)
            rc.line(hx + 1, hy - 13, hx + 1, hy + 3, WHITE, 2)
            rc.px(hx + 3, hy - 5, TRIM, 4)
            rc.px(hx + 3, hy - 4, TRIM, 2)
        elif kind == 'rod':
            rc.rect(hx, hy - 8, 2, 12, WOOD)
            rc.rect(hx - 1, hy - 1, 4, 1, TRIM, shaded=False)
            rc.ellipse(hx + 1, hy - 11, 3.0, 3.0, GEM)
            rc.px(hx, hy - 12, WHITE, 4)
            rc.px(hx - 3, hy - 11, GEM, 4)
            rc.px(hx + 4, hy - 11, GEM, 1)
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
            d = 1 if facing == 'side' else -1
            if d == 1:
                rc.poly([(hx + 2, hy - 15), (hx + 8, hy - 17), (hx + 9, hy - 9), (hx + 8, hy - 7), (hx + 2, hy - 9)], METAL)
                rc.line(hx + 9, hy - 16, hx + 9, hy - 8, METAL, 4)
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
