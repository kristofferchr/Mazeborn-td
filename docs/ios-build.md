# iOS-bygg og TestFlight

Repoet er offentlig, så GitHub sine macOS-runnere er gratis. Hovedveien er derfor
**GitHub Actions** (`.github/workflows/ios.yml`): bygg, automatisk signering med
en App Store Connect API-nøkkel og opplasting til TestFlight. **Ingen mac trengs.**

Xcode Cloud (`ios/ci_scripts/`) er beholdt som alternativ, men krever at
workflowen opprettes én gang fra Xcode på en mac.

## Slik fungerer det

1. `scripts/export-ios.sh <build>` laster ned Godot og eksportmalene for
   versjonen i `.godot-version` (`scripts/godot.sh`) og eksporterer `game/` til
   `ios/Mazeborn.xcodeproj` med det gitte byggnummeret. Dette virker også på Linux.
2. `xcodebuild archive` med `-allowProvisioningUpdates` og API-nøkkelen.
   Xcode lager eller henter sertifikat og provisioning-profil selv.
3. `xcodebuild -exportArchive` med `scripts/ExportOptions.plist`
   (`app-store-connect`, `destination=upload`) signerer for App Store og laster opp.

Workflowen kjører ved tagg `v*` eller manuelt (Actions → iOS TestFlight → Run workflow).
Byggnummeret er `GITHUB_RUN_NUMBER + 100`.

### Hva som ligger i git

| Sti | I git? | Hvorfor |
|---|---|---|
| `ios/Mazeborn.xcodeproj`, `ios/Mazeborn/`, `ios/PrivacyInfo.xcprivacy` | ✅ | Små filer. CI sjekker at de er i synk med eksporten. |
| `ios/ci_scripts/` | ✅ | Bare for Xcode Cloud. |
| `ios/*.xcframework` (motoren, 189 MB per arkitektur), `ios/Mazeborn.pck` | ❌ | For store, og genereres i hvert bygg. |

Når `game/export_presets.cfg` eller Godot-versjonen endres: kjør
`scripts/export-ios.sh` og commit `ios/`.

## Engangsoppsett (bare nettleser)

1. **App ID:** developer.apple.com → Identifiers → `kristofferchr.MazebornTD` ✅
2. **App:** App Store Connect → Apps → **+** → New App, bundle ID `kristofferchr.MazebornTD`.
3. **API-nøkkel:** App Store Connect → Users and Access → Integrations →
   App Store Connect API → Team Keys → **+**. Rollen må være **Admin**, siden
   automatisk signering må kunne lage sertifikater og profiler. Last ned `AuthKey_XXXX.p8`
   (det går bare én gang) og noter Key ID og Issuer ID.
4. **GitHub secrets:** repo → Settings → Secrets and variables → Actions → New repository secret:
   - `ASC_KEY_ID`: Key ID
   - `ASC_ISSUER_ID`: Issuer ID
   - `ASC_PRIVATE_KEY_BASE64`: `.p8`-filen base64-kodet (`base64 -i AuthKey_XXXX.p8`)
5. **Kjør:** Actions → iOS TestFlight → Run workflow. Builden dukker opp i
   TestFlight etter noen minutter med prosessering hos Apple.

Secrets er ikke tilgjengelige for PR-er fra forks, og iOS-workflowen kjører bare
på tagger og ved manuell start. Et offentlig repo lekker derfor ikke nøkkelen.

## Kjente risikoer ved første kjøring

- **«No devices»:** Arkivering med utviklingsidentitet krever at teamet har minst én
  registrert enhet. iPhonen din er trolig registrert fra Sleiv. Hvis ikke: legg den til
  under Certificates, Identifiers & Profiles → Devices (UDID finnes i Finder eller via
  nettsteder som viser UDID).
- **Signeringsfeil:** Faller automatisk signering gjennom, går vi over til manuell
  signering: lag distribusjonssertifikat og App Store-profil via API-et, legg dem i
  secrets og importer dem i en midlertidig nøkkelring på runneren.

## Lokalt (Linux eller mac)

```bash
scripts/export-ios.sh          # Xcode-prosjekt i ios/
scripts/export-web.sh          # web-bygg i build/web/
scripts/screenshot.sh out.png  # skjermbilde av res://main.tscn
```

## Alternativ: Xcode Cloud

`ios/ci_scripts/ci_post_clone.sh` kjører `scripts/export-ios.sh "$CI_BUILD_NUMBER"`.
Workflowen må opprettes én gang fra Xcode (Product → Xcode Cloud → Create Workflow:
Archive, scheme `Mazeborn`, TestFlight internal). Bruk bare én av løsningene,
ellers kolliderer byggnumrene.
