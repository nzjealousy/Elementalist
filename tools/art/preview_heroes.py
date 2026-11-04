"""Composes the hero parts the way the game does (scripts/character/hero_composer.gd) and writes a contact sheet to
tools/art/preview_heroes.png: every class, then every subclass, facing down; then one class in all facings/frames.
Run: python tools/art/preview_heroes.py   (then look at the PNG)
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import gen_heroes as gh  # noqa: E402
from pixel import Canvas, hexc  # noqa: E402

DATA = json.load(open(os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'data', 'hero_looks.json')))
RAMP = DATA['ramp']
W, H = gh.W, gh.H
REGION_KEY = {1: 'skin', 2: 'hair', 3: 'outfit', 4: 'trim', 5: 'pants', 6: 'boots', 7: 'head', 8: 'headtrim', 9: 'cape',
              10: 'accent', 11: 'metal', 12: 'wood', 13: 'gem'}

_cache = {}


def part_frames(name, builder):
    if name not in _cache:
        _cache[name] = gh.for_all(builder)
    return _cache[name]


BUILDERS = {
    'base_body': lambda v: gh.base_body,
    'boots': gh.boots, 'outfit': gh.outfit, 'hair': gh.hair, 'head': gh.headgear,
    'back': gh.back, 'accent': gh.accent, 'weapon': gh.weapon,
}


def resolve(cls, sub='', armor='', helm='', boots='', weapon_kind='', weapon_prefix='', skin=0, hair_color=1):
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


def color_of(region, shade, pal):
    if region == 14:
        return (30, 22, 44, 255)
    if region == 15:
        base = (252, 248, 240)
    else:
        base = tuple(hexc(pal[REGION_KEY[region]])[:3])
    if shade == 0:
        return tuple(min(255, int(base[i] * RAMP['outline_mul'] + RAMP['outline_add'][i])) for i in range(3)) + (255,)
    if shade == 4:
        hc = RAMP['highlight_color']
        m = RAMP['highlight_mix']
        return tuple(int(base[i] + (hc[i] - base[i]) * m) for i in range(3)) + (255,)
    if shade == 3:
        return tuple(min(255, int(base[i] * RAMP['light_mul'])) for i in range(3)) + (255,)
    if shade == 1:
        sc = RAMP['shadow_color']
        m = RAMP['shadow_mix']
        d = [base[i] * RAMP['dark_mul'] for i in range(3)]
        return tuple(int(d[i] + (sc[i] - d[i]) * m) for i in range(3)) + (255,)
    return base + (255,)


def compose(look, pal, facing, frame):
    grid = [[None] * W for _ in range(H)]
    for part, variant in layer_list(look, facing):
        key = part + ('_' + variant if variant else '')
        if part == 'base_body':
            frames = part_frames(key, gh.base_body)
        else:
            frames = part_frames(key, BUILDERS[part](variant))
        rc = frames[facing][frame]
        for y in range(H):
            for x in range(W):
                if rc.g[y][x] is not None:
                    grid[y][x] = rc.g[y][x]
    out = Canvas(W, H)
    for y in range(H):
        for x in range(W):
            cell = grid[y][x]
            if cell is not None:
                out.set(x, y, color_of(cell[0], cell[1], pal))
    for y in range(H):  # outline
        for x in range(W):
            if grid[y][x] is not None:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and grid[ny][nx] is not None:
                    out.set(x, y, color_of(grid[ny][nx][0], 0, pal))
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


def main():
    k = 3
    cells = []
    for cls in DATA['classes']:
        cells.append(resolve(cls))
    for cls in DATA['classes']:
        for sub in [s for s in DATA['subclasses'] if True]:
            pass
    sub_of = {'channeler': ['spellweaver', 'warden'], 'vanguard': ['duelist', 'bulwark'], 'ranger': ['sharpshooter', 'pathfinder'],
              'mystic': ['oracle', 'spiritblade'], 'assassin': ['nightstalker', 'trickster'], 'berserker': ['warlord', 'reaver'],
              'sage': ['archmage', 'lorekeeper'], 'druid': ['grovekeeper', 'stormcaller']}
    for cls, subs in sub_of.items():
        for sub in subs:
            cells.append(resolve(cls, sub))
    cols = 9
    rows = (len(cells) + cols - 1) // cols
    sheet_cv = Canvas(cols * W * k + 8, (rows + 2) * H * k + 8, (44, 52, 40, 255))
    for i, (look, pal) in enumerate(cells):
        cv = scaled(compose(look, pal, 'down', 0), k)
        sheet_cv.blit(cv, 4 + (i % cols) * W * k, 4 + (i // cols) * H * k)
    # all facings and frames of the sage and the vanguard with a chain mail and iron helm
    for r, (look, pal) in enumerate([resolve('channeler', 'spellweaver'), resolve('vanguard', 'bulwark', 'chain_mail', 'iron_helm', 'runner_boots', 'sword', 'iron')]):
        for j, facing in enumerate(('down', 'up', 'side')):
            for f in range(4):
                cv = scaled(compose(look, pal, facing, f), k)
                sheet_cv.blit(cv, 4 + (j * 4 + f) * W * k - (0 if j * 4 + f < cols else 0), 4 + (rows + r) * H * k)
    path = os.path.join(os.path.dirname(__file__), 'preview_heroes.png')
    sheet_cv.save(path)
    print('wrote', path, sheet_cv.w, sheet_cv.h)


if __name__ == '__main__':
    main()
