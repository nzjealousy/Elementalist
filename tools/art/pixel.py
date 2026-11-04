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
