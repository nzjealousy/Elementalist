# Elementalist: the core loop

The loop the game is built around, what is already playable, and what to decide next. Written as a
proposal (you asked for suggestions): the camp-and-dungeon structure below is implemented in Phase 5;
the open questions at the end are the ones worth your call.

## The loop in one line

**Prepare at camp → choose a dungeon → spend resources fighting down → get rewards or pay for failure → return to camp stronger (or with one element fewer).**

```
              ┌────────────────────────── CAMP ──────────────────────────┐
              │  heal, save · forge · merchant (gems, legendaries) · gear   │
              │  hall of heroes (leaderboard) · the gate                 │
              └──────────────┬───────────────────────────▲───────────────┘
                             │ choose a dungeon           │ return (win, fall or retreat)
                             ▼                            │
   ┌─── DUNGEON (5 floors, then 10) ──────────────────────┴───────────┐
   │ combat room → treasure/forge room → combat/mini boss → ... → BOSS │
   │ mana, stamina and health recover slowly: plan, don't trade blows  │
   └───────────────────────────────────────────────────────────────────┘
```

## Three time scales

| Scale | What the player does | What pulls them forward |
|---|---|---|
| **Seconds** (a fight) | Read the monsters, spend mana, stamina and health on the right skill, dodge, chain abilities of different elements for the discount, fuse two elements for a combo | Combos, kills that give back resources, enemies that dash, dodge or shoot |
| **Minutes** (a run) | Move room to room, heal a little with every cleared room and fully at a forge room, decide whether to push to the mini boss | Loot, XP and levels (every second level offers a reward), mastery unlocking passives, chests |
| **Hours** (the hero) | Return to camp, forge and enchant gear, clear the next dungeon, find a Light or Dark gem, pick a class and later a subclass, climb the leaderboard | New elements (gems from bosses), class mastery, deeper dungeons, better difficulty oath |

## What a run costs and pays (forgiving but rewarding)

* **Cost of failing**: you keep your levels and the gear you owned before the run, but lose **one element** (at
  random, its mastery restarts), **30 % of your gold** and **the loot found in the run** (gear, worn or not, and
  materials; scrap is safe). A hero with no element left to lose is gone for good (their save is deleted, the run goes
  on the leaderboard).
* **Cost of playing it safe**: retreating from a dungeon also costs the run and 30 % of the gold (the run's loot
  is kept, never an element is lost), so leaving is never free.
* **Reward for finishing**: the boss drops two gear pieces and (sometimes) an elemental **gem**; the dungeon pays a
  clear bonus; the next dungeon opens. The second dungeon's bosses also carry the rare **Light** and **Dark** gems.
* **Healing between fights**: a cleared combat room or guardian heals 15% of max HP, a forge room and a level-up heal
  fully, and out of combat health returns at about 0.5% of max HP a second (3 s after the last hit). Monsters hit
  softly (a normal hit is about 5-8% of max HP) and every dash winds up for at least 0.4 s, so mistakes are cheap.
* **The oath** (chosen at hero creation): *Squire* (x0.75 monsters, x0.8 spoils), *Knight* (x1/x1), *Warlord*
  (x1.25 monsters, x1.6 spoils: XP, every gold drop, the clear bonus and drop luck). The leaderboard multiplies the score by the same reward factor, so
  the risk is visible and rewarded.

## Why it holds up

1. **Resources are the game.** Slow recovery means every spell is a decision made a few seconds ahead.
2. **Elements are earned, then protected.** Because death takes elements, the thing you want most is also what a mistake costs.
3. **Short sessions, long arc.** A 5-floor dungeon is 15 rooms (about 15 minutes); the 10-floor one doubles it, with a mini boss every third floor as a checkpoint of tension.
4. **Autosave at every room** (and a seed-rebuilt dungeon) means closing the game never loses more than the current room.

## Open questions for you

1. **Gold sink and stash.** Gold is banked on the hero. Should the camp sell something (a shop, rerolling an affix,
   re-attuning a lost element for a big price)? Re-buying a lost element would soften permadeath; leaving it out keeps it harsh.
2. **Meta-progression across heroes.** Today a dead hero leaves only a leaderboard line. Do you want a small
   heritage (a starting bonus, an unlocked class or oath) so the next hero feels the last one mattered?
3. **Between-room choices.** Slay the Spire-style branching (two doors, one forge, one elite) would add planning on top of
   the resource game. The generator is linear for now.
4. **Daily/seeded runs.** Because runs are rebuilt from a seed, a shared "seed of the day" leaderboard is cheap to add.
5. **Hub life (Phase 6).** The camp is a single room; NPCs, dialogue and the ceremony cutscene would live here.

## Phase 6 additions

* The gate now offers **five dungeons** (5, 10, 12, 15 and 20 floors); the camp has a sign to the **training grounds** (altar of elements,
  dummies, a controls checklist) that never touches the save.
* **Together:** from the title screen a hero can join a friend's dungeon (the host picks the dungeon; everyone earns XP, loot and the clear bonus)
  or duel in the arena. A fallen hero in co-op comes back after five seconds with half health; the run is lost only when all fall at once.
* Open question: should co-op scale monsters with the party size (today it does not), and should the arena have rewards (ranked score)?
