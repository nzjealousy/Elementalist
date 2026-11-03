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

## Status (2026-11-03)

| Phase | State | Notes |
|---|---|---|
| 0 Pre-production | Done | Godot 4.7 project in `elementalist/`, AssetDB placeholders, input map, git repo, README and architecture docs. Not pushed to GitHub yet. |
| 1 Core prototype | Done, except pause menu | Pixel-perfect 320x180 view, WASD, dodge, camera limits. Test room uses sprites, not a TileMap. |
| 2 Combat and elements | Done | LMB element bolt, Q area skill, 1-5 / wheel to switch element, RMB stamina slash, all 10 combos, auras, status effects, hit-stop/shake/particles. Only the slime enemy so far (no ranged enemy). |
| 3 Character systems | Done | `CharacterData` (attributes, XP, element + weapon mastery, subclass, traits, save/load dict), ceremony with a no-element outcome and martial skills for non-elementalists, skills-vs-elements gating, attribute scaling of skills and elements, four passive types, four classes (Channeler, Vanguard, Ranger, Mystic), tabbed character sheet (TAB) with combo list and rewards, new-character menu (N), class chosen at level 3, Q at level 5, subclass at level 10, milestone rewards (special skills and passives), class melee reach, melee imbue (E). 254 in-game self-tests (`tests/combo_selftest.tscn`). |
| 4 Items, loot, crafting | Not started | Weapon type is currently fixed per class; equipment will set it. |

**Phase 3 decisions to revisit:** all balance numbers (attribute formulas, XP curve, mastery bonuses, ceremony odds, trait pool, rare-passive thresholds) are first guesses. Light and Dark roll but have no skills yet (passive only). The N menu stands in for the full character creation of Phase 6. F10 stands in for an attunement item until items exist (Phase 4). Debug keys in the arena: F5 sandbox, F10 attune. Combat still uses only the slime enemy.

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
