# Elementalist: balance measurement

What the game's numbers add up to, measured with the game's own code. The target tone is **forgiving**: monsters
hit noticeably softer, every lethal attack is telegraphed and avoidable, healing comes between fights and mistakes
are cheap. The game was tuned to that tone (see "After tuning"); the tables below are the tuned game. A short
"Before" summary keeps the first measurement.

The numbers come from `elementalist/tests/balance_report.gd`. It calls the real functions (`Monsters.floor_scale`,
`Enemy.configure`, `Dungeon._monster_scale`, `DungeonGen.generate`, `CharacterData.derived`, `SkillCaster`,
`Loot`, `Pickup.gold_value`, `Forge`, `Ceremony`, `CharacterData.die`), seeds every random roll and prints Markdown
tables. Run it again after any tuning change to get fresh tables:

```
godot --headless --path elementalist res://tests/balance_report.tscn
```

It takes about 8 seconds. It reads no save and writes no file.

## How it measures

- **Floors.** The first, middle and last floor of each of the five dungeons (tiers). "T2 F5 (d10)" means tier 2,
  floor 5, overall depth 10. Monsters scale with depth, not with the tier's own floor number.
- **Monsters.** Each monster is a real `Enemy` configured exactly as `Dungeon._spawn_wave` does it, then read back.
  "Normal hit" is the band-weighted main attack of the monsters that can roll on that floor: touch for melee,
  the shot for ranged monsters. "Elite" is the elemental variant of the band's hardest-touching monster.
  "Guardian slam" is the heaviest of the three mini bosses scaled to that depth.
- **Heroes.** Sandbox heroes owning Fire, no traits, no subclass, element and weapon mastery equal to the level
  (capped at 10). Free attribute points are left unspent unless a column says "VIT", where every point goes into
  Vitality (the most HP a hero can have). "Typical gear" is six uncommon +0 pieces with no affixes.
- **The intended level.** A hero clears each tier once, in order, killing everything (summons included). The level
  on each floor comes from the real XP table. That is the slowest path; a player who repeats tiers is higher.
- **Fight maths** uses the seven playable classes at that level, in typical gear of the floor's own loot level, so
  defence from gear (damage taken goes down as item level goes up) is counted.
- **Targets** (share of max HP one hit takes, Knight, median class): normal 5-8%, elite 10-15%, guardian 15-20%,
  final boss 15-25%. "Factor" is the multiplier on today's damage that would put the median class mid-target:
  x1.0 is on target, above 1 is softer than the middle of the band.
- Two numbers live inside function bodies with no constant to read; the report names them: the clear bonus
  150 x tier (`Dungeon._finish_run`) and the roll's ease-out average 67.5% (`Player._physics_process`).

## Before (the first measurement)

Knight, first-clear level, median class, points unspent. The game before this tuning:

| Measure | Before | Target |
|---|---|---|
| Normal hit, share of max HP | 6-9% on T1 F1, 9-19% everywhere after | 5-8% |
| Elite (variant) hit | 16-37% | 10-15% |
| Guardian slam | 17-42% | 15-20% |
| Final boss slam | 23-68% (frailest dies in 2-3) | 15-25% |
| Factor normal / elite / boss | x0.36-0.78 / x0.36-1.06 / x0.30-0.74 | x1.0 |
| Heal between two combat rooms | none (forge 50% on half the floors, level-up 20%) | some |
| Dash wind-up at depth 15+ | 0.20 s, lunges up to 1747 px/s over 437 px | readable |
| Monsters per room from a tier's fifth floor | 14-18 | about 12 |
| Variants from depth 4 | 56-65% of all monsters | rare |
| Warlord's drop gold | about 2% more than Knight (reward ignored) | 60% more |

## After tuning

Every constant moved:

