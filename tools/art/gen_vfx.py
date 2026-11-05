"""Skill effect sprites in the Moonlit Glyphwork style: glowing bolts, impact bursts, the slash arc and ground rune circles.
Run: python tools/art/gen_vfx.py -> elementalist/assets/sprites/

proj_<element>_strip.png     4 frames, 18x11, pointing right; the bright head sits 5.5 px ahead of the centre
proj_enemy_strip.png         3 frames, 7x7, white orb (code tints it with the shooter's colour)
fx_hit_strip.png             5 frames, 18x18, white-hot burst (code tints it with the element colour)
fx_slash_strip.png           4 frames, 34x34, a crescent sweeping clockwise (white, tinted by code)
fx_rune_strip.png            4 frames, 40x40, a turning rune circle for area skills (white, tinted by code)
fx_rune_<element>_strip.png  the same circle with that element's glyph in its heart

Glow recipe (every emissive thing in the game): white-hot core, saturated body, dark halo, coloured outer glow."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import style
from pixel import Canvas, Rng, ellipse, line, poly, sheet

style.use("moonlit")

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'sprites')
os.makedirs(OUT, exist_ok=True)

ELEMENTS = ['fire', 'water', 'earth', 'air', 'mineral', 'light', 'dark', 'martial']
W, H, CY = 18, 11, 5
HEAD = 14.0     # x of the bolt's head; the game offsets the sprite by (-(HEAD - W/2 + 0.5), 0)


def cols(element):
    return style.ramp(style.RAMP_OF.get(element, element))


def rgba(c, a):
    return (c[0], c[1], c[2], a)


def disc(cv, cx, cy, r, c):
    ellipse(cv, cx, cy, r, r, c)


def glow_head(cv, cx, cy, r, cs, hot=True):
    """The recipe as concentric discs: outer glow, dark halo, saturated body, white-hot core."""
    disc(cv, cx, cy, r + 2.0, rgba(cs[2], 55))
    disc(cv, cx, cy, r + 1.2, rgba(cs[1], 255))
    disc(cv, cx, cy, r, cs[2])
    disc(cv, cx, cy, r * 0.72, cs[3])
    if hot:
        disc(cv, cx, cy, max(r * 0.38, 0.8), cs[4])


def tail(cv, cs, frame, element):
    """A tapering comet tail: dark halo, body, then a hot centre line near the head."""
    pulse = [0.0, 0.5, 1.0, 0.5][frame]
    rng = Rng(7 + frame * 13)
    for i in range(12):
        x = 1 + i
        t = i / 11.0
        half = (0.5 + 2.1 * t) * (0.85 + 0.15 * pulse)
        wob = 0.0
        if element in ('air', 'water'):
            wob = 0.9 * math.sin(frame * 1.3 + i * 0.7)
        elif element == 'fire':
            half += (rng.next() - 0.5) * 0.8
        cy = CY + wob
        for dy in range(-3, 4):
            d = abs(dy - (cy - CY))
            if d <= half + 0.6:
                cv.set(x, CY + dy, rgba(cs[1], 255 if d <= half else 150))
            if d <= half - 0.5:
                cv.set(x, CY + dy, cs[2] if t < 0.65 else cs[3])
        if t > 0.35:
            cv.set(x, int(round(cy)), cs[4] if t > 0.6 else cs[3])


def bolt(element, frame):
    cs = cols(element)
    cv = Canvas(W, H)
    if element == 'air':     # three trailing wind streaks and a small crescent head
        for k, dy in enumerate((-2, 0, 2)):
            for i in range(3, 14):
                y = CY + dy + int(round(0.7 * math.sin(frame * 1.1 + i * 0.6 + k)))
                cv.set(i, y, cs[1] if i < 6 else (cs[2] if i < 10 else cs[3]))
            cv.set(13, CY + dy, cs[4])
        glow_head(cv, HEAD, CY, 2.1, cs)
        return cv
    tail(cv, cs, frame, element)
    if element == 'mineral':     # a spinning cut shard, two facets
        a = frame * 0.55
        pts = [(HEAD + 3.6 * math.cos(a), CY + 3.6 * math.sin(a)), (HEAD + 2.3 * math.cos(a + 1.57), CY + 2.3 * math.sin(a + 1.57)),
               (HEAD + 3.6 * math.cos(a + 3.14), CY + 3.6 * math.sin(a + 3.14)), (HEAD + 2.3 * math.cos(a + 4.71), CY + 2.3 * math.sin(a + 4.71))]
        poly(cv, [(HEAD + (p[0] - HEAD) * 1.3, CY + (p[1] - CY) * 1.3) for p in pts], cs[1])   # dark halo
        poly(cv, pts, cs[2])
        poly(cv, [pts[0], pts[1], (HEAD, CY)], cs[3])
        cv.set(int(HEAD), CY, cs[4])
    elif element == 'earth':     # a leaf-wrapped thorn
        poly(cv, [(17.6, CY), (12, CY - 3.4), (10, CY), (12, CY + 3.4)], cs[1])
        poly(cv, [(17, CY), (12.2, CY - 2.6), (10.8, CY), (12.2, CY + 2.6)], cs[2])
        poly(cv, [(17, CY), (12.2, CY - 2.6), (11, CY - 0.4)], cs[3])
        line(cv, 11, CY, 16, CY, cs[4])
    elif element == 'fire':      # a flame head: a round heart with a licking tip
        glow_head(cv, HEAD - 1.0, CY, 2.4, cs)
        poly(cv, [(17.4, CY), (14, CY - 2.2), (14, CY + 2.2)], cs[3])
        cv.set(15, CY, cs[4])
        cv.set(13, CY - 3 + (frame % 2), cs[3])
    elif element == 'water':     # a droplet
        glow_head(cv, HEAD - 1.0, CY, 2.5, cs)
        poly(cv, [(17.2, CY), (14, CY - 2.0), (14, CY + 2.0)], cs[3])
        cv.set(int(HEAD) - 1, CY - 1, cs[4])
    elif element == 'light':     # a four-point star
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            line(cv, int(HEAD), CY, int(HEAD) + dx * 4, CY + dy * 4, cs[3])
        glow_head(cv, HEAD, CY, 2.3, cs)
        for dx, dy in ((2, 2), (-2, 2), (2, -2), (-2, -2)):
            cv.set(int(HEAD) + dx, CY + dy, cs[2])
    elif element == 'dark':      # a void orb with a bright rim and a black heart
        disc(cv, HEAD, CY, 4.4, rgba(cs[2], 55))
        disc(cv, HEAD, CY, 3.5, cs[3])
        disc(cv, HEAD, CY, 2.6, cs[1])
        disc(cv, HEAD + 0.6, CY, 1.8, cs[0])
        cv.set(int(HEAD) - 2, CY - 2, cs[4])
        cv.set(int(HEAD) - 1, CY - 3, cs[4])
    else:                        # martial: a throwing knife
        line(cv, 6, CY, 16, CY, cs[3])
        line(cv, 7, CY - 1, 14, CY - 1, cs[2])
        poly(cv, [(17.4, CY), (14, CY - 1.8), (14, CY + 1.8)], cs[4])
        for dy in (-2, -1, 1, 2):
            cv.set(5, CY + dy, cs[1])
        cv.set(4, CY, cs[2])
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
                tail_t = (ang + 1.15) / (2.3 * sweep + 1e-6)
                if thick > 0.15 + 0.5 * (1.0 - tail_t):
                    cv.set(x, y, (255, 255, 255, int(alpha * min(1.0, 0.4 + tail_t))))
    return cv


def rune_ring(frame, element=None):
    """A ground rune circle (white; code tints it): two rings, ticks turning between them, four nodes turning the other
    way and, for an element, its glyph from style.py in the middle."""
    cv = Canvas(40, 40)
    c = 19.5
    spin = frame * (math.tau / 24)
    for r, a in [(18.5, 210), (13.0, 150)]:
        for k in range(130):
            ang = k / 130 * math.tau
            cv.set(int(round(c + math.cos(ang) * r)), int(round(c + math.sin(ang) * r)), (255, 255, 255, a))
    for k in range(12):  # tick marks between the rings: long and short alternating
        ang = k / 12 * math.tau + spin
        r1 = 17.5 if k % 2 == 0 else 16.0
        line(cv, int(c + math.cos(ang) * 14), int(c + math.sin(ang) * 14), int(c + math.cos(ang) * r1), int(c + math.sin(ang) * r1), (255, 255, 255, 230 if k % 2 == 0 else 150))
    for k in range(4):   # nodes on the outer ring turning against the ticks
        ang = k / 4 * math.tau - spin * 1.5 + 0.4
        px, py = int(round(c + math.cos(ang) * 18.5)), int(round(c + math.sin(ang) * 18.5))
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            cv.set(px + dx, py + dy, (255, 255, 255, 255))
    if element is None:  # the generic circle: a triangle glyph
        for k in range(3):
            a0, a1 = k / 3 * math.tau - spin * 0.6, (k + 1) / 3 * math.tau - spin * 0.6
            line(cv, int(c + math.cos(a0) * 8.5), int(c + math.sin(a0) * 8.5), int(c + math.cos(a1) * 8.5), int(c + math.sin(a1) * 8.5), (255, 255, 255, 220))
        return cv
    scale = 8.6
    for pts in style._glyph(element):
        for i in range(len(pts) - 1):
            x0, y0 = pts[i]
            x1, y1 = pts[i + 1]
            line(cv, int(round(c + x0 * scale)), int(round(c + y0 * scale)), int(round(c + x1 * scale)), int(round(c + y1 * scale)), (255, 255, 255, 255))
    return cv


def save(name, frames):
    frames[0].save(os.path.join(OUT, name + '.png'))
    sheet(frames, os.path.join(OUT, name + '_strip.png'))


for element in ELEMENTS:
    save('proj_' + element, [bolt(element, f) for f in range(4)])
enemy_orb = []
for f in range(3):
    cv = Canvas(7, 7)
    ellipse(cv, 3, 3, 2.7 + 0.3 * (f % 2), 2.7 + 0.3 * (f % 2), (255, 255, 255, 255))
    ellipse(cv, 3, 3, 1.1, 1.1, (255, 255, 255, 255))
    enemy_orb.append(cv.outline(style.INK))
save('proj_enemy', enemy_orb)
save('fx_hit', [hit(f) for f in range(5)])
save('fx_slash', [slash(f) for f in range(4)])
save('fx_rune', [rune_ring(f) for f in range(4)])
for element in ELEMENTS:
    save('fx_rune_' + element, [rune_ring(f, element) for f in range(4)])
print('vfx ->', os.path.abspath(OUT))
