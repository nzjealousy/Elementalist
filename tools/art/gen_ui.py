"""Medieval-fantasy UI frames (9-slice sources) -> elementalist/assets/ui/. Run: python tools/art/gen_ui.py"""
import os
import sys
sys.path.insert(0, os.path.dirname(__file__))
from pixel import Canvas, hexc, shade, mix, Rng

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'ui')
os.makedirs(OUT, exist_ok=True)

GOLD = hexc('d4a94a'); GOLD_HI = hexc('f6df94'); GOLD_LO = hexc('8a6522'); GOLD_DK = hexc('4a3512')
STONE = hexc('231b16'); STONE_HI = hexc('2d241d'); STONE_LO = hexc('170f0c')
IRON = hexc('5b5f6b'); IRON_HI = hexc('8d93a3'); IRON_LO = hexc('2a2c34')
LEATHER = hexc('5a3a22'); LEATHER_HI = hexc('7a5232'); LEATHER_LO = hexc('34200f')
PARCH = hexc('d9c391'); PARCH_HI = hexc('ebdcb0'); PARCH_LO = hexc('a98f5c'); INK = hexc('3a2a14')


def textured(w, h, base, hi, lo, seed):
    cv = Canvas(w, h, base)
    r = Rng(seed)
    for y in range(h):
        for x in range(w):
            v = r.next()
            if v > 0.86:
                cv.set(x, y, hi)
            elif v < 0.10:
                cv.set(x, y, lo)
    return cv


def frame(cv, outer, inner, hi, lo, inset=0):
    """A bevelled 1px border: light top/left, dark bottom/right."""
    w, h = cv.w, cv.h
    for x in range(inset, w - inset):
        cv.set(x, inset, hi); cv.set(x, h - 1 - inset, lo)
    for y in range(inset, h - inset):
        cv.set(inset, y, hi); cv.set(w - 1 - inset, y, lo)
    cv.set(inset, h - 1 - inset, mix(hi, lo, 0.5)); cv.set(w - 1 - inset, inset, mix(hi, lo, 0.5))


def stud(cv, x, y):
    cv.set(x, y, GOLD_HI); cv.set(x + 1, y, GOLD); cv.set(x, y + 1, GOLD); cv.set(x + 1, y + 1, GOLD_LO)


def panel(path, size=24, seed=3):
    cv = textured(size, size, STONE, STONE_HI, STONE_LO, seed)
    for x in range(size):  # outer dark rim, gold line, dark gap, inner gold hairline
        for ring, col in enumerate([GOLD_DK, GOLD, GOLD_LO, STONE_LO]):
            cv.set(x, ring, col); cv.set(x, size - 1 - ring, col)
            cv.set(ring, x, col); cv.set(size - 1 - ring, x, col)
    for i in range(1, size - 1):
        cv.set(i, 1, GOLD_HI if i % 2 == 0 else GOLD); cv.set(1, i, GOLD_HI if i % 2 == 0 else GOLD)
    stud(cv, 1, 1); stud(cv, size - 3, 1); stud(cv, 1, size - 3); stud(cv, size - 3, size - 3)
    cv.save(path)


def parchment(path, size=16, seed=11):
    cv = textured(size, size, PARCH, PARCH_HI, PARCH_LO, seed)
    for i in range(size):
        for ring, col in enumerate([INK, PARCH_LO]):
            cv.set(i, ring, col); cv.set(i, size - 1 - ring, col)
            cv.set(ring, i, col); cv.set(size - 1 - ring, i, col)
    cv.save(path)


def button(path, base, hi, lo, border, size=16, seed=5, glow=None):
    cv = textured(size, size, base, hi, lo, seed)
    for i in range(size):
        cv.set(i, 0, border); cv.set(i, size - 1, border); cv.set(0, i, border); cv.set(size - 1, i, border)
    for p in [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)]:
        cv.set(*p, (0, 0, 0, 0))
    frame(cv, border, border, shade(hi, 1.25), shade(lo, 0.8), inset=1)
    if glow:
        for i in range(2, size - 2):
            cv.set(i, 2, glow); cv.set(i, size - 3, shade(glow, 0.7))
    cv.save(path)


