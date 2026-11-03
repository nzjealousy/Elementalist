# Elementalist

A 2D pixel-art top-down action RPG with roguelike runs and a story-driven world, built in
**Godot 4** (GDScript). You are born into a medieval-fantasy kingdom where the world grants
people *elements*; skills are something else entirely, learned from others.

Inspirations: The Mageseeker (action magic), Witchbrook (a cozy, lived-in hub), Lies of P
(weighty bosses). Single player, PC.

> **Status:** early development. Phases 0-3 of [the roadmap](docs/ROADMAP.md) are done: a playable
> combat arena with the element/combo system, four classes, a ceremony, leveling and
> mastery. There is no story, inventory or world yet. All art is generated placeholder.

## Run it

1. Install [Godot 4.7](https://godotengine.org/download) (developed on 4.7.2; 4.4+ should work).
2. Open `elementalist/project.godot` in Godot and press **F5** (the main scene is `scenes/main.tscn`).

## Controls

| Input | Action |
|---|---|
| `WASD` | Move |
| Mouse | Aim |
| `LMB` (hold) | Cast the selected set's primary skill |
| `Q` | Area skill (unlocks at level 5; lands under the cursor, up to its range) |
| `R` | Special skill (learned only as a level reward) |
| `1`-`5` or mouse wheel | Select element (or the martial set) |
| `RMB` (hold) | Physical slash (stamina). Reach depends on your class |
| `E` | Imbue your blade with the selected element for 10 s (15 mana): slashes then carry the element |
| `Space` | Dodge roll (stamina, short i-frames) |
| `TAB` | Character sheet (tabs: Stats, Skills, Elements, Passives, Combos, Rewards) |
| `N` | New character: pick how they are born |
| `Esc` | Close a menu |

**Debug keys (arena only):** `F5` sandbox (all elements, level 10) - `F10` stand-in for an
attunement item: gain a random element.

## How it plays

- **Elements** come from the world: rolled at a coming-of-age ceremony (or gained later through
  items/story). Fire, Water, Air, Mineral and Earth are castable; Light and Dark exist but have
  no skills yet.
- **Combos:** hit an enemy with one element, then a different one within 4 seconds, for a bonus
  and a status effect (ten pairs, see the Combos tab).
- **Skills** are separate from elements: you can only cast a skill whose element you own and have
  learned. Characters born without elements learn **martial** skills (stamina-powered, no
  element) and can still be attuned later.
- **Progression:** everyone starts as a **Novice**. **Level 3:** choose a class (Channeler,
  Vanguard, Ranger or Mystic). **Level 5:** area skill (`Q`) unlocks. **Level 10:** choose a
  subclass. All classes have the same attribute budget; they differ in shape, passives and melee
  reach (Vanguard long, Channeler short).
- **Level rewards:** every even level except 10 offers 1-3 options, a skill (the `R` special of
  a set you have) or a passive, and you pick one on the Rewards tab.
- **Passives** come in four kinds: class, character traits (rolled at creation or chosen as
  rewards), rare element passives (mastery level 5) and rare skill passives (many uses of one
  skill).

## Tests

The game has an in-game self-test suite (it needs the autoloads, so it runs as a scene rather
than in the editor test runner):

1. In Godot, open `elementalist/tests/combo_selftest.tscn` and run it with **F6**.
2. Read the Output panel: one `PASS`/`FAIL` line per check and a final
   `SELFTEST <n> passed, <n> failed`.

## Project layout

```
docs/                     design and planning
  GDD.md                  game design document
  ROADMAP.md              phases and current status
  ARCHITECTURE.md         how the code fits together, and how to extend it
elementalist/             the Godot project
  scenes/                 main scene, player, enemies
  scripts/
    core/                 autoloads: Game, Elements, SkillDB, AssetDB, Juice
    character/            CharacterData, Classes (tables), Ceremony
    combat/               Enemy, Projectile, AoeEffect, health bar, hit effects
    player/               Player, SkillCaster, AimMarker
    ui/                   HUD, CharacterSheet, NewCharacterMenu, UiTheme
    world/                the test arena
  tests/                  in-game self-tests
  addons/godot_ai/        development tooling (MIT, see its LICENSE)
```

## Art

There is no art yet. `AssetDB` generates a coloured placeholder for any sprite id, and uses
`res://assets/sprites/<id>.png` instead if that file exists, so final art can be dropped in
without code changes.

## Third-party

`addons/godot_ai` ("Godot AI", MIT licensed, see `addons/godot_ai/LICENSE`) is an editor plugin used during
development to drive the editor from an AI assistant. The game does not depend on it, but the
project file registers it, so it ships in the repository with its own license.

## License

No license has been chosen yet. All rights reserved for now.
