# Drei Heldenlobbys (historisch: vor dem Kolosseum)

Branch: `feature/lobby-und-rom`.

> **Stand 9. November 2026: überholt.** Die Lobbys sind jetzt **im** Kolosseum unter den Rängen
> eingebaut, die freistehenden Hallen und die endlose Granitplatte im Hub sind entfernt, rundherum
> liegt Rom. Aufbau, Anker, Wegmessung (8,7 s → 2,7 s) und Prüfungen: `docs/ROM_INSEL.md`.
> Die Abschnitte zum Kolosseum, zu Treppenhäusern, Vomitorien, Toren und zum Nach-dem-Kampf-Ablauf
> unten gelten weiter; die Beschreibung der Hallen darunter ist der alte Stand.

Die Lobbys liegen wieder auf Arenahöhe. Sie stehen auf der Granitplatte vor dem Kolosseum,
jede gegenüber ihrem Heldentor (Otti 90°, Schili 330°, Kroko 210°). Der Weg in die Arena führt
eben durch einen Fassadenbogen, über den Umgang und durch das offene Erdgeschoss unter den
Rängen bis ans Tor. Ein Goldstreifen auf dem Pflaster und ein Schild unter Rang 1 zeigen ihn.

## Ottis Halle (Hauptlobby)

Die alte Start-Lobby, vereinfacht: eine 88 × 80 Studs große Halle mit Säulen, Oberlicht und
Bänken. Ottis Monument steht links neben dem freien Mittelweg und blickt den ankommenden Spieler
an, rechts liegt das Otti-Mosaik. Beide Spawns stehen auf der Mittelachse und blicken zum
Ausgang mit dem Schild THE ARENA.

- Vorne: das Zombie-Archiv, drei Käfige auf jeder Seite der Tür (`ZombieDisplayService`).
- Links: die Ladenstraße. Waffen, Schilde und Rüstung liegen Tür an Tür in einer Reihe,
  jeweils mit den bestehenden Kampfmosaiken. Die Regale stehen nur an den festen Wänden.
- Rechts: ein offener Hof. Am Eingang liegt die Otti-Co-op-Gruppe (`ZombieCoop`), dahinter
  stehen sechs Strohpuppen. Die letzte ist die Sparring-Puppe. Training verursacht keinen
  Schaden und gibt keine Belohnungen.
- Hinten: TEAM BATTLES mit den Warteschlangen TIME BATTLE, FIRST TO und ELIMINATION,
  dazu PLAY · ALL MODES, BOSS FIGHT und LIVE BATTLES.

## Schili- und Kroko-Halle

Kleinere Hallen (60 × 52) mit Oberlicht, dem Heldenmonument an der Rückwand und den Tafeln
für alle Modi, Bosse und Live-Kämpfe. Links liegt die Zombie-Co-op-Gruppe, rechts der
Team-Sammelplatz (`TeamSchili` bzw. `TeamKrokero`). Die Tafeln hängen an den Seitenwänden,
die Startsäulen stehen zum Mittelgang hin. Betreten eines Mosaiks bildet dessen öffentliche
Party. READY, LEAVE, START GROUP und FIND PLAYERS verwenden die bestehenden Party- und
Matchfunktionen.

Wer in einer Lobby bis ans Arenator läuft, startet einen Solo-Zombie-Lauf, ohne Taste und
ohne Menü. Von Ottis Spawn bis zum Tor sind es etwa 140 Studs, also rund neun Sekunden.

## Intro

`LobbyIntroService` zeigt neuen Spielern nur den Weg in die Arena. Nach jedem beendeten Kampf
erscheint bei der Rückkehr genau eine neue Stufe mit Hinweis-Banner und goldenem Bodenpfeil:
1 Ladenstraße, 2 Schili- und Kroko-Halle, 3 Co-op und Training samt Team-Warteschlangen,
4 Bosskämpfe und Live-Kämpfe. Die passenden Schilder in Ottis Halle tragen das Attribut
`IntroStage` und bleiben lokal verborgen, bis der Spieler die Stufe erreicht hat. Gespeichert
wird die gezeigte Stufe (`introSeen`); wer schon mehr als vier Kämpfe hatte, überspringt das
Intro. `ExperienceConfig.Studio.IntroStage` (0–4) erzwingt in Studio eine Stufe.

## Nach dem Kampf

Es gibt keine automatische Rückkehr mehr. Auf der Tribüne erscheinen RETRY und BACK TO LOBBY.
RETRY startet in Zombie-Modi einen neuen Lauf auf demselben Arena-Server, sobald alle
Kämpfer gewählt haben, mit allen, die RETRY gewählt haben. In Studio gilt das auch für
Team-Modi. Team-Modi bieten sonst nur BACK TO LOBBY. Wer nach 120 Sekunden nicht gewählt
hat, kehrt in den Hub zurück.

## Keller

Das Hypogeum ist aus dem Hub entfernt. Der Keller des Kolosseums soll später als Mission
dienen. Er liegt dann nur unter dem Sand, mit der Decke direkt unter dem Arenaboden.

## Kolosseum

`src/shared/ColosseumLayout.luau` enthält alle Maße. Hub und Kampf-Place bauen beide mit
`src/server/Arena.luau`. Die Proportionen folgen dem flavischen Amphitheater:

- Der Sand ist eine Ellipse von 152 × 96 Studs, etwa 8 : 5 wie die echte Arena (87 × 55 m).
  Er liegt in Streifen von einem Stud.
- Die Cavea ist ringsum gleich breit (93 Studs vom Sandrand bis zur Außenseite der Fassade)
  und etwa so hoch wie breit (Attika-Oberkante 91).