| File | Constant | Old | New |
|---|---|---|---|
| `scripts/world/dungeon.gd` | `FORGE_HEAL` | 0.5 | 1.0 |
| `scripts/world/dungeon.gd` | `CLEAR_HEAL` (new; `_clear_room` -> `_clear_heal`) | none | 0.15 (combat and guardian rooms, green "+N") |
| `scripts/character/character_data.gd` | `LEVEL_UP_HEAL_FRACTION` | 0.2 | 1.0 |
| `scripts/character/character_data.gd` | `HP_PER_LEVEL` (new, in `derived()`) | 0 | +5 max HP a level, every class |
| `scripts/character/classes.gd` | `HP_REGEN_SHARE` (new, in `derived()`) | 0 | 0.004 of max HP a second (`HP_REGEN_BASE` 0.1 and `HP_REGEN_PER_VIT` 0.03 unchanged) |
| `scripts/player/player.gd` | `hp_regen_delay` | 6 s | 3 s |
| `scripts/player/player.gd` | `dodge_iframes` / `dodge_stamina_cost` | 0.3 s / 30 | 0.4 s / 25 |
| `scripts/combat/monsters.gd` | `HARDNESS` | 1.35 | 1.0 |
| `scripts/combat/monsters.gd` | `floor_scale` damage slope (`DAMAGE_PER_FLOOR`, new) | +0.2 a floor to depth 10, +0.07 after | +0.08, +0.06 (HP slope unchanged) |
| `scripts/combat/monsters.gd` | `VARIANT_CHANCE_PER_FLOOR` / `VARIANT_CHANCE_MAX` | 0.15 / 0.6 | 0.04 / 0.3 |
| `scripts/combat/monsters.gd` | guardian `slam.damage`: Grave Warden / Ember Matron / Bog Hulk | 16 / 18 / 22 | 19 / 22 / 26 |
| `scripts/combat/monsters.gd` | boss `slam.damage`: Crypt Lich / Tide Titan / Thorn Matriarch | 34 / 38 / 26 | 30 / 32 / 30 |
| `scripts/combat/enemy.gd` | `CONTACT_COOLDOWN` (was a literal in `_physics_process`) | 0.9 s | 1.2 s |
| `scripts/combat/enemy.gd` | `SLAM_STUN` | 0.5 s | 0.25 s |
| `scripts/combat/enemy.gd` | `ENRAGE_COOLDOWN` (was a literal in `_enrage_cooldown`) | x0.65 | x0.8 |
| `scripts/combat/enemy.gd` | `DASH_WINDUP_MIN` (`configure`) | 0.2 s | 0.4 s |
| `scripts/combat/enemy.gd` | `DASH_SPEED_MAX` (new) | no cap | 300 px/s |
| `scripts/combat/enemy.gd` | `DODGE_CHANCE_MAX` (growth +8% a level kept) | 0.7 | 0.45 |
| `scripts/combat/enemy.gd` | `WALK_SPEED_MAX` (new; growth +4% a level kept, enrage too) | no cap | 80 px/s (a level-1 Novice) |
| `scripts/world/dungeon_gen.gd` | wave size (`WAVE_GROWTH_FLOORS`, new) | 2 + min(f, 5) to 3 + min(f, 5) (+1 from floor 2) | 2 + min(f, 3) to 3 + min(f, 3) |
| `scripts/core/game.gd` | `DIFFICULTIES` hardness Squire / Knight / Warlord | 0.8 / 1.0 / 1.3 | 0.75 / 1.0 / 1.25 (rewards unchanged, descriptions rewritten) |
| `scripts/world/pickup.gd` | gold drops (`gold_value`, new) | amount as rolled | amount x `Game.reward_mult()`, rounded, at least 1 |

Why HARDNESS ended at 1.0 rather than about 0.55: flattening the damage slope already cuts deep damage to
x0.61-0.75 of before (depth 10: x1.72 instead of x2.80; depth 62: x4.84 instead of x6.44), and it fixes the
first three floors climbing too fast. With both, damage at depth 62 is x0.56 of before in all. One HARDNESS cut
alone would have left T1 F1 too soft and T2 too hard. HARDNESS 1.0 also removes the hidden multiplier.

Final factor columns (normal / elite / boss, guardian where the floor has no boss):

| Where | Normal | Elite | Boss or guardian |
|---|---|---|---|
| T1 F1 (d1) | x1.06 | x1.44 | x0.74 (no guardian can stand here: the first is on floor 3) |
| T1 F3 (d3) | x1.02 | x0.93 | x0.96 |
| T1 F5 (d5) | x0.99 | x0.99 | x1.09 |
| T2 F1 (d6) | x0.99 | x1.00 | x1.03 |
| T2 F5 (d10) | x0.99 | x0.99 | x1.02 |
| T2 F10 (d15) | x1.02 | x1.02 | x0.98 |
| T3 F1 (d16) | x1.04 | x1.04 | x1.08 |
| T3 F6 (d21) | x1.02 | x1.05 | x1.08 |
| T3 F12 (d27) | x1.03 | x1.05 | x1.08 |
| T4 F1 (d28) | x1.05 | x1.07 | x1.11 |
| T4 F8 (d35) | x0.93 | x0.97 | x1.12 |
| T4 F15 (d42) | x0.95 | x0.99 | x1.07 |
| T5 F1 (d43) | x0.88 | x0.99 | x1.15 |
| T5 F10 (d52) | x0.93 | x1.05 | x1.22 |
| T5 F20 (d62) | x0.98 | x1.11 | x1.01 |

Everything lands in x0.88-1.22 except the first floor's elite (x1.44: band-1 monsters are weak and only 4% of
them are variants there) and a guardian cell on a floor no guardian can reach.

## Headline findings (tuned)

1. **Normal hits sit in the target all game.** 4.1-7.6% of max HP across the classes on every sampled floor
   (median on target, x0.88-1.06). The frailest class takes 14-16 normal hits to fall.
2. **Bosses take five or more slams.** A final boss slam takes 13.2-19.3% (T1), 13.7-21.1% (T2), 12.3-19.0% (T3),
   12.3-19.1% (T4) and 13.2-20.2% (T5). The frailest class survives 5-6 slams. Guardians take 9.0-19.2%.
3. **No hidden multiplier.** `Monsters.HARDNESS = 1.0`; the oath is the only extra dial (x0.75 / x1 / x1.25).
4. **Healing comes between rooms.** Every cleared combat or guardian room gives 15% of max HP, a forge room and a
   level-up heal fully, and out of combat health returns at about 0.5% of max HP a second (10% in 12-23 s) from
   3 s after the last hit. The budget is 35-142% of max HP per fight, 5-23 normal hits.
5. **Every telegraphed attack stays readable.** Dash wind-ups never drop below 0.4 s and lunges stop at 300 px/s
   (75 px at most). Slams keep 0.8-1.0 s of telegraph against 0.5-0.7 s to walk out. Touch is still not
   telegraphed, but it lands at most every 1.2 s and is 5-8% of HP.
