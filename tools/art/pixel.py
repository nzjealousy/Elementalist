"""Tiny dependency-free pixel-art toolkit: a Canvas of RGBA pixels, PNG output, ASCII sprite
parsing, an outline pass and sprite-sheet packing. Python 3.8+, standard library only."""
import struct
import zlib


def hexc(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(c, f):
    """Multiply the colour by f (<1 darker, >1 lighter), keep alpha."""
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))), max(0, min(255, int(c[2] * f))), c[3])


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


class Canvas:
    def __init__(self, w, h, fill=(0, 0, 0, 0)):
        self.w, self.h = w, h
        self.px = [fill] * (w * h)

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y * self.w + x]
        return (0, 0, 0, 0)

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y * self.w + x] = c

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, c)

    def blit(self, other, ox, oy):
        for y in range(other.h):
            for x in range(other.w):
                c = other.px[y * other.w + x]
                if c[3]:
                    self.set(ox + x, oy + y, c)

    def flip_h(self):
        out = Canvas(self.w, self.h)
        for y in range(self.h):
            for x in range(self.w):
                out.px[y * self.w + (self.w - 1 - x)] = self.px[y * self.w + x]
        return out

    def outline(self, c, diagonal=False):
        """1px outline around opaque pixels (drawn on transparent neighbours)."""
        out = Canvas(self.w + 2, self.h + 2)
        out.blit(self, 1, 1)
        for y in range(out.h):
            for x in range(out.w):
                if out.px[y * out.w + x][3]:
                    continue
                near = [(1, 0), (-1, 0), (0, 1), (0, -1)]
                if diagonal:
                    near += [(1, 1), (-1, -1), (1, -1), (-1, 1)]
                if any(out.get(x + dx, y + dy)[3] and out.get(x + dx, y + dy) != c for dx, dy in near):
                    out.px[y * out.w + x] = c
        return out

    def save(self, path):
        raw = bytearray()
        for y in range(self.h):
            raw.append(0)
            for x in range(self.w):
                raw.extend(self.px[y * self.w + x])

        def chunk(tag, data):
            body = tag + data
            return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xffffffff)

        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', self.w, self.h, 8, 6, 0, 0, 0)) \
            + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')
        with open(path, 'wb') as f:
            f.write(png)


def from_ascii(rows, palette):
    """rows: list of equal-width strings; '.' or ' ' is transparent; other chars look up palette."""
    h = len(rows)
    w = max(len(r) for r in rows)
    cv = Canvas(w, h)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in '. ':
                continue
            cv.set(x, y, palette[ch])
    return cv


def sheet(frames, path):
    """Pack same-size frames left to right into one PNG strip."""
    fw, fh = frames[0].w, frames[0].h
    cv = Canvas(fw * len(frames), fh)
    for i, f in enumerate(frames):
        cv.blit(f, i * fw, 0)
    cv.save(path)


class Rng:
    """Small deterministic generator so art is identical on every run."""
    def __init__(self, seed):
        self.s = seed & 0xffffffff or 1

    def next(self):
        self.s = (self.s * 1664525 + 1013904223) & 0xffffffff
        return self.s / 0x100000000

    def rint(self, a, b):
        return a + int(self.next() * (b - a + 1))


# ---------------------------------------------------------------------------------------------
# Procedural drawing helpers: shaded shapes with a fixed top-left light, so every sprite in the
# game is lit the same way. All coordinates are pixel units; shapes are filled, never anti-aliased.
# ---------------------------------------------------------------------------------------------
import math

OUTLINE = (24, 16, 30, 255)
_LIGHT = (-0.45, -0.6, 0.66)
_LL = math.sqrt(sum(v * v for v in _LIGHT))
LIGHT = tuple(v / _LL for v in _LIGHT)


def tones(base):
    """(highlight, base, shadow, deep) for a colour."""
    return (shade(base, 1.28), base, shade(base, 0.74), shade(base, 0.5))


def ellipse(cv, cx, cy, rx, ry, c):
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            if ((x - cx) / max(rx, 0.01)) ** 2 + ((y - cy) / max(ry, 0.01)) ** 2 <= 1.0:
                cv.set(x, y, c)


def shaded_ellipse(cv, cx, cy, rx, ry, base, bands=3):
    """A ball-lit ellipse in 3 tones (highlight / base / shadow) plus a specular dot."""
    hi, mid, lo, deep = tones(base)
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            nx = (x - cx) / max(rx, 0.01)
            ny = (y - cy) / max(ry, 0.01)
            r2 = nx * nx + ny * ny
            if r2 > 1.0:
                continue
            nz = math.sqrt(1.0 - r2)
            lam = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
            cv.set(x, y, hi if lam > 0.78 else (mid if lam > 0.32 else (lo if lam > -0.1 else deep)))


def rect(cv, x, y, w, h, c):
    cv.rect(int(x), int(y), int(w), int(h), c)


def shaded_rect(cv, x, y, w, h, base):
    """A box with a light top-left edge and a dark bottom-right edge."""
    hi, mid, lo, deep = tones(base)
    cv.rect(int(x), int(y), int(w), int(h), mid)
    for i in range(int(w)):
        cv.set(int(x) + i, int(y), hi)
        cv.set(int(x) + i, int(y + h - 1), lo)
    for j in range(int(h)):
        cv.set(int(x), int(y) + j, hi)
        cv.set(int(x + w - 1), int(y) + j, lo)
    cv.set(int(x + w - 1), int(y + h - 1), deep)


def line(cv, x0, y0, x1, y1, c, thick=1):
    steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(steps + 1):
        t = i / max(steps, 1)
        x = round(x0 + (x1 - x0) * t)
        y = round(y0 + (y1 - y0) * t)
        for dx in range(thick):
            for dy in range(thick):
                cv.set(x + dx, y + dy, c)


def poly(cv, pts, c):
    """Filled polygon (scanline, even-odd)."""
    ys = [p[1] for p in pts]
    for y in range(int(min(ys)), int(max(ys)) + 1):
        xs = []
        n = len(pts)
        for i in range(n):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
            if (y0 <= y + 0.5 < y1) or (y1 <= y + 0.5 < y0):
                xs.append(x0 + (y + 0.5 - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(int(round(xs[i])), int(round(xs[i + 1]))):
                cv.set(x, y, c)


def eyes(cv, x, y, gap, c=(255, 255, 255, 255), pupil=(20, 16, 30, 255), size=1):
    """Two eyes centred on x, `gap` apart."""
    for sx in (x - gap // 2, x + gap // 2 - (0 if gap % 2 else 0)):
        cv.set(sx, y, c)
        if size > 1:
            cv.set(sx, y + 1, c)
        cv.set(sx + (1 if sx >= x else 0), y + (size - 1), pupil)


def finish(cv, outline=OUTLINE, pad=0):
    """Add the 1px outline and return the framed canvas."""
    return cv.outline(outline)


def fit(cv, w, h):
    """Centre `cv` in a (w, h) transparent canvas (bottom-aligned), so animation frames share a size."""
    out = Canvas(w, h)
    out.blit(cv, (w - cv.w) // 2, h - cv.h)
    return out
