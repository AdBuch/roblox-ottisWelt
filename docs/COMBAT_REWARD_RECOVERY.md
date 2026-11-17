# Kampfbelohnungen und Kampagnen-Recovery

Ausgangspunkt ist `27aae86a54734e140a67586fe7d371dce246b084` mit den Folgearbeiten für Speicher-API, Teleports und Käufe. Die Daten liegen weiterhin in der jeweiligen DEV- oder PROD-Umgebung. Profil v14 ergänzt `rewardIds` und `campaignClears`.

## IDs und Commit

Ein neuer Match-Durchlauf erhält eine serverseitige GUID. Auch RETRY erhält eine neue GUID. Die Belohnungs-ID enthält diese Match-ID, das Ergebnis und die UserId.

| Ereignis | Ergebnisanteil der ID |
| --- | --- |
| Boss besiegt | `boss/<Kapitel>` |
| Runde abgeschlossen | `round/<kapitelübergreifende Rundennummer>` |
| Zombie besiegt oder Assist | `zombie/<Kapitel>/<Runde>/<Spawnordinal>` |
| Gültiges PvP-Ergebnis oder PvE-Abschlussstatistik | `result` |

Die ID endet jeweils auf `/p<UserId>`. Boss- und PvP-Callbacks prüfen zusätzlich das aktuelle Kapitel beziehungsweise die lokale Match-Generation. Wiederholte Events und verspätete Events eines alten Kampfes können dadurch keinen neueren Kampf abschließen.

1. `RewardRecoveryService.submit` schreibt den vollständigen Anspruch mit Betrag, Statistikänderungen und optionalem Kapitel in `OttiRewardInbox_<DEV|PROD>_v1`, Schlüssel `player_<UserId>`. Erst das passende zurückgegebene Record bestätigt den Anspruch. Fehlgeschlagene oder zeitlich offene Versuche bleiben auf dem Quellserver für Wiederholungen registriert.
2. `recover` liest die offenen Ansprüche per `UpdateAsync`. `InventoryService.applyReward` erfasst Belohnung, Statistik, Kapitel und `rewardIds[id]` in einer Mutation. Ein bereits vorhandener Nachweis verhindert eine erneute Gewährung.
3. Die [Speicher-API aus Task 2](PLAYER_DATA_API.md) bestätigt diese Profilrevision per Flush unter ihrer Lease-Generation. Erst danach darf der entsprechende Postfach-Eintrag entfernt werden.
4. Hub und Arena versuchen Recovery regelmäßig erneut. Die Kampagne verlangt eine erfolgreiche Recovery vor der Ermittlung ihres Einstiegskapitels. Ein abwesender berechtigter Spieler behält seinen Anspruch im Postfach.

| Absturzpunkt | Wiederaufnahme |
| --- | --- |
| Vor bestätigtem Postfach-Write | Der Anspruch ist unbestätigt. Der laufende Quellserver versucht erneut zu schreiben. Ein vollständiger Prozessverlust kann einen bislang ausschließlich im Speicher vorhandenen Anspruch verlieren. |
| Nach bestätigtem Postfach-Write, vor Profil-Commit | Der nächste Server findet den Anspruch und schreibt Belohnung und Kapitel gemeinsam. |
| Nach Profil-Commit, vor Postfach-Löschung | Der gespeicherte `rewardIds`-Nachweis verhindert eine zweite Gewährung. Die erneute Löschung ist wiederholbar. |
| Postfach-Löschung schlägt fehl | Der bestätigte Profilstand bleibt erhalten. Ein späterer Versuch verarbeitet den offenen Eintrag anhand seines Nachweises. |
| Ein Gruppenmitglied kann nicht speichern | Andere Spieler behalten ihre bestätigten Commits. Für das betroffene Mitglied bleibt der bestätigte Anspruch offen. Der nächste gemeinsame Einstieg wartet auf seine Recovery. |

Die Prüfung wartet höchstens 20 Sekunden je Operation. Ein noch laufender Plattformaufruf bleibt registriert. Der Shutdown wartet innerhalb seines Budgets auf offene Ansprüche und protokolliert fehlende Bestätigungen.

## Checkpoint- und Gruppenregeln

