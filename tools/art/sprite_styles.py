"""Five proposed art styles for the game's SPRITES (heroes, enemies, equipment, effects), drawn as comparison boards.
Run: python tools/art/sprite_styles.py [soft|chibi|painted|noir|retro]   ->   docs/art/sprites_<n>_<name>.png (x3 upscaled)

Every board shows the same things in one style so the five can be compared: the hero in idle, attack, dodge, cast and stunned frames,
three enemies (slime, skeleton, bat), three pieces of gear, a bolt, an area ring, stun stars and a class card. Heroes are about 15% smaller
than the current 38 px figure. Nothing here changes the game: it is a menu of looks. Once one is picked, the real sprites, animations and
effects are redrawn in it (gen_heroes.py, gen_enemies.py, gen_items.py, gen_vfx.py) and added to check_art.py's rules.

A figure is a skeleton (pelvis, chest, head, two-bone arms and legs) posed by a few numbers and rendered by a style: its proportions, how many
tones it shades with, whether tone changes are dithered, and what its outline is.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pixel import Canvas, hexc, mix

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'docs', 'art')
LIGHT = (-0.55, -0.7)
SHADOW_TINT = (30, 20, 80)
LIGHT_TINT = (255, 240, 205)


# ------------------------------------------------------------------------------------------------ the styles
class Style:
    def __init__(self, key, number, name, blurb, **kw):
        self.key, self.number, self.name, self.blurb = key, number, name, blurb
        self.height = 32        # figure height in px
        self.head = 4.6         # head radius
        self.limb = 2.0         # limb thickness
        self.torso = 7.0        # shoulder width
        self.tones = 5          # shading steps per material
        self.dither = False     # dither between steps
        self.shift = 1.0        # hue shift of shadows (cool) and lights (warm)
        self.outline = 'selout'  # selout | ink | none | rim
        self.backdrop = '1c1838'
        self.sat = 1.0
        self.eyes = 'dots'
        self.rim = None
        self.pal = {}
        self.limit = 0          # >0: at most this many colours per sprite (the retro look)
        self.__dict__.update(kw)


STYLES = {
    'soft': Style('soft', 1, 'Soft Village', 'Natural proportions, five soft tones, hue-shifted shadows, a selective outline. What the game does now, 15% smaller.',
                  height=32, head=4.6, limb=2.0, torso=7.0, tones=5, shift=1.0, outline='selout', backdrop='2a2448',
                  pal=dict(robe='6858b0', hat='5c5a9c', trim='f8d060', skin='f0b090', hair='704830', gem='9cf0d8', slime='5cd070', bat='7a5ab0',
                           bone='e0d8c4', bolt='ff8040', ring='9cf0d8', blade='c8d0e8', helm='a8b4cc', card='a098f0', cardbody='12102a')),
    'chibi': Style('chibi', 2, 'Chunky Chibi', 'A big head on a small body, bold flat colours in three tones, a thick dark outline. Reads at a glance, cute and loud.',
                   height=26, head=6.6, limb=2.4, torso=7.5, tones=3, shift=0.6, outline='ink', backdrop='283a58', sat=1.25, eyes='big',
                   pal=dict(robe='e8405a', hat='f8c030', trim='f8f4ff', skin='ffc8a0', hair='ff8a30', gem='40e0ff', slime='40e060', bat='a850e8',
                            bone='f8f0d8', bolt='ffd030', ring='40e0ff', blade='d8e8ff', helm='c8d0e8', card='ffb030', cardbody='24385a')),
    'painted': Style('painted', 3, 'Lineless Painted', 'No outline at all: shapes are separated by value and by dithered gradients. Muted, earthy and hand-painted.',
                     height=34, head=4.3, limb=2.0, torso=6.6, tones=5, dither=True, shift=1.2, outline='none', backdrop='3a2e34', sat=0.78,
                     pal=dict(robe='8a6a78', hat='5a4a60', trim='c0a060', skin='d8a888', hair='5a4034', gem='88b8a0', slime='7aa070', bat='6a5878',
                              bone='d0c0a0', bolt='d88858', ring='88b8a0', blade='b8b8c0', helm='988878', card='b89060', cardbody='2a2028')),
    'noir': Style('noir', 4, 'Noir Silhouette', 'Tall and lean, near-black bodies with one glowing accent colour and a hard rim light. Silhouette first, drama second.',
                  height=36, head=3.8, limb=1.7, torso=6.0, tones=3, shift=0.9, outline='rim', backdrop='0e0c18', sat=0.6, eyes='glow', rim='9cf0d8',
                  pal=dict(robe='24223a', hat='181624', trim='3a3858', skin='a08898', hair='0c0a14', gem='9cf0d8', slime='2a6a68', bat='2a2040',
                           bone='a8a0b8', bolt='ff4a8a', ring='ff4a8a', blade='8890b0', helm='5a6078', card='3a3858', cardbody='08060e')),
    'retro': Style('retro', 5, 'Retro 16-bit', 'Tiny three-head sprites, four colours each, hard pixel clusters and a one-pixel black outline, like a console RPG.',
                   height=24, head=4.2, limb=1.6, torso=5.4, tones=3, shift=0.5, outline='ink', backdrop='20302c', sat=1.1, eyes='dots', limit=6,
                   pal=dict(robe='3858d8', hat='3858d8', trim='f8d838', skin='f8b078', hair='884820', gem='58f0f0', slime='38c038', bat='9838c8',
                            bone='f0f0d8', bolt='f85838', ring='58f0f0', blade='d0d8f0', helm='a0a8c8', card='c0c0e0', cardbody='181830')),
}


# ------------------------------------------------------------------------------------------------ colour and shading
def ramp(base, style, n=None):
    """n tones of a colour, dark to light: shadows lean cool, lights lean warm by the style's shift."""
    n = n or style.tones
    r, g, b = hexc(base)[:3]
    gray = (r + g + b) / 3.0
    r, g, b = [gray + (v - gray) * style.sat for v in (r, g, b)]
    out = []
    for i in range(n):
        k = i / (n - 1) * 2 - 1
        if k < 0:
            f = 1.0 + k * 0.5
            c = (r * f, g * f, b * f)
            c = tuple(c[j] + (SHADOW_TINT[j] - c[j]) * (-k) * 0.28 * style.shift for j in range(3))
        else:
            c = tuple(v + (255 - v) * k * 0.22 for v in (r, g, b))
            c = tuple(c[j] + (LIGHT_TINT[j] - c[j]) * k * 0.14 * style.shift for j in range(3))
        out.append(tuple(max(0, min(255, int(v))) for v in c) + (255,))
    return out


