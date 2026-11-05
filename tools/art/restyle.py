"""The Moonlit Glyphwork pass: snaps a sprite's colours onto the style's ramps, redraws its outline as the one ink line
and lights its upper-left edge. Older generators (monsters, props) call `restyle(canvas)` on a finished sprite, so every
picture in the game shares one palette, one outline and one light direction without each script being rewritten.

    import restyle
    cv = restyle.restyle(cv)    # a new canvas, same size
    restyle.install()           # or: every Canvas.save() in this run is restyled

Rules (docs/ART_DIRECTION.md): colours come from `style.STYLES["moonlit"]["ramps"]`, nothing is pure black, the outline is
`style.INK`, the lit edge (upper left) is one ramp step brighter, translucent pixels keep their alpha."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import noir  # noqa: E402
import pixel  # noqa: E402
import style  # noqa: E402
from pixel import Canvas  # noqa: E402

style.use("moonlit")

_PALETTE = None


def palette():
    """[(ramp name, step index, (r, g, b))] for every colour the style owns."""
    global _PALETTE
    if _PALETTE is None:
        _PALETTE = []
        for name in style.STYLES[style.ACTIVE]["ramps"]:
            if name == "skin":    # skin is only for the heroes' own faces; bone and flesh-coloured props use the cool ramps
                continue
            for i, c in enumerate(style.ramp(name)):
                _PALETTE.append((name, i, c[:3]))
    return _PALETTE


def _dist(a, b):
    """Redmean colour distance: cheap and much closer to what the eye sees than plain RGB."""
    rm = (a[0] + b[0]) / 2.0
    dr, dg, db = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return (2 + rm / 256.0) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256.0) * db * db


_CACHE = {}


def nearest(rgb):
    """(ramp name, step) closest to a colour."""
    key = rgb[:3]
    if key not in _CACHE:
        best = min(palette(), key=lambda p: _dist(key, p[2]))
        _CACHE[key] = (best[0], best[1])
    return _CACHE[key]


def _luma(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def restyle(cv, rim=True, outline=True):
    """Returns a restyled copy of `cv` (a finished sprite that already has some outline)."""
    out = Canvas(cv.w, cv.h)
    ink = style.INK
    kept = {}
    for y in range(cv.h):
        for x in range(cv.w):
            c = cv.px[y * cv.w + x]
            if c[3] == 0:
                continue
            name, step = nearest(c)
            kept[(x, y)] = (name, step)
            out.px[y * cv.w + x] = style.ramp(name)[step][:3] + (c[3],)
    if outline:  # dark pixels on the silhouette become the ink line
        for (x, y), (name, step) in list(kept.items()):
            if cv.get(x, y)[3] < 255:
                continue
            edge = any(cv.get(x + dx, y + dy)[3] == 0 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if edge and _luma(cv.get(x, y)) < 72:
                out.px[y * cv.w + x] = ink
                kept[(x, y)] = ("ink", 0)
    if rim:  # the pixel just inside the ink on the lit side steps one shade up its ramp
        for (x, y), (name, step) in list(kept.items()):
            if name == "ink" or step >= 3:
                continue
            lit = False
            for dx, dy in ((-1, 0), (0, -1)):
                n = kept.get((x + dx, y + dy))
                if n is None and cv.get(x + dx, y + dy)[3] == 0:
                    lit = True
                elif n is not None and n[0] == "ink":
                    lit = True
            if lit and step >= 1:
                c = style.ramp(name)[step + 1]
                out.px[y * cv.w + x] = c[:3] + (out.px[y * cv.w + x][3],)
    return out


def volumize(cv, strength=1.0):
    """Rounds a flat-shaded sprite (before its outline is added): the pixels just inside the silhouette catch the light on the
    upper-left side and fall into shadow on the lower-right, the way cosy village RPGs model their characters. Works on the
    outward direction of each edge pixel, so thin limbs and wide bodies both get a lit and a shaded side. Returns a new canvas."""
    out = Canvas(cv.w, cv.h)
    out.px = list(cv.px)
    light = (-0.6, -0.8)
    near = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

    def empty(x, y):
        return cv.get(x, y)[3] == 0

    for y in range(cv.h):
        for x in range(cv.w):
            c = cv.get(x, y)
            if c[3] == 0:
                continue
            ox = oy = 0.0
            count = 0
            for dx, dy in near:
                if empty(x + dx, y + dy):
                    ox += dx
                    oy += dy
                    count += 1
            if count == 0:
                continue
            length = math.hypot(ox, oy)
            if length < 0.01:
                continue
            lam = (ox * light[0] + oy * light[1]) / length          # +1: this edge faces the light
            if lam > 0.55:
                k = 0.3 * strength
                lit = (int(c[0] + (255 - c[0]) * k * 0.55 + 10 * strength), int(c[1] + (240 - c[1]) * k * 0.55 + 8 * strength),
                       int(c[2] + (214 - c[2]) * k * 0.35), c[3])
                out.px[y * cv.w + x] = tuple(max(0, min(255, v)) for v in lit[:3]) + (c[3],)
            elif lam < -0.45:
                k = 0.28 * strength
                dark = (int(c[0] * (1 - k) + 24 * k), int(c[1] * (1 - k) + 16 * k), int(c[2] * (1 - k) + 64 * k * 1.2), c[3])
                out.px[y * cv.w + x] = tuple(max(0, min(255, v)) for v in dark[:3]) + (c[3],)
    return out


def pillow(cv, strength=1.0, radius=4):
    """Gives a sprite a rounded volume: a height field from the distance to its silhouette (a pillow), its slope against the
    light from the upper left, and one tone lighter where the surface faces the light and one darker where it turns away.
    A flat interior stays as drawn; the shading only appears on the curved parts, so hand-drawn detail survives."""
    w, h = cv.w, cv.h
    big = 99
    dist = [[big] * w for _ in range(h)]
    for y in range(h):                      # chamfer distance to the nearest empty pixel (4-neighbours, two sweeps)
        for x in range(w):
            if cv.get(x, y)[3] == 0:
                dist[y][x] = 0
            else:
                best = 1 if (x == 0 or y == 0 or x == w - 1 or y == h - 1 or cv.get(x - 1, y)[3] == 0 or cv.get(x, y - 1)[3] == 0) else big
                dist[y][x] = best
    for _ in range(2):
        for y in range(h):
            for x in range(w):
                if dist[y][x]:
                    for dx, dy in ((-1, 0), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h:
                            dist[y][x] = min(dist[y][x], dist[ny][nx] + 1)
        for y in range(h - 1, -1, -1):
            for x in range(w - 1, -1, -1):
                if dist[y][x]:
                    for dx, dy in ((1, 0), (0, 1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h:
                            dist[y][x] = min(dist[y][x], dist[ny][nx] + 1)

    def height(x, y):
        if not (0 <= x < w and 0 <= y < h) or cv.get(x, y)[3] == 0:
            return 0.0
        return math.sqrt(min(dist[y][x], radius) / float(radius))

    out = Canvas(w, h)
    out.px = list(cv.px)
    light = (-0.45, -0.6, 0.66)
    for y in range(h):
        for x in range(w):
            c = cv.get(x, y)
            if c[3] == 0:
                continue
            gx = (height(x + 1, y) - height(x - 1, y)) * 0.5
            gy = (height(x, y + 1) - height(x, y - 1)) * 0.5
            k = 2.2
            nx, ny, nz = -gx * k, -gy * k, 1.0
            ln = math.sqrt(nx * nx + ny * ny + nz * nz)
            lam = (nx * light[0] + ny * light[1] + nz * light[2]) / ln
            if lam > 0.80:
                t = min(1.0, (lam - 0.80) * 3.5) * 0.3 * strength
                out.px[y * w + x] = (min(255, int(c[0] + (255 - c[0]) * t + 6 * t * 4)), min(255, int(c[1] + (240 - c[1]) * t + 5 * t * 4)),
                                     min(255, int(c[2] + (214 - c[2]) * t * 0.7)), c[3])
            elif lam < 0.34:
                t = min(1.0, (0.34 - lam) * 2.2) * 0.32 * strength
                out.px[y * w + x] = (int(c[0] * (1 - t) + 24 * t), int(c[1] * (1 - t) + 16 * t), int(c[2] * (1 - t) + 70 * t), c[3])
    return out


def noirize(cv, glow=None):
    """The Noir Silhouette look for a finished (outlined) monster: its body colours go dark and desaturated, what is bright and saturated
    (eyes, gems, fire, slime shine) stays and becomes its glow, the lit upper-left edge takes that glow as a hard rim, and the
    outline is nearly black. `glow` (r, g, b) overrides the glow found in the picture."""
    w, h = cv.w, cv.h
    bright = []
    opaque = 0
    for c in cv.px:
        if c[3] == 255:
            opaque += 1
            hi, lo = max(c[:3]), min(c[:3])
            if hi > 170 and hi - lo > 70:
                bright.append(c[:3])
    floor = 0.0      # a body that is bright all over (a green slime) is mostly dark in Noir: only its brightest shine glows
    if len(bright) > 0.2 * opaque:
        lumas = sorted(0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2] for c in bright)
        floor = lumas[int(0.88 * len(lumas))]

    def glows(c):
        hi, lo = max(c[:3]), min(c[:3])
        return c[3] == 255 and hi > 170 and hi - lo > 70 and 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2] >= floor
    if glow is None:
        if bright:
            glow = tuple(int(sum(v[i] for v in bright) / len(bright)) for i in range(3))
        else:    # no glowing part: the most saturated mid-tone stands in
            mids = sorted((c for c in cv.px if c[3] == 255), key=lambda c: -(max(c[:3]) - min(c[:3])))
            glow = tuple(min(255, int(v * 1.5)) for v in (mids[0][:3] if mids else (156, 240, 216)))
    out = Canvas(w, h)
    for i, c in enumerate(cv.px):
        if c[3] == 0:
            continue
        if glows(c):
            out.px[i] = c[:3] + (255,)                          # a glowing part keeps its colour
        else:
            out.px[i] = noir.base(c[:3]) + (c[3],)
    for y in range(h):                                            # the hard rim on the lit upper-left edge; a nearly black outline
        for x in range(w):
            c = out.get(x, y)
            if c[3] != 255:
                continue
            src = cv.get(x, y)
            edge = cv.get(x - 1, y)[3] == 0 or cv.get(x, y - 1)[3] == 0
            outline = any(cv.get(x + dx, y + dy)[3] == 0 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if outline and sum(src[:3]) < 260:                    # the old soft outline pixel: now nearly black
                out.set(x, y, tuple(int(v * 0.3 + t) for v, t in zip(c[:3], (6, 5, 16))) + (255,))
            elif edge and sum(c[:3]) > 90:
                out.set(x, y, noir.rim(c, '%02x%02x%02x' % glow))
    return out


def install():
    """Restyles every Canvas this process saves (older generators then need no changes beyond importing this)."""
    original = Canvas.save

    def save(self, path, _orig=original):
        _orig(restyle(self), path)

    Canvas.save = save


if __name__ == "__main__":
    print("palette:", len(palette()), "colours,", len(style.STYLES[style.ACTIVE]["ramps"]), "ramps")