6. **Elites are special again.** 2% of monsters on T1 F1, 12-16% on the rest of T1, 22-35% after.
7. **Rooms are smaller.** 3-8 monsters on a tier's first floor, 4-10 on its second, 10-12 from its third.
8. **HP grows with level for everyone** (+5 a level): Novice 118 at level 1 and 352 at 30 in typical gear.
9. **The oath's reward now applies to drop gold.** Warlord kill gold is x1.7 Knight's (x2.2 Squire's).
10. **Side effect: fewer kills, slower levels.** Smaller rooms give 26-33% less XP per clear. A Knight leaves T4
    at level 24 (was 28) and reaches 30 only at the end of T5. Time to kill a normal monster at the intended level
    rose by 0-15% (T4 F15: 3.2 s instead of 2.8 s with the fireball), and a boss by up to 16%.

## 1. Monsters

### The dials

| Dial | Value |
|---|---|
| `Monsters.HARDNESS` (all monster damage) | 1.0 |
| Variant HP / damage (touch only) / XP | x1.25 / x1.20 / x1.50 |
| Variant chance | 4% per depth, cap 30% |
| Touch cooldown | 1.2 s between touch hits that land |
| Dash | wind-up at least 0.4 s, speed at most 300 px/s, cooldown at least 1.2 s |
| Dodge (monsters) | +8% a level, cap 45%, cooldown at least 0.8 s |
| Walk speed | +4% a level, never above 80 px/s (a monster that starts faster keeps its own) |
| Boss enrage | below 30% HP: cooldowns x0.8, speed x1.25 within the walk cap (final bosses only) |
| Slam stun | 0.25 s, then 1.5 s of stun immunity |

| Oath | Hardness (HP and damage) | Reward (XP, drop gold, clear bonus, drop luck) |
|---|---|---|
| Squire | 0.75 | 0.8 |
| Knight | 1.0 | 1.0 |
| Warlord | 1.25 | 1.6 |

`Monsters.floor_scale` raises HP +35% a floor and damage +8% a floor up to depth 10, then +14% and +6%. HP x11.4
and damage x4.84 at depth 62.

### Per floor, by oath (Squire / Knight / Warlord)

| Where | Normal hit | Heaviest normal hit | Avg normal HP | Guardian slam (max) | Boss slam | Boss HP |
|---|---|---|---|---|---|---|
| T1 F1 (d1) | 5.1 / 6.8 / 8.5 | 6.0 / 8.0 / 10.0 | 24 / 31 / 39 | 19.5 / 26.0 / 32.5 | - | - |
| T1 F3 (d3) | 7.9 / 10.6 / 13.2 | 15.7 / 20.9 / 26.1 | 63 / 85 / 106 | 22.6 / 30.2 / 37.7 | - | - |
| T1 F5 (d5) | 9.9 / 13.2 / 16.5 | 17.8 / 23.8 / 29.7 | 101 / 135 / 168 | 25.7 / 34.3 / 42.9 | 27.7 / 37.0 / 46.2 | 1224 / 1632 / 2040 |
| T2 F1 (d6) | 10.5 / 14.0 / 17.5 | 18.9 / 25.2 / 31.5 | 116 / 154 / 193 | 27.3 / 36.4 / 45.5 | - | - |
| T2 F5 (d10) | 12.9 / 17.2 / 21.5 | 23.2 / 31.0 / 38.7 | 175 / 233 / 291 | 33.5 / 44.7 / 55.9 | - | - |
| T2 F10 (d15) | 15.1 / 20.1 / 25.1 | 27.3 / 36.4 / 45.5 | 197 / 262 / 328 | 39.4 / 52.5 / 65.7 | 48.5 / 64.6 / 80.8 | 4001 / 5335 / 6669 |
| T3 F1 (d16) | 15.5 / 20.7 / 25.9 | 28.1 / 37.4 / 46.8 | 202 / 270 / 337 | 40.6 / 54.1 / 67.6 | - | - |
| T3 F6 (d21) | 18.2 / 24.3 / 30.4 | 32.1 / 42.8 / 53.5 | 229 / 305 / 382 | 46.4 / 61.9 / 77.3 | - | - |
| T3 F12 (d27) | 21.0 / 28.0 / 35.0 | 37.0 / 49.3 / 61.6 | 263 / 351 / 438 | 53.4 / 71.2 / 89.0 | 61.7 / 82.2 / 102.7 | 6122 / 8163 / 10203 |
| T4 F1 (d28) | 21.4 / 28.6 / 35.7 | 37.8 / 50.4 / 63.0 | 269 / 358 / 448 | 54.6 / 72.8 / 91.0 | - | - |
| T4 F8 (d35) | 28.2 / 37.6 / 47.0 | 43.5 / 58.0 / 72.5 | 393 / 524 / 655 | 62.8 / 83.7 / 104.7 | - | - |
| T4 F15 (d42) | 31.9 / 42.5 / 53.1 | 49.1 / 65.5 / 81.9 | 443 / 591 / 739 | 71.0 / 94.6 / 118.3 | 87.4 / 116.5 / 145.6 | 11003 / 14671 / 18339 |
| T5 F1 (d43) | 35.2 / 46.9 / 58.6 | 50.0 / 66.6 / 83.3 | 524 / 699 / 873 | 72.2 / 96.2 / 120.3 | - | - |
| T5 F10 (d52) | 40.3 / 53.7 / 67.1 | 57.2 / 76.3 / 95.4 | 599 / 799 / 999 | 82.7 / 110.2 / 137.8 | - | - |
| T5 F20 (d62) | 46.0 / 61.3 / 76.6 | 65.3 / 87.1 / 108.9 | 683 / 911 / 1138 | 94.4 / 125.8 / 157.3 | 137.9 / 183.9 / 229.9 | 19717 / 26289 / 32861 |

Where two bosses share a tier (T1: Slime King or Stone Colossus, T2: Crypt Lich or Tide Titan) the harder one is
shown. Monster HP is unchanged by this tuning except through the oath (Squire 0.75 instead of 0.8, Warlord 1.25
instead of 1.3).

### A sample of single monsters, Knight

| Where | Monster | HP | Touch | Shot (dmg @ cooldown, flight) | Dash (hit @ cooldown, wind-up) | Slam (dmg @ cooldown, telegraph, radius) | Speed | Dodge | XP |
|---|---|---|---|---|---|---|---|---|---|
| T1 F1 (d1) | Slime | 40 | 8.0 | - | - | - | 30 | - | 12 |
| T1 F1 (d1) | Skeleton Archer | 32 | - | 7.0 @2.2s, 0.84s | - | - | 28 | - | 16 |
| T1 F3 (d3) | Stone Brute | 221 | 18.6 | - | - | - | 18 | - | 34 |
| T1 F3 (d3) | Imp | 48 | 10.4 | - | 16.7 @2.4s, 0.40s | - | 43 | - | 20 |
| T1 F5 (d5) | Bone Duelist | 168 | 15.8 | 6.6 @3.0s, 1.11s | 23.8 @1.9s, 0.40s | - | 42 | 45% | 40 |
| T1 F5 (d5) | Stone Colossus | 1632 | 23.8 | - | - | 37.0 @5.0s, 0.90s, r48 | 21 | - | 260 |
| T2 F10 (d15) | Tide Titan | 5335 | 40.4 | 20.2 @1.8s, 1.25s | 64.6 @1.2s, 0.40s | 64.6 @5.0s, 1.00s, r60 | 27 | - | 460 |
| T4 F15 (d42) | Magma Slug | 1295 | 65.5 | - | - | - | 37 | - | 38 |
| T4 F15 (d42) | Cinder Tyrant | 14671 | 80.1 | 43.7 @1.6s, 1.16s | 136.1 @1.2s, 0.40s | 116.5 @3.8s, 0.90s, r52 | 63 | - | 720 |
| T5 F20 (d62) | Dire Wolf | 549 | 48.4 | - | 72.6 @1.2s, 0.40s | - | 80 | - | 26 |
| T5 F20 (d62) | Gloom Shade | 457 | - | 53.2 @1.6s, 1.00s | - | - | 80 | 45% | 36 |
| T5 F20 (d62) | Gloaming Sovereign | 26289 | 116.2 | 67.8 @1.3s, 1.40s | 209.1 @1.2s, 0.40s | 183.9 @3.5s, 0.90s, r56 | 80 | - | 1000 |

### Monsters per room (24 seeded layouts per tier)

| Where | Monsters/room | Range | Waves | Variants | Room HP total (Knight) |
|---|---|---|---|---|---|
| T1 F1 (d1) | 5.2 | 3-8 | 1.5 | 2% | 164 |
| T1 F3 (d3) | 10.8 | 10-12 | 2.0 | 12% | 945 |
| T1 F5 (d5) | 11.0 | 10-12 | 2.0 | 16% | 1547 |
| T2 F1 (d6) | 5.7 | 3-8 | 1.6 | 22% | 923 |
| T2 F5 (d10) | 11.2 | 10-12 | 2.0 | 33% | 2815 |
| T3 F6 (d21) | 11.3 | 10-12 | 2.0 | 31% | 3729 |
| T4 F8 (d35) | 10.8 | 10-12 | 2.0 | 30% | 6076 |
| T5 F20 (d62) | 11.1 | 10-12 | 2.0 | 28% | 10794 |

Room size follows the tier's own floor number (`DungeonGen._make_room`): waves of 3-4 on a tier's first floor,
4-5 on its second, 5-6 from its third (two waves from the third floor on).

## 2. Heroes

### Max HP, typical gear (HP with every free point in Vitality in brackets)

| Class | L1 HP | L10 HP | L20 HP | L30 HP | HP/s at L30 | Fireball DPS L1 / L10 / L30 | Slash DPS L1 / L10 / L30 |
|---|---|---|---|---|---|---|---|
| Novice | 118 | 200 (344) | 276 (580) | 352 (816) | 1.66 | 13 / 18 / 18 | 10 / 19 / 27 |
| Channeler | 110 | 192 (336) | 268 (572) | 344 (808) | 1.60 | 27 / 70 / 163 | 7 / 11 / 14 |
| Vanguard | 138 | 220 (364) | 296 (600) | 372 (836) | 1.77 | 10 / 14 / 15 | 12 / 34 / 84 |
| Ranger | 110 | 192 (336) | 268 (572) | 344 (808) | 1.60 | 11 / 15 / 15 | 11 / 22 / 39 |
| Mystic | 134 | 288 (432) | 444 (748) | 600 (1064) | 3.58 | 18 / 25 / 26 | 7 / 11 / 13 |
| Assassin | 102 | 184 (328) | 260 (564) | 336 (800) | 1.53 | 10 / 13 / 14 | 11 / 24 / 45 |
| Berserker | 134 | 288 (432) | 444 (748) | 600 (1064) | 3.58 | 9 / 12 / 12 | 13 / 25 / 38 |
| Sage | 102 | 184 (328) | 260 (564) | 336 (800) | 1.53 | 31 / 69 / 156 | 6 / 10 / 12 |
| Druid | 142 | 224 (368) | 300 (604) | 376 (840) | 2.06 | 17 / 39 / 78 | 7 / 11 / 13 |

Every class gains 5 max HP a level (`CharacterData.HP_PER_LEVEL`); Mystic and Berserker also grow Vitality. Health
regen is 0.4% of max HP a second plus 0.1 + 0.03 per Vitality, about 0.45-0.85% in all. Every class now has four
dodges in a full bar at level 1 (25 stamina each) and three from level 5 (a 94 bar); Ranger and Assassin get more (up to 11 at level 30).

Level 40 cannot be reached: `CharacterData.MAX_LEVEL = 30`. The report still prints what the growth would give at
40 (marked `40*`).

### XP and the level after each tier

`CharacterData.xp_to_next(lv) = 30 x lv^1.4`: 30 XP for level 2, 753 for level 11, 3345 for level 30; 42,097 in all.
XP per kill does not grow with depth.

| Tier | Kills in a clear | XP of a clear (Sq / Kn / Wl) | Level in -> out (Sq / Kn / Wl) |
|---|---|---|---|
| T1 The Ashen Vaults | 78 | 1601 / 1999 / 3198 | 1 -> 8 / 1 -> 8 / 1 -> 10 |
| T2 The Drowned Crypts | 179 | 4874 / 6100 / 9756 | 8 -> 14 / 8 -> 15 / 10 -> 18 |
| T3 The Thornroot Hollow | 221 | 6159 / 7690 / 12303 | 14 -> 18 / 15 -> 20 / 18 -> 24 |
| T4 The Cinder Forge | 278 | 8520 / 10649 / 17045 | 18 -> 22 / 20 -> 24 / 24 -> 30 |
| T5 The Gloaming Spire | 382 | 12659 / 15827 / 25348 | 22 -> 27 / 24 -> 30 / 30 -> 30 |

## 3. Fight maths

Knight, first-clear level, the seven classes in typical gear of the floor's loot level. Each cell: the share of max
HP one hit takes, lowest to highest across the classes, and in brackets the hits that kill the frailest class.

### What one hit costs, per tier

| Where | Lvl | Max HP | Normal | Heaviest normal | Elite (variant) | Guardian slam | Boss slam | Factor normal / elite / boss | Normal, all VIT | Boss or guardian, all VIT |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 F1 (d1) | 1 | 102-142 | 4.8-6.6% (16) | 5.6-7.8% (13) | 6.7-9.4% (11) | 18.3-25.4% (4) | - | x1.06 / x1.44 / x0.74 | 4.8-6.6% | 18.3-25.4% |
| T1 F3 (d3) | 4 | 144-200 | 4.9-6.7% (15) | 9.6-13.3% (8) | 10.2-14.2% (8) | 13.9-19.2% (6) | - | x1.02 / x0.93 / x0.96 | 3.9-5.1% | 11.2-14.4% |
| T1 F5 (d5) | 7 | 172-252 | 4.7-6.9% (15) | 8.5-12.4% (9) | 9.0-13.2% (8) | 12.2-17.9% (6) | 13.2-19.3% (6) | x0.99 / x0.99 / x1.09 | 3.4-4.4% | 9.5-12.4% |
| T2 F1 (d6) | 8 | 182-270 | 4.6-6.8% (15) | 8.3-12.3% (9) | 8.8-13.1% (8) | 12.0-17.7% (6) | - | x0.99 / x1.00 / x1.03 | 3.3-4.2% | 8.5-11.0% |
| T2 F5 (d10) | 11 | 215-327 | 4.5-6.8% (15) | 8.1-12.3% (9) | 8.6-13.1% (8) | 11.7-17.8% (6) | - | x0.99 / x0.99 / x1.02 | 3.0-3.9% | 7.8-10.2% |
| T2 F10 (d15) | 14 | 251-387 | 4.3-6.6% (16) | 7.7-11.9% (9) | 8.2-12.7% (8) | 11.1-17.1% (6) | 13.7-21.1% (5) | x1.02 / x1.02 / x0.98 | 2.8-3.6% | 8.9-11.5% |
| T3 F1 (d16) | 15 | 261-405 | 4.1-6.4% (16) | 7.5-11.6% (9) | 8.0-12.4% (9) | 10.8-16.8% (6) | - | x1.04 / x1.04 / x1.08 | 2.7-3.5% | 7.0-9.0% |
| T3 F6 (d21) | 17 | 289-449 | 4.2-6.5% (16) | 7.4-11.5% (9) | 7.9-12.3% (9) | 10.7-16.6% (7) | - | x1.02 / x1.05 / x1.08 | 2.7-3.5% | 6.8-8.8% |
| T3 F12 (d27) | 19 | 320-496 | 4.2-6.5% (16) | 7.4-11.4% (9) | 7.9-12.2% (9) | 10.6-16.5% (7) | 12.3-19.0% (6) | x1.03 / x1.05 / x1.08 | 2.6-3.4% | 7.8-10.0% |
| T4 F1 (d28) | 20 | 330-514 | 4.1-6.3% (16) | 7.2-11.2% (9) | 7.6-11.9% (9) | 10.4-16.1% (7) | - | x1.05 / x1.07 / x1.11 | 2.6-3.3% | 6.5-8.4% |
| T4 F8 (d35) | 22 | 363-563 | 4.6-7.1% (15) | 7.1-11.0% (10) | 8.5-13.2% (8) | 10.3-15.9% (7) | - | x0.93 / x0.97 / x1.12 | 2.9-3.7% | 6.4-8.3% |
| T4 F15 (d42) | 24 | 396-612 | 4.5-6.9% (15) | 6.9-10.7% (10) | 8.3-12.9% (8) | 10.0-15.5% (7) | 12.3-19.1% (6) | x0.95 / x0.99 / x1.07 | 2.8-3.6% | 7.7-9.9% |
| T5 F1 (d43) | 24 | 399-615 | 4.9-7.6% (14) | 7.0-10.8% (10) | 8.4-12.9% (8) | 10.1-15.5% (7) | - | x0.88 / x0.99 / x1.15 | 3.1-3.9% | 6.3-8.1% |
| T5 F10 (d52) | 27 | 445-685 | 4.6-7.1% (15) | 6.6-10.1% (10) | 7.9-12.1% (9) | 9.5-14.6% (7) | - | x0.93 / x1.05 / x1.22 | 2.9-3.7% | 5.9-7.5% |
| T5 F20 (d62) | 29 | 485-741 | 4.4-6.7% (15) | 6.3-9.6% (11) | 7.5-11.5% (9) | 9.0-13.8% (8) | 13.2-20.2% (5) | x0.98 / x1.11 / x1.01 | 2.7-3.5% | 8.2-10.5% |

Per tier, lowest to highest across the classes and the tier's sampled floors (guardians from floor 3, where the
first one stands):

