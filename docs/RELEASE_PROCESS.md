# Release-Prozess: Hub und Arena reproduzierbar bauen, prüfen und veröffentlichen

Ergänzt [RELEASE_BASELINE.md](RELEASE_BASELINE.md) (verbindlicher Git-Stand, Releaseblocker,
manuelle Abnahme). Dieses Dokument beschreibt die Werkzeuge, mit denen ein freigegebener
Commit in genau die beiden Places einer Zielumgebung gelangt, und was einen Upload stoppt.

Grundsatz: **Validierung und Build sind vom Publish getrennt.** Ein Build erzeugt Artefakte
und ein Manifest, lädt aber nichts hoch. Der Publish nimmt nur ein Manifest an, baut beide
Places erneut, vergleicht die Hashes und lädt erst dann hoch. Jede Fehlkonfiguration stoppt
vor dem Upload. Ein Prüfer sieht in der Ausgabe und im Manifest, welches Artefakt (Hash)
in welchen Place (ID) welcher Experience (Universe-ID) gelangen würde.

## Dateien

| Datei | Zweck |
| --- | --- |
| [release/targets.json](../release/targets.json) | **Allowlist** der Ziele DEV, STAGING, PROD: Universe-ID, Hub- und Arena-Place-ID, Umgebung (`DEV`/`PROD` nach ExperienceConfig), DataStore- und MemoryStore-Namen, `publishAllowed`, `requiresApproval`, `requireCommitOnOriginMain`, Name der Umgebungsvariable mit dem API-Key. |
| [release/tools.json](../release/tools.json) | Fixierte Werkzeugversionen: Rojo 7.7.1, Luau 0.747, mit SHA-256 der Release-Archive; GitHub-Actions-SHAs. |
| [release/tests.json](../release/tests.json) | Die lokalen Luau-Suiten, die ein Release-Build ausführt, und welche davon bestehen müssen. |
| [aftman.toml](../aftman.toml) | Dieselbe Rojo-Version für `aftman install`. |
| [scripts/release/Install-Tools.ps1](../scripts/release/Install-Tools.ps1) | Lädt genau die fixierten Release-Archive nach `.tools/` (git-ignoriert), prüft den SHA-256 vor dem Entpacken, verweigert Archive ohne eingetragenen Hash. |
| [scripts/release/Validate-Release.ps1](../scripts/release/Validate-Release.ps1) | Prüft Ziel, Git-Stand, Werkzeugversion, Quellversionen. Kein Build, kein Upload. |
| [scripts/release/Build-Release.ps1](../scripts/release/Build-Release.ps1) | Validiert, baut beide Places, hasht sie, führt optional die Suiten aus, schreibt `manifest.json` und `summary.txt`. |
| [scripts/release/Publish-Release.ps1](../scripts/release/Publish-Release.ps1) | Lädt ein gebautes Manifest hoch (Open Cloud). Rebuild und Hashvergleich davor, Protokoll danach. |
| [.github/workflows/validate-build.yml](../.github/workflows/validate-build.yml) | CI bei jedem Push/PR: Werkzeuge, Syntax, Suiten, Build, Manifest als Artefakt. Keine Secrets, kein Upload. |
| [.github/workflows/publish.yml](../.github/workflows/publish.yml) | Nur manuell (`workflow_dispatch`), je Ziel eine GitHub-Environment mit Freigabe. Nicht Teil dieses Tasks ausgeführt. |

`scripts/build-places.ps1` und `scripts/publish-places.ps1` bleiben als einfache lokale
Hilfen bestehen; für Releases gilt ausschließlich der Weg über `scripts/release/`.

## Ziele und Allowlist

```text
DEV      Universe 10771565873, Hub 127694690386807, Arena 70661230851944   publishAllowed, ohne Freigabe
STAGING  nicht konfiguriert (IDs null)                                       gesperrt, Freigabe nötig, Commit muss auf origin/main liegen
PROD     nicht konfiguriert (IDs null; ExperienceConfig PROD = 0)            gesperrt, Freigabe nötig, Commit muss auf origin/main liegen
```

