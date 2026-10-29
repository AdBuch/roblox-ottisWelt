# Drei Heldenlobbys und Hypogeum

Branch: `feature/lobby-und-rom`.

Die drei Hallen greifen den ursprünglichen 80 × 72 Studs großen Lobbyraum wieder auf:
Gewölberippen, Säulen, Monument mit Inschrift, Mosaik, Banner, Bänke und ein freier
Arenazugang. Otti, Schilibitzli/Schili und Krokero/Kroko erhalten jeweils eine vollständige
Halle. Die beiden ehemaligen Tribünentreppen pro Halle führen ins Hypogeum.

## Wege und Ausrüstung

Der geschlossene Rundgang verbindet die seitlichen Hallentüren. Reihenfolge:
Otti – Schildshop – Schili – Rüstungsshop – Kroko – Waffenshop – Otti.
Die Shops haben eigene Wände, Türen, Decken und die bestehenden neun Kampfmosaike.
Es gibt keinen durchgehenden Boden über den Treppenschächten. Massive Brüstungen
begrenzen die Öffnungen; Verbindungsgänge haben Böden, Seitenwände und Decken.

## Spielzugänge und Gruppen

Jede Halle hat einen Arenagang mit zwei seitlichen Kammern anstelle der alten Käfigbuchten.
Links entsteht eine eigene Zombie-Co-op-Gruppe, rechts liegen bei Schili und Kroko die
beiden Team-Sammelbereiche. Ottis rechte Kammer bietet direkte Zugänge zu TIME BATTLE,
FIRST TO und ELIMINATION. Betreten eines seitlichen Gruppenmosaiks bildet dessen öffentliche
Party; Verlassen löst die Mitgliedschaft, sofern die Gruppe nicht in einer Warteschlange ist.
READY, LEAVE, START GROUP und FIND PLAYERS verwenden die bestehenden Party- und Matchfunktionen.

START SOLO FIGHT erfordert F an einem eigenen Schild. Vorbeilaufen im Hauptgang startet
keinen Kampf. Menü und Raumzugänge greifen auf dieselben Dienste zu. Die Tafeln zeigen
Mitglieder, Bereitschaft und Warteschlange; das Menü erhält die gleichen Party-Snapshots.
Bestehende private Partys können weiterhin über ihren Leiter starten. Alle drei Bosskämpfe
und Live-Zuschauen bleiben über Menü und ausgeschilderte Zugänge erreichbar.

## Hypogeum

Ein deterministisches Netz aus 13 × 13 Zellen mit Hauptachsen und Querverbindungen liegt
unter dem Kolosseum. Dazu gehören ein zentraler Treffpunkt, gewölbte Gangportale,
Stützpfeiler, Wegweiser, eine westliche Gefangenengalerie mit sechs getrennten Zellen
und ein östlicher Trainingsbereich mit sechs offenen Übungsbuchten. Die dekorativen
Gefangenen und die angreifbaren, regenerierenden Trainingszombies verwenden getrennte Tags.
Training verursacht keinen Spielerschaden und vergibt keine regulären Kampfbelohnungen.

## Gemeinsame Arena und Tore

`src/shared/ColosseumLayout.luau` enthält Maße, Höhen, Heldenzugänge und den Torstil.
Hub und Kampf-Place verwenden tatsächlich beide `src/server/Arena.luau` als Builder.
Der Sandboden folgt nun der Arenaellipse; echte Öffnungen in Podium, Sitzreihen und
Außenwand lassen die Zugangstunnel durch. Die übrige Arena und ihre Kampfsysteme bleiben erhalten.

`GateStyle = "Grille"` zeigt Gitter mit einer transparenten Kollisionsfläche.
`GateStyle = "Solid"` zeigt blickdichte Holzflügel. Beide Varianten versperren den Weg.
`ColosseumGate.build` erlaubt auch eine explizite Stilwahl pro Aufruf. Der Blick durch
Gitter zeigt die lokale Arena; Kämpfe auf reservierten Servern werden über WATCH LIVE besucht.

## Bauen und prüfen

```powershell
./scripts/build-places.ps1
./scripts/test-lobby-ring.ps1 -LuauPath <luau.exe>
./scripts/test-pad-teams.ps1 -LuauPath <luau.exe>
./scripts/test-combat-animation.ps1 -LuauPath <luau.exe> -CompilePath <luau-compile.exe>
./scripts/test-passive-momentum.ps1 -LuauPath <luau.exe>
```

Der Geometrietest führt die echten Arena- und Lobby-Builder mit einem Roblox-Adapter aus.
Er prüft Gangmitten, 276 Treppenpositionen auf Kopffreiheit, Sicherheitsbereiche,
Shopfreigaben, Heldenräume, Gruppenkammern und die Erreichbarkeit aller Labyrinthzellen.
Der Adapter ersetzt keine Prüfung der Roblox-Physik.

`build/OttiHub.rbxlx` ist die lokale Hub-Testdatei. Der Studio-Client-Audit
`scripts/studio-lobby-audit.luau` lässt die Figur die sechs Abgänge hinunter und hinauf
laufen und stellt danach Position, Kamera und Eingabesteuerung wieder her. Der Audit
gehört ausschließlich in die Client-Kommandoleiste eines laufenden Studio-Tests.

`build/OttiArena.rbxlx` unterstützt weiterhin die Studio-Bossauswahl an den drei Podesten.
`ExperienceConfig.Studio.ArenaMockMode` steht auf `BOSS_SOLO`. In Studio werden im Hub
Reservierungen simuliert; Teleports zwischen den beiden Places benötigen veröffentlichte Places.

## Verifizierter Stand am 29. Oktober 2026

- Beide Place-Dateien erfolgreich gebaut; geänderte Luau-Module kompiliert.
- Geometrieprüfung mit echten Buildern: Gangmitten, 276 Treppenpositionen, alle 169
  Labyrinthzellen und die zwölf bestehenden Zuschauer-Spawnpunkte. Beide Torvarianten erzeugt.
- Bestehende Prüfungen: 51 Team-Pad-Checks, 68 Animationschecks sowie 85 Momentum-Checks bestanden.
- Hub in Roblox Studio gestartet. Alle drei Heldenräume, zentraler Treffpunkt und Sicht
  durch das Gitter auf die gemeinsame Arena visuell kontrolliert. Spawn-Blick und Beleuchtung korrigiert.
- Spielfigur alle sechs Abgänge abwärts und aufwärts bewegt. Ein zunächst fehlgeschlagener
  Lauf wurde am betroffenen Kroko-Abgang erfolgreich wiederholt. Der Audit wartet
  deshalb vor dem Loslaufen auf die Serverreplikation und wählt den niedrigsten Schritt eindeutig.
- Physischer Beitritt zur öffentlichen Co-op-Party erscheint im Menü; READY-Umschaltung
  und Verlassen bestätigt. TIME BATTLE, FIRST TO und ELIMINATION erfolgreich eingereiht
  und anschließend abgebrochen. Testparty und Warteschlangen aufgeräumt, Kamera freigegeben.

Ein vollständiger Kampfstart mit mehreren Studio-Clients sowie veröffentlichte Cross-Place-
Teleports wurden in diesem Durchlauf nicht geprüft. Die letzten Dekorationsanpassungen
(zusätzliche Hypogeum-Portale, beidseitige Wegweiser und versetzte Shop-Wandbilder)
werden bei einem neuen Play-Durchlauf aus den aktualisierten Quellen erzeugt.