| Tier | Normal | Elite | Guardian slam | Final boss slam |
|---|---|---|---|---|
| T1 | 4.7-6.9% | 6.7-14.2% | 12.2-19.2% | 13.2-19.3% |
| T2 | 4.3-6.8% | 8.2-13.1% | 11.1-17.8% | 13.7-21.1% |
| T3 | 4.1-6.5% | 7.9-12.4% | 10.6-16.8% | 12.3-19.0% |
| T4 | 4.1-7.1% | 7.6-13.2% | 10.0-16.1% | 12.3-19.1% |
| T5 | 4.4-7.6% | 7.5-12.9% | 9.0-15.5% | 13.2-20.2% |

Reading it: the median class lands mid-target for normal hits and elites everywhere (x0.88-1.11), and at or a
little under the middle for guardians and bosses (x0.96-1.22), which is the forgiving side. The frailest class
(Assassin, Sage) needs 14-16 normal hits and 5-6 boss slams. The spread between classes is still about 1.5x.

### Time to kill and the room's pressure

Hero DPS: Channeler fireball / Vanguard slash, sustained. Room DPS is every monster attacking whenever it can and
nobody dodging, an upper bound; "stand still" is how long a hero who never dodges survives it.

| Where | Hero DPS | Normal HP | TTK normal (s) | Boss HP | TTK boss (s) | Room HP | Room clear (s) | Room DPS | Stand still (s) |
|---|---|---|---|---|---|---|---|---|---|
| T1 F1 (d1) | 27 / 12 | 31 | 1.2 / 2.6 | - | - | 164 | 6 / 13 | 29 | 3.5-4.9 |
| T1 F5 (d5) | 58 / 28 | 135 | 2.3 / 4.8 | 1632 | 28 / 58 | 1547 | 27 / 55 | 115 | 1.5-2.2 |
| T2 F10 (d15) | 99 / 53 | 262 | 2.7 / 5.0 | 5335 | 54 / 101 | 3110 | 32 / 59 | 173 | 1.5-2.2 |
| T3 F12 (d27) | 136 / 78 | 351 | 2.6 / 4.5 | 8163 | 60 / 104 | 4101 | 30 / 52 | 238 | 1.3-2.1 |
| T4 F15 (d42) | 185 / 114 | 591 | 3.2 / 5.2 | 14671 | 80 / 128 | 6956 | 38 / 61 | 370 | 1.1-1.7 |
| T5 F20 (d62) | 251 / 166 | 911 | 3.6 / 5.5 | 26289 | 105 / 158 | 10794 | 43 / 65 | 540 | 0.9-1.4 |

