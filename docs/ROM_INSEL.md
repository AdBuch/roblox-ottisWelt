# Rom auf der Weltscheibe (Hub)

Branch `feature/lobby-und-rom`. Rom ist ein frei begehbarer Teil des Hubs rund um das bestehende
Kolosseum. Der Arena-Place und der gemeinsame Arena-Builder (`src/server/Arena.luau`,
`ColosseumGate.luau`, `ColosseumLayout.luau`) sind unverändert.

## 1. Die drei Lobbys im Kolosseum

`src/server/LobbyArchitecture.luau` baut die Lobbys jetzt **in** die offene Halle unter den Rängen,
zwischen Podium und Fassade, in Ringkoordinaten (Ellipsenwinkel + Abstand nach außen):

| Bereich | Ring | Inhalt |
|---|---|---|
| Ottis Lobby (Hauptankunft) | 70–110°, Tor 90° | Ankunft auf der Torachse, Monument, Mosaik, zwei Anschlagwände (Teams, alle Modi, Boss, Live), Zombie-Archiv hinter der Ankunft |
| Ladenstraße | 110–170° | Waffen 112–126°, Schilde 127–148°, Rüstung 151–169°, zwei Regalreihen (Abstand 26 und 44) |
| Trainingshof | 30–70° | Otti-Co-op-Mosaik am Eingang, sechs Strohpuppen, Kombo-Tafel |
| Kroko | 190–250°, Tor 210° | Monument, Co-op- und Teammosaik, Tafelwand |
| Schili | 290–350°, Tor 330° | dasselbe gespiegelt |
| Weg nach Rom | Westbogen 180° | Schild ROMA · FORUM, Wegweiser aus Kroko- und Ottis Lobby |

Freie Felder liegen zwischen den Pfeilerstrahlen (10, 30, 70, 110, 150, 170, 190, 250, 270, 290,
350°), außerhalb der Treppenhäuser (45/135/225/315°, Abstand 57–74) und unter der jeweiligen
Kopffreiheit (Abstand 13–22: 15, 22–31: 21, 31–40: 27, 40–48,5: 33). Alle Einbauten stehen nur auf
dem Hallenboden; Tribünen, Pfeiler, Umgänge, Tore und Fassade sind unverändert.

Anker: Ankunft (90°, Abstand 52) mit Blick aufs Tor, Respawn/Rückkehr (87,5°, 58). Hub-Spawn,
Hub-Respawn und Ankunft nach dem Kampf nutzen diese Anker über `HubMatchService` (unverändert).

**Fußweg Spawn → Tor-Trigger** (gleiche Gitter-Messung im Geometrietest):
vorher 139,5 Studs (8,7 s bei Gehtempo 16), nachher 43,5 Studs (2,7 s). Der Spawn liegt 35 Studs vor
dem Trigger; Laden oder Respawn starten keinen Kampf.

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
  Hafen y −6, Meer y −10. Stützmauern bei x −232 und −508; Straßen führen als Rampen (≤ 14 %) durch.

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

## 6. Schmiede (Spielwert)

`src/shared/ForgeDefinitions.luau`:

- Eine Stufe für jede **besessene** Waffe: **+10 % PvE-Schaden** (Zombies, Bosse, Trainingspuppen).
- Preis: 50 % des Waffenpreises, auf 5 gerundet, mindestens 40 Denarii.
  Rusty Gladius 40, Legion Sword 40, Hunter Bow 65, Morning Star 95, Trident 130, Hoplite Spear 150,
  Twin Daggers 170, Battle Axe 190.
- Der Dialog zeigt den echten Grundschlag gegen Zombies vorher/nachher (Basis-Move ×
  `WeaponBalanceConfig.pveFactor` × Schmiedefaktor), denselben Wert, den der Server rechnet.
- Wirkung: `PlayerCombatService` gibt `forgeFactor` an `SpecialMoveService`; er steckt im
  PvE-Faktor, den `pvpMultiplier` gegen Spieler wieder herausteilt. **PvP bleibt unverändert.**
- Helme haben keinen Slot: drei Helme stehen als Schaustücke auf einem Regal
  (`ExpansionPoint = "Helmets"`).
