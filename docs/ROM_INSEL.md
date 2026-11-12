# Rom auf der Weltscheibe (Hub)

Branch `feature/lobby-und-rom`. Rom ist ein frei begehbarer Teil des Hubs rund um das bestehende
Kolosseum. Der Arena-Place und der gemeinsame Arena-Builder (`src/server/Arena.luau`,
`ColosseumGate.luau`, `ColosseumLayout.luau`) sind unverändert.

## 1. Die drei Lobbys im Kolosseum

`src/server/LobbyArchitecture.luau` baut die Lobbys **in** die offene Halle unter den Rängen,
zwischen Podium und Fassade, in Ringkoordinaten (Ellipsenwinkel + Abstand nach außen). Stand
10. November 2026: Käfige unter Rang 1, Läden auf die drei Hallen verteilt, Arena offen.

| Bereich | Ring | Inhalt |
|---|---|---|
| Ottis Lobby (Hauptankunft) | 70–110°, Tor 90° | Ankunft auf der Torachse, Monument, Mosaik, zwei Anschlagwände (Teams, alle Modi, Boss, Live), sechs Zombie-Käfige |
| Ottis Laden | 112–131° | Klingen und ausgewogene Schilde innen (Abstand 26), Rüstung außen (44) |
| Kroko | 190–250°, Tor 210° | Monument, Käfige (Legionär, berittener Prätorianer), Laden 224–238° (schwere Waffen, schwere Schilde), Tafelwand |
| Schili | 290–350°, Tor 330° | Monument, Käfige (drei Ninjas, Terrakotta-Samurai), Laden 302–316° (Fernwaffen, leichte Schilde), Tafelwand |
| Arena (im Hub offen) | Sand | sechs Strohpuppen im Kreis (Radius 16), Kombo-Tafel; vor jedem Tor Solo-Start, Co-op-Mosaik und (Kroko, Schili) Team-Sammelplatz |
| Weg nach Rom | Westbogen 180° | Schild ROMA · FORUM, Wegweiser aus Kroko- und Ottis Lobby |

- **Käfige:** unter dem untersten Rang (Abstand 4,5–12,6, Höhe 7,6), Rücken an der Podiumsmauer,
  mit Rückwand und Dach, Gitter zur Halle, Tafel an der Rangkante darüber. Der Stall des
  Prätorianers reicht bis unter Rang 2 (Abstand 21,6, Höhe 11). Je Halle die Vorkämpfer des
  Kapitels (`HEROES[].foes` → `archiveIds` → `ZombieDisplayService`). Käfige halten den Torweg
  (22 breit) und die Pfeilerstrahlen frei.
- **Offene Arena:** `openHeroGates` entfernt im Hub Gitter und Kollision der drei Heldentore
  (Rahmen bleibt; der gemeinsame Arena-Builder und der Kampf-Place sind unverändert). Training gilt
  auf dem Sand (`TrainingService`-Zone und `Arena.isInside`).
- **Sammelplätze auf dem Sand:** acht Mosaike. Solo-Start (`OttiSolo`, `KrokoSolo`, `SchiliSolo`,
  `Kind = "Solo"`): drei Sekunden auf dem Mosaik stehen startet den Solo-Lauf; die früheren
  Tor-Trigger gibt es nicht mehr (`arenaTriggers` ist leer). Co-op 24 Studs neben der Torachse,
  Team-Sammelplatz auf der anderen Seite.
- **Statuen:** aus den Heldenmodellen, in Kalkstein (ohne Texturen, Glanz, Lichter), Maßstab
  `STATUE_SCALE = 2` gegenüber der Kampfgröße.

Freie Felder liegen zwischen den Pfeilerstrahlen (10, 30, 70, 110, 150, 170, 190, 250, 270, 290,
350°), außerhalb der Treppenhäuser (45/135/225/315°, Abstand 57–74) und unter der jeweiligen
Kopffreiheit (Abstand 4–13: 8, 13–22: 14, darüber höher). Tribünen, Pfeiler, Umgänge und Fassade
sind unverändert.