Prüfungen in `Resolve-ReleaseTarget` (ReleaseCommon.ps1), alle vor jedem Build und Upload:

- Der Zielname muss **genau** (Groß-/Kleinschreibung) in `targets.json` stehen; `dev` wird abgelehnt.
- Universe-, Hub- und Arena-ID müssen Zahlen mit 7 bis 20 Stellen ohne führende Null sein; `null`, `0`, leer oder mit Buchstaben wird abgelehnt. Hub und Arena dürfen nicht dieselbe ID haben.
- `environment` muss `DEV` oder `PROD` sein; DataStore- und MemoryStore-Name müssen denen in [ExperienceConfig](../src/shared/ExperienceConfig.luau) für diese Umgebung gleichen.
- Für DEV und PROD müssen die Place-IDs **exakt** den `HubPlaceId`/`ArenaPlaceId` der Umgebung in ExperienceConfig gleichen, sonst würde der Server auf diesen Places eine andere Umgebung wählen. Für PROD gilt zusätzlich: Die IDs in ExperienceConfig dürfen nicht `0` sein.
- STAGING ist eine eigene Experience, deren IDs in ExperienceConfig **nicht** vorkommen dürfen (ihre Server laufen mit der DEV-Konfiguration innerhalb ihres eigenen Universums). Das STAGING-Ziel wird erst nutzbar, wenn in `targets.json` die IDs eingetragen sind und `publishAllowed` auf `true` steht; ein Nachtrag braucht ein eigenes Review.
- `publishAllowed: false` erlaubt Builds, aber keinen Upload.

PROD freischalten heißt: PROD-Place-IDs in `ExperienceConfig.luau` eintragen (Gameplay-/Integrations-Task), dieselben IDs und die Universe-ID in `targets.json`, `publishAllowed: true`. Beides in einem reviewten Commit, der auf `origin/main` liegt.

## Lokaler Ablauf

Voraussetzung: Windows PowerShell 5.1 oder PowerShell 7, Git, Rojo 7.7.1 (Aftman oder `.tools/`).

```powershell
.\scripts\release\Install-Tools.ps1                       # einmalig: Rojo 7.7.1 und Luau 0.747 nach .tools\ (Hash geprüft)
.\scripts\release\Validate-Release.ps1 -Target DEV        # darf dieser Stand für DEV gebaut werden?
.\scripts\release\Build-Release.ps1 -Target DEV -RunTests -LuauPath .\.tools\luau.exe
#  -> build\release\DEV-<commit12>\OttiHub.rbxlx, OttiArena.rbxlx, manifest.json, summary.txt
.\scripts\release\Publish-Release.ps1 -ManifestPath build\release\DEV-<commit12>\manifest.json -DryRun
.\scripts\release\Publish-Release.ps1 -ManifestPath build\release\DEV-<commit12>\manifest.json            # Versionen SPEICHERN (nichts live)
.\scripts\release\Publish-Release.ps1 -ManifestPath build\release\DEV-<commit12>\manifest.json -Publish   # live schalten
```

`-SkipCleanCheck` erlaubt Validate und Build auf einem unsauberen Arbeitsstand für lokale
Probeläufe. Der Publish kennt diesen Schalter nicht und lehnt ein Manifest ab, das aus einem
unsauberen Stand gebaut wurde (`git.clean` im Manifest).

### Was Validate und Build prüfen

1. Ziel-Allowlist und ExperienceConfig (oben).
2. Git: `git status --porcelain` leer (auch keine untracked Dateien); HEAD und Branch werden
   erfasst; für Ziele mit `requireCommitOnOriginMain` muss HEAD Vorfahr von `origin/main` sein
   (lokales `origin/main`; vorher `git fetch`).
3. Rojo: `rojo --version` muss der Version in `tools.json` und `aftman.toml` gleichen.
4. Quellversionen: `PlayerDataSchema.Version` (Profil, derzeit 12) und
   `GameProtocol.Version`/`MinCompatible` (derzeit 1/1) werden gelesen und ins Manifest geschrieben.
