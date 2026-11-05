"""The Moonlit Glyphwork pass: snaps a sprite's colours onto the style's ramps, redraws its outline as the one ink line
and lights its upper-left edge. Older generators (monsters, props) call `restyle(canvas)` on a finished sprite, so every
picture in the game shares one palette, one outline and one light direction without each script being rewritten.

    import restyle
    cv = restyle.restyle(cv)    # a new canvas, same size
    restyle.install()           # or: every Canvas.save() in this run is restyled

Rules (docs/ART_DIRECTION.md): colours come from `style.STYLES["moonlit"]["ramps"]`, nothing is pure black, the outline is
`style.INK`, the lit edge (upper left) is one ramp step brighter, translucent pixels keep their alpha."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
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


def install():
    """Restyles every Canvas this process saves (older generators then need no changes beyond importing this)."""
    original = Canvas.save

    def save(self, path, _orig=original):
        _orig(restyle(self), path)

    Canvas.save = save


if __name__ == "__main__":
    print("palette:", len(palette()), "colours,", len(style.STYLES[style.ACTIVE]["ramps"]), "ramps")
