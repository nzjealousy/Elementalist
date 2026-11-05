"""Characters, monsters, bosses and props -> elementalist/assets/sprites/. Run: python tools/art/gen_sprites.py

Every creature is drawn procedurally from shaded shapes (top-left light, 1px dark outline) so the whole
cast shares one look. For each id the generator writes:
    <id>.png          the idle frame (what code asks AssetDB for)
    <id>_strip.png    the animation frames side by side (AssetDB.get_frames slices them)
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pixel import *  # noqa: F401,F403
import restyle  # noqa: E402
import style  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'sprites')
os.makedirs(OUT, exist_ok=True)
FRAMES = 4
WAVE = [0, 1, 0, -1]  # idle breathing phase per frame


def save(name, frames, moonlit=True):
    """frames: list of Canvas, all the same size. Pictures are snapped onto the Moonlit Glyphwork ramps (restyle.py);
    `moonlit=False` keeps a white picture white, for the ones code tints (pickups)."""
    if moonlit:   # soft outline: the drawing's own deep shade of each colour, snapped to the ramps (the lit rim is added by volumize)
        frames = [restyle.restyle(f, rim=False, outline=False) for f in frames]
    frames[0].save(os.path.join(OUT, name + '.png'))
    if len(frames) > 1:
        sheet(frames, os.path.join(OUT, name + '_strip.png'))


def unify(frames):
    w = max(f.w for f in frames)
    h = max(f.h for f in frames)
    return [fit(f, w, h) for f in frames]


# ------------------------------------------------------------------------------------------- hero
HERO_FRONT = ["..hhhhhh..", ".hhhhhhhh.", ".hhsssshh.", ".hsessesh.", "..ssssss..", "..rrttrr..", ".rrrrrrrr.",
              ".rRrrrrRr.", "srRrkkrRrs", ".rRrrrrRr.", "..rRrrRr..", "..rrrrrr..", "..bb..bb..", "..bb..bb.."]
HERO_BACK = ["..hhhhhh..", ".hhhhhhhh.", ".hhhhhhhh.", ".hhhhhhhh.", "..hhhhhh..", "..rrrrrr..", ".rrrttrrr.",
             ".rRrttrRr.", "srRrttrRrs", ".rRrttrRr.", "..rRrrRr..", "..rrrrrr..", "..bb..bb..", "..bb..bb.."]
HERO_SIDE = ["...hhhhh..", "..hhhhhhh.", "..hhhssss.", "..hhsesss.", "...hssss..", "...rrttr..", "..rrrrrrr.",
             "..rRrrrRr.", "..rRkkrRs.", "..rRrrrRr.", "...rrrrr..", "...rrrrr..", "...bb.bb..", "...bb.bb.."]
LEGS = {  # facing -> (stepA rows 12-13, stepB rows 12-13)
    'down': (["..bb..bb..", "..b...bb.."], ["..bb..bb..", "..bb...b.."]),
    'up': (["..bb..bb..", "..b...bb.."], ["..bb..bb..", "..bb...b.."]),
    'side': (["...bb.bb..", "..bb...b.."], ["...bb.bb..", "...b..bb.."]),
}

CLASS_PALETTES = {
    'wanderer': ('8a8f9c', 'c9a35a', '6b4a2a'), 'channeler': ('e0653a', 'ffd84a', '3a2a20'),
    'vanguard': ('4a6fb0', 'd9dde8', '8a5a2a'), 'ranger': ('4f8f4a', '8a6a3a', '2f2f2f'),
    'mystic': ('7a4fb5', 'f2cf6a', 'c9c9e8'), 'assassin': ('2e2e3a', 'b03a3a', '1a1a1a'),
    'berserker': ('9a3a2a', '5a3a22', 'c0632a'), 'sage': ('e8e0c0', '4a8ad0', 'a8a8a8'),
    'druid': ('5a7a3a', 'a8d070', '6a4a2a'),
}


def hero(facing, frame, pal):
    robe, trim, hair = (hexc(c) for c in pal)
    rows = list({'down': HERO_FRONT, 'up': HERO_BACK, 'side': HERO_SIDE}[facing])
    if frame in (1, 3):
        rows[12], rows[13] = LEGS[facing][0 if frame == 1 else 1]
    colors = {'h': hair, 's': hexc('f0c8a0'), 'S': hexc('c89870'), 'r': robe, 'R': shade(robe, 0.7), 't': trim,
              'k': hexc('5a3a22'), 'b': hexc('3a2a20'), 'e': hexc('2a1a20')}
    body = from_ascii(rows, colors)
    # a little shade on the robe's lit side and the hair
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == 'r' and x <= 2 and y > 5:
                body.set(x, y, shade(robe, 1.2))
            if ch == 'h' and y == 0:
                body.set(x, y, shade(hair, 1.3))
    cv = Canvas(10, 15)
    cv.blit(body, 0, 1 if frame in (1, 3) else 1)  # bob: stepping frames sit one pixel higher
    if frame in (1, 3):
        cv = Canvas(10, 15)
        cv.blit(body, 0, 0)
    return finish(cv)


def make_heroes():
    for cls, pal in CLASS_PALETTES.items():
        for facing in ('down', 'up', 'side'):
            save('player_%s_%s' % (cls, facing), unify([hero(facing, f, pal) for f in range(FRAMES)]))
    # the generic fallbacks the code asks for first
    for facing in ('down', 'up', 'side'):
        save('player_%s' % facing, unify([hero(facing, f, CLASS_PALETTES['wanderer']) for f in range(FRAMES)]))
    save('player', unify([hero('down', f, CLASS_PALETTES['wanderer']) for f in range(FRAMES)]))


# ---------------------------------------------------------------------------------------- monsters
def eye_pair(cv, cx, y, gap, white=True, color=None):
    c = (255, 255, 255, 255) if white else color
    for sx in (cx - gap, cx + gap):
        cv.set(sx, y, c)
        cv.set(sx, y + 1, c)
        if white:
            cv.set(sx + (1 if sx > cx else -1) * 0, y + 1, (20, 14, 28, 255))


def slime(ph, base='5fcf5f', w=14, h=11, crown=False, eye_scale=1):
    cv = Canvas(w, h)
    sq = WAVE[ph]
    ry = h * 0.42 + sq * 0.7
    rx = w * 0.46 - sq * 0.7
    cx = (w - 1) / 2
    cy = h - 1 - ry + 0.6
    shaded_ellipse(cv, cx, cy, rx, ry, hexc(base))
    for x in range(w):  # flat bottom
        for y in range(h - 1, h):
            pass
    ey = int(cy - ry * 0.15)
    gap = max(2, int(w * 0.18))
    for sx in (int(cx) - gap, int(cx) + gap):
        for k in range(eye_scale + 1):
            cv.set(sx, ey + k, (255, 255, 255, 255))
            cv.set(sx + 1, ey + k, (255, 255, 255, 255))
        cv.set(sx + 1, ey + eye_scale, (20, 14, 28, 255))
    my = ey + eye_scale + 2
    for x in range(int(cx) - 1, int(cx) + 2):
        cv.set(x, my, shade(hexc(base), 0.4))
    cv.set(int(cx) - gap - 1, int(cy - ry * 0.55), (255, 255, 255, 220))
    if crown:
        gold = hexc('f2cf6a')
        top = int(cy - ry) - 1
        for i, dx in enumerate((-5, -2, 1, 4)):
            line(cv, int(cx) + dx, top + 2, int(cx) + dx, top - 1, gold)
            cv.set(int(cx) + dx, top - 2, hexc('ff6a4a'))
        rect(cv, int(cx) - 6, top + 2, 13, 2, gold)
        rect(cv, int(cx) - 6, top + 3, 13, 1, shade(gold, 0.7))
    return cv


def bat(ph):
    cv = Canvas(14, 9)
    flap = [-3, -1, 2, 0][ph]
    body = hexc('8b5fbf')
    for sgn in (-1, 1):
        tip = (7 + sgn * 6, 4 + flap)
        poly(cv, [(7 + sgn * 1, 3), (tip[0], tip[1]), (7 + sgn * 4, 7), (7 + sgn * 1, 6)], shade(body, 0.8))
        line(cv, 7 + sgn * 1, 3, tip[0], tip[1], shade(body, 1.3))
    shaded_ellipse(cv, 6.5, 4.5, 2.2, 2.4, body)
    cv.set(5, 2, hexc('c9a0ff')); cv.set(8, 2, hexc('c9a0ff'))  # ears
    cv.set(5, 4, hexc('ff5a5a')); cv.set(8, 4, hexc('ff5a5a'))
    return cv


def skeleton(ph, bone='e8e4d0', bow=True, cape=None, rapier=False, w=12, h=16):
    cv = Canvas(w, h)
    b = hexc(bone)
    dark = hexc('2a2430')
    sway = WAVE[ph]
    cx = w // 2
    if cape:
        poly(cv, [(cx - 3, 6), (cx + 3, 6), (cx + 4 + sway, h - 2), (cx - 4 + sway, h - 2)], hexc(cape))
    shaded_ellipse(cv, cx, 3.2, 3.1, 3.0, b)
    cv.set(cx - 1, 3, dark); cv.set(cx + 1, 3, dark); cv.set(cx, 5, dark)
    cv.set(cx - 1, 3, hexc('ff5a5a')) if rapier else None
    for i, y in enumerate(range(7, 11)):  # ribs
        rect(cv, cx - 2, y, 5, 1, b if i % 2 == 0 else shade(b, 0.55))
    line(cv, cx, 6, cx, 11, shade(b, 0.8))
    line(cv, cx - 1, 11, cx - 2, h - 1, b); line(cv, cx + 1, 11, cx + 2 + (sway > 0), h - 1, b)
    line(cv, cx - 3, 7, cx - 4, 10 + sway, shade(b, 0.85)); line(cv, cx + 3, 7, cx + 4, 10 - sway, shade(b, 0.85))
    if bow:
        wood = hexc('8a5a2a')
        for y in range(4, 13):
            x = cx + 5 + int(round(1.6 * math.sin((y - 4) / 8 * math.pi)))
            cv.set(x, y, wood)
        line(cv, cx + 5, 4, cx + 5, 12, hexc('d8d0b0'))
    if rapier:
        line(cv, cx + 4, 10 - sway, cx + 9, 5 + sway, hexc('c8d0e0'))
        cv.set(cx + 4, 10 - sway, hexc('f2cf6a'))
    return cv


def wisp(ph):
    cv = Canvas(10, 12)
    core = hexc('7fe8ff')
    f = [0, 1, 2, 1][ph]
    for i, (dy, r) in enumerate([(7 + f, 1.4), (9 + f, 0.9)]):
        ellipse(cv, 5, dy, r + 0.6, r + 1.0, shade(core, 0.6))
    shaded_ellipse(cv, 5, 4.2, 3.2, 3.4, core)
    ellipse(cv, 4, 3, 1.0, 1.0, (255, 255, 255, 255))
    cv.set(4, 4, hexc('1a3a5a')); cv.set(7, 4, hexc('1a3a5a'))
    return cv


def brute(ph, w=22, h=22, base='8a8f9c'):
    cv = Canvas(w, h)
    sway = WAVE[ph]
    stone = hexc(base)
    cx = w // 2
    shaded_ellipse(cv, cx, h - 8, 7.5, 7.0, stone)
    shaded_ellipse(cv, cx, 5, 4.2, 4.0, shade(stone, 1.08))
    cv.set(cx - 2, 5, hexc('ff8a3a')); cv.set(cx + 2, 5, hexc('ff8a3a'))
    for sgn in (-1, 1):  # fists
        shaded_ellipse(cv, cx + sgn * 9, h - 9 + (sway if sgn > 0 else -sway), 3.0, 3.4, shade(stone, 0.95))
    for p in [(cx - 3, h - 11), (cx + 4, h - 7), (cx, h - 5)]:  # cracks and moss
        line(cv, p[0], p[1], p[0] + 2, p[1] + 2, shade(stone, 0.45))
    for p in [(cx - 5, h - 12), (cx + 5, h - 13), (cx - 2, 2)]:
        cv.set(p[0], p[1], hexc('6a9a4a'))
    shaded_rect(cv, cx - 5, h - 3, 4, 3, shade(stone, 0.8)); shaded_rect(cv, cx + 1, h - 3, 4, 3, shade(stone, 0.8))
    return cv


def spitter(ph):
    cv = Canvas(13, 12)
    base = hexc('a7c94f')
    sq = WAVE[ph]
    shaded_ellipse(cv, 6, 7.5, 5.6 - sq * 0.4, 3.8 + sq * 0.4, base)
    for sx in (3, 9):  # eye stalks
        line(cv, sx, 4, sx, 2, shade(base, 0.8))
        ellipse(cv, sx, 2, 1.3, 1.3, (255, 255, 240, 255))
        cv.set(sx, 2, (20, 14, 28, 255))
    mouth = hexc('d0508a')
    rect(cv, 4, 8, 5, 2, shade(mouth, 0.5))
    rect(cv, 5, 9, 3, 1, mouth)
    if ph in (1, 2):
        cv.set(6, 10, hexc('d8ff6a')); cv.set(6, 11, hexc('b0e050'))
    for p in [(3, 6), (9, 6), (7, 9)]:
        cv.set(p[0], p[1], shade(base, 0.7))
    return cv


def imp(ph):
    cv = Canvas(13, 15)
    red = hexc('e0553a')
    wag = WAVE[ph]
    line(cv, 8, 11, 11, 9 + wag, shade(red, 0.7)); cv.set(12, 8 + wag, hexc('ffd84a'))
    for sgn in (-1, 1):
        poly(cv, [(6 + sgn * 2, 7), (6 + sgn * 6, 4 - wag), (6 + sgn * 4, 10)], hexc('7a2030'))
    shaded_ellipse(cv, 6, 10, 3.2, 3.6, red)
    shaded_ellipse(cv, 6, 5, 3.4, 3.0, shade(red, 1.05))
    for sgn in (-1, 1):  # horns
        poly(cv, [(6 + sgn * 2, 3), (6 + sgn * 3, 0), (6 + sgn * 4, 3)], hexc('f0e0c0'))
    cv.set(5, 5, hexc('ffe84a')); cv.set(7, 5, hexc('ffe84a'))
    rect(cv, 5, 7, 3, 1, hexc('3a0a10'))
    rect(cv, 4, 13, 2, 2, shade(red, 0.6)); rect(cv, 7, 13, 2, 2, shade(red, 0.6))
    return cv


def wraith(ph):
    cv = Canvas(13, 17)
    robe = hexc('b9a8ff')
    w = [0, 1, 0, -1][ph]
    pts = [(6, 1), (10, 5), (11 + w, 15), (9, 13 - w), (6, 16), (4, 13 + w), (1 - w, 15), (2, 5)]
    poly(cv, pts, shade(robe, 0.85))
    shaded_ellipse(cv, 6, 5, 3.6, 3.8, robe)
    ellipse(cv, 6, 5.5, 2.2, 2.4, hexc('1a1030'))
    cv.set(5, 5, hexc('9aefff')); cv.set(7, 5, hexc('9aefff'))
    for x in range(3, 10):
        cv.set(x, 9, shade(robe, 0.6))
    return cv


def duelist(ph):
    return skeleton(ph, bone='d8c9a0', bow=False, cape='7a2a30', rapier=True, w=14, h=17)


def slime_king(ph):
    return slime(ph, base='4fbf4f', w=32, h=26, crown=True, eye_scale=2)


def colossus(ph):
    w, h = 32, 34
    cv = Canvas(w, h)
    stone = hexc('a1a6b4')
    sway = WAVE[ph]
    cx = w // 2
    shaded_ellipse(cv, cx, 21, 12, 10, stone)
    shaded_ellipse(cv, cx, 8, 6.5, 6, shade(stone, 1.1))
    glow = hexc('6adfff')
    for sx in (cx - 3, cx + 2):
        rect(cv, sx, 8, 2, 2, glow)
    for sgn in (-1, 1):
        shaded_ellipse(cv, cx + sgn * 14, 22 + (sway if sgn > 0 else -sway), 4.2, 6.0, shade(stone, 0.95))
    line(cv, cx - 4, 17, cx + 4, 17, glow); line(cv, cx, 15, cx, 21, glow)  # rune
    line(cv, cx - 6, 24, cx - 3, 28, shade(stone, 0.4)); line(cv, cx + 5, 22, cx + 8, 27, shade(stone, 0.4))
    shaded_rect(cv, cx - 8, h - 5, 7, 5, shade(stone, 0.8)); shaded_rect(cv, cx + 1, h - 5, 7, 5, shade(stone, 0.8))
    for p in [(cx - 9, 16), (cx + 8, 14), (cx + 3, 3)]:
        cv.set(p[0], p[1], hexc('6a9a4a'))
    return cv


def warden(ph):
    w, h = 20, 24
    cv = Canvas(w, h)
    steel = hexc('9ab0a0')
    sway = WAVE[ph]
    cx = w // 2
    shaded_rect(cv, cx - 5, 9, 10, 9, steel)
    shaded_ellipse(cv, cx, 6, 4.2, 4.2, shade(steel, 1.1))
    rect(cv, cx - 3, 6, 6, 1, hexc('1a2a20')); rect(cv, cx - 2, 6, 1, 1, hexc('7fff9a')); rect(cv, cx + 1, 6, 1, 1, hexc('7fff9a'))
    shaded_ellipse(cv, cx - 7, 13, 3.2, 4.6, hexc('3a6fb0'))  # shield
    cv.set(cx - 7, 12, hexc('f2cf6a')); cv.set(cx - 7, 13, hexc('f2cf6a')); cv.set(cx - 7, 14, hexc('f2cf6a'))
    line(cv, cx + 7, 16 + sway, cx + 7, 3 + sway, hexc('d8e0f0'), 1)  # sword
    rect(cv, cx + 5, 16 + sway, 5, 1, hexc('f2cf6a'))
    shaded_rect(cv, cx - 4, 18, 3, 6, shade(steel, 0.8)); shaded_rect(cv, cx + 1, 18, 3, 6, shade(steel, 0.8))
    poly(cv, [(cx - 5, 9), (cx + 5, 9), (cx + 4, 11), (cx - 4, 11)], hexc('5a1a20'))
    return cv


def matron(ph):
    w, h = 18, 24
    cv = Canvas(w, h)
    red = hexc('e0663a')
    f = [0, 1, 2, 1][ph]
    cx = w // 2
    poly(cv, [(cx - 2, 9), (cx + 2, 9), (cx + 7, 22), (cx - 7, 22)], shade(red, 0.9))
    shaded_ellipse(cv, cx, 15, 4.5, 6, red)
    shaded_ellipse(cv, cx, 7, 3.4, 3.4, hexc('f0c8a0'))
    for i, dx in enumerate((-3, -1, 1, 3)):  # flame hair
        line(cv, cx + dx, 5, cx + dx + (i % 2) - 1, 0 + (f if i % 2 else 2 - f), hexc('ffb030' if i % 2 else 'ff6a1a'), 1)
    cv.set(cx - 1, 7, hexc('3a1a10')); cv.set(cx + 1, 7, hexc('3a1a10'))
    for sgn in (-1, 1):  # raised hands with embers
        line(cv, cx + sgn * 4, 12, cx + sgn * 7, 8 - f, hexc('f0c8a0'))
        ellipse(cv, cx + sgn * 7, 7 - f, 1.3, 1.3, hexc('ffd84a'))
    poly(cv, [(cx - 5, 20), (cx + 5, 20), (cx + 4, 22), (cx - 4, 22)], hexc('f2cf6a'))
    return cv


def hulk(ph):
    w, h = 24, 24
    cv = Canvas(w, h)
    moss = hexc('6a8a4a')
    sway = WAVE[ph]
    cx = w // 2
    shaded_ellipse(cv, cx, 14, 10.5, 8.5, moss)
    shaded_ellipse(cv, cx, 6, 4.0, 3.6, shade(moss, 1.1))
    cv.set(cx - 2, 6, hexc('ffe84a')); cv.set(cx + 2, 6, hexc('ffe84a'))
    for sgn in (-1, 1):
        shaded_ellipse(cv, cx + sgn * 11, 16 + (sway if sgn > 0 else -sway), 3.4, 5.0, shade(moss, 0.9))
        for k, (mx, my) in enumerate([(cx + sgn * 6, 8), (cx + sgn * 8, 10)]):  # shoulder mushrooms
            ellipse(cv, mx, my, 2.0 - k * 0.5, 1.4, hexc('d05a5a'))
            cv.set(mx, my - 1, (255, 255, 255, 255))
    for p in [(cx - 4, 12), (cx + 3, 17), (cx - 1, 20), (cx + 6, 12)]:
        cv.set(p[0], p[1], hexc('3a5a2a')); cv.set(p[0] + 1, p[1], hexc('3a5a2a'))
    shaded_rect(cv, cx - 6, h - 4, 5, 4, shade(moss, 0.8)); shaded_rect(cv, cx + 1, h - 4, 5, 4, shade(moss, 0.8))
    return cv


def lich(ph):
    w, h = 34, 34
    cv = Canvas(w, h)
    robe = hexc('7a5ac8')
    f = [0, 1, 0, -1][ph]
    cx = 14
    aura = hexc('b58af0')
    for r, a in [(13, 40), (10, 70)]:
        ellipse(cv, cx, 18, r, r + 2, (aura[0], aura[1], aura[2], a))
    poly(cv, [(cx - 5, 12), (cx + 5, 12), (cx + 10 + f, 32), (cx + 4, 29 - f), (cx, 33), (cx - 4, 29 + f), (cx - 10 - f, 32)], shade(robe, 0.8))
    shaded_ellipse(cv, cx, 20, 6.5, 8, robe)
    shaded_ellipse(cv, cx, 8, 3.6, 3.8, hexc('e8e4d0'))
    cv.set(cx - 2, 8, hexc('7fff9a')); cv.set(cx + 2, 8, hexc('7fff9a')); cv.set(cx, 10, hexc('2a2430'))
    for sgn in (-1, 1):  # horned crown
        poly(cv, [(cx + sgn * 2, 5), (cx + sgn * 6, 0 - f), (cx + sgn * 4, 6)], hexc('f2cf6a'))
    rect(cv, cx - 3, 4, 7, 1, hexc('f2cf6a'))
    line(cv, cx + 8, 12, cx + 12, 22 + f, hexc('d8c9a0'))  # staff
    ellipse(cv, cx + 12, 10 + f, 2.4, 2.4, hexc('7fff9a'))
    ellipse(cv, cx + 12, 10 + f, 1.0, 1.0, (255, 255, 255, 255))
    for sgn in (-1, 1):
        line(cv, cx + sgn * 6, 16, cx + sgn * 9, 14 + f * sgn, hexc('e8e4d0'))
    return cv


def titan(ph):
    w, h = 46, 38
    cv = Canvas(w, h)
    water = hexc('4a8ac0')
    sway = WAVE[ph]
    cx = 18
    shaded_ellipse(cv, cx, 24, 14, 12, water)
    shaded_ellipse(cv, cx, 9, 7.5, 6.5, shade(water, 1.12))
    for sx in (cx - 3, cx + 2):
        rect(cv, sx, 9, 2, 2, hexc('e8ffff'))
    for dx in range(-9, 10, 3):  # wave pattern on the body
        for dy, off in ((20, 0), (25, 1), (30, 2)):
            cv.set(cx + dx + off, dy, hexc('a8e0ff'))
            cv.set(cx + dx + off + 1, dy - 1, hexc('a8e0ff'))
    for sgn in (-1, 1):
        shaded_ellipse(cv, cx + sgn * 16, 25 + (sway if sgn > 0 else -sway), 4.5, 7.0, shade(water, 0.95))
    line(cv, cx + 19, 4 + sway, cx + 19, 30 + sway, hexc('d8c9a0'))  # trident
    for dx in (-2, 0, 2):
        line(cv, cx + 19 + dx, 4 + sway, cx + 19 + dx, 1 + sway, hexc('c8e0f0'))
    rect(cv, cx + 17, 4 + sway, 5, 1, hexc('c8e0f0'))
    shaded_rect(cv, cx - 9, h - 6, 8, 6, shade(water, 0.8)); shaded_rect(cv, cx + 1, h - 6, 8, 6, shade(water, 0.8))
    return cv


def sapling(ph):
    cv = Canvas(13, 17)
    bark = hexc('8a5a30')
    leaf = hexc('4fa84a')
    w = WAVE[ph]
    shaded_ellipse(cv, 6, 11, 3.8, 4.4, bark)
    for dx, lift in ((-2, 0 if ph % 2 == 0 else 1), (2, 1 if ph % 2 == 0 else 0)):  # root feet
        rect(cv, 6 + dx - 1, 14 + lift - 1, 2, 3, shade(bark, 0.75))
    for cx, cy, r in ((3, 5 + w, 2.6), (9, 5 - w, 2.6), (6, 3, 3.2)):  # a crown of leaves
        shaded_ellipse(cv, cx, cy, r, r, leaf)
    ellipse(cv, 6, 1.5, 1.2, 1.2, hexc('e0553a'))  # a red bud
    cv.set(5, 10, hexc('ffe84a')); cv.set(7, 10, hexc('ffe84a'))
    rect(cv, 5, 12, 3, 1, hexc('3a2010'))
    return cv


def wolf(ph):
    cv = Canvas(20, 12)
    fur = hexc('8a8a96')
    run = [0, 1, 0, -1][ph]
    shaded_ellipse(cv, 9, 6, 6.5, 3.4, fur)
    shaded_ellipse(cv, 15.5, 4.5, 3.0, 2.6, shade(fur, 1.1))
    poly(cv, [(14, 2), (15, 0), (16.5, 2.5)], shade(fur, 0.85))                  # ear
    poly(cv, [(17.5, 4.5), (20, 5.5), (17.5, 6.5)], shade(fur, 1.15))            # snout
    cv.set(19, 5, hexc('1a1020'))
    cv.set(16, 4, hexc('ffd84a'))
    line(cv, 2, 4, 0, 2 - run, shade(fur, 0.8), 2)                               # tail
    for lx, lift in ((5, run), (8, -run), (11, run), (14, -run)):                # legs
        rect(cv, lx, 8, 2, 3 + (1 if lift > 0 else 0), shade(fur, 0.75))
    rect(cv, 6, 5, 6, 1, shade(fur, 1.25))
    return cv


def slug(ph):
    cv = Canvas(18, 11)
    rock = hexc('6a3a30')
    f = [0, 1, 2, 1][ph]
    shaded_ellipse(cv, 9, 6, 8.0 - f * 0.3, 3.8 + f * 0.2, rock)
    glow = hexc('ff8a2a')
    for x0, y0 in ((4, 4), (8, 3), (12, 5)):
        line(cv, x0, y0, x0 + 2, y0 + 2 + (f % 2), glow)
    cv.set(14, 3, hexc('ffe84a')); cv.set(16, 4, hexc('ffe84a'))
    for sx in (13, 15):
        line(cv, sx, 3, sx + 1, 1, shade(rock, 0.8))
    rect(cv, 2, 9, 14, 1, shade(rock, 0.6))
    return cv


def shade_monster(ph):
    cv = Canvas(13, 17)
    robe = hexc('4a3a70')
    w = [0, 1, 0, -1][ph]
    pts = [(6, 1), (10, 5), (11 + w, 15), (8, 13), (6, 16), (4, 13), (1 - w, 15), (2, 5)]
    poly(cv, pts, shade(robe, 0.8))
    shaded_ellipse(cv, 6, 5, 3.8, 4.0, robe)
    ellipse(cv, 6, 5.5, 2.4, 2.4, hexc('0a0612'))
    cv.set(5, 5, hexc('ff4a6a')); cv.set(7, 5, hexc('ff4a6a'))
    for sgn in (-1, 1):  # claws
        line(cv, 6 + sgn * 4, 9, 6 + sgn * 6, 11 + w, hexc('d8d0f0'))
    return cv


def matriarch(ph):
    w, h = 32, 36
    cv = Canvas(w, h)
    bark = hexc('7a5030')
    leaf = hexc('4fa84a')
    sway = WAVE[ph]
    cx = w // 2
    shaded_ellipse(cv, cx, 23, 8, 11, bark)
    shaded_ellipse(cv, cx, 10, 5.2, 5.0, hexc('c8a070'))                                    # a bark-pale face
    cv.set(cx - 2, 10, hexc('7fff9a')); cv.set(cx + 2, 10, hexc('7fff9a'))
    rect(cv, cx - 2, 13, 4, 1, hexc('3a2010'))
    for sgn in (-1, 1):  # antlers with leaves
        line(cv, cx + sgn * 3, 6, cx + sgn * 8, 0 + sway, hexc('b08a50'), 1)
        line(cv, cx + sgn * 6, 3, cx + sgn * 11, 3 + sway, hexc('b08a50'), 1)
        shaded_ellipse(cv, cx + sgn * 9, 1 + sway, 2.2, 2.0, leaf)
        shaded_ellipse(cv, cx + sgn * 12, 4 + sway, 2.0, 1.8, leaf)
        for k in range(5):                                                                    # vine arms
            line(cv, cx + sgn * 7, 18 + k, cx + sgn * (12 + k // 2), 24 + k * 2 + (sway if sgn > 0 else -sway), shade(leaf, 0.7), 1)
        shaded_ellipse(cv, cx + sgn * 14, 31 + (sway if sgn > 0 else -sway), 3.2, 3.0, shade(leaf, 0.9))
    for dx in (-8, -4, 0, 4, 8):                                                              # root feet
        shaded_rect(cv, cx + dx - 1, h - 5, 4, 5, shade(bark, 0.8))
    for p in [(cx - 3, 20), (cx + 4, 25), (cx - 1, 29)]:
        cv.set(p[0], p[1], hexc('a8d070')); cv.set(p[0] + 1, p[1], hexc('a8d070'))
    return cv


def tyrant(ph):
    w, h = 36, 36
    cv = Canvas(w, h)
    rock = hexc('5a3a38')
    glow = hexc('ff8a2a')
    sway = WAVE[ph]
    cx = w // 2
    shaded_ellipse(cv, cx, 23, 12, 10, rock)
    shaded_ellipse(cv, cx, 10, 6.5, 5.8, shade(rock, 1.1))
    for sx in (cx - 3, cx + 2):
        rect(cv, sx, 10, 2, 2, hexc('ffe84a'))
    for i, dx in enumerate((-5, -2, 1, 4)):                                                   # a crown of flames
        base = 4 + (1 if i % 2 else 0)
        line(cv, cx + dx, base, cx + dx + (i % 2) - 1, (sway if i % 2 else 1), hexc('ffb030' if i % 2 else 'ff6a1a'), 1)
    for sgn in (-1, 1):
        shaded_ellipse(cv, cx + sgn * 15, 24 + (sway if sgn > 0 else -sway), 4.6, 6.4, shade(rock, 0.95))
        line(cv, cx + sgn * 15, 20, cx + sgn * 15, 28, glow)
    for x0, y0, x1, y1 in ((cx - 7, 19, cx - 3, 24), (cx + 2, 18, cx + 7, 23), (cx - 3, 25, cx + 2, 30)):  # glowing cracks
        line(cv, x0, y0, x1, y1, glow)
    shaded_rect(cv, cx - 9, h - 6, 8, 6, shade(rock, 0.8)); shaded_rect(cv, cx + 1, h - 6, 8, 6, shade(rock, 0.8))
    return cv


def sovereign(ph):
    w, h = 40, 38
    cv = Canvas(w, h)
    sway = WAVE[ph]
    cx = w // 2
    light = hexc('f4ecd0')
    dark = hexc('3a2a5a')
    for sgn, col in ((-1, light), (1, dark)):                                                 # wings, one of each
        poly(cv, [(cx + sgn * 4, 14), (cx + sgn * 19, 3 + sway), (cx + sgn * 17, 18), (cx + sgn * 10, 24)], shade(col, 0.9))
        for k in range(3):
            line(cv, cx + sgn * 6, 16 + k * 2, cx + sgn * (16 - k), 8 + k * 4 + sway, shade(col, 1.15))
    for dx in range(-6, 6):                                                                   # the body: half light, half dark
        col = light if dx < 0 else dark
        for y in range(13, 32):
            cv.set(cx + dx, y, shade(col, 1.0 - 0.18 * (dx % 3) / 2.0))
    shaded_ellipse(cv, cx - 3, 9, 3.4, 4.2, light)
    shaded_ellipse(cv, cx + 3, 9, 3.4, 4.2, dark)
    cv.set(cx - 3, 9, hexc('ffd84a')); cv.set(cx + 3, 9, hexc('ff4a8a'))
    ellipse(cv, cx, 2, 6.5, 1.4, hexc('fff3a8'))                                              # a halo
    ellipse(cv, cx, 2, 4.5, 0.6, hexc('0a0612'))
    for sgn, col in ((-1, hexc('ffd84a')), (1, hexc('b58af0'))):
        poly(cv, [(cx + sgn * 2, 5), (cx + sgn * 6, 1), (cx + sgn * 4, 7)], col)
    line(cv, cx + 9, 14 + sway, cx + 9, 36 + sway, hexc('d8d0f0'))                            # a long blade
    rect(cv, cx + 6, 22 + sway, 7, 1, hexc('f2cf6a'))
    shaded_rect(cv, cx - 5, 31, 4, 7, shade(light, 0.85)); shaded_rect(cv, cx + 1, 31, 4, 7, shade(dark, 0.9))
    return cv


MONSTERS = {
    'enemy_slime': slime, 'enemy_bat': bat, 'enemy_skeleton': skeleton, 'enemy_wisp': wisp, 'enemy_brute': brute,
    'enemy_spitter': spitter, 'enemy_imp': imp, 'enemy_wraith': wraith, 'enemy_duelist': duelist,
    'boss_slime_king': slime_king, 'boss_colossus': colossus, 'mini_warden': warden, 'mini_matron': matron,
    'mini_hulk': hulk, 'boss_lich': lich, 'boss_titan': titan,
    'enemy_sapling': sapling, 'enemy_wolf': wolf, 'enemy_slug': slug, 'enemy_shade': shade_monster,
    'boss_matriarch': matriarch, 'boss_tyrant': tyrant, 'boss_sovereign': sovereign,
}


HUMANOIDS = ('enemy_skeleton', 'enemy_duelist', 'mini_warden', 'mini_matron', 'enemy_wraith', 'enemy_shade')   # redrawn on the hero rig by gen_enemies.py


def make_monsters():
    for name, fn in MONSTERS.items():
        if name in HUMANOIDS:
            continue
        save(name, unify([finish(restyle.volumize(restyle.pillow(fn(ph)))) for ph in range(FRAMES)]))


# ------------------------------------------------------------------------------------------- props
def chest(open_=False):
    cv = Canvas(14, 12)
    wood = hexc('a8742c')
    shaded_rect(cv, 0, 4, 14, 8, wood)
    if open_:
        shaded_rect(cv, 0, 0, 14, 4, shade(wood, 0.7))
        rect(cv, 1, 4, 12, 3, hexc('f2cf6a'))
        for x in (3, 6, 9):
            cv.set(x, 5, (255, 255, 255, 255))
    else:
        shaded_rect(cv, 0, 0, 14, 5, shade(wood, 1.1))
        rect(cv, 6, 3, 2, 4, hexc('d8d8e0'))
    for x in (2, 11):
        rect(cv, x, 0 if not open_ else 4, 1, 12 if not open_ else 8, hexc('5a4a3a'))
    return finish(cv)


def forge():
    cv = Canvas(20, 16)
    stone = hexc('5b5f6e')
    shaded_rect(cv, 0, 6, 20, 10, stone)
    shaded_rect(cv, 2, 2, 16, 6, shade(stone, 0.9))
    rect(cv, 5, 4, 10, 4, hexc('2a1410'))
    for i, c in enumerate(['ff6a1a', 'ffb030', 'ffe88a']):
        poly(cv, [(6 + i, 8), (10, 2 + i * 1), (14 - i, 8)], hexc(c))
    shaded_rect(cv, 6, 11, 8, 3, hexc('2e3038'))  # anvil
    return finish(cv)


def board():
    cv = Canvas(18, 16)
    wood = hexc('8a6a3a')
    rect(cv, 2, 14, 2, 2, shade(wood, 0.7)); rect(cv, 14, 14, 2, 2, shade(wood, 0.7))
    shaded_rect(cv, 0, 0, 18, 14, wood)
    for (x, y, w, h, c) in [(2, 2, 6, 5, 'e8dcc0'), (10, 3, 6, 4, 'dccaa0'), (4, 8, 7, 4, 'e8dcc0'), (12, 8, 4, 4, 'c8b890')]:
        rect(cv, x, y, w, h, hexc(c))
        cv.set(x + w // 2, y, hexc('b03a3a'))
        for k in range(1, h - 1, 2):
            rect(cv, x + 1, y + k, w - 2, 1, hexc('7a6a50'))
    return finish(cv)


def door(kind):
    cv = Canvas(16, 16)
    if kind == 'locked':
        rect(cv, 0, 0, 16, 16, hexc('3a1418'))
        for x in range(2, 16, 4):
            shaded_rect(cv, x, 0, 2, 16, hexc('8a8f9c'))
        shaded_rect(cv, 0, 6, 16, 2, hexc('6a6f7c'))
        rect(cv, 0, 0, 16, 1, hexc('b03a3a'))
        rect(cv, 0, 15, 16, 1, hexc('b03a3a'))
    elif kind == 'open':
        rect(cv, 0, 0, 16, 16, hexc('0a0810'))
        for y in range(0, 16, 2):
            rect(cv, 0, y, 16, 1, hexc('14101c'))
        rect(cv, 0, 0, 16, 1, hexc('7fe88a'))
        rect(cv, 0, 15, 16, 1, hexc('7fe88a'))
    else:  # sealed: a wall with a carved seal
        rect(cv, 0, 0, 16, 16, hexc('4a4036'))
        shaded_rect(cv, 0, 0, 16, 16, hexc('4a4036'))
        ellipse(cv, 8, 8, 4, 4, hexc('2f2a24'))
        ellipse(cv, 8, 8, 2, 2, hexc('6a5a46'))
    return cv


def pickups():
    gold = Canvas(7, 7)
    shaded_ellipse(gold, 3, 3, 2.6, 2.6, hexc('ffd84a'))
    gold.set(3, 2, (255, 255, 255, 255))
    save('pickup_gold', [finish(gold)])
    mat = Canvas(7, 7)
    poly(mat, [(3, 0), (6, 3), (3, 6), (0, 3)], (255, 255, 255, 255))
    poly(mat, [(3, 1), (5, 3), (3, 5), (1, 3)], (215, 215, 225, 255))
    mat.set(2, 2, (255, 255, 255, 255))
    save('pickup_material', [finish(mat)], moonlit=False)
    item = Canvas(9, 9)
    shaded_ellipse(item, 4, 5.5, 3.4, 3.0, (255, 255, 255, 255))
    rect(item, 3, 1, 3, 2, (225, 225, 235, 255))
    item.set(4, 4, (150, 150, 165, 255))
    save('pickup_item', [finish(item)], moonlit=False)


def altar():
    """The elements altar: a stepped obsidian plinth with the five main element glyphs glowing on its face and a light
    rune floating above it (docs/ART_DIRECTION.md: every element is a rune)."""
    cv = Canvas(24, 26)
    shaded_rect(cv, 5, 17, 14, 3, hexc('5c5890'))
    shaded_rect(cv, 3, 20, 18, 3, hexc('3c3868'))
    shaded_rect(cv, 1, 23, 22, 3, hexc('5c5890'))
    for i, element in enumerate(['fire', 'water', 'earth', 'air', 'mineral']):   # glowing glyph dots on the middle step
        ramp = style.ramp(element)
        x = 5 + i * 3
        cv.set(x, 21, ramp[4])
        cv.set(x + 1, 21, ramp[3])
        cv.set(x, 22, ramp[2])
        cv.set(x + 1, 22, ramp[1])
    light = style.ramp('light')
    for y in (16, 14):                                                           # a thread of light up to the rune
        cv.set(11, y, light[2])
        cv.set(12, y, light[3])
    cv.blit(style.rune('light', size=10, glow=False), 4, 0)
    return finish(cv)


def training_sign():
    cv = Canvas(14, 18)
    wood = hexc('a8742c')
    rect(cv, 6, 6, 2, 12, shade(wood, 0.7))
    shaded_rect(cv, 0, 1, 12, 5, wood)
    poly(cv, [(12, 1), (14, 3), (12, 5)], shade(wood, 1.1))
    for x in (2, 4, 6, 8):
        rect(cv, x, 3, 1, 1, hexc('3b2610'))
    return finish(cv)


def dummy():
    cv = Canvas(12, 18)
    rect(cv, 5, 8, 2, 10, hexc('6a4a20'))
    shaded_rect(cv, 1, 8, 10, 3, hexc('c8a870'))  # arms
    shaded_ellipse(cv, 6, 5, 4.0, 4.5, hexc('d8b880'))
    rect(cv, 3, 4, 6, 1, hexc('b03a3a'))  # a painted target band
    rect(cv, 4, 15, 4, 3, hexc('5a4020'))
    return finish(cv)


def props():
    save('chest', [chest(False)])
    save('chest_open', [chest(True)])
    save('forge', [forge()])
    save('board', [board()])
    save('altar', [altar()])
    save('training_sign', [training_sign()])
    save('enemy_dummy', [dummy()])
    for kind in ('locked', 'sealed'):   # the open doorway is a portal pad: gen_portal.py
        save('door_' + kind, [door(kind)])
    pickups()


if __name__ == '__main__':
    # the layered heroes come from gen_heroes.py; make_heroes() (the old single-sheet heroes) is no longer run
    make_monsters()
    props()
    print('sprites ->', os.path.abspath(OUT), len(os.listdir(OUT)), 'files')
