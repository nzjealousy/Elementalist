"""Three proposed art styles as code: colour ramps, the rune renderer, glow/shadow helpers and a per-style outline rule.
Everything the style boards (style_board.py) draw goes through here, and the real restyle will reuse it, so the whole
game ends up with one palette, one light and one outline rule per chosen style.

Styles (see docs/ART_DIRECTION.md):
  gilded     "Gilded Hollow":     jewel ramps, coloured outlines, carved wood and brass, glowing runes on dark stone.
  moonlit    "Moonlit Glyphwork": cold deep world, flat 3-tone cel shading, ink outlines, emissive runes that pop.
  storybook  "Autumn Storybook": warm painterly earth tones, soft warm outlines, parchment and leather, long soft shadows.

Shared rules: five-step ramps (shadows lean cool, lights lean warm), light from the top left, glow = white-hot core +
saturated body + halo, no pure black or white.
"""
import math
from pixel import Canvas, hexc, mix, soft_outline, line

STYLES = {
    "gilded": {
        "name": "Gilded Hollow",
        "ink": "140c24",
        "backdrop": "181226",
        "ramps": {
            "fire":    ["3a1226", "8e2a1e", "d9531c", "ff9a30", "ffe08a"],
            "water":   ["0e1c48", "1f4a9c", "2f86dc", "6cc6f4", "d2f4ff"],
            "air":     ["123a42", "2a7c6e", "58bc96", "9eeabc", "e8fff0"],
            "mineral": ["3a2412", "7e5420", "c48a2a", "f2c24a", "fff0a8"],
            "earth":   ["102e1c", "1f6a2c", "46a83a", "8ad45a", "d8f8a0"],
            "light":   ["5a4a2a", "b89a4a", "f0d070", "fff0b0", "ffffff"],
            "dark":    ["1c0c3a", "4a2084", "8a44c8", "c27cf0", "f0d0ff"],
            "stone":   ["1a1626", "3a3650", "625e7e", "908cac", "c8c4dc"],
            "wood":    ["24131a", "4e2a28", "835038", "b87c4c", "e8b678"],
            "brass":   ["2a1a14", "6a4418", "b88428", "ecc050", "fff2b0"],
            "moss":    ["10261e", "224a34", "3a7a4a", "6cae5c", "b4dc86"],
            "skin":    ["4a2430", "9a5a4a", "d8906a", "f4bc92", "ffe2c4"],
        },
        "outline": "soft",     # a dark, slightly violet shade of the colour it touches
        "steps": 5,             # shading steps used on sprites
        "ui": "wood",
    },
    "moonlit": {
        "name": "Moonlit Glyphwork",
        "ink": "0a0618",
        "backdrop": "0c0818",
        "ramps": {
            "fire":    ["2a0a2a", "7a1f4a", "e0403a", "ff8040", "ffd8a0"],
            "water":   ["081838", "103a8a", "2a78e0", "5cc8ff", "e0f8ff"],
            "air":     ["0c2e3a", "1e6a78", "3cc0b0", "9cf0d8", "f0fffa"],
            "mineral": ["2a1810", "6a4a20", "c8962c", "f8d060", "fff8c0"],
            "earth":   ["0c2a20", "1a6a48", "38b060", "88e880", "d8ffc8"],
            "light":   ["302a50", "8878c8", "d8d0ff", "fff8ff", "f8f4ff"],
            "dark":    ["10082a", "3a1070", "7a30d0", "b868ff", "f0c8ff"],
            "stone":   ["0c0a1a", "24204a", "3c3868", "5c5890", "9090c0"],
            "wood":    ["140c1c", "30203a", "503450", "785070", "a87898"],
            "brass":   ["1a1228", "3a3068", "6858b0", "a098f0", "e0d8ff"],
            "moss":    ["0c1c2c", "1a3a4a", "2a6a6a", "4a9a8a", "88d0b0"],
            "skin":    ["301830", "804860", "c88080", "f0b0a0", "ffe0d0"],
        },
        "outline": "ink",      # one dark ink line, the same colour everywhere
        "steps": 3,             # flat cel shading: shadow, base, light
        "ui": "slab",
    },
    "storybook": {
        "name": "Autumn Storybook",
        "ink": "2a1620",
        "backdrop": "2a1e24",
        "ramps": {
            "fire":    ["4a1a1c", "a03020", "e86a28", "ffa83c", "ffe8a8"],
            "water":   ["1a3a50", "2e6c8c", "4ea0b8", "8ad4d8", "d8f4ee"],
            "air":     ["2c4a40", "58886a", "90bc88", "c8e4a8", "f4ffe0"],
            "mineral": ["4a2c18", "8a5a28", "c89038", "f0c868", "fff0b8"],
            "earth":   ["2a3a18", "4a6a20", "78a030", "b0d050", "e8f4a0"],
            "light":   ["6a5020", "c8a040", "f8dc78", "fff4c0", "ffffff"],
            "dark":    ["3a2048", "6a3a78", "9a60a8", "c898d0", "f0d8f4"],
            "stone":   ["382c34", "6a5a5c", "988478", "c4b09c", "ece0cc"],
            "wood":    ["3a2014", "6a3c20", "a06a38", "d09a58", "f4cc88"],
            "brass":   ["4a3018", "8a5a20", "c89030", "f0c458", "fff0a8"],
            "moss":    ["2a3818", "4a6a28", "7a9a38", "aac858", "d8ec98"],
            "skin":    ["5a3030", "a86a58", "e0a07c", "f8cca4", "ffe8d0"],
        },
        "outline": "warm",     # a dark warm brown, lighter than ink, so sprites feel painted
        "steps": 5,
        "ui": "parchment",
    },
}