5. Beide Rojo-Projekte und die `PlaceRole`-Module (`"Hub"`, `"Arena"`) sind vorhanden.
6. Build: beide Places; SHA-256 und Größe jedes Artefakts ins Manifest.
7. Mit `-RunTests`: `luau-compile --binary` über jede Datei unter `src/` (Syntax), dann die Suiten
   aus `tests.json`. Eine fehlgeschlagene `required`-Suite bricht den Build ab. Die beiden auf der
   Basis roten Rom-Suiten sind als nicht erforderlich eingetragen und werden mit Ergebnis protokolliert.

### Das Manifest

`manifest.json` enthält: `manifestVersion`, Zeitpunkt, Bauende/Rechner, `git` (Commit,
Branch, describe, clean, onOriginMain), `target` (Name, Universe, Umgebung, Speichernamen,
Freigabeflags), `tools` (Rojo-Version, Luau-Pfad und fixierte Luau-Version),
`profileSchemaVersion`, `protocol`, je Place `role`, `project`, `file`, `bytes`, `sha256`,
`universeId`, `placeId`, `placeName`, die `tests` mit Ergebnis und ein `publishLog`, das jeder
Publish-Lauf ergänzt. `summary.txt` fasst dasselbe für einen Prüfer auf einer Seite zusammen.

### Was der Publish zusätzlich prüft

- Das Manifest gehört zum angegebenen Ziel; Universe, Umgebung, Speichername und beide
  Place-IDs im Manifest gleichen der Allowlist (ein nachträglich geändertes `targets.json`
  oder ein Manifest für ein anderes Ziel stoppt).
- HEAD ist der Manifest-Commit, der Arbeitsstand ist sauber, `requireCommitOnOriginMain` erfüllt.
- Rojo ist die Version des Manifests. **Beide Places werden erneut gebaut**; die Hashes des
  Rebuilds und der Artefakte auf der Platte müssen dem Manifest gleichen. Ein Build, der sich
  nicht reproduziert, wird nicht hochgeladen.
- `requiresApproval` verlangt `-ApprovalReference "<wer, wo dokumentiert>"`; der Text landet im Protokoll.
- `-DryRun` endet nach der Ausgabe der Tabelle „Artefakt → Place“, ohne Netzwerk.

### Secrets

Der Open-Cloud-API-Key wird **nie** als Kommandozeilenargument übergeben (sichtbar in
Prozesslisten), nie ausgegeben, nie in Manifest oder Protokoll geschrieben (dort steht nur die
Quelle: Umgebungsvariable oder Eingabe). Er kommt aus der Umgebungsvariablen, die das Ziel in
`targets.json` nennt (`OTTI_OPEN_CLOUD_API_KEY_DEV` usw.), oder bei interaktivem Lauf aus einer
verdeckten Eingabe. Fehlermeldungen der API werden vor der Ausgabe um den Key bereinigt.

Anforderungen (im Repository **nicht** angelegt, bei Bedarf vom Besitzer der Experience zu erstellen):

| Wert | Wo | Berechtigung |
| --- | --- | --- |
| `OTTI_OPEN_CLOUD_API_KEY_DEV` | lokal als Umgebungsvariable oder GitHub-Environment-Secret `DEV` | Open Cloud API Key, `universe-places: write`, nur Experience 10771565873, möglichst mit IP-Beschränkung und Ablaufdatum |
| `OTTI_OPEN_CLOUD_API_KEY_STAGING` | GitHub-Environment `STAGING` | wie oben für die STAGING-Experience, sobald sie existiert |
| `OTTI_OPEN_CLOUD_API_KEY_PROD` | GitHub-Environment `PROD` | wie oben für die PROD-Experience; Environment mit Pflicht-Reviewern |

### Upload und Teilfehler

