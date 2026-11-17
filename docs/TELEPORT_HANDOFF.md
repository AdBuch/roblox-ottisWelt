# Hub–Arena-Transfer

`TeleportUtil` besitzt pro Spieler genau einen Ablauf auf dem Quellserver. Hub und Arena übergeben Ziel und Fehlerbehandlung. Die [Speicher-API aus Task 2](PLAYER_DATA_API.md) liefert den dauerhaften Commit und gibt die Lease frei.

| Zustand | Auslöser |
| --- | --- |
| `Preparing` | Die Quelle nimmt den Auftrag an, ermittelt das Ziel und wartet auf Profil-Load beziehungsweise laufende Saves und den bestätigten `beginTransfer`. Gruppenmitglieder bereiten ihre Profile parallel vor. |
| `Travelling` | Direkt vor jedem Roblox-Aufruf bestätigt `isTransferPrepared`, dass das Profil weiter eingefroren und der Commit bestätigt ist. Nur diese Mitglieder kommen in den Aufruf. |
| `Arrived` | Im Hub setzt der lokale `PlayerAdded`-Ablauf den Zustand. Die Arena setzt ihn nach erfolgreicher serverseitiger Ticketprüfung. Das Entfernen des Spielers an der Quelle sagt nur aus, dass er dort weg ist. |
| `Failed` | Ablehnung, ausgeschöpfte Retries oder Ablauf der 40-Sekunden-Frist. Die Quelle startet sofort die Profilwiederaufnahme und stellt Hub-Aktionen beziehungsweise den Arena-Rückkehrbutton wieder zur Verfügung. Kann die Speicherung die Lease innerhalb weiterer 20 Sekunden nicht bestätigen, bleibt das Profil für die Sitzung als `Unsaved` nutzbar. Bei nachgewiesenem Verlust der Lease greift der Schutz aus Task 2. |

Roblox liefert je fehlgeschlagenem Spieler neue `TeleportOptions`. Die Quelle ordnet den Callback nach Spieler, Place-ID und Kennung des jeweiligen Versuchs zu. Ein Retry übernimmt das serverseitige Routing aus dem Callback. In einer Gruppe kann so ein Mitglied zum selben Ziel erneut versuchen, während die übrigen weiterreisen. Der Ablauf serialisiert Roblox-Aufrufe pro Spieler. [Roblox-Referenz zu TeleportInitFailed](https://create.roblox.com/docs/reference/engine/classes/TeleportService#TeleportInitFailed)

Nach Ablauf der Frist ist eine bereits an Roblox übergebene Abreise unter Umständen noch offen. Die Quelle setzt den Spieler lokal wieder frei und blockiert weitere Reisen, bis Roblox für genau diesen Versuch einen eindeutigen Fehler meldet oder der Spieler den Server verlässt. Bei ausbleibender Rückmeldung kann der Spieler für einen erneuten Transfer neu beitreten.

`TeleportData` enthält einen Match-Schlüssel für die Suche nach dem serverseitigen Match, optionale Anzeigehinweise für den Hub und die Versuchkennung für Roblox-Callbacks an der Quelle. Der Empfänger verwirft unbekannte Felder. Die Arena prüft Match, reservierten Server, Einmalticket und Spielerkennung. Rolle und Team stammen aus serverseitigen Daten. Belohnungen bleiben beim Match- und Speicherpfad. Der reservierte Zugriffscode steht ausschließlich in serverseitigen Teleport-Optionen.

## Manuelle Abnahme und Übergabe

1. In Studio mit lokalen Mocks die Statusanzeige prüfen. In Hub und Arena sollen nach einem simulierten endgültigen Fehler Lobby-Aktionen beziehungsweise der Rückkehrbutton wieder verfügbar sein.
2. In einer separat freigegebenen privaten DEV-Umgebung beide Places mit Testprofilen prüfen. In beiden Richtungen einen ausstehenden Save verzögern und danach die bestätigte Änderung am Ziel kontrollieren. Eine verweigerte Freigabe muss den Spieler am Ausgangsort lassen.
3. In derselben Umgebung eine Gruppe mit einem fehlschlagenden Mitglied, Abbruch während eines Retry und einen späten Roblox-Callback prüfen. Die anderen Mitglieder sollen unabhängig ankommen. An der Quelle dürfen pro Spieler keine konkurrierenden Reisen entstehen.
4. Für Folgearbeiten die Absicherung von Match- und Ticket-Zustand in der Arena erhalten. Änderungen an den Anzeigehinweisen müssen mit dem Ziel-Place abgestimmt werden. Die private DEV-Abnahme steht aus.
