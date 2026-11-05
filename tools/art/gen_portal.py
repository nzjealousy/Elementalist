"""Portals -> elementalist/assets/sprites/. Run: python tools/art/gen_portal.py

portal_gate_strip.png   6 frames, 34 x 44: the camp's way into the dungeons, a standing stone ring with a swirling rune gate
door_open_strip.png     4 frames, 16 x 16: an opened room exit (one tile of a doorway), a turning portal pad
door_open.png           the first frame of that strip

Moonlit Glyphwork: the swirl is the air ramp (teal) with a violet rim from the dark ramp, the ring is carved obsidian with
glowing tick marks, one ink outline. Frames loop seamlessly: the two-armed swirl repeats every half turn."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import style
from pixel import Canvas, mix, sheet

style.use("moonlit")
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'sprites')
os.makedirs(OUT, exist_ok=True)

AIR, DARK, STONE = style.ramp("air"), style.ramp("dark"), style.ramp("stone")
INK = style.INK


def swirl_colour(r, ang, t, rmax):
    """The portal's inside at polar (r, ang): two spiral arms turning with t, a bright heart, a violet rim."""
    v = math.sin(2.0 * (ang + r * 0.42 - t))
    heart = 1.0 - r / rmax
    if r < rmax * 0.16:
        return AIR[4]
    if r > rmax * 0.86:
        return DARK[2] if v > 0 else DARK[1]
    if v > 0.55:
        return AIR[3] if heart > 0.35 else AIR[2]
    if v > 0.05:
        return AIR[2] if heart > 0.45 else AIR[1]
    if v > -0.5:
        return DARK[1] if heart < 0.6 else AIR[1]
    return DARK[0]


def gate(frame):
    w, h = 34, 44
    cv = Canvas(w, h)
    cx, cy = 16.5, 20.5
    t = frame * math.pi / 6.0
    # a pool of light on the floor under the ring
    for y in range(h):
        for x in range(w):
            d = math.hypot((x - cx) / 15.0, (y - 40.0) / 3.4)
            if d < 1.0:
                cv.set(x, y, (AIR[2][0], AIR[2][1], AIR[2][2], int(110 * (1.0 - d))))
    # the plinth: two stepped stone slabs
    for y0, hw, tone in ((37, 14, STONE[2]), (40, 16, STONE[1])):
        for y in range(y0, y0 + 3):
            for x in range(int(cx - hw), int(cx + hw) + 1):
                lit = x < cx - hw + 2 or y == y0
                cv.set(x, y, STONE[3] if lit else (STONE[0] if y == y0 + 2 else tone))
    # the ring: a thick carved arch (an ellipse band), lit from the upper left
    rx_o, ry_o, rx_i, ry_i = 14.5, 19.0, 11.0, 15.5
    for y in range(h):
        for x in range(w):
            ox = (x - cx) / rx_o
            oy = (y - cy) / ry_o
            ix = (x - cx) / rx_i
            iy = (y - cy) / ry_i
            if ox * ox + oy * oy <= 1.0 and ix * ix + iy * iy > 1.0:
                lam = -(ox * 0.5 + oy * 0.7)
                cv.set(x, y, STONE[3] if lam > 0.55 else (STONE[2] if lam > 0.0 else (STONE[1] if lam > -0.55 else STONE[0])))
    for k in range(16):    # glowing rune ticks carved round the ring
        a = math.tau * k / 16
        px = int(round(cx + math.cos(a) * 12.9))
        py = int(round(cy + math.sin(a) * 17.2))
        lit = (k + frame // 2) % 4 == 0
        cv.set(px, py, AIR[4] if lit else AIR[2])
        if lit:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                c = cv.get(px + dx, py + dy)
                if c[3]:
                    cv.set(px + dx, py + dy, mix(c, AIR[2], 0.4))
    # the swirl
    for y in range(h):
        for x in range(w):
            ix = (x - cx) / rx_i
            iy = (y - cy) / ry_i
            if ix * ix + iy * iy <= 1.0:
                dx, dy = (x - cx) / 11.0, (y - cy) / 15.5
                r = math.hypot(dx, dy)
                cv.set(x, y, swirl_colour(r * 14.0, math.atan2(dy, dx), t, 14.0))
    for k in range(4):     # motes rising out of the gate
        a = frame * 1.3 + k * 1.7
        mx = int(cx + math.sin(a * 1.7 + k) * 7)
        my = int(cy + 14 - ((frame * 3 + k * 9) % 34))
        if cv.get(mx, my)[3] == 255:
            cv.set(mx, my, AIR[4])
    return cv.outline(INK)


def pad(frame):
    """One tile of an open doorway: a dark floor with a swirling disc."""
    cv = Canvas(16, 16, STONE[0])
    t = frame * math.pi / 4.0
    for y in range(16):
        for x in range(16):
            dx, dy = x - 7.5, y - 7.5
            r = math.hypot(dx, dy)
            if r <= 7.4:
                cv.set(x, y, swirl_colour(r, math.atan2(dy, dx), t, 7.4))
            elif r <= 8.6:
                cv.set(x, y, mix(STONE[0], AIR[2], 0.35))
    for i in range(16):    # a thin lit rim on the tile's edge, so two tiles read as one doorway
        cv.set(i, 0, mix(STONE[0], AIR[2], 0.5))
        cv.set(i, 15, mix(STONE[0], AIR[2], 0.5))
    return cv


frames = [gate(f) for f in range(6)]
frames[0].save(os.path.join(OUT, 'portal_gate.png'))
sheet(frames, os.path.join(OUT, 'portal_gate_strip.png'))
pads = [pad(f) for f in range(4)]
pads[0].save(os.path.join(OUT, 'door_open.png'))
sheet(pads, os.path.join(OUT, 'door_open_strip.png'))
print('portals ->', os.path.abspath(OUT))