Der Upload benutzt die Open-Cloud-Place-Publishing-API
(`POST https://apis.roblox.com/universes/v1/{universe}/places/{place}/versions?versionType=Saved|Published`,
Header `x-api-key`, Body die `.rbxlx`). Reihenfolge: Hub, dann Arena. Die Antwort
(`versionNumber`) wird je Place protokolliert (`publish-log.jsonl` im Build-Ordner und
`publishLog` im Manifest).

| Lage | Protokollzustand | Folge |
| --- | --- | --- |
| Beide Uploads erfolgreich | `OK` | Versionsnummern beider Places im Protokoll; für die Abnahme dem Commit zuordnen. |
| Hub schlägt fehl | `FAILED` | Nichts geändert. Ursache beheben, erneut starten. |
| Hub erfolgreich, Arena schlägt fehl, Modus Saved | `PARTIAL` | Nichts live. `-Only Arena` mit demselben Manifest wiederholen. |
| Hub erfolgreich, Arena schlägt fehl, Modus Published | `PARTIAL` | Hub live mit neuer, Arena mit alter Version. Entweder `-Only Arena -Publish` mit demselben Manifest, oder Rollback des Hubs (unten). Bis dahin schützt `GameProtocol.MinCompatible`: Eine Arena lehnt Tickets einer inkompatiblen Protokollversion ab; bei gleicher Protokollversion laufen alte Arena-Server mit dem neuen Hub weiter. |

Der Standardmodus ist **Saved**: Beide Places erhalten eine gespeicherte, nicht live
geschaltete Version, die ein Prüfer in Studio oder in der Versionshistorie öffnen kann.
Erst `-Publish` schaltet live.

## Rollback

Die Open-Cloud-API dieses Prozesses legt nur neue Versionen an. Ein Rollback ist die erneute
Veröffentlichung eines früheren Standes:

1. **Aus Git (bevorzugt):** Den zuletzt freigegebenen Commit auschecken (sauberer Stand),
   `Build-Release.ps1` und `Publish-Release.ps1 -Publish` für dasselbe Ziel ausführen. Das
   Protokoll des neuen Laufs verweist mit Commit und Hashes auf den Rollback-Stand. Beide Places
   zusammen zurücksetzen, es sei denn, nur ein Place war betroffen (`-Only`).
2. **Aus der Versionshistorie (Creator Hub):** Experience → Places → Place → Versionshistorie →
   die frühere Version, deren Nummer im Protokoll des vorigen erfolgreichen Laufs steht, auf
   „Veröffentlichen“ setzen. Für den anderen Place genauso, damit Hub und Arena wieder zu einem
   Commit gehören. Danach im Protokoll (`publish-log.jsonl`) von Hand einen Eintrag mit beiden
   Versionsnummern und dem Grund nachtragen.

Nicht zurückgerollt werden gespeicherte Spielerdaten: Die Profilmigration
(`PlayerDataSchema`, `InventoryService.migrateProfile`) läuft nur vorwärts. Ein Rollback auf
einen Stand mit kleinerer `PlayerDataSchema.Version` darf nicht veröffentlicht werden, solange
Profile mit der höheren Version existieren; der Publish prüft das derzeit **nicht** (siehe Risiken).

## Manuelle Freigabe und Abnahme

1. **Kandidat festlegen:** Commit-SHA auf `origin/main` (DEV: beliebiger Branch), Manifest aus
   `Build-Release.ps1 -RunTests` ohne fehlgeschlagene `required`-Suite. `summary.txt` an die
   Freigabe anhängen: Commit, Hashes, Ziel, Schema- und Protokollversion, Testergebnisse.
2. **Prüfen, wohin es geht:** `Publish-Release.ps1 -DryRun` zeigt Universe, beide Place-IDs und
   Hashes. Die Place-IDs mit dem Creator Hub abgleichen (Place-URL).
3. **Speichern statt veröffentlichen:** Publish ohne `-Publish`. Die gespeicherten Versionen in
   Studio öffnen und die Abläufe aus RELEASE_BASELINE.md, Abschnitt „Manuelle Abnahme“, abhaken
   (Hub: Ankunft, Intro, Solo-Start, Portale, Keller, Trainingshöfe; Arena: Modi, Rollen, Match-Ende;
   Profil und Shop).
