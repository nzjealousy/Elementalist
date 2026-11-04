"""Skill effect sprites: projectiles per element, impact bursts, the slash arc and ground runes.
Run: python tools/art/gen_vfx.py -> elementalist/assets/sprites/

proj_<element>_strip.png   4 frames, 14x9, pointing right (code rotates it along the flight)
fx_hit_strip.png           5 frames, 18x18, white-hot burst (code tints it with the element colour)
fx_slash_strip.png         4 frames, 34x34, a crescent sweeping clockwise (white, tinted by code)
fx_rune_strip.png          4 frames, 40x40, a rotating rune circle for area skills (white, tinted by code)
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pixel import Canvas, Rng, ellipse, hexc, line, poly, shade, sheet, shaded_ellipse, mix

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'sprites')
os.makedirs(OUT, exist_ok=True)

# element -> (core, mid, edge) colours of its bolt
BOLTS = {
    'fire': ('ffe9a0', 'ff7a1f', 'a02a10'), 'water': ('eaf6ff', '3fa7ff', '1a4a9a'),
    'earth': ('d8f5b0', '5fbf4a', '2d5a22'), 'air': ('ffffff', 'b8e4ff', '6a9ac0'),
    'mineral': ('fff6df', 'c9b898', '6a5a40'), 'light': ('ffffff', 'ffe27a', 'c8901a'),
    'dark': ('e0c0ff', '8a4fd0', '2a1040'), 'martial': ('ffffff', 'c9c9d2', '55555f'),
}


def bolt(element, frame):
    core, mid, edge = (hexc(c) for c in BOLTS[element])
    cv = Canvas(14, 9)
    pulse = [0.0, 0.5, 1.0, 0.5][frame]
    cy = 4
    # tail: a tapering comet, flickering with the frame
    for i in range(9):
        r = (1.0 + 2.6 * (i / 9)) * (0.8 + 0.2 * pulse) if i < 9 else 0
        x = 1 + i
        ellipse(cv, x, cy + (0.6 * math.sin(frame + i) if element in ('air', 'water') else 0), 0.7, r * 0.9, edge if i < 4 else mid)
    if element == 'mineral':  # a spinning shard
        a = frame * 0.5
        poly(cv, [(11 + 3 * math.cos(a), cy + 3 * math.sin(a)), (11 + 2 * math.cos(a + 1.6), cy + 2 * math.sin(a + 1.6)),
                  (11 + 3 * math.cos(a + 3.14), cy + 3 * math.sin(a + 3.14)), (11 + 2 * math.cos(a + 4.7), cy + 2 * math.sin(a + 4.7))], mid)
        ellipse(cv, 11, cy, 1.2, 1.2, core)
    elif element == 'martial':  # a throwing knife
        line(cv, 4, cy, 12, cy, core)
        poly(cv, [(12, cy), (9, cy - 2), (9, cy + 2)], mid)
        cv.set(3, cy, edge); cv.set(4, cy, edge)
    elif element == 'earth':  # a leaf-wrapped thorn
        poly(cv, [(13, cy), (8, cy - 3), (6, cy), (8, cy + 3)], mid)
        line(cv, 6, cy, 12, cy, core)
    else:
        shaded_ellipse(cv, 10.5, cy, 3.0 + 0.4 * pulse, 3.0 + 0.4 * pulse, mid)
        ellipse(cv, 10.5, cy, 1.6, 1.6, core)
    return cv


def hit(frame):
    cv = Canvas(18, 18)
    t = frame / 4.0
    r = 2 + 6 * t
    a = int(255 * (1.0 - t * 0.8))
    for k in range(24):  # a ring
        ang = k / 24 * math.tau
        cv.set(int(round(9 + math.cos(ang) * r)), int(round(9 + math.sin(ang) * r)), (255, 255, 255, a))
    for k in range(8):  # rays
        ang = k / 8 * math.tau + 0.3
        r0, r1 = r * 0.5, r + 2 + 2 * (1 - t)
        line(cv, int(9 + math.cos(ang) * r0), int(9 + math.sin(ang) * r0), int(9 + math.cos(ang) * r1), int(9 + math.sin(ang) * r1), (255, 255, 255, int(a * 0.8)))
    if frame < 2:
        ellipse(cv, 9, 9, 3 - frame, 3 - frame, (255, 255, 255, 255))
    return cv


def slash(frame):
    cv = Canvas(34, 34)
    sweep = [0.35, 0.6, 0.85, 1.0][frame]
    alpha = [255, 235, 170, 80][frame]
    # a crescent: the gap between two circles, swept through an arc facing right
    for y in range(34):
        for x in range(34):
            dx, dy = x - 6.0, y - 17.0
            d = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            if 14 <= d <= 24 and -1.15 < ang < -1.15 + 2.3 * sweep:
                thick = 1.0 - abs(d - 19.0) / 5.0
                head = 1.0 - (ang - (-1.15 + 2.3 * sweep)) ** 2 * 0 if True else 0
                tail = (ang + 1.15) / (2.3 * sweep + 1e-6)
                if thick > 0.15 + 0.5 * (1.0 - tail):
                    cv.set(x, y, (255, 255, 255, int(alpha * min(1.0, 0.4 + tail))))
    return cv


def rune(frame):
    cv = Canvas(40, 40)
    c = 19.5
    spin = frame * (math.tau / 16)
    for r, a in [(18.5, 200), (13.5, 150)]:
        for k in range(120):
            ang = k / 120 * math.tau
            cv.set(int(round(c + math.cos(ang) * r)), int(round(c + math.sin(ang) * r)), (255, 255, 255, a))
    for k in range(8):  # tick marks between the rings
        ang = k / 8 * math.tau + spin
        line(cv, int(c + math.cos(ang) * 14), int(c + math.sin(ang) * 14), int(c + math.cos(ang) * 18), int(c + math.sin(ang) * 18), (255, 255, 255, 220))
    for k in range(3):  # a triangle glyph
        a0 = k / 3 * math.tau - spin * 0.5
        a1 = (k + 1) / 3 * math.tau - spin * 0.5
        line(cv, int(c + math.cos(a0) * 9), int(c + math.sin(a0) * 9), int(c + math.cos(a1) * 9), int(c + math.sin(a1) * 9), (255, 255, 255, 190))
    cv.set(19, 19, (255, 255, 255, 255)); cv.set(20, 20, (255, 255, 255, 255))
    return cv


def save(name, frames):
    frames[0].save(os.path.join(OUT, name + '.png'))
    sheet(frames, os.path.join(OUT, name + '_strip.png'))


for element in BOLTS:
    save('proj_' + element, [bolt(element, f) for f in range(4)])
for f in range(3):
    pass
enemy_orb = []
for f in range(3):
    cv = Canvas(7, 7)
    shaded_ellipse(cv, 3, 3, 2.6 + 0.3 * (f % 2), 2.6 + 0.3 * (f % 2), (255, 255, 255, 255))
    ellipse(cv, 3, 3, 1.0, 1.0, (255, 255, 255, 255))
    enemy_orb.append(cv.outline((40, 20, 50, 255)))
save('proj_enemy', enemy_orb)
save('fx_hit', [hit(f) for f in range(5)])
save('fx_slash', [slash(f) for f in range(4)])
save('fx_rune', [rune(f) for f in range(4)])
print('vfx ->', os.path.abspath(OUT))
