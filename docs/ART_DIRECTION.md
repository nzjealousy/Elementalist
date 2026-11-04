# Art direction: three proposals (pick one)

Status: **proposed, not yet applied to the game.** Three complete styles are drawn by code (`tools/art/style.py`,
`tools/art/style_board.py`) so they can be compared on the same subjects. Run `python tools/art/style_board.py [gilded|moonlit|storybook]`
to redraw them into `docs/art/`. Once a style is chosen, the real restyle reuses the same functions.

Every board shows the same things: the seven element **runes**, an isometric dungeon corner (floor, walls, torchlight, a casting
circle, a bolt, a prop), a **detailed hero** and a monster, the UI kit (frame, hotbar, bars, buttons, text blocks), the twelve colour
ramps and three item icons.

| | A. Gilded Hollow | B. Moonlit Glyphwork | C. Autumn Storybook |
|---|---|---|---|
| Board | ![A](art/style_a_gilded_hollow.png) | ![B](art/style_b_moonlit_glyphwork.png) | ![C](art/style_c_autumn_storybook.png) |
| Mood | Jewel-toned, carved, a candlelit crypt | Cold, deep, everything magic glows | Warm, cosy, painted, a lantern-lit inn |
| Palette | Violet shadows, warm cream lights | Blue-violet world, saturated emissive accents | Earth tones, plum shadows, honey lights |
| Outline | Dark shade of the colour it touches | One ink line everywhere | Warm brown, lighter than ink |
| Environment | Bevelled stone, mossy bricks, brass and wood | Obsidian with glowing rune seams, floating glyph lanterns | Planks, plaster between timber, leaves |
| UI | Carved wood, brass studs, dark interior | Obsidian slab with a thin glowing rune border, slim light bars | Stitched leather around parchment, chunky bars |
| Reads best | Dungeons, loot, gear | Spells and combat (magic pops) | Camp, towns, long play sessions |
| Risk | Busiest to draw by hand | Low contrast between floor and walls | Magic is less dramatic against warm tones |

## What changed from the first proposal

1. **Elements are runes.** Each element is a carved dark disc with an inscribed ring of tick marks and an angular glowing glyph:
   fire a rising triangle with a flame sigil, water a falling triangle with waves, air a wind spiral, mineral a cut diamond with
   facets, earth a boundary square with a sprout, light an eight-ray radiance, dark a crescent with a void. The same rune is drawn
   as the hotbar slot icon (14 px), the card and altar emblem (32 px) and, squashed to an ellipse, as the **casting circle** on the
   floor under the hero (`style.rune`, `style.squash`). The glow recipe is white-hot core, saturated body, dark halo, coloured outer glow.
2. **Heroes are more detailed.** The proposed sprite is 24 x 38 instead of 16 x 26: a hat with band and gem, hair with a fringe and
   locks, a face with brows, eyes (sclera, iris, glint), nose and mouth, a mantle with a brass trim, an open robe with studs and a rune
   hem, a belt with buckle, pouch and vial, sleeves with cuffs, boots, a folded cape and a runed staff, with a rim light on the lit
   side. The size comparison sits beside it on each board. Applying it means growing hero frames to 24 x 38 in `tools/art/gen_heroes.py`
   (parts stay palette-region strips) and `HeroComposer`; hitboxes stay the same.

## Rules shared by all three

1. **Ramps, not colours.** Every hue is a 5-step ramp (`style.STYLES[...]["ramps"]`); shadows lean cool, lights lean warm; no pure black or white.
2. **Light from the top left**: bevel highlights on upper-left edges, a rim light on characters, shaded right faces on walls.
3. **One outline rule per style** (`style.outline`).
4. **Glow is a recipe** for spells, runes, gems and torches.
5. **Shadows are tinted, never black**, dithered blobs on the floor.
6. **Detail by clusters**: dense detail on heroes, props and UI, calm floors underneath so sprites always read.

## Element identity colours

The seven element ramps are the identity of everything element-related: bolts, area rings, hotbar slots, damage numbers, card borders,
status icons, casting circles. One element, one ramp, everywhere.

## Production plan (each step ends with the self-tests and a screenshot)

1. **Palette and tools.** The chosen style becomes the default in `style.py`; `pixel.py` gains ramp snapping so older generators can use it.
2. **Runes and VFX.** Runes replace the element icons (hotbar, cards, altar, combo list); bolts, area rings, hit bursts and status marks follow the glow recipe; area spells draw their casting circle.
3. **UI and HUD.** `tools/art/gen_ui.py` produces the chosen frame, buttons, bars and slots; `UiTheme` loads them. Layout does not move.
4. **Heroes.** 24 x 38 frames, ramp-mapped regions, rim light, coloured outline; gear icons match.
5. **Monsters and bosses.** One family at a time, checked against the readability gate.
6. **Tiles, walls and props.** Five themes follow the chosen environment rules; props gain cast shadows.
7. **Items.** Weapons, armour, potions and materials as 16 x 16 icons.

## Acceptance gates

* Every sprite reads at native size, in motion, over every theme's floor (contact sheet plus an in-game screenshot).
* One light direction, one outline rule, no pure black or white (a script checks every PNG).
* The same element is the same colour on bolts, areas, hotbar, cards and numbers (self-test).
* Self-tests stay green after each step; `tools/art` stays dependency-free (standard library only).

## References and provenance

Six reference images (an elemental emblem set, a painterly top-down action scene, two cosy isometric village scenes, an
isometric autumn scene and an isometric farm scene) were studied for technique only: ramps, outlines, light pools and block faces.
No shape, character, prop or layout is copied, none of the images is stored here, and every picture in the repository is drawn by
the scripts in `tools/art`.