4. **Freigabe dokumentieren:** Für STAGING und PROD Freigebende und Ablageort festhalten; dieser
   Text wird als `-ApprovalReference` übergeben und im Protokoll gespeichert. In GitHub schützen
   die Environments `STAGING` und `PROD` mit Pflicht-Reviewern den manuellen Workflow.
5. **Live schalten:** `-Publish` lokal oder über den Workflow `publish` mit `mode = publish`.
   Versionsnummern aus dem Protokoll in die Abnahme übernehmen; den Hub-→-Arena-→-Hub-Ablauf mit
   mehreren Testkonten auf dem veröffentlichten Stand prüfen (RELEASE_BASELINE.md, Schritt 3).
6. **Nachweis ablegen:** Manifest, `summary.txt` und `publish-log.jsonl` des Laufs (CI: das
   Artefakt `publish-<ziel>-<sha>-<run>`) mit dem Commit verknüpfen.

## CI

`validate-build` läuft bei jedem Push und Pull Request auf `windows-latest`: fixierte Werkzeuge
per `Install-Tools.ps1` (Hash-geprüft), `Validate-Release.ps1 -Target DEV`,
`Build-Release.ps1 -Target DEV -RunTests`, Zusammenfassung ins Log, Artefakte und Manifest 30
Tage als Workflow-Artefakt. Der Workflow hat keine Secrets und keinen Netzwerkzugriff auf Roblox.
Die Actions sind per Commit-SHA fixiert (`release/tools.json`).

`publish` läuft nur per `workflow_dispatch` mit Ziel, Modus (`save`/`publish`),
Freigabereferenz und `only`. Der Job läuft in der GitHub-Environment des Ziels; deren Secret ist
der API-Key, deren Schutzregeln sind die Freigabe. Er wurde in diesem Task **nicht** ausgeführt
und kann erst laufen, wenn Environments und Secrets angelegt sind.

## Werkzeuge fixieren und aktualisieren

- Rojo-Version: `aftman.toml` **und** `release/tools.json` ändern (beide müssen gleich sein,
  sonst stoppt die Validierung), die neuen Archiv-Hashes eintragen, `Install-Tools.ps1` laufen lassen.
- Hash eines Archivs ermitteln: Archiv von der GitHub-Release-Seite laden, `Get-FileHash -Algorithm SHA256`,
  Größe vergleichen, Inhalt sichten (Rojo: `rojo.exe`; Luau: `luau.exe`, `luau-analyze.exe`,
  `luau-compile.exe`, `luau-ast.exe`), erst dann eintragen. Ein leerer Hash sperrt die Installation.
- Luau 0.747 ist die fixierte Version für CI und `.tools/`. Lokal vorhandene andere Luau-Binaries
  funktionieren für die Suiten, werden aber im Manifest nur mit Pfad, nicht mit Version erfasst.

## Verbleibende Risiken

- Der Publish ist gegen die Open-Cloud-API **nicht** ausgeführt worden (kein Key, keine Uploads in
  diesem Task). Pfad, Header und Antwortformat entsprechen der dokumentierten Place-Publishing-API;
  der erste Lauf gegen DEV im Modus Saved ist der Nachweis.
- Keine Prüfung, dass die `PlayerDataSchema.Version` des Kandidaten nicht kleiner ist als die
  der zuletzt veröffentlichten Version (Rollback-Schutz der Profile). Bis dahin manuell im
  Protokoll vergleichen.
- Die Reproduzierbarkeit stützt sich darauf, dass Rojo für dieselben Quellen byteidentische
  `.rbxlx` erzeugt. Der Publish stoppt, wenn das nicht gilt; dann ist der Build zu untersuchen.
- `requireCommitOnOriginMain` prüft gegen das lokale `origin/main`; ohne vorheriges `git fetch`
  kann es veraltet sein. In CI ist es der Stand des Checkouts.
- Die beiden roten Rom-Suiten bleiben Befunde der Basis; sie blockieren den Build nicht.
