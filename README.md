# Elementalist

A 2D pixel-art top-down action RPG with roguelike runs and a story-driven world, built in
**Godot 4** (GDScript). You are born into a medieval-fantasy kingdom where the world grants
people *elements*; skills are something else entirely, learned from others.

Inspirations: The Mageseeker (action magic), Witchbrook (a cozy, lived-in hub), Lies of P
(weighty bosses). Single player, PC.

> **Status:** early development. Phases 0-4 of [the roadmap](docs/ROADMAP.md) are done: a randomly
> generated three-floor dungeon with a boss, the element/combo system, eight classes, a ceremony,
> leveling and mastery, gear, loot and a forge. There is no story, hub or save file yet. All art is
> generated placeholder.

## Run it

1. Install [Godot 4.7](https://godotengine.org/download) (developed on 4.7.2; 4.4+ should work).
2. Open `elementalist/project.godot` in Godot and press **F5** (the main scene is `scenes/main.tscn`).

## Controls

| Input | Action |
|---|---|
| `WASD` | Move |
| Mouse | Aim |
| `LMB` (hold) | **Fuse**: one bolt that hits with each of your locked elements in turn, so their combos fire in a single shot. Needs two or more locked; each extra element costs +30% mana and its hit is weaker (75% for two down to 50% for five). With no elements: a straight slash (melee classes) or a knife throw (ranged classes) |
| `RMB` (hold) | The basic attack: a slash (stamina), or, for ranged classes while imbued, a bolt of the selected element (mana). Reach depends on your class |
| `Q` | **Lock** the selected element (any number, up to all of yours). Needs two or more elements, no level required. The Q slot shows the combo the lock makes ("Steam") in its colour |
| `F` | Area skill (unlocks at level 5; lands under the cursor, up to its range) |
| `R` | Special skill (learned only as a level reward) |
| `1`-`5` or mouse wheel | Select element (or the martial set) |
| `E` | Toggle **imbue** (no cooldown, no timer). A blade holds **one** element, the selected one: slashes carry it for a little mana, and ranged classes can shoot it with RMB |
| `Space` | Dodge roll (stamina, short i-frames). **Dodge + RMB = a 360 degree spin**: costs more stamina, can be imbued, and you take no damage until it finishes |
| `G` | Use what you stand next to: open a chest, use the forge |
| `I` | Gear: open the character sheet on the Gear tab (click a bag item to wear it, a worn item to take it off) |
| `TAB` | Character sheet (tabs: Stats, Gear, Skills, Elements, Passives, Combos, Rewards) |
| `N` | New character: pick how they are born |
| `V` | Support skill (unlocks at level 7): a buff on yourself or a debuff on enemies |
| `Esc` | Close a menu |

The bottom of the screen: the element tabs (1-5) at the **bottom left**; the actions at the **bottom
right**: Fuse (LMB), Slash/Bolt (RMB, tinted with the imbued element), Q, then the abilities F, V, R.

**Debug keys (dungeon):** `[` clear the room, `]` jump to the boss.

**Debug keys (arena only):** `F5` sandbox (all elements, level 10, some gold, materials and gear) -
`F6` open the forge from anywhere - `F10` stand-in for an attunement item: gain a random element.

## How it plays

- **Elements** come from the world: rolled at a coming-of-age ceremony (or gained later through
  items/story). Fire, Water, Air, Mineral and Earth are castable; Light and Dark exist but have
  no skills yet.
- **Combos:** hit an enemy with one element, then a different one within 4 seconds, for a bonus
  and a status effect (ten pairs). Also **resonance** (3 hits of the same element in a row) and
  the martial **Rend** (3 physical hits within 3 s). See the Combos tab.
- **Fighting styles:** the Vanguard is a *melee* class: RMB always slashes, and it uses elements
  by imbuing its blade, fusing locked elements and its abilities (F, R). Channeler, Ranger,
  Mystic and the Novice are *ranged*: RMB shoots the selected element while imbued (mana per
  cast) and slashes when not.
- **No elements, no mana:** a sealed character (or one not yet attuned) has no mana pool and no
  mana bar. They fight with stamina and martial skills.
- **Elemental Harmony:** a passive that appears once you own two or more elements and grows with
  each extra one (+4% spell damage, +10 max mana, +6% fused damage per extra element).
- **Skills** are separate from elements: you can only cast a skill whose element you own and have
  learned. Characters born without elements learn **martial** skills (stamina-powered, no
  element) and can still be attuned later.
- **Progression:** everyone starts as a **Novice**. **Level 3:** choose a class (Channeler,
  Vanguard, Ranger or Mystic). **Level 5:** area skill (`Q`) unlocks. **Level 10:** choose a
  subclass. All classes have the same attribute budget; they differ in shape, passives and melee
  reach (Vanguard long, Channeler short).
- **Level rewards:** every even level except 10 offers 1-3 options, a skill (the `R` special of
  a set you have) or a passive. The game pauses and the options appear as cards in the middle of
  the screen; click one (or press its number). Esc postpones; claim later on the Rewards tab.
- **Passives** come in four kinds: class, character traits (rolled at creation or chosen as
  rewards), rare element passives (mastery level 5) and rare skill passives (many uses of one
  skill).

## Resources and death (the game is meant to be punishing)

- **Recovery is slow.** Health, stamina and mana come back at roughly half the old rate, and health
  recovery waits 6 seconds after a hit. Plan your fights: kills give back a little stamina and mana,
  and traits and gear can add health, mana or stamina per kill. Monsters hit 35% harder than their
  listed numbers, and a forge room heals only half your health.
- **Chaining abilities is cheaper.** An F/V/R ability of a *different element* than your last one,
  cast within 3 seconds, costs 30% less mana (a gold frame shows it on the slot).
- **More elements, more mana.** A fusion costs +30% per extra element. **Elemental Harmony** (owning
  two or more elements) gives small bonuses per extra element, but every spell also costs 4% more.
- **Attack speed** comes from the new **Dexterity** attribute (+3% per point) and from every character
  level (+1%). It speeds slashes, bolts and fusions, not abilities.
- **Dying costs elements.** If you have elements you survive, losing as many as the number of times
  you have died (one, then two, then three...), chosen at random; their mastery starts over. With no
  element left to lose, dying ends the character: you make a new one.
- **Classes are cards.** At level 3 pick any of the eight classes from a card screen. Your class gains
  **mastery** from kills; at class mastery 5 you choose a subclass (cards again).
- **Monsters** are melee, ranged or both; imps and duelists **dash** (after a warning flash), wraiths and
  duelists **dodge**. Both get sharper on deeper floors.

## The dungeon

Each run is a random dungeon of **three floors**: rooms of monster waves, a treasure room or a forge
(which also heals you) on every floor, and a boss at the end of the last. A room's exit door is **locked
until you defeat its wave(s)**; walking through it fades to the next room (loot on the floor is picked up
as you leave). Beat the boss, or die, and Enter starts a new dungeon with the same character.

- **Monsters:** slimes, cave bats, skeleton archers, wisps and stone brutes get tougher (and more
  elemental) each floor. An **elemental variant** shrugs off its own element and is weak to the one that
  beats it (water beats fire, earth beats water, fire beats earth, mineral beats air, air beats mineral).
- **Bosses** (Slime King, Stone Colossus) slam where a red circle warns you, and summon minions. They drop
  great loot and sometimes an **elemental gem**: use it on the Gear tab to attune to a new element.
- **Attributes:** Strength, Agility, Intellect, Vitality, **Wisdom** (mana regen, cooldowns, buff length)
  and **Luck** (crits, loot). **Eight classes**, each with two subclasses.
- **Support skills (`V`, level 7):** Blazing Might, Tidal Mending, Stone Skin, Tailwind (buffs),
  Fracture and Intimidate (debuffs).

## Gear, loot and the forge

- **Six slots:** weapon, head, body, feet, ring, amulet. Gear gives the same stats passives do
  (HP, mana, speed, damage, damage taken, ...). Items come in five **rarities**; the better the
  rarity the more random bonuses (0-4) and the stronger the base stats. Item level comes from the
  level you found it at and how deep you are.
- **The weapon you hold sets your weapon type** (sword, staff, bow, rod) and which weapon mastery
  grows. You start with a worn weapon for your class; any class can wield any weapon.
- **Loot:** enemies drop gold, scrap, slime gel and sometimes gear. Kill an enemy **with an element**
  and it may drop that element's *essence*. Every third wave a chest appears: walk up and press `G`.
  Pick things up by walking over them (gear waits on the floor if your 24-slot bag is full).
- **The forge** (the grey block at the top of the arena, `G` to use) can **craft** gear, **upgrade** it
  (+1 to +10, +10% of its stats each, never fails), **enchant** it with an essence for an extra
  bonus, and **salvage** bag items into scrap and gold.

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
    items/                Items (tables), Inventory, Forge, Loot
    combat/               Enemy, Monsters, SkillFx, Projectile, AoeEffect, Telegraph, hit effects
    player/               Player, SkillCaster, AimMarker
    ui/                   HUD, CharacterSheet, ForgeScreen, RewardCards, NewCharacterMenu, UiTheme
    world/                Dungeon, DungeonGen, Door, Pickup, Chest, ForgeStation
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
