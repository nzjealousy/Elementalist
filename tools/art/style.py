"""The proposed art style, "Gilded Hollow", as code: colour ramps, a bevel-lit emblem renderer, glow and halo
helpers. Everything the style board (style_board.py) draws goes through here, and the real restyle will reuse it,
so the whole game ends up with one palette, one light and one outline rule.

Rules in short (see docs/ART_DIRECTION.md):
  * every hue is a 5-step ramp whose shadows lean violet/teal and whose lights lean warm cream (never grey/black);
  * outlines are a dark shade of the colour they touch, never pure black;
  * light comes from the top left: bevel highlights on the upper left edges, a cool dark rim on the lower right;
  * glowing things (spells, gems, torches) have a white-hot core, a saturated body and a dark translucent halo.
"""
import math
from pixel import Canvas, hexc, mix, soft_outline

# 5 steps, darkest to lightest. The darkest is already a dark violet tint of the hue, so shadows stay coloured.
RAMPS = {
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
}
RAMPS_RGBA = {k: [hexc(c) for c in v] for k, v in RAMPS.items()}
INK = hexc("140c24")  # the one near-black allowed: a violet ink, used only for the darkest gaps


def ramp(name):
    return RAMPS_RGBA[name]


# ---------------------------------------------------------------------------------------------
# emblems: chunky gem-like icons rendered from a shape function instead of drawn by hand
# ---------------------------------------------------------------------------------------------

