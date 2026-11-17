# Profil- und Hub/Arena-Kompatibilität

Die verbindliche Basis ist `27aae86a54734e140a67586fe7d371dce246b084`. Die nachfolgenden lokalen Arbeiten für Speicherung, Teleports, Käufe und Kampf-Recovery sind enthalten. Dieser Stand verwendet Profil v14 und Protokoll 2.

## Unterstützte Versionen

| Komponente | Vertrag dieses Builds |
| --- | --- |
| PlayerDataSchema | `MinReadVersion = 0`, `MaxReadVersion = 14`, `WriteVersion = 14`. Fehlende Version entspricht dem Legacy-Format 0. Gebrochene, negative, als Text gespeicherte und neuere Versionsnummern werden abgelehnt. |
| InventoryService | Migriert unterstützte Formate auf einer Kopie. Erst nach erfolgreicher Prüfung ersetzt das Ergebnis die bisherige Tabelle. Ein zweiter Durchlauf erhält denselben Zustand. |
| PlayerDataService | Prüft das Format beim Claim, bei jedem Profil-Write im atomaren Update und bei einer Wiederaufnahme. Ein fehlgeschlagener Profil-Preflight sperrt den Write. `Incompatible` blockiert persistente Mutationen, Käufe und die Transfer-Vorbereitung. |
| GameProtocol | `Version = 2`, `MinCompatible = 2`, `MaxCompatible = 2`. Tickets, Match-Records und Registry tragen zusätzlich Lesegrenzen und Schreibversion. |

Der Empfänger prüft, dass beide Seiten das Protokoll des anderen unterstützen, beide die ausgegebene Profilversion lesen können und dieselbe Schreibversion verwenden. Für diesen Build bedeutet das Protokoll 2 und Schreibversion 14. Ticket und Match müssen denselben Vertrag und Modus tragen. Eine widersprüchliche oder fehlende Angabe führt zur Ablehnung.

## Kompatibilitätsmatrix

N bezeichnet hier die Release-Basis mit Protokoll 1 und Profil v12. N+1 bezeichnet diesen Gesamtstand mit Protokoll 2 und Profil v14.

| Hub | Arena | Ergebnis |
| --- | --- | --- |
| N | N | Verhalten der Release-Basis. Die neuen Schutzmaßnahmen gelten dort noch nicht. |
| N | N+1 | Arena lehnt alte Match-Records und Tickets mit `UPDATE` ab. |
| N+1 | N | Die alte Arena lehnt Protokoll 2 anhand ihrer bisherigen Protokollgrenze ab. Ihr alter Profillader kann jedoch bereits vor dieser Prüfung laufen. Dieser Mischbetrieb ist für neue Profildaten unsicher. |
| N+1 | N+1 | Zulässig bei übereinstimmendem Vertrag und gültigem Einmalticket. |
| Protokoll 2, Writer 13 | Protokoll 2, Writer 14 | Abgelehnt, auch wenn die nominelle Lesegrenze 14 angibt. |
| Protokoll 2 | Ein künftiges Protokoll 3 | Dieser Build lehnt Protokoll 3 ab. Eine Erweiterung der Grenzen erfordert eigene Tests für beide Richtungen. |

Bei einer Ablehnung erscheint eine Meldung über unpassende Spielversionen und die Aufforderung, einem aktuellen Server beizutreten. Im Hub wird ein inkompatibler Match-Record vor Profilfreigabe und Teleport abgewiesen. Eine Quellinstanz kann die Binärversion eines noch nicht gestarteten Zielservers anhand eines Match-Records allein nicht feststellen. Deshalb bleibt die nachfolgende Ablösung der alten Server erforderlich.

Bei der Rückreise Arena → Hub besitzt der alte Hub ebenfalls keinen neuen Vertragscheck. Ein Protokollwert im TeleportData-Hinweis könnte seine Binärdatei nicht ändern. Die Freigabe dieses Builds setzt deshalb die Ablösung sämtlicher alter Hub- und Arena-Writer voraus.

## Daten, Migrationen und Erweiterungen

