# Architecture

How the code is organised and how to extend it. Everything lives in `elementalist/`.

## Principles

- **Data-driven.** Elements, combos, skills, classes, passives and traits are plain tables
  (`const` dictionaries). Adding one is adding data, not writing new logic.
- **Rules are separate from nodes.** `CharacterData` and `Ceremony` are `RefCounted` classes with
  no scene dependencies, so they can be saved, loaded and unit-tested directly.
- **Everything asks for art by id.** `AssetDB.get_texture("player")`. See *Art* in the README.

## Autoloads (`scripts/core/`)

| Autoload | File | Responsibility |
|---|---|---|
| `AssetDB` | `asset_db.gd` | Sprite lookup by id; generates placeholders |
| `Elements` | `elements.gd` | Element colours, the ten combos, `resolve(a, b)` |
| `SkillDB` | `skill_db.gd` | All skill definitions, per-element loadouts, melee, cost helpers |
| `Juice` | `juice.gd` | Camera shake and hit-stop (`Juice.enabled = false` in tests) |
| `Game` | `game.gd` | The current `CharacterData`, new-game and sandbox helpers, kill XP and loot drops, banner, run text, hit indicator; **the flow between scenes**: save slot, `meta`, `run`, `mode` (camp/dungeon), difficulty, `new_game`, `continue_game`, `begin_run`, `return_to_camp`, `save_game` |
| `Controls` | `controls.gd` | Gamepad defaults, rebinding, pad/keyboard device tracking, `aim_point()` (mouse or right stick with aim assist) |
| `Settings` | `settings.gd` | Preferences in `user://settings.cfg` (audio sliders, fullscreen, shake, damage numbers, HUD size, aim assist, deadzone) and the bindings; applies them |
| `Sfx` | `sfx.gd` | Audio: Music/SFX/UI buses, `play`, `play_at`, `music` (crossfade), `duck`; missing files are skipped |

Plain classes (not autoloads): `SaveStore` (slots on disk), `Leaderboard`, `SpriteAnim` (strip animation node).

Autoloads are **not** instantiated by the editor's own test runner, which is why the self-tests
run as a scene (`tests/combo_selftest.tscn`).

## Data flow of a spell

```
input (LMB / Q)
  -> SkillCaster.try_cast(id)           checks Game.character.can_use_skill + cost + cooldown
     -> _spawn(): builds a `hit` dictionary from CharacterData (damage, potency, scaling)
        -> Projectile / AoeEffect       moves/overlaps, then calls Enemy.take_hit(hit)
           -> Enemy.take_hit()          aura check -> combo? -> damage, status effects, juice
              -> Game.on_enemy_killed() on death -> CharacterData.gain_xp()
```

The `hit` dictionary is the contract between skills and enemies:

```
{ damage: float, element: String ("" = physical), apply: {kind, time, power},
  from: Vector2, knockback: float, juice: bool }
```

**Aura and combos.** Every element hit leaves the enemy marked with that element for 4 s
(`Enemy.AURA_TIME`). A hit with a *different* element while marked triggers
`Elements.resolve(aura, element)`, which multiplies damage, applies the combo's effect and
consumes the aura. Physical hits (`element == ""`) never touch the aura, but deal x1.5 to rooted
or stunned enemies ("Shatter").

Two more combo kinds live in `Enemy.take_hit` and `Elements`:
- **Resonance:** the 3rd discrete hit of the *same* element in a row (`Enemy.aura_stacks`,
  `Elements.RESONANCE`) triggers that element's resonance and consumes the aura. Lingering ticks
  (`juice: false`) don't count.
- **Martial Rend:** the 3rd physical hit within 3 s (`Enemy.chain_count`,
  `Elements.MARTIAL_COMBO`). It never touches the aura. Imbued slashes are elemental hits, so
  they build resonance, not Rend.

`take_hit` ignores an enemy that is already dead, so a multi-hit bolt can't reward twice.

**Status effects** (`Enemy.effects`): `dot`, `slow`, `root`, `stun`, `vuln`.

## The character model (`scripts/character/`)

`CharacterData` holds class, attributes, level/XP, owned elements and mastery, weapon mastery,
traits and skill-use counts. `Classes` holds the static tables.

**Progression gates** (all in `Classes`): everyone starts as the **Novice** (`NEUTRAL_CLASS`,
all attributes 5). Level 3 (`CLASS_LEVEL`): `choose_class()` turns the Novice into a real class,
keeping the points the player spent and applying the class's growth retroactively. Level 5
(`AREA_LEVEL`): area skills (F) unlock and element locking (Q) becomes available, for every
class. Level 10 (`SUBCLASS_LEVEL`): subclass.

**Elements vs skills.** Owning an element does not give you its skills.
`CharacterData.can_use_skill(id)` requires (1) owning the skill's element and (2) having learned
it: primary skills at level 1, area at level 5 (`Classes.SKILL_LEVELS`), and **special** (R)
skills only as rewards (`learned_specials`). Characters born without elements get the
**martial** set (`SkillDB.LOADOUTS["martial"]`): stamina-powered, no element.

**Level rewards** (`Rewards`): even levels except 10 queue an offer of 1-3 options in
`pending_rewards`: a *skill* (the special of a set the character has) or a *passive* (a trait not
yet owned). `claim_reward(offer, option)` applies one and discards that offer. The sheet's
Rewards tab is the UI.

**LMB and RMB** (`SkillCaster.lmb_mode` / `rmb_mode`, `Classes.style_of`):
- LMB is the fused cast: `"fusion"` when two or three elements are locked, otherwise `"locked"`
  (disabled, casts nothing). A character with no elements (or on the martial set) gets `"slash"`
  (melee-style class) or `"knife"` (ranged-style class, the martial primary).
