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
- **RMB is the basic attack:** a slash, or (ranged classes, while imbued) a bolt of the selected
  element. **LMB is the fused cast.**
- **Imbue (E):** a toggle. Coat your blade in your element(s) so slashes carry them (and set up
  combos). Ranged classes shoot with RMB only while imbued; the melee class (Vanguard) always
  slashes and uses elements through imbue, fused casts and abilities.
- **Element locking (Q):** lock up to 3 elements (needs two or more); LMB then fires one fused
  bolt hitting with each element in turn, so their combos trigger in a single shot, and is
  disabled until then. With no elements, Q is locked and LMB is a straight slash (melee classes)
  or a knife throw (ranged classes). Area skills are on F (level 5) and specials on R (reward).
- **No elements, no mana:** sealed characters have no mana pool.
- **Elemental Harmony:** a multi-element passive; each extra element adds bonuses.
- **The dodge spin makes you immune** until it finishes.
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
- **Level-ups heal 40% of max HP**, not all of it. (Superseded: a level-up now heals fully, see section 18.)

## 15. Design updates (Phase 4.2: the game is about managing resources)

The aim: make the player think fast and plan ahead. Health, stamina and mana recover slowly, monsters hit
hard, and the choices that cost resources (more elements, more fusion, chained abilities) are made to matter.

- **Slow recovery, small refills.** Recovery is about half the old rate; a hit pauses health recovery for
  six seconds; a level-up heals a fifth; a forge room heals half. A kill gives back a little stamina and
  mana, and traits and gear can add health, mana or stamina per kill. (Superseded by the forgiving tuning,
  section 18: a 3 s pause, full heals at forges and level-ups, 15% on every cleared room.)
- **More elements cost more.** A fused cast costs +30% mana per extra element and each hit is weaker. Q
  can lock every element you own (the fuse needs two). A blade holds only one imbued element. **Elemental
  Harmony** (the multi-element passive) now gives small bonuses but makes every spell cost 4% more per
  extra element.
- **Chain your abilities.** An F/V/R ability of a different element within 3 seconds of the last costs 30% less.
- **Attack speed** is a new attribute (Dexterity) and grows a little with level.
- **Death costs elements; the story can end.** Dying with elements: lose one at random, and its mastery
  starts over. Dying with none: the character is gone and you create a new one.
- **Classes are a card choice**, and each class has **mastery** that opens its subclass.
- **Enemies** are melee, ranged or both; some dash after a warning flash, some dodge; both sharpen per floor.
- **Gear, passives and traits** were reworked around these systems (kills, mana cost, attack speed, dodge cost).

## 14. Design updates (Phase 4.1: content and the dungeon)

- **Six attributes:** the four old ones plus **Wisdom** (mana regen, shorter cooldowns, longer buffs) and
  **Luck** (crit chance, better loot).
- **Eight classes, sixteen subclasses.** New: Assassin (melee, dagger, crits), Berserker (melee, axe,
  fury), Sage (ranged, tome, wisdom), Druid (ranged, staff, regeneration).
- **Support skills (V, level 7):** buffs on yourself (Might, Mending, Stone Skin, Tailwind) and debuffs on
  enemies (Fracture makes them vulnerable, Intimidate weakens them).
- **Feedback:** per-element skill effects, red damage numbers and a hit indicator, "Dodge!", crits, and
  Resist/Weak labels on elemental monsters.
- **Monsters:** slime, cave bat (weaves), skeleton archer and wisp (ranged), stone brute (tank). Any may
  appear as an **elemental variant**: resistant to its own element, weak to the one that beats it
  (water > fire > earth > water, mineral > air > mineral), and a source of that element's essence.
- **Bosses** (Slime King, Stone Colossus): telegraphed slams and summoned minions. They **sometimes drop
  an elemental gem** that attunes you to an element you don't have.
- **The dungeon:** three randomly generated floors; each room is a wave fight (or a chest, or a forge
  and rest). The exit door stays locked until the wave is cleared. The last floor ends in the boss.

## 13. Design updates (Phase 4: items, loot, crafting)

- **Six gear slots:** weapon, head, body, feet, ring, amulet. Gear stats are the same stats
  passives and attributes give, so everything stacks through one system.
- **Rarity** (common, uncommon, rare, epic, legendary) decides how many random bonuses an item
  has (0 to 4) and scales its base stats. Items also have an **item level** (from the level you
  found them at, plus depth) and an **upgrade level** (+0 to +10, +10% of its stats each).
- **The weapon you hold sets your weapon type**, and each type trains its own mastery. A new
  character holds a worn starter weapon for their class; a better weapon you found is never
  swapped away when you pick a class at level 3. Any class can wield any weapon.
- **Loot:** kills drop gold, scrap, slime gel and sometimes gear. **Finish an enemy with an element
  and it can drop that element's essence**, so which elements you fight with decides what you can
  enchant with. Chests appear every third wave of the arena.
- **The forge** (one station) crafts gear from gold and materials (rarity is rolled), upgrades it,
  **enchants** it with an essence for an extra bonus (re-enchanting replaces), and salvages
  unwanted gear into scrap and gold. Nothing fails or breaks.
- **Sealed characters** are never dropped gear or bonuses that only help spellcasting.
- Not yet: a shop, a safe stash, gear sets, item-granted elements (an attunement item is still the
  F10 debug key). Those belong with the run structure and story phases.

