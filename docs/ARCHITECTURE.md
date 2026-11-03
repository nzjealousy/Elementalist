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
| `Game` | `game.gd` | The current `CharacterData`, new-game and sandbox helpers, kill XP, banner |

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

**Fighting style and LMB** (`Classes.style_of`, `SkillCaster.lmb_mode`): each class has a style.
`melee` (Vanguard): LMB always slashes; elements come from imbue and abilities (F, R), which are
castable regardless of style. `ranged` (Channeler, Ranger, Mystic): LMB shoots only while
imbued (mana per cast), and slashes when not. `hybrid` (the Novice) always shoots. The martial
set always shoots (knives are not an element). The Player turns LMB into a slash whenever the
caster says `"slash"`.

**Imbue (E)** (`Player.try_imbue`): a toggle with no timer and no cooldown. It needs at least
one castable element. While `imbued`, ranged classes' LMB shoots, and every slash carries
`imbue_elements()` (the locked elements, else the selected one): one hit per element in order
(so their combos fire), each costing `IMBUE_SWING_COST` mana; if you can't pay, the swing is
plain. Imbued hits set the aura, apply the element's primary status (`SkillCaster.status_for`)
and train the element, but give up the physical "Shatter" bonus.

**Locking and fusion** (`SkillCaster`, from level 5): Q toggles the selected element in `locked`
(max `Classes.MAX_LOCKED` = 3; the martial set can't be locked; no element means locked). With
nothing locked LMB uses the selected element; with one locked it is pinned to that element;
with 2-3 it casts a **fusion**: `primary_id()` returns `"fusion:fire+water"`, which costs the sum
of the parts, waits for the slowest cooldown plus 0.15 s per extra element, and fires one
`Projectile` whose `extra_hits` apply each element in turn at `FUSION_DAMAGE` (75%) damage.

**Dodge spin** (`Player.try_spin`): attacking while dodging (RMB, or LMB when it is a slash) is a
360 degree slash costing `SPIN_STAMINA_MULT` (1.8x) stamina, dealing 1.15x damage, once per dodge.
It uses the same imbue logic as a slash.

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

**A new enemy.** Duplicate `scenes/enemies/slime.tscn`, point `sprite_id` at a new placeholder in
`AssetDB.PLACEHOLDERS`, and set its exports (HP, speed, contact damage, `xp_reward`).

## Testing

`tests/combo_selftest.gd` (run `tests/combo_selftest.tscn`) covers the combat rules, the
character model, the ceremony statistics, gating, scaling, balance budgets, saving, and builds
every UI screen. A test that fails prints `FAIL <name>`. Tests seed their own RNGs; the player is
tested with a neutral character (`_neutral_character()`) so the tuned numbers stay meaningful.

## UI notes

- Screens share `UiTheme`. Buttons use `focus_mode = FOCUS_NONE` so TAB/WASD stay with the game.
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
