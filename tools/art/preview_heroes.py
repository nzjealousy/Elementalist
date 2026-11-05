"""Composes the hero parts the way the game does (scripts/character/hero_composer.gd, Noir Silhouette colouring from noir.py) and writes
contact sheets: tools/art/preview_heroes.png (every class facing down, each with a different element glowing) and
tools/art/preview_poses.png (one hero in every pose and every facing).
Run: python tools/art/preview_heroes.py   (then look at the PNGs)
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import gen_heroes as gh  # noqa: E402
import noir  # noqa: E402
from pixel import Canvas  # noqa: E402

DATA = json.load(open(os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'data', 'hero_looks.json')))
W, H = gh.OUT_W, gh.OUT_H   # the saved (baked 15% smaller) cell, as the game composes it

_cache = {}


def part_frames(name, builder):
    """{facing: [grid]} of a part as saved: each pose baked to the OUT_W x OUT_H cell."""
    if name not in _cache:
        _cache[name] = {facing: [rc.shrunk() for rc in frames] for facing, frames in gh.for_all(builder).items()}
    return _cache[name]


BUILDERS = {
    'base_body': lambda v: gh.base_body,
    'boots': gh.boots, 'outfit': gh.outfit, 'hair': gh.hair, 'head': gh.headgear,
    'back': gh.back, 'accent': gh.accent, 'weapon': gh.weapon,
}
GLOWS = {'fire': 'ff8040', 'water': '5cc8ff', 'air': '9cf0d8', 'mineral': 'f8d060', 'earth': '88e880', 'light': 'e8e0ff', 'dark': 'b868ff'}


def resolve(cls, sub='', armor='', helm='', boots='', weapon_kind='', weapon_prefix='', skin=0, hair_color=1, glow=None):
    c = DATA['classes'][cls]
    look = {k: c[k] for k in ('outfit', 'hair', 'head', 'back', 'boots', 'weapon')}
    pal = dict(c['palette'])
    look['accent'] = ''
    if sub:
        s = DATA['subclasses'][sub]
        look['accent'] = s.get('accent', '')
        for k in ('head', 'back'):
            if k in s:
                look[k] = s[k]
        pal.update(s.get('palette', {}))
    if armor:
        a = DATA['armor'][armor]
        look['outfit'] = a['outfit']
        pal.update(a['palette'])
    if helm:
        h = DATA['helms'][helm]
        look['head'] = h['head']
        pal.update(h['palette'])
    if boots:
        b = DATA['boots'][boots]
        look['boots'] = b['boots']
        pal.update(b['palette'])
    if weapon_kind:
        look['weapon'] = weapon_kind
    mat = DATA['weapons'].get(weapon_prefix or 'worn')
    pal['metal'] = mat['metal']
    pal['wood'] = mat['wood']
    pal['skin'] = DATA['skin_tones'][skin]
    pal['hair'] = DATA['hair_colors'][hair_color]
    pal['glow'] = glow or noir.DEFAULT_GLOW
    return look, pal


def layer_list(look, facing):
    out = []
    if look['back']:
        out.append(('back', look['back']))
    if facing == 'up':
        out.append(('weapon', look['weapon']))
    out.append(('base_body', ''))
    out.append(('boots', look['boots']))
    out.append(('outfit', look['outfit']))
    if look['accent']:
        out.append(('accent', look['accent']))
    if look['hair']:
        out.append(('hair', look['hair']))
    if look['head']:
        out.append(('head', look['head']))
    if facing != 'up':
        out.append(('weapon', look['weapon']))
    return out


def compose(look, pal, facing, frame):
    grid = [[None] * W for _ in range(H)]
    for part, variant in layer_list(look, facing):
        key = part + ('_' + variant if variant else '')
        frames = part_frames(key, gh.base_body if part == 'base_body' else BUILDERS[part](variant))
        g = frames[facing][frame]
        for y in range(H):
            for x in range(W):
                if g[y][x] is not None:
                    grid[y][x] = g[y][x]
    return paint(grid, pal)


def paint(grid, pal):
    """A grid of (region, shade) coloured the Noir way, with the rim light and the outline (any size)."""
    H, W = len(grid), len(grid[0])
    out = Canvas(W, H)
    for y in range(H):
        for x in range(W):
            cell = grid[y][x]
            if cell is not None:
                out.set(x, y, noir.colour(cell[0], cell[1], pal))
    for y in range(H):  # the hard rim light on the upper-left edge
        for x in range(W):
            cell = grid[y][x]
            if cell is None or cell[0] == 14 or cell[1] < 2:
                continue
            if x == 0 or grid[y][x - 1] is None or y == 0 or grid[y - 1][x] is None:
                out.set(x, y, noir.rim(out.get(x, y), pal['glow']))
    for y in range(H):  # a nearly black outline tinted by what it borders
        for x in range(W):
            if grid[y][x] is not None:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and grid[ny][nx] is not None:
                    out.set(x, y, noir.colour(grid[ny][nx][0], 0, pal))
                    break
    return out


def scaled(cv, k):
    out = Canvas(cv.w * k, cv.h * k)
    for y in range(cv.h):
        for x in range(cv.w):
            c = cv.get(x, y)
            if c[3]:
                for j in range(k):
                    for i in range(k):
                        out.set(x * k + i, y * k + j, c)
    return out


def crop(cv, x0, w):
    out = Canvas(w, cv.h)
    for y in range(cv.h):
        for x in range(w):
            out.px[y * w + x] = cv.get(x0 + x, y)
    return out


def main():
    k = 3
    bg = (24, 22, 44, 255)
    cellw = gh.OUT_CELL + 4
    names = list(DATA['classes'])
    glows = list(GLOWS.values())
    cells = [resolve(cls, glow=glows[i % len(glows)]) for i, cls in enumerate(names)]
    sheet1 = Canvas(len(cells) * cellw * k + 8, H * k + 8, bg)
    for i, (look, pal) in enumerate(cells):
        sheet1.blit(scaled(crop(compose(look, pal, 'down', 4), gh.OUT_OX - 2, cellw), k), 4 + i * cellw * k, 4)
    sheet1.save(os.path.join(os.path.dirname(__file__), 'preview_heroes.png'))
    look, pal = resolve('channeler', 'spellweaver', glow=GLOWS['fire'])
    n = gh.FRAMES
    sheet2 = Canvas(n * W * 2 + 8, 3 * H * 2 + 8, bg)
    for r, facing in enumerate(('down', 'up', 'side')):
        for f in range(n):
            sheet2.blit(scaled(compose(look, pal, facing, f), 2), 4 + f * W * 2, 4 + r * H * 2)
    sheet2.save(os.path.join(os.path.dirname(__file__), 'preview_poses.png'))
    print('wrote previews', sheet1.w, sheet1.h, sheet2.w, sheet2.h)


if __name__ == '__main__':
    main()