Anker: Ankunft (90°, Abstand 52) mit Blick aufs Tor, Respawn/Rückkehr (87,5°, 58). Hub-Spawn,
Hub-Respawn und Ankunft nach dem Kampf nutzen diese Anker über `HubMatchService` (unverändert).

**Fußweg Spawn → Solo-Start** (Gitter-Messung im Geometrietest): 61,5 Studs, 3,8 s bei Gehtempo 16
(vor dem Umbau ins Kolosseum 139,5 Studs; mit Tor-Trigger 43,5 Studs).

## 2. Maßstab und Grundriss

- Kolosseum (fest): Fassade 338 × 282 Studs ≈ 189 × 156 m → **0,56 m/Stud**. Avatar ≈ 5 Studs →
  0,35 m/Stud. Häuser sind avatar-groß (Tür 7–8 Studs, Geschoss 8,5 Studs).
- Stadtfläche (`RomeLayout.cityArea()`): Mauerpolygon 333 443 Stud² minus Hafenbecken 20 776 Stud²
  = **312 667 Stud²**. Als Abbild von 22 ha entspricht das **0,84 m/Stud**: die Stadt ist gegenüber
  dem Kolosseumsmaßstab etwa 1,5-fach verdichtet (bei 0,56 m/Stud wären es nur 9,8 ha), damit 80
  Häuser einen dichten Stadtkern bilden und Wege kurz bleiben (Ost–West ≈ 930 Studs, ≈ 1 Minute).
- Insel (Küstenpolygon) 971 591 Stud², also ≈ 2× die Stadt draußen. Weltscheibe Radius 1080
  (Zentrum −150/−140), mindestens 300 Studs offenes Meer bis zum Rand.
- Terrassen: Oben y 1 (Kolosseum, Vorplatz), Unten y −2 (Handwerk, Forum, Wohnviertel, Villen),
  Hafen y −6, Meer y −12 (auf der Voxelgrenze). Stützmauern bei x −232 und −508; Straßen führen als Rampen (≤ 14 %) durch.

Alles steht als deterministische Daten in `src/hub/server/Rome/RomeLayout.luau`: Mauer, Becken,
Küste, Tore, Straßen mit Höhen, Querungen, Plätze, Anker, Blöcke mit Fronten und die 80 Häuser
(stabile IDs `<Block>-<Seite><Nr>`, Typ, Türanker mit Ausrichtung, `facesStreet`, `open`).

## 3. Module (`src/hub/server/Rome/`)

| Modul | Aufgabe |
|---|---|
| RomeLayout | Plan als Daten + Geometrie-Hilfen |
| RomeParts | Bausteine, Materialfamilien (Kalkstein, Putz, Terrakotta, Holz, Bronze) |
| IslandBuilder | Terrain per WriteVoxels (Höhenfeld 8 Studs, Voxel 4), Meer, Rand mit Wasserfall, Atmosphäre |
| CityShell | Stadtmauer mit Türmen, Landtor, Küstentor, Stützmauern, Kolosseumsring, Vorplatz |
| StreetBuilder | Pompeji-Straßen, Gehsteige, Randsteine, Rampen, Laternen, Trittsteinquerungen |
| HouseKit | 6 Haustypen aus Bausteinen, Varianten per Seed, Attribute und Türanker |
| Smithy | Schmiede mit Innenraum |
| ForumTemple | Forum, Brunnen, reservierte Anschlagtafel, Tempel mit Cella und Orakelplatz |
| Harbor | Kais, Molen, Poller, Liegeplatz (Trireme-Umriss 64 × 12), Reisepunkt |
| Countryside | Einkornfelder, Wald, Lichtung, Wegmarken, Aussichtspunkt, Klippenruine |
| RomeNpc | Figuren in Toga/Schürze, feste Routen mit Gehanimation |
| TownServices | Schmied und Orakel, serverseitig |
| WorldEdgeService | Sturz über den Rand → einmal zum Forumsbrunnen; Sand → Lobby-Respawn |
| RomeWorld | Aufbau in dieser Reihenfolge; entfernt nur die endlose Granitplatte des Arena-Builders im Hub |

