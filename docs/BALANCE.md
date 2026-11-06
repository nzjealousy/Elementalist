# Elementalist: balance measurement

What the game's numbers add up to today, measured with the game's own code, and what would have to move for the
new target tone: **forgiving**. Monsters should hit noticeably softer, every attack should be telegraphed and
avoidable, some healing should exist and mistakes should be cheap. Nothing here changes the game.

The numbers come from `elementalist/tests/balance_report.gd`. It calls the real functions (`Monsters.floor_scale`,
`Enemy.configure`, `Dungeon._monster_scale`, `DungeonGen.generate`, `CharacterData.derived`, `SkillCaster`,
`Loot`, `Forge`, `Ceremony`, `CharacterData.die`), seeds every random roll and prints Markdown tables. Run it again
after any tuning change to get fresh tables:

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
- **Heroes.** Sandbox heroes owning Fire, no traits, no subclass, element and weapon mastery equal to the level
  (capped at 10). Free attribute points are left unspent unless a column says "VIT", where every point goes into
  Vitality (the most HP a hero can have). "Typical gear" is six uncommon +0 pieces with no affixes.
- **The intended level.** A hero clears each tier once, in order, killing everything (summons included). The level
  on each floor comes from the real XP table. That is the slowest path; a player who repeats tiers is higher.
- **Fight maths** uses the seven playable classes at that level, in typical gear of the floor's own loot level, so
  defence from gear (damage taken goes down as item level goes up) is counted.
- Three numbers live inside function bodies with no constant to read. The report names them and says where they come
  from: touch cooldown 0.9 s (`Enemy._physics_process`), clear bonus 150 x tier (`Dungeon._finish_run`), the roll's
  ease-out average 67.5% (`Player._physics_process`).

## Headline findings

1. **Only the very first floor is forgiving.** On T1 F1 a normal hit takes 6.4-8.9% of max HP, inside the 5-8%
   target. From T1 F3 on it is 9-19% for the rest of the game, two to three times the target. Today's damage would
   need roughly **x0.4** to land mid-target for normal monsters (median class, points unspent).
2. **Bosses kill in two or three slams.** A boss slam takes 26-42% (T1), 38-68% (T2: the Tide Titan kills the
   frailest classes in 2), 23-43% (T3), 25-47% (T4) and 29-50% (T5). Target 15-25%: factor **x0.30-0.50**.
3. **There is one hidden global multiplier.** `Monsters.HARDNESS = 1.35` multiplies every monster hit on top of the
   oath, so Knight hits at x1.35 and even Squire hits at x1.08.
4. **Healing is scarce and mostly luck.** Between fights the only heals are a forge room (on about half the floors,
   50% of max HP) and level-ups (20%). Spread over the fights, that is 10-35% of max HP per fight, which covers
   **0.6-4 normal hits per fight**, in rooms of 14-18 monsters. Natural regen needs 22-183 s per 10% of max HP and
   pauses for 6 s after every hit. No potions or healing drops exist. Healing skills exist only for Water and Light.
5. **Touch damage, the most common attack, has no warning at all.** Every melee monster hurts on contact, every
   0.9 s. "Every attack telegraphed" is false for the bulk of the damage taken.
6. **Dash wind-ups shrink below reaction time.** Wind-ups lose 10% per depth level down to a 0.2 s floor (reached by
   depth 5-7), while the lunge gains 12% speed per level: at depth 62 an Imp, Dire Wolf or Bone Duelist lunges
   395-437 px at up to 1747 px/s, longer than most rooms are wide (20-28 tiles, 320-448 px).
7. **"Elite" monsters are the majority.** The elemental variant chance is 15% per depth, capped at 60%, so from
   depth 4 on 56-65% of all monsters are variants (+25% HP, +20% touch damage). They are not a rare threat.
8. **The level cap arrives before the last dungeon.** `MAX_LEVEL = 30`. A Knight enters T5 at level 28 and is 30 by
   floor 10; a Warlord is 30 when T5 starts. Monsters keep scaling (damage x6.9 to x8.7 through T5) while the hero
   stops. Level 40 cannot be reached at all.
9. **Most classes gain no HP from levels.** Only Mystic and Berserker grow Vitality per level. The others keep their
   starting HP (84-124) for life unless the player spends free points on Vitality; gear adds about 20 HP at item
   level 1 and about 260 at item level 90.
10. **Death is permadeath for most new heroes within two deaths.** 8% of heroes are born with no element and die for
    good on their first death; 75% are born with one and die for good on their second.

Suspected bugs and oddities are listed in "Outliers" below: summoned minions do not scale with depth, drop gold
ignores the oath's reward, variant shots skip the variant damage bonus.

## 1. Monsters

### The dials

| Dial | Value |
|---|---|
| `Monsters.HARDNESS` (all monster damage) | 1.35 |
| Variant HP / damage (touch only) / XP | x1.25 / x1.20 / x1.50 |
| Variant chance | 15% per depth, cap 60% |
| Boss enrage | below 30% HP: cooldowns x0.65, speed x1.25 (final bosses only) |
| Slam stun | 0.5 s, then 1.5 s of stun immunity |

