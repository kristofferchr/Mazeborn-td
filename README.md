# Mazeborn TD

Tower defense for iOS i klassisk Warcraft 3-stil: 3D-grafikk oppå 2D-logikk på et rutenett med mazing. Laget med Godot 4 (GDScript).

- Teknologivalg og plan: issue #1
- iOS-bygg og TestFlight via GitHub Actions (ingen mac): [`docs/ios-build.md`](docs/ios-build.md)
- 3D-grafikk, kandidater og lisenser: [`docs/art-assets.md`](docs/art-assets.md) og [`CREDITS.md`](CREDITS.md)
- Spillbar web-versjon: https://kristofferchr.github.io/Mazeborn-td/ (PR-er får egen lenke i en kommentar)

## Struktur

```
game/            Godot-prosjektet
  core/          spillregler som ren 2D-logikk (Grid, Game, Creep, Tower), testes headless
  data/          bølger og økonomi (waves.json), tårntyper (towers.json) og fiendetyper (creeps.json)
  view/          3D-lag og HUD som bare leser tilstanden (BoardView, CameraRig, Hud)
  tests/         headless tester (scripts/test.sh)
  tools/         skjermbilde, demo-scene og balanse-bot (ikke med i eksporten)
ios/             eksportert Xcode-prosjekt og ci_scripts for Xcode Cloud
scripts/         godot.sh (pinnet versjon), export-ios.sh, export-web.sh, screenshot.sh
.godot-version   Godot-versjonen som brukes overalt
```

## Kommandoer

```bash
scripts/godot.sh --path game          # åpne eller kjøre med pinnet Godot
scripts/export-web.sh                 # web-bygg i build/web/
scripts/export-ios.sh                 # Xcode-prosjekt i ios/
scripts/screenshot.sh shot.png        # skjermbilde (xvfb, Compatibility-rendereren)
scripts/test.sh                       # headless tester (game/tests/**/test_*.gd)
gdlint game && gdformat --check game  # lint (pip install "gdtoolkit==4.5.0")
scripts/screenshot.sh shot.png res://tools/demo.tscn 30 2532x1170  # maze midt i en bølge
scripts/godot.sh --headless --path game -s res://tools/balance.gd   # bot spiller en runde
```