`src/hub/server/Main.server.luau` baut zuerst die Lobbys und startet die Dienste, dann Rom im
Hintergrund. Remotes: `RomeRequest` (RemoteFunction), `RomeEvent` (RemoteEvent), nur im Hub.
Client: `src/hub/client/RomeDialog.client.luau`.

## 4. Pompeji-Straßen

| Typ | Fahrbahn | Gehsteig je Seite | Gehsteighöhe |
|---|---|---|---|
| Hauptstraße | 10 | 4,5 | 0,7 |
| Gasse | 6 | 2,5 | 0,55 |
| Kai (Uferstraße) | 14 große Platten | – | – |

Pro Straßenstück eine durchgehende Fahrbahnplatte (Cobblestone, dunkel), Wagenspuren als Detail.
Unsichtbare Keile vor jedem Randstein und an jedem Gehsteigende machen die Stufe zu einer Rampe.
An Einmündungen endet der Gehsteig an der Fahrbahn der anderen Straße, Hauptstraßen haben Vorrang.

**Querung:** 3 abgerundete Steine quer zur Fahrtrichtung (Gasse 1–2), Oberkante auf Gehsteighöhe,
zwei offene Durchlässe in Fahrtrichtung. Kollision: eine unsichtbare Planke auf Gehsteighöhe und
flache Anläufe in alle vier Richtungen. Setzpunkte: Kolosseumsvorplatz, Schmiedevorplatz,
Forumseingang (Bronzeeinlage, zwei Laternen), Abzweig Hafenstraße, Landtor, Schmiedgasse,
Südgasse. Abgesenkte Übergänge 6 Studs neben den wichtigen Querungen.

## 5. Häuser

80 Häuser (+ Tempel, Kolosseum): 24 Reihenhäuser, 16 Mietshäuser, 16 Ladenhäuser, 10 Hofhäuser,
6 Villen, 8 Speicher/Werkstätten. Darin: Schmiede (BN1-S1, Werkstatt, **einziges offenes Haus**),
Bäckerei (BN1-S3, Ofenmotiv und Brotkörbe), Tavernen *Zum Goldenen Korn* (BN2a-W1, Wohnviertel an
der Landtorstraße), *Zum Letzten Meilenstein* (BN4b-W1, am Landtor), *Zum Salzigen Anker*
(BH2-N2, am Südkai). Jedes Modell trägt `HouseId`, `HouseType`, `District`, `Floors`,
`FacesStreet`, `OpenInMVP` und `DoorAnchor` (CFrame auf der Schwelle, −Z zur Straße).
Geschlossene Türen sind fest; dahinter liegt der volle Baukörper.

## 6. Schmiede: Exemplare, Aufträge, Verschleiss, Designs, Robux

`src/shared/ForgeDefinitions.luau`, `InventoryService` (Profil v10), `src/hub/server/Rome/TownServices.luau`,
Dialog `src/hub/client/RomeDialog.client.luau`.

- **Exemplare:** Jede besessene Waffe besteht aus einem oder mehreren Exemplaren mit eigener
  Härtung, eigenem Verschleiss, eigenem Design und ggf. einem Auftrag beim Schmied. Ein Exemplar
  wird gewählt (BENUTZEN). Weitere Exemplare derselben Waffe: Grundpreis (Waffenpreis, mind. 40)
  × 2, × 4, × 8 … (jedes weitere das Doppelte), höchstens 6.
- **Aufträge brauchen Zeit** (`os.time`, laufen über Teleport und Rejoin weiter): Härten 15 min,
  Schleifen 2 min, Reparieren 5 min, Design 10 min, neues Exemplar 20 min. Solange ein Exemplar
  beim Schmied ist, ist es nicht benutzbar: ein anderes freies Exemplar derselben Waffe kommt in die
  Hand, sonst die Startergladius (als schlichte Leihwaffe, falls auch die beim Schmied ist).
  Fertige Aufträge schliessen sich selbst ab; im Hub prüft eine Schleife alle 5 s und rüstet neu aus.