- RMB is the basic attack: `"slash"`, or `"bolt"` (the selected element's primary, for mana) when
  the class style is `ranged`, the player is imbued, and an element is selected. The `melee`
  style (Vanguard) always slashes; its imbued slashes carry the element. The Novice is `ranged`.
- Abilities (F area, R special) and fusions are castable whatever the style.

**Imbue (E)** (`Player.try_imbue`): a toggle with no timer and no cooldown. It needs at least
one castable element. While `imbued`, ranged classes' RMB shoots, and every slash carries
`imbue_elements()` (the locked elements, else the selected one): one hit per element in order
(so their combos fire), each costing `IMBUE_SWING_COST` mana; if you can't pay, the swing is
plain. Imbued hits set the aura, apply the element's primary status (`SkillCaster.status_for`)
and train the element, but give up the physical "Shatter" bonus.

**Locking and fusion** (`SkillCaster`): Q toggles the selected element in `locked` (max
`Classes.MAX_LOCKED` = 3; the martial set can't be locked). It needs two or more castable
elements and no level. With 2-3 locked, LMB casts a **fusion**: `primary_id()` returns
`"fusion:fire+water"`, which costs the sum of the parts, waits for the slowest cooldown plus
0.15 s per extra element, and fires one `Projectile` whose `extra_hits` apply each element in
turn at `FUSION_DAMAGE` (75%) x the `fusion_damage_mult` stat (from Harmony).

**No elements, no mana:** `CharacterData.uses_mana()` is true only if the character owns an
element. Otherwise `derived()` gives 0 max mana and 0 regen (sealed characters, or attunable ones
before their first element), and the HUD hides the mana bar. The caster refills mana when the
first element arrives. Sealed characters are also never given spell-only traits
(`Classes.SPELL_TRAITS`) at creation or as rewards.

**Elemental Harmony** (`Classes.HARMONY_PASSIVE`): added automatically by
`passive_sources()` with `stacks = elements - 1` once a character owns two or more elements.
`stat_mods()` applies a source's mods once per stack (`*_add` multiplied by stacks, `*_mult`
raised to the stacks).

**Dodge spin** (`Player.try_spin`): attacking while dodging (RMB, or LMB when it is a slash) is a
360 degree slash costing `SPIN_STAMINA_MULT` (1.8x) stamina, dealing 1.15x damage, once per dodge.
It uses the same imbue logic as a slash. For `SPIN_DURATION` (0.32 s) the player is invulnerable
(`is_spinning()` is part of `is_invulnerable()`), i.e. until the attack finishes.

**Reward cards** (`RewardCards`): when a reward is ready the game pauses and the first pending
offer is shown as centered cards (click, or press 1-3; Esc postpones). It pops up shortly after
the level-up, and for any offers already pending when the scene starts.

**Melee reach:** `derived()["melee_range_mult"]` = the class's `melee_range` x passives, applied
to the slash radius (`Player.melee_reach`).

**Affinity:** `elementalist` (rolled elements), `attunable` (born with none; can gain elements
via `add_element`), `sealed` (can never hold elements). Attunable and sealed characters have the
martial set.

**Derived stats** (`CharacterData.derived()`), at all-5 attributes these equal the values the
combat was tuned against:

| Stat | Formula |
|---|---|
| Max HP | `60 + 8*Vitality` |
| HP regen | `0.3 + 0.06*Vitality` per s |
| Max mana / regen | `50 + 10*Intellect` / `5 + 0.8*Intellect` per s |
| Max stamina / regen | `70 + 6*Agility` / `20 + 2*Agility` per s |
| Move speed | `70 + 2*Agility` |
| Melee damage | `(1 + 0.06*(Strength-5))` x weapon mastery x passives |

Passive modifiers are added on top (see below).

**How attributes affect skills and elements**

- *Spell damage:* `(1 + 0.05*(Intellect-5))` x element mastery (+4% per level) x passives.
- *Element potency:* each element has a governing attribute (`Classes.ELEMENT_ATTRIBUTE`:
  fire/mineral Strength, water/air Agility, earth/light Vitality, dark Intellect). Every point
  above 5 adds 3% to that element's status duration and strength (burn, slow, ...).
- *Per-skill scaling:* a skill's `scales` entry names an attribute for one property (radius,
  knockback, speed or cooldown), at the rate in `Classes.SCALE_RATE`.
- *Martial skills:* damage scales with Strength (the melee multiplier).

**Passives** come from four sources (`CharacterData.passive_sources()`):

| Type | Where from | Rarity |
|---|---|---|
| `class` | Class and chosen subclass | Fixed |
| `trait` | Rolled at creation (`Ceremony.roll_traits`) | Always 1+. Fewer other passive sources (e.g. no elements) means more traits |
| `element` | Element mastery level 5 | Rare |
| `skill` | 120 uses of a primary skill / 30 of an area skill, or weapon mastery 5 | Rare |

Passive `mods` keys ending in `_add` are summed and `_mult` are multiplied. Per-skill keys are
`<skill_id>_damage_mult` and `<skill_id>_cooldown_mult`.

**Ceremony** (`Ceremony.perform`): 8% are born with no element (-> attunable). Otherwise one
main element is guaranteed, then 15% for a second, 20% for each further one, and 2% each for
Light/Dark (never both).

**Leveling:** `xp_to_next(level) = 30 * level^1.4`. A level gives 2 free points and the class's
growth attribute +1. A level-up heals 40% of max HP (`LEVEL_UP_HEAL_FRACTION`).

**Saving:** `to_dict()` / `from_dict()` survive a JSON round trip (JSON turns ints into
floats; `from_dict` converts them back). There is no save file or UI yet (Phase 5).

## The resource model (Phase 4.2)

