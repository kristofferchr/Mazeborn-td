# iOS-bygg med Xcode Cloud

Godot eksporterer et Xcode-prosjekt. Xcode Cloud bygger, signerer og laster det
opp til TestFlight. Ingen GitHub macOS-runnere, og macen trengs bare til
engangsoppsettet.

## Slik fungerer det

1. `ios/ci_scripts/ci_post_clone.sh` kjører på Xcode Cloud etter klone.
2. Scriptet kaller `scripts/export-ios.sh "$CI_BUILD_NUMBER"`, som
   - laster ned Godot for macOS og eksportmalene for versjonen i `.godot-version`
     (`scripts/godot.sh`, ca. 170 MB pluss 1,3 GB malpakke, der vi bare beholder iOS og web),
   - eksporterer `game/` til `ios/Mazeborn.xcodeproj` med byggnummeret fra Xcode Cloud.
3. Xcode Cloud bygger `ios/Mazeborn.xcodeproj` med schemet `Mazeborn` og
   arkiverer det til TestFlight.

### Hva som ligger i git

| Sti | I git? | Hvorfor |
|---|---|---|
| `ios/Mazeborn.xcodeproj`, `ios/Mazeborn/`, `ios/PrivacyInfo.xcprivacy` | ✅ | Små filer. Xcode Cloud og Xcode må finne prosjektet før post-clone kjører. |
| `ios/ci_scripts/` | ✅ | Xcode Cloud krever at mappen ligger ved siden av prosjektet. |
| `ios/*.xcframework` (motoren, 189 MB per arkitektur), `ios/Mazeborn.pck` | ❌ | For store, og genereres på nytt av post-clone. |

De sjekkede iOS-filene regenereres av `scripts/export-ios.sh`. Kjør scriptet og
commit endringene når `game/export_presets.cfg` eller Godot-versjonen endres.

## Verifisert fra Linux (Claude Code-containeren)

- Godot 4.7.2 eksporterer et komplett Xcode-prosjekt fra Linux. Bare `.ipa` krever macOS.
- Bundle ID `kristofferchr.MazebornTD` og team `TL57MDF5L6` (samme konto som Sleiv),
  automatisk signering, iOS 16+, bare iPhone.
- `ITSAppUsesNonExemptEncryption = false` legges inn av Godot.

## Engangsoppsett (krever macen én gang)

1. App Store Connect → Apps → **+** → ny app med bundle ID
   `kristofferchr.MazebornTD` (registrer ID-en under Certificates, Identifiers &
   Profiles hvis den ikke dukker opp).
2. Klon repoet på macen og åpne `ios/Mazeborn.xcodeproj` i Xcode.
   Prosjektet bygger ikke lokalt før `scripts/export-ios.sh` er kjørt, men det
   trengs ikke for å opprette workflowen.
3. Product → Xcode Cloud → **Create Workflow**:
   - Start condition: branch `main` (eller tagg `v*` senere, for å spare compute-timer)
   - Environment: siste stabile Xcode og macOS
   - Action: **Archive**, iOS, scheme `Mazeborn`, distribusjon **TestFlight (Internal Testing Only)**
   - Post-action: TestFlight Internal Testing → din testergruppe
4. Gi Xcode Cloud tilgang til GitHub-repoet når du blir bedt om det.

Etter dette kan workflowen endres i App Store Connect på web (Xcode Cloud → Manage Workflows).

## Lokalt (Linux eller mac)

```bash
scripts/export-ios.sh          # Xcode-prosjekt i ios/
scripts/export-web.sh          # web-bygg i build/web/
scripts/screenshot.sh out.png  # skjermbilde av res://main.tscn
```

## Feilsøking

- Loggene ligger i App Store Connect → Xcode Cloud → build → `ci_post_clone.sh`.
- `godot.sh: downloading ...` feiler: sjekk at versjonen i `.godot-version` finnes
  på https://github.com/godotengine/godot/releases.
- `export-ios.sh: missing ios/...`: Godot-eksporten feilet. Se `ERROR:`-linjene over i loggen.
