# Instrukser for agenter

Mazeborn TD er et tower defense i Godot 4 (GDScript) for iOS. Se `README.md` og issue #1.

## Kommandoer (fra repo-roten)

- `scripts/test.sh`: headless tester. Kjør dem alltid før commit.
- `gdlint game && gdformat --check game`: lint og format (`pip install "gdtoolkit==4.5.0"`).
- `scripts/screenshot.sh <out.png> [scene] [frames] [WxH]`: render en scene og se på bildet for å verifisere visuelle endringer.
- `scripts/export-web.sh` og `scripts/export-ios.sh`: eksport. Godot lastes ned automatisk til versjonen i `.godot-version`.
- `scripts/asc_builds.py [--wait N]`: status for TestFlight-builds hos Apple (krever `ASC_*`-variablene og `pip install pyjwt cryptography`).

## Arbeidsflyt

1. Jobb på en branch, skriv logikk og tester i `game/core/` og `game/tests/`, og kjør `scripts/test.sh` og lint.
2. Verifiser visuelle endringer selv med `scripts/screenshot.sh` (gjerne i `2532x1170`) og se på bildet før du åpner en PR.
3. Åpne en PR. CI kjører tester og lint og publiserer en spillbar forhåndsvisning på `https://kristofferchr.github.io/Mazeborn-td/pr-preview/pr-N/`, som brukeren tester i Safari på iPhone.
4. TestFlight: start `.github/workflows/ios.yml` (`workflow_dispatch` på `main`, eller tagg `v*`). Følg kjøringen og les loggene via GitHub Actions. Vent deretter med `scripts/asc_builds.py --wait <byggnummer>`, der byggnummeret er `run_number + 100`.
5. Du får ikke åpnet github.io fra cloud-containeren (proxyen blokkerer den). Bruk lokal eksport og skjermbilder for å verifisere.

## Regler

- Spillogikk ligger i `game/core/` som ren 2D-logikk uten noder, og den testes. 3D-grafikken leser bare tilstand.
- Tester skrives i `game/tests/**/test_*.gd` med metoder `test_*`, og bruker `t.check(cond, msg)` og `t.eq(actual, expected, msg)`.
- Bruk typet GDScript.
- Endres `game/export_presets.cfg` eller `.godot-version`, kjør `scripts/export-ios.sh` og commit `ios/` (CI sjekker at de er i synk).
- Ikke bruk Blizzard-innhold (modeller, lyder, navn eller kart).
