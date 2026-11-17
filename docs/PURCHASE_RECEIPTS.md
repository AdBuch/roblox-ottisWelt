# Bezahlte Developer Products

[PurchaseService](../src/server/PurchaseService.luau) installiert `MarketplaceService.ProcessReceipt` je Server einmal. Hub und Arena verwenden denselben Produktkatalog und dasselbe Profil pro Umgebung. Produkt-ID, Spieler und PurchaseId kommen aus dem Roblox-Callback. Unbekannte Produkte, abwesende Spieler, unbrauchbare Profile und Speicherfehler liefern `NotProcessedYet`. Ein Callback kann beim Beitritt bis zu 20 Sekunden auf das Laden warten. Roblox liefert offene Receipts unter anderem beim erneuten Beitritt. [Roblox-Referenz zu ProcessReceipt](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService#ProcessReceipt)

## Commit und Wiederholung

1. Die [Speicher-API](PLAYER_DATA_API.md) prüft die persistente Sitzung. `InventoryService.applyPurchase` prüft synchron die PurchaseId und erfasst bei Bedarf Denarii, Guthaben oder Helm und Kaufnachweis als eine Mutation.
2. `PlayerDataService.flush` bestätigt die Revision mit dem Snapshot des gemeinsamen Profil-Datensatzes. Jede Receipt-Zustellung verlangt diese Bestätigung, einschließlich lokaler Duplikate bei einem vorangegangenen fehlgeschlagenen Save.
3. Erst der bestätigte Flush liefert `PurchaseGranted`. Anzeige, Waffenmodell und die optionale Nutzung eines bereits gewährten Schmiedeguthabens folgen danach. Bei einem Abbruch bleibt das gespeicherte Guthaben für die spätere Einlösung verfügbar.

| Zeitpunkt des Abbruchs | Verhalten bei erneuter Zustellung |
| --- | --- |
| Vor der Mutation | Die aktuelle Sitzung gewährt und speichert den Kauf. |
| Nach der Mutation, vor dem Commit | Auf demselben Server bleibt die ausstehende Revision erhalten. Nach einem Prozessabbruch lädt der nächste Server den letzten bestätigten Stand und gewährt erneut, falls darin weder Kaufnachweis noch Leistung liegen. |
| Nach dem Commit, vor der Antwort an Roblox | Das geladene Profil enthält Leistung und PurchaseId gemeinsam. Die erneute Zustellung bestätigt per Flush und gewährt kein zweites Mal. |
| Parallel auf zwei Servern | Die Lease aus Task 2 und ihre Generation schützen den Datensatz. Der alte Server kann nach der Übernahme keinen alten Snapshot mehr schreiben. |

## Schema und Betrieb

- Profil v13 speichert `receipts` als `PurchaseId → true` im selben Profil wie die Leistung. Die Migration übernimmt sämtliche noch vorhandenen v12-IDs und entfernt Duplikate. Bereits von v12 verworfene IDs lassen sich aus dem Profil nicht rekonstruieren. Der kontrollierte Testreset überspringt Profile mit Kaufhistorie.
- Die Menge wächst mit der Kaufhistorie. Roblox begrenzt einen gespeicherten Wert auf 4.194.304 Zeichen je Schlüssel. Bei einem abgewiesenen Write bleibt das Receipt offen. Vor größerem Kaufvolumen Profilgrößen überwachen und bei Bedarf eine verlustfreie Archivierung planen. [Roblox DataStore-Grenzen](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits)
- `PurchaseConfig.PromptsEnabled = false` sperrt neue Prompts in der Schmiede und im Helmladen. Die Einstellung gilt für Server, die mit dieser Konfiguration laufen. Offene bezahlte Receipts werden unabhängig davon abgearbeitet. Produktzuordnungen für bereits bezahlte Produkte im Katalog belassen. Studio-Mock-Käufe verwenden ausschließlich sitzungsgebundene Daten.

## Manuelle Abnahme und Übergabe

1. Mit isolierten Studio-Mocks die Schmiede und den Helmladen bei ein- und ausgeschaltetem Schalter prüfen. Die Angebote mit ID `0` dürfen ausschließlich im Studio-Mock simuliert werden.
2. Im freigegebenen isolierten Mehrplace-Test synthetische Receipts und simulierte Speicherfehler verwenden. Einen fehlgeschlagenen Flush, Wiederbeitritt in der Arena und Rückkehr in den Hub prüfen. Je PurchaseId müssen Saldo, Guthaben oder Helm und Nachweis genau einmal im bestätigten Stand erscheinen.
3. Hub und Arena gemeinsam auf v13 umstellen und ältere aktive Schreiber bei der Freigabe berücksichtigen. Vor Einsatz echter Produkte die autorisierten Produktzuordnungen und das Verhalten bei offenen Roblox-Receipts abnehmen.