def pick(tones, lam, x, y, style):
    """The tone for a surface facing `lam` (-1 away from the light .. +1 toward it)."""
    n = len(tones)
    f = (lam + 0.3) / 1.2 * n - 0.5
    if style.dither:
        base = math.floor(f)
        frac = f - base
        idx = base + (1 if frac > (0.25 if (x + y) % 2 else 0.75) else 0)
    else:
        idx = int(round(f))
    return tones[max(0, min(n - 1, idx))]


def ball(cv, cx, cy, rx, ry, tones, style):
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            nx, ny = (x + 0.5 - cx) / max(rx, 0.1), (y + 0.5 - cy) / max(ry, 0.1)
            r2 = nx * nx + ny * ny
            if r2 > 1.0:
                continue
            lam = nx * LIGHT[0] + ny * LIGHT[1] + math.sqrt(1 - r2) * 0.55
            cv.set(x, y, pick(tones, lam, x, y, style))


def capsule(cv, p0, p1, w, tones, style):
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = x1 - x0, y1 - y0
    ln = math.hypot(dx, dy) or 1.0
    ux, uy = dx / ln, dy / ln
    px, py = -uy, ux
    r = w / 2.0
    for y in range(int(min(y0, y1) - r - 1), int(max(y0, y1) + r + 2)):
        for x in range(int(min(x0, x1) - r - 1), int(max(x0, x1) + r + 2)):
            t = ((x + 0.5 - x0) * ux + (y + 0.5 - y0) * uy)
            t = max(0.0, min(ln, t))
            cx, cy = x0 + ux * t, y0 + uy * t
            ox, oy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(ox, oy)
            if d > r:
                continue
            nx, ny = ox / max(r, 0.1), oy / max(r, 0.1)
            lam = nx * LIGHT[0] + ny * LIGHT[1] + math.sqrt(max(0.0, 1 - d * d / (r * r))) * 0.55
            cv.set(x, y, pick(tones, lam, x, y, style))