| Oath | Hardness (HP and damage) | Reward (XP, clear bonus, drop luck) | Damage with HARDNESS |
|---|---|---|---|
| Squire | 0.8 | 0.8 | x1.08 |
| Knight | 1.0 | 1.0 | x1.35 |
| Warlord | 1.3 | 1.6 | x1.755 |

`Monsters.floor_scale` climbs steeply for ten floors, then gently: HP +35% a floor and damage +20% a floor up to
depth 10, then +14% and +7%. HP x11.4 and damage x6.4 at depth 62 (x8.7 with HARDNESS).

### Per floor, by oath (Squire / Knight / Warlord)

Both HP and damage scale linearly with the oath, so 0.8 / 1.0 / 1.3 apply to every number here.

| Where | Normal hit | Heaviest normal hit | Avg normal HP | Guardian slam (max) | Boss slam | Boss HP |
|---|---|---|---|---|---|---|
| T1 F1 (d1) | 7.3 / 9.2 / 11.9 | 8.6 / 10.8 / 14.0 | 25 / 31 / 41 | 23.8 / 29.7 / 38.6 | - | - |
| T1 F3 (d3) | 13.8 / 17.2 / 22.4 | 27.2 / 34.0 / 44.2 | 68 / 85 / 110 | 33.3 / 41.6 / 54.1 | - | - |
| T1 F5 (d5) | 19.4 / 24.3 / 31.6 | 35.0 / 43.7 / 56.9 | 108 / 135 / 175 | 42.8 / 53.5 / 69.5 | 54.4 / 68.0 / 88.5 | 1306 / 1632 / 2122 |
| T2 F1 (d6) | 21.6 / 27.0 / 35.1 | 38.9 / 48.6 / 63.2 | 123 / 154 / 201 | 47.5 / 59.4 / 77.2 | - | - |
| T2 F5 (d10) | 30.2 / 37.8 / 49.1 | 54.4 / 68.0 / 88.5 | 186 / 233 / 303 | 66.5 / 83.2 / 108.1 | - | - |
| T2 F10 (d15) | 33.9 / 42.3 / 55.0 | 61.2 / 76.5 / 99.5 | 210 / 262 / 341 | 74.8 / 93.6 / 121.6 | 129.3 / 161.6 / 210.1 | 4268 / 5335 / 6935 |
| T3 F1 (d16) | 34.6 / 43.3 / 56.2 | 62.6 / 78.2 / 101.7 | 216 / 270 / 351 | 76.5 / 95.6 / 124.3 | - | - |
| T3 F6 (d21) | 39.4 / 49.2 / 64.0 | 69.4 / 86.8 / 112.8 | 244 / 305 / 397 | 84.8 / 106.0 / 137.8 | - | - |
| T3 F12 (d27) | 44.0 / 55.0 / 71.5 | 77.6 / 97.0 / 126.0 | 280 / 351 / 456 | 94.8 / 118.5 / 154.1 | 112.0 / 140.0 / 182.1 | 6530 / 8163 / 10611 |
| T4 F1 (d28) | 44.8 / 56.0 / 72.8 | 78.9 / 98.7 / 128.3 | 286 / 358 / 465 | 96.5 / 120.6 / 156.8 | - | - |
| T4 F8 (d35) | 57.3 / 71.7 / 93.2 | 88.5 / 110.6 / 143.7 | 419 / 524 / 681 | 108.1 / 135.1 / 175.7 | - | - |
| T4 F15 (d42) | 63.5 / 79.4 / 103.2 | 98.0 / 122.5 / 159.2 | 473 / 591 / 768 | 119.8 / 149.7 / 194.6 | 174.2 / 217.7 / 283.0 | 11737 / 14671 / 19072 |
| T5 F1 (d43) | 69.9 / 87.4 / 113.6 | 99.3 / 124.2 / 161.4 | 559 / 699 / 908 | 121.4 / 151.8 / 197.3 | - | - |
| T5 F10 (d52) | 78.5 / 98.2 / 127.6 | 111.6 / 139.5 / 181.3 | 639 / 799 / 1039 | 136.4 / 170.5 / 221.6 | - | - |
| T5 F20 (d62) | 88.1 / 110.1 / 143.2 | 125.2 / 156.5 / 203.4 | 728 / 911 / 1184 | 153.0 / 191.3 / 248.6 | 264.3 / 330.4 / 429.5 | 21031 / 26289 / 34176 |

Where two bosses share a tier (T1: Slime King or Stone Colossus, T2: Crypt Lich or Tide Titan) the harder one is
shown. Guardians (mini bosses) are not tied to a tier: any of the three can guard any third floor, scaled by depth.

### A sample of single monsters, Knight

The report prints every monster on every sampled floor (section 1b). A few that show the shape:

