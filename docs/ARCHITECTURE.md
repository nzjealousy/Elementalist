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

**Death** (`CharacterData.die()`): with elements, lose `deaths` of them at random (`remove_element` resets
that element's mastery, special and skill uses; none left means attunable); with none, the result is `final`
and `RunEndScreen` starts a new character (`Game.open_creation` opens the creation menu in the next scene).

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
jump to the boss (the F-keys clash with the Godot editor's own debugger shortcuts; F8 even stops the game). `Game.run_text` is the HUD's "Floor 1/3 Room 2/3 ..." line.

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
- **Game flow:** title (`MainMenu`) -> `Game.new_game` / `continue_game` -> `scenes/main.tscn`, where
  `Dungeon._make_layout` builds the **camp** (`DungeonGen.camp_room`) or the saved dungeon from `Game.mode`.
  The gate (`CampGate` -> `DungeonSelect`) calls `Game.begin_run(tier)`; a finished run calls
  `Dungeon._finish_run` (meta, leaderboard, gold) and `RunEndScreen` returns to camp or the menu.
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
  at random) and `music/<track>.wav` (looped). `Sfx.music()` is called by `Dungeon._play_music`.

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

- Screens share `UiTheme`. In-game screens (character sheet, forge) use `focus_mode = FOCUS_NONE` buttons so
  TAB/WASD stay with the game; the shell menus (`MainMenu`, `SettingsMenu`, `PauseMenu`, ...) use `UiKit.button`,
  which takes focus, because they are navigated by keyboard and gamepad.
- `CharacterSheet` keeps every tab inside the 320x180 view: the body sits in a fixed-size
  `ScrollContainer`, and a tab's columns plus gaps must fit `CONTENT_WIDTH` (a self-test checks
  this and that the panel stays on screen even when stuffed with content).
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
* **Net flags:** `Player.net_state()` is `[x, y, aim_x, aim_y, hp, max_hp, flags]`; `Player.pack_flags`/`unpack_flags`: 1 moving, 2 dodging, 4 stunned, glow code from
  bit 3 (0 none, 1..7 = fire water air mineral earth light dark: append new elements, never reorder). `RemoteAvatar` and the arena ghosts re-register their look
  with `HeroLook.with_glow` when the code changes; a stunned partner or rival gets the stars (`SkillFx.stun_stars`, which also lines them up in the flat view).
