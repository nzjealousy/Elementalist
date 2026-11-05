"""Humanoid enemies drawn on the hero rig -> elementalist/assets/sprites/<id>.png + <id>_strip.png. Run: python tools/art/gen_enemies.py

Skeleton archer, bone duelist, grave warden, ember matron, wraith and shade share the hero's anatomy (gen_heroes.py: a head about a quarter
of the height, a neck, shoulders, arms ending in hands, legs ending in shoes, 24 x 38 with a 1 px margin) and the hero's shading
(region + shade pixels painted through the hero_looks.json ramp: pale highlights, cold shadows, a moonlit rim on the upper-left edge and
a selective outline). They are drawn facing the viewer in four walking frames (the game flips them to face left or right). Their hit
boxes are NOT the picture: scripts/combat/enemy.gd keeps the sizes of the smaller drawings they replaced (BODY_SIZES).

Parts that only enemies have (skull, ribcage, bone limbs, shield, flame crown, ghost cloak) live here; everything else is a hero part.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import gen_heroes as gh
import preview_heroes as ph
from gen_heroes import (ACCENT, BOB, BOOT, CAPE, EYE, FOOT, GEM, HAIR, HAT, HATTRIM, HEAD_Y, HIP, METAL, OUTFIT, PANTS, RC, SHOULDER, SKIN,
                        STEP, TRIM, WHITE, WOOD, H, W)
from pixel import Canvas, sheet

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'sprites')


# ------------------------------------------------------------------------------------------ enemy-only parts
def skull(rc, f, bob, step):
    cy = HEAD_Y + bob
    rc.ellipse(11.5, cy - 0.3, 5.0, 5.0, SKIN)                          # cranium
    rc.poly([(8, cy + 3), (15, cy + 3), (14, cy + 6), (9, cy + 6)], SKIN)  # jaw
    for ex in (8, 14):                                                   # eye sockets with a faint glow
        rc.rect(ex, cy - 1, 2, 3, EYE, shaded=False)
        rc.px(ex + (1 if ex == 8 else 0), cy, GEM, 4)
    rc.px(11, cy + 2, EYE, 2)                                            # nose hole
    rc.px(12, cy + 2, EYE, 2)
    for x in range(9, 15):                                               # teeth
        rc.px(x, cy + 4, WHITE if x % 2 else EYE, 3 if x % 2 else 2)
    rc.px(8, cy + 1, SKIN, 4)                                            # a cheekbone in the light
    rc.px(9, cy - 4, SKIN, 4)
    rc.px(10, cy - 4, SKIN, 4)
    rc.px(13, cy + 2, SKIN, 1)
    rc.px(11, cy + 6, EYE, 2)                                            # the neck bones
    rc.px(12, cy + 6, EYE, 2)


def bones(rc, f, bob, step, rags=True):
    top = SHOULDER + bob
    rc.rect(11, top - 1, 2, 2, SKIN, shaded=False)                       # spine
    rc.px(11, top - 1, SKIN, 1)
    rc.rect(7, top, 10, 1, SKIN)                                         # collarbones
    rc.rect(5, top, 3, 2, SKIN)                                          # shoulder joints
    rc.rect(16, top, 3, 2, SKIN)
    rc.poly([(8, top + 1), (16, top + 1), (15, top + 9), (9, top + 9)], SKIN, 'dark')   # the open chest in shadow
    for y in range(top + 1, top + 10):                                    # a spine column
        rc.px(11, y, SKIN, 3 if y % 2 else 2)
        rc.px(12, y, SKIN, 2 if y % 2 else 1)
    for i in range(4):                                                   # ribs, curving down toward the middle
        y = top + 2 + i * 2
        rc.rect(8 + (i == 3), y, 3, 1, SKIN, shaded=False)
        rc.px(8 + (i == 3), y, SKIN, 3)
        rc.rect(13, y, 3 - (i == 3), 1, SKIN, shaded=False)
        rc.px(16 - (i == 3), y - 0, SKIN, 1)
    rc.poly([(8, HIP - 1 + bob), (16, HIP - 1 + bob), (15, HIP + 2 + bob), (9, HIP + 2 + bob)], SKIN)   # pelvis
    rc.rect(11, HIP + bob, 2, 1, EYE, shaded=False)
    # arms: upper bone, elbow knob, forearm, hand
    for ax, ay in gh.arm_boxes('down', bob, step, 2):
        rc.rect(ax, ay, 2, 5, SKIN)
        rc.rect(ax - (1 if ax < 10 else 0), ay + 5, 3, 2, SKIN)         # the elbow
        rc.rect(ax, ay + 7, 2, 4, SKIN)
        rc.rect(ax - 1, ay + 11, 4, 2, SKIN)                            # the hand
        rc.px(ax, ay + 13, SKIN, 1)
        rc.px(ax + 2, ay + 13, SKIN, 1)
    # legs: thigh, knee, shin, foot
    for x, raised in gh.leg_cols('down', step):
        lift = 1 if raised else 0
        bx = x if x < 11 else x + 1
        rc.rect(bx, HIP + 2, 2, 5, SKIN)
        rc.rect(bx - 1, HIP + 7, 4, 2, SKIN)                            # the knee
        rc.rect(bx, HIP + 9, 2, FOOT - 1 - lift - HIP - 9, SKIN)
        rc.rect(bx - 1, FOOT - 1 - lift, 4, 2, SKIN)                    # the foot
    if rags:                                                              # a tattered loincloth
        rc.poly([(8, HIP + 1 + bob), (16, HIP + 1 + bob), (16, HIP + 6 + bob), (8, HIP + 6 + bob)], OUTFIT)
        for x in range(8, 16, 2):
            rc.px(x, HIP + 6 + bob, OUTFIT, 1)
            rc.px(x + 1, HIP + 7 + bob, OUTFIT, 1)


def rapier(rc, f, bob, step):
    hx, hy = gh.hand('down', bob)
    rc.rect(hx, hy - 1, 2, 4, WOOD)
    rc.poly([(hx - 2, hy - 3), (hx + 4, hy - 3), (hx + 3, hy - 5), (hx - 1, hy - 5)], TRIM)                # a cup guard
    rc.rect(hx, hy - 6, 1, 14, METAL)                                                                       # a long thin blade
    rc.line(hx, hy - 6, hx, hy - 19, METAL, 4)
    rc.px(hx, hy - 20, METAL, 4)


def shield(rc, f, bob, step):
    cx, cy = 4.0, 27.0 + bob
    rc.ellipse(cx, cy, 4.2, 5.4, METAL)
    rc.ellipse(cx, cy, 2.6, 3.6, TRIM)
    rc.px(int(cx), int(cy), GEM, 4)
    rc.px(int(cx) - 1, int(cy) - 1, WHITE, 4)


def flame_crown(rc, f, bob, step):
    cy = HEAD_Y + bob
    for i, (x, h) in enumerate(((8, 5), (10, 8), (12, 6), (14, 9), (16, 5))):          # tongues of fire that sway with the frame
        sway = (f + i) % 2
        rc.poly([(x - 1 + sway, cy - 4), (x + 2 + sway, cy - 4), (x + sway, cy - 4 - h)], HAIR, 'light')
        rc.px(x + sway, cy - 4 - h + 2, HAIR, 4)


def fire_orbs(rc, f, bob, step):
    for ax, ay in gh.arm_boxes('down', bob, step, 3):
        gx = ax + 1
        gy = ay + 12
        rc.ellipse(gx + 0.5, gy + 1.5, 2.6, 2.6, GEM)
        rc.px(gx, gy, WHITE, 4)


def hooded_cloak(float_range, tendrils=False):
    """A floating hooded figure with no legs: a hood with a dark face and two glowing eyes, a cloak flaring into a tattered hem."""
    def draw(rc, f, bob, step):
        cy = HEAD_Y + bob
        sway = (0, 1, 0, -1)[f]
        rc.ellipse(11.5, cy - 0.2, 6.4, 6.3, HAT)                                           # the hood
        rc.ellipse(11.5, cy + 1.2, 4.0, 4.4, EYE)                                            # the dark face
        for ex in (9, 13):
            rc.rect(ex, cy + 1, 2, 2, GEM, shaded=False)
            rc.px(ex, cy + 1, WHITE, 4)
        rc.poly([(6, cy + 5), (17, cy + 5), (20 + sway, FOOT - 5), (3 + sway, FOOT - 5)], OUTFIT)   # the cloak, flaring from the shoulders
        rc.poly([(9, cy + 6), (14, cy + 6), (14, FOOT - 5), (9, FOOT - 5)], OUTFIT, 'dark')           # the fold of its front
        for x in range(3 + sway, 21 + sway, 3):                                             # a ragged hem
            depth = 2 + ((x + f) % 3)
            rc.poly([(x, FOOT - 6), (x + 3, FOOT - 6), (x + 1, FOOT - 6 + depth)], OUTFIT)
        rc.rect(7, cy + 5, 10, 1, HATTRIM, shaded=False)                                    # a clasp line at the neck
        rc.px(11, cy + 5, GEM, 4)
        for sx, d in ((5, -1), (18, 1)):                                                    # sleeves flaring out, with pale fingers
            rc.poly([(sx, cy + 6), (sx + 3, cy + 6), (sx + 3 + d * 3 + sway, cy + 15), (sx + d * 3 + sway, cy + 15)], OUTFIT)
            rc.rect(sx + d * 3 + sway, cy + 15, 3, 2, SKIN)
            rc.px(sx + d * 3 + sway + (2 if d > 0 else 0), cy + 17, SKIN, 1)
        if tendrils:
            for x in (6, 10, 14, 18):
                rc.line(x + sway, FOOT - 4, x + sway + ((f + x) % 3) - 1, FOOT - 1, OUTFIT, 1)
    return draw


# ----------------------------------------------------------------------------------------------- composing
def BODY(rc, f, bob, step):
    """The hero's own body (head, face, neck, hands, trousers) seen from the front."""
    gh.base_body(rc, 'down', f, bob, step)