Constants live in `Classes` (`HP_REGEN_BASE`, `STAMINA_REGEN_BASE`, `MANA_REGEN_BASE`, `KILL_MANA`,
`KILL_STAMINA`): recovery is deliberately slow. `derived()` adds `attack_speed` (Dexterity and level),
`mana_cost_mult`, `dodge_cost_mult` and `kill_hp / kill_mana / kill_stamina`; `Player.restore_on_kill()`
applies the kill restores (called from `Game.on_enemy_killed`). `SkillCaster.mana_multiplier(id)` is the one
place mana costs are scaled: the stat (Elemental Harmony's spread-thin penalty, gear, traits), +30% per
extra element in a fusion (`FUSION_COST_PER_EXTRA`), and the chain discount (`chain_discount`: an F/V/R
ability of a different element within `CHAIN_WINDOW`). `fusion_hit_scale(n)` is 75% for two elements down
to 50%. Imbue holds a single element (`Player.imbue_elements`). Monsters multiply everything by
`Monsters.HARDNESS`.

**Death** (`CharacterData.die()`): with elements, lose one at random (`remove_element` resets that element's
mastery, special and skill uses; none left means attunable); with none, the result is `final` and
`RunEndScreen` starts a new character (`Game.open_creation` opens the creation menu in the next scene).

**Run loot** (`Game.lose_run`, used by a fall in `Dungeon._finish_run` and by the pause menu's retreat): 30% of
the gold and what the run found. `Pickup` marks gear picked up in a run with `"run": <run seed>` (the mark is
saved with the item, `Inventory._clean` keeps it) and counts materials picked up, scrap aside, in
`Game.run["found"]`; `Inventory.lose_run_loot` removes the marked gear, bag or worn, and up to the found
count of each material. Gear owned before the run has no mark (or another run's) and stays. A win keeps it all.

**Class mastery** (`class_mastery`, `add_class_xp`): grows with kills; `Classes.SUBCLASS_MASTERY` opens the
subclass. `ClassCards` shows the class (level 3) and subclass choices as cards; signals `class_available` /
`subclass_available` open them.

**Enemy abilities** (`Monsters.DEFS`): `attack` is melee, ranged or both; `dash` (warning flash then a lunge,
`Enemy._tick_dash`) and `dodge` (`Enemy._try_dodge`, discrete hits only) sharpen with the floor (`level`).

## Attributes and classes

Seven attributes (`Classes.ATTRIBUTES`): Strength, Agility, Intellect, Vitality, Wisdom, Luck and Dexterity (attack speed).
**Wisdom** (per point above 5: +0.6 mana regen, -1% spell cooldowns, +4% buff and debuff duration)
and **Luck** (+1.5% crit chance, +5% loot luck). At 5 each they change nothing, so the tuned
baseline is intact. `wisdom_add` / `luck_add` passive mods add to the attribute (the Scholar trait,
the Trickster subclass). Crits: `derived()["crit_chance"]` / `["crit_mult"]` (base x1.5); `Enemy.take_hit`
rolls them with `Game.combat_rng`, only for discrete hits, and only when the chance is above zero.

**Eight classes**, two subclasses each (sixteen in all): Channeler, Vanguard, Ranger, Mystic and the
newer Assassin (melee, dagger, crits), Berserker (melee, axe, fury), Sage (ranged, tome, wisdom) and
Druid (ranged, staff, regeneration). Every class has the same 36 attribute points and +1 per level in
one attribute (a self-test checks it). New weapon types: dagger, axe, tome (starter weapons, craftable
upgrades and a weapon-mastery passive each).

## Support skills, VFX and damage indicators

**Support skills (V, level 7).** Every set has a fourth skill slot, `support`, learned at
`Classes.SUPPORT_LEVEL`: four **buffs** (kind `"buff"`: Might +25% damage, Mending heals per second,
Stone Skin -30% damage taken, Tailwind +30% speed) and two **debuffs** (`"aoe"` skills whose `apply` is
`vuln` or the new `weaken`, which cuts the enemy's damage; `Enemy.damage_out`). A buff is a timed entry in
`Player.buffs` (`add_buff`, `buff_power`, `damage_mult`), its length scaled by `buff_duration_mult`.
`SkillDB.effect_text` describes them for menus.

**VFX (`SkillFx`).** Everything is built from code: per-element particle profiles (fire flickers up,
water drips, earth throws chunks, air streaks, mineral spins shards, martial strikes sparks), an
additive glow sprite, expanding rings and auras. Used for the cast flash (`cast_burst`), a bolt's glow and
trail (`trail`), impacts, area bursts (lingering areas keep emitting), buff and imbue auras, and enemy
status puffs.

**Damage indicators.** Enemies show damage in their element's colour (crits larger with "!", "Resist!" and
"Weak!" for variants); the player shows `-N` in red, "Dodge!" when a hit is avoided and `+N` while mending.
`Game.player_hurt()` drives the HUD's red edge flash and an arrow toward the attacker (`Game.hurt_time`).

## Monsters (`scripts/combat/`)

`Monsters.DEFS` holds every monster; all of them are the one `slime.tscn` scene configured through
`Enemy.configure(id, variant, hp_scale, damage_scale)`. Behaviours: `chase`, `flutter` (weaves), `ranged`
(keeps distance and fires an `EnemyProjectile`) and `boss`. Regular monsters: slime, cave bat, skeleton
archer, wisp, stone brute. **Elemental variants** (`Monsters.VARIANT_CHANCE_PER_FLOOR` per floor) are
tougher, tinted, take `RESIST_MULT` from their own element and `WEAK_MULT` from the one in `WEAK_TO`, and
usually drop their element's essence.

**Bosses** (Slime King, Stone Colossus) chase, telegraph a ground circle (`Telegraph`) and slam it, and
summon minions at the health fractions in `summon.stages`. They never roll variants. A boss drops gold,
scrap, two items (the first at least rare) and, about half the time, an **elemental gem** for an element
you don't have (`Loot.boss_drops`). A gem is a material (`gem_<element>`); `CharacterData.use_gem` spends one
to attune (the Gear tab lists them). Sealed characters never get gems.

## The dungeon (`scripts/world/`)

`DungeonGen` (pure data) makes the layout: 3 floors of 3 rooms. Floors 1-2: two combat rooms and one
treasure-or-forge room (never first); floor 3: combat, a special room, then the boss. A room is a dictionary
(size, entry and exit walls, door positions, pillars, waves; see the header of `dungeon_gen.gd`). `Dungeon`
(the main scene's world node) builds one room at a time: walls, pillars, a locked `Door`, and the room's
contents. Combat rooms spawn their waves one after another; when the last monster dies the door unlocks;
walking into it fades to the next room (loot lying on the floor is picked up on the way out). Special rooms
open at once (a forge room also heals you). Beating the boss, or dying, shows a `RunEndScreen` (Enter starts a
new dungeon with the same character). Monsters get `Monsters.floor_scale` more health and damage per floor,
and `Game.danger` (floor and room) raises item level and loot luck. Debug keys: `[` clear the room, `]`
jump to the boss (the F-keys clash with the Godot editor's own debugger shortcuts; F8 even stops the game).
All debug keys (also F5 sandbox, F6 forge, F10 attune) work only when `OS.is_debug_build()`; the sandbox sets `Game.slot = -1` so it is never saved. `Game.run_text` is the HUD's "Floor 1/3 Room 2/3 ..." line.

## Items, loot and crafting (`scripts/items/`)

All `RefCounted` rules over plain data, so they are saved and tested without any scene.

| File | Responsibility |
|---|---|
| `Items` | The tables (rarities, gear bases, affixes, enchants, materials) and item maths |
| `Inventory` | Gold, materials, the 24-slot bag and the six equipped slots; `mods()` for the stat system |
| `Forge` | Craft, upgrade, enchant, salvage (each has a `*_problem()` that says why it can't be done) |
| `Loot` | Rarity weights, drop tables for enemies and chests |

**An item** is a JSON-safe dictionary: `{base, rarity, ilvl, plus, affixes: [{mod, value}], enchant}`.
Rarity decides the number of random affixes (0 to 4) and scales the base stats. Stats use the
**same mod names as passives** (`max_hp_add`, `melee_damage_mult`, ...), so gear feeds the one
aggregator, `CharacterData.stat_mods()`. In an item a `*_mult` value is the bonus fraction (0.10 =
+10%); `Inventory.mods()` turns the worn gear into passive format (`1 + sum`, floored at 0.4) and
`stat_mods()` multiplies/adds it in. Stat size = base x level scale (`LEVEL_STEP` 8% per item
level) x rarity scale x upgrade scale (`UPGRADE_STEP` 10% per +).

**Weapon type follows the wielded weapon.** `CharacterData._refresh_weapon()` sets `weapon_type`
from the equipped weapon (the class's own type if none is held), and each type trains its own
mastery. A new character wears a worn starter weapon of their class's type; choosing a class at
level 3 swaps a *starter* weapon for the new class's, but keeps anything better you found.

**Loot** (`Loot`): kills drop gold (70%), slime gel (35%), scrap (25%), **essence of the element that
last hit the enemy** (25%, `Enemy.last_element`) and gear (8%). Chests (in the dungeon's treasure rooms)
always hold gold, scrap and two items, the first at least uncommon. `Game.on_enemy_killed` rolls the
drops and emits `Game.loot_dropped(drops, position)`; the arena turns each entry into a `Pickup`.
Depth (`Game.danger`) raises item level, and depth and Luck give a bonus that shifts rarity weights.
Sealed characters are never dropped spell-only gear or spell affixes (`Items.SPELL_MODS`).

**Forge** (`ForgeScreen`, opened at the `ForgeStation` with G): *Craft* (gold + materials, rarity
rolled up to rare), *Upgrade* (+1 to +10, always succeeds, cost grows with level and rarity),
*Enchant* (one essence of a main element + gold; replaces an earlier enchant) and *Salvage* (bag
items to scrap + gold). Upgrading or enchanting edits the item dictionary in place and emits
`Inventory.changed`, which `CharacterData` forwards as `changed`, so the player's stats refresh.

**World objects** (`scripts/world/`): `Interactable` (G within `radius`, shows a prompt) is the base
of `Chest` and `ForgeStation`; `Pickup` drifts to the player and is collected on touch (gear waits
while the bag is full; everything vanishes after 120 s, or is vacuumed up when you leave a room).

**UI:** the sheet's *Gear* tab (`I` opens it) lists worn gear (click to take off) and the bag
(click to wear; hover for details). `Inventory.summary()` is the one-line wallet text.

## Combat scripts (`scripts/combat/`, `scripts/player/`)

- `Player` - movement, dodge (stamina, i-frames), melee, HP. Reads its stats from
  `Game.character` via `apply_stats()`, and re-applies them whenever the character changes.
- `SkillCaster` - mana, cooldowns, set selection (1-5 / wheel), and spawning skills.
- `Enemy` - HP, aura, status effects, chase AI, contact damage via `touches()` (rectangle
  overlap with the player's `hurtbox()`), health bar.
- `Projectile`, `AoeEffect` - the two skill shapes. `HitFx`, `FloatText`, `SlashEffect` -
  feedback.

## How to add things

**A new element.** Add a colour in `Elements.COLORS` (and to `Elements.MAIN` if it should roll),
a `Classes.ELEMENT_ATTRIBUTE` and `ELEMENT_PASSIVES` entry, two skills in `SkillDB.DEFS` and a
`SkillDB.LOADOUTS` entry, and combos in `Elements.COMBOS`. The HUD, sheet, caster and ceremony
pick it up automatically.

**A new skill.** Add an entry to `SkillDB.DEFS` (see the header comment of `skill_db.gd` for the
fields) and put it in a loadout slot (`primary`, `area` or `special`). Tune scaling with `scales`.
A new set needs all three slots.

**A new class.** Add it to `Classes.CLASSES` (base attributes totalling 21, one growth
attribute, `melee_range`, `weapon`, `passives`, `subclasses`), its subclasses to `SUBCLASSES`,
their passives to `PASSIVES`, and a `WEAPON_PASSIVES` entry for its weapon. The balance tests
(`_test_classes`) will tell you if the budget is off. A class needs no skill-unlock levels: those
are the same for everyone (see Progression gates).

**A new passive or trait.** Add it to `Classes.PASSIVES` with `mods`; for a trait also add it to
`Classes.TRAITS`. Supported stats are the keys read in `CharacterData.derived()` and the
caster (`spell_damage_mult`, `spell_cooldown_mult`, `projectile_speed_mult`, `burn_time_mult`,
...). A new stat needs a line there to take effect.

**A new combo effect kind.** Handle the kind in `Enemy` (movement, tick or damage), and add it to
the list in `Elements.describe_combo` and the self-test.

**A new piece of gear.** Add an entry to `Items.BASES` (slot, `mods` at item level 1, optional
`weapon` type, `min_ilvl`, `craft` cost). It drops and is craftable automatically. A new weapon
type also needs a `Classes.WEAPON_PASSIVES` entry and a worn starter base.

**A new affix, material or enchant.** Add it to `Items.AFFIXES` / `MATERIALS` / `ENCHANTS`; an
affix's `mod` must be a stat `derived()` or the caster reads. A new element's essence is
`"essence_" + element` and needs an `ENCHANTS` entry to be droppable.

**A new monster.** Add it to `Monsters.DEFS` (sprite id, stats, `behavior`; ranged ones need `shot`,
`attack_range` and `keep_distance`), a placeholder sprite in `AssetDB.PLACEHOLDERS`, and a weight in
`Monsters.WEIGHTS` so waves can roll it. A new behaviour is a case in `Enemy._desired_velocity` / `_attack`.

**A new support skill.** A buff: `kind: "buff"` with `buff {kind, time, power}` (a new buff kind also
needs a case in `Player`). A debuff: an `aoe` whose `apply` kind the enemy understands (`vuln`, `weaken`).
Put it in a loadout's `support` slot.

**A new class.** Also give it the two newer attributes (31 points in all) and a starter weapon.

## Saves, flow and the shell (Phase 5)

- **`SaveStore`** writes `user://saves/slot_N.json` atomically (temp file, previous file kept as `.bak`,
  rename) and loads defensively (file, then backup; parse errors give `{}`; `migrate()` brings old
  versions up and refuses newer ones). A slot is `{version, saved_at, character, meta, run}`: plain data
  only, never objects. `run` is the dungeon in progress (`tier, seed, floor, room, kills, time, hp`); the layout
  is rebuilt from the seed with `DungeonGen.generate(rng, floors, tier, depth_offset)`.
  `SaveStore.write_atomic` (also used by `Leaderboard.record`) never replaces the old file when a write fails;
  `Leaderboard.entries()` reads the file, then its `.bak`, the same way.
- **When it saves:** entering a room (autosave), begin_run / return_to_camp / training, the pause menu, and
  closing the window (`Game._notification`, `NOTIFICATION_WM_CLOSE_REQUEST`). Permadeath deletes the slot and
  sets `Game.slot = -1`. A hero picked for multiplayer (`use_hero`) has `keep_saved_run`: saves write back the
  slot's own `run`, so co-op or the arena never erases a dungeon in progress (a solo `begin_run` clears it).
- **Game flow:** title (`MainMenu`) -> `Game.new_game` / `continue_game` -> `scenes/main.tscn`, where
  `Dungeon._make_layout` builds the **camp** (`DungeonGen.camp_room`) or the saved dungeon from `Game.mode`.
  The gate (`CampGate` -> `DungeonSelect`) calls `Game.begin_run(tier)`; a finished run calls
  `Dungeon._finish_run` (meta, leaderboard, gold, run loot) and `RunEndScreen` returns to camp or the menu.
  Tests build a `Dungeon` with `with_ui = false` and a preset `layout`, which skips all of this.
- **Difficulty** (`Game.DIFFICULTIES`) scales monsters (`hardness_mult`) and rewards (`reward_mult`: XP, gold, drop luck).
- **Controls:** every aim in the game goes through `Controls.aim_point(node, origin)`. Pad defaults are added
  to the InputMap at start-up; `Settings` persists user rebinds in `[bindings]`.
- **UI kit:** `UiTheme` (9-slice frames from `assets/ui`, serif `SystemFont`) and `UiKit` (centred panels,
  buttons with click/tick sounds, `focus_first`, `wrap_focus`) are the only places screens get their look.
  Every menu opens with a button focused so a gamepad works. `HUD` draws in four scaled corner groups.
- **Art pipeline:** `tools/art/*.py` write `assets/sprites/<id>.png` (idle frame) and `<id>_strip.png` (frames side
  by side). `AssetDB.get_frames(id)` slices a strip; `SpriteAnim` plays it. Heroes are composed at run time (below); tiles are
  `tile_<floor|wall>_<theme>_<n>` for the themes camp / vault / crypt / hollow / ember / spire. The style is Moonlit Glyphwork
  (docs/ART_DIRECTION.md): `style.py` owns the ramps, `restyle.py` snaps older sprites onto them, `check_art.py` is the gate, `build_all.py` runs
  everything. Element runes live in `assets/ui/rune_<element>_<s|m|l>.png` (`UiTheme.rune`), area-skill rune circles are `fx_rune_<element>`.
- **Audio pipeline:** `tools/audio/gen_audio.py` writes `assets/audio/sfx/<name>[_2..5].wav` (variations are picked
  at random) and `music/<track>.wav` (looped). New sounds and tracks are appended after the old ones (each has its own seed), so a
  re-run leaves every existing file byte-identical. `Sfx.music()` is called by `Dungeon._play_music`: one track per theme (camp, vault,
  crypt, hollow, ember, spire), `boss` in a guardian's room until it is cleared, `menu` on the title screen; tracks stay under 800 KB.
  Who plays what (sounds go through the SFX or UI bus, never a per-clip setting):

  | Event | Sound | Where |
  |---|---|---|
  | Button press / hover or focus | `ui_click` / `ui_tick` | `UiKit.button` (the sheet's, the forge's `_button` and the run end's button use it; Enter on the run end clicks too) |
  | Back, Close, Cancel, Resume, Leave; Esc / pad B closing a screen | `ui_back` | `UiKit.BACK_LABELS`; each screen's cancel handler |
  | Element key 1-7 | `ui_tick` (-8 dB) | `SkillCaster._process` |
  | Denied action: forge fails, equip refused, cast on cooldown or unaffordable | `error` (UI, at most one per 0.3 s) | `ForgeScreen`, `CharacterSheet._equip`, `SkillCaster._refused`; limit in `Sfx.play`. An unearned special is silent (pad B is R and every menu's back), and F, V and R ignore a press on the first frame after a pause (it closed a menu) |
  | Equip / unequip | `equip` | `CharacterSheet._equip`, `_unequip` |
  | Deliberate save: back to camp, new hero, save and quit | `save` (-6 dB) | `Game.return_to_camp`, `NewCharacterMenu._begin`, `PauseMenu._save_and_leave` (room autosaves are silent) |
  | Camp gate, next floor | `portal` | `Game.begin_run`, `Dungeon._advance` |
  | Rest (camp, forge room, when hurt), altar Refill, a mend buff | `heal` | `Dungeon._heal_player`, `AltarScreen._refill`, `SkillCaster._spawn` |
  | Run won / lost | `run_win` / `run_lose` (music fades out, ducked) | `RunEndScreen.show_result` |
  | Walking into a barred door / door opens | `door_locked` (once per bump) / `door_open` | `Door` |
  | Hit contact / monster grunt | `hit` / `enemy_hurt` (-9 dB, non-lethal, no combo, at most every 0.45 s per monster) | `Enemy.take_hit` |
  | Area skill lands; a bolt bursts on impact (splash); a boss dies | `explode` (their own hits skip `hit`) | `AoeEffect._ready`; `Projectile._burst`; `Enemy._damage` (`enemy_die` for the rest) |
  | Casts, buffs, melee, dodge, hurt, death | `cast_<element>` / `cast_martial`, `buff`, `slash` / `spin`, `dodge`, `player_hurt`, `player_die` | `SkillCaster`, `Player` |
  | A co-op partner casts (not a fusion, silent for its caster too) / is hurt by the host's monsters | `cast_<element>` / `cast_martial`, `player_hurt` (-4 dB, by distance) | `RemoteAvatar.apply_state` (once per new cast count in the state, however many casts it covers, and at most twice the sync rate), `RemoteAvatar.take_damage` (on the host, spaced by `HURT_COOLDOWN`) |
  | Combo, telegraph, slam, enrage, boss roar, level-up, reward, pickups, chest, forge | same-named files | `Enemy`, `Dungeon`, `Pickup`, `Chest`, `ForgeScreen` |

  `_test_audio_coverage` scans the scripts for these names: a call to a missing file, a file nobody plays, or a theme without a track fails it.

## Testing

`tests/combo_selftest.gd` (run `tests/combo_selftest.tscn`) covers the combat rules, the
character model, the ceremony statistics, gating, scaling, balance budgets, saving, and builds
every UI screen, settings, bindings, saves, the leaderboard, the camp and the tiered dungeons. A test that fails
prints `FAIL <name>`. Run it headless for CI with
`godot --headless --path elementalist res://tests/combo_selftest.tscn` (exit code 1 on any failure). Tests seed their own RNGs; the player is
tested with a neutral character (`_neutral_character()`, which also takes the starter weapon off;
`_bare(character)` does the same for other characters) so the tuned numbers stay meaningful. UI
buttons call `show_tab.call_deferred(...)`, so tests `await` a frame after clicking one.

## UI notes

- Screens share `UiTheme`. Every menu opens with a control focused so a gamepad can act at once (the shell menus via
  `UiKit.button` / `UiKit.focus_first`; the sheet and the forge focus their open tab and keep the pad's place across
  rebuilds with `UiKit.focused_index` / `restore_focus`; the run-end button takes focus after 0.6 s, since A and Space
  also dodge). Esc and pad B (`pause` / `ui_cancel`) close a screen or go back one level; the run-end screen and the
  first hero's creation are modal on purpose. Key hints use the names `Controls.label_of` gives (LMB, RMB, TAB, Esc);
  the HUD's slot keys and tips and the sheet's keys read the current binding through `Controls.key_of(action)` (the HUD every frame, the
  sheet on every rebuild), so a rebind shows at once. With a full bag the forge's Craft tab says so above its greyed-out buttons.
- **The fit sweep** (`_test_ui_fit_sweep`): every screen, tab and state, opened with a stuffed hero (16-letter name,
  level 30, 3-digit numbers, full bag), must fit both 320x180 and the 420x180 a 21:9 window gives (`_ui_view`), staying
  centred there: `_ui_fit_problems` flags Controls outside the view or their parent, cut labels, overlapping controls
  and off-centre screens. For a new screen, open each state in `_ui_sweep_screens` and `await _ui_sweep("<name>", node)`.
  The drawn HUD is checked through `hud.gd`'s pure `layout()`, which anchors the groups to the view's corners and caps a
  big HUD size per area (bottom pair side by side, top-left block beside a 100 px boss bar); 1.0 at 320 is never capped. `-- --ui-shots` (windowed, 1280x720) runs only the sweep
  and refreshes `docs/art/ui_*.png`; `-- --ui-sweep` runs only its checks headless.
- `CharacterSheet` keeps every tab inside the 320x180 view: the body sits in a fixed-size
  `ScrollContainer`, and a tab's columns plus gaps must fit `CONTENT_WIDTH` (a self-test checks
  this and that the panel stays on screen even when stuffed with content).
- Stats tab: the derived stats (HP/mana/stamina, move, crit, recovery, on-kill) sit in the right column under Traits
  (or under the class-choice button), split into short lines that never wrap. Each attribute row shows a native
  tooltip from `Classes.attribute_text(attr)`, built from the same constants as `CharacterData.derived()`;
  `UiTheme` styles `TooltipPanel` / `TooltipLabel` so tooltips fit the 320x180 view (they work while paused).
- The sheet toggles on TAB in `_input` (not `_unhandled_input`), because Godot would otherwise
  use TAB to move GUI focus while a button is focused.

## Gotchas

- **New `class_name` scripts need a scan** before other scripts see them: in the editor, let it
  re-scan the filesystem (focus the window) or reopen the project.
- **Don't edit a script outside the editor while a scene that uses it is being saved.** The
  editor can write a stale in-memory copy back over the file. Re-check the file after saving
  scenes if you edit scripts programmatically.
- Godot's `ClassDB` is a built-in, which is why the class table is called `Classes`.

## Phase 6: look, depth and multiplayer

**Heroes are parts, not pictures.** `tools/art/gen_heroes.py` writes interchangeable parts (body, boots, outfit, hair, head gear, back item,
accent, weapon) per facing as strips of four frames in `assets/sprites/hero/`. A pixel stores a *region* (skin, hair, outfit, trim ...) and a
*shade*, not a colour. `HeroLook` (data in `data/hero_looks.json`, shared with `tools/art/preview_heroes.py`) works out which parts and palette
a hero wears from class, subclass and equipped items; `HeroComposer` stacks the parts (34 x 32 frames), paints them through a ramp (pale
highlights, cold shadows), adds a moonlit rim on the upper-left edge and traces a selective outline (a deep violet shade of the colour it borders). Gear has painted icons (`item_<base>.png`, `HeroLook.slot_icon`). Results are cached by look and registered in `AssetDB` as `hero:<n>:<facing>` so `SpriteAnim` plays them.
`HeroDoll`, `CardFrame` (class borders) and the equipment paper doll in the character sheet reuse the same pictures.

**The isometric view (`IsoView`).** Gameplay stays flat and so does the picture: `IsoView` (a child of the Dungeon) is a 2D renderer, no
3D nodes. A world point p is shown at `project(p) = (x - y, (x + y) / 2)`, so a 16 px tile is a 32 x 16 diamond. The flat world is shared with a
SubViewport that renders the floor and every flat effect (telegraphs, rings, the melee ring, the aim marker) into one texture, laid on the screen as
a skewed `Sprite2D`. Walls and pillars are `IsoView.Block` nodes that draw a top face and two shaded side faces from the tile's art
(`Dungeon._add_tile` calls `add_wall`). Creatures, pickups, props and projectiles are mirrored by ordinary `Sprite2D`s that stand on their position,
with an indigo blob shadow; text is a `Label`, health bars a small `Bar` node. Walls and mirrors live in one y-sorted node, so whatever is nearer
the bottom of the screen draws in front. All of it sits in a `CanvasLayer` below the HUD that is scrolled to follow the hero (the player's own
`Camera2D` is not used for the picture). Canvas items are sorted by `visibility_layer`: layer 2 = ground (drawn into the floor texture), layer 4 =
mirrored (hidden from both viewports); the main window's `canvas_cull_mask` hides both. Because nothing is 3D, text goes through the normal 2D
font path and stays sharp. `Controls.aim_point` inverts the projection (`IsoView.unproject`); movement and facing use `IsoView.world_dir` /
`screen_dir`. The setting `iso_view` (off: the flat top-down picture) applies from the next scene.

**Multiplayer (`Net`, `CoopHost`, `CoopClient`).** ENet, up to four players, host-authoritative for the world. Every player (host too) plays
their own `Player` locally. The host's monsters are mirrored on guests as *ghost* `Enemy` nodes (`ghost = true`: no AI, `take_hit` forwards
the hit to the host with `Net.send_hit`); the host sends snapshots 15 times a second (monsters, players, door, run text) and reliable
messages for rooms, loot, kills and damage; guests send their position, aim and health. Other players appear as `RemoteAvatar`s (group
`net_players`, which monsters target like the local hero). In the **arena** the other players are ghost Enemies wearing their hero's picture
(`PvpGhost`), so every attack already aimed at monsters works on them; a hit on one is sent to that player (`Net.send_pvp_hit`), who takes 70%
as damage. A guest's `Dungeon` runs in `viewer` mode: it builds the host's rooms and spawns nothing. `tests/net_selftest.tscn` plus
`tools/run_net_test.ps1` run a real host and guest over loopback; `combo_selftest.gd` covers snapshots, ghosts, avatars and the arena offline.

**Trust model.** The host is trusted; clients are not, since any `any_peer` RPC can come from a stranger. On the host, every client message
(`_pos`, `_hit`, `_down`, `_pvp_hit`, `_pvp_down`) is ignored unless the sender passed the hello (`Net.roster`), a second hello is ignored, and
a peer that says nothing for 5 s is disconnected so it cannot hold a slot. The hello itself is cleaned (`Net._clean_info`: a known class, a
look shaped exactly like `HeroLook.for_character`, else the default). A guest's monster hit is rebuilt from known keys with capped numbers and
a whitelisted status (`CoopHost.clean_hit` / `clean_apply`) and rate-limited per peer (`take_token`, 60 a second, burst 100); PvP hits pass
only in an arena session, to a peer in the roster, as damage and origin alone (`Net.clean_pvp_hit`). The other way, a guest caps what the host
gives it before it reaches the save (`Net.clean_kill`, `Net.clean_clear_reward`) and skips malformed snapshot entries (`Net.all_numbers`).
Numbers must be finite: `Net.all_numbers` refuses NaN and INF, so a guest's position update with one is dropped whole (and a partner's health
is clamped to its maximum, as an arena rival's is). An arena kill scores only for a killer in the roster who is not the victim, a PvP hit
whose attacker is its target is ignored, and a guest makes no ghost for a monster id `Monsters.DEFS` does not know.

**Five dungeons.** `Game.TIERS` holds five dungeons (floors 5, 10, 12, 15, 20; depth offsets 0, 5, 15, 27, 42) with themes (`vault`, `crypt`,
`hollow`, `ember`, `spire`) for tiles and music. `Monsters.band_of(depth)` picks one of nine weight bands; `floor_scale` climbs steeply to depth
10 and gently after. New monsters: Thornling, Dire Wolf, Magma Slug, Gloom Shade; new final bosses: Thorn Matriarch, Cinder Tyrant, Gloaming
Sovereign.

**Training grounds.** `Game.begin_training()` swaps in a sandbox copy of the hero (every element, nothing saved); the grounds hold three
dummies, the `AltarScreen` (compares every element's mana, speed, area and damage) and a `TutorialGuide` checklist that ticks off controls as
they are used.

## Sprites after Noir Silhouette (docs/SPRITE_STYLES.md)

* **Poses.** A hero part strip holds 21 poses in a 34 x 32 cell (`gen_heroes.POSES`, `HeroComposer.FRAME_COUNT`, `HeroComposer.CLIPS`). The figure is the
  middle 20 columns (`HeroComposer.portrait_size()`); portraits and the doll cards show only that. The rig is drawn on a 40 x 38 grid and reduced to
  34 x 32 when the strips are written (`gen_heroes.RC.shrunk`, `tools/art/shrink.py`).
* **Colour.** `HeroComposer._color_of` is the Noir colouring (twin of `tools/art/noir.py`); the look's `palette["glow"]` is the accent. `Player._refresh_look`
  sets it from the selected or imbued element (`_glow_hex`, checked every physics frame), so a new element is a new composed look (cached per glow).
* **Lazy frames.** `HeroComposer.register(look)` registers each facing with `AssetDB.register_lazy`; the 21 poses are composed the first time a facing is
  used (`compose_facing`), not up front.
* **Clips.** `SpriteAnim.set_clip(start, count, fps, looping)` plays a run of a strip; `Player._update_sprite` picks the clip from the state (swirl, dodge,
  hurt, cast, attack, walk, idle); remote avatars and arena ghosts play walk, idle, dodge and stun.
* **Enemies.** Humanoid enemies come from `gen_enemies.py` on the same rig with a per-enemy glow; the other monsters pass through `restyle.noirize`.
  `Enemy._sync_stun_fx` shows the stun stars; hit boxes are unchanged (`Enemy.BODY_SIZES`).

## Combat feel (after Phase 6)

* **Melee reach** is `SkillDB.MELEE["range"]` = 28.6 (it was 26: +10% for everyone, before class and passive multipliers).
* **Ranged rate:** the basic shots (the seven element primaries and Knife Throw) wait 2.3 times as long between casts as they did (Fireball 0.87 s,
  Water Jet 0.32 s, Gust 0.41 s, Shard Shot 1.38 s, Thorn Shot 0.8 s, Light Lance 0.58 s, Shadow Bolt 0.74 s, Knife Throw 0.55 s). Slash is unchanged (0.26 s).
* **Wind-ups:** areas (F) and specials (R) charge first (`SkillDB.WINDUPS`, 0.25 to 0.9 s). The cost and cooldown are paid when the key is pressed, the hero
  moves at half speed while charging (`SkillCaster.WINDUP_SLOW`), a charge ring fills round the hero and an area shows its circle under the aim point
  (`SkillFx.charge`), and a dodge interrupts the charge (`SkillCaster.cancel_windup`). `SkillCaster.windups_enabled` switches them off for tests.
* **Dodge:** i-frames last 0.3 s from the start of a roll (`dodge_iframes`; the roll is 0.18 s, so they outlast it), a swirl attack is immune for 0.5 s
  (`Player.SPIN_DURATION`), and a roll passes through ordinary enemies: for its length the hero and each non-boss, non-mini-boss enemy carry collision
  exceptions, lifted once the two no longer overlap. Terrain, bosses and mini bosses still block.
* **Sprite size:** the hero and every enemy are 15% smaller than they were, baked into the pictures (`tools/art/shrink.py`); nothing is scaled at runtime
  (`Player.SPRITE_SCALE` is gone) and the sprites' offset is (0, -8). Hit boxes did not change (`Player.HURTBOX_SIZE`, `Enemy.BODY_SIZES`, which now also
  lists the other monsters' old picture sizes).
* **Enemy attack poses:** `Enemy._update_pose` shifts the sprite by whole pixels (`sprite.offset = _rest_offset + pose`; never scale or rotation) and
  holds one walk frame: a dash wind-up crouches back 2 px (tall pictures 2 down, others 1) and trembles in its last third, the dash leans in 2 px, a shot
  recoils 2 px for 0.12 s, a bite lunges 2 px for 0.1 s, a slam rises 3 px (2 for small pictures) over its telegraph and drops 1 px for 0.15 s; every pose
  eases back over `POSE_RECOVER` (0.15 s); a stun drops it at once. On the host the pose comes from the monster's own state (`Enemy.pose_code()`); each
  monster in `CoopHost.snapshot()["e"]` ends with that code (`Enemy.POSES`: "", windup, tremble, dash, shot, bite, rise, land: append, never reorder; `Net.PROTOCOL`
  3) and a co-op ghost starts the same pose from it (`apply_pose_code`), arena rivals never pose. The isometric mirror adds `Enemy.pose.y` to the standing picture
  (`IsoView._update_sprite`), the sideways part is already in `offset.x`. `CROUCH_FRAME` (the lowest walk frame of each strip) is hand-measured: re-measure
  it when enemy art is redrawn.
* **Stun:** a boss or mini-boss slam that lands stuns the hero (`Enemy.SLAM_STUN` 0.5 s, `Player.stun`): no moving, slashing, dodging, casting or imbuing, the stun
  clip and three stars; `Player.STUN_IMMUNITY` (1.5 s) follows, so no stun-lock. Dodge and spin i-frames refuse it. For a partner on another machine the stun
  rides with the damage (`Net.send_damage(peer, amount, from, stun_time)`; `Net.PROTOCOL` is 2).
* **Net flags:** `Player.net_state()` is `[x, y, aim_x, aim_y, hp, max_hp, flags, casts, cast element code]` (`Player.cast_count` counts the casts
  that sounded, `cast_code` is the last one's glow code; `Net.PROTOCOL` 4); `Player.pack_flags`/`unpack_flags`: 1 moving, 2 dodging, 4 stunned, glow code from
  bit 3 (0 none, 1..7 = fire water air mineral earth light dark: append new elements, never reorder). `RemoteAvatar` and the arena ghosts re-register their look
  with `HeroLook.with_glow` when the code changes; a stunned partner or rival gets the stars (`SkillFx.stun_stars`, which also lines them up in the flat view).

## Lighting (`scripts/world/lighting.gd`)

* **Where.** `Lighting` is a child of `IsoView`, built in `IsoView._build_stage` unless the setting `lighting` is "off"; the flat top-down view
  (`iso_view` off) has no IsoView and so no lighting at all. `Dungeon._load_room` passes the place (`_theme()`) through
  `IsoView.begin_room(room, tile, theme)`; `IsoView._on_node_added` hands every world node to `Lighting.track`.
* **What is lit.** Only canvas items with the light-mask bit `Lighting.LIT` take light: the floor tiles (`Dungeon._add_tile`), the wall blocks
  (`IsoView.add_wall`) and the prop mirrors (`Interactable`s, `IsoView._make_mirror`). Creatures, bolts, loot, telegraphs, rings, spell effects,
  labels, health bars and the HUD keep the default mask and their full colour, so the ink silhouettes' element glow pops on the darker world.
* **Layering, and why.** The floor and every flat effect share one ground picture (the SubViewport), so dimming the stage layer as a whole
  (`CanvasModulate`, or a multiply overlay) would dull the telegraphs and could not spare the labels and bars that live on the stage. Instead the
  floor is lit *inside the flat world*: the floor tiles carry a small shader (`Lighting.FLOOR_SHADER`) that multiplies them by the ambient, and 24
  `PointLight2D`s in the world canvas add the pools (a ground circle of radius r / sqrt 2 becomes the r-wide ellipse after the skew); the shader also
  adds a touch of the light's own colour (`tint` 0.15), because the floors are near black and a plain light only multiplies them. Under a
  pool the shader also pulls the floor's own hue toward grey (`neutral` 0.9, scaled by how saturated the light is), so a warm pool on a cold
  floor (crypt teal, spire violet, hollow green) reads as warm light and not as a grey-pink mix; a white light leaves the floor's hue alone. On the stage,
  one subtracting `PointLight2D` (an all-white 8 x 8 texture spanning 8192 px) takes 1 - ambient off the walls and props, and 24 more lights sit at
  `project(p) - 8 px`. Lessons from testing: a `DirectionalLight2D` ignores the item cull mask (it dimmed the telegraphs), and a light only reaches
  canvas layers inside its `range_layer_min..max` (the stage lights use `_layer.layer`, -2). Two radial `GradientTexture2D`s (128 px) serve
  the pools: the soft one for all, a steep one (bright core, fast falloff) for bosses, swapped on a pair only when its kind changes; no PNG.
* **Budget.** `MAX_LIGHTS` = 24 light pairs, built once and reused. Each frame the tracked nodes on screen become candidates in fixed packed
  arrays; `Lighting.light_key(kind, distance to the hero, index)` ranks them and the pure `Lighting.choose(keys, cap)` keeps, in order: the hero,
  partners (co-op avatars, arena rivals), bosses (mini bosses too), the exit `Door`, the 6 nearest bolts (`MAX_BOLTS`), monsters by distance,
  props (gate, forge, altar), loot of rare or better. Colours: the hero's glow (`Player._glow`), a partner's glow code, a monster's variant
  element or the colour its art glows in (mean of its bright, saturated pixels, read once per picture), a bolt's element, loot's rarity colour.
* **Pools by kind.** A boss's pool is 60 px (no wider than the hero's 64) on the steep texture, so the boss stands in a spot of light. A monster
  whose glow is pale (saturation under `PALE_SATURATION` 0.45: the wraith, the lich, the matriarch, the sovereign, the dummy) would light a flat
  white patch: `Lighting.pool_colour` gives it its own hue at saturation 0.6 (a near-grey one takes `PALE_TINT`, a cold blue), and
  `Lighting.flags_of` marks it `SOFT` (energy x 0.7; not for bosses). The exit door's pool sits 12 px inside the room in front of it:
  `DOOR_LOCKED` (dim cold blue, `SOFT`) while barred, `DOOR_OPEN` (warm amber, which flickers like fire) once open. The entry is a plain sealed
  wall block and carries no light.
* **Motion and comfort.** In "full", orange and red lights (not white or grey ones) flicker by at most +-8% (2.1 and 3.7 Hz sines) and bosses breathe +-8% at 0.45 Hz;
  "soft" and "off" never move.
* **Setting.** `Settings.lighting`: "full" (default), "soft" (ambient 40% of the way back to unlit, pools at 60%, no flicker) or "off" (nothing
  built); validated in `Settings._clean`, applies from the next scene (`Lighting (next scene)` in the Game tab, which now scrolls like the
  controls list so it fits the 180 px screen). Per-place ambients are data in `Lighting.AMBIENT` (see docs/ART_DIRECTION.md).
* **Cost** (RTX 4050 laptop, 1280 x 720, vsync off, a vault room with 22 monsters, bolts in flight, 24 lights on): 203 fps / 4.9 ms a frame with
  "full", 220 fps / 4.55 ms with "off"; `Lighting._process` itself takes about 0.23 ms; 1000 updates created 0 objects and 0 bytes.

## Effects (`scripts/combat/skill_fx.gd`, `hit_fx.gd`, `scripts/world/ambient_motes.gd`)

* **Helpers.** Everything is code-built `CPUParticles2D` (one-shot, freed on `finished`), `FxRing` and glow sprites: no PNG. Spell looks
  (`SkillFx.PROFILES`, `burst`, `cast_burst`, `trail`, `impact`, `area_burst`, `aura`) are as before; the event effects are
  `death(parent, enemy)`, `hero_death`, `fanfare(hero, reward)`, `sparkle` (loot collected), `chest_puff`, `dust` (a low floor puff) and
  `dust_ring` (a slam's cloud), all built on `specks(color, amount, life)`: square 1-2 px specks, lighter at birth, fading out.
* **The cap.** `SkillFx.MAX_LIVE` = 48 short-lived emitters alive at once across every helper (HitFx included): `admit(priority)` says whether
  a new one may start, `launch` / `launch_upright` start and count it, `live_count()` drops the freed ones. Hit sparks stop at
  `MAX_LIVE - RESERVE` (36); deaths, level-ups, the hero's death, the boss slam and a door's dust are priority and may take the last 12. An impact
  over budget drops its ring and flash too. Telegraph and spawn rings (`ring` called directly) are never capped.
* **Where each event plays.** A monster's death: `Enemy._damage` (it replaced the old green burst); the monster is still freed in the same call, so
  XP, loot, `died` and the room's clear happen when they always did, and an `FxCorpse` (its last picture) fades for 0.4 s (0.6 s for a boss or
  mini boss) so it does not pop. The hero's death: `Player.take_damage`. Level-up and reward: `Dungeon._fanfare`, beside the sound. Loot:
  `Pickup._collect`, `Chest.interact`, `Door.unlock`. Dodge: `Player.try_dodge` and the frame the roll ends. Slam: `Enemy._land_slam`.
* **Through the isometric view.** Rings and dust lie on the floor, so they go to the ground picture like every flat effect. Effects that rise
  (death specks, the level-up column, sparkles, the chest puff, the room's motes) would only slide along the floor there, so `launch_upright` puts
  them on IsoView's stage instead (`IsoView.add_upright(node, ground_point, lift)`), sorted with the bodies; `SkillFx.FxFollow` keeps the level-up
  column on the walking hero. `FxCorpse` is in `IsoView._stands_up`, so the fading picture gets a standing mirror and a fading shadow. In the flat
  view (no IsoView) the same nodes sit in the world at the point minus the lift. Nothing here carries `Lighting.LIT`: effects keep their colour.
* **Ambient motes.** `Dungeon._build_room` adds one `AmbientMotes` per room (unless `Settings.ambient_particles` is false: then nothing is created),
  freed with the room. One emitter, at most 24 specks (`MAX_SPECKS`), alpha at most 0.5, born at 48 spots scattered once over the floor
  (`EMISSION_SHAPE_POINTS`, already projected and lifted in the isometric view), `preprocess` so the room starts full. On the stage it sits at the
  origin, which sorts before every wall and body, so they hide the specks behind them. Looks per place: `AmbientMotes.LOOKS`
  (docs/ART_DIRECTION.md). Its own RandomNumberGenerator, so it never shifts the game's `randf()`.
* **Setting.** `ambient_particles` (bool, default true; anything not a bool is true) in `Settings._clean`; "Ambient particles (next room)" in the
  Game tab.
* **Cost** (RTX 4050 laptop, 1280 x 720 window, vsync off, editor open, a vault room with 22 monsters and a boss, a spin every 0.55 s, the boss
  killed at 1.5 s, 4 s averaged; "before" = no cap, no event effects, no motes, switched by a temporary flag): 10.5 ms (95 fps) with the effects,
  10.6 ms before. Worst case (also seven element hits on every monster at each spin, ~150 hits a frame): 53 ms with the cap (36 emitters live) vs
  56 ms without it (179 live); that case is dominated by the damage numbers, not the particles.