Time to kill a normal monster stays near 1-6 s all game. It is 0-15% longer than before because the hero arrives
a few levels lower (smaller rooms give less XP); monster HP did not change. Room clears are shorter (fewer
monsters) and a room that nobody dodges takes 2-5 times longer to kill a hero than before.

### Healing between rooms

Heal per floor = chance of a forge room x 100% + levels gained on that floor x 100% + combat and guardian rooms
cleared x 15%. Budget = that heal per fight (two fights a floor). "Hits" = how many median normal hits the budget
covers.

| Where | Forge chance | Levels gained | Heal/floor | Budget/fight | Normal hits/fight | Regen 10% (s) |
|---|---|---|---|---|---|---|
| T1 F1 (d1) | 54% | 2 | 284% | 142.1% | 23.1 | 12-15 |
| T1 F5 (d5) | 67% | 1 | 182% | 90.8% | 13.8 | 15-20 |
| T2 F5 (d10) | 42% | 1 | 172% | 85.8% | 13.0 | 16-20 |
| T3 F1 (d16) | 58% | 0 | 88% | 44.2% | 7.1 | 17-21 |
| T4 F15 (d42) | 54% | 0 | 69% | 34.6% | 5.1 | 18-22 |
| T5 F20 (d62) | 58% | 1 | 173% | 86.7% | 13.1 | 18-23 |