| Where | Monster | HP | Touch | Shot (dmg @ cooldown, flight) | Dash (hit @ cooldown, wind-up) | Slam (dmg @ cooldown, telegraph, radius) | Speed | Dodge | XP |
|---|---|---|---|---|---|---|---|---|---|
| T1 F1 (d1) | Slime | 40 | 10.8 | - | - | - | 30 | - | 12 |
| T1 F1 (d1) | Skeleton Archer | 32 | - | 9.5 @2.2s, 0.84s | - | - | 28 | - | 16 |
| T1 F3 (d3) | Stone Brute | 221 | 30.2 | - | - | - | 18 | - | 34 |
| T1 F3 (d3) | Imp | 48 | 17.0 | - | 27.2 @2.4s, 0.32s | - | 43 | - | 20 |
| T1 F5 (d5) | Bone Duelist | 168 | 29.2 | 12.1 @3.0s, 1.11s | 43.7 @1.9s, 0.27s | - | 42 | 62% | 40 |
| T1 F5 (d5) | Stone Colossus | 1632 | 43.7 | - | - | 68.0 @5.0s, 0.90s, r48 | 21 | - | 260 |
| T2 F10 (d15) | Tide Titan | 5335 | 85.1 | 42.5 @1.8s, 1.25s | 136.1 @1.2s, 0.20s | 161.6 @5.0s, 1.00s, r60 | 27 | - | 460 |
| T4 F15 (d42) | Magma Slug | 1295 | 122.5 | - | - | - | 37 | - | 38 |
| T4 F15 (d42) | Cinder Tyrant | 14671 | 149.7 | 81.6 @1.6s, 1.16s | 254.5 @1.2s, 0.20s | 217.7 @3.8s, 0.90s, r52 | 63 | - | 720 |
| T5 F20 (d62) | Dire Wolf | 549 | 86.9 | - | 130.4 @1.2s, 0.20s | - | 179 | - | 26 |
| T5 F20 (d62) | Gloom Shade | 457 | - | 95.6 @1.6s, 1.00s | - | - | 131 | 70% | 36 |
| T5 F20 (d62) | Gloaming Sovereign | 26289 | 208.7 | 121.7 @1.3s, 1.40s | 375.6 @1.2s, 0.20s | 330.4 @3.5s, 0.90s, r56 | 96 | - | 1000 |

### Monsters per room (24 seeded layouts per tier)

| Where | Monsters/room | Range | Waves | Variants | Room HP total (Knight) |
|---|---|---|---|---|---|
| T1 F1 (d1) | 5.1 | 3-8 | 1.4 | 16% | 166 |
| T1 F3 (d3) | 11.8 | 10-14 | 2.0 | 43% | 1105 |
| T1 F5 (d5) | 16.0 | 14-18 | 2.0 | 59% | 2473 |
| T2 F1 (d6) | 5.5 | 3-8 | 1.5 | 57% | 973 |
| T2 F5 (d10) | 16.2 | 14-18 | 2.0 | 58% | 4323 |
| T3 F6 (d21) | 16.0 | 14-18 | 2.0 | 56% | 5587 |
| T4 F8 (d35) | 15.7 | 14-18 | 2.0 | 62% | 9503 |
| T5 F20 (d62) | 16.5 | 14-18 | 2.0 | 64% | 17472 |

Room size follows the tier's own floor number (`DungeonGen._make_room`): every tier restarts at 3-8 monsters on its
first floor and is back to 14-18 by its fifth.

## 2. Heroes

### Max HP and damage, typical gear (HP with every free point in Vitality in brackets)

Points unspent / all in VIT. Fireball and slash DPS are sustained (mana or stamina limited) and include expected
crits and the burn.

| Class | L1 HP | L10 HP | L20 HP | L30 HP | HP/s at L30 | Fireball DPS L1 / L10 / L30 | Slash DPS L1 / L10 / L30 |
|---|---|---|---|---|---|---|---|
| Novice | 118 | 155 (299) | 181 (485) | 207 (671) | 0.25 | 13 / 18 / 18 | 10 / 19 / 27 |
| Channeler | 110 | 147 (291) | 173 (477) | 199 (663) | 0.22 | 27 / 70 / 163 | 7 / 11 / 14 |
| Vanguard | 138 | 175 (319) | 201 (505) | 227 (691) | 0.28 | 10 / 14 / 15 | 12 / 34 / 84 |
| Ranger | 110 | 147 (291) | 173 (477) | 199 (663) | 0.22 | 11 / 15 / 15 | 11 / 22 / 39 |
| Mystic | 134 | 243 (387) | 349 (653) | 455 (919) | 1.18 | 18 / 25 / 26 | 7 / 11 / 13 |
| Assassin | 102 | 139 (283) | 165 (469) | 191 (655) | 0.19 | 10 / 13 / 14 | 11 / 24 / 45 |
| Berserker | 134 | 243 (387) | 349 (653) | 455 (919) | 1.18 | 9 / 12 / 12 | 13 / 25 / 38 |
| Sage | 102 | 139 (283) | 165 (469) | 191 (655) | 0.19 | 31 / 69 / 156 | 6 / 10 / 12 |
| Druid | 142 | 179 (323) | 205 (509) | 231 (695) | 0.56 | 17 / 39 / 78 | 7 / 11 / 13 |

With starter gear only (the worn weapon) HP never moves for five classes: Channeler and Ranger 92, Vanguard 120,
Assassin and Sage 84, Druid 124, at every level. Mana 70-435, stamina 94-292 at level 30 (Ranger and Assassin grow
Agility). Every class has 3 dodges in a full bar at level 1; only Ranger and Assassin get more (up to 9 at level 30).

The two big casters (Channeler, Sage) reach 156-163 fireball DPS at level 30: twice the best sustained slash
(Vanguard, 84) and 6-13x the other classes' fireballs, because Intellect grows per level and mana regen keeps up. Fighters' sustained slash is limited by stamina: regen stops for 0.8 s after
each swing, so continuous slashing never regenerates.