- Ablauf: Prompt am Schmied → Server prüft und sendet ein Angebot mit Einmal-Token → Client
  bestätigt → `RomeRequest("ForgeUpgrade", {token, weaponId, level})` → Server prüft Token (60 s),
  Nähe (16 Studs), Lobby-Zustand, geladene Daten, Waffe, Besitz, erwartete Stufe, Preis und Guthaben,
  dann `InventoryService.forgeUpgrade`: Abbuchung und Stufe in einem Schritt ohne Yield.
  Doppelklick: Sperre + Mindestabstand 0,35 s; zweite Bestätigung scheitert an der Stufe.

**Datenmigration:** `PlayerDataSchema.Version` 9, neues Feld `forge` (Waffen-ID → Stufe).
Ältere Profile starten ohne verbesserte Waffe; unbekannte IDs fallen weg, Stufen werden begrenzt.
Gespeichert über `InventoryService.serialize` → bleibt nach Rejoin und Hub-Arena-Wechsel erhalten.

## 7. Tempel und Orakel

Podium (Boden y 4), breite Fronttreppe in 10 Halbstufen ins Forum, flacher Seitenaufgang im Süden,
sechs Frontsäulen, Giebel vorne und zur Hafenseite, Cella mit Bodenmosaik, Statue, Dreifuß mit
Flamme und ruhigem Licht. Zwei Priester in Togas gehen feste Routen (Cella; Pronaos und
Südumgang). Der Augur bietet die Weissagung an: **5 Denarii** (`OracleDefinitions.Price`),
vor der Bestätigung sichtbar, genau einmal pro Angebot abgebucht, bei zu wenig Guthaben bleibt
der Kontostand gleich. Text: ein wechselnder Spruch plus die exakt fehlende Aura bis zum nächsten
Titel (und bis zur nächsten Ranggruppe), am Höchstrang CÄSAR ein eigener Text. Keine Zufallsbelohnung.

## 8. Weltrand und Respawn

Wasser über die ganze Scheibe (y −40 bis −10). Am Rand: Felslippe, überlaufendes Wasser, ein
Wasservorhang 240 Studs in die Tiefe, Gischt, Wolken darunter. Sichtbar vom Strand und vom
Aussichtspunkt (Mauer, Schild „Am Rand der Welt"). `WorldEdgeService` prüft viermal pro Sekunde:
außerhalb des Radius und unter dem Meer, oder tiefer als −45 → einmal zum Forumsbrunnen
(kein Tod, nichts geht verloren), danach 3 s Schonzeit. Sand der Arena im Hub → Lobby-Respawn.
Arena-Todeslogik, Spawnwahl, Intro und Rückkehr bleiben unberührt.

## 9. Prüfungen

```powershell
./scripts/test-rome-layout.ps1 -LuauPath <luau.exe>    # Plan: Zählung, Überlappung, Straßen, Mauer, Wasser, Fläche
./scripts/test-rome-geometry.ps1 -LuauPath <luau.exe>  # Builder: Begehbarkeit, Querungen, Tempel, Schmiede, Insel
./scripts/test-rome-services.ps1 -LuauPath <luau.exe>  # Schmied und Orakel (Mock-Spieler, echte Logik)
./scripts/test-lobby-ring.ps1 -LuauPath <luau.exe>     # Lobbys im Kolosseum, keine Kollision, Wegmessung
```

Stand 9. November 2026: alle Projekttests grün (Progression 1747, Specials 2118, Pads 51,
Momentum 95, Heldenkampf 66, Kampagne, Animationen 149, Rom-Layout 141 495, Rom-Geometrie
13 734, Rom-Dienste 34, Lobby-Ring). Typprüfung ohne neue Fehler. Hub und Arena mit Rojo gebaut.

Nur mit Mock-Daten bzw. Geometrie-Adapter geprüft (nicht in Roblox Studio):
Begehbarkeit (Adapter statt Physik), Schmied/Orakel (Mock-Spieler, -Zeit, -Charakter),
Inselhöhen (Höhenfunktion, nicht das geschriebene Terrain).

**Offen / in Studio zu prüfen:** Aufbauzeit von RomeWorld (Terrain), Bildrate mit ~6000 Teilen,
NPC-Laufen (R15 über `CreateHumanoidModelFromDescriptionAsync`, Ausweich-Rig R6), Wasserfall-Optik,
Touch-Laufen über die Querungen, ein voller Arena-Durchlauf mit Rückkehr, Aufnahmen
(Insel, Querung aus Spielerhöhe, Forum mit Tempel, Hafen).
Später: Questfiguren/Anschlagtafel, Hausinnenräume, Trireme und Reisen, geheime Treppe an der Ruine.
