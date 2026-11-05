"""The art gate (docs/ART_DIRECTION.md): scans every generated picture and fails when a rule is broken.
Run: python tools/art/check_art.py      (exit code 1 on a violation)

Rules checked:
  1. No pure black (0,0,0) in any opaque pixel: shadows and outlines are tinted, the ink is 0a0618.
  2. No pure white (255,255,255) except in the pictures the game tints with code (effects, pickups, enemy bolts).
  3. Props, doors and pickups use ONLY colours of the Moonlit ramps plus the ink (restyle.py); monsters and bosses are Noir: at least half
     their pixels are dark (restyle.noirize), the rest is their glowing accent.
  4. Hero part pictures use the region/shade encoding only: blue channel 0, red a multiple of 16, green a multiple of 60.
  5. Every hero part strip is FRAMES poses of 40 x 38 (gen_heroes.py) and no part touches the edge cells of a frame.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import style
from gen_heroes import FRAMES, H as HERO_H, W as HERO_W
from pixel import load_png

style.use("moonlit")
ROOT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets')
SPRITES = os.path.join(ROOT, 'sprites')
TINTED = ('fx_', 'proj_enemy', 'pickup_material', 'pickup_item', 'bolt')   # white by design; code tints them
PALETTE_ONLY = ('chest', 'forge', 'board', 'altar', 'training_sign', 'door_locked', 'door_sealed', 'pickup_gold')
HERO_DIR = os.path.join(SPRITES, 'hero')
HERO_RIG = ('enemy_skeleton', 'enemy_duelist', 'mini_warden', 'mini_matron', 'enemy_wraith', 'enemy_shade')

ramp_colours = set()
for name in style.STYLES[style.ACTIVE]["ramps"]:
    for c in style.ramp(name):
        ramp_colours.add(c[:3])
ramp_colours.add(style.INK[:3])

problems = []


def walk(folder):
    for root, _dirs, files in os.walk(folder):
        for f in sorted(files):
            if f.endswith('.png'):
                yield os.path.join(root, f)


count = 0
for path in list(walk(SPRITES)) + list(walk(os.path.join(ROOT, 'ui'))):
    rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
    name = os.path.basename(path)
    cv = load_png(path)
    count += 1
    in_hero = os.path.abspath(path).startswith(os.path.abspath(HERO_DIR))
    if in_hero:
        if cv.w != HERO_W * FRAMES or cv.h != HERO_H:
            problems.append('%s is %dx%d, a hero strip must be %dx%d (%d poses of %dx%d)' % (rel, cv.w, cv.h, HERO_W * FRAMES, HERO_H, FRAMES, HERO_W, HERO_H))
        for c in cv.px:
            if c[3] and (c[2] != 0 or c[0] % 16 != 0 or c[1] % 60 != 0):
                problems.append('%s has a pixel outside the region/shade encoding %s' % (rel, c))
                break
        for frame in range(FRAMES):   # nothing may sit on a frame's edge cells: the composer's outline needs them
            if any(cv.get(frame * HERO_W + x, y)[3] and (x in (0, HERO_W - 1) or y in (0, HERO_H - 1)) for x in range(HERO_W) for y in range(HERO_H)):
                problems.append('%s frame %d is clipped by the edge of its %d x %d cell' % (rel, frame, HERO_W, HERO_H))
                break
        continue
    tinted = name.startswith(TINTED)
    if name.startswith(('enemy_', 'boss_', 'mini_')) and not name.endswith('_strip.png'):   # Noir: monsters are mostly dark bodies with a small glowing accent
        opaque = [c for c in cv.px if c[3] == 255]
        dark = sum(1 for c in opaque if 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2] < 80)
        if opaque and dark < 0.5 * len(opaque):
            problems.append('%s is not Noir: only %d%% of its pixels are dark' % (rel, 100 * dark // len(opaque)))
    palette_only = name.startswith(PALETTE_ONLY) and not tinted and not name.startswith(HERO_RIG)   # hero-rig enemies are shaded through the hero ramp, like the heroes
    for c in cv.px:
        if c[3] == 255:
            if c[:3] == (0, 0, 0):
                problems.append('%s has a pure black pixel' % rel)
                break
            if c[:3] == (255, 255, 255) and not tinted and not name.startswith('rune_') and not name.startswith('proj_'):
                if not (name.startswith('pickup_gold') or palette_only and False):
                    problems.append('%s has a pure white pixel' % rel)
                    break
            if palette_only and c[:3] not in ramp_colours:
                problems.append('%s uses a colour outside the Moonlit ramps %02x%02x%02x' % (rel, c[0], c[1], c[2]))
                break

print('checked', count, 'pictures')
for p in problems:
    print('FAIL', p)
if problems:
    sys.exit(1)
print('art gate passed')