- **Preise (Denarii):** Härten 50 % des Waffenpreises (mind. 40; Rusty Gladius 40 … Battle Axe 190),
  Schleifen 10 + 4 % des Waffenpreises, Reparieren 15 + 20 % des Waffenpreises × Verschleissanteil.
- **Härten:** +10 % PvE-Schaden pro Stufe (eine Stufe).
- **Verschleiss (nur PvE):** +0,25 je gelandetem Treffer auf Zombie oder Boss (nie gegen Spieler oder
  Trainingspuppen). Stufen: unter 60 voller Schaden, ab 60 → 85 %, ab 90 → 70 % (die Waffe bleibt
  benutzbar). Schleifen −35, Reparieren → 0.
- **Wirkung:** Härtung × Verschleiss bilden den Exemplarfaktor im PvE-Faktor (`SpecialMoveService`),
  den der PvP-Multiplikator wieder herausteilt: **PvP unverändert.** Der Dialog zeigt den
  Grundschlag gegen Zombies mit diesem Faktor und erklärt, was erst beim Treffer wirkt
  (`ForgeDefinitions.ValueNote`).
- **Designs (kosmetisch, Robux):** Griff (Gold, Silber, Purpurleder), Klinge (Poliert, Geschwärzt,
  Bronze), Beschläge (Gold, Silber, Bronze) je Exemplar; Schildbemalung (Legionsrot, Kaiserblau,
  Gold) je Schild. Färbt die benannten Teile des Waffen-/Schildmodells beim Ausrüsten.
- **Robux (Platzhalter):** `ForgeDefinitions.Products`: 250 / 1200 / 3000 Denarii (25 / 99 / 199 R$),
  Auftrag sofort fertig (15 R$), Design anfertigen (49 R$). **SALE-Bundles:** 3× Vorspulen (39 R$ statt 45),
  3× Design (129 R$ statt 147), Starterpaket 1200 Denarii + 1 Vorspulen + 1 Design (149 R$ statt 163).
  Gutschriften stehen in `Product.credits` und werden in `TownServices.grant` je Receipt einmal gewährt. `productId = 0` bis die Produkte im
  Creator Hub angelegt sind: in Studio laufen Testkäufe über denselben Gewährungsweg, ausserhalb
  werden sie abgelehnt. `MarketplaceService.ProcessReceipt` (nur Hub) gewährt jede Quittung einmal
  (gespeicherte Kaufnummern), wandelt Vorspulen/Design in Gutschriften, löst die vorgemerkte Aktion
  aus, speichert (`PlayerDataService.flush`) und meldet erst dann `PurchaseGranted`.
- **Prüfungen des Servers** bei jeder Aktion: Angebots-Token (60 s), Nähe zum Schmied (16), Lobbyzustand,
  geladene Daten, Waffe, Besitz des Exemplars, freier Zustand, Vorbedingung, Serverpreis, Guthaben;
  Abbuchung und Auftrag in einem Schritt ohne Yield; Mindestabstand 0,35 s zwischen Anfragen.
- Helme haben keinen Slot: drei Helme stehen als Schaustücke (`ExpansionPoint = "Helmets"`).

**Datenmigration:** `PlayerDataSchema.Version` 10. Neu: `weaponCopies`, `activeCopy`, `nextCopy`,
`shieldDesigns`, `forgeCredits`, `receipts`. Jede besessene Waffe erhält ein Exemplar; die v9-Stufe
(`forge`) geht auf das erste Exemplar über, das v9-Feld entfällt. Ungültige Exemplare, Designs und
Aufträge werden bereinigt, Stufe und Verschleiss begrenzt. Nichts wird weggenommen.

## 7. Tempel und Orakel

