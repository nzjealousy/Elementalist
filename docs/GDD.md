# Elementalist — Game Design Document (v0.1)

2D pixel-art, top-down action RPG / roguelike / story adventure for PC.
Inspirations: The Mageseeker (action magic combat), Witchbrook (cozy, lived-in world and hub), Lies of P (weighty bosses, dark tone, parry and stagger).

**Locked decisions:** Godot 4 (GDScript) · tight vertical slice first · placeholder art loaded by ID · real-time top-down combat (WASD move, mouse aim/cast).

---

## 1. Pillars

1. **The world gives you elements; people give you skills.** The two systems never merge (see §3).
2. **Combos are the fun.** Mixing elements should feel discovered, not menu-picked.
3. **Story survives death.** Dying resets the run, never the narrative.
4. **Beautiful, readable scenery.** Light, weather and palette carry the mood more than sprite count.

## 2. Elements

| Tier | Elements | How you get them |
|---|---|---|
| Main | Fire, Air, Mineral, Water, Earth (nature/plants) | Coming-of-age ceremony roll; later via story or special items |
| Rare | Light, Dark | Very rare ceremony roll; story or items |
| Man-made ("Arts") | Music, Art, others later | Not rolled. Story, mentors, or relics. Treated as a separate category so we can add more freely |

**Starting elements (proposed, all tunable in data):** exactly 1 guaranteed; ~15% chance of a 2nd; ~3% of a 3rd; ~2% for Light or Dark (own roll). Can be pushed toward "all elements" late game via story and items.

**Combinations.** Any 2 main elements produce a combined element. Ten pairs, defined in a data table:

| Pair | Combo | Pair | Combo |
|---|---|---|---|
| Fire + Water | Steam | Water + Mineral | Crystal / Brine |
| Fire + Air | Lightning / Storm | Air + Earth | Spore / Pollen |
| Fire + Earth | Ash / Ember | Air + Mineral | Sand / Dust |
| Fire + Mineral | Magma | Earth + Mineral | Amber / Petrify |
| Water + Air | Frost | Water + Earth | Swamp / Growth |

(Names are placeholders. Combo requires owning both elements, *or* hitting an enemy already affected by one element with the other.)

**Light / Dark are modifiers, not combos.** Combined with another element they add a buff (Light: heal, shield, reveal, cleanse) or a debuff (Dark: curse, drain, blind, fear).

**Element mastery** levels with use and unlocks passives and tiers of effect.

## 3. Elements vs Skills (core rule)

- **Element** = an affinity from the world. Determines which damage types and passives you have, your mana flavor, and which skills you can *use*.
- **Skill** = a learned ability obtained, taught, found or inherited. Can be element-tagged (needs that affinity) or untagged (anyone can use).
- **Passives** can come from an element, a skill, or both.
- **Non-elementalists:** skills only. Two kinds for the player: **Sealed** (can never hold elements) and **Attunable** (can gain elements via item or story). NPCs can be either.

## 4. Classes and Subclasses

Slice: 2 classes, with subclasses as placeholders in data. More added later.

- **Mage-type (Channeler):** ranged caster, element-heavy.
- **Warrior-type (Vanguard):** melee with weapon masteries, element-infused strikes.
- Later: Ranger, Summoner, Artisan (man-made arts), etc.

Class decides weapon masteries, base attribute growth and starting skill tree. It does **not** decide elements.

## 5. Progression

- **Character attributes** (STR/AGI/INT/VIT/etc., finalized in Phase 3) level by player-chosen points plus use.
- **Element masteries:** per element, leveled by casting and combos.
- **Weapon masteries:** per weapon type.
- **Gear:** rarity, level, enchants, upgrade and craft.

## 6. Game structure (proposal, needs your OK)

**Hub-and-run, Hades style:** a living hub town (Witchbrook-like: NPCs, schedules, crafting stations, story scenes) and runs into dungeons/wilds (roguelike: room-by-room, randomized rooms/loot/boons). Death returns you to the hub. Persistent: element/weapon mastery, story flags, unlocked recipes, hub upgrades. Reset per run: temporary boons, most carried loot (a small safe stash persists).

