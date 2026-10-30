# Drei Heldenlobbys und Hypogeum

Branch: `feature/lobby-und-rom`.

Die drei Hallen greifen den ursprünglichen 80 × 72 Studs großen Lobbyraum wieder auf:
Gewölberippen, Säulen, Monument mit Inschrift, Mosaik, Banner, Bänke und ein freier
Arenazugang. Otti, Schilibitzli/Schili und Krokero/Kroko erhalten jeweils eine vollständige
Halle. Die beiden ehemaligen Tribünentreppen pro Halle führen ins Hypogeum.

## Wege und Ausrüstung

Der geschlossene Rundgang verbindet die seitlichen Hallentüren. Reihenfolge:
Otti – Schildshop – Schili – Rüstungsshop – Kroko – Waffenshop – Otti.
Jeder Abschnitt ist ein durchgehender Gang mit Gehrungen an jedem Knick: gerade aus der
Hallentür, entlang des Rings und gerade von Tür zu Tür durch den Shop. So bleiben Boden, Wände
und Decke an jeder Biegung geschlossen.
Die Shops haben eigene Wände, Türen, Decken und die bestehenden neun Kampfmosaike.
Es gibt keinen durchgehenden Boden über den Treppenschächten. Brüstungen umschließen die
Schächte auf drei Seiten, offen bleibt nur der Treppenantritt.

## Ein- und Ausgänge

Jede Heldenhalle hat in der Rückwand eine Tür. Dahinter führt eine Treppe unter dem Boden
hindurch nach draußen und endet in einem Portalbogen mit dem Namen der Halle. Zwischen den
Hallen führen drei Treppen aus dem Hypogeum nach Osten, Westen und Norden hinauf. Sie beginnen
an der jeweils äußersten Zelle hinter einem Bogen mit EXIT-Schild. Draußen liegt vorerst
eine endlose Granitplatte. Die Treppenschächte sind ausgeschnitten und von Brüstungen umgeben.
Die Porta Roma und die Straße nach Rom sind entfallen.

## Start, Spielzugänge und Gruppen

Ottis Halle ist der Startbereich der alten Lobby: Beide Spawns stehen auf der freien Mittelachse
und blicken zum Ausgang, darüber hängt THE ARENA, ein Goldstreifen führt über den Boden zum
Gang. Ottis Arenagang hat keine Seitenkammern und eine lange, flache Rampe (halbe Stufen).
Wer in irgendeiner Halle bis ans Arenator läuft, startet einen Solo-Zombie-Lauf, ohne Taste
und ohne Menü. Der Weg vom Spawn bis zum Tor dauert etwa fünf Sekunden.

Schili und Kroko behalten ihre seitlichen Kammern: links eine Zombie-Co-op-Gruppe, rechts den
Team-Sammelbereich. Die Otti-Co-op-Gruppe (`ZombieCoop`) und die Zugänge zu TIME BATTLE,
FIRST TO und ELIMINATION stehen jetzt am Treffpunkt im Hypogeum. Betreten eines Gruppenmosaiks
bildet dessen öffentliche Party; Verlassen löst die Mitgliedschaft, sofern die Gruppe nicht in
einer Warteschlange ist. READY, LEAVE, START GROUP und FIND PLAYERS verwenden die bestehenden
Party- und Matchfunktionen. Die Tafeln zeigen Mitglieder, Bereitschaft und Warteschlange.

## Intro

`LobbyIntroService` zeigt neuen Spielern nur den Weg in die Arena. Nach jedem beendeten Kampf
erscheint bei der Rückkehr genau eine neue Stufe mit Hinweis-Banner und goldenem Bodenpfeil:
1 Shops, 2 Schili- und Kroko-Halle (Gruppen), 3 Hypogeum, 4 Bosskämpfe und Live-Kämpfe.
Die passenden Schilder in Ottis Halle tragen das Attribut `IntroStage` und bleiben lokal
verborgen, bis der Spieler die Stufe erreicht hat. Gespeichert wird die gezeigte Stufe
(`introSeen`); wer schon mehr als vier Kämpfe hatte, überspringt das Intro.
`ExperienceConfig.Studio.IntroStage` (0–4) erzwingt in Studio eine Stufe.

## Nach dem Kampf

Es gibt keine automatische Rückkehr mehr. Auf der Tribüne erscheinen RETRY und BACK TO LOBBY.
RETRY startet in Zombie-Modi einen neuen Lauf auf demselben Arena-Server, sobald alle
Kämpfer gewählt haben, mit allen, die RETRY gewählt haben. In Studio gilt das auch für
Team-Modi. Team-Modi bieten sonst nur BACK TO LOBBY. Wer nach 120 Sekunden nicht gewählt
hat, kehrt in den Hub zurück.
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
Der Sandboden folgt der Arenaellipse in Streifen von einem Stud (ein Zylinderteil wäre kreisrund und
ließ an beiden Arenaenden je 15 Studs ohne Boden). Echte Öffnungen in Podium, Sitzreihen und
Außenwand lassen die Zugangstunnel durch. Die übrige Arena und ihre Kampfsysteme bleiben erhalten.

