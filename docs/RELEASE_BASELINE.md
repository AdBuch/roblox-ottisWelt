# MVP-Release-Basis 01

## Verbindlicher Git-Stand

- Repository [AdBuch/roblox-ottisWelt](https://github.com/AdBuch/roblox-ottisWelt).
- Basis [`27aae86a54734e140a67586fe7d371dce246b084`](https://github.com/AdBuch/roblox-ottisWelt/commit/27aae86a54734e140a67586fe7d371dce246b084), Git-Betreff „Redesign Hub lobby: introduce cellars, gateways, and dynamic intro“.
- Am 15. November 2026 zeigten der saubere lokale `main`, das lokale `origin/main` und GitHubs `main` auf diese Basis. Der lesende Vergleich mit GitHub ergab 0 Commits voraus und 0 zurück. [GitHub-Vergleich](https://github.com/AdBuch/roblox-ottisWelt/compare/27aae86a54734e140a67586fe7d371dce246b084...main)
- Der Merge `e44c8b4016591ea79b088a411c56fa73672d156d` und sein Feature-Commit `d26b7b0` für Helme, Designs und Datensicherung sind in der Basis enthalten. Zum Stichtag lagen auf GitHub `main` keine zusätzlichen Commits vor. [Pull Request #3](https://github.com/AdBuch/roblox-ottisWelt/pull/3)

Den ersten Folge-Task auf einem eigenen Branch direkt vom vollständigen Basis-Commit starten. Für spätere Tasks zusätzlich die ausdrücklich freigegebenen Folge-Commits mit SHA und Abnahme übernehmen und bei der Übergabe aufführen. Ein späterer Stand von `main` ersetzt die vereinbarte Basis nur nach ausdrücklicher Freigabe. Für parallele Tasks je einen eigenen Worktree verwenden.

```sh
git worktree add -b task/<name> <arbeitsverzeichnis> 27aae86a54734e140a67586fe7d371dce246b084
```

## Hub, Arena und Umgebungen

| Place | Rojo-Projekt | Build-Artefakt | Rolle |
| --- | --- | --- | --- |
| OTTI HUB | [places/hub.project.json](../places/hub.project.json) | `build/OttiHub.rbxlx` | `Hub`, Start-Place |
| COLOSSEUM ARENA | [places/arena.project.json](../places/arena.project.json) | `build/OttiArena.rbxlx` | `Arena`, reservierte Match-Server |

[default.project.json](../default.project.json) bildet ebenfalls den Hub ab. [scripts/build-places.ps1](../scripts/build-places.ps1) und [scripts/build-places.sh](../scripts/build-places.sh) erzeugen beide lokalen Artefakte.

| Umgebung | Experience-/Universe-ID | Hub-Place-ID | Arena-Place-ID | DataStore | MemoryStore-Namensraum |
| --- | --- | --- | --- | --- | --- |
| DEV | `10771565873` | `127694690386807` | `70661230851944` | `OttiPlayerData_DEV_v1` | `OttiMatches_DEV` |
| PROD | In der Basis nicht hinterlegt | `0` (Platzhalter) | `0` (Platzhalter) | `OttiPlayerData_PROD_v1` | `OttiMatches_PROD` |

Die Place-IDs und Speichernamen stammen aus [ExperienceConfig](../src/shared/ExperienceConfig.luau). Die DEV-Universe-ID steht dort im Kommentar und als Ziel im [DEV-Publish-Skript](../scripts/publish-places.ps1). [EnvironmentConfig](../src/shared/EnvironmentConfig.luau) wählt PROD ausschließlich außerhalb von Studio anhand einer passenden PROD-Place-ID ungleich `0`. Studio verwendet DEV mit simuliertem DataStore und MemoryStore. Cross-Place-Teleports benötigen außerhalb von Studio beide Place-IDs der gewählten Umgebung.

## Profil und Protokoll

- Gespeichertes Spielerprofil `12` gemäß [PlayerDataSchema](../src/shared/PlayerDataSchema.luau). Die v12-Migration strukturiert Schilddesigns nach Slots und erhält den Besitz beim Wechsel von `Galea` zu `SpartaHelm`. Die DataStore-Namen bleiben bei normalen Updates stabil. Der [Testprofil-Reset](../src/server/PlayerDataResetConfig.luau) ist deaktiviert.
- Hub-/Arena-Protokoll `1`, mindestens kompatibel mit `1`, gemäß [GameProtocol](../src/shared/GameProtocol.luau). Die Protokollversion gilt für den Match- und Zutrittsvertrag, unabhängig von der Profilversion. Änderungen an Tickets, Matchdaten oder Teleport-Payload müssen auf beiden Seiten abgestimmt werden.

## Releaseblocker und offene Nachweise

| Befund | Erforderlicher Nachweis |
| --- | --- |
| PROD-Place-IDs stehen auf `0`, und eine PROD-Experience-ID ist im Repository nicht belegt. | Vor einer Produktionsfreigabe die Zuordnung von Universe, Start-Place und Arena-Place verifizieren und die PROD-Konfiguration im dafür freigegebenen Task vervollständigen. |
| Die Developer-Product-IDs für Robux-Angebote stehen auf `0`. | Für den Releaseumfang festlegen, welche Angebote aktiv sein sollen. Für aktive Angebote dokumentierte Zuordnung zur Ziel-Experience und Nachweis der idempotenten Receipt-Verarbeitung. Die ID-Quellen sind [ForgeDefinitions](../src/shared/ForgeDefinitions.luau) und [HelmetDefinitions](../src/shared/HelmetDefinitions.luau). |
| Zwei lokale Rom-Suiten sind rot. `test-rome-layout.ps1` meldet sechs Abweichungen bei Gebäudezahlen und geöffneten Läden. `test-rome-geometry.ps1` meldet vier Abweichungen, davon drei für die mit der Basis geöffneten Trainingszugänge `BN1-Sued` und `BS1-Nord`. | Die Layout-Sollwerte und Modellvorgaben prüfen, die beabsichtigten Zugänge und Läden im Test abbilden und beide Suiten erneut ausführen. Beim direkten Vorgänger traten dieselben sechs Layout-Abweichungen und bereits der Geometriefehler „genau ein offenes Haus“ auf. |
| Der veröffentlichte Roblox-Stand ist **nicht verifiziert**, sowohl für DEV als auch für PROD. Die Git-SHA und die lokal gebauten `.rbxlx`-Dateien belegen keine veröffentlichte Place-Version. | Für beide Places Universe-/Place-ID und veröffentlichte Versionsnummer erfassen und dem freigegebenen Git-Commit über einen nachvollziehbaren Build-/Veröffentlichungsnachweis zuordnen. Hub- und Arena-Version gemeinsam für die Abnahme erfassen. |
| Die lokale Validierung deckt Studio-Spielabläufe und veröffentlichte Mehrserver-Abläufe noch nicht ab. | Die unten aufgeführten manuellen Abläufe für den vorgesehenen Release-Stand protokollieren. |

### Lokale Nachweise vom 15. November 2026

- Rojo `7.7.1` hat über `scripts/build-places.ps1` Hub und Arena erfolgreich gebaut.
- Zehn von zwölf `scripts/test-*.ps1` bestanden mit lokalem Luau. Erfolgreich waren `arena-campaign`, `combat-animation`, `hero-combat`, `lobby-ring`, `pad-teams`, `passive-momentum`, `player-data`, `progression`, `rome-services` und `specials`. Die Fehler in `rome-geometry` und `rome-layout` sind oben erfasst.
- Der Lobby-Harness prüft unter anderem die Kellerportale, die verlegten Gruppenpads und den geschlossenen Hub-Sand. Seine abschließende PASS-Zeile enthält noch die frühere Beschreibung von Training und Mosaiken auf dem Sand. Für den Sollstand gelten die Assertions in [lobby-ring-harness.luau](../scripts/lobby-ring-harness.luau) und die Implementierung der Basis.

## Reihenfolge und Zuständigkeit der Folge-Tasks

Vorgeschlagene Reihenfolge für die Übergabe. Die Zuständigkeiten benennen Aufgabenbereiche und werden bei Task-Zuteilung Personen zugewiesen.

| Reihenfolge | Zuständigkeit | Dateien und Schnittstellen |
| --- | --- | --- |
| 1. Hub, Rom und lokale Tests | Hub-/Weltenbau-Task | `src/hub/`, insbesondere `CellarService`, Lobby-Intro und `Rome/`, sowie die Rom- und Lobby-Harnesses. Änderungen an den gemeinsam eingebundenen `LobbyArchitecture`, `LobbyService`, `TrainingService` und `LobbyPadDefinitions` mit dem Arena-/Gameplay-Task abstimmen. Den Vertrag von `RomeLayout.training()` bis zur Initialisierung in Hub `Main.server.luau` zusammen prüfen. |
| 2. Profil und Shop | Daten-/Shop-Task | `PlayerDataSchema`, `InventoryService`, `PlayerDataService`, `PlayerDataResetConfig`, `ForgeDefinitions` und `HelmetDefinitions`. Der Shop-Aufruf und die Receipt-Verarbeitung in `src/hub/server/Rome/TownServices.luau` gehören für Käufe und Speicherung zu diesem Task. Änderungen an Profilübergabe oder Shop-Remotes mit dem Integrations-Task abstimmen. |
| 3. Cross-Place-Integration | Hub-/Arena-Integrations-Task | `ExperienceConfig`, `EnvironmentConfig`, die Rojo-Projekte, `GameProtocol`, `MatchTypes`, `MatchDefinitions`, `Remotes` sowie Ticket-, Matchrecord- und Teleport-Dienste. Bei Änderungen Hub-Erzeugung und -Versand, Arena-Zulassung und Rückkehr sowie DataStore-Handoff gemeinsam prüfen. Der Arena-/Gameplay-Task verantwortet Arena-spezifische Modi, Kämpfe, Spawns und Rückgabe der Match-Ergebnisse an die Integration. |
| 4. Abnahme und Freigabeentscheidung | Release-Verantwortung | Versionszuordnung beider Places, Befunde, Testergebnisse und freigegebene Folge-SHAs erfassen. Mit Hub, Arena und Daten/Shop die manuellen Nachweise am selben Release-Kandidaten abhaken. |

Parallel ausführbare Arbeiten können nach der Basisfestlegung beginnen, wenn die betroffenen Schnittstellen stabil sind. Überschneiden sich Änderungen an einem Modul oder Vertrag, führt der zuständige Task sie zusammen und prüft die Aufrufer in beiden Places. Jede Übergabe nennt Basis-SHA, freigegebene Folge-SHAs, berührte Schnittstellen, Tests und offene Punkte.

## Manuelle Abnahme

1. In lokalem Studio mit den getrennten Hub- und Arena-Builds die Rolle und DEV-Mocks im Output prüfen. Im Hub Ankunft, Respawn und Intro-Wegführung, Ottis Solo-Start, Kroko-/Schili-Portale mit Hin- und Rückweg, Gruppenpads in den Kellern und beide Trainingshöfe ablaufen. Auf Desktop, Touch und Gamepad prüfen.
2. Die Arena lokal mit mehreren Clients und passenden Mock-Modi durchspielen. Solo, Co-op und Team-Modi starten, Kämpfer-/Zuschauerrollen, Start und Ende eines Matches sowie einen Neustart des Match-Ablaufs prüfen. Für Profil und Shop mit Testprofilen oder Mocks Migration, Equip, Speichern und wiederholte Receipt-Zustellung prüfen.
3. In einer separat freigegebenen privaten DEV-Abnahme die veröffentlichten Versionen dokumentieren und Hub → reservierte Arena → Hub mit mehreren Testkonten prüfen. Matchmaking, Zuschauerbeitritt, fehlgeschlagene Reise mit Wiederherstellung und Persistenz über die Übergabe einschließen. Dieser Nachweis steht aus.

Für die nächste Arbeit zuerst die beiden roten Rom-Suiten mit dem Sollstand der Trainingshöfe und Läden abgleichen. Das liefert die lokale Grundlage für die Studio-Abnahme des Hub-Umbaus.