def slot(path, size=18, accent=IRON_HI, seed=21):
    cv = textured(size, size, IRON_LO, shade(IRON_LO, 1.4), shade(IRON_LO, 0.7), seed)
    for i in range(size):
        cv.set(i, 0, IRON); cv.set(i, size - 1, GOLD_DK); cv.set(0, i, IRON); cv.set(size - 1, i, GOLD_DK)
    for i in range(1, size - 1):
        cv.set(i, 1, accent); cv.set(1, i, accent)
        cv.set(i, size - 2, STONE_LO); cv.set(size - 2, i, STONE_LO)
    cv.save(path)


def bar(path, w=48, h=6):
    cv = Canvas(w, h, STONE_LO)
    for x in range(w):
        cv.set(x, 0, GOLD_LO); cv.set(x, h - 1, GOLD_DK)
    for y in range(h):
        cv.set(0, y, GOLD_LO); cv.set(w - 1, y, GOLD_DK)
    cv.save(path)


def divider(path, w=64, h=5):
    cv = Canvas(w, h)
    mid = w // 2
    for x in range(2, w - 2):
        if abs(x - mid) > 3:
            cv.set(x, 2, GOLD_LO if x % 3 else GOLD)
    for dx, dy in [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)]:
        cv.set(mid + dx, 2 + dy, GOLD_HI if (dx, dy) == (0, 0) else GOLD)
    cv.save(path)


def title_banner(path, w=120, h=26):
    """A hanging gold-trimmed banner behind the game title."""
    cv = textured(w, h, hexc('3a1418'), hexc('4a1c20'), hexc('2a0c10'), 31)
    for x in range(w):
        for ring, col in enumerate([GOLD_DK, GOLD, GOLD_LO]):
            cv.set(x, ring, col); cv.set(x, h - 1 - ring, col)
    for y in range(h):
        for ring, col in enumerate([GOLD_DK, GOLD, GOLD_LO]):
            cv.set(ring, y, col); cv.set(w - 1 - ring, y, col)
    for i in range(0, 6):  # swallow-tail bottom notch
        for x in range(w // 2 - 6 + i, w // 2 + 6 - i):
            pass
    cv.save(path)


panel(os.path.join(OUT, 'panel.png'))
parchment(os.path.join(OUT, 'parchment.png'))
button(os.path.join(OUT, 'button_normal.png'), LEATHER, LEATHER_HI, LEATHER_LO, GOLD_DK)
button(os.path.join(OUT, 'button_hover.png'), shade(LEATHER, 1.35), shade(LEATHER_HI, 1.3), LEATHER, GOLD_LO, seed=6, glow=GOLD_LO)
button(os.path.join(OUT, 'button_pressed.png'), hexc('8a6a2c'), hexc('a98640'), hexc('5c4318'), GOLD_HI, seed=7, glow=GOLD_HI)
button(os.path.join(OUT, 'button_disabled.png'), hexc('2c2a28'), hexc('36332f'), hexc('1c1a19'), hexc('3a3733'), seed=8)
button(os.path.join(OUT, 'button_focus.png'), shade(LEATHER, 1.35), shade(LEATHER_HI, 1.3), LEATHER, GOLD_HI, seed=6, glow=GOLD)
slot(os.path.join(OUT, 'slot.png'))
slot(os.path.join(OUT, 'slot_selected.png'), accent=GOLD_HI)
bar(os.path.join(OUT, 'bar_frame.png'))
divider(os.path.join(OUT, 'divider.png'))
title_banner(os.path.join(OUT, 'title_banner.png'))
print('ui frames ->', os.path.abspath(OUT))
