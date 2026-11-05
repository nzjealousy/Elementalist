# Elementalist — Development Roadmap

Each phase ends with something **playable** and a short review with you before the next begins. Durations are rough for a solo dev with Claude assisting.

| # | Phase | Deliverable / exit criteria | Est. |
|---|---|---|---|
| 0 | **Pre-production** | Godot 4 installed, project scaffolded, git repo, folder layout, AssetDB with placeholder generator, CI-less test runner. GDD signed off. | 2–3 d |
| 1 | **Core prototype** | WASD movement, 8-dir facing, camera, tilemap room, collision, pixel-perfect scaling, input mapping, pause menu. | 1 wk |
| 2 | **Combat and elements engine** | Mouse-aim casting, cooldown/mana, dodge, enemy AI (chase/ranged), health/damage, status effects. 3 elements with 2 skills each, combo resolver (e.g. Fire+Water), hit feedback. | 2 wk |
| 3 | **Character systems** | Attributes, element mastery, weapon mastery, XP/leveling, 2 classes + subclass data, skills vs elements enforced in code, passives, **ceremony roll** with tests. | 2 wk |
| 4 | **Items, loot, crafting** | Inventory/equipment UI, rarities, drops from enemies and chests, upgrade/enchant, one crafting station. | 2 wk |
| 5 | **Roguelike run structure** | Room generator, run loop (hub → dungeon → death/win → hub), persistent meta-progress, save/load. | 2 wk |
| 6 | **Story and world** | Dialogue system, quest system, NPCs, village hub, character creation, ceremony cutscene, first boss with parry/stagger. | 3 wk |
| 7 | **Vertical slice polish** | Lighting, particles, audio hooks, UI pass, balancing, bug-fix, playtest build. **Decision point:** continue, adjust, or cut. | 2 wk |
| 8+ | **Content expansion** | Light/Dark, remaining main elements and combos, man-made arts, more classes, kingdoms, final art swap, Steam-ready build. | ongoing |

## Status (2026-11-05)

| Phase | State | Notes |
|---|---|---|
| 0 Pre-production | Done | Godot 4.7 project in `elementalist/`, AssetDB placeholders, input map, git repo, README and architecture docs. Not pushed to GitHub yet. |
| 1 Core prototype | Done, except pause menu | Pixel-perfect 320x180 view, WASD, dodge, camera limits. Test room uses sprites, not a TileMap. |
| 2 Combat and elements | Done | LMB element bolt, Q area skill, 1-5 / wheel to switch element, RMB stamina slash, all 10 combos, auras, status effects, hit-stop/shake/particles. Only the slime enemy so far (no ranged enemy). |
| 3 Character systems | Done | `CharacterData` (attributes, XP, element + weapon mastery, subclass, traits, save/load dict), ceremony with a no-element outcome and martial skills for non-elementalists, skills-vs-elements gating, attribute scaling of skills and elements, four passive types, four classes (Channeler, Vanguard, Ranger, Mystic), tabbed character sheet (TAB) with combo list and rewards, new-character menu (N), class chosen at level 3, Q at level 5, subclass at level 10, milestone rewards (special skills and passives), class melee reach, melee imbue (E), element locking and fusion (Q), melee vs ranged class styles, resonance and martial combos, dodge spin, reward cards. 344 in-game self-tests (`tests/combo_selftest.tscn`). |
| 4.1 Content and dungeon | Done | Six attributes (new Wisdom and Luck, crits), eight classes with sixteen subclasses, buff and debuff support skills (V, level 7), skill VFX and damage indicators, five monsters plus elemental variants, two bosses that drop elemental gems (attune to a new element), and a randomly generated 3-floor dungeon whose last floor is the boss, with doors that unlock when the wave is cleared. 683 in-game self-tests. |
| 4.2 Resource rework | Done (820 self-tests) | Slow recovery and harder monsters; fusion costs more per element and Q locks any number; one imbued element; rebalanced Elemental Harmony; cheaper ability chains; Dexterity (attack speed); losing elements on death and permadeath; class and subclass cards with class mastery; melee/ranged/both monsters with dash and dodge; HUD reorganised (elements bottom left, actions bottom right, Q shows the combo); traits, passives and gear reworked around kills, mana cost and attack speed. |
| 5 Run structure, saves, shell | Done | Title screen, three save slots (atomic, versioned, with backup), oath (difficulty), camp hub, tiered dungeons (5 floors, then 10) with mini bosses, runs leaderboard, settings, pause menu, gamepad support with rebinding, medieval UI theme, compact HUD with a size setting, Light and Dark elements, generated sprites/tiles/effects and audio. 952 self-tests. Meta-progression across heroes and a branching map are open questions in `docs/CORE_LOOP.md`. |
| 6 Look, depth, together | Done (first playable) | Hero names; melee range ring; elements with their own mana, speed, area and traits (pierce, burst, fan, homing, drain); training grounds with an altar and a controls checklist; layered 24 x 38 heroes that change with class, subclass and gear (palette-region parts composed at run time), drawn in the Moonlit Glyphwork style (rune elements, obsidian UI); class and reward cards with sprites and class borders; an equipment paper doll; five dungeons (5, 10, 12, 15, 20 floors) with new monsters, bosses and themes; the 2D isometric view; co-op for up to four and an arena duel over ENet. 1112 self-tests, an art gate (`tools/art/check_art.py`) and a two-process network test (`tools/run_net_test.ps1`). |
| 4 Items, loot, crafting | Done | Six gear slots, five rarities (0-4 random affixes), item level and +0 to +10 upgrades; the wielded weapon sets the weapon type and which mastery grows; drops from enemies (gold, scrap, slime gel, essence of the killing element, gear) and chests (every third wave); one forge station (craft, upgrade, enchant with essence, salvage); Gear tab (`I`), forge screen, gold on the HUD. 480 in-game self-tests. |