Level 40 was asked for but cannot be reached: `CharacterData.MAX_LEVEL = 30`. The report still prints what the growth
would give at 40 (marked `40*`).

### XP and the level after each tier

`CharacterData.xp_to_next(lv) = 30 x lv^1.4`: 30 XP for level 2, 753 for level 11, 3345 for level 30; 42,097 in all.
XP per kill does not grow with depth (a Slime is 12 XP at depth 1 and at depth 62).

| Tier | Kills in a clear | XP of a clear (Sq / Kn / Wl) | Level in -> out (Sq / Kn / Wl) |
|---|---|---|---|
| T1 The Ashen Vaults | 91 | 2164 / 2700 / 4321 | 1 -> 9 / 1 -> 9 / 1 -> 11 |
| T2 The Drowned Crypts | 232 | 6951 / 8684 / 13899 | 9 -> 16 / 9 -> 17 / 11 -> 21 |
| T3 The Thornroot Hollow | 294 | 8998 / 11243 / 17993 | 16 -> 21 / 17 -> 23 / 21 -> 28 |
| T4 The Cinder Forge | 378 | 12776 / 15970 / 25551 | 21 -> 26 / 23 -> 28 / 28 -> 30 |
| T5 The Gloaming Spire | 518 | 18938 / 23660 / 37851 | 26 -> 30 / 28 -> 30 / 30 -> 30 |

## 3. Fight maths

Knight, first-clear level, the seven classes in typical gear of the floor's loot level. Each cell: the share of max
HP one hit takes, lowest to highest across the classes, and in brackets the hits that kill the frailest class.

### What one hit costs, today and with the most HP possible

| Where | Lvl | Max HP | Normal | Heaviest normal | Elite (variant) | Guardian slam | Boss slam | Factor to target normal / elite / boss | Normal, all VIT | Boss or guardian, all VIT |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 F1 (d1) | 1 | 102-142 | 6.4-8.9% (12) | 7.6-10.5% (10) | 9.1-12.7% (8) | 20.9-29.0% (4) | - | x0.78 / x1.06 / x0.74 | 6.4-8.9% | 20.9-29.0% |
| T1 F3 (d3) | 4 | 129-185 | 8.5-12.3% (9) | 16.9-24.2% (5) | 18.0-25.8% (4) | 20.7-29.6% (4) | - | x0.56 / x0.51 / x0.72 | 6.8-8.9% | 16.4-21.6% |
| T1 F5 (d5) | 8 | 145-233 | 9.3-15.0% (7) | 16.8-27.0% (4) | 17.9-28.8% (4) | 20.5-33.0% (4) | 26.1-42.0% (3) | x0.46 / x0.46 / x0.50 | 6.3-8.4% | 17.6-23.7% |
| T2 F1 (d6) | 9 | 150-246 | 9.7-15.9% (7) | 17.5-28.7% (4) | 18.6-30.6% (4) | 21.3-35.0% (3) | - | x0.43 / x0.43 / x0.60 | 6.4-8.6% | 14.0-18.9% |
| T2 F5 (d10) | 12 | 168-288 | 11.2-19.2% (6) | 20.1-34.5% (3) | 21.5-36.8% (3) | 24.6-42.2% (3) | - | x0.36 / x0.36 / x0.50 | 6.9-9.4% | 15.3-20.6% |
| T2 F10 (d15) | 16 | 191-343 | 10.0-17.9% (6) | 18.1-32.4% (4) | 19.3-34.6% (3) | 22.1-39.7% (3) | 38.1-68.5% (2) | x0.38 / x0.38 / x0.30 | 5.9-7.9% | 22.4-30.3% |
| T3 F1 (d16) | 17 | 196-356 | 9.7-17.7% (6) | 17.6-31.9% (4) | 18.8-34.1% (3) | 21.5-39.0% (3) | - | x0.38 / x0.38 / x0.53 | 5.7-7.7% | 12.5-16.9% |
| T3 F6 (d21) | 19 | 214-390 | 9.7-17.6% (6) | 17.1-31.1% (4) | 18.2-33.2% (4) | 20.9-38.0% (3) | - | x0.38 / x0.39 / x0.55 | 5.6-7.5% | 12.0-16.2% |
| T3 F12 (d27) | 22 | 237-437 | 9.1-16.8% (6) | 16.1-29.7% (4) | 17.2-31.7% (4) | 19.7-36.3% (3) | 23.3-42.9% (3) | x0.40 / x0.41 / x0.48 | 5.2-7.0% | 13.2-17.7% |
| T4 F1 (d28) | 23 | 242-450 | 8.9-16.6% (7) | 15.7-29.2% (4) | 16.8-31.1% (4) | 19.2-35.7% (3) | - | x0.41 / x0.41 / x0.58 | 5.0-6.8% | 10.8-14.5% |
| T4 F8 (d35) | 25 | 266-490 | 9.9-18.2% (6) | 15.3-28.1% (4) | 18.3-33.8% (3) | 18.6-34.4% (3) | - | x0.37 / x0.38 / x0.60 | 5.5-7.5% | 10.5-14.1% |
| T4 F15 (d42) | 28 | 291-539 | 9.3-17.2% (6) | 14.3-26.5% (4) | 17.2-31.8% (4) | 17.5-32.4% (4) | 25.4-47.1% (3) | x0.39 / x0.40 / x0.44 | 5.1-6.9% | 14.1-19.0% |
| T5 F1 (d43) | 28 | 294-542 | 10.1-18.6% (6) | 14.3-26.4% (4) | 17.2-31.7% (4) | 17.5-32.3% (4) | - | x0.36 / x0.41 / x0.64 | 5.6-7.5% | 9.7-13.1% |
| T5 F10 (d52) | 30 | 322-586 | 9.6-17.5% (6) | 13.7-24.9% (5) | 16.4-29.8% (4) | 16.7-30.4% (4) | - | x0.38 / x0.43 / x0.67 | 5.4-7.2% | 9.3-12.5% |
| T5 F20 (d62) | 30 | 348-612 | 9.5-16.7% (6) | 13.5-23.8% (5) | 16.2-28.5% (4) | 16.5-29.0% (4) | 28.5-50.2% (2) | x0.40 / x0.45 / x0.41 | 5.4-7.2% | 16.2-21.5% |