def shape(cv, pts, tones, style):
    """A filled polygon lit from the left: the pixel's place across its row sets the tone, the top edge catches the light."""
    ys = [p[1] for p in pts]
    n = len(pts)
    cells = {}
    for y in range(int(math.floor(min(ys))), int(math.ceil(max(ys)))):
        xs = []
        for i in range(n):
            (xa, ya), (xb, yb) = pts[i], pts[(i + 1) % n]
            if (ya <= y + 0.5 < yb) or (yb <= y + 0.5 < ya):
                xs.append(xa + (y + 0.5 - ya) * (xb - xa) / (yb - ya))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(int(round(xs[i])), int(round(xs[i + 1]))):
                cells[(x, y)] = None
    rows = {}
    for (x, y) in cells:
        lo, hi = rows.get(y, (x, x))
        rows[y] = (min(lo, x), max(hi, x))
    for (x, y) in cells:
        lo, hi = rows[y]
        frac = (x - lo) / max(hi - lo, 1)
        lam = 0.75 - frac * 1.35
        if (x, y - 1) not in cells:
            lam += 0.35
        if (x, y + 1) not in cells:
            lam -= 0.3
        cv.set(x, y, pick(tones, lam, x, y, style))


def limit_colours(cv, k):
    """Keeps the k most used colours of a sprite (its outline included) and maps every pixel to the nearest of them."""
    counts = {}
    for c in cv.px:
        if c[3] == 255:
            counts[c[:3]] = counts.get(c[:3], 0) + 1
    chosen = []
    for c, _ in sorted(counts.items(), key=lambda kv: -kv[1]):   # most used first, skipping near-duplicates so the few colours stay distinct
        if all(sum((c[i] - d[i]) ** 2 for i in range(3)) > 1800 for d in chosen):
            chosen.append(c)
        if len(chosen) >= k:
            break
    out = Canvas(cv.w, cv.h)
    for i, c in enumerate(cv.px):
        if c[3] == 255:
            best = min(chosen, key=lambda d: sum((c[j] - d[j]) ** 2 for j in range(3)))
            out.px[i] = best + (255,)
        else:
            out.px[i] = c
    return out


