"""Renders the style board for the proposed art direction ("Gilded Hollow") into style_board.png.
Run:  python tools/art/style_board.py
Everything on the board is drawn by code (style.py and this file), so the real restyle can reuse the same functions."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pixel import Canvas, hexc, mix, poly, line, rect as fill_rect, ellipse as fill_ellipse
import style
from style import ramp

HERE = os.path.dirname(__file__)
ELEMENTS = ["fire", "water", "air", "mineral", "earth", "light", "dark"]
BACK = hexc("181226")
INK = style.INK


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


def backdrop(w, h):
    """A dusk-violet backdrop with a few drifting motes."""
    cv = Canvas(w, h, BACK)
    s = 7
    for _ in range(w * h // 260):
        s = (s * 1103515245 + 12345) & 0x7fffffff
        x = s % w
        s = (s * 1103515245 + 12345) & 0x7fffffff
        y = s % h
        cv.set(x, y, hexc("2a2240"))
    return cv


def hashed(x, y, salt=0):
    n = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
    n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
    return ((n ^ (n >> 16)) & 0xffff) / 65535.0


def emblems_row():
    row = Canvas(7 * 44 + 6, 50, BACK)
    for i, name in enumerate(ELEMENTS):
        e = style.emblem(name, 32)
        put(row, e, 4 + i * 44 - (e.w - 32) // 2 + 4, 4)
    return row


# ---------------------------------------------------------------------------------------------
# panel: an isometric corner of a dungeon (floor, walls, torchlight, hero, spell, prop)
# ---------------------------------------------------------------------------------------------

def diamond(cv, cx, cy, hw, hh, colour):
    poly(cv, [(cx, cy - hh), (cx + hw, cy), (cx, cy + hh), (cx - hw, cy)], colour)


def floor_tile(cv, cx, cy, tx, ty):
    """One 32x16 floor diamond: a stone ramp with hue drift, bevelled edges, speckles, moss and cracks."""
    stone, moss = ramp("stone"), ramp("moss")
    drift = hashed(tx, ty)
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
    """A wall tile standing on the diamond centred at (cx, cy): top face and two bricked side faces."""
    stone, moss = ramp("stone"), ramp("moss")
    hw, hh = 16, 8
    top = cy - height
    poly(cv, [(cx - hw, top), (cx, top + hh), (cx, cy + hh), (cx - hw, cy)], stone[2])
    poly(cv, [(cx, top + hh), (cx + hw, top), (cx + hw, cy), (cx, cy + hh)], stone[1])
    for row in range(1, height // 5 + 1):
        yoff = row * 5
        line(cv, cx - hw, top + yoff, cx, top + hh + yoff, stone[1])
        line(cv, cx, top + hh + yoff, cx + hw, top + yoff, stone[0])
    for row in range(height // 5):
        for k in range(2):
            jx = cx - hw + 4 + k * 8 + (4 if row % 2 else 0)
            if jx < cx:
                cv.set(jx, top + row * 5 + 2 + (jx - (cx - hw)) // 2 + 1, stone[1])
    diamond(cv, cx, top, hw, hh, stone[3])
    diamond(cv, cx, top, hw - 3, hh - 2, mix(stone[3], stone[4], 0.4))
    line(cv, cx - hw, top, cx, top - hh, stone[4])
    line(cv, cx, top - hh, cx + hw, top, stone[3])
    line(cv, cx, top + hh, cx, cy + hh, stone[0])
    line(cv, cx - hw, cy, cx, cy + hh, INK)
    line(cv, cx, cy + hh, cx + hw, cy, INK)
    line(cv, cx - hw, top, cx - hw, cy, INK)
    line(cv, cx + hw, top, cx + hw, cy, INK)
    line(cv, cx - hw, top, cx, top - hh, INK)
    line(cv, cx, top - hh, cx + hw, top, INK)
    for j in range(6):
        mx = cx - hw + 2 + int(hashed(tx, ty, 50 + j) * 11)
        my = cy - 3 + int(hashed(tx, ty, 60 + j) * 5)
        cv.set(mx, my, moss[2])


def hero_sprite():
    """A 16x24 hero: warm lit left side, cool shaded right, rim light, coloured outline."""
    fire, skin, brass, wood, dark = ramp("fire"), ramp("skin"), ramp("brass"), ramp("wood"), ramp("dark")
    cv = Canvas(16, 24)
    poly(cv, [(4, 11), (11, 11), (13, 21), (2, 21)], fire[2])
    poly(cv, [(8, 11), (11, 11), (13, 21), (8, 21)], fire[1])
    poly(cv, [(4, 11), (6, 11), (4, 21), (2, 21)], fire[3])
    fill_rect(cv, 3, 16, 10, 1, brass[3])
    fill_rect(cv, 7, 16, 2, 2, brass[4])
    fill_ellipse(cv, 8, 8, 3.4, 3.2, skin[3])
    fill_rect(cv, 8, 6, 4, 5, skin[2])
    cv.set(6, 8, INK)
    cv.set(9, 8, INK)
    cv.set(7, 10, skin[1])
    poly(cv, [(4, 6), (12, 6), (11, 3), (9, 0), (7, 2)], dark[2])
    poly(cv, [(8, 3), (9, 0), (11, 3), (12, 6), (8, 6)], dark[1])
    fill_rect(cv, 3, 6, 11, 1, dark[1])
    fill_rect(cv, 4, 5, 8, 1, brass[3])
    fill_rect(cv, 4, 21, 3, 2, wood[1])
    fill_rect(cv, 9, 21, 3, 2, wood[0])
    line(cv, 14, 8, 14, 22, wood[2])
    fill_rect(cv, 13, 5, 3, 3, fire[3])
    cv.set(14, 5, fire[4])
    out = cv.outline(None)
    for y in range(out.h):  # rim light on the lit (left) edge
        for x in range(out.w - 1):
            c = out.get(x, y)
            if c[3] and out.get(x - 1, y)[3] == 0 and c[0] > 80:
                out.set(x, y, mix(c, hexc("ffe9b0"), 0.5))
    return out


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
    return cv.outline(None)


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
    cv = Canvas(160, 118, hexc("0f0b1c"))
    ox, oy = 80, 40

    def foot(tx, ty):
        return ox + (tx - ty) * 16, oy + (tx + ty) * 8 + 8

    for ty in range(5):
        for tx in range(5):
            cx, cy = foot(tx, ty)
            floor_tile(cv, cx, cy, tx, ty)
    # the light pool goes on before the props so they sit in it
    torch_x, torch_y = ox + 10, oy + 8 + 8 - 14
    style.light_pool(cv, torch_x + 4, torch_y + 30, 40, 17, hexc("ffb25a"), 0.55)
    for tx, ty in ((0, 0), (1, 0), (2, 0), (0, 1)):
        cx, cy = foot(tx, ty)
        wall_block(cv, cx, cy, 24, tx, ty)
    fire = ramp("fire")
    fill_rect(cv, torch_x, torch_y + 4, 2, 5, ramp("wood")[1])
    fill_rect(cv, torch_x - 1, torch_y + 3, 4, 1, ramp("brass")[2])
    poly(cv, [(torch_x - 1, torch_y + 2), (torch_x + 3, torch_y + 2), (torch_x + 2, torch_y - 3), (torch_x + 1, torch_y - 6), (torch_x, torch_y - 2)], fire[2])
    poly(cv, [(torch_x, torch_y + 2), (torch_x + 2, torch_y + 2), (torch_x + 1, torch_y - 2)], fire[4])
    for dx, dy, c in ((-3, -6, 4), (4, -4, 3), (-2, -9, 3)):
        cv.set(torch_x + dx, torch_y + dy, fire[c])
    bx, by = foot(4, 2)
    style.blob_shadow(cv, bx, by + 2, 8, 3)
    put(cv, barrel(), bx - 6, by - 12)
    hx, hy = foot(2, 3)
    style.blob_shadow(cv, hx, hy + 3, 7, 3)
    put(cv, hero_sprite(), hx - 8, hy - 21)
    put(cv, fire_bolt(), hx + 6, hy - 14)
    style.light_pool(cv, hx + 40, hy - 6, 22, 10, hexc("ff9a30"), 0.35)
    for j in range(14):
        mx = torch_x - 10 + int(hashed(j, 1, 99) * 60)
        my = torch_y - 8 + int(hashed(j, 2, 99) * 44)
        cv.set(mx, my, hexc("ffd89a") if j % 3 == 0 else hexc("c88a5a"))
    return cv


# ---------------------------------------------------------------------------------------------
# panel: the UI kit (frame, bars, hotbar, button, text blocks)
# ---------------------------------------------------------------------------------------------

def ui_frame(w, h):
    """A carved dark-wood frame with brass studs and an inner ink bevel; the interior stays dark for legible text."""
    wood, brass = ramp("wood"), ramp("brass")
    cv = Canvas(w, h, INK)
    fill_rect(cv, 1, 1, w - 2, h - 2, wood[1])
    fill_rect(cv, 2, 2, w - 4, h - 4, wood[2])
    fill_rect(cv, 3, 3, w - 6, h - 6, wood[1])
    fill_rect(cv, 4, 4, w - 8, h - 8, INK)
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
    return cv


def bar(w, kind, frac):
    """A resource bar: ink case, banded fill with a bright top line, notches."""
    cols = ramp(kind)
    cv = Canvas(w, 7)
    fill_rect(cv, 0, 0, w, 7, INK)
    fill_rect(cv, 1, 1, w - 2, 5, hexc("2a2038"))
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
    if fillw > 1:
        cv.set(fillw, 1, cols[4])
        cv.set(fillw, 2, cols[4])
    return cv


def slot(element, selected=False):
    wood, brass = ramp("wood"), ramp("brass")
    cv = Canvas(18, 18, INK)
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
        put(cv, style.emblem(element, 12, glow=False), 1, 1)
    return cv


def button(w, label_w, pressed=False):
    brass, wood = ramp("brass"), ramp("wood")
    cv = Canvas(w, 12, INK)
    fill_rect(cv, 1, 1, w - 2, 10, wood[2] if not pressed else wood[3])
    for x in range(1, w - 1):
        cv.set(x, 1, brass[3])
        cv.set(x, 10, wood[0])
    for y in range(1, 11):
        cv.set(1, y, brass[2])
        cv.set(w - 2, y, wood[0])
    fill_rect(cv, (w - label_w) // 2, 5, label_w, 2, brass[4] if pressed else hexc("f0e2c0"))
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
    cv = Canvas(82, 118, hexc("0f0b1c"))
    put(cv, ui_frame(82, 80), 0, 0)
    for i, e in enumerate(["fire", "water", "air", "mineral"]):
        put(cv, slot(e, i == 0), 5 + i * 19 - (1 if i else 0), 8)
    put(cv, bar(70, "fire", 0.8), 6, 30)
    put(cv, bar(70, "water", 0.55), 6, 39)
    put(cv, bar(70, "mineral", 0.9), 6, 48)
    put(cv, text_lines(70, 3, hexc("e8dcc0")), 6, 58)
    put(cv, button(60, 20), 11, 84)
    put(cv, button(60, 28, True), 11, 99)
    return cv


# ---------------------------------------------------------------------------------------------
# panel: palette ramps and items
# ---------------------------------------------------------------------------------------------

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
    return cv.outline(None)


def sword():
    stone, brass, wood = ramp("stone"), ramp("brass"), ramp("wood")
    cv = Canvas(16, 18)
    line(cv, 12, 2, 4, 11, stone[3], 2)
    line(cv, 11, 2, 3, 10, stone[4])
    line(cv, 13, 3, 5, 12, stone[1])
    line(cv, 2, 9, 7, 14, brass[3], 2)
    line(cv, 3, 14, 1, 16, wood[2], 2)
    return cv.outline(None)


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
    return cv.outline(None)


def palette_panel():
    cv = Canvas(62, 118, hexc("0f0b1c"))
    names = ["fire", "water", "air", "mineral", "earth", "light", "dark", "stone", "wood", "brass", "moss", "skin"]
    for i, n in enumerate(names):
        for j, c in enumerate(ramp(n)):
            fill_rect(cv, 2 + j * 11, 2 + i * 6, 10, 5, c)
    put(cv, potion(), 4, 80)
    put(cv, sword(), 24, 80)
    put(cv, ring(), 44, 80)
    return cv


def main():
    board = backdrop(320, 180)
    put(board, emblems_row(), 4, 2)
    put(board, scene_panel(), 2, 58)
    put(board, ui_panel(), 166, 58)
    put(board, palette_panel(), 252, 58)
    out_dir = os.path.join(HERE, "..", "..", "docs", "art")
    os.makedirs(out_dir, exist_ok=True)
    scaled(board, 4).save(os.path.join(out_dir, "style_board.png"))
    print("style_board.png written")


if __name__ == "__main__":
    main()
