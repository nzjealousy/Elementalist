# Building a Windows playtest build

The game exports to a single `Elementalist.exe` (the .pck is embedded). Builds go to `build/` at the repo root,
which git ignores; never commit the binary or the export templates.

## One-time setup: export templates

Export needs the Godot export templates of the exact engine version. `godot --version` reports
`4.7.2.stable.official.ed1daf0bf`, so the templates live in:

    %APPDATA%\Godot\export_templates\4.7.2.stable\

They came from the official release, `Godot_v4.7.2-stable_export_templates.tpz` on
<https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable> (1,281,349,702 bytes). Its SHA512
matched the release's `SHA512-SUMS.txt`:

    ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079

The .tpz is a zip; its `templates/` folder (35 files, `version.txt` says `4.7.2.stable`) is what goes into the
folder above. The editor's Export > Manage Export Templates does the same thing.

## Export

The preset is `elementalist/export_presets.cfg`, "Windows Desktop": x86_64, pck embedded, all resources except
`tests/*`, no icon or version info written into the exe (`application/modify_resources=false`, so no rcedit is
needed; the exe has the default Godot icon). From the repo root:

    mkdir build
    "C:\App\Godot_v4.7.2-stable_win64.exe" --headless --path elementalist --export-release "Windows Desktop" ../build/Elementalist.exe

Always export **release**: the debug keys (F5 sandbox hero and friends in `Dungeon`) check
`OS.is_debug_build()` and stay out of a release build. The output path is relative to `elementalist/`.

The `godot_ai` addon is still packed, because `project.godot` autoloads its `game_helper.gd`; excluding it would
break the start-up.

## Last result (2026-11-07, rebuilt with potions and the shorter melee reach)

* Export: exit code 0; the old exe was deleted first, `build/` holds only the new one.
* `build/Elementalist.exe`: 112,809,408 bytes (about 108 MB), SHA256
  `df83973413260ce026403bee87e1c864c49a2182258dc96bb89123e4a6d08575`.
* Smoke test: started with `--windowed`, still running after 8 s, then killed.
* Not verified: reaching the camp from the title screen, combat, saving from the build. The build shares
  `%APPDATA%\Godot\app_userdata\Elementalist\` (saves, settings, leaderboard) with the editor runs.