**Phase 6 decisions to revisit:** the art is still generated by script (`tools/art`), now in the Moonlit Glyphwork style (docs/ART_DIRECTION.md:
runes for elements, a cold world with glowing magic, 24 x 38 heroes), and an artist will want to redo it; monsters are recoloured, not yet redrawn; the five dungeon lengths (5, 10, 12, 15, 20 floors), the gentler monster scaling past depth 10,
the element numbers on the altar, the arena damage (70%) and the co-op rules (a fallen hero returns after 5 s, no penalty) are first guesses.
The isometric view is a 2D skew of the flat game: collisions and aiming stay flat. Multiplayer was tested over loopback with two real
processes, not across a network; the host's pause freezes the world for everyone; guests cannot use the forge or the gate during a session.

**Phase 5 decisions to revisit:** all art and audio is procedural and meant as a solid stand-in (a human
artist and composer will want to redo it); the tier numbers (5 then 10 floors, a mini boss every third),
the 30% gold loss, the oath multipliers, the leaderboard score formula and the Light/Dark skill numbers are
first guesses. Light and Dark gems drop only from the second dungeon's bosses (60%); the ceremony's 2%
rare roll still exists. The camp is a single room: NPCs, dialogue and the ceremony cutscene are Phase 6.
The dungeon is still linear. Gamepad bindings were checked by tests and the input map, not on hardware.

**Phase 3 decisions to revisit:** all balance numbers (attribute formulas, XP curve, mastery bonuses, ceremony odds, trait pool, rare-passive thresholds) are first guesses. Light and Dark roll but have no skills yet (passive only). The N menu stands in for the full character creation of Phase 6. F10 stands in for an attunement item until items exist (Phase 4). Debug keys in the arena: F5 sandbox, F10 attune. Combat still uses only the slime enemy.

**Phase 4 decisions to revisit:** every number (drop chances, rarity weights, upgrade and craft
costs, +10% per level) is a first guess. Gear is not restricted by class (any class can wield any
weapon; the style of fighting still comes from the class). Upgrades never fail and nothing breaks:
forgiving, in line with the tone question below. Light and Dark have no essence or enchant yet.
Enchants are stat bonuses, not free elemental hits (so a sealed character cannot fake elements
with gear). There is no shop, and no stash that survives death: both belong to Phase 5. Only the
slime exists, so all drops are slime-themed. Debug key `F6` opens the forge from anywhere.

**Phase 4.1 decisions to revisit:** gems are *attunement* items (one gem = one new element for good,
the first real way to gain elements after birth). The dungeon is linear (3 rooms a floor) rather than a
branching map, and dying just ends the run with the same character: both belong to Phase 5 (save/load,
meta-progress, a hub). Only one boss exists per run (random of two). Balance is a first guess everywhere.

## Working agreements

- Systems before content; content lives in data files.
- Every phase: playable build, short notes on what changed, open questions for you.
- Anything creative (names, lore, balance feel) is proposed to you first.

## Open questions for you

1. Hub-and-run structure OK (GDD §6)?
2. "Creator creation" = character creation, or an editor?
3. Is the ceremony roll fully random, or should you get some influence (e.g. choose a ritual that tilts odds)?
4. Death penalty tone: Hades-forgiving or Lies-of-P-punishing?
5. Gamepad support in the slice, or keyboard and mouse only?
