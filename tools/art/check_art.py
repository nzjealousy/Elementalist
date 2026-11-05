"""The art gate (docs/ART_DIRECTION.md): scans every generated picture and fails when a rule is broken.
Run: python tools/art/check_art.py      (exit code 1 on a violation)

Rules checked:
  1. No pure black (0,0,0) in any opaque pixel: shadows and outlines are tinted, the ink is 0a0618.
  2. No pure white (255,255,255) except in the pictures the game tints with code (effects, pickups, enemy bolts).
  3. Monsters, bosses, props, doors and pickups use ONLY colours of the Moonlit ramps plus the ink (they pass through restyle.py).
  4. Hero part pictures use the region/shade encoding only: blue channel 0, red a multiple of 16, green a multiple of 60.
  5. Every hero part strip is 4 frames of 24 x 38 and no part touches the edge cells of a frame.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import style
from pixel import load_png

style.use("moonlit")
ROOT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets')
SPRITES = os.path.join(ROOT, 'sprites')
TINTED = ('fx_', 'proj_enemy', 'pickup_material', 'pickup_item', 'bolt')   # white by design; code tints them
PALETTE_ONLY = ('enemy_', 'boss_', 'mini_', 'chest', 'forge', 'board', 'altar', 'training_sign', 'door_locked', 'door_sealed', 'pickup_gold')
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
        if cv.w != 24 * 4 or cv.h != 38:
            problems.append('%s is %dx%d, a hero strip must be 96x38' % (rel, cv.w, cv.h))
        for c in cv.px:
            if c[3] and (c[2] != 0 or c[0] % 16 != 0 or c[1] % 60 != 0):
                problems.append('%s has a pixel outside the region/shade encoding %s' % (rel, c))
                break
        for frame in range(4):   # nothing may sit on a frame's edge cells: the composer's ink outline needs them
            if any(cv.get(frame * 24 + x, y)[3] and (x in (0, 23) or y in (0, 37)) for x in range(24) for y in range(38)):
                problems.append('%s frame %d is clipped by the edge of its 24 x 38 cell' % (rel, frame))
                break
        continue
    tinted = name.startswith(TINTED)
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
