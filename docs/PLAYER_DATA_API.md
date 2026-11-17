# Spielerdaten in Hub und Arena

Die beiden Places verwenden dieselbe serverseitige Speicher-API und pro Umgebung denselben DataStore. Der Schlüssel lautet `player_<UserId>`. [PlayerDataSchema v14](../src/shared/PlayerDataSchema.luau) speichert Kaufnachweise, Reward-IDs und persönliche Kampagnenkapitel. Der Gameplay-Abschnitt `session` speichert Aura, Denarii und Zeitangaben der Spielsitzung.

## Schnittstelle

| Operation | Vertrag |
| --- | --- |
| `PlayerDataService.load(player)` | Wird beim Beitritt aufgerufen und kann warten. Holt die Lease per `UpdateAsync`, migriert das Profil und setzt danach `Loaded`. Bei einer unbestätigten Übernahme oder einem unlesbaren Profil bleibt der Fortschritt sitzungsgebunden (`Unsaved`). Während des Ladens lassen sich Aura- und Denarii-Belohnungen vormerken. Andere Mutationen warten auf ein verfügbares Profil. |
| Mutationen über `InventoryService` | Die Methoden ändern den Speicherzustand und erhöhen synchron die lokale Revision. Rückgaben wie ein erfolgreicher Kauf mit Denarii bestätigen die Mutation im Speicher. Während Transfer, Freigabe und nach Lease-Verlust blockiert die Mutationsprüfung Änderungen. Getter für Waffenexemplare und Schilddesigns liefern Kopien. |
| `PlayerDataService.flush(player)` | Wartet auf laufende Writes. `true` bestätigt einen dauerhaften Commit mindestens bis zu der Revision, die bei Aufruf schon vorlag. `false` bedeutet, dass der Aufrufer keine Bestätigung hat. Bei 15 Sekunden Wartezeit kann der laufende Write weiterhin ausstehen. `Mock` und `Unsaved` liefern immer `false`. |
| `PlayerDataService.beginTransfer(player)` | Friert das Profil ein und speichert die ausstehende Revision zusammen mit der Lease-Freigabe. Erst ein bestätigtes Ergebnis erlaubt den Teleport. Bei Gruppen prüft der Aufrufer vor dem Absenden zusätzlich `isTransferPrepared(player)`. |
| `PlayerDataService.cancelTransfer(player)` | Startet nach einem fehlgeschlagenen oder abgelaufenen Transfer die Wiederaufnahme. Sie prüft atomar die bisherige Lease oder den eigenen Freigabe-Commit. Nach einem erfolgreichen Erwerb nimmt das Profil wieder Mutationen an. |
| `PlayerDataService.releaseSession(player)` | Wird beim Verlassen und im Shutdown eingesetzt. Wartet auf ein laufendes Laden und frühere Writes. `true` bestätigt die abschließende Freigabe. Eine unbestätigte Freigabe bleibt registriert, wird bei vorliegender Lease erneut versucht und im Shutdown nach Ablauf des Budgets protokolliert. |

`isReady` beschreibt die Spielbarkeit einschließlich sitzungsgebundener Profile. `canPersist` beschreibt eine aktuell nutzbare persistente Sitzung. Für eine dauerhafte Zusage, etwa `PurchaseGranted` für einen Robux-Receipt, muss `flush` erfolgreich sein.

## Lease und Commit

- `lock.server` enthält den GUID-Token pro Profil-Ladevorgang. `leaseEpoch` steigt bei jeder neuen Übernahme und bleibt nach einer Freigabe im Datensatz. Jeder Write prüft Token und Epoch atomar gegen den aktuellen Datensatz. Auch eine bereits wieder freigegebene neuere Lease sperrt alte Writes und Transfer-Abbrüche aus.
- `lock.expiresAt` erlaubt eine Übernahme nach fünf Minuten ohne Erneuerung. Der Autosave erneuert auch unveränderte Leases alle 120 Sekunden. Eine konkurrierende Sitzung gibt die Übernahme nach rund 20 Sekunden auf, wenn die fremde Lease weiterhin gültig ist. Alte Locks ohne `expiresAt` laufen anhand von `lock.at` nach 30 Minuten aus. Die Zeit entscheidet über die Übernahmemöglichkeit, Token und Epoch über die Schreibberechtigung.
- Pro Sitzung läuft höchstens ein Write. Jeder Snapshot deckt eine feste Revision ab. Die bestätigte Revision wird nur bei passender Epoch, passendem `saveId` und erwarteter Lease (gehalten oder freigegeben) erhöht. Eine zwischenzeitliche Mutation bleibt für den nächsten Snapshot offen. Ein Retry kann seinen bereits gespeicherten `saveId` erkennen, falls die Antwort verloren ging.
- `PlayerRemoving` friert das Profil vor dem Warten ein. `BindToClose` verfolgt laufende Loads, Writes und ausstehende Freigaben bis zu 25 Sekunden, in Studio bis zu 5 Sekunden. Bei einem Plattformabbruch oder anhaltender Nichtverfügbarkeit bleiben zuletzt bestätigte Daten abrufbar. Für offene Revisionen fehlt dann die Bestätigung.

## Übergabe an Task 6

- Das persistente Kaufdatenformat v13 und die Migration stehen in [PURCHASE_RECEIPTS.md](PURCHASE_RECEIPTS.md). `lock`, `leaseEpoch`, `saveId` und `savedAt` gehören exklusiv zum Speicher-Dienst.
- Profil v14 ergänzt die in [COMBAT_REWARD_RECOVERY.md](COMBAT_REWARD_RECOVERY.md) beschriebenen Reward-Nachweise und Checkpoints. Die Mutation und ihr Nachweis werden gemeinsam gespeichert.
- Wenn Task 6 das Nutzdatenformat erweitert, müssen Leser und Schreiber beider Places dieselbe Migration verstehen. Der Speicher-Dienst verweigert Profile mit einer höheren Schema-Version. Zuständigkeit für Lease-Metadaten und Commit-Bestätigung liegt beim Daten-Task.
- Alte Server der Release-Basis können einen Lock nach kurzer Wartezeit übernehmen oder ein Profil ohne Lock überschreiben. Vor einem gemeinsamen Rollout muss Task 6 eine koordinierte Umstellung für beide Places und laufende alte Schreiber planen. Der Mischbetrieb mit der bisherigen Storage-Implementierung hat keinen Fencing-Nachweis.

## Manuelle Abnahme

1. In lokalem Studio Hub und Arena mit Mock-Profilen öffnen. Laden, Ausrüsten und simulierte Shop-Käufe prüfen. `Mock` im Status kontrollieren.
2. In einer separat freigegebenen, isolierten DEV-Umgebung mit beiden neuen Builds und einem Testprofil den Wechsel Hub → Arena → Hub prüfen. Vor dem Transfer eine dokumentierte Änderung auslösen und am Ziel Saldo, Ausrüstung und die fortgesetzten Sitzungszähler vergleichen.
3. In derselben Testumgebung einen verzögerten oder fehlgeschlagenen Write, einen erneuten Beitritt und einen abgebrochenen Transfer nachstellen. Bei verweigertem Commit bleibt der Spieler am Ausgangsort. Prüfen, dass das Ziel den zuletzt bestätigten Stand erhält und der alte Server nach einer neueren Lease-Übernahme keine Daten verändern kann.
4. Für einen simulierten Receipt die gleiche ID nach einer fehlenden Bestätigung erneut zustellen. Der Zuschlag erscheint einmal und die Bestätigung erst nach erfolgreichem Flush.
