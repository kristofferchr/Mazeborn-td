# Instrukser for agenter

Mazeborn TD er et tower defense i Godot 4 (GDScript) for iOS. Se `README.md` og issue #1.

## Kommandoer (fra repo-roten)

- `scripts/test.sh`: headless tester. Kjør dem alltid før commit.
- `gdlint game && gdformat --check game`: lint og format (`pip install "gdtoolkit==4.5.0"`).
- `scripts/screenshot.sh <out.png> [scene] [frames] [WxH]`: render en scene og se på bildet for å verifisere visuelle endringer.
- `scripts/export-web.sh` og `scripts/export-ios.sh`: eksport. Godot lastes ned automatisk til versjonen i `.godot-version`.

## Regler

- Spillogikk ligger i `game/core/` som ren 2D-logikk uten noder, og den testes. 3D-grafikken leser bare tilstand.
- Tester skrives i `game/tests/**/test_*.gd` med metoder `test_*`, og bruker `t.check(cond, msg)` og `t.eq(actual, expected, msg)`.
- Bruk typet GDScript.
- Endres `game/export_presets.cfg` eller `.godot-version`, kjør `scripts/export-ios.sh` og commit `ios/` (CI sjekker at de er i synk).
- Ikke bruk Blizzard-innhold (modeller, lyder, navn eller kart).