Reading it:

- **Today vs forgiving, per band.** Normal monsters take 9-19% a hit everywhere past T1 F1 (target 5-8%). Elites
  take 16-37% (target 10-15%). Guardians take 17-42% and final bosses 23-68% (target 15-25%). The factor column is
  the multiplier on today's damage that puts the median class mid-target: about **x0.4 for normal and elite hits,
  x0.3-0.5 for bosses**, fairly flat across the tiers. One global damage cut of about 0.4 would do most of it; the
  T1 F1 numbers show the curve starts in the right place and climbs too fast over the first three floors.
- **The all-Vitality build is already forgiving for normal hits** (5-9%) and close for bosses (10-30%), but it costs
  every point of offence. A real hero sits between the two columns.
- **The spread between classes is about 2x.** Assassin and Sage are the frailest; Mystic and Berserker (Vitality
  per level) the sturdiest. The frailest class dies to 6 normal hits or 2-3 boss slams for most of the game.

### Time to kill and the room's pressure

Hero DPS: Channeler fireball / Vanguard slash, sustained. Room DPS is every monster attacking whenever it can and
nobody dodging, an upper bound; "stand still" is how long a hero who never dodges survives it.

| Where | Hero DPS | Normal HP | TTK normal (s) | Boss HP | TTK boss (s) | Room HP | Room clear (s) | Room DPS | Stand still (s) |
|---|---|---|---|---|---|---|---|---|---|
| T1 F1 (d1) | 27 / 12 | 31 | 1.2 / 2.6 | - | - | 166 | 6 / 13 | 50 | 2.1-2.9 |
| T1 F5 (d5) | 63 / 31 | 135 | 2.1 / 4.4 | 1632 | 26 / 53 | 2473 | 39 / 81 | 385 | 0.4-0.6 |
| T2 F10 (d15) | 108 / 58 | 262 | 2.4 / 4.5 | 5335 | 50 / 92 | 4733 | 44 / 82 | 658 | 0.3-0.5 |
| T3 F12 (d27) | 153 / 88 | 351 | 2.3 / 4.0 | 8163 | 53 / 92 | 6558 | 43 / 74 | 872 | 0.3-0.5 |
| T4 F15 (d42) | 213 / 132 | 591 | 2.8 / 4.5 | 14671 | 69 / 111 | 10631 | 50 / 81 | 1241 | 0.2-0.4 |
| T5 F20 (d62) | 259 / 172 | 911 | 3.5 / 5.3 | 26289 | 102 / 153 | 17472 | 68 / 102 | 1825 | 0.2-0.3 |

Time to kill stays near 2-5 s per normal monster all game: hero damage and monster HP grow together, which is fine.
The problem is the incoming side. A full room of 16 is 40-100 s of fighting for a single hero, and a boss 26-153 s,
during which the slam lands 5-45 times.

### Healing between rooms

Heal per floor = chance of a forge room x 50% + levels gained on that floor x 20%. Budget = that heal per fight
(two fights a floor). "Hits" = how many median normal hits the budget covers.

| Where | Forge chance | Levels gained | Heal/floor | Budget/fight | Normal hits/fight | Regen 10% (s) |
|---|---|---|---|---|---|---|
| T1 F1 (d1) | 54% | 2 | 67% | 33.5% | 4.0 | 22-37 |
| T1 F5 (d5) | 54% | 1 | 47% | 23.5% | 1.7 | 33-76 |
| T2 F5 (d10) | 46% | 1 | 43% | 21.5% | 1.2 | 37-88 |
| T3 F1 (d16) | 58% | 0 | 29% | 14.6% | 0.9 | 42-103 |
| T4 F15 (d42) | 46% | 0 | 23% | 11.5% | 0.7 | 48-153 |
| T5 F20 (d62) | 42% | 0 | 21% | 10.4% | 0.6 | 52-183 |

Plainly: **between two combat rooms there is no heal at all** unless the floor rolled a forge room (about half do)
or the hero levels up. HP carries from room to room. Every healing source in the game:

| Source | Amount |
|---|---|
| Forge room | 50% of max HP, all stamina and mana; on about half the floors |
| Camp | everything (between runs only) |
| Level-up | 20% of max HP; rare after T2 (0-1 levels a floor) |
| Natural regen | 0.19-1.18 HP/s, paused 6 s after any hit (Novice: 15% of max HP a minute) |
| Tidal Mending (Water support, level 7) | 48 HP over 6 s, every 18 s |
| Benediction (Light support, level 7) | 60 HP over 6 s, every 18 s |
| Shadow Bolt (Dark) | 25% lifesteal |
| Bloodrage (Berserker) / Vampiric / Survivor traits | 3 / 2 / 1 HP per kill |
| Lucky Charm amulet | 1 HP per kill at item level 1, 6.6 at item level 60 |
| Potions, healing drops, heal on room clear | none exist |

Mend skills heal a flat 48-60 HP: 25-45% of max HP at level 7, when they are learned, and 10-30% at level 30.

### Warning time versus the dodge

The dodge: 0.30 s of i-frames, a roll of about 32 px, 30 stamina (3 dodges from a 94-100 bar for most classes),
0.40 s cooldown; stamina waits 0.8 s after spending, then regains 17-26 a second (Ranger and Assassin more).

| Attack | d1 | d5 | d15 | d27 | d42 | d62 |
|---|---|---|---|---|---|---|
| Touch (every melee monster) | no warning | no warning | no warning | no warning | no warning | no warning |
| Imp dash: wind-up, lunge | 0.40 s, 48 px | 0.24 s, 70 px | 0.20 s, 127 px | 0.20 s, 196 px | 0.20 s, 281 px | 0.20 s, 395 px |
| Dire Wolf dash | 0.30 s, 53 px | 0.20 s, 78 px | 0.20 s, 141 px | 0.20 s, 216 px | 0.20 s, 311 px | 0.20 s, 437 px |
| Bone Duelist dash | 0.45 s, 50 px | 0.27 s, 74 px | 0.20 s, 134 px | 0.20 s, 206 px | 0.20 s, 296 px | 0.20 s, 416 px |
| Fastest shot: flight time | 0.84 s | 0.84 s | 0.84 s | 0.88 s | 0.88 s | 1.00 s |
| Slime King slam: telegraph, walk out | 0.80 s, 0.50 s | same | same | same | same | same |
| Gloaming Sovereign slam | 0.90 s, 0.70 s | same | same | same | same | same |
| Bog Hulk (guardian) slam | 0.90 s, 0.55 s | same | same | same | same | same |

"Walk out" is the slam radius divided by Novice speed from the very centre, an upper bound.

- **Slams are fair.** 0.8-1.0 s of telegraph against 0.5-0.7 s to walk out, and a well-timed dodge covers it too.
- **Shots are fair.** 0.84-1.0 s of flight; a side step of about 11 px takes 0.14 s.
- **Dashes become unfair.** A 0.2 s wind-up is under a typical 0.25 s human reaction; the 0.3 s of i-frames can only
  cover the lunge if the dodge is pressed during that wind-up. From depth 15 the lunge also outranges any roll.
- **Touch is not telegraphed at all**, and it is most of the damage: in the T5 band, 67% of the spawn weight
  touches (Bone Duelist, Dire Wolf, Magma Slug, Stone Brute).
- **Stamina caps how much can be avoided.** Three dodges, then 2.0-2.6 s per further dodge, against a room of 16
  attacking several times a second. Forgiving play needs most damage to be avoidable by walking, not by rolling.

### Speed

Monsters gain 4% speed per depth level (`Enemy.configure`). The Dire Wolf walks faster than the slowest class from
depth 27 (106 vs 99 px/s); at depth 62 Bone Duelists, Dire Wolves (179 px/s) and Gloom Shades all outpace the slowest
hero. For a Novice-speed hero (80 px/s) the wolf overtakes at depth 15 and the Cave Bat at depth 11. Ranger and
Assassin escape this through Agility growth (up to 229 px/s with gear).

## 4. Economy

### Income of one first clear, Knight

| Tier | Gold: kills | Chests | Guardians | Boss | Clear bonus | Gold total | Scrap | Gel | Essence | Gear pieces | Salvage all gear |
|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 645 | 98 | 85 | 181 | 150 | 1159 | 59 | 32 | 47 | 16.0 | 356 g + 47 scrap |
| T2 | 3912 | 392 | 537 | 367 | 300 | 5508 | 135 | 81 | 121 | 34.4 | 2176 g + 115 scrap |
| T3 | 8566 | 639 | 807 | 506 | 450 | 10967 | 160 | 98 | 151 | 41.8 | 4438 g + 143 scrap |
| T4 | 15957 | 1107 | 1479 | 554 | 600 | 19697 | 206 | 132 | 199 | 53.2 | 8610 g + 188 scrap |
| T5 | 28737 | 1933 | 3001 | 1062 | 750 | 35482 | 285 | 176 | 271 | 72.3 | 14907 g + 245 scrap |

Gold of one clear by oath: T1 1093 / 1159 / 1335, T5 34,621 / 35,482 / 35,819 (Squire / Knight / Warlord). Only the
clear bonus and drop luck follow the reward; the Warlord's "60% richer spoils" is about 2% more gold.

### Costs

