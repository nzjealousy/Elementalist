"""The Noir Silhouette colouring of hero-rig sprites (Python twin of HeroComposer._color_of in scripts/character/hero_composer.gd).

Bodies are near-black and desaturated in three hard tones; everything that is magic glows in ONE accent colour, the "glow", which the game
sets from the element the hero has selected (or the enemy's element). Eyes, gems and the hard rim light on the lit upper-left edge take it.
Keep the two implementations in step: tests/combo_selftest.gd checks the composer against these numbers.
"""
from pixel import hexc, mix

REGION_KEY = {1: 'skin', 2: 'hair', 3: 'outfit', 4: 'trim', 5: 'pants', 6: 'boots', 7: 'head', 8: 'headtrim', 9: 'cape',
              10: 'accent', 11: 'metal', 12: 'wood', 13: 'gem'}
DEFAULT_GLOW = '9cf0d8'
NIGHT = (16, 14, 34)


def base(rgb):
    """A palette colour as it appears in the dark: half the saturation, 46% of the light, a breath of night blue."""
    r, g, b = rgb[:3]
    luma = 0.3 * r + 0.59 * g + 0.11 * b
    c = [(luma + (v - luma) * 0.5) * 0.46 for v in (r, g, b)]
    return tuple(int(c[i] * 0.88 + NIGHT[i] * 0.12) for i in range(3))


def colour(region, shade, pal):
    """The colour of a pixel: region (1..15), shade (0 outline, 1 dark, 2 base, 3 light, 4 glint) under palette `pal` (hex strings)."""
    glow = hexc(pal.get('glow', DEFAULT_GLOW))[:3]
    if region == 14:                                  # eyes: the glow, hot
        c = mix(glow + (255,), (255, 250, 255, 255), 0.35)[:3]
        return tuple(c) + (255,) if shade else tuple(int(v * 0.3 + 4) for v in c) + (255,)
    if region == 13:                                  # gems: the glow itself
        k = {0: 0.25, 1: 0.55, 2: 0.9, 3: 1.1, 4: 1.3}[shade]
        return tuple(min(255, int(v * k)) for v in glow) + (255,)
    if region == 15:
        rgb = (150, 146, 176)
    elif region == 11:
        rgb = tuple(min(255, int(v * 1.35)) for v in base(hexc(pal['metal'])))
    else:
        rgb = base(hexc(pal[REGION_KEY[region]]))
    if shade == 0:                                    # the outline: nearly black, tinted by what it borders
        return tuple(int(rgb[i] * 0.25 + (6, 5, 16)[i]) for i in range(3)) + (255,)
    if shade == 1:
        return tuple(int(rgb[i] * 0.62 * 0.8 + (8, 6, 22)[i] * 0.2) for i in range(3)) + (255,)
    if shade == 3:
        return tuple(min(255, int(v * 1.3 + 5)) for v in rgb) + (255,)
    if shade == 4:                                    # a glint takes some of the glow
        lit = tuple(min(255, int(v * 1.45 + 8)) for v in rgb)
        return tuple(int(lit[i] + (glow[i] - lit[i]) * 0.5) for i in range(3)) + (255,)
    return rgb + (255,)


def rim(c, glow_hex):
    """A lit upper-left edge pixel: mostly the glow."""
    glow = hexc(glow_hex)[:3]
    return tuple(int(c[i] + (glow[i] - c[i]) * 0.8) for i in range(3)) + (255,)