def hero(builder, *args):
    """A hero part (gh.outfit('mail'), gh.headgear('helm') ...) seen from the front."""
    draw = builder(*args)
    return lambda rc, f, bob, step: draw(rc, 'down', f, bob, step)


def composed(layers, palette, bobs=None):
    """The four walking frames of an enemy: layers are drawn in order, then coloured, rimmed and outlined as the hero composer does."""
    frames = []
    for f in range(4):
        bob = (bobs or BOB)[f]
        grid = [[None] * W for _ in range(H)]
        for layer in layers:                                                # each part on its own canvas, as in the game (parts erase their own cells only)
            part = RC()
            layer(part, f, bob, STEP[f])
            for y in range(H):
                for x in range(W):
                    if part.g[y][x] is not None:
                        grid[y][x] = part.g[y][x]
        out = Canvas(W, H)
        for y in range(H):
            for x in range(W):
                cell = grid[y][x]
                if cell is not None:
                    c = ph.color_of(cell[0], cell[1], palette)
                    out.set(x, y, (248, 244, 255, 255) if c[:3] == (255, 255, 255) else c)   # never pure white (the art gate)
        for y in range(H):                                                  # the moonlit rim on the lit edge
            for x in range(W):
                cell = grid[y][x]
                if cell is None or cell[0] == 14 or cell[1] < 2:
                    continue
                if x == 0 or grid[y][x - 1] is None or y == 0 or grid[y - 1][x] is None:
                    c = out.get(x, y)
                    out.set(x, y, tuple(int(c[i] + (ph.RIM[i] - c[i]) * 0.3) for i in range(3)) + (255,))
        for y in range(H):                                                  # the selective outline
            for x in range(W):
                if grid[y][x] is not None:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and grid[ny][nx] is not None:
                        out.set(x, y, ph.color_of(grid[ny][nx][0], 0, palette))
                        break
        frames.append(out)
    return frames