Every healing source in the game:

| Source | Amount |
|---|---|
| Clearing a combat or guardian room | 15% of max HP (a green "+N" over the hero) |
| Forge room | 100% of max HP, all stamina and mana; on about half the floors |
| Camp | everything (between runs only) |
| Level-up | 100% of max HP |
| Natural regen | 0.4% of max HP a second plus 0.1 + 0.03 per Vitality (Novice level 10: 0.83 HP/s, 34% of max HP a minute), paused 3 s after any hit |
| Tidal Mending (Water support, level 7) | 48 HP over 6 s, every 18 s |
| Benediction (Light support, level 7) | 60 HP over 6 s, every 18 s |
| Shadow Bolt (Dark) | 25% lifesteal |
| Bloodrage (Berserker) / Vampiric / Survivor traits | 3 / 2 / 1 HP per kill |
| Lucky Charm amulet | 1 HP per kill at item level 1, 6.6 at item level 60 |
| Potions, healing drops | none exist |

The room-clear heal lives in `Dungeon._clear_room` (it calls `_clear_heal` for combat and guardian rooms only:
treasure and forge rooms, the boss room, the camp and the training grounds give none). In a co-op game it heals
the host's hero; guests' heroes are not healed by it.

### Warning time versus the dodge

The dodge: 0.40 s of i-frames, a roll of about 32 px, 25 stamina (three or four dodges from a 94-109 bar for most classes),
0.40 s cooldown; stamina waits 0.8 s after spending, then regains 17-26 a second (Ranger and Assassin more).

