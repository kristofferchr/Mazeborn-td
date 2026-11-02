# Mazeborn TD

Tower defense for iOS i klassisk Warcraft 3-stil: 3D-grafikk oppå 2D-logikk på et rutenett med mazing. Laget med Godot 4 (GDScript).

- Teknologivalg og plan: issue #1
- iOS-bygg og TestFlight via Xcode Cloud: [`docs/ios-build.md`](docs/ios-build.md)

## Struktur

```
game/            Godot-prosjektet
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
```