def base_palette(**kw):
    pal = {'skin': 'd8d0c0', 'hair': '3a3a4a', 'outfit': '5c5890', 'trim': 'a098f0', 'pants': '3c3868', 'boots': '30203a', 'head': '5c5890',
           'headtrim': 'a098f0', 'cape': '3c3868', 'accent': 'a098f0', 'metal': 'a098c8', 'wood': '785070', 'gem': '9cf0d8'}
    pal.update(kw)
    return pal


ENEMIES = {
    'enemy_skeleton': ([skull, bones, hero(gh.weapon, 'bow')],
                       base_palette(skin='d8d0c0', outfit='6a5878', gem='9cf0d8', wood='785070', trim='c8b098')),
    'enemy_duelist': ([hero(gh.back, 'cape'), skull, bones, hero(gh.headgear, 'feather'), rapier],
                      base_palette(skin='e0d8c8', outfit='7a1f4a', cape='b02a4a', head='3a3068', headtrim='e0403a', gem='ff8040', metal='d8d0ff', trim='f8d060')),
    'mini_warden': ([BODY,
                     hero(gh.boots, 'boots'), hero(gh.outfit, 'mail'), hero(gh.accent, 'pauldrons'), hero(gh.headgear, 'helm'),
                     hero(gh.weapon, 'sword'), shield],
                    base_palette(skin='7aa898', outfit='4a6a78', trim='9cb0c8', accent='6a8aa0', head='5c7890', headtrim='9cb0c8', boots='24304a',
                                 pants='34485a', metal='c8d0e8', gem='9cf0d8', wood='503450')),
    'mini_matron': ([BODY,
                     hero(gh.boots, 'shoes'), hero(gh.outfit, 'robe'), hero(gh.hair, 'long'), hero(gh.accent, 'collar'), flame_crown, fire_orbs],
                    base_palette(skin='e8b098', hair='ff8040', outfit='c8402a', trim='f8d060', accent='f8d060', cape='7a1f4a', boots='501a30',
                                 pants='7a1f4a', gem='ffd8a0')),
    'enemy_wraith': ([hooded_cloak(1)],
                     base_palette(skin='b8b0e0', outfit='6858b0', head='8878c8', headtrim='d8d0ff', gem='9cf0d8')),
    'enemy_shade': ([hooded_cloak(1, tendrils=True)],
                    base_palette(skin='584878', outfit='241c44', head='30284c', headtrim='5c5890', gem='ff4a60')),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (layers, palette) in ENEMIES.items():
        bobs = (0, 1, 2, 1) if name in ('enemy_wraith', 'enemy_shade') else None   # ghosts float up and down a little more
        frames = composed(layers, palette, bobs)
        frames[0].save(os.path.join(OUT, name + '.png'))
        sheet(frames, os.path.join(OUT, name + '_strip.png'))
    print('humanoid enemies ->', os.path.abspath(OUT), len(ENEMIES), 'drawn')


if __name__ == '__main__':
    main()