## 7. Controls

WASD move · mouse aim · LMB/RMB and number keys cast skills · Space dodge · E interact. Point-click skills (ground-target and aimed). Bosses add a parry/stagger window (Lies of P influence).

## 8. Tone and setting

Medieval fantasy: kingdoms, monsters, gods. Slice has one kingdom. Kingdom choice at game start is designed into the data model now but only one is shipped.

## 9. "Creator creation"

Interpreted as **character creation** (name, appearance, kingdom, pronouns, class) happening before the ceremony. *Please confirm — it could also mean a level/content editor.*

---

## 10. Vertical slice contents (the target for Phases 1–7)

Coming-of-age ceremony · 1 village hub · 1 dungeon with 3–4 room types · 3 elements (Fire, Water, Earth) + 1 combo set · 2 classes · ~4 enemy types · 1 boss · loot, equipment, basic craft/upgrade · short story arc with dialogue and 1–2 quests · save/load · controller-optional.

## 11. Technical approach

- **Data-driven:** elements, combos, skills, items, enemies, loot tables are `Resource` (`.tres`) or JSON files, not hard-coded. Adding an element or class should be adding data.
- **Placeholder-art contract:** every sprite is requested by string ID through one `AssetDB`; swapping real art is a file drop plus a manifest edit.
- **Pixel-perfect:** 320×180 base resolution (16:9) scaled by integer factors, 16px tiles. (Revisit if you want finer detail: 480×270.)
- **Folder layout:** `game/` (Godot project: `scenes/`, `scripts/`, `data/`, `assets/`), `docs/`.
- **Testing:** headless GDScript test runner (GUT) for the rules-heavy parts: element rolls, combo resolution, damage, loot.

---

## 12. Design updates (Phase 3)

- **Born without elements.** The ceremony has an 8% chance of granting no element. Such characters
  are *attunable*: they learn the **martial** skill set (stamina-powered, physical, no element),
  tend to roll more traits, and can still gain elements later through items or story. *Sealed*
  characters get the same martial set but can never hold elements. See `docs/ARCHITECTURE.md`.
- **Four classes** with an equal attribute budget (21 points + 1 per level): Channeler (caster),
  Vanguard (fighter), Ranger (skirmisher), Mystic (hybrid). Two subclasses each. Class melee reach
  differs: fighters reach far, casters barely at all.
- **Progression gates:** everyone starts as a Novice. Level 3: choose a class. Level 5: the area
  skill (Q) unlocks. Level 10: choose a subclass. Even levels except 10 give a **reward**: an
  offer of 1-3 options, a special skill (R) or a passive, of which you pick one.
- **Imbue (E):** a toggle. Coat your blade in your element(s) so slashes carry them (and set up
  combos). Ranged classes shoot only while imbued and slash when not; the melee class (Vanguard)
  has no ranged bolts and uses elements through imbue and abilities.
- **Element locking (Q, level 5):** lock up to 3 elements; the primary attack then fires one
  fused bolt hitting with each element in turn, so their combos trigger in a single shot. With no
  elements, Q is locked. Area skills moved to F.
- **More combos:** *resonance* (3 hits of one element in a row) and martial *Rend* (3 physical
  hits in a row).
- **Dodge spin:** attack while dodging for a costly 360 degree slash, which can be imbued.
- **Rewards appear as cards** in the middle of the screen, pausing the game.
- **New trait:** Jack of All Trades (small bonuses to everything).
- **Passives come in four types:** *class* (fixed), *trait* (rolled at creation, tied to the
  character; fewer other passive sources means more traits), *element* (rare, element mastery 5)
  and *skill* (rare, earned by using one skill many times).
- **Attributes shape skills and elements:** Intellect drives spell damage, each element has a
  governing attribute that scales its status effects, and individual skills scale their size,
  speed, knockback or cooldown from an attribute.
- **Level-ups heal 40% of max HP**, not all of it.