| | Gold | Scrap | Other |
|---|---|---|---|
| Craft a piece | 15-40 | 4-10 | 0-3 gel |
| Upgrade +0 to +5 (common / uncommon / rare / epic / legendary) | 300 / 390 / 510 / 660 / 900 | 20 | |
| Upgrade +0 to +10 | 1100 / 1430 / 1870 / 2420 / 3300 | 65 | |
| Enchant (by rarity) | 40-120 | | 1 essence + 1 per 8 item levels |
| Six uncommon pieces to +5 / to +10 | 2340 / 8580 | 120 / 390 | |

Clears needed for a +10 uncommon kit, salvaging every drop (gold / scrap): T1 5.7 / 3.7, T2 1.1 / 1.6,
T3 0.6 / 1.3, T4 0.3 / 1.0, T5 0.2 / 0.7.

- **Gold inflates, costs do not.** Kill gold is 2-6 plus the item level, so a T5 clear pays about 30x a T1 clear
  while every forge price is flat. From T2 on gold stops being a constraint; scrap (and the bag) is the real limit.
- **Essence is plentiful**: 47 a T1 clear against enchants that need 1-8.

### What a death costs today

The committed rule (git HEAD): a fall in the dungeon costs `Game.DEATH_GOLD_LOSS` = 30% of carried gold; the Nth
death costs N elements chosen at random; a hero with no element left dies for good and the save is deleted.

| Hero has cleared | Gold carried (nothing spent) | Lost on a fall |
|---|---|---|
| T1 | 1159 | 347 |
| T2 | 6667 | 2000 |
| T3 | 17635 | 5290 |
| T4 | 37332 | 11199 |
| T5 | 72814 | 21844 |

| Born with | Share of new heroes (20,000 ceremony rolls) | Permadeath at (N per death, HEAD) | Permadeath at (1 per death) |
|---|---|---|---|
| 0 elements | 8.2% | death 1 | death 1 |
| 1 element | 75.2% | death 2 | death 2 |
| 2 elements | 13.6% | death 3 | death 3 |
| 3 elements | 2.5% | death 3 | death 4 |
| 4 elements | 0.5% | death 4 | death 5 |
| 5 elements | 0.1% | death 4 | death 6 |

