"""Renders one style board per proposed art style into docs/art/.
Run:  python tools/art/style_board.py [gilded|moonlit|storybook]      (no argument: all three)
Each board shows the same things so the styles can be compared side by side: the seven element runes, an isometric
dungeon corner with a hero, a spell circle, a bolt and a prop, a detailed hero and a monster, the UI kit, the colour
ramps and three item icons. Everything is drawn by code (style.py and this file); no outside image is used."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pixel import Canvas, hexc, mix, poly, line, rect as fill_rect, ellipse as fill_ellipse
import style
from style import ramp

HERE = os.path.dirname(__file__)
OUT_DIR = os.path.join(HERE, "..", "..", "docs", "art")
ELEMENTS = ["fire", "water", "air", "mineral", "earth", "light", "dark"]
FILES = {"gilded": "style_a_gilded_hollow.png", "moonlit": "style_b_moonlit_glyphwork.png", "storybook": "style_c_autumn_storybook.png"}


def scaled(cv, k):
    out = Canvas(cv.w * k, cv.h * k)
    for y in range(cv.h):
        for x in range(cv.w):
            c = cv.px[y * cv.w + x]
            if c[3]:
                for dy in range(k):
                    for dx in range(k):
                        out.px[(y * k + dy) * out.w + x * k + dx] = c
    return out


def put(dst, src, ox, oy):
    """Alpha-composites src onto dst."""
    for y in range(src.h):
        for x in range(src.w):
            c = src.px[y * src.w + x]
            if not c[3]:
                continue
            d = dst.get(ox + x, oy + y)
            a = c[3] / 255.0
            dst.set(ox + x, oy + y, (int(d[0] * (1 - a) + c[0] * a), int(d[1] * (1 - a) + c[1] * a), int(d[2] * (1 - a) + c[2] * a), 255))


def hashed(x, y, salt=0):
    n = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
    n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
    return ((n ^ (n >> 16)) & 0xffff) / 65535.0


def backdrop(w, h):
    cv = Canvas(w, h, style.backdrop_colour())
    s = 7
    dot = mix(style.backdrop_colour(), hexc("ffffff"), 0.07)
    for _ in range(w * h // 260):
        s = (s * 1103515245 + 12345) & 0x7fffffff
        x = s % w
        s = (s * 1103515245 + 12345) & 0x7fffffff
        cv.set(x, s % h, dot)
    return cv


def runes_row():
    row = Canvas(7 * 46 + 6, 52, style.backdrop_colour())
    for i, name in enumerate(ELEMENTS):
        put(row, style.rune(name, 32), 4 + i * 46, 4)
    return row


# ---------------------------------------------------------------------------------------------
# panel: an isometric corner of a dungeon (floor, walls, light, hero, spell circle, bolt, prop)
# ---------------------------------------------------------------------------------------------

def diamond(cv, cx, cy, hw, hh, colour):
    poly(cv, [(cx, cy - hh), (cx + hw, cy), (cx, cy + hh), (cx - hw, cy)], colour)


def floor_tile(cv, cx, cy, tx, ty):
    """One 32x16 floor diamond. The material follows the style: stone (gilded), obsidian with glowing seams
    (moonlit), warm planks with leaves (storybook)."""
    kind = style.spec()["ui"]
    stone, moss, wood, brass = ramp("stone"), ramp("moss"), ramp("wood"), ramp("brass")
    drift = hashed(tx, ty)
    if kind == "parchment":
        base = wood[2] if drift < 0.5 else wood[3]
        diamond(cv, cx, cy, 16, 8, base)
        for k in (-8, -3, 3, 8):   # planks run along the x axis of the floor
            line(cv, cx - 16 + abs(k) // 2 + 6, cy + k // 2 - 4 + 4, cx + abs(k) // 2 - 1, cy + k // 2 - 8 + 8, wood[1])
        diamond(cv, cx, cy, 13, 6, mix(base, wood[4], 0.18))
        line(cv, cx - 16, cy, cx, cy - 8, wood[4])
        line(cv, cx, cy - 8, cx + 16, cy, wood[3])
        line(cv, cx - 16, cy, cx, cy + 8, wood[0])
        line(cv, cx, cy + 8, cx + 16, cy, wood[0])
        if hashed(tx, ty, 5) > 0.55:
            for j in range(3):
                lx = cx - 8 + int(hashed(tx, ty, 30 + j) * 16)
                ly = cy - 3 + int(hashed(tx, ty, 40 + j) * 6)
                cv.set(lx, ly, ramp("fire")[2] if j % 2 else ramp("mineral")[3])
                cv.set(lx + 1, ly, ramp("fire")[1] if j % 2 else ramp("mineral")[2])
        return
    base = stone[2] if drift < 0.55 else stone[1]
    diamond(cv, cx, cy, 16, 8, base)
    diamond(cv, cx, cy, 13, 6, mix(base, stone[3], 0.35 if drift > 0.3 else 0.15))
    line(cv, cx - 16, cy, cx, cy - 8, stone[3])
    line(cv, cx, cy - 8, cx + 16, cy, stone[3] if drift > 0.5 else stone[2])
    line(cv, cx - 16, cy, cx, cy + 8, stone[0])
    line(cv, cx, cy + 8, cx + 16, cy, stone[0])
    for i in range(3):
        px = cx + int((hashed(tx, ty, 10 + i) - 0.5) * 20)
        py = cy + int((hashed(tx, ty, 20 + i) - 0.5) * 8)
        if abs(px - cx) / 16 + abs(py - cy) / 8 < 0.8:
            cv.set(px, py, stone[3] if i % 2 else stone[1])
    if kind == "slab":
        if hashed(tx, ty, 6) > 0.55:   # glowing seams: a rune line running across the tile
            line(cv, cx - 7, cy - 2, cx - 1, cy + 1, brass[3])
            line(cv, cx - 1, cy + 1, cx + 5, cy - 2, brass[3])
            cv.set(cx - 1, cy + 1, brass[4])
            cv.set(cx - 1, cy + 2, brass[2])
            cv.set(cx - 2, cy + 2, brass[1])
        return
    if hashed(tx, ty, 5) > 0.72:
        for j in range(9):
            mx = cx - 10 + int(hashed(tx, ty, 30 + j) * 8)
            my = cy + int((hashed(tx, ty, 40 + j) - 0.2) * 6)
            if abs(mx - cx) / 16 + abs(my - cy) / 8 < 0.85:
                cv.set(mx, my, moss[2] if j % 3 else moss[3])
    if hashed(tx, ty, 6) > 0.8:
        line(cv, cx - 4, cy - 2, cx + 2, cy + 1, stone[0])
        cv.set(cx + 3, cy + 2, stone[0])


def wall_block(cv, cx, cy, height, tx, ty):
    """A wall tile standing on the diamond centred at (cx, cy): top face and two shaded side faces."""
    kind = style.spec()["ui"]
    stone, moss, wood, brass = ramp("stone"), ramp("moss"), ramp("wood"), ramp("brass")
    ink = style.INK
    hw, hh = 16, 8
    top = cy - height
    if kind == "parchment":   # plaster between timber beams
        left, right, tcol = stone[4], stone[3], wood[3]
    elif kind == "slab":      # obsidian
        left, right, tcol = stone[2], stone[1], stone[3]
    else:
        left, right, tcol = stone[2], stone[1], stone[3]
    poly(cv, [(cx - hw, top), (cx, top + hh), (cx, cy + hh), (cx - hw, cy)], left)
    poly(cv, [(cx, top + hh), (cx + hw, top), (cx + hw, cy), (cx, cy + hh)], right)
    if kind == "parchment":
        for k in range(0, hw + 1, 8):    # vertical beams and a lintel
            line(cv, cx - hw + k, top + k // 2, cx - hw + k, cy + k // 2, wood[2])
            line(cv, cx + k, top + hh - k // 2, cx + k, cy + hh - k // 2, wood[1])
        line(cv, cx - hw, top + 2, cx, top + hh + 2, wood[2])
        line(cv, cx, top + hh + 2, cx + hw, top + 2, wood[1])
        for j in range(4):   # plaster flecks
            cv.set(cx - hw + 3 + int(hashed(tx, ty, 70 + j) * 9), cy - 4 + int(hashed(tx, ty, 80 + j) * 6), stone[3])
    elif kind == "slab":
        mid = top + height // 2
        line(cv, cx - hw, mid, cx, mid + hh, brass[3])           # one glowing seam around the block
        line(cv, cx, mid + hh, cx + hw, mid, brass[2])
        cv.set(cx - 5, mid + 2, brass[4])
        line(cv, cx, top + hh, cx, cy + hh, stone[0])
    else:
        for row in range(1, height // 5 + 1):
            yoff = row * 5
            line(cv, cx - hw, top + yoff, cx, top + hh + yoff, stone[1])
            line(cv, cx, top + hh + yoff, cx + hw, top + yoff, stone[0])
        for row in range(height // 5):
            for k in range(2):
                jx = cx - hw + 4 + k * 8 + (4 if row % 2 else 0)
                if jx < cx:
                    cv.set(jx, top + row * 5 + 2 + (jx - (cx - hw)) // 2 + 1, stone[1])
    diamond(cv, cx, top, hw, hh, tcol)
    diamond(cv, cx, top, hw - 3, hh - 2, mix(tcol, stone[4] if kind != "parchment" else wood[4], 0.4))
    line(cv, cx - hw, top, cx, top - hh, stone[4] if kind != "parchment" else wood[4])
    line(cv, cx, top - hh, cx + hw, top, tcol)
    edge = ink if kind != "parchment" else wood[0]
    line(cv, cx - hw, cy, cx, cy + hh, edge)
    line(cv, cx, cy + hh, cx + hw, cy, edge)
    line(cv, cx - hw, top, cx - hw, cy, edge)
    line(cv, cx + hw, top, cx + hw, cy, edge)
    line(cv, cx - hw, top, cx, top - hh, edge)
    line(cv, cx, top - hh, cx + hw, top, edge)
    if kind == "gilded" or kind == "wood":
        for j in range(6):
            cv.set(cx - hw + 2 + int(hashed(tx, ty, 50 + j) * 11), cy - 3 + int(hashed(tx, ty, 60 + j) * 5), moss[2])


# ---------------------------------------------------------------------------------------------
# characters
# ---------------------------------------------------------------------------------------------

def hero_sprite():
    """A detailed 24 x 38 hero (the game's heroes are 16 x 26 today): hat with band and gem, hair, a face with brows, eyes
    and mouth, a mantle with a trim, an open robe with studs and a rune hem, belt with pouch and vial, sleeves with
    cuffs, boots, a cape and a runed staff. Lit from the upper left; a rim light is added after the outline."""
    fire, skin, brass, wood, dark, stone = ramp("fire"), ramp("skin"), ramp("brass"), ramp("wood"), ramp("dark"), ramp("stone")
    iris = ramp("water" if style.ACTIVE != "storybook" else "earth")
    ink = style.INK
    S = style.step
    cv = Canvas(24, 38)

    def R(x, y, w, h, c):
        fill_rect(cv, x, y, w, h, c)

    def P(pts, c):
        poly(cv, pts, c)

    def L(x0, y0, x1, y1, c):
        line(cv, x0, y0, x1, y1, c)

    # cape behind the body, with folds
    P([(6, 20), (18, 20), (21, 36), (3, 36)], dark[S(1)])
    P([(6, 20), (10, 20), (7, 36), (3, 36)], dark[S(2)])
    L(12, 25, 12, 35, dark[S(0)])
    L(16, 24, 18, 35, dark[S(0)])
    # staff on the right with a runed crystal head
    L(21, 9, 21, 37, wood[S(2)])
    L(22, 11, 22, 37, wood[S(1)])
    for y in (17, 23, 29):
        R(21, y, 2, 1, brass[S(3)])
    P([(21, 1), (23, 4), (21, 8), (19, 4)], fire[S(2)])
    P([(21, 1), (21, 8), (19, 4)], fire[S(3)])
    R(21, 3, 1, 3, fire[4])
    cv.set(20, 4, fire[4])
    # boots and the hem of the robe
    R(8, 35, 4, 3, wood[S(1)])
    R(13, 35, 4, 3, wood[S(0)])
    R(8, 35, 4, 1, brass[S(3)])
    R(13, 35, 4, 1, brass[S(2)])
    cv.set(8, 37, wood[S(3)])
    # robe: lit left, shaded right, folds, an open front with studs
    P([(7, 22), (17, 22), (19, 35), (5, 35)], fire[S(2)])
    P([(13, 22), (17, 22), (19, 35), (13, 35)], fire[S(1)])
    P([(7, 22), (9, 22), (7, 35), (5, 35)], fire[S(3)])
    for fx, fy0 in ((10, 28), (15, 27), (17, 30)):
        L(fx, fy0, fx - 1, 34, fire[S(1)])
    if style.spec()["steps"] >= 5:
        for y in range(23, 35, 2):    # a dithered edge where light turns to shade
            cv.set(12, y, fire[S(1)])
    P([(11, 22), (14, 22), (14, 35), (10, 35)], stone[S(2)])
    R(11, 22, 1, 13, stone[S(3)])
    for y in (25, 29):
        cv.set(13, y, brass[3])
    R(6, 33, 13, 2, brass[S(3)])
    for x in range(7, 18, 3):     # rune pattern on the hem
        cv.set(x, 33, brass[4])
        cv.set(x + 1, 34, brass[S(1)])
    # belt, buckle, pouch and vial
    R(7, 28, 11, 2, wood[S(1)])
    R(11, 28, 3, 2, brass[3])
    cv.set(12, 28, brass[4])
    R(7, 30, 3, 3, wood[S(2)])
    cv.set(8, 30, brass[3])
    R(16, 30, 2, 3, fire[S(3)])
    cv.set(16, 29, stone[4])
    # mantle over the shoulders with a brass trim and studs
    P([(6, 19), (18, 19), (20, 23), (4, 23)], dark[S(2)])
    P([(6, 19), (10, 19), (7, 23), (4, 23)], dark[S(3)])
    R(4, 23, 16, 1, brass[S(3)])
    for x in (7, 12, 17):
        cv.set(x, 23, brass[4])
    # arms: sleeves with cuffs and hands
    P([(3, 21), (7, 21), (7, 30), (3, 30)], fire[S(3)])
    P([(5, 21), (7, 21), (7, 30), (5, 30)], fire[S(2)])
    R(3, 29, 4, 1, brass[S(3)])
    R(3, 30, 4, 3, skin[S(3)])
    cv.set(3, 32, skin[S(2)])
    P([(17, 21), (21, 21), (21, 29), (17, 29)], fire[S(1)])
    R(17, 28, 4, 1, brass[S(2)])
    R(19, 29, 4, 3, skin[S(2)])
    # neck and head
    R(11, 17, 3, 3, skin[S(2)])
    fill_ellipse(cv, 12, 13, 4.6, 5.0, skin[S(3)])
    R(14, 9, 4, 9, skin[S(2)])
    R(10, 17, 4, 1, skin[S(1)])
    cv.set(7, 14, skin[S(3)])
    cv.set(17, 14, skin[S(2)])
    # face: brows, eyes (sclera, iris, glint), nose, mouth
    for bx in (9, 13):
        R(bx, 12, 2, 1, wood[S(1)])
    for ex in (9, 13):
        cv.set(ex, 14, hexc("f4eefc"))
        cv.set(ex + 1, 14, iris[S(2)])
        cv.set(ex + 1, 15, ink)
    cv.set(10, 14, hexc("ffffff"))
    cv.set(12, 15, skin[S(1)])
    R(11, 17, 2, 1, fire[S(1)])
    # hair: a fringe under the brim and side locks
    P([(8, 10), (17, 10), (17, 13), (15, 11), (13, 12), (11, 11), (9, 13), (8, 13)], wood[S(2)])
    P([(6, 11), (8, 11), (8, 19), (5, 19)], wood[S(2)])
    P([(17, 11), (19, 11), (20, 19), (17, 19)], wood[S(1)])
    cv.set(10, 11, wood[S(3)])
    cv.set(12, 11, wood[S(3)])
    # hat: brim, cone leaning to the right, band, buckle gem
    P([(3, 10), (21, 10), (19, 8), (5, 8)], dark[S(2)])
    R(3, 10, 18, 1, dark[S(0)])
    P([(8, 9), (17, 9), (16, 4), (18, 1), (15, 0), (12, 2), (10, 5)], dark[S(2)])
    P([(13, 9), (17, 9), (16, 4), (18, 1), (15, 0), (13, 2)], dark[S(1)])
    L(9, 8, 12, 2, dark[S(3)])
    R(8, 7, 10, 2, brass[S(3)])
    R(8, 7, 10, 1, brass[4])
    R(12, 6, 3, 3, fire[S(2)])
    cv.set(13, 7, fire[4])
    cv.set(16, 2, brass[4])
    out = style.outline(cv)
    for y in range(out.h):  # rim light on the lit (left) edge
        for x in range(out.w - 1):
            c = out.get(x, y)
            if c[3] and out.get(x - 1, y)[3] == 0 and c[0] > 70:
                out.set(x, y, mix(c, hexc("ffe9b0"), 0.45))
    return out


def monster_sprite():
    """A cinder slime: glossy body with an ember core, brow ridge, eyes and a toothy mouth."""
    dark, fire, stone = ramp("dark"), ramp("fire"), ramp("stone")
    S = style.step
    cv = Canvas(24, 20)
    fill_ellipse(cv, 12, 12, 10.5, 7.5, dark[S(2)])
    fill_ellipse(cv, 14, 14, 8.5, 5.5, dark[S(1)])
    fill_ellipse(cv, 9, 9, 5.0, 3.2, dark[S(3)])
    fill_ellipse(cv, 12, 13, 4.2, 3.0, fire[S(2)])
    fill_ellipse(cv, 12, 13, 2.4, 1.8, fire[S(3)])
    cv.set(12, 13, fire[4])
    for x, y in ((6, 6), (7, 5), (8, 5)):
        cv.set(x, y, dark[4])
    for ex in (8, 15):
        fill_rect(cv, ex, 8, 3, 3, hexc("f4eefc"))
        fill_rect(cv, ex + 1, 9, 2, 2, style.INK)
        cv.set(ex + 1, 9, hexc("ffffff"))
    line(cv, 7, 7, 10, 8, dark[S(0)])
    line(cv, 17, 8, 14, 7, dark[S(0)])
    for x in (9, 11, 13, 15):
        cv.set(x, 17, stone[4])
        cv.set(x, 18, stone[3])
    fill_rect(cv, 8, 16, 9, 1, dark[S(0)])
    return style.outline(cv)


def barrel():
    wood, brass = ramp("wood"), ramp("brass")
    cv = Canvas(12, 14)
    fill_ellipse(cv, 6, 10, 5.5, 3.2, wood[1])
    fill_rect(cv, 1, 3, 10, 7, wood[2])
    fill_rect(cv, 1, 3, 3, 7, wood[3])
    fill_rect(cv, 8, 3, 3, 7, wood[1])
    fill_ellipse(cv, 6, 3, 5.5, 2.8, wood[3])
    fill_ellipse(cv, 6, 3, 4, 1.8, wood[2])
    fill_rect(cv, 1, 5, 10, 1, brass[3])
    fill_rect(cv, 1, 8, 10, 1, brass[2])
    return style.outline(cv)


def fire_bolt(length=36):
    """A spell in flight: white-hot core, saturated body, a tail that fades and narrows, and sparks."""
    fire = ramp("fire")
    cv = Canvas(length + 10, 14)
    cy = 7
    for i in range(length):
        t = i / length
        r = 1.0 + 4.4 * t
        for y in range(cy - 6, cy + 7):
            d = abs(y - cy)
            if d <= r * (0.55 + 0.45 * t):
                if d <= r * 0.28 and t > 0.55:
                    col = fire[4]
                elif d <= r * 0.58 and t > 0.3:
                    col = fire[3]
                elif t > 0.4:
                    col = fire[2]
                else:
                    col = fire[1]
                cv.set(i + 2, y, col)
    for i, (x, y) in enumerate([(5, 3), (11, 11), (17, 2), (24, 12), (30, 1)]):
        cv.set(x, y, fire[3] if i % 2 else fire[4])
    head = Canvas(10, 14)
    fill_ellipse(head, 5, 7, 4.4, 4.6, fire[3])
    fill_ellipse(head, 5, 7, 2.8, 3.0, fire[4])
    cv.blit(head, length - 4, 0)
    return cv


def scene_panel():
    cv = Canvas(150, 140, style.backdrop_colour())
    ox, oy = 75, 50
    kind = style.spec()["ui"]

    def foot(tx, ty):
        return ox + (tx - ty) * 16, oy + (tx + ty) * 8 + 8

    for ty in range(5):
        for tx in range(5):
            cx, cy = foot(tx, ty)
            floor_tile(cv, cx, cy, tx, ty)
    torch_x, torch_y = ox + 10, oy + 8 + 8 - 14
    glow = {"wood": hexc("ffb25a"), "slab": hexc("8a78ff"), "parchment": hexc("ffc070")}[kind]
    style.light_pool(cv, torch_x + 4, torch_y + 30, 40, 17, glow, 0.5)
    for tx, ty in ((0, 0), (1, 0), (2, 0), (0, 1)):
        cx, cy = foot(tx, ty)
        wall_block(cv, cx, cy, 24, tx, ty)
    fire, brass = ramp("fire"), ramp("brass")
    if kind == "slab":   # a floating glyph lantern instead of a torch
        fill_ellipse(cv, torch_x + 1, torch_y - 1, 3.2, 3.2, brass[3])
        fill_ellipse(cv, torch_x + 1, torch_y - 1, 1.8, 1.8, brass[4])
        for dx, dy in ((-4, -1), (5, -1), (1, -6), (1, 4)):
            cv.set(torch_x + dx, torch_y + dy, brass[2])
    else:
        fill_rect(cv, torch_x, torch_y + 4, 2, 5, ramp("wood")[1])
        fill_rect(cv, torch_x - 1, torch_y + 3, 4, 1, brass[2])
        poly(cv, [(torch_x - 1, torch_y + 2), (torch_x + 3, torch_y + 2), (torch_x + 2, torch_y - 3), (torch_x + 1, torch_y - 6), (torch_x, torch_y - 2)], fire[2])
        poly(cv, [(torch_x, torch_y + 2), (torch_x + 2, torch_y + 2), (torch_x + 1, torch_y - 2)], fire[4])
        for dx, dy, c in ((-3, -6, 4), (4, -4, 3), (-2, -9, 3)):
            cv.set(torch_x + dx, torch_y + dy, fire[c])
    bx, by = foot(4, 2)
    style.blob_shadow(cv, bx, by + 2, 8, 3)
    put(cv, barrel(), bx - 6, by - 12)
    hx, hy = foot(2, 3)
    circle = style.squash(style.rune("fire", 44, glow=True, disc=False), 0.5)   # the hero's casting circle on the floor
    put(cv, circle, hx - circle.w // 2, hy - circle.h // 2 + 3)
    style.blob_shadow(cv, hx, hy + 3, 7, 3)
    put(cv, hero_sprite(), hx - 12, hy - 33)
    put(cv, fire_bolt(), hx + 8, hy - 20)
    style.light_pool(cv, hx + 42, hy - 10, 22, 10, hexc("ff9a30"), 0.3)
    mx, my = foot(4, 4)
    style.blob_shadow(cv, mx, my + 2, 9, 3)
    put(cv, monster_sprite(), mx - 12, my - 17)
    for j in range(14):
        px = torch_x - 10 + int(hashed(j, 1, 99) * 60)
        py = torch_y - 8 + int(hashed(j, 2, 99) * 44)
        cv.set(px, py, mix(glow, hexc("ffffff"), 0.4) if j % 3 == 0 else mix(glow, style.backdrop_colour(), 0.4))
    return cv


# ---------------------------------------------------------------------------------------------
# panel: the UI kit
# ---------------------------------------------------------------------------------------------

def ui_frame(w, h):
    kind = style.spec()["ui"]
    wood, brass, stone = ramp("wood"), ramp("brass"), ramp("stone")
    ink = style.INK
    cv = Canvas(w, h, ink)
    if kind == "wood":     # carved dark wood, brass studs, dark interior
        fill_rect(cv, 1, 1, w - 2, h - 2, wood[1])
        fill_rect(cv, 2, 2, w - 4, h - 4, wood[2])
        fill_rect(cv, 3, 3, w - 6, h - 6, wood[1])
        fill_rect(cv, 4, 4, w - 8, h - 8, ink)
        fill_rect(cv, 5, 5, w - 10, h - 10, hexc("231a30"))
        for x in range(2, w - 2):
            cv.set(x, 2, wood[3])
            cv.set(x, h - 3, wood[0])
        for y in range(2, h - 2):
            cv.set(2, y, wood[3])
            cv.set(w - 3, y, wood[0])
        for x, y in ((3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4)):
            cv.set(x, y, brass[3])
            cv.set(x - 1, y - 1, brass[4])
            cv.set(x + 1, y + 1, brass[1])
        for k in range(5, w - 5, 2):
            cv.set(k, 6, hexc("30263f"))
    elif kind == "slab":   # an obsidian slab with a thin glowing rune border and notched corners
        fill_rect(cv, 1, 1, w - 2, h - 2, stone[1])
        fill_rect(cv, 2, 2, w - 4, h - 4, stone[0])
        fill_rect(cv, 3, 3, w - 6, h - 6, hexc("0e0a20"))
        for x in range(3, w - 3):
            cv.set(x, 3, brass[2] if x % 6 else brass[4])
            cv.set(x, h - 4, brass[1])
        for y in range(3, h - 3):
            cv.set(3, y, brass[2] if y % 6 else brass[4])
            cv.set(w - 4, y, brass[1])
        for x, y, dx, dy in ((3, 3, 1, 1), (w - 4, 3, -1, 1), (3, h - 4, 1, -1), (w - 4, h - 4, -1, -1)):   # corner glyphs
            for k in range(4):
                cv.set(x + dx * k, y + dy * 3, brass[4])
                cv.set(x + dx * 3, y + dy * k, brass[4])
        for k in range(8, w - 8, 12):   # inscription ticks along the top
            cv.set(k, 5, brass[3])
    else:                  # stitched leather around a parchment page
        fill_rect(cv, 1, 1, w - 2, h - 2, wood[1])
        fill_rect(cv, 2, 2, w - 4, h - 4, wood[2])
        fill_rect(cv, 4, 4, w - 8, h - 8, wood[0])
        fill_rect(cv, 5, 5, w - 10, h - 10, stone[4])
        fill_rect(cv, 6, 6, w - 12, h - 12, stone[3])
        for x in range(4, w - 4):
            cv.set(x, 5, stone[4])
            cv.set(x, h - 6, stone[2])
        for k in range(4, w - 4, 3):   # stitching
            cv.set(k, 3, brass[3])
            cv.set(k, h - 4, brass[3])
        for k in range(4, h - 4, 3):
            cv.set(3, k, brass[3])
            cv.set(w - 4, k, brass[3])
    return cv


def bar(w, kind, frac):
    cols = ramp(kind)
    ink = style.INK
    ui = style.spec()["ui"]
    cv = Canvas(w, 7)
    if ui == "slab":       # a thin glowing line in a dark channel
        fill_rect(cv, 0, 2, w, 4, ink)
        fill_rect(cv, 1, 3, w - 2, 2, hexc("1a1438"))
        fw = int((w - 2) * frac)
        for x in range(fw):
            cv.set(1 + x, 3, cols[4])
            cv.set(1 + x, 4, cols[2])
            cv.set(1 + x, 2, mix(cols[1], ink, 0.3))
        for x in range(6, w - 2, 6):
            cv.set(x, 5, cols[1])
        return cv
    fill_rect(cv, 0, 0, w, 7, ink)
    fill_rect(cv, 1, 1, w - 2, 5, hexc("2a2038") if ui == "wood" else ramp("wood")[0])
    fillw = int((w - 2) * frac)
    for x in range(fillw):
        cv.set(1 + x, 1, cols[4])
        cv.set(1 + x, 2, cols[3])
        cv.set(1 + x, 3, cols[2])
        cv.set(1 + x, 4, cols[2])
        cv.set(1 + x, 5, cols[1])
    for x in range(6, w - 2, 6):
        cv.set(x, 5, cols[0])
        cv.set(x, 4, mix(cols[1], cols[0], 0.5))
    if ui == "parchment":  # rounded ends
        for y in (0, 6):
            cv.set(0, y, (0, 0, 0, 0))
            cv.set(w - 1, y, (0, 0, 0, 0))
    return cv


def slot(element, selected=False):
    ui = style.spec()["ui"]
    wood, brass, stone = ramp("wood"), ramp("brass"), ramp("stone")
    ink = style.INK
    cv = Canvas(18, 18, ink)
    if ui == "slab":
        fill_rect(cv, 1, 1, 16, 16, brass[4] if selected else stone[1])
        fill_rect(cv, 2, 2, 14, 14, hexc("0e0a20"))
    elif ui == "parchment":
        fill_rect(cv, 1, 1, 16, 16, brass[3] if selected else wood[2])
        fill_rect(cv, 2, 2, 14, 14, stone[3])
        for k in range(2, 16):
            cv.set(k, 2, stone[2])
            cv.set(2, k, stone[2])
    else:
        fill_rect(cv, 1, 1, 16, 16, wood[1] if not selected else brass[2])
        fill_rect(cv, 2, 2, 14, 14, hexc("1c1426"))
        for k in range(2, 16):
            cv.set(k, 2, wood[0])
            cv.set(2, k, wood[0])
        if selected:
            for k in range(1, 17):
                cv.set(k, 1, brass[4])
                cv.set(1, k, brass[4])
                cv.set(k, 16, brass[1])
                cv.set(16, k, brass[1])
    if element:
        put(cv, style.rune(element, 14, glow=False), 0, 0)
    return cv


def button(w, label_w, pressed=False):
    ui = style.spec()["ui"]
    brass, wood, stone = ramp("brass"), ramp("wood"), ramp("stone")
    ink = style.INK
    cv = Canvas(w, 12, ink)
    if ui == "slab":
        fill_rect(cv, 1, 1, w - 2, 10, stone[2] if pressed else stone[1])
        for x in range(1, w - 1):
            cv.set(x, 1, brass[4] if pressed else brass[2])
            cv.set(x, 10, stone[0])
        fill_rect(cv, (w - label_w) // 2, 5, label_w, 2, brass[4] if pressed else stone[4])
        return cv
    top = wood[3] if pressed else wood[2]
    fill_rect(cv, 1, 1, w - 2, 10, top)
    for x in range(1, w - 1):
        cv.set(x, 1, brass[3])
        cv.set(x, 10, wood[0])
    for y in range(1, 11):
        cv.set(1, y, brass[2])
        cv.set(w - 2, y, wood[0])
    if ui == "parchment":
        for x in range(3, w - 3, 3):
            cv.set(x, 2, brass[4])
    fill_rect(cv, (w - label_w) // 2, 5, label_w, 2, brass[4] if pressed else (hexc("f0e2c0") if ui == "wood" else stone[4]))
    return cv


def text_lines(w, lines, colour):
    cv = Canvas(w, lines * 4)
    for i in range(lines):
        run = w if i < lines - 1 else w // 2
        x = 0
        while x < run:
            word = 3 + int(hashed(i, x, 7) * 8)
            fill_rect(cv, x, i * 4 + 1, min(word, run - x), 2, colour)
            x += word + 2
    return cv


def ui_panel():
    cv = Canvas(84, 140, style.backdrop_colour())
    ui = style.spec()["ui"]
    put(cv, ui_frame(84, 84), 0, 0)
    for i, e in enumerate(["fire", "water", "air", "dark"]):
        put(cv, slot(e, i == 0), 6 + i * 19 - (1 if i else 0), 9)
    put(cv, bar(72, "fire", 0.8), 6, 32)
    put(cv, bar(72, "water", 0.55), 6, 41)
    put(cv, bar(72, "mineral", 0.9), 6, 50)
    text_colour = hexc("e8dcc0") if ui != "parchment" else ramp("wood")[1]
    put(cv, text_lines(72, 3, text_colour), 6, 62)
    put(cv, button(64, 20), 10, 90)
    put(cv, button(64, 28, True), 10, 106)
    put(cv, button(64, 24), 10, 122)
    return cv


# ---------------------------------------------------------------------------------------------
# panels: characters, palette and items
# ---------------------------------------------------------------------------------------------

def character_panel():
    cv = Canvas(70, 140, style.backdrop_colour())
    hx, hy = 21, 64
    style.blob_shadow(cv, hx + 12, hy + 38, 11, 3)
    put(cv, hero_sprite(), hx, hy)
    mon = monster_sprite()
    style.blob_shadow(cv, 36, 128, 13, 3)
    put(cv, mon, 24, 108)
    bar_cv = Canvas(18, 4, style.INK)
    fill_rect(bar_cv, 1, 1, 12, 2, ramp("fire")[2])
    fill_rect(bar_cv, 13, 1, 4, 2, ramp("stone")[1])
    put(cv, bar_cv, 27, 103)
    # a size reference: the current 16 x 26 hero next to the proposed 24 x 38
    cur = Canvas(16, 26)
    fire, skin = ramp("fire"), ramp("skin")
    poly(cur, [(4, 11), (11, 11), (13, 21), (2, 21)], fire[2])
    fill_ellipse(cur, 8, 8, 3.4, 3.2, skin[3])
    poly(cur, [(4, 6), (12, 6), (11, 3), (9, 0), (7, 2)], ramp("dark")[2])
    put(cv, style.outline(cur), 2, 70)
    return cv


def potion():
    red, stone, wood = ramp("fire"), ramp("stone"), ramp("wood")
    cv = Canvas(16, 18)
    fill_ellipse(cv, 8, 12, 5.2, 4.6, red[2])
    fill_rect(cv, 6, 4, 4, 5, stone[4])
    fill_rect(cv, 6, 2, 4, 2, wood[3])
    fill_ellipse(cv, 8, 13, 4.0, 3.2, red[3])
    fill_rect(cv, 4, 12, 8, 4, red[2])
    for x, y, c in ((5, 10, 4), (6, 9, 4), (10, 15, 1), (11, 14, 1)):
        cv.set(x, y, red[c])
    return style.outline(cv)


def sword():
    stone, brass, wood = ramp("stone"), ramp("brass"), ramp("wood")
    cv = Canvas(16, 18)
    line(cv, 12, 2, 4, 11, stone[3], 2)
    line(cv, 11, 2, 3, 10, stone[4])
    line(cv, 13, 3, 5, 12, stone[1])
    line(cv, 2, 9, 7, 14, brass[3], 2)
    line(cv, 3, 14, 1, 16, wood[2], 2)
    return style.outline(cv)


def ring():
    brass, dark = ramp("brass"), ramp("dark")
    cv = Canvas(16, 18)
    for y in range(18):
        for x in range(16):
            if 3.6 <= math.hypot(x - 8, y - 11) <= 5.6:
                cv.set(x, y, brass[3] if (x + y) % 5 else brass[4])
    fill_ellipse(cv, 8, 5, 2.8, 2.6, dark[2])
    cv.set(7, 4, dark[4])
    cv.set(8, 4, dark[3])
    return style.outline(cv)


def palette_panel():
    cv = Canvas(64, 140, style.backdrop_colour())
    names = ["fire", "water", "air", "mineral", "earth", "light", "dark", "stone", "wood", "brass", "moss", "skin"]
    for i, n in enumerate(names):
        for j, c in enumerate(ramp(n)):
            fill_rect(cv, 2 + j * 12, 2 + i * 6, 11, 5, c)
    put(cv, potion(), 4, 82)
    put(cv, sword(), 24, 82)
    put(cv, ring(), 44, 82)
    return cv


def render(name):
    style.use(name)
    board = backdrop(380, 200)
    put(board, runes_row(), 4, 2)
    put(board, scene_panel(), 2, 58)
    put(board, character_panel(), 154, 58)
    put(board, ui_panel(), 226, 58)
    put(board, palette_panel(), 312, 58)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, FILES[name])
    scaled(board, 3).save(path)
    print(path)


def main():
    names = sys.argv[1:] or list(FILES)
    for name in names:
        render(name)


if __name__ == "__main__":
    main()