def _distance_to_outside(mask, w, h):
    """Chamfer distance of every inside pixel to the nearest outside one."""
    big = 999.0
    d = [[0.0 if not mask[y][x] else big for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            if not mask[y][x]:
                continue
            best = d[y][x]
            for dx, dy, cost in ((-1, 0, 1.0), (0, -1, 1.0), (-1, -1, 1.4), (1, -1, 1.4)):
                nx, ny = x + dx, y + dy
                best = min(best, (d[ny][nx] + cost) if 0 <= nx < w and 0 <= ny < h else 1.0)
            d[y][x] = best
    for y in range(h - 1, -1, -1):
        for x in range(w - 1, -1, -1):
            if not mask[y][x]:
                continue
            best = d[y][x]
            for dx, dy, cost in ((1, 0, 1.0), (0, 1, 1.0), (1, 1, 1.4), (-1, 1, 1.4)):
                nx, ny = x + dx, y + dy
                best = min(best, (d[ny][nx] + cost) if 0 <= nx < w and 0 <= ny < h else 1.0)
            d[y][x] = best
    return d


def render_emblem(body, engrave, ramp_name, size=32, glow=True, sparkle=True):
    """body(u, v) and engrave(u, v) are shape tests in [-1, 1] coordinates (y down); returns a Canvas with room
    for the outline and halo. The look: a bevel lit from the top left, grooves with a light lower lip, a soft
    coloured outline and a dark translucent halo."""
    cols = ramp(ramp_name)
    pad = 5 if glow else 2
    w = h = size
    mask = [[body((x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1) for x in range(w)] for y in range(h)]
    groove = [[mask[y][x] and engrave((x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1) for x in range(w)] for y in range(h)]
    dist = _distance_to_outside(mask, w, h)
    scale = size / 32.0
    out = Canvas(w + pad * 2, h + pad * 2)

    def dd(x, y):
        return dist[y][x] if 0 <= x < w and 0 <= y < h else 0.0

    for y in range(h):
        for x in range(w):
            if not mask[y][x]:
                continue
            gx = dd(x + 1, y) - dd(x - 1, y)
            gy = dd(x, y + 1) - dd(x, y - 1)
            edge = dist[y][x] <= 2.2 * max(scale, 0.7)
            s = 0.56 + 0.12 * (0.5 - y / h)           # a gentle top-to-bottom ramp
            if edge:
                s += 0.17 * (gx + gy)                  # upper-left bevel lights, lower-right bevel darkens
            s += 0.10 * min(dist[y][x] / (6.0 * scale), 1.0)  # the middle swells toward the light
            idx = max(0, min(4, int(s * 5.0)))
            out.set(x + pad, y + pad, cols[idx])
    # grooves: a dark channel with a light lip below and right of it, which is what makes them read as carved
    for y in range(h):
        for x in range(w):
            if groove[y][x]:
                out.set(x + pad, y + pad, cols[0] if dist[y][x] > 1.0 else cols[1])
    for y in range(h):
        for x in range(w):
            if mask[y][x] and not groove[y][x] and (groove[y - 1][x] or groove[y][x - 1]) and 0 < x and 0 < y:
                out.set(x + pad, y + pad, cols[min(4, 3 if dist[y][x] > 1.4 else 2)])
    framed = out.outline(None)
    if glow:
        framed = _halo(framed, cols[0], 4)
    if sparkle:
        _sparkles(framed, mask, pad + 1, cols[4], size)
    return framed


def _halo(cv, colour, radius):
    """A dark, translucent glow ring around the opaque pixels."""
    w, h = cv.w, cv.h
    out = Canvas(w, h)
    for y in range(h):
        for x in range(w):
            if cv.px[y * w + x][3]:
                continue
            best = 99.0
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    if cv.get(x + dx, y + dy)[3] and cv.get(x + dx, y + dy)[3] == 255:
                        best = min(best, math.hypot(dx, dy))
            if best <= radius:
                alpha = int(110 * (1.0 - (best - 1.0) / radius)) if best >= 1.0 else 110
                out.set(x, y, (colour[0], colour[1], colour[2], max(0, alpha)))
    out.blit(cv, 0, 0)
    return out


def _sparkles(cv, mask, pad, colour, size):
    """A few plus-shaped glints on the lit upper-left of the shape."""
    spots = [(0.30, 0.28), (0.62, 0.20)] if size >= 24 else [(0.32, 0.30)]
    for fx, fy in spots:
        x, y = int(fx * size) + pad, int(fy * size) + pad
        if cv.get(x, y)[3] == 255:
            cv.set(x, y, colour)
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if cv.get(x + dx, y + dy)[3] == 255:
                    cv.set(x + dx, y + dy, mix(cv.get(x + dx, y + dy), colour, 0.55))


# ---- shape toolkit (all in [-1, 1] space) ----

def circle(cx, cy, r):
    return lambda u, v: (u - cx) ** 2 + (v - cy) ** 2 <= r * r


def ellipse(cx, cy, rx, ry, angle=0.0):
    ca, sa = math.cos(angle), math.sin(angle)

    def test(u, v):
        x, y = u - cx, v - cy
        a, b = x * ca + y * sa, -x * sa + y * ca
        return (a / rx) ** 2 + (b / ry) ** 2 <= 1.0
    return test


def polygon(points):
    def test(u, v):
        inside = False
        n = len(points)
        for i in range(n):
            (x0, y0), (x1, y1) = points[i], points[(i + 1) % n]
            if (y0 > v) != (y1 > v) and u < (x1 - x0) * (v - y0) / (y1 - y0) + x0:
                inside = not inside
        return inside
    return test


def union(*tests):
    return lambda u, v: any(t(u, v) for t in tests)


def minus(a, b):
    return lambda u, v: a(u, v) and not b(u, v)


def stroke(points, width):
    """Pixels within `width` of a polyline."""
    def test(u, v):
        for i in range(len(points) - 1):
            (x0, y0), (x1, y1) = points[i], points[i + 1]
            dx, dy = x1 - x0, y1 - y0
            ln = dx * dx + dy * dy
            t = 0.0 if ln == 0 else max(0.0, min(1.0, ((u - x0) * dx + (v - y0) * dy) / ln))
            if (u - x0 - dx * t) ** 2 + (v - y0 - dy * t) ** 2 <= width * width:
                return True
        return False
    return test


def spiral(cx, cy, r0, r1, turns, start=0.0, steps=60):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        a = start + t * turns * math.tau
        r = r0 + (r1 - r0) * t
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def none(u, v):
    return False


# ---- the seven emblems (original designs; each reads by silhouette first) ----

def emblem(element, size=32, glow=True):
    if element == "fire":      # a flame with a licking side tongue and a spiral ember inside
        body = union(circle(0.0, 0.32, 0.6),
                     polygon([(0.14, -0.98), (0.36, -0.55), (0.56, -0.05), (0.58, 0.32), (-0.58, 0.32), (-0.52, -0.1),
                              (-0.3, -0.42), (-0.12, -0.6), (-0.04, -0.82)]),
                     polygon([(-0.9, -0.05), (-0.56, -0.38), (-0.6, 0.1), (-0.42, 0.45), (-0.78, 0.45)]),
                     polygon([(0.82, -0.12), (0.5, -0.36), (0.56, 0.15), (0.4, 0.45), (0.74, 0.45)]))
        carve = union(stroke(spiral(0.03, 0.34, 0.04, 0.3, 1.6, 0.4), 0.05), stroke([(0.1, -0.7), (0.2, -0.3), (0.12, -0.05)], 0.03))
    elif element == "water":   # a droplet whose belly holds ripple rings and a wave crest
        drop = union(circle(0.0, 0.28, 0.66), polygon([(0.0, -0.92), (0.5, 0.0), (-0.5, 0.0)]))
        body = drop
        carve = union(stroke([(-0.4, 0.28), (-0.2, 0.18), (0.0, 0.3), (0.2, 0.18), (0.4, 0.28)], 0.045),
                      stroke([(-0.3, 0.5), (-0.1, 0.42), (0.1, 0.52), (0.3, 0.44)], 0.04))
    elif element == "air":     # a cloud bank with a wind curl cut through it
        body = union(circle(-0.46, 0.26, 0.38), circle(-0.02, -0.06, 0.52), circle(0.46, 0.22, 0.4),
                     polygon([(-0.78, 0.5), (0.84, 0.5), (0.84, 0.2), (-0.78, 0.2)]))
        carve = union(stroke(spiral(0.05, 0.02, 0.05, 0.3, 1.25, 3.4), 0.045), stroke([(-0.55, 0.38), (0.6, 0.38)], 0.035))
    elif element == "mineral": # three crystal shards, the tall one faceted down its middle
        body = union(polygon([(0.0, -0.95), (0.3, -0.4), (0.3, 0.7), (-0.3, 0.7), (-0.3, -0.4)]),
                     polygon([(-0.74, -0.2), (-0.46, 0.0), (-0.46, 0.7), (-0.9, 0.7), (-0.9, 0.1)]),
                     polygon([(0.72, -0.4), (0.9, 0.05), (0.9, 0.7), (0.46, 0.7), (0.46, 0.1)]))
        carve = union(stroke([(0.0, -0.9), (0.0, 0.7)], 0.03), stroke([(-0.68, -0.15), (-0.68, 0.7)], 0.03),
                      stroke([(0.68, -0.3), (0.68, 0.7)], 0.03), stroke([(-0.3, 0.7), (0.3, 0.7)], 0.03))
    elif element == "earth":   # a seed pod with a pair of leaves and root veins
        pod = circle(0.0, 0.2, 0.66)
        leaf_l = ellipse(-0.34, -0.5, 0.36, 0.17, -0.7)
        leaf_r = ellipse(0.34, -0.5, 0.36, 0.17, 0.7)
        body = union(pod, leaf_l, leaf_r, polygon([(-0.06, -0.5), (0.06, -0.5), (0.06, -0.2), (-0.06, -0.2)]))
        carve = union(stroke([(0.0, -0.1), (0.0, 0.8)], 0.035), stroke([(0.0, 0.2), (-0.34, -0.05)], 0.03),
                      stroke([(0.0, 0.2), (0.34, -0.05)], 0.03), stroke([(0.0, 0.5), (-0.28, 0.32)], 0.03),
                      stroke([(0.0, 0.5), (0.28, 0.32)], 0.03))
    elif element == "light":   # an eight-point sun with a ringed heart
        pts = []
        for i in range(16):
            r = 0.95 if i % 2 == 0 else 0.42
            a = math.pi * i / 8 - math.pi / 2
            pts.append((math.cos(a) * r, math.sin(a) * r))
        body = polygon(pts)
        carve = minus(circle(0.0, 0.0, 0.26), circle(0.0, 0.0, 0.17))
    else:                      # dark: a crescent that cradles a small void
        moon = minus(circle(0.0, 0.0, 0.86), circle(0.42, -0.2, 0.7))
        body = union(moon, circle(0.28, 0.18, 0.2))
        carve = union(stroke([(-0.5, 0.35), (-0.2, 0.05), (-0.34, -0.2)], 0.03), stroke([(-0.62, -0.1), (-0.38, -0.34)], 0.03))
    return render_emblem(body, carve, element, size, glow)


# ---------------------------------------------------------------------------------------------
# light and shadow helpers shared by every scene piece
# ---------------------------------------------------------------------------------------------

def light_pool(cv, cx, cy, rx, ry, colour, strength=0.5):
    """A warm additive pool of light on the floor (torch, spell glow): brighter toward the centre."""
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


def blob_shadow(cv, cx, cy, rx, ry, tint=(20, 12, 50), alpha=120):
    """An indigo (not black) ellipse shadow, dithered at its edge so it stays pixel-clean."""
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