- Die Fassade hat drei Bogenetagen von je 22 Studs und die Attika. Sie zählt 72 Joche. Jedes
  Heldentor liegt genau gegenüber einer Bogenmitte, und in jedem Bogen der 2. und 3. Etage
  steht eine Statue (144).

Die Ränge sind steiler als zuvor. Unterrang 1–4: je 9 tief und 6 hoch, also etwa 34°.
Rang 5 steigt zusätzlich über die Praecinctio-Mauer. Oberrang 5–8: je 8,5 tief und 7⅓ hoch,
etwa 41°. Dadurch liegen Rang 2, Rang 5 und Rang 8 genau eine Fassadenetage auseinander, auf
23, 45 und 67.

Jeder Rang ist eine Platte, deren Stirnseite auf dem Rang darunter steht. Darunter bleibt das
Erdgeschoss offen: eine gepflasterte Halle vom Podium bis zur Fassade, getragen von Pfeilern
unter den Stirnseiten. Jeder zweite Pfeiler hat eine Lampe. Zu den Heldentoren, unter den
Vomitorien und in den Treppenhäusern stehen keine Pfeiler. Das Podium hat an den Heldentoren
eine echte Öffnung.

Hinter dem obersten Rang liegt auf jeder Etage ein Umgang: auf dem Boden, auf 23, auf 45 und
der überdachte obere Umgang auf 67. Die Umgänge sind frei von Treppen. Über dem offenen
Unterbau haben die Umgänge auf 23 und 45 ein Geländer.

## Treppenhäuser

Vier Treppenhäuser bei 45°, 135°, 225° und 315° stehen unter Rang 7 und 8 direkt am Umgang.

- Jede Etage hat zwei Läufe von zehn Stufen. Der erste führt auf der Außenspur zum
  Zwischenpodest, der zweite wendet dort und führt auf der Innenspur zurück zum nächsten
  Hauptpodest.
- Die Hauptpodeste öffnen sich durch die Außenwand auf den Umgang ihrer Etage. Unten führt
  zusätzlich eine Tür in die Halle unter den Rängen.
- Oben endet das Treppenhaus auf Höhe von Rang 8. Ein Geländer sichert das Treppenauge, und
  die Wände stehen als Brüstung über Rang 7.

## Vomitorien und Tribünentreppen

Acht ebene Vomitorien führen von den Umgängen auf die gleich hohen Ränge, je eines pro Viertel:
vier von 23 auf Rang 2 und vier von 45 auf Rang 5. Wo sie über den offenen Unterbau führen,
haben sie Geländer. Wo der Schlitz nach oben offen ist, stehen Brüstungen.

Zwei Tribünentreppen bei 30° und 210° führen über alle Ränge vom unteren Zuschauergang bis
ganz nach oben. Jeder Lauf trifft die nächste Stirnseite eben.

Über jedem Geländer und jeder Brüstung reicht ein unsichtbarer Aufsatz 17 Studs über den Boden.
So springt niemand darüber oder von einer höheren Fläche darauf. Die Erdgeschossbögen sind im
Kampf-Place gesperrt; der Hub öffnet sie mit `Arena.setGroundExits(true)`. Rundherum liegt
eine endlose Granitplatte aus 25 großen Kacheln.

## Tore

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

Der Geometrietest führt die echten Arena- und Lobby-Builder mit einem Roblox-Adapter aus. Er prüft:

- Pads, Tafeln, Archiv, Training, Shopbereiche und Intro-Stufen
- dass keine Lobby unter dem Boden liegt und keine im Kolosseum steht
- die Steigung jedes Rangs
- die Kopffreiheit auf allen 240 Treppenhausstufen und in den Ladendurchgängen
- Boden und Kopffreiheit in allen acht Vomitorien
- den ebenen, freien Weg von jeder Lobby zu ihrem Tor
- die Zuschauer-Spawnpunkte

Die Lückensuche lässt eine Spielfigur (5 Studs hoch, Stufen und Sprünge bis 6,2 Studs) von allen
Spawns aus über die Oberseiten aller festen Teile laufen, abgetastet in Säulen von 1,5 Studs. Sie
schlägt fehl, wenn man irgendwo ins Leere fällt oder tiefer als 12 Studs stürzt. Vom Hallen-Spawn
aus muss sie Folgendes erreichen:

- jede Halle, jeden Laden und den Trainingshof
- jedes Tor und die Granitplatte
- beide oberen Umgänge und den oberen Umgang
- jede Treppe der vier Treppenhäuser
- jedes Vomitorium

Der Adapter ersetzt keine Prüfung der Roblox-Physik.

`build/OttiHub.rbxlx` ist die lokale Hub-Testdatei. `build/OttiArena.rbxlx` unterstützt
weiterhin die Studio-Bossauswahl an den drei Podesten (`ExperienceConfig.Studio.ArenaMockMode`
steht auf `BOSS_SOLO`). In Studio werden im Hub Reservierungen simuliert; Teleports zwischen den
beiden Places benötigen veröffentlichte Places.

## Stand am 30. Oktober 2026

- Geometrietest bestanden: 240 Treppenpositionen, keine Lücke, kein Sturz über 12 Studs.
- Team-Pads (51), Momentum (85), Specials (2111) und Animationen bestanden.
- Typprüfung für Hub und Arena ohne Fehler, beide Places gebaut.
- In Studio noch nicht angesehen: Wirkung der steileren Ränge, Licht im offenen Unterbau,
  Treppenhäuser im Spiel und die Bildrate mit 72 Jochen.
