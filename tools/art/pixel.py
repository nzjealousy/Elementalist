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
        """1px outline around opaque pixels (drawn on transparent neighbours). With c=None the outline is SOFT:
        each outline pixel is a dark, slightly purple shade of the sprite pixel it touches (the way Stardew Valley
        and Witchbrook draw theirs), instead of one black line."""
        out = Canvas(self.w + 2, self.h + 2)
        out.blit(self, 1, 1)
        placed = []
        for y in range(out.h):
            for x in range(out.w):
                if out.px[y * out.w + x][3]:
                    continue
                near = [(1, 0), (-1, 0), (0, 1), (0, -1)]
                if diagonal:
                    near += [(1, 1), (-1, -1), (1, -1), (-1, 1)]
                for dx, dy in near:
                    n = out.get(x + dx, y + dy)
                    if n[3] and n != c:
                        placed.append((x, y, c if c is not None else soft_outline(n)))
                        break
        for x, y, col in placed:
            out.px[y * out.w + x] = col
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


def load_png(path):
    """Reads one of our own PNGs (8-bit RGBA, any filter) back into a Canvas; used by check_art.py and the previews."""
    data = open(path, 'rb').read()
    pos, idat, w, h = 8, b'', 0, 0
    while pos < len(data):
        n, tag = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if tag == b'IHDR':
            w, h = struct.unpack('>II', body[:8])
        elif tag == b'IDAT':
            idat += body
        pos += 12 + n
    raw = zlib.decompress(idat)
    cv = Canvas(w, h)
    stride = w * 4
    prev = bytearray(stride)
    i = 0
    for y in range(h):
        kind = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a_ = line[x - 4] if x >= 4 else 0
            b_ = prev[x]
            c_ = prev[x - 4] if x >= 4 else 0
            if kind == 1:
                line[x] = (line[x] + a_) & 255
            elif kind == 2:
                line[x] = (line[x] + b_) & 255
            elif kind == 3:
                line[x] = (line[x] + (a_ + b_) // 2) & 255
            elif kind == 4:
                p_ = a_ + b_ - c_
                pa, pb, pc = abs(p_ - a_), abs(p_ - b_), abs(p_ - c_)
                line[x] = (line[x] + (a_ if pa <= pb and pa <= pc else (b_ if pb <= pc else c_))) & 255
        for x in range(w):
            cv.px[y * w + x] = tuple(line[x * 4:x * 4 + 4])
        prev = line
    return cv


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


def soft_outline(c):
    """A dark shade of a pixel, pushed toward purple: the outline colour for the pixel it surrounds."""
    return (min(255, int(c[0] * 0.36 + 20)), min(255, int(c[1] * 0.34 + 8)), min(255, int(c[2] * 0.4 + 36)), 255)


def cool_shadow(c, f):
    """Darkens toward blue-purple instead of toward grey, so shadows feel lit by a warm sun."""
    d = [c[0] * f, c[1] * f, c[2] * f]
    mixed = [d[0] + (64 - d[0]) * 0.18, d[1] + (44 - d[1]) * 0.18, d[2] + (120 - d[2]) * 0.18]
    return (max(0, min(255, int(mixed[0]))), max(0, min(255, int(mixed[1]))), max(0, min(255, int(mixed[2]))), c[3])


def warm_light(c, f):
    """Lightens toward warm cream instead of toward white."""
    l = [c[0] * f, c[1] * f, c[2] * f]
    mixed = [l[0] + (255 - l[0]) * 0.1, l[1] + (240 - l[1]) * 0.1, l[2] + (205 - l[2]) * 0.1]
    return (max(0, min(255, int(mixed[0]))), max(0, min(255, int(mixed[1]))), max(0, min(255, int(mixed[2]))), c[3])


def tones(base):
    """(highlight, base, shadow, deep) for a colour: warm highlights, cool shadows."""
    return (warm_light(base, 1.2), base, cool_shadow(base, 0.78), cool_shadow(base, 0.55))


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


def finish(cv, outline=None, pad=0):
    """Add the 1px outline (soft and coloured unless a colour is given) and return the framed canvas."""
    return cv.outline(outline)


def fit(cv, w, h):
    """Centre `cv` in a (w, h) transparent canvas (bottom-aligned), so animation frames share a size."""
    out = Canvas(w, h)
    out.blit(cv, (w - cv.w) // 2, h - cv.h)
    return out