`GateStyle = "Grille"` zeigt Gitter mit einer transparenten Kollisionsfläche.
`GateStyle = "Solid"` zeigt blickdichte Holzflügel. Beide Varianten versperren den Weg.
`ColosseumGate.build` erlaubt auch eine explizite Stilwahl pro Aufruf. Der Blick durch
Gitter zeigt die lokale Arena; Kämpfe auf reservierten Servern werden über WATCH LIVE besucht.

## Kolosseum und Umgänge

Acht Sitzränge in zwei Etagen (Unterrang 1–4, Oberrang 5–8 über einer höheren Brüstung),
je 14 Studs tief und 7 hoch. Zwei Treppen führen vom unteren Umgang bis ganz nach oben.
Hinter dem obersten Rang liegen die Umgänge: einer auf Platzhöhe, schmale Balkone hinter den
Statuenbögen der 2. und 3. Etage und der überdachte obere Umgang auf Höhe des obersten Rangs,
offen zu den Sitzen hin. Vier Treppenanlagen mit je drei Läufen verbinden die Ebenen.
Von jeder Umgangsebene führen vier Vomitorien auf die Ränge, eines pro Viertel und Ebene.
Vom Erdgeschoss geht es zum unteren Zuschauergang, vom 2. Geschoss zum mittleren Gang und vom
3. Geschoss auf Rang 5. Die Durchgänge steigen mit Stufen von höchstens einem Stud. Geländer sichern
die Balkonkanten bis an die Vomitorienbrücken, das Treppenloch zum oberen Umgang, die offene
Seite jeder Umgangstreppe, die Enden der Treppenläufe zum offenen Treppenhaus, die Brücken über
das Treppenhaus und beide Tribünentreppen. Über jedem Geländer und jeder Brüstung reicht ein
unsichtbarer Aufsatz 17 Studs über den Boden, über den Treppen der Lobby 8,5 Studs. So springt
niemand darüber oder von einer höheren Fläche darauf. Die Attikafenster sind verglast.
Die Außenfassade folgt dem römischen Vorbild: drei Bogenetagen mit Halbsäulen und Gesimsen,
eine Attika mit einem Fenster pro Joch und 64 Joche. In jedem Bogen der 2. und 3. Etage steht
eine Marmorstatue im Roblox-Stil, also 128 Statuen. Rundherum liegt die Granitplatte: ein Ring
aus Platten bis 295 Studs vor der Fassade, in den die Treppenschächte geschnitten werden
(`Arena.cutGround`), dahinter große Kacheln bis 4096 Studs.
Die Erdgeschossbögen sind im Kampf-Place gesperrt; der Hub öffnet sie mit `Arena.setGroundExits(true)`.

Die Ränge reichen über Hallen, Shops und Rundgang. Der Kellerboden liegt auf −28,
das Hypogeum auf −60, und kein Kellerteil ragt über den Boden. Das Hypogeum umfasst nur
noch die Zellen unter dem Kolosseum.
## Bauen und prüfen

```powershell
./scripts/build-places.ps1
./scripts/test-lobby-ring.ps1 -LuauPath <luau.exe>
./scripts/test-pad-teams.ps1 -LuauPath <luau.exe>
./scripts/test-combat-animation.ps1 -LuauPath <luau.exe> -CompilePath <luau-compile.exe>
./scripts/test-passive-momentum.ps1 -LuauPath <luau.exe>
```

Der Geometrietest führt die echten Arena- und Lobby-Builder mit einem Roblox-Adapter aus.
Er prüft Gangmitten, 576 Treppenpositionen auf Kopffreiheit, Sicherheitsbereiche,
Shopfreigaben, Heldenräume, Gruppenkammern und die Erreichbarkeit aller Labyrinthzellen.
Er prüft außerdem Boden, Kopffreiheit und Stufenhöhe in allen zwölf Vomitorien, den freien
Startgang mit flacher Rampe, die Torauslöser und die sechs Ausgangstreppen.

Die Lückensuche lässt eine Spielfigur (5 Studs hoch, Stufen und Sprünge bis 6,2 Studs) von allen
Spawns aus über die Oberseiten aller festen Teile laufen, abgetastet in Säulen von 1,5 Studs. Sie
schlägt fehl, wenn man irgendwo ins Leere fällt oder tiefer als 12 Studs stürzt. Vom Hallen-Spawn
aus muss sie die Granitplatte, den oberen Umgang, das Hypogeum und jede Ausgangstreppe erreichen.
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