| Attack | d1 | d5 | d15 | d27 | d42 | d62 |
|---|---|---|---|---|---|---|
| Touch (every melee monster) | no warning, every 1.2 s | same | same | same | same | same |
| Imp dash: wind-up, lunge | 0.40 s, 48 px | 0.40 s, 70 px | 0.40 s, 75 px | 0.40 s, 75 px | 0.40 s, 75 px | 0.40 s, 75 px |
| Dire Wolf dash | 0.40 s, 53 px | 0.40 s, 75 px | 0.40 s, 75 px | 0.40 s, 75 px | 0.40 s, 75 px | 0.40 s, 75 px |
| Bone Duelist dash | 0.45 s, 50 px | 0.40 s, 74 px | 0.40 s, 75 px | 0.40 s, 75 px | 0.40 s, 75 px | 0.40 s, 75 px |
| Fastest shot: flight time | 0.84 s | 0.84 s | 0.84 s | 0.88 s | 0.88 s | 1.00 s |
| Slime King slam: telegraph, walk out | 0.80 s, 0.50 s | same | same | same | same | same |
| Gloaming Sovereign slam | 0.90 s, 0.70 s | same | same | same | same | same |
| Bog Hulk (guardian) slam | 0.90 s, 0.55 s | same | same | same | same | same |

- **Dashes are fair now.** A 0.4 s wind-up is above a typical 0.25 s reaction, and the 0.4 s of i-frames cover a
  lunge that lasts 0.25 s. A lunge reaches 75 px at most.
- **Slams and shots stay fair.** Slams: 0.8-1.0 s of telegraph against 0.5-0.7 s to walk out. Shots: 0.84-1.0 s of
  flight.
- **Touch is still not telegraphed**, but it is slower (1.2 s) and soft (5-8% a bite), and no monster walks faster
  than any hero, so walking away always works.

### Speed

Monsters gain 4% speed per depth level up to 80 px/s (`Enemy.WALK_SPEED_MAX`), the speed of a level-1 Novice, the
slowest hero. The slowest hero walks 82-114 px/s at the intended level. The Dire Wolf walks at the cap from depth 15,
the Imp from depth 27, the Wraith from depth 43; no regular monster or boss outpaces any hero at any depth.

## 4. Economy

### Income of one first clear, Knight

| Tier | Gold: kills | Chests | Guardians | Boss | Clear bonus | Gold total | Scrap | Gel | Essence | Gear pieces | Salvage all gear |
|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 489 | 96 | 82 | 176 | 150 | 993 | 56 | 27 | 23 | 14.3 | 291 g + 42 scrap |
| T2 | 2734 | 374 | 529 | 338 | 300 | 4275 | 116 | 59 | 67 | 32.3 | 1983 g + 111 scrap |
| T3 | 5944 | 617 | 744 | 462 | 450 | 8218 | 135 | 76 | 84 | 34.8 | 3785 g + 125 scrap |
| T4 | 10799 | 978 | 1473 | 533 | 600 | 14383 | 166 | 97 | 109 | 43.6 | 6561 g + 153 scrap |
| T5 | 19754 | 1767 | 2964 | 973 | 750 | 26208 | 232 | 134 | 150 | 60.5 | 12032 g + 209 scrap |

Gold of one clear by oath: T1 783 / 993 / 1675, T5 20,327 / 26,208 / 44,163 (Squire / Knight / Warlord). Every
gold drop (monsters, guardians, bosses, chests) is multiplied by the oath's reward when it is picked up
(`Pickup.gold_value`), so the Warlord's "60% richer spoils" is true: about x1.7 Knight's gold (the extra comes
from a higher level and loot luck).

Income is 15-26% lower than before at the same tier because rooms hold fewer monsters.

### Costs

| | Gold | Scrap | Other |
|---|---|---|---|
| Craft a piece | 15-40 | 4-10 | 0-3 gel |
| Upgrade +0 to +5 (common / uncommon / rare / epic / legendary) | 300 / 390 / 510 / 660 / 900 | 20 | |
| Upgrade +0 to +10 | 1100 / 1430 / 1870 / 2420 / 3300 | 65 | |
| Enchant (by rarity) | 40-120 | | 1 essence + 1 per 8 item levels |
| Six uncommon pieces to +5 / to +10 | 2340 / 8580 | 120 / 390 | |

