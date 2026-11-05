# Mazeborn TD

Tower defense for iOS i klassisk Warcraft 3-stil: 3D-grafikk oppå 2D-logikk på et rutenett med mazing. Laget med Godot 4 (GDScript).

- Teknologivalg og plan: issue #1
- iOS-bygg og TestFlight via GitHub Actions (ingen mac): [`docs/ios-build.md`](docs/ios-build.md)
- Lyd: syntetisert av `scripts/make_sfx.py` (CC0), se [`CREDITS.md`](CREDITS.md)
- 3D-grafikk, kandidater og lisenser: [`docs/art-assets.md`](docs/art-assets.md) og [`CREDITS.md`](CREDITS.md)
- Spillbar web-versjon: https://kristofferchr.github.io/Mazeborn-td/ (PR-er får egen lenke i en kommentar)

## Struktur

```
game/            Godot-prosjektet
  core/          spillregler som ren 2D-logikk (Grid, Game, Creep, Tower), testes headless
  data/          bølger og økonomi (waves.json), tårntyper (towers.json) og fiendetyper (creeps.json)
  data/maps/     kart som data: størrelse, portaler, mål, steiner og regler (én JSON per kart)
  view/          3D-lag, HUD, lyd og kartvalg som bare leser tilstanden (BoardView, Effects, CameraRig, Hud, HudFx, WaveOverview, GameAudio, MapSelect)
  main.tscn      appen: kartvalg, deretter en runde (round.tscn)
  tests/         headless tester (scripts/test.sh)
  tools/         skjermbilde, demo-scener og balanse-bot (ikke med i eksporten)
ios/             eksportert Xcode-prosjekt og ci_scripts for Xcode Cloud
scripts/         godot.sh (pinnet versjon), export-ios.sh, export-web.sh, screenshot.sh, make_sfx.py (lyd)
.godot-version   Godot-versjonen som brukes overalt
```

## Kart

Kartene ligger i `game/data/maps/<id>.json`: `name` og `description` (vises i kartvalget), `order`, `size` `[b, h]`, `spawns` (én eller flere `[x, y]`), `goal`, `blocked` (steinceller `[x, y]` eller rektangler `[x, y, b, h]`), valgfritt `decor` (`style` `"mountain"` eller `"boulders"`, `trees`, `boulders`) og `rules` (overstyrer `waves.json`, f.eks. `hp_scale` eller `start_gold`). Fiendene veksler mellom portalene, og man kan aldri bygge slik at en portal blir stengt inne. Nye kart testes av `game/tests/core/test_maps.gd` (legg id-en inn der), og boten bør vinne dem med noen liv tapt.

## Bølgeflyt og endeløs

Første bølge venter på spilleren. Etter hver bølge går en nedtelling (`build_time` i `waves.json`, litt kortere for hver bølge ned til `build_time_min`), og neste bølge starter av seg selv når den er ute. «Send nå» gir `early_gold_per_second` gull per sekund som er igjen, og sender man mens en bølge pågår, får man hele nedtellingen pluss `early_bonus`. Trykk på kortet for neste bølge for å se alle bølgene som er igjen.

Endeløs modus (`Game.create_map(id, seed, {"mode": "endless"})`, bryteren «Endeløs» i kartvalget) vinnes aldri: etter de faste bølgene lages nye bølger fra seeden (`endless` i `waves.json`): fiendetypene går på rundgang, livet vokser ×`hp_growth` per bølge og dusøren saktere, og hver `boss_every`-te bølge er en boss. Poengsummen er bølgen man nådde.

## Kommandoer

```bash
scripts/godot.sh --path game          # åpne eller kjøre med pinnet Godot
scripts/export-web.sh                 # web-bygg i build/web/
scripts/export-ios.sh                 # Xcode-prosjekt i ios/
scripts/screenshot.sh shot.png        # skjermbilde (xvfb, Compatibility-rendereren)
scripts/test.sh                       # headless tester (game/tests/**/test_*.gd)
gdlint game && gdformat --check game  # lint (pip install "gdtoolkit==4.5.0")
scripts/screenshot.sh shot.png res://tools/demo.tscn 30 2532x1170  # maze midt i en bølge
DEMO_MAP=klofta scripts/screenshot.sh shot.png res://tools/demo.tscn 30 2532x1170  # samme på et annet kart
scripts/screenshot.sh shot.png res://tools/juice.tscn 8 2532x1170   # banner, skadetall og partikler
DEMO_STATE=countdown scripts/screenshot.sh shot.png res://tools/demo.tscn 30 2532x1170  # nedtelling (også overview, endless)
scripts/make_sfx.py                   # lager alle lydeffekter og musikken i game/assets/audio/
scripts/godot.sh --headless --path game -s res://tools/balance.gd   # bot spiller alle kartene
scripts/godot.sh --headless --path game -s res://tools/balance.gd -- klofta 7  # ett kart, seed 7
scripts/godot.sh --headless --path game -s res://tools/balance.gd -- all 3 endless  # endeløs (modus: wait er standard, early sender tidlig, endless-early)
```