ACTIVE = "moonlit"     # the chosen style (docs/ART_DIRECTION.md); the others stay for the comparison boards
INK = hexc(STYLES[ACTIVE]["ink"])


def use(name):
    """Selects the style every helper draws in."""
    global ACTIVE, INK
    ACTIVE = name
    INK = hexc(STYLES[name]["ink"])


def spec():
    return STYLES[ACTIVE]


def ramp(name):
    return [hexc(c) for c in STYLES[ACTIVE]["ramps"][name]]


def backdrop_colour():
    return hexc(STYLES[ACTIVE]["backdrop"])


def outline(cv):
    """The style's outline rule: coloured (gilded), one ink (moonlit) or warm brown (storybook)."""
    mode = STYLES[ACTIVE]["outline"]
    if mode == "soft":
        return cv.outline(None)
    ink = INK
    if mode == "ink":
        return cv.outline(ink)
    out = Canvas(cv.w + 2, cv.h + 2)
    out.blit(cv, 1, 1)
    placed = []
    for y in range(out.h):
        for x in range(out.w):
            if out.px[y * out.w + x][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = out.get(x + dx, y + dy)
                if n[3]:
                    placed.append((x, y, (int(n[0] * 0.38 + 38), int(n[1] * 0.3 + 20), int(n[2] * 0.28 + 24), 255)))
                    break
    for x, y, c in placed:
        out.px[y * out.w + x] = c
    return out


def step(index):
    """The shading index to use. Every style paints with the same five ramp steps; the difference between styles lives in
    the palettes, the outline rule and in whether the gradients are dithered (styles with 5 steps dither, the flat one does not)."""
    return index


# ---------------------------------------------------------------------------------------------
# runes: spell glyphs on a dark carved disc, the element icon of the whole game
# ---------------------------------------------------------------------------------------------

RAMP_OF = {"martial": "light"}   # the physical skill set is not an element: it glows pale metal


def _glyph(element):
    """Polylines in [-1, 1] space (y down): angular, runic, readable by silhouette. Each is (points, is_closed)."""
    c, s = math.cos, math.sin
    if element == "fire":      # a rising triangle with a flame sigil in its heart
        return [[(0, -0.92), (0.82, 0.62), (-0.82, 0.62), (0, -0.92)],
                [(0, 0.38), (0, -0.28)], [(0, 0.04), (0.3, -0.22)], [(0, 0.04), (-0.3, -0.22)], [(0, -0.28), (0, -0.52)]]
    if element == "water":     # a falling triangle holding two waves
        return [[(-0.82, -0.6), (0.82, -0.6), (0, 0.9), (-0.82, -0.6)],
                [(-0.42, -0.24), (-0.21, -0.42), (0, -0.24), (0.21, -0.42), (0.42, -0.24)],
                [(-0.24, 0.1), (-0.08, -0.06), (0.08, 0.1), (0.24, -0.06)]]
    if element == "air":       # a wind spiral with two trailing strokes
        pts = []
        for i in range(31):
            a = 3.4 + i / 30.0 * 1.45 * math.tau
            r = 0.08 + 0.6 * i / 30.0
            pts.append((c(a) * r, s(a) * r))
        return [pts, [(-0.9, 0.18), (-0.5, 0.18)], [(0.5, -0.18), (0.9, -0.18)]]
    if element == "mineral":   # a cut diamond with a cross of facets
        return [[(0, -0.92), (0.66, 0), (0, 0.92), (-0.66, 0), (0, -0.92)],
                [(0, -0.46), (0, 0.46)], [(-0.33, 0), (0.33, 0)], [(-0.66, 0), (-0.9, 0)], [(0.66, 0), (0.9, 0)]]
    if element == "earth":     # a boundary square with a sprout and root
        return [[(-0.68, -0.68), (0.68, -0.68), (0.68, 0.68), (-0.68, 0.68), (-0.68, -0.68)],
                [(0, 0.68), (0, -0.46)], [(0, 0.22), (-0.38, -0.12)], [(0, 0.22), (0.38, -0.12)], [(0, -0.2), (-0.26, -0.46)], [(0, -0.2), (0.26, -0.46)]]
    if element == "light":     # a radiant square-eye with eight rays
        rays = [[(c(a) * 0.36, s(a) * 0.36), (c(a) * (0.94 if i % 2 == 0 else 0.7), s(a) * (0.94 if i % 2 == 0 else 0.7))]
                for i, a in enumerate([math.tau * k / 8 for k in range(8)])]
        return rays + [[(-0.16, -0.16), (0.16, -0.16), (0.16, 0.16), (-0.16, 0.16), (-0.16, -0.16)]]
    if element == "martial":   # not an element: two crossed blades with guards
        return [[(-0.74, 0.74), (0.74, -0.74)], [(0.74, 0.74), (-0.74, -0.74)],
                [(-0.58, 0.1), (-0.1, 0.58)], [(0.1, 0.58), (0.58, 0.1)]]
    outer = [(c(a) * 0.86, s(a) * 0.86) for a in [math.radians(40 + k * 280 / 18) for k in range(19)]]   # dark: a crescent
    inner = [(0.24 + c(a) * 0.6, s(a) * 0.6) for a in [math.radians(320 - k * 270 / 14) for k in range(15)]]
    return [outer + inner + [outer[0]], [(0.34, -0.06), (0.46, -0.06), (0.46, 0.06), (0.34, 0.06), (0.34, -0.06)]]


def rune(element, size=32, glow=True, disc=True):
    """The element's spell rune: a carved dark disc with an inscribed ring and a glowing glyph. `disc=False` draws
    only the ring ticks and glyph on transparent (for ground circles)."""
    cols = ramp(RAMP_OF.get(element, element))
    stone = ramp("stone")
    plate = [mix(stone[i], cols[0], 0.45) for i in range(5)]
    pad = 5 if glow else 2
    cv = Canvas(size + pad * 2, size + pad * 2)
    cx = cy = pad + size / 2.0
    radius = size / 2.0 - 0.7
    big = size >= 24
    if disc:
        for y in range(cv.h):
            for x in range(cv.w):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                r = math.hypot(dx, dy)
                if r > radius:
                    continue
                edge = radius - r
                lam = -(dx * 0.5 + dy * 0.7) / max(r, 0.01)   # +1 toward the light (upper left)
                if edge < 1.6:
                    idx = 3 if lam > 0.35 else (2 if lam > -0.2 else 0)
                elif edge < 2.8 and big:
                    idx = 0 if lam > 0.1 else 2     # the inner lip of the carved ring: shaded on the lit side, lit opposite
                else:
                    idx = 1 if (lam < 0.62 or r > radius * 0.6) else 2
                cv.set(x, y, plate[idx])
    strokes = set()
    scale = radius * (0.66 if big else 0.7)
    for poly_pts in _glyph(element):
        for i in range(len(poly_pts) - 1):
            x0, y0 = poly_pts[i]
            x1, y1 = poly_pts[i + 1]
            tmp = Canvas(cv.w, cv.h)
            line(tmp, int(cx + x0 * scale), int(cy + y0 * scale), int(cx + x1 * scale), int(cy + y1 * scale), (1, 1, 1, 255))
            for yy in range(cv.h):
                for xx in range(cv.w):
                    if tmp.px[yy * cv.w + xx][3]:
                        strokes.add((xx, yy))
    ticks = {}
    if big:  # twelve rune ticks and dots on the ring: long ticks lit, short ones dim
        for k in range(24):
            a = math.tau * k / 24
            for depth in ((1.7, 2.7) if k % 2 == 0 else (2.2,)):
                px, py = int(cx + math.cos(a) * (radius - depth)), int(cy + math.sin(a) * (radius - depth))
                ticks[(px, py)] = cols[3] if k % 2 == 0 else cols[1]
    for (x, y), c in ticks.items():
        if (x, y) not in strokes:
            cv.set(x, y, c)
    near = set()
    for (x, y) in strokes:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if (x + dx, y + dy) not in strokes:
                near.add((x + dx, y + dy))
    far = set()
    if big:
        for (x, y) in near:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                p = (x + dx, y + dy)
                if p not in strokes and p not in near:
                    far.add(p)
    for (x, y) in far:
        if cv.get(x, y)[3] or not disc:
            cv.set(x, y, mix(cv.get(x, y) if cv.get(x, y)[3] else cols[0], cols[1], 0.55))
    for (x, y) in near:
        if cv.get(x, y)[3] or not disc:
            cv.set(x, y, cols[2] if disc else cols[2])
    for (x, y) in strokes:
        cv.set(x, y, cols[4])
    framed = outline(cv) if disc else cv
    if glow:
        framed = _halo(framed, cols[2], 4, 130)
    return framed


def _halo(cv, colour, radius, peak=110):
    """A translucent coloured glow ring around the opaque pixels."""
    w, h = cv.w, cv.h
    out = Canvas(w, h)
    for y in range(h):
        for x in range(w):
            if cv.px[y * w + x][3] == 255:
                continue
            best = 99.0
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    if cv.get(x + dx, y + dy)[3] == 255:
                        best = min(best, math.hypot(dx, dy))
            if best <= radius:
                alpha = int(peak * (1.0 - (best - 1.0) / radius)) if best >= 1.0 else peak
                out.set(x, y, (colour[0], colour[1], colour[2], max(0, alpha)))
    out.blit(cv, 0, 0)
    return out


def squash(cv, factor):
    """Vertically squashes a canvas (nearest), turning a flat circle into the ellipse it is on the isometric floor."""
    h = max(1, int(cv.h * factor))
    out = Canvas(cv.w, h)
    for y in range(h):
        for x in range(cv.w):
            out.px[y * cv.w + x] = cv.px[int(y / factor) * cv.w + x]
    return out


# ---------------------------------------------------------------------------------------------
# light and shadow helpers shared by every scene piece
# ---------------------------------------------------------------------------------------------

def light_pool(cv, cx, cy, rx, ry, colour, strength=0.5):
    """A warm pool of light on the floor (torch, spell glow): brighter toward the centre."""
    for y in range(int(cy - ry), int(cy + ry) + 1):
        for x in range(int(cx - rx), int(cx + rx) + 1):
            d = math.hypot((x - cx) / rx, (y - cy) / ry)
            if d >= 1.0:
                continue
            base = cv.get(x, y)
            if not base[3]:
                continue
            t = (1.0 - d) ** 1.5 * strength
            cv.set(x, y, (min(255, int(base[0] + (colour[0] - base[0]) * t + 30 * t)),
                          min(255, int(base[1] + (colour[1] - base[1]) * t + 14 * t)),
                          min(255, int(base[2] + (colour[2] - base[2]) * t)), base[3]))


def blob_shadow(cv, cx, cy, rx, ry, tint=None, alpha=120):
    """A tinted (never black) ellipse shadow, dithered at its edge so it stays pixel-clean."""
    tint = tint or {"gilded": (20, 12, 50), "moonlit": (6, 4, 28), "storybook": (50, 30, 40)}[ACTIVE]
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if d > 1.0:
                continue
            a = alpha if d < 0.62 else (alpha // 2 if (x + y) % 2 == 0 else alpha)
            base = cv.get(x, y)
            if base[3]:
                t = a / 255.0
                cv.set(x, y, (int(base[0] * (1 - t) + tint[0] * t), int(base[1] * (1 - t) + tint[1] * t), int(base[2] * (1 - t) + tint[2] * t), base[3]))
            else:
                cv.set(x, y, (tint[0], tint[1], tint[2], a))