- Die bestehenden Migrationen erhalten den Übergang von Coins zu Aura/Denarii, Rüstung, Helmen, Waffenexemplaren, Designs, Credits und Receipts. `Galea` wird ausdrücklich auf `SpartaHelm` abgebildet. Die Receipts aus der alten Liste werden vollständig in die Kaufnachweismenge übernommen.
- Unbekannte oberste Felder werden im Snapshot erhalten. Auch oberste Erweiterungen, die während einer Sitzung im Store hinzukommen, bleiben beim Write erhalten.
- Kann die Migration verschachtelte Daten oder Inventar-IDs nicht erhalten, verweigert sie den Datensatz. Dies gilt auch für ein unbekanntes neues Credit, Design, Exemplar oder einen zusätzlichen verschachtelten Schlüssel innerhalb eines bekannten Abschnitts. Die Prüfung darf diese Daten nicht still normalisieren oder entfernen. Die ausdrücklich dokumentierten Legacy-Umwandlungen bleiben zulässig.
- Neue Semantik und neue persistente Felder benötigen eine neue Profilversion und eine geprüfte Migration. Das Weiterreichen unbekannter oberster Felder ersetzt keine Unterstützung ihres Inhalts. Die Einhaltung von Store-Größe und Plattformbudget bleibt erforderlich.
- Profil v14 enthält die Änderungen für Kaufnachweise und Reward-Recovery. Der Rollback auf einen Writer, der Receipts abschneidet, Reward-IDs weglässt oder persönliche Kapitel nicht erhält, ist nach dem ersten v14-Commit ausgeschlossen.

## Gestufte Einführung und Rollback

Diese Schritte sind ein Freigabeplan. Deployments, Drain, Creator-Hub-Einstellungen und Serverablösungen wurden in diesem Task nicht ausgeführt.

1. Den finalen Kandidaten beider Places einschließlich Build- und Commit-Zuordnung abnehmen. Profil-Fixtures und die Kompatibilitätsmatrix isoliert prüfen. Store-Namen und Keys bei der Migration stabil halten.
2. Vor dem ersten produktiven Write neuer Datenfelder neue Käufe und neue Match-Starts im Rahmen einer separat autorisierten Betriebsmaßnahme sperren. Der vorhandene Kauf-Schalter sperrt nur neue Prompts. Bereits bezahlte Receipts müssen weiter erfüllt werden.
3. Alte Hub- und Arena-Instanzen vollständig drainen oder kontrolliert ablösen. Ausstehende Saves, Profilfreigaben und bezahlte Receipts abarbeiten. Ein bloßes Update beider Place-Dateien macht laufende alte Server nicht sicher.
4. Vor Aktivierung verifizieren, dass keine alten Writer mehr in derselben Umgebung aktiv sind. Noch offene alte Tickets und Match-Records gezielt auslaufen lassen beziehungsweise ihre autorisierte Ablösung planen. Solange alte Matches aktiv sind, darf die Annahme erfolgen, dass auch alte Writer weiterlaufen.
5. Beide neuen Places zunächst mit geschlossenen regulären Einstiegspfaden prüfen. Den neuen Datenvertrag erst nach bestätigter Ablösung der alten Writer für reguläre Spieler aktivieren. Danach neue Match-Starts und Kauf-Prompts freigeben.
6. Tritt vor dem ersten neuen Profil-Commit ein Fehler auf, kann der vorherige koordinierte Stand verwendet werden. Nach einem v14-Commit kommt als Rollback nur ein Build infrage, der v14 vollständig erhält, dieselben Lease-/Fencing-Regeln verwendet und Protokoll 2 versteht. Andernfalls die Einstiegspfade geschlossen halten und vorwärts korrigieren.

Ein vorbereitender Guard-Build kann die Ablösung erleichtern, muss aber separat geprüft werden. Die alten Release-Binaries enthalten diese Guards nicht. Ein ungeprüfter Reader/Writer-Mix ist kein freigegebener Einführungsschritt.

## Nachweise und Übergabe

Die isolierten Tests prüfen Legacy-Profile v1, v4, v9, v11, v12 und v13 sowie v14, zweimalige Migration, unbekannte neue Felder, einen neueren Datensatz unter einer laufenden Lease, einen begrenzten alten Writer sowie beide Transferrichtungen. Ticket und Match werden mit echten Modulen und simuliertem MemoryStore geprüft.

Manuell stehen die Statusmeldung und Shop-Sperre in Studio, ein privater DEV-Durchlauf mit beiden kompatiblen Places und die Ablehnung kontrolliert gemischter Builds aus. Vor einem Release muss die Betriebsverantwortung die Instanzinventur und Ablösung bestätigen. Für den nächsten Task gelten `PlayerDataSchema`, `GameProtocol` und die Capability-Felder in Tickets/Records als gemeinsamer Datenvertrag.