Clears needed for a +10 uncommon kit, salvaging every drop (gold / scrap): T1 6.7 / 4.0, T2 1.4 / 1.7,
T3 0.7 / 1.5, T4 0.4 / 1.2, T5 0.2 / 0.9.

- **Gold inflates, costs do not.** From T2 on gold stops being a constraint; scrap (and the bag) is the real limit.
- **Essence is plentiful**: 23 a T1 clear against enchants that need 1-8.

### What a death costs

A fall in the dungeon costs `Game.DEATH_GOLD_LOSS` = 30% of carried gold, one element chosen at random and the
loot found in the run; a hero with no element left dies for good and the save is deleted. (Unchanged by this
tuning.)

| Hero has cleared | Gold carried (nothing spent) | Lost on a fall |
|---|---|---|
| T1 | 993 | 298 |
| T2 | 5269 | 1580 |
| T3 | 13486 | 4045 |
| T4 | 27869 | 8360 |
| T5 | 54077 | 16223 |

| Born with | Share of new heroes (20,000 ceremony rolls) | Permadeath at |
|---|---|---|
| 0 elements | 8.2% | death 1 |
| 1 element | 75.2% | death 2 |
| 2 elements | 13.6% | death 3 |
| 3 elements | 2.5% | death 4 |
| 4 elements | 0.5% | death 5 |
| 5 elements | 0.1% | death 6 |

## 5. Outliers and suspected bugs

1. **FIXED 2026-11-07: summoned minions now carry the boss's floor scale and level** (numbers below are from before the fix and are not re-measured: the Sovereign's shades are now as tough as native ones, which makes that fight harder; watch it in play). Was: **summoned minions ignore depth and oath** (left as is on purpose). `Enemy._spawn_minions` calls `Monsters.spawn`
   with the default scale (1, 1) and level 1. The Gloaming Sovereign's shades have 40 HP and an 11.0 hit; a shade
   native to that floor has 457 HP and a 53.2 hit. An accidental mercy, and free XP at depth.
2. **Dash scaling** is fixed: wind-up at least 0.4 s, speed at most 300 px/s. The cooldown still falls 12% a level
   to 1.2 s.
3. **Dodging monsters** reach the 45% cap by depth 2-3 and void about 30% of a Channeler's hits (x1.43 effective
   HP, was x1.66).
4. **Speed** is capped at 80 px/s (see Speed).
5. **The level cap (30)** is now reached at the end of T5 by a Knight; a Warlord is capped from the end of T4.
6. **FIXED 2026-11-07: a variant's shots carry `VARIANT_DAMAGE`** (not re-measured). Was: **variant damage skips shots** (left as is). A Fire Spitter at depth 10 touches for 14.4 (Spitter 12.0) but
   shoots for the same 10.3.
7. **XP per kill is flat with depth** while the XP curve rises as level^1.4. With smaller rooms the levels come
   more slowly (Knight 24 after T4, was 28).
8. **Drop gold follows the oath** (fixed in `Pickup.gold_value`).
9. **Gear defence scales with item level without a cap below 0.4.** Typical uncommon gear gives damage taken x0.90
   at item level 10, x0.81 at 30, x0.67 at 60 and x0.58 at 80. It is counted in the tables above.
10. **Variants** are 2-35% of monsters (was 56-65% from depth 4).
11. **HP grows with level for every class** (+5 a level).
12. **Mend skills heal 8-10 HP/s times the caster's spell power (1.0 to 1.6, `SkillCaster._spawn`) since 2026-11-07** (not re-measured; it does not follow max HP, lever 4 below). Was a flat 48 / 60 HP.
13. **Room size resets every tier** (3-8 on floor 1, 10-12 by floor 3), so each tier's first floor is a breather.
14. **The first floor's elite is soft** (x1.44 factor): band-1 monsters hit for 5-8 and only 4% are variants there.

## 6. Tuning levers still open

| # | File | Now | Direction |
|---|---|---|---|
| 1 | `scripts/combat/enemy.gd` touch damage | no wind-up, every 1.2 s | A short bite wind-up (the "bite" pose exists) would make every attack telegraphed. |
| 2 | `scripts/core/game.gd` `DIFFICULTIES` | hardness scales HP and damage together | Separate HP and damage multipliers so Squire can be soft without being quick. |
| 3 | `scripts/combat/enemy.gd` `_spawn_minions` | summons at depth 1 | Decide on purpose: pass the boss's scale, or keep them weak and say so. |
| 4 | `scripts/core/skill_db.gd` `tidal_mending` / `benediction` | flat 8 / 10 HP a second | A share of max HP, so mends keep up with deeper heroes. |
| 5 | XP per kill | flat with depth, fewer kills per room now | Raise XP per kill with depth if T4-T5 should not be fought below the intended level. |
| 6 | `scripts/character/character_data.gd` `MAX_LEVEL` | 30 | 35-40, or flatten `floor_scale` past depth 42. |
| 7 | `scripts/core/game.gd` `DEATH_GOLD_LOSS` | 0.3 | Kept on purpose. |

## What could not be measured

- How often a real player gets hit. The report gives the cost of a hit and the time to avoid it, not hit rates:
  aim, positioning, AI pathing, collisions and how many monsters reach the hero at once need play testing.
- Combos, splash, pierce, fusion and the martial Rend are left out of hero DPS (they raise it). Crits are counted as
  their expected value.
- Free points, traits, subclasses and gear affixes vary per hero. The report shows the two extremes for points
  (unspent and all in Vitality) and leaves out traits, subclasses and affixes.
- Whether every boss summon stage fires (a boss killed in one burst skips some); the report assumes all do.
