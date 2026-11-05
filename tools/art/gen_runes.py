"""Element rune icons -> elementalist/assets/ui/rune_<element>_<size>.png. Run: python tools/art/gen_runes.py

The element glyphs of docs/ART_DIRECTION.md as pictures: a carved dark disc, an inscribed ring with tick marks and an
angular glowing glyph (fire a rising triangle, water a falling one, air a spiral, mineral a diamond, earth a square with
a sprout, light eight rays, dark a crescent; martial is two crossed blades and not an element).
    _s   18 x 18   hotbar and skill slots
    _m   30 x 30   lists and the character sheet (ring ticks drawn)
    _l   40 x 40   cards and altars (with a glow)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import style

style.use("moonlit")

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'ui')
os.makedirs(OUT, exist_ok=True)

ELEMENTS = ["fire", "water", "air", "mineral", "earth", "light", "dark", "martial"]
SIZES = {"s": dict(size=12, glow=False), "m": dict(size=24, glow=False), "l": dict(size=28, glow=True)}

for element in ELEMENTS:
    for tag, kwargs in SIZES.items():
        style.rune(element, **kwargs).save(os.path.join(OUT, "rune_%s_%s.png" % (element, tag)))
print("runes ->", os.path.abspath(OUT), len(ELEMENTS) * len(SIZES), "files")