def finish(cv, style, rim=None):
    """The style's outline rule (and a rim light for noir), after the figure is drawn. The canvas grows by 2 px each way."""
    out = Canvas(cv.w + 4, cv.h + 4)
    out.blit(cv, 2, 2)
    marks = []
    for y in range(out.h):
        for x in range(out.w):
            if out.get(x, y)[3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = out.get(x + dx, y + dy)
                if n[3]:
                    marks.append((x, y, n))
                    break
    if style.outline in ('selout', 'rim'):
        for x, y, n in marks:
            out.set(x, y, (int(n[0] * 0.3 + 14), int(n[1] * 0.3 + 8), int(n[2] * 0.34 + 40), 255) if style.outline == 'selout'
                    else (int(n[0] * 0.22 + 6), int(n[1] * 0.22 + 4), int(n[2] * 0.3 + 18), 255))
    elif style.outline == 'ink':
        for x, y, n in marks:
            out.set(x, y, (16, 12, 26, 255))
    if style.outline == 'rim' or rim:   # a hard coloured light on the upper-left edges
        col = hexc(rim or style.rim)
        for y in range(out.h):
            for x in range(out.w):
                c = out.get(x, y)
                if c[3] and (not out.get(x - 1, y)[3] or not out.get(x, y - 1)[3]) and sum(c[:3]) > 90:
                    out.set(x, y, mix(c, col, 0.8))
    if style.limit:
        out = limit_colours(out, style.limit)
    return out


# ------------------------------------------------------------------------------------------------ the hero
POSES = {
    'idle0': dict(),
    'idle1': dict(crouch=1, arm_f=8, arm_b=-8),
    'atk0': dict(lean=-2, arm_f=-70, arm_b=20, staff=-60, crouch=1),
    'atk1': dict(lean=3, arm_f=95, arm_b=-30, staff=95, crouch=2, slash=True),
    'atk2': dict(lean=2, arm_f=60, arm_b=-20, staff=70, crouch=1),
    'dodge0': dict(lean=4, crouch=4, arm_f=-50, arm_b=-70, trail=1),
    'dodge1': dict(lean=7, crouch=7, arm_f=-80, arm_b=-90, trail=2, tuck=True),
    'cast0': dict(arm_f=150, arm_b=150, crouch=0, orb=1),
    'cast1': dict(arm_f=172, arm_b=172, crouch=-1, orb=2),
    'stun0': dict(lean=-1, tilt=2, arm_f=15, arm_b=-15, crouch=2, stars=0),
    'stun1': dict(lean=1, tilt=-2, arm_f=-15, arm_b=15, crouch=2, stars=1),
}


def joint(p, length, angle_deg):
    """The end of a limb hanging from p, swung `angle_deg` forward (positive = to the right, 180 = straight up)."""
    a = math.radians(angle_deg)
    return (p[0] + math.sin(a) * length, p[1] + math.cos(a) * length)


def hero(style, pose):
    pz = dict(POSES[pose])
    s = style
    robe, trim, skin, hair = s.pal['robe'], s.pal['trim'], s.pal['skin'], s.pal['hair']
    h = s.height
    cv = Canvas(int(h * 0.8) + 12, h + 10)
    cx = cv.w / 2.0 + pz.get('lean', 0) * 0.4
    base = h + 3
    crouch = pz.get('crouch', 0)
    leg = h * 0.32 - crouch * 0.5
    torso_len = h * 0.27
    pelvis = (cx - pz.get('lean', 0) * 0.3, base - leg)
    chest = (cx + pz.get('lean', 0) * 0.5, pelvis[1] - torso_len)
    head_c = (chest[0] + pz.get('tilt', 0), chest[1] - s.head * 0.9 - 1)
    robe_t, trim_t, skin_t, hair_t = ramp(robe, s), ramp(trim, s), ramp(skin, s), ramp(hair, s)
    boot_t = ramp('3a2840', s)
    staff_t = ramp('8a6040', s)
    gem_t = ramp(s.pal['gem'], s)
    # trail (dodge): faint copies behind the hero
    shoulder_l = (chest[0] - s.torso * 0.5, chest[1] + 1)
    shoulder_r = (chest[0] + s.torso * 0.5, chest[1] + 1)
    arm_len = h * 0.30
    # back arm and the staff
    elbow_b = joint(shoulder_l, arm_len * 0.5, pz.get('arm_b', 0) * 0.8)
    hand_b = joint(elbow_b, arm_len * 0.5, pz.get('arm_b', 0))
    capsule(cv, shoulder_l, elbow_b, s.limb + 0.4, robe_t, s)
    capsule(cv, elbow_b, hand_b, s.limb, skin_t, s)
    # legs and boots (the robe hides most of them)
    for dx in (-1.6, 1.6):
        foot = (pelvis[0] + dx * (1.4 if pz.get('tuck') else 1.0), base)
        capsule(cv, (pelvis[0] + dx * 0.6, pelvis[1]), foot, s.limb + 0.2, boot_t, s)
        ball(cv, foot[0] + (0.8 if dx > 0 else -0.2), base - 0.5, 1.8, 1.0, boot_t, s)
    # the robe: a flared trapezoid from the shoulders to above the boots
    skirt_y = base - 1.5
    shape(cv, [(chest[0] - s.torso * 0.5, chest[1]), (chest[0] + s.torso * 0.5, chest[1]), (pelvis[0] + s.torso * 0.5 + 2.2, skirt_y), (pelvis[0] - s.torso * 0.5 - 2.2, skirt_y)], robe_t, s)
    shape(cv, [(pelvis[0] - s.torso * 0.5 - 2.2, skirt_y - 1.4), (pelvis[0] + s.torso * 0.5 + 2.2, skirt_y - 1.4), (pelvis[0] + s.torso * 0.5 + 2.4, skirt_y + 0.4), (pelvis[0] - s.torso * 0.5 - 2.4, skirt_y + 0.4)], trim_t, s)
    shape(cv, [(pelvis[0] - s.torso * 0.5, pelvis[1] - 1.5), (pelvis[0] + s.torso * 0.5, pelvis[1] - 1.5), (pelvis[0] + s.torso * 0.5, pelvis[1]), (pelvis[0] - s.torso * 0.5, pelvis[1])], trim_t, s)   # a sash
    # head, face, hair and a pointed hat
    ball(cv, head_c[0], head_c[1], s.head, s.head * 1.02, skin_t, s)
    ball(cv, head_c[0], head_c[1] - s.head * 0.35, s.head * 1.05, s.head * 0.8, hair_t, s)
    face_y = head_c[1] + s.head * 0.15
    ew = 1 if s.eyes in ('dots', 'glow') else 2
    for ex in (-s.head * 0.42, s.head * 0.42):
        ec = hexc(s.pal['gem']) if s.eyes == 'glow' else hexc('24182c')
        for yy in range(2 if s.eyes in ('big', 'glow') else 1):
            for xx in range(ew):
                cv.set(int(head_c[0] + ex - ew / 2 + xx + 0.5), int(face_y + yy), ec)
    if s.eyes == 'big':
        cv.set(int(head_c[0] - s.head * 0.42 + 0.5), int(face_y), hexc('f8f4ff'))
        cv.set(int(head_c[0] + s.head * 0.42 + 0.5), int(face_y), hexc('f8f4ff'))
    hat_t = ramp(s.pal['hat'], s)
    shape(cv, [(head_c[0] - s.head * 1.5, head_c[1] - s.head * 0.45), (head_c[0] + s.head * 1.5, head_c[1] - s.head * 0.45), (head_c[0] + s.head * 0.9, head_c[1] - s.head * 0.9), (head_c[0] - s.head * 0.9, head_c[1] - s.head * 0.9)], hat_t, s)
    shape(cv, [(head_c[0] - s.head * 0.9, head_c[1] - s.head * 0.8), (head_c[0] + s.head * 0.9, head_c[1] - s.head * 0.8), (head_c[0] + s.head * 0.5 + pz.get('tilt', 0), head_c[1] - s.head * 2.2), (head_c[0] + s.head * 0.1, head_c[1] - s.head * 2.5)], hat_t, s)
    # front arm and the staff
    elbow_f = joint(shoulder_r, arm_len * 0.5, pz.get('arm_f', 0) * 0.8)
    hand_f = joint(elbow_f, arm_len * 0.5, pz.get('arm_f', 0))
    capsule(cv, shoulder_r, elbow_f, s.limb + 0.4, robe_t, s)
    capsule(cv, elbow_f, hand_f, s.limb, skin_t, s)
    if 'staff' in pz or pose.startswith('idle') or pose.startswith('cast'):
        angle = pz.get('staff', 8)
        top = joint(hand_f, h * 0.5, 180 - angle) if pose.startswith('atk') else (hand_f[0] + 1.5, hand_f[1] - h * 0.5)
        bottom = (hand_f[0] - (top[0] - hand_f[0]) * 0.25, hand_f[1] + h * 0.14)
        if pose.startswith('cast'):
            top = (hand_f[0] + 1, hand_f[1] - h * 0.18)
            bottom = (hand_f[0] + 1, hand_f[1] + h * 0.2)
        capsule(cv, bottom, top, 1.5, staff_t, s)
        ball(cv, top[0], top[1] - 1, 1.9, 1.9, gem_t, s)
    if pz.get('orb'):
        r = 2.6 + pz['orb']
        ball(cv, hand_f[0] - 1, hand_f[1] - r - 2, r, r, ramp(s.pal['gem'], s), s)
    if pz.get('stars') is not None:
        for i in range(3):
            a = (i / 3.0 + pz['stars'] * 0.17) * math.tau
            star(cv, head_c[0] + math.cos(a) * s.head * 1.7, head_c[1] - s.head * 1.9 + math.sin(a) * 2.0, s)
    out = finish(cv, s)
    return out


def star(cv, x, y, style):
    c = hexc('f8d060')
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        cv.set(int(x) + dx, int(y) + dy, c)


def trail(cv, style, copies=2, dx=-5):
    """Afterimages of a dodging hero: faded copies trailing behind."""
    out = Canvas(cv.w + abs(dx) * copies, cv.h)
    for k in range(copies, 0, -1):
        for y in range(cv.h):
            for x in range(cv.w):
                c = cv.get(x, y)
                if c[3]:
                    out.set(x + abs(dx) * copies + dx * k, y, (c[0], c[1], c[2], 70 + 30 * (copies - k)))
    out.blit(cv, abs(dx) * copies, 0)
    return out


# ------------------------------------------------------------------------------------------------ enemies, gear, effects
def slime(style, squash=0):
    s = style
    base = s.pal['slime']
    cv = Canvas(int(s.height * 0.6) + 8, int(s.height * 0.42) + 8)
    t = ramp(base, s)
    w, h = s.height * 0.26 + squash, s.height * 0.17 - squash * 0.6
    cx, cy = cv.w / 2.0, cv.h - 3 - h
    ball(cv, cx, cy, w, h, t, s)
    ball(cv, cx - w * 0.35, cy - h * 0.45, w * 0.22, h * 0.2, [t[-1], t[-1]], s) if s.tones > 3 else cv.set(int(cx - w * 0.4), int(cy - h * 0.4), t[-1])
    ec = hexc('24182c')
    for ex in (-w * 0.35, w * 0.35):
        cv.set(int(cx + ex), int(cy), ec)
        cv.set(int(cx + ex), int(cy + 1), ec)
    return finish(cv, s)


def skeleton(style, swing=0):
    s = style
    cv = Canvas(int(s.height * 0.8) + 10, s.height + 8)
    bone = ramp(s.pal['bone'], s)
    dark = ramp('2a2038', s)
    base = s.height + 3
    cx = cv.w / 2.0
    leg = s.height * 0.32
    pelvis = (cx, base - leg)
    chest = (cx, pelvis[1] - s.height * 0.27)
    head_c = (cx, chest[1] - s.head * 0.9 - 1)
    for dx in (-1.6, 1.6):
        capsule(cv, (cx + dx * 0.5, pelvis[1]), (cx + dx + swing * (0.6 if dx > 0 else -0.6), base), s.limb, bone, s)
    ball(cv, cx, chest[1] + s.height * 0.12, s.torso * 0.5, s.height * 0.16, dark, s)
    for i in range(3):
        y = chest[1] + 2 + i * 2.4
        capsule(cv, (cx - s.torso * 0.45, y), (cx + s.torso * 0.45, y), 1.2, bone, s)
    capsule(cv, (cx, chest[1]), (cx, pelvis[1]), 1.2, bone, s)
    for sx in (-1, 1):
        capsule(cv, (cx + sx * s.torso * 0.5, chest[1] + 1), (cx + sx * (s.torso * 0.65 + swing * 0.3), chest[1] + s.height * 0.26), s.limb * 0.8, bone, s)
    ball(cv, head_c[0], head_c[1], s.head, s.head * 1.02, bone, s)
    for ex in (-s.head * 0.42, s.head * 0.42):
        cv.set(int(head_c[0] + ex + 0.5), int(head_c[1]), hexc('24182c'))
        cv.set(int(head_c[0] + ex + 0.5), int(head_c[1] + 1), hexc('24182c'))
    return finish(cv, s)


def bat(style, flap=0):
    s = style
    cv = Canvas(int(s.height * 0.8) + 8, int(s.height * 0.5) + 8)
    t = ramp(s.pal['bat'], s)
    cx, cy = cv.w / 2.0, cv.h / 2.0
    wing = 4 + flap * 2
    for sx in (-1, 1):
        shape(cv, [(cx + sx * 1.5, cy - 1), (cx + sx * (s.height * 0.32), cy - wing), (cx + sx * (s.height * 0.3), cy + 1 + flap), (cx + sx * (s.height * 0.16), cy + 2), (cx + sx * 1.5, cy + 3)] if sx > 0 else
              [(cx + sx * (s.height * 0.3), cy + 1 + flap), (cx + sx * (s.height * 0.32), cy - wing), (cx + sx * 1.5, cy - 1), (cx + sx * 1.5, cy + 3), (cx + sx * (s.height * 0.16), cy + 2)], t, s)
    ball(cv, cx, cy + 1, 2.6, 3.0, t, s)
    for ex in (-1, 1):
        cv.set(int(cx + ex), int(cy), hexc('ff6a60'))
    shape(cv, [(cx - 2.5, cy - 2), (cx - 1.5, cy - 4.5), (cx - 0.5, cy - 2)], t, s)
    shape(cv, [(cx + 0.5, cy - 2), (cx + 1.5, cy - 4.5), (cx + 2.5, cy - 2)], t, s)
    return finish(cv, s)


def sword(style):
    s = style
    cv = Canvas(16, 16)
    blade, wood, gold = ramp(s.pal['blade'], s), ramp('8a6040', s), ramp('d8a838', s)
    capsule(cv, (4, 11), (12, 3), 2.4, blade, s)
    capsule(cv, (4, 8), (8, 12), 1.6, gold, s)
    capsule(cv, (4, 11), (2, 13), 1.8, wood, s)
    return finish(cv, s)


def robe_icon(style):
    s = style
    cv = Canvas(16, 16)
    t, tr = ramp(s.pal['robe'], s), ramp(s.pal['trim'], s)
    shape(cv, [(3, 2), (6, 1), (9, 1), (12, 2), (14, 9), (12, 10), (12, 14), (3, 14), (3, 10), (1, 9)], t, s)
    shape(cv, [(3, 12), (12, 12), (12, 14), (3, 14)], tr, s)
    shape(cv, [(3, 7), (12, 7), (12, 8), (3, 8)], tr, s)
    return finish(cv, s)


def helm_icon(style):
    s = style
    cv = Canvas(16, 16)
    t, tr = ramp(s.pal['helm'], s), ramp('d8a838', s)
    shape(cv, [(2, 13), (1, 7), (3, 3), (6, 1), (9, 1), (12, 3), (14, 7), (13, 13), (10, 13), (10, 9), (5, 9), (5, 13)], t, s)
    shape(cv, [(4, 6), (11, 6), (11, 8), (4, 8)], ramp('1a1024', s), s)
    shape(cv, [(7, 1), (9, 1), (9, 5), (7, 5)], tr, s)
    return finish(cv, s)


def bolt(style, frame=0):
    s = style
    cv = Canvas(24, 12)
    core = ramp(s.pal['bolt'], s)
    for i in range(7):
        r = 0.8 + i * 0.28 + (0.3 if frame == 1 else 0)
        ball(cv, 3 + i * 1.6, 6, r, r, core, s)
    ball(cv, 16, 6, 3.3 + frame * 0.3, 3.3 + frame * 0.3, core, s)
    cv.set(15, 5, hexc('fff0d0'))
    cv.set(16, 5, hexc('fff0d0'))
    out = finish(cv, s) if s.outline in ('ink',) else cv
    return out


def ring(style, frame=0):
    s = style
    cv = Canvas(34, 34)
    c = hexc(s.pal['ring'])
    r = 8 + frame * 3.5
    for k in range(80):
        a = k / 80 * math.tau
        x, y = 17 + math.cos(a) * r, 17 + math.sin(a) * r * 0.9
        cv.set(int(x), int(y), c if (k // 2) % 2 == 0 or s.key != 'retro' else hexc('20605a'))
        if s.key in ('soft', 'painted', 'noir'):
            cv.set(int(17 + math.cos(a) * (r - 1.5)), int(17 + math.sin(a) * (r - 1.5) * 0.9), (c[0], c[1], c[2], 90))
    for k in range(6):
        a = k / 6 * math.tau + frame * 0.4
        cv.set(int(17 + math.cos(a) * (r * 0.6)), int(17 + math.sin(a) * (r * 0.6) * 0.9), hexc('f0fffa'))
    return cv


def stars(style, frame=0):
    cv = Canvas(22, 10)
    for i in range(3):
        a = (i / 3.0 + frame * 0.17) * math.tau
        star(cv, 11 + math.cos(a) * 7, 5 + math.sin(a) * 2.5, style)
    return cv


def card(style, hero_cv):
    s = style
    cv = Canvas(48, 60)
    frame = ramp(s.pal['card'], s, 3)
    body = ramp(s.pal['cardbody'], s, 3)
    for y in range(60):
        for x in range(48):
            edge = min(x, y, 47 - x, 59 - y)
            cv.set(x, y, frame[2] if edge == 0 else (frame[0] if edge == 1 and s.outline != 'none' else body[1]))
    for y in range(36, 60):                       # the lower half is a darker text well
        for x in range(2, 46):
            if y < 58:
                cv.set(x, y, body[0])
    cv.blit(hero_cv, (48 - hero_cv.w) // 2, 3)
    for y, w in ((45, 30), (50, 22)):             # two lines of text
        for x in range(24 - w // 2, 24 + w // 2):
            cv.set(x, y, frame[1])
    return cv


# ------------------------------------------------------------------------------------------------ micro font and board
FONT = {
    'A': '010101111101101', 'B': '110101110101110', 'C': '011100100100011', 'D': '110101101101110', 'E': '111100110100111',
    'F': '111100110100100', 'G': '011100101101011', 'H': '101101111101101', 'I': '111010010010111', 'J': '001001001101010',
    'K': '101101110101101', 'L': '100100100100111', 'M': '101111111101101', 'N': '110101101101101', 'O': '010101101101010',
    'P': '110101110100100', 'Q': '010101101111011', 'R': '110101110101101', 'S': '011100010001110', 'T': '111010010010010',
    'U': '101101101101111', 'V': '101101101101010', 'W': '101101111111101', 'X': '101101010101101', 'Y': '101101010010010',
    'Z': '111001010100111', ' ': '000000000000000', '-': '000000111000000', '1': '010110010010111', '2': '110001010100111',
    '3': '110001010001110', '4': '101101111001001', '5': '111100110001110', '6': '011100110101010', '7': '111001010010010',
    '8': '010101010101010', '9': '010101011001110', '0': '010101101101010',
}


def text(cv, x, y, msg, colour):
    for ch in msg.upper():
        g = FONT.get(ch, FONT[' '])
        for i, bit in enumerate(g):
            if bit == '1':
                cv.set(x + i % 3, y + i // 3, colour)
        x += 4


def board(style):
    s = style
    W, H = 400, 250
    cv = Canvas(W, H, hexc(s.backdrop))
    for y in range(H):  # a soft vignette so the sprites sit on a floor
        for x in range(W):
            if y > 170:
                c = cv.get(x, y)
                cv.set(x, y, mix(c, hexc('0a0814'), min(0.35, (y - 170) / 200.0)))
    label = hexc('d8d0ff')
    dim = hexc('8c88b8')
    text(cv, 6, 5, '%d %s' % (s.number, s.name), hexc('f8d060'))
    # hero animation rows
    rows = [('IDLE', ['idle0', 'idle1']), ('ATTACK', ['atk0', 'atk1', 'atk2']), ('DODGE', ['dodge0', 'dodge1']), ('CAST', ['cast0', 'cast1']), ('STUN', ['stun0', 'stun1'])]
    x = 6
    for name, poses in rows:
        text(cv, x, 16, name, dim)
        px = x
        for pose in poses:
            cvp = hero(s, pose)
            if pose.startswith('dodge'):
                cvp = trail(cvp, s, copies=pose == 'dodge1' and 2 or 1)
            cv.blit(cvp, px, 24 + (46 - cvp.h))
            px += int(cvp.w * 0.74)
        x = px + 10
    # enemies
    text(cv, 6, 82, 'ENEMIES', dim)
    ex = 8
    for sprite in (slime(s, 0), slime(s, 1.2), skeleton(s, 0), skeleton(s, 1.5), bat(s, 0), bat(s, 1)):
        cv.blit(sprite, ex, 140 - sprite.h)
        ex += sprite.w + 4
    # gear
    text(cv, 262, 82, 'GEAR', dim)
    gx = 262
    for icon in (sword(s), robe_icon(s), helm_icon(s)):
        cv.blit(icon, gx, 92)
        gx += 22
    # effects
    text(cv, 6, 150, 'BOLT', dim)
    cv.blit(bolt(s, 0), 6, 160)
    cv.blit(bolt(s, 1), 34, 160)
    text(cv, 70, 150, 'AREA', dim)
    for i in range(3):
        cv.blit(ring(s, i), 70 + i * 34, 160)
    text(cv, 176, 150, 'STUN', dim)
    cv.blit(stars(s, 0), 176, 170)
    cv.blit(stars(s, 1), 202, 170)
    # class card
    text(cv, 262, 150, 'CARD', dim)
    cv.blit(card(s, hero(s, 'idle0')), 262, 160)
    cv.blit(card(s, hero(s, 'cast1')), 316, 160)
    # palette strip of the style's tones
    text(cv, 6, 205, 'TONES', dim)
    for i, base in enumerate([s.pal[k] for k in ('robe', 'trim', 'skin', 'slime', 'bolt', 'gem')]):
        for j, c in enumerate(ramp(base, s)):
            for yy in range(6):
                for xx in range(4):
                    cv.set(6 + i * 20 + j * 4 + xx, 215 + yy, c)
    return cv


def scaled(cv, k):
    out = Canvas(cv.w * k, cv.h * k)
    for y in range(cv.h):
        for x in range(cv.w):
            c = cv.px[y * cv.w + x]
            for j in range(k):
                for i in range(k):
                    out.px[(y * k + j) * out.w + x * k + i] = c
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    keys = sys.argv[1:] or list(STYLES)
    for key in keys:
        s = STYLES[key]
        path = os.path.join(OUT, 'sprites_%d_%s.png' % (s.number, key))
        scaled(board(s), 3).save(path)
        print(path)


if __name__ == '__main__':
    main()
