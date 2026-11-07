# Elementalist (Godot 4.7 GDScript game in `elementalist/`)

General rules (plan gate, git, vault) are in `~/.claude/CLAUDE.md`. Project rules live in the vault at `Projects/Elementalist/Rules.md`; read it first.

## Build
- Godot exe `C:\App\Godot_v4.7.2-stable_win64.exe`, command line only. The user's editor stays open and untouched. No godot-ai MCP.
- Data-driven tables first, rules in `RefCounted` classes, UI built in code. Never `scene_save`. `.gd` indentation is tabs.
- New `.gd` needs a `.gd.uid`; new `.wav`/`.png` need `.import` (`godot --headless --path elementalist --import`).
- After editing a `\n` inside a GDScript string, grep that no line ends inside an open string.
- Art and audio come from `tools/art/*.py` and `tools/audio/gen_audio.py` (stdlib only). Never use Python `hash()` for seeds.
- Leave `form.html` alone. Do not change balance numbers unless the task is balance (`docs/BALANCE.md`).

## Verify before calling it done
- `res://tests/combo_selftest.tscn` headless: last line `SELFTEST <n> passed, 0 failed`; `tools/run_net_test.ps1` (host 9/0, client 13/0); no SCRIPT or Parse Error. UI: 320x180 and 420x180 fit sweep.
- Flaky: "a plain slash on a rooted enemy shatters".
- Each phase updates README, docs/GDD, ROADMAP, ARCHITECTURE, CORE_LOOP.

## Art
- Current style: Noir Silhouette, one element-coloured glow (supersedes Moonlit). Details: `docs/ART_DIRECTION.md`, `docs/SPRITE_STYLES.md`.
- Never use pure black or white (`check_art.py` fails it). Regenerate with `python tools/art/build_all.py`.
- Hurtbox stays 16x26 (`Player.HURTBOX_SIZE`) whatever the art size; a new hero size means re-checking card sizes in `class_cards.gd`.

## Tone
- Forgiving difficulty. Death = 1 element + 30% gold + the run's loot; retreat keeps loot (30% gold only).