## 16. Design updates (Phase 5: the shell, the camp and the world)

- **Structure.** Camp (hub) -> dungeon -> camp. See [CORE_LOOP.md](CORE_LOOP.md). The camp is one safe room
  with the forge, a notice board (the leaderboard) and the gate; it heals and saves.
- **Dungeons.** Dungeon I has 5 floors, Dungeon II has 10 (each opens when the one before is cleared). Every third
  floor ends in a mini boss, the last floor in a boss. Depth carries across dungeons, so the second starts
  where the first ends (monster level 6 to 15). Dungeon I looks like a burned vault, Dungeon II like a flooded crypt.
- **Difficulty is an oath**, chosen once per hero: Squire, Knight (the intended game), Warlord. Harder oaths
  multiply monster health and damage (x0.75 / x1 / x1.25) and also XP, gold, drop luck and the leaderboard score.
- **Punishing but rewarding.** Failing costs one element, 30% of gold and the loot found in the run; retreating
  costs the same gold but keeps the loot and every element; there is no free exit. In return the boss drops two gear pieces and maybe an element gem, a cleared dungeon pays a bonus,
  and a harder oath pays more.
- **Light and Dark** (the rare elements) now have four skills each, eleven combos with the main elements and with
  each other (Twilight), a resonance and monster variants from the second dungeon. They are gained from the
  second dungeon's bosses (Crypt Lich: Dark gem, Tide Titan: Light gem) or, rarely, at the ceremony.
- **Saves.** Three slots, autosave at the camp and every dungeon room, permadeath deletes the slot.
- **Controls.** Keyboard + mouse and a full gamepad layout; rebinding for both; right-stick aim with assist; the camera
  looks a little toward where you aim.
- **Look.** Medieval fantasy: dark stone panels with gold trim, leather and brass buttons, a serif face. The HUD is
  four small corner groups and scales with a setting.

## 17. Phase 6: look, depth and play together

* **Names.** A hero is named at creation (random suggestions); the name shows on the sheet, the board and to other players.
* **Elements are different from one another.** Fire: heavy, bursts on impact. Water: cheap and fast, slows, wide pools. Air: the fastest bolt,
  pierces two, shoves. Mineral: slowest and hardest, stuns. Earth: a fan of three thorns, wide root ring. Light: near-instant piercing lance.
  Dark: slow homing bolt that drains life. The altar in the training grounds shows the numbers side by side.
* **Melee range ring.** A wedge and ring around the hero show the reach and arc of the next slash (it glows on a target, dims without
  stamina, becomes a full circle while dodging). Setting: Melee range ring.
* **Look.** Heroes are drawn in a Stardew/Witchbrook-like chibi style from parts: the class sets outfit, hair, head gear and weapon; the subclass
  adds an accent and may change the head gear and back item; equipped helm, armour, boots and weapon replace them. The class cards show each
  class in the middle of a card with its own border, the name below; the character sheet shows a paper doll with six slots.
* **Five dungeons**, each harder than the last: Ashen Vaults (5 floors), Drowned Crypts (10), Thornroot Hollow (12), Cinder Forge (15), Gloaming
  Spire (20). Each opens when the one before is cleared.
* **Isometric view.** The world is shown in 2D isometric: diamond floor tiles, walls with a lit and a shaded face, upright sprites with
  shadows. Drawn entirely in 2D, so pixels and text stay sharp. A setting switches back to the flat top-down picture.
* **Multiplayer.** From the title screen: host or join (address and port), wait in the lobby, then a co-op dungeon (up to four heroes, each
  keeps its XP and loot; a fallen hero returns after 5 s) or an arena duel (first to three kills).

## 18. Forgiving tuning

The tone moved from punishing to forgiving: monsters hit softer, every lethal attack can be read and avoided,
healing comes between fights and mistakes are cheap. The numbers are measured in [BALANCE.md](BALANCE.md). This
supersedes the healing and recovery figures of sections 12 and 15.

* **Healing between fights.** Clearing a combat room or a guardian heals 15% of max HP; a forge room and a level-up
  heal fully. Out of combat health returns at about 0.5% of max HP a second, 3 s after the last hit. Every class
  gains 5 max HP a level on top of Vitality.
* **Soft hits.** At the level a hero reaches a floor (Knight oath), a normal hit takes about 5-8% of max HP, an
  elemental variant about 7-14%, a guardian's slam about 9-19% and a final boss's slam about 12-21%: no class
  falls to fewer than five boss slams. Monsters carry no hidden damage multiplier, and their damage climbs gently with depth.
* **Readable attacks.** Melee monsters bite at most every 1.2 s; a dash always winds up for at least 0.4 s and never
  lunges faster than 300 px/s; no monster walks faster than the slowest hero; a dodger sidesteps at most 45% of
  hits; a slam stuns for 0.25 s; an enraged boss attacks only a little faster (cooldowns x0.8). A dodge costs 25
  stamina and gives 0.4 s of immunity.
* **Smaller rooms, rarer elites.** A room holds 3-8 monsters on a dungeon's first floor and at most 12 from its
  third. Elemental variants are 4% more likely per depth, at most 30% of a wave.
* **Oaths.** Squire x0.75 monsters (health and damage) and x0.8 spoils; Knight x1 and x1; Warlord x1.25 monsters and
  x1.6 spoils. Spoils are XP, every gold drop, the clear bonus and drop luck.
