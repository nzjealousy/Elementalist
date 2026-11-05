"""Bakes the 15% reduction into pictures, so the game draws every sprite at scale 1 and every pixel is a real pixel.

The hero rig (gen_heroes.py) is drawn on its 40 x 38 grid and saved as 34 x 32 cells; monsters, bosses and mini bosses (gen_sprites.py)
are drawn at their old size and saved 85% as big. Plain resampling would blur the colours or the region/shade codes of the hero parts,
and nearest-neighbour drops whole rows, so each destination pixel takes the 1 to 4 source pixels whose centres fall inside it (every
source pixel lands in exactly one destination pixel, so a 1 px line is never skipped) and keeps ONE of them, never a mix:

  * it is opaque when at least half of them are; on an even split it stays empty only when the empty cells are a gap inside the shape
    (rarer around the box than filled ones), so silhouettes and thin lines survive and slits between limbs stay open;
  * the kept value is the most important one present (eyes, then gems, then glints, then dark holes), else the most common, else the
    one that is rarer around the box (a detail beats the fill it sits on);
  * a clean-up pass drops pixels the reduction left floating alone and fills single-pixel pinholes it opened.

`pairs` name the rows (or columns) that merge, so a rig can keep them out of the face; by default they are spread evenly.
"""


def boxes(n_src, n_dst, pairs=None):
    """[[source indices] per destination index]: by default each source index goes to the destination its centre falls in."""
    if pairs is None:
        out = [[] for _ in range(n_dst)]
        for i in range(n_src):
            out[((2 * i + 1) * n_dst) // (2 * n_src)].append(i)
        return out
    assert len(pairs) == n_src - n_dst, 'need %d merged pairs' % (n_src - n_dst)
    starts = {a for a, _b in pairs}
    out, i = [], 0
    while i < n_src:
        out.append([i, i + 1] if i in starts else [i])
        i += 2 if i in starts else 1
    return out


def _ring(get, xs, ys):
    """The cells just around a box (out of bounds counts as empty)."""
    for y in range(ys[0] - 1, ys[-1] + 2):
        for x in range(xs[0] - 1, xs[-1] + 2):
            if not (xs[0] <= x <= xs[-1] and ys[0] <= y <= ys[-1]):
                yield get(x, y)


def reduce(get, w, h, w2, h2, prio, empty=None, cols=None, rows=None):
    """The generic reduction: get(x, y) -> a value or `empty`; prio(value) -> int (higher survives). Returns rows of values."""
    bx, by = boxes(w, w2, cols), boxes(h, h2, rows)
    out = [[empty] * w2 for _ in range(h2)]
    dropped = set()     # destination pixels left empty although some of their source was filled
    for y2, ys in enumerate(by):
        for x2, xs in enumerate(bx):
            cells = [get(x, y) for y in ys for x in xs]
            filled = [c for c in cells if c != empty]
            if not filled:
                continue
            if 2 * len(filled) < len(cells):
                dropped.add((x2, y2))
                continue
            if 2 * len(filled) == len(cells) and len(cells) > 1:
                around = list(_ring(get, xs, ys))
                holes = sum(1 for c in around if c == empty)
                if holes < len(around) - holes:     # the empty half is a slit inside the shape: keep it open
                    dropped.add((x2, y2))
                    continue
            kinds = set(filled)
            if len(kinds) == 1:
                out[y2][x2] = filled[0]
                continue
            around = list(_ring(get, xs, ys))
            out[y2][x2] = max(kinds, key=lambda c: (prio(c), filled.count(c), -around.count(c)))
    _clean(out, w2, h2, prio, empty, dropped)
    return out


def _clean(g, w, h, prio, empty, dropped):
    def at(x, y):
        return g[y][x] if 0 <= x < w and 0 <= y < h else empty
    for y in range(h):
        for x in range(w):
            c = g[y][x]
            if c != empty and prio(c) < 3 and all(at(x + dx, y + dy) == empty for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy):
                g[y][x] = empty                     # a stray pixel the reduction left floating alone
            elif (x, y) in dropped:
                n = [at(x + 1, y), at(x - 1, y), at(x, y + 1), at(x, y - 1)]
                if all(v != empty for v in n):      # a pinhole the reduction opened: it would show as an outline dot
                    g[y][x] = max(set(n), key=n.count)


# ------------------------------------------------------------------------------------------- hero parts: (region, shade) codes
def code_prio(c):
    region, shade = c
    if region == 14:
        return 4    # eyes
    if region == 13:
        return 3    # gems
    if shade == 4:
        return 2    # glints
    if shade == 0:
        return 1    # dark holes (sockets, mouths)
    return 0


def shrink_codes(grid, w2, h2, cols=None, rows=None):
    """A grid (rows of (region, shade) or None) reduced to w2 x h2."""
    h, w = len(grid), len(grid[0])

    def get(x, y):
        return grid[y][x] if 0 <= x < w and 0 <= y < h else None
    return reduce(get, w, h, w2, h2, code_prio, None, cols, rows)


# ------------------------------------------------------------------------------------------- finished RGBA pictures
def _luma(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def rgba_prio(c):
    hi, lo = max(c[:3]), min(c[:3])
    if hi > 170 and hi - lo > 70:
        return 2    # a glowing colour (eyes, gems, fire)
    if _luma(c) < 40:
        return 1    # the dark outline and holes
    return 0


def shrink_canvas(cv, k=0.85):
    """A finished picture (pixel.Canvas) `k` times as big (rounded), each pixel one of the source colours."""
    from pixel import Canvas
    w2, h2 = max(1, round(cv.w * k)), max(1, round(cv.h * k))

    def get(x, y):
        if 0 <= x < cv.w and 0 <= y < cv.h:
            c = cv.px[y * cv.w + x]
            return c if c[3] else None
        return None
    g = reduce(get, cv.w, cv.h, w2, h2, rgba_prio, None)
    out = Canvas(w2, h2)
    for y in range(h2):
        for x in range(w2):
            if g[y][x] is not None:
                out.px[y * w2 + x] = g[y][x]
    return out


if __name__ == '__main__':      # self-check: a 1 px line survives, eyes beat skin, sizes are right
    line = [[(3, 2) if x == 5 else None for x in range(12)] for _ in range(12)]
    out = shrink_codes(line, 10, 10)
    assert sum(1 for row in out for c in row if c) >= 9, out
    face = [[(1, 2)] * 6 for _ in range(6)]
    face[2][2] = (14, 2)
    out = shrink_codes(face, 5, 5)
    assert any(c == (14, 2) for row in out for c in row)
    assert [len(b) for b in boxes(38, 32, [(1, 2), (5, 6), (16, 17), (21, 22), (27, 28), (32, 33)])].count(2) == 6
    print('shrink ok')