Podium (Boden y 4), breite Fronttreppe in 10 Halbstufen ins Forum, flacher Seitenaufgang im Süden,
sechs Frontsäulen, Giebel vorne und zur Hafenseite, Cella mit Bodenmosaik, Statue, Dreifuß mit
Flamme und ruhigem Licht. Zwei Priester in Togas gehen feste Routen (Cella; Pronaos und
Südumgang). Der Augur bietet die Weissagung an: **5 Denarii** (`OracleDefinitions.Price`),
vor der Bestätigung sichtbar, genau einmal pro Angebot abgebucht, bei zu wenig Guthaben bleibt
der Kontostand gleich. Text: ein wechselnder Spruch plus die exakt fehlende Aura bis zum nächsten
Titel (und bis zur nächsten Ranggruppe), am Höchstrang CÄSAR ein eigener Text. Keine Zufallsbelohnung.

## 8. Weltrand und Respawn

Wasser über die ganze Scheibe (y −42 bis −12). Am Rand: Felslippe, überlaufendes Wasser, ein
Wasservorhang 240 Studs in die Tiefe, Gischt, Wolken darunter. Sichtbar vom Strand und vom
Aussichtspunkt (Mauer, Schild „Am Rand der Welt"). `WorldEdgeService` prüft viermal pro Sekunde:
außerhalb des Radius und unter dem Meer, oder tiefer als −45 → einmal zum Forumsbrunnen
(kein Tod, nichts geht verloren), danach 3 s Schonzeit. Der Sand der Arena ist im Hub offen (Training, Sammelplätze): dort greift keine Regel mehr.
Arena-Todeslogik, Spawnwahl, Intro und Rückkehr bleiben unberührt.

Ergänzt in der Abnahmerunde (9. November 2026): `Yards.luau` mit zwei Werkhöfen hinter den
Ladenfronten der Handwerksgasse (Schuppen eingeschossig, Karren, Brennholz, Schleifstein) und
niedrigen Mauern mit geschlossenen Torbögen vor Werkhöfen und Villengärten
(`RomeLayout.Yards`/`YardWalls`); am Hafen Seile an den Pollern und zwei Lagerarkaden (Horrea)
hinter dem Ostkai (`RomeLayout.QuayArcades`), die mit Speichern und Kaimauer die Uferfront
schließen; im Schmiededialog die Erklärung, welcher Kampfwert angezeigt wird
(`ForgeDefinitions.ValueNote`); Terrain-Kalibrierung (`IslandBuilder.calibrate`) gegen die in
Studio gemessene Höhenabweichung von 2 Studs; die unzulässige `FallenPartsDestroyHeight`-Zuweisung
entfernt.

## 9. Prüfungen

```powershell
./scripts/test-rome-layout.ps1 -LuauPath <luau.exe>    # Plan: Zählung, Überlappung, Straßen, Mauern, Höfe, Wasser, Fläche
./scripts/test-rome-geometry.ps1 -LuauPath <luau.exe>  # Builder: Begehbarkeit, Querungen, Tempel, Schmiede, Höfe, Inselhöhen
./scripts/test-rome-services.ps1 -LuauPath <luau.exe>  # Schmied, Orakel, Weltrand-Regel (Mock-Spieler, echte Logik)
./scripts/test-lobby-ring.ps1 -LuauPath <luau.exe>     # Lobbys im Kolosseum, keine Kollision, Wegmessung
```

### 9.1 Stand der Prüfungen (9. November 2026)

**Automatisiert (echter Quellcode, Mock-Roblox):** Lobby-Ring (326 Lobbyteile gegen 3722
Kolosseum-Kollisionskörper, keine Überschneidung; Gap-Walk ohne Loch), Rom-Layout 150 036,
Rom-Geometrie 13 743 (alle 7 Querungen quer und längs in beiden Richtungen, auch entlang der
Raddurchlässe, Randsteine aller Hauptstraßen, Tempeltreppe und Seitenrampe bis zum Orakel, beide
Priesterrouten, Schmiede bis vor den Amboss, Forum → Hafenstraße → Kai, Handwerksgasse, alle Tore
der Gartenmauern geschlossen, Inselpfade trocken und höchstens 0,31 steil), Rom-Dienste 44,
Progression 1747, Specials 2118, Team-Pads 51, Momentum 95, Heldenkampf 66, Arena-Kampagne,
Kampfanimationen 149. Rom-Dienste nach dem Schmiede-Ausbau: 70 (Exemplare, Aufträge mit Zeitsprung, Verschleiss, Designs, Vorspulen, Bemalung, Quittungen einmalig, Studio-Testkauf, Migration v9→v10). Strict-Analyse (luau-lsp, Sourcemap `default.project.json`): 62 Meldungen,
alle in sechs vorbestehenden, unberührten Dateien (Ausgangsstand 62). Hub und Arena mit Rojo gebaut.
`Arena.luau`, `ColosseumGate.luau`, `ColosseumLayout.luau`, `src/arena` und
`places/arena.project.json` sind identisch mit dem Stand vor dem Rom-Commit.

**Gemessen im Studio-Spieltest (Log 9. 11. 07:19, Hub, Mock-Daten):** Rom in 2,6 s aufgebaut,
60 Bilder/s bei 6128 Rom-Teilen (Übersicht und Straße), Augur und Flamen als R15 mit
Gehanimation unterwegs (36 und 85 Studs), Schmied steht. Daraus zwei Mängel, behoben:
Terrain 2 Studs zu hoch (Straßen teils verschüttet) und der Abbruch durch
`FallenPartsDestroyHeight` in einer früheren Sitzung. **Nach diesen Korrekturen noch nicht erneut in
Studio gestartet.**

**Rechnerisch (nicht gestoppt):** Weg Ankunft → Tor-Trigger vorher 139,5, nachher 43,5 Studs
(Gitter-BFS im Geometrietest); bei WalkSpeed 16 ≈ 8,7 s → 2,7 s.

**Nur Mock / Serialisierung:** Schmied und Orakel (Mock-Spieler, -Uhr, -Charakter); Speicherung
nach Rejoin und Hub-Arena-Wechsel über `InventoryService.serialize`/`load` (in Studio sind die
Daten ohnehin MOCK, Teleports nur simuliert, siehe Hub-Log).

### 9.2 Abnahmematrix

| Bereich | Status | Prüfmethode | Mängel / Stelle |
|---|---|---|---|
| 1 Hub, Kolosseum, Abläufe | teilweise verifiziert | Lobby-Harness (Kollision, Kopffreiheit, Gap-Walk, Wegmessung), Git-Vergleich Arena-Dateien, Regressionstests | Studio: Ankunft, Respawn, Kampfrückkehr, Zuschauerrückkehr, drei Lobbys, Weg gestoppt — offen |
| 2 Maßstab, Stadtgestalt | teilweise verifiziert | Layouttest, Flächen aus Polygonen; Studio-Log (Aufbau, FPS) | Wirkung auf Avatarhöhe, Blickachsen visuell — offen |
| 3 Viertel, Wege, Blickachsen | behoben und erneut geprüft (automatisch) | Layout- und Geometrietest, Inselhöhen | Werkhöfe, Gartenmauern/Torbögen, Uferfront (Horrea), Taue ergänzt (`Yards.luau`, `Harbor.luau`); Inselrunde in Studio — offen |
| 4 Pompeji-Straßen | behoben und erneut geprüft (automatisch) | Geometrietest alle Querungen/Randsteine; Studio-Log (Terrain über Deck) | Terrain-Höhe (`IslandBuilder.luau`) korrigiert; Touch, Kamera, NPC über Querung in Studio — offen |
| 5 Häuser, Bausteine | bestanden (automatisch) | Layouttest (80, Verteilung, IDs, Türanker), Geometrietest (Türen fest) | Fassadenwirkung visuell — offen |
| 6 Schmiede, Tempel, Server | behoben und erneut geprüft (Mock) | Dienste-Test 44, Progression (Migration v9), Schadenspfad im Code belegt | Dialogkennzeichnung ergänzt (`ForgeDefinitions.ValueNote`); UI-Bestätigung und echter PvE-Schaden in Studio — offen |
| 7 Insel, Meer, Respawn | behoben und erneut geprüft (teilweise) | Weltrand-Klassifizierung, Inselhöhen, Studio-Log | `FallenPartsDestroyHeight` entfernt; Sturz, Wasserfall, Grenzzone in Studio — offen |

**Gesamt: nicht vollständig abgenommen.** Es fehlen der Studio-Spieltest nach den Korrekturen und
die vier Aufnahmen (Insel, Forumsquerung aus Spielerhöhe, Forum mit Tempel, Hafen).

Außerhalb des Auftrags, vorbestehend: `PlayerAnimator:193` (arithmetic on nil) im Studio-Log vom
8. 11., Datei unverändert.

Später: Questfiguren/Anschlagtafel, Hausinnenräume, Trireme und Reisen, geheime Treppe an der Ruine.

### 9.3 Spieltest-Rückmeldungen vom 9. November (Studio), umgesetzt

- Terrain-Kalibrierung gemessen: 1,28 Studs Versatz, korrigiert (der harte Wert 2 wäre falsch gewesen).
- Weltrand: die Felslippe trägt keine Spieler mehr (keine Kollision, tiefer unter der Oberfläche).
- Meer: Meeresspiegel auf der Voxelgrenze (−12), nur volle Wasservoxel, Insel- und Meeresfüllung
  gleich: flache Oberfläche; Wellen über `WaterWaveSize 0.35`, `WaterWaveSpeed 14`.
- Bäume, Zypressen, Amphoren, Wolken: längliche Kugeln sind jetzt Ellipsoide (vorher von Roblox auf
  die kleinste Seite verkleinert: Kugeln auf Stummeln).
- Gehsteige enden an Einmündungen, Lücken und Plätzen halbrund mit hellem Randstein; Trittsteine
  0,25 unter Gehsteighöhe, die Begehungsplanke folgt; Randsteinrampen überlappen den Gehsteig 0,1.
- Schmiede-Ausbau wie in Abschnitt 6.
- `ContentId rbxassetid://203785492` im Log stammt nicht aus dem Projekt (weder Quellen noch Build).

## 7. Läden in Rom und Trainingsplatz

- **Läden (Rom, offene Innenräume, `src/hub/server/Rome/ArmoryShops.luau`):** Waffenladen neben der
  Schmiede (BN1, Waffen), Helmhändler gegenüber (BS1, Helme), Rüstungsladen neben dem Helmhändler
  (BS1, Rüstungen), Schildhaus (BS1, Schilde). Je ein Händler-NPC hinter dem Tresen. Die Taverne
  bleibt, wo sie war. Die Gladiatorenwaffenkammer in der Arena ist leer.
- **Helme (`src/shared/HelmetDefinitions.luau`):** eigener Ausrüstungs-Slot neben der Rüstung, Profil v11
  (`ownedHelmets`, `equippedHelmet`). „Kein Helm“ ist kostenlos. Helme bringen etwas Schadensminderung
  zusätzlich zur Rüstung (`PlayerCombatService.armorReduction`) und werden am Kopf angebracht
  (`EquipmentModels.buildHelmet`).
- **Training:** auf dem Kolosseums-Vorplatz vor dem Westbogen (`LobbyArchitecture` FORECOURT), nicht mehr
  auf dem Sand. Die Kampfregel „nur Strohpuppen im Trainingsbereich“ gilt dort.
- **Gathering-Punkte:** Co-op- und Team-Mosaike liegen jetzt in den Hallen-Buchten unter den Tribünen,
  wo früher die Laden-Buchten waren. Der Solo-Start bleibt am Tor auf dem Sand.
- **Noch nicht geprüft:** Ohne Roblox Studio und ohne Luau-Analyse sind nur die Rojo-Builds geprüft
  (beide Places bauen). Platzierung von Ständern, Kollision und Sicht in den Läden müssen in Studio
  angesehen werden.