The working tree already has the one-element-per-death rule (another change in progress), which is what the report's
live `die()` run shows. For 97% of heroes (0-2 elements) the two rules end the hero on the same death. The planned
change (one element per death and loss of the run's loot) makes deaths gentler but leaves the main problem: a
typical hero is still at most two deaths from permadeath. Gold loss is large in absolute terms but buys little
after T2 (see inflation above), so it hurts less than it looks.

## 5. Outliers and suspected bugs

1. **Summoned minions ignore depth and oath.** `Enemy._spawn_minions` calls `Monsters.spawn` with the default scale
   (1, 1) and level 1. The Gloaming Sovereign's shades have 40 HP and a 14.9 hit; a shade native to that floor has
   457 HP and a 95.6 hit. The Cinder Tyrant's slugs: 150 HP vs 1295. Harmless today (it is an accidental mercy) but
   it looks unintended, and it makes boss summons free XP at depth.
2. **Dash scaling runs away.** Wind-up -10% a level to a 0.2 s floor, lunge speed +12% a level with no cap,
   cooldown -12% a level to 1.2 s. At depth 62 the lunge is 1581-1747 px/s over 395-437 px.
3. **Dodging monsters reach the 70% cap by depth 6.** Wraith, Bone Duelist and Gloom Shade sidestep 70% of hits
   (cooldown 0.8 s). Against a hero landing 1.35 hits a second that voids about 40% of the hits: x1.66 effective HP.
4. **Speed +4% per depth level** makes several monsters faster than slow heroes (see Speed).
5. **The level cap (30) is reached in T5** while monsters keep scaling; Warlord heroes are capped for all of T5.
6. **Variant damage skips shots.** `VARIANT_DAMAGE` only multiplies touch damage: a Fire Spitter at depth 10 touches
   for 31.8 (Spitter 26.5) but shoots for the same 22.7.
7. **XP per kill is flat with depth** while the XP curve rises as level^1.4, so later tiers level slowly by design or
   by accident (T5 gives 2 levels on Knight).
8. **Drop gold ignores the oath's reward** although the Warlord description promises 60% richer spoils.
9. **Gear defence scales with item level without a cap below 0.4.** Typical uncommon gear gives damage taken x0.90
   at item level 10, x0.81 at 30, x0.67 at 60 and x0.58 at 80 (Iron Helm + Chain Mail). With affixes and the Mineral
   enchant it can reach the 0.4 floor. That quietly offsets monster scaling late and is already counted above.
10. **Variants are the majority** from depth 4 (56-65%).
11. **Most classes have flat HP for life** unless free points go to Vitality; only Mystic and Berserker grow.
12. **Mend skills heal a flat amount** (48 / 60 HP) that does not scale with max HP.
13. **Room size resets every tier** (3-8 on floor 1, 14-18 by floor 5), so each tier's first floor is a breather.

## 6. Suggested tuning levers (toward forgiving)

Ordered by impact. "Now" is today's value; the direction is what forgiving asks for.

| # | File | Now | Direction |
|---|---|---|---|
| 1 | `scripts/combat/monsters.gd` `HARDNESS` | 1.35 | Down to about 0.5-0.6. On its own this lands normal hits mid-target on most floors (factor x0.36-0.46 on today's 1.35). The single biggest lever. |
| 2 | `scripts/combat/monsters.gd` `floor_scale` damage slope | +0.2 a floor to depth 10, +0.07 after | Flatter early (e.g. +0.1 then +0.05) so floors 2-5 do not triple the damage before the hero has grown. HP slope (+0.35 / +0.14) can stay: kill times are fine. |
| 3 | `scripts/combat/monsters.gd` boss and guardian `slam.damage` (22-38) | 2-3 slams kill | About 60-70% of today after lever 1, so a slam is 15-25%. |
| 4 | `scripts/combat/enemy.gd` touch damage | no warning, every 0.9 s (literal in `_physics_process`) | Give the bite a short wind-up (the "bite" pose exists), or slow it (1.2-1.5 s), or cut touch damage relative to telegraphed attacks. Needed for "every attack telegraphed". |
| 5 | `scripts/combat/enemy.gd` `configure` sharpening | dash wind-up -10%/level (floor 0.2 s), dash speed +12%/level, dodge +8%/level (cap 0.7), speed +4%/level | Keep wind-ups fixed (or floor 0.4 s), cap dash speed (about 300 px/s), dodge +2%/level cap 0.45, walk speed +1%/level or cap below hero speed. |
| 6 | `scripts/world/dungeon.gd` `FORGE_HEAL` | 0.5, on about half the floors | 1.0, and/or a guaranteed rest on every floor (`DungeonGen._make_floor` picks treasure or forge 50/50). |
| 7 | New: heal on room clear (`dungeon.gd _clear_room`) | none | 15-25% of max HP when a room is cleared: the clearest "way to heal between rooms". |
| 8 | `scripts/character/classes.gd` `HP_REGEN_BASE` / `HP_REGEN_PER_VIT`; `scripts/player/player.gd` `hp_regen_delay` | 0.1 + 0.03 per VIT HP/s; 6 s pause | Faster out-of-combat regen (e.g. 1% of max HP a second) and a 2-3 s pause. |
| 9 | `scripts/character/character_data.gd` `LEVEL_UP_HEAL_FRACTION` | 0.2 | 1.0 (a full heal on level-up). |
| 10 | `scripts/character/character_data.gd` `derived()` max HP | 60 + 8 per VIT, no growth per level | Base HP per level for every class (e.g. +6), so HP is not a pure stat-point tax. |
| 11 | `scripts/world/dungeon_gen.gd` wave size | 1-2 waves of 3-4 on floor 1, 2 waves of 7-9 from floor 5 | Fewer per room from floor 3 (e.g. cap at 10-12), or more, smaller waves. |
| 12 | `scripts/combat/monsters.gd` `VARIANT_CHANCE_PER_FLOOR` / `VARIANT_CHANCE_MAX` | 0.15 / 0.6 | 0.03 / 0.25, so elites stay special. |
| 13 | `scripts/combat/enemy.gd` `SLAM_STUN`, enrage cooldown x0.65 | 0.5 s; x0.65 | 0 (no stun after a slam); x0.8. |
| 14 | `scripts/player/player.gd` `dodge_iframes`, `dodge_stamina_cost` | 0.3 s, 30 | 0.35-0.4 s, 20-25 (four or five dodges a bar). |
| 15 | `scripts/character/character_data.gd` `MAX_LEVEL` | 30 | 35-40, or flatten `floor_scale` past depth 42 so T5 is not fought at the cap. |
| 16 | `scripts/core/game.gd` `DEATH_GOLD_LOSS` | 0.3 | 0.1-0.15, or a cap; gold inflates so the absolute loss is large. |
| 17 | `scripts/core/game.gd` `DIFFICULTIES` | hardness 0.8 / 1.0 / 1.3 scales HP and damage together (`Dungeon._monster_scale`) | Consider separate HP and damage multipliers so Squire can be soft without being quick. |
| 18 | `scripts/combat/enemy.gd` `_spawn_minions` | summons at depth 1 | Decide on purpose: pass the boss's scale, or keep them weak and say so. |
| 19 | `scripts/core/skill_db.gd` `tidal_mending` / `benediction` | flat 8 / 10 HP a second | A share of max HP, so mends keep up with deeper heroes. |

A first pass that only touches levers 1, 3, 4, 6 and 7 would already meet the forgiving targets for normal monsters
and bosses on every tier and give a heal between every two rooms. Run the report after each change: the "Factor"
column should drift toward x1.0.

## What could not be measured

- How often a real player gets hit. The report gives the cost of a hit and the time to avoid it, not hit rates:
  aim, positioning, AI pathing, collisions and how many monsters reach the hero at once need play testing.
- Combos, splash, pierce, fusion and the martial Rend are left out of hero DPS (they raise it). Crits are counted as
  their expected value.
- Free points, traits, subclasses and gear affixes vary per hero. The report shows the two extremes for points
  (unspent and all in Vitality) and leaves out traits, subclasses and affixes.
- The committed death rule (N elements on the Nth death) could not be run: the working tree already has the
  one-per-death rule from another change. It is described from the code instead.
- Whether every boss summon stage fires (a boss killed in one burst skips some); the report assumes all do.