- Checkpoints gehören jetzt dem Spieler und dem Modus `Solo` beziehungsweise `Coop`. Bestätigte Kapitel werden als Menge gespeichert. Der Einstieg folgt dem ersten fehlenden Kapitel und ist auf das dritte Kapitel begrenzt. Eine geänderte Zustellreihenfolge kann kein fehlendes Kapitel überspringen.
- Eine Gruppe beginnt beim niedrigsten persönlichen Einstiegskapitel ihrer aktuellen Mitglieder. Die Reihenfolge der Mitglieder spielt keine Rolle. Eine neue Person mit weniger Fortschritt senkt den Gruppeneinstieg, während die vorhandenen persönlichen Checkpoints erhalten bleiben.
- Bei einem Boss-Sieg bekommen anwesende Teilnehmer den Checkpoint. Solo-Spieler und überlebende Co-op-Spieler bekommen die bisher festgelegte Belohnung. Besiegte oder inzwischen getrennte Co-op-Spieler bekommen die Beitragsbelohnung, wenn sie dem Boss Schaden zugefügt haben. Anwesende Spieler ohne Beitrag bekommen ausschließlich den Checkpoint.
- Der ursprüngliche Roster bleibt bis zum Ende des Durchlaufs bekannt. Ein Disconnect entfernt die Person aus den lebenden Kämpfern, während ein bestätigter Anspruch unabhängig von ihrer Anwesenheit zugestellt werden kann.
- Vorhandene Checkpoints aus `OttiArenaCampaign_<DEV|PROD>_v1` werden beim Wiedereintritt mit genau dem alten Roster anhand stabiler Import-IDs in persönliche Kapitel übertragen. Ein früherer Roster-Schlüssel kann nicht aus einem veränderten Roster abgeleitet werden. Boss-Versuchszähler bleiben für die Intro-Auswahl im bisherigen Store.
- Ein technischer PvP-Abbruch einschließlich Disconnect eines Teilnehmers erzeugt keine Siege und keine Ergebnisbelohnung. Zeitablauf, Zielpunktzahl und reguläre Rundenentscheidungen der Regelmodule können ein gültiges Ergebnis erzeugen.
- Ein neuer Durchlauf beginnt am ermittelten Kapitel mit frischen Wellen und Gegnern. Projektilzustände, Specials und Boss-HP werden im Recovery-Pfad nicht erfasst.

## Nachweise und offene Abnahme

Die isolierten Tests decken doppelte Boss-Endevents, verspätete Kapitel- und Match-Callbacks, Disconnect eines Boss-Beiträgers, beide Commit-Absturzpunkte, Save-Fehler eines Mitglieds sowie gleiche und veränderte Roster ab. Sie verwenden die realen Reward-, Match- und Speicher-Module mit simulierten Roblox-Diensten.

Vor einem Release stehen folgende Nachweise aus.

1. In Studio-Mocks einen Co-op-Boss besiegen, einen Beiträger trennen und erneut beitreten lassen. Saldo, Bossstatistik und Kapitel nach Recovery kontrollieren.
2. In einer separat freigegebenen isolierten DEV-Umgebung den Wechsel Arena → Hub → Arena mit gleicher und veränderter Gruppe prüfen. Ein ausstehender Anspruch muss am Ziel genau einmal eingelöst werden.
3. Save- und Postfach-Fehler für ein Mitglied nachstellen. Bei Wiederholung müssen bereits bestätigte Mitglieder unveränderte Beträge behalten. Einen PvP-Disconnect und einen regulären Sieg jeweils auf Ergebnis und Statistik prüfen.

Die Historie im Profil wächst mit den Reward-IDs. Der zusätzliche Postfachverkehr und die Profilgröße benötigen Messungen unter realer DEV-Last. Eine spätere Archivierung muss die Deduplizierungsnachweise erhalten. Der Rollout auf v14 muss beide Places und laufende ältere Schreiber berücksichtigen. Historische Belohnungen ohne stabile IDs können nachträglich anhand der vorhandenen Profile nicht sicher rekonstruiert werden.

Für den nächsten Task gehören `RewardTypes`, `InventoryService.applyReward`, die Profilmigration und die Postfach-Bestätigung zum gemeinsamen Datenvertrag. Änderungen daran mit der Speicher- und Kaufverarbeitung abstimmen.
