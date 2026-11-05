"""Moonlit Glyphwork UI frames (9-slice sources) -> elementalist/assets/ui/. Run: python tools/art/gen_ui.py

The kit is obsidian slabs under one ink outline, with a thin carved rune line that glows when a control is lit:
    panel.png          24x24, margin 8   windows and cards (rune line with a glint every 8 px, lit corner nodes)
    parchment.png      16x16, margin 3   a paler slate for lists and text blocks
    button_*.png       16x16, margin 5   normal / hover / pressed / disabled / focus
    slot.png           18x18             an item or skill well (slot_selected.png: the rune line lit)
    bar_frame.png      48x6              the frame behind a thin bar
    divider.png        64x5              a rune line with a diamond
    title_banner.png   120x26            the slab behind the game title
Every colour is a ramp step from style.py (moonlit); nothing is pure black or white."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import style
from pixel import Canvas, Rng, mix

style.use("moonlit")

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'ui')
os.makedirs(OUT, exist_ok=True)

STONE, BRASS, DARK = style.ramp("stone"), style.ramp("brass"), style.ramp("dark")
INK = style.INK
DEEP = STONE[0]          # the well colour
SLAB = (0x16, 0x12, 0x2e, 255)   # between the first two stone steps: the body of a panel
SLAB_HI = (0x1c, 0x18, 0x3a, 255)


def noise(w, h, base, hi, lo, seed, rate=0.07):
    """A flat fill with a few lighter and darker specks, so large slabs do not look printed."""
    cv = Canvas(w, h, base)
    r = Rng(seed)
    for y in range(h):
        for x in range(w):
            v = r.next()
            if v > 1.0 - rate:
                cv.set(x, y, hi)
            elif v < rate * 0.8:
                cv.set(x, y, lo)
    return cv


def round_corners(cv, radius=1):
    """Cuts the corner pixel(s) so slabs read as cut stone rather than rectangles."""
    for (x, y) in ((0, 0), (cv.w - 1, 0), (0, cv.h - 1), (cv.w - 1, cv.h - 1)):
        cv.set(x, y, (0, 0, 0, 0))


def ring(cv, inset, colour):
    """A 1 px rectangle `inset` pixels from the edge."""
    for x in range(inset, cv.w - inset):
        cv.set(x, inset, colour)
        cv.set(x, cv.h - 1 - inset, colour)
    for y in range(inset, cv.h - inset):
        cv.set(inset, y, colour)
        cv.set(cv.w - 1 - inset, y, colour)


def rune_line(cv, inset, base, glint, period=8):
    """A carved rune line: a steady stroke with a lit glint every `period` pixels (the pattern tiles in a 9-slice)."""
    for x in range(inset + 2, cv.w - inset - 2):
        c = glint if x % period == period // 2 else base
        cv.set(x, inset, c)
        cv.set(x, cv.h - 1 - inset, c)
    for y in range(inset + 2, cv.h - inset - 2):
        c = glint if y % period == period // 2 else base
        cv.set(inset, y, c)
        cv.set(cv.w - 1 - inset, y, c)


def node(cv, x, y, lit):
    """A corner node: a small diamond, lit or dim."""
    core, edge = (BRASS[4], BRASS[3]) if lit else (BRASS[3], BRASS[2])
    cv.set(x, y, core)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        cv.set(x + dx, y + dy, edge)


def panel(path, size=24, seed=3, lit=False):
    cv = noise(size, size, SLAB, SLAB_HI, DEEP, seed)
    ring(cv, 0, INK)
    ring(cv, 1, STONE[2])                       # the slab's cut edge, lit from above
    for x in range(1, size - 1):
        cv.set(x, 1, STONE[3])                  # top edge catches the light
    for y in range(1, size - 1):
        cv.set(1, y, STONE[3])
        cv.set(size - 2, y, STONE[1])
    for x in range(1, size - 1):
        cv.set(x, size - 2, STONE[1])
    ring(cv, 2, DEEP)
    rune_line(cv, 3, BRASS[3 if lit else 2], BRASS[4])
    ring(cv, 4, STONE[0])
    for (x, y) in ((4, 4), (size - 5, 4), (4, size - 5), (size - 5, size - 5)):
        node(cv, x, y, lit)
    round_corners(cv)
    cv.save(path)


def slate(path, size=16, seed=11):
    cv = noise(size, size, STONE[1], STONE[2], STONE[0], seed, 0.09)
    ring(cv, 0, INK)
    ring(cv, 1, STONE[0])
    for i in range(1, size - 1):
        cv.set(i, 1, STONE[2])
    cv.save(path)


def button(path, fill, top, edge, glow=None, glint=None, size=16, seed=5):
    cv = noise(size, size, fill, top, mix(fill, INK, 0.3), seed, 0.05)
    ring(cv, 0, INK)
    ring(cv, 1, edge)
    for x in range(2, size - 2):           # a lit top lip and a dark underside: the slab stands proud
        cv.set(x, 2, top)
        cv.set(x, size - 3, mix(fill, INK, 0.45))
    for x in range(1, size - 1):
        cv.set(x, 1, glow or mix(edge, top, 0.5))
    if glint:                              # a glowing rune tick at both ends of the lip
        for x in (3, size - 4):
            cv.set(x, 1, glint)
    round_corners(cv)
    cv.save(path)


def slot(path, size=18, lit=False, seed=21):
    cv = noise(size, size, DEEP, STONE[1], INK, seed, 0.05)
    ring(cv, 0, INK)
    ring(cv, 1, BRASS[3] if lit else STONE[1])
    for i in range(2, size - 2):
        cv.set(i, 2, STONE[0])
        cv.set(2, i, STONE[0])
    for (x, y) in ((1, 1), (size - 2, 1), (1, size - 2), (size - 2, size - 2)):
        cv.set(x, y, BRASS[4] if lit else BRASS[2])
    cv.save(path)


def bar(path, w=48, h=6):
    cv = Canvas(w, h, INK)
    for x in range(1, w - 1):
        cv.set(x, 1, STONE[1])
        cv.set(x, h - 2, STONE[0])
    for y in range(1, h - 1):
        cv.set(1, y, STONE[1])
        cv.set(w - 2, y, STONE[0])
    cv.save(path)


def divider(path, w=64, h=5):
    cv = Canvas(w, h)
    mid = w // 2
    for x in range(2, w - 2):
        if abs(x - mid) > 4:
            cv.set(x, 2, BRASS[3] if (x % 8) == 4 else BRASS[2])
    for dx, dy in [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)]:
        cv.set(mid + dx, 2 + dy, BRASS[4] if (dx, dy) == (0, 0) else BRASS[3])
    for dx in (-3, 3):
        cv.set(mid + dx, 2, BRASS[3])
    cv.save(path)


def title_banner(path, w=120, h=26):
    """The slab behind the game title: a darker body, a lit rune line and a row of ticks along the bottom."""
    cv = noise(w, h, mix(SLAB, DARK[0], 0.4), mix(SLAB_HI, DARK[1], 0.3), INK, 31, 0.06)
    ring(cv, 0, INK)
    ring(cv, 1, STONE[2])
    rune_line(cv, 3, BRASS[2], BRASS[4], 8)
    ring(cv, 2, DEEP)
    for x in range(10, w - 10, 4):
        cv.set(x, h - 6, BRASS[2] if (x // 4) % 2 else BRASS[3])
    for (x, y) in ((5, 5), (w - 6, 5), (5, h - 6), (w - 6, h - 6)):
        node(cv, x, y, True)
    round_corners(cv)
    cv.save(path)


panel(os.path.join(OUT, 'panel.png'))
slate(os.path.join(OUT, 'parchment.png'))
button(os.path.join(OUT, 'button_normal.png'), STONE[1], STONE[2], STONE[2])
button(os.path.join(OUT, 'button_hover.png'), mix(STONE[1], STONE[2], 0.6), STONE[3], BRASS[3], glow=BRASS[3], glint=BRASS[4], seed=6)
button(os.path.join(OUT, 'button_pressed.png'), BRASS[2], BRASS[3], BRASS[4], glow=BRASS[4], glint=BRASS[4], seed=7)
button(os.path.join(OUT, 'button_disabled.png'), STONE[0], STONE[1], STONE[1], seed=8)
button(os.path.join(OUT, 'button_focus.png'), mix(STONE[1], STONE[2], 0.6), STONE[3], style.ramp("water")[3], glow=style.ramp("water")[3], glint=style.ramp("water")[4], seed=6)
slot(os.path.join(OUT, 'slot.png'))
slot(os.path.join(OUT, 'slot_selected.png'), lit=True)
bar(os.path.join(OUT, 'bar_frame.png'))
divider(os.path.join(OUT, 'divider.png'))
title_banner(os.path.join(OUT, 'title_banner.png'))
print('ui frames ->', os.path.abspath(OUT))
