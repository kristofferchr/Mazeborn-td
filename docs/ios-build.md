# iOS-bygg og TestFlight

Repoet er offentlig, så GitHub sine macOS-runnere er gratis. Hovedveien er derfor
**GitHub Actions** (`.github/workflows/ios.yml`): bygg, automatisk signering med
en App Store Connect API-nøkkel og opplasting til TestFlight. **Ingen mac trengs.**

Xcode Cloud (`ios/ci_scripts/`) er beholdt som reserve, men er ikke satt opp og
krever at workflowen opprettes én gang fra Xcode på en mac.

## Ny TestFlight-versjon

```bash
git tag v0.2.0 && git push --tags
```

Det er alt. Workflowen bygger versjon `0.2.0`, laster den opp, setter
«What to Test» og venter til Apple er ferdig. Testergruppen «meg» er intern og har
tilgang til alle bygg, og `ITSAppUsesNonExemptEncryption=false` står i Info.plist,
så builden er klar i TestFlight uten manuelle steg. Jobben blir rød hvis Apple
avviser builden eller ikke er ferdig innen 45 minutter.

Taggen må være `v` etterfulgt av ett til tre tall (`v1`, `v0.2`, `v0.2.0`), fordi
iOS krever det for `CFBundleShortVersionString`. `v0.2.0-beta` stoppes i første steg.

Manuell kjøring (Actions → iOS TestFlight → Run workflow) på en branch bruker
versjonen i `game/export_presets.cfg` (`application/short_version`, nå `0.1.0`).
Velger du en tagg som ref, brukes taggens versjon.

## Slik fungerer det

1. **Versjon og byggnummer:** `APP_VERSION` kommer fra taggen (`v0.2.0` → `0.2.0`),
   ellers fra `export_presets.cfg`. Byggnummeret er `GITHUB_RUN_NUMBER + 100`.
2. `scripts/export-ios.sh <build>` laster ned Godot og eksportmalene for
   versjonen i `.godot-version` (`scripts/godot.sh`) og eksporterer `game/` til
   `ios/Mazeborn.xcodeproj` med det gitte byggnummeret. Dette virker også på Linux.
3. `xcodebuild archive` med `-allowProvisioningUpdates`, API-nøkkelen og
   `MARKETING_VERSION=$APP_VERSION`. Info.plist bruker `$(MARKETING_VERSION)`, så
   versjonen settes ved bygging, og `export_presets.cfg` og `ios/` i git er uendret.
   Xcode lager eller henter sertifikat og provisioning-profil selv. Et eget steg
   sjekker at arkivet har riktig versjon og byggnummer.
4. `xcodebuild -exportArchive` med `scripts/ExportOptions.plist`
   (`app-store-connect`, `destination=upload`) signerer for App Store og laster opp.
5. `scripts/asc_whats_new.py` venter til builden dukker opp i App Store Connect og
   setter «What to Test» (`betaBuildLocalizations`) før testerne varsles. Teksten
   er titlene på PR-ene og commit-meldingene siden forrige `v*`-tagg. Finnes det
   ingen tidligere tagg, er det endringene siden committen til forrige vellykkede
   TestFlight-kjøring. Ved manuell kjøring på en branch er det de siste 15 PR-ene.
   Teksten kortes ned til Apples grense på 4000 tegn, og den vises også i
   oppsummeringen av kjøringen. Språket er appens primærspråk (`no`, norsk) pluss
   eventuelle TestFlight-lokaliseringer.
6. `scripts/asc_builds.py --wait <build> --version <versjon>` venter på
   `processingState`. `VALID` gir grønn jobb. `INVALID`/`FAILED`, en feilet opplasting
   eller tidsavbrudd etter 45 minutter gir rød jobb.

Sjekk lokalt (bare lesing mot App Store Connect, krever `ASC_*`-variablene og
`pip install pyjwt cryptography`):

```bash
scripts/asc_builds.py                                  # siste opplastinger og bygg
scripts/asc_builds.py --wait 107 --version 0.2.0       # vent på et bygg
scripts/asc_whats_new.py --build 107 --version 0.2.0 --tag v0.2.0 --dry-run
```

`--dry-run` skriver ut teksten og API-kallene scriptet ville gjort, uten å endre noe.
Uten `ASC_*`-variablene skrives bare teksten ut.

### Hva som ligger i git

| Sti | I git? | Hvorfor |
|---|---|---|
| `ios/Mazeborn.xcodeproj`, `ios/Mazeborn/`, `ios/PrivacyInfo.xcprivacy` | ✅ | Små filer. CI sjekker at de er i synk med eksporten. |
| `ios/ci_scripts/` | ✅ | Bare for Xcode Cloud (se nederst). Brukes ikke av GitHub Actions. |
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
5. **Kjør:** `git tag v0.2.0 && git push --tags`, eller Actions → iOS TestFlight →
   Run workflow. Builden er klar i TestFlight når jobben er grønn.

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

Vi beholder `ci_scripts/` fordi det er ett lite script som ikke koster noe, og som
er en reserve hvis GitHub sine macOS-runnere eller automatisk signering slutter å
virke. Xcode Cloud setter ikke «What to Test» eller versjon fra tagg. Det
gjør bare GitHub-workflowen.
