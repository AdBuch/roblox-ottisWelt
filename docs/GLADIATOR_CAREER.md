# Gladiatorenlaufbahn, Lobby-Menü und Ausrüstung

Stand: Schema v8 · `GladiatorLevelDefinitions` · `LobbyMenuController` · `LoadoutRequestService`

## Funktionen in Kürze

- **Zentrales Lobby-Menü** (Hub): Button „☰ MENÜ“ oben links, Taste **M**, Gamepad **Y** oder Tippen auf die Level-Kapsel oben rechts. Reiter: ÜBERSICHT · AUSRÜSTUNG · LAUFBAHN · SPIELMODI · EINSTELLUNGEN · STEUERUNG. Gamepad **B**, ✕ oder Tippen neben das Fenster schließt.
- **Ein großes Menü gleichzeitig** (`MenuSystem`): Lobby-Menü, Spielmodus-Menü, LIVE-Übersicht und Info-Panel schließen sich gegenseitig. Solange Lobby-, Modus- oder LIVE-Menü offen sind, sind Angriff/Block/Spezial gesperrt, eine gehaltene Spezialaufladung wird **ohne Auslösen** beendet (neue Server-Aktion `SpecialCancel`), der Block gesenkt, ein gehaltener Sprung losgelassen, Bewegung und Touch-Tasten pausiert und Näherungs-Prompts (Kauf/Ausrüsten per F/X) deaktiviert. Beim Schließen werden Bewegung, Kameratyp und Gamepad-Fokus wiederhergestellt. Das „i“-Panel bleibt exklusiv, lässt aber Bewegung und Kampf zu (es darf im Kampf offen sein).
- **Ausrüstung wechseln**: nur Gegenstände im Besitz, je Kategorie (Waffen/Schilde/Rüstungen) Kacheln mit kleiner statischer Vorschau (Klon des Waffenkammer-Modells, kein Charakter pro Kachel), Markierung **AUSGERÜSTET**, Detailbereich mit Beschreibung, echten Werten (`ItemInfo`), Vergleich zur aktuellen Ausrüstung und **AUSRÜSTEN**. Eine einzige Charaktervorschau zeigt die serverbestätigte Ausrüstung. Die Anzeige wechselt erst nach `{ ok = true }` vom Server.
- **Server prüft** (`LoadoutRequestService`): Ratenbegrenzung, Form der Anfrage, Gegenstands-ID passend zur Art, nur im Hub, Daten geladen und keine Teleport-Übergabe, Lobby-Zustand und Ort Lobby, keine Kampfvorbereitung (`MatchTransition`), Besitz. Kein Denarii-Abzug. Zweihandwaffen: die Schildwahl bleibt gespeichert, wird aber nicht getragen. `PlayerCombatService.refreshEquipment` baut Waffe, Schild, Rüstung, Angriffskette und Lauftempo neu auf. Gespeichert über den bestehenden PlayerDataService (Debounce, Flush vor jedem Teleport) → bleibt nach Rejoin und in der Arena erhalten.
- **Gekaufte Ausrüstung bleibt immer nutzbar**: Ausrüsten braucht nur Besitz; das Level begrenzt nur das Kaufen.
- **Übersicht**: Name, Charaktervorschau, „Level 24 / 150“, Titel, Ranggruppe, Fortschrittsbalken, erreichte/benötigte Aura im Level, exakt „Noch X Aura“, nächster Titel und nächster Rangaufstieg, Aura- und Denarii-Kontostand, Sitzungsverdienst, Belohnungen des letzten Kampfes, Gesamtverdienst aus eigenem Zähler.
- **Ergebnisanzeige**: zusätzlich „Level N / 150 · Titel · noch X Aura bis Level N+1“ (bzw. „Höchster Rang erreicht“).
- **Einheitliches Design**: Shop-Karte, Spielmodus-Menü, LIVE-Übersicht, Info-Panel, Ergebnis-Banner und Level-Kapsel nutzen das Theme aus `UiConfig.Menu` (warmer Stein, dunkle Flächen, Bronze/Gold, ≥ 44 px Touch-Flächen, gleiche Kopfzeile und Schließen-Button, Zustände Ausgewählt/Ausgerüstet/Gesperrt/Nicht verfügbar).

## Ranggruppen

| Ranggruppe | Level | Bedeutung |
|---|---|---|
| TIRO I–V | 1–5 | Rekrut der Gladiatorenschule |
| NOVICIUS I–V | 6–10 | Neuling mit ersten Arenasiegen |
| AUCTORATUS I–VIII | 11–18 | Unter Vertrag genommener Kämpfer |
| GLADIATOR I–X | 19–28 | Vollwertiger Kämpfer der Arena |
| VETERANUS I–XII | 29–40 | Erfahrener Gladiator vieler Kämpfe |
| PRIMUS PALUS I–XII | 41–52 | Bester Kämpfer seiner Schule |
| ARENACHAMPION I–XIV | 53–66 | Gefeierter Sieger der Arena |
| HELD DES KOLOSSEUMS I–XIV | 67–80 | Liebling der Tribünen |
| LEGENDE DER ARENA I–XV | 81–95 | Ein Name, den ganz Rom kennt |
| RUDIARIUS I–XV | 96–110 | Mit dem Holzschwert geehrter Meisterkämpfer |
| MEISTER DER ARENA I–XIV | 111–124 | Lehrmeister der Champions |
| TRIUMPHATOR I–XIII | 125–137 | Gefeiert mit einem Triumphzug |
| IMPERATOR I–XII | 138–149 | Feldherr der Arena |
| CÄSAR | 150 | Höchster Rang des Kolosseums (nur Level 150) |

Frühe Gruppen sind kurz (5 Level), damit Rangaufstiege anfangs häufig sind; spätere Gruppen sind länger.

## Fortschrittskurve

Aura von Level L nach L+1 (k = L − 1), auf 5 gerundet:

    step(k) = 100 + 25·k + 0,3·k²

Level 1 → 2 braucht 100 Aura, 10 → 11 rund 350, 50 → 51 rund 2 050, 149 → 150 rund 10 370. Jede Stufe ist mindestens so groß wie die vorige (getestet). Summe bis Level 150: **618 060 Aura**.

### Grundlage: tatsächliche Belohnungen (unverändert, nicht pauschal erhöht)

| Quelle | Aura | Denarii |
|---|---:|---:|
| Zombie (Killer) | 8–25 je Typ (Ø ca. 10–12) | = Aura |
| Co-op-Assist | 30 % der Zombie-Aura | = Aura |
| Abgeschlossene Runde | 10 | 15 |
| Bosssieg Solo (auch Boss-Testkampf) | 500 | 500 |
| Bosssieg Co-op überlebend / beteiligt | 400 / 250 | 400 / 250 |
| Teamkampf Sieg / Unentschieden / Niederlage | 80 / 40 / 25 | = Aura |

### Beispielrechnungen (aus den Definitionen; Spieldauern sind Annahmen)

- **Komplette Solo-Arena** (63 Zombies in 6 Runden, 6 Rundenboni, Bosssieg): ≈ 750 + 60 + 500 ≈ **1 310 Aura**, angenommen ca. 25 Min.
- **Solo bis Runde 4 verloren**: ≈ **200 Aura** → Level 2 schon im ersten Versuch.
- **Co-op mit 4 Spielern, komplett**: je Spieler ≈ 350 (Kills) + 300 (Assists) + 60 + 400 ≈ **1 100 Aura**.
- **Teamkampf** (8 Min.): Ø ca. 50 Aura.

| Gespielt | Aura | Level |
|---|---:|---|
| 1 komplette Solo-Arena | 1 310 | 8 · NOVICIUS III |
| 5 komplette Läufe (≈ 2 Std.) | 6 550 | 19 · GLADIATOR I |
| 10 Läufe (≈ 4 Std.) | 13 100 | 27 · GLADIATOR IX |
| 20 Läufe (≈ 8 Std.) | 26 200 | 38 · VETERANUS X |
| 50 Läufe (≈ 21 Std.) | 65 500 | 58 · ARENACHAMPION VI |
| 100 Läufe (≈ 42 Std.) | 131 000 | 79 · HELD DES KOLOSSEUMS XIII |
| 200 Läufe (≈ 83 Std.) | 262 000 | 106 · RUDIARIUS XI |
| 300 Läufe (≈ 125 Std.) | 393 000 | 125 · TRIUMPHATOR I |
| ≈ 472 Läufe (≈ 200 Std.) | 618 060 | 150 · CÄSAR |

### Ausrüstungsfreischaltungen (Kaufen; neu verteilt, Balancing-Stufe `Tier` unverändert)

| Level | Aura | Freischaltung |
|---:|---:|---|
| 3 | 225 | Legion Sword, Legion Shield |
| 6 | 760 | Hunter Bow, Arena Tower Shield |
| 11 | 2 215 | Gladiator Morning Star, Parma Equestris, Murmillo Armor |
| 15 | 3 925 | Champion Shield |
| 19 | 6 165 | Gladiator Trident |
| 22 | 8 215 | Scutum |
| 24 | 9 765 | Hoplite Spear, Hoplite Bronze |
| 29 | 14 340 | Twin Arena Daggers, Hoplon |
| 35 | 21 190 | Thraex Shield |
| 41 | 29 670 | Arena Battle Axe, Champion Armor |

Der PvE-Schadensfaktor hängt jetzt an `Tier` (die frühere Stufe 1–6) statt an `LevelRequired`, damit die neuen Levelzahlen die Kampfwerte nicht verändern.

## Matchmaking

Erlaubter Levelabstand zum ältesten Eintrag: `5 + 0,1 · Level + 0,2 · Wartesekunden`, nach 180 s jeder mit jedem. Beispiele: Level 10 ±6 sofort, ±18 nach 60 s; Level 100 ±15 sofort, ±27 nach 60 s. (Vorher: Start 1, maximal 6 Level – ausgelegt auf 7 Level.)

## Datenmigration (Schema v7 → v8)

- Level werden weiterhin **nicht gespeichert**, sondern aus der Aura berechnet: niemand verliert Aura, Denarii oder Gegenstände. Ein Spieler mit früher Level 7 (3 200 Aura) ist jetzt Level 13 AUCTORATUS III; schon gekaufte Ausrüstung mit höherer neuer Anforderung bleibt ausrüstbar.
- Neue Profilfelder: `earnings` (verdiente Aura/Denarii seit `since`, `complete`), `session` (Sitzung über Hub↔Arena-Teleports; neue Sitzung nach 20 Min. Abwesenheit), `lastBattle`, `activity` (aktive Kampfsekunden, Aura, Anzahl Belohnungen).
- Alte Profile bekommen Zähler **0** und `complete = false` → Anzeige „Seit Beginn der Erfassung (Datum)“; nichts wird geschätzt oder erfunden. Neue Profile zählen von Anfang an (`complete = true`).
- Die Migration legt nur fehlende Tabellen an und bereinigt vorhandene; wiederholtes Ausführen vergibt nichts doppelt (getestet, auch v1-`coins` und die v4-Umrechnung).
- Gesamtverdienst ist ein eigener, nur wachsender Zähler (`InventoryService.addReward`); Käufe senken ihn nie.
- **Zeitschätzung**: verlässlich ist „Noch X Aura“. Eine Spielzeit-Schätzung erscheint nur als „Schätzung: etwa …“ und erst ab 25 echten Belohnungen **und** 15 Min. aktiver Kampfzeit (nur MATCH_ACTIVE/ROUND_COMPLETE; Lobby-Warten zählt nicht), gerundet auf 5 Min. bzw. 0,1 Std.

## Touch-Steuerung (Rhombus)

Gemeinsamer Mittelpunkt C, Abstand r, Positionen aus `UiConfig.rhombusOffsets(r)`: BLOCK C+(0,−r), ANGRIFF C+(r,0), SPRUNG C+(0,r), SPEZIAL C+(−r,0). Alle vier: gleiche Größe (Telefon 66 px, Tablet 84 px Basis, dieselbe UIScale), gleiche runde Form, gleiche Kontur, zentriertes Icon und Beschriftung (nicht gedreht). Radius 60 / 76, Randabstand 14 / 26 px innerhalb der Safe Area; Nachbarabstand r·√2 ≥ Größe + 12 px (getestet). Der Roblox-Sprungbutton wird versteckt, solange SPRUNG sichtbar ist, auch nach Respawn oder neu erzeugtem TouchGui; SPRUNG springt per `Humanoid:ChangeState(Jumping)`, Halten springt bei jeder Landung erneut. Der Momentum-Ring bleibt am SPEZIAL-Button. Jede Taste verfolgt ihr eigenes Touch-Objekt (Multitouch; Loslassen auch nach Herausziehen des Fingers).

## Vollständige Level- und Titeltabelle

| Level | Titel | Aura gesamt | Aura für dieses Level |
|---:|---|---:|---:|
| 1 | TIRO I | 0 | 100 |
| 2 | TIRO II | 100 | 125 |
| 3 | TIRO III | 225 | 150 |
| 4 | TIRO IV | 375 | 180 |
| 5 | TIRO V | 555 | 205 |
| 6 | NOVICIUS I | 760 | 235 |
| 7 | NOVICIUS II | 995 | 260 |
| 8 | NOVICIUS III | 1.255 | 290 |
| 9 | NOVICIUS IV | 1.545 | 320 |
| 10 | NOVICIUS V | 1.865 | 350 |
| 11 | AUCTORATUS I | 2.215 | 380 |
| 12 | AUCTORATUS II | 2.595 | 410 |
| 13 | AUCTORATUS III | 3.005 | 445 |
| 14 | AUCTORATUS IV | 3.450 | 475 |
| 15 | AUCTORATUS V | 3.925 | 510 |
| 16 | AUCTORATUS VI | 4.435 | 545 |
| 17 | AUCTORATUS VII | 4.980 | 575 |
| 18 | AUCTORATUS VIII | 5.555 | 610 |
| 19 | GLADIATOR I | 6.165 | 645 |
| 20 | GLADIATOR II | 6.810 | 685 |
| 21 | GLADIATOR III | 7.495 | 720 |
| 22 | GLADIATOR IV | 8.215 | 755 |
| 23 | GLADIATOR V | 8.970 | 795 |
| 24 | GLADIATOR VI | 9.765 | 835 |
| 25 | GLADIATOR VII | 10.600 | 875 |
| 26 | GLADIATOR VIII | 11.475 | 915 |
| 27 | GLADIATOR IX | 12.390 | 955 |
| 28 | GLADIATOR X | 13.345 | 995 |
| 29 | VETERANUS I | 14.340 | 1.035 |
| 30 | VETERANUS II | 15.375 | 1.075 |
| 31 | VETERANUS III | 16.450 | 1.120 |
| 32 | VETERANUS IV | 17.570 | 1.165 |
| 33 | VETERANUS V | 18.735 | 1.205 |
| 34 | VETERANUS VI | 19.940 | 1.250 |
| 35 | VETERANUS VII | 21.190 | 1.295 |
| 36 | VETERANUS VIII | 22.485 | 1.345 |
| 37 | VETERANUS IX | 23.830 | 1.390 |
| 38 | VETERANUS X | 25.220 | 1.435 |
| 39 | VETERANUS XI | 26.655 | 1.485 |
| 40 | VETERANUS XII | 28.140 | 1.530 |
| 41 | PRIMUS PALUS I | 29.670 | 1.580 |
| 42 | PRIMUS PALUS II | 31.250 | 1.630 |
| 43 | PRIMUS PALUS III | 32.880 | 1.680 |
| 44 | PRIMUS PALUS IV | 34.560 | 1.730 |
| 45 | PRIMUS PALUS V | 36.290 | 1.780 |
| 46 | PRIMUS PALUS VI | 38.070 | 1.835 |
| 47 | PRIMUS PALUS VII | 39.905 | 1.885 |
| 48 | PRIMUS PALUS VIII | 41.790 | 1.940 |
| 49 | PRIMUS PALUS IX | 43.730 | 1.990 |
| 50 | PRIMUS PALUS X | 45.720 | 2.045 |
| 51 | PRIMUS PALUS XI | 47.765 | 2.100 |
| 52 | PRIMUS PALUS XII | 49.865 | 2.155 |
| 53 | ARENACHAMPION I | 52.020 | 2.210 |
| 54 | ARENACHAMPION II | 54.230 | 2.270 |
| 55 | ARENACHAMPION III | 56.500 | 2.325 |
| 56 | ARENACHAMPION IV | 58.825 | 2.385 |
| 57 | ARENACHAMPION V | 61.210 | 2.440 |
| 58 | ARENACHAMPION VI | 63.650 | 2.500 |
| 59 | ARENACHAMPION VII | 66.150 | 2.560 |
| 60 | ARENACHAMPION VIII | 68.710 | 2.620 |
| 61 | ARENACHAMPION IX | 71.330 | 2.680 |
| 62 | ARENACHAMPION X | 74.010 | 2.740 |
| 63 | ARENACHAMPION XI | 76.750 | 2.805 |
| 64 | ARENACHAMPION XII | 79.555 | 2.865 |
| 65 | ARENACHAMPION XIII | 82.420 | 2.930 |
| 66 | ARENACHAMPION XIV | 85.350 | 2.995 |
| 67 | HELD DES KOLOSSEUMS I | 88.345 | 3.055 |
| 68 | HELD DES KOLOSSEUMS II | 91.400 | 3.120 |
| 69 | HELD DES KOLOSSEUMS III | 94.520 | 3.185 |
| 70 | HELD DES KOLOSSEUMS IV | 97.705 | 3.255 |
| 71 | HELD DES KOLOSSEUMS V | 100.960 | 3.320 |
| 72 | HELD DES KOLOSSEUMS VI | 104.280 | 3.385 |
| 73 | HELD DES KOLOSSEUMS VII | 107.665 | 3.455 |
| 74 | HELD DES KOLOSSEUMS VIII | 111.120 | 3.525 |
| 75 | HELD DES KOLOSSEUMS IX | 114.645 | 3.595 |
| 76 | HELD DES KOLOSSEUMS X | 118.240 | 3.665 |
| 77 | HELD DES KOLOSSEUMS XI | 121.905 | 3.735 |
| 78 | HELD DES KOLOSSEUMS XII | 125.640 | 3.805 |
| 79 | HELD DES KOLOSSEUMS XIII | 129.445 | 3.875 |
| 80 | HELD DES KOLOSSEUMS XIV | 133.320 | 3.945 |
| 81 | LEGENDE DER ARENA I | 137.265 | 4.020 |
| 82 | LEGENDE DER ARENA II | 141.285 | 4.095 |
| 83 | LEGENDE DER ARENA III | 145.380 | 4.165 |
| 84 | LEGENDE DER ARENA IV | 149.545 | 4.240 |
| 85 | LEGENDE DER ARENA V | 153.785 | 4.315 |
| 86 | LEGENDE DER ARENA VI | 158.100 | 4.395 |
| 87 | LEGENDE DER ARENA VII | 162.495 | 4.470 |
| 88 | LEGENDE DER ARENA VIII | 166.965 | 4.545 |
| 89 | LEGENDE DER ARENA IX | 171.510 | 4.625 |
| 90 | LEGENDE DER ARENA X | 176.135 | 4.700 |
| 91 | LEGENDE DER ARENA XI | 180.835 | 4.780 |
| 92 | LEGENDE DER ARENA XII | 185.615 | 4.860 |
| 93 | LEGENDE DER ARENA XIII | 190.475 | 4.940 |
| 94 | LEGENDE DER ARENA XIV | 195.415 | 5.020 |
| 95 | LEGENDE DER ARENA XV | 200.435 | 5.100 |
| 96 | RUDIARIUS I | 205.535 | 5.185 |
| 97 | RUDIARIUS II | 210.720 | 5.265 |
| 98 | RUDIARIUS III | 215.985 | 5.350 |
| 99 | RUDIARIUS IV | 221.335 | 5.430 |
| 100 | RUDIARIUS V | 226.765 | 5.515 |
| 101 | RUDIARIUS VI | 232.280 | 5.600 |
| 102 | RUDIARIUS VII | 237.880 | 5.685 |
| 103 | RUDIARIUS VIII | 243.565 | 5.770 |
| 104 | RUDIARIUS IX | 249.335 | 5.860 |
| 105 | RUDIARIUS X | 255.195 | 5.945 |
| 106 | RUDIARIUS XI | 261.140 | 6.035 |
| 107 | RUDIARIUS XII | 267.175 | 6.120 |
| 108 | RUDIARIUS XIII | 273.295 | 6.210 |
| 109 | RUDIARIUS XIV | 279.505 | 6.300 |
| 110 | RUDIARIUS XV | 285.805 | 6.390 |
| 111 | MEISTER DER ARENA I | 292.195 | 6.480 |
| 112 | MEISTER DER ARENA II | 298.675 | 6.570 |
| 113 | MEISTER DER ARENA III | 305.245 | 6.665 |
| 114 | MEISTER DER ARENA IV | 311.910 | 6.755 |
| 115 | MEISTER DER ARENA V | 318.665 | 6.850 |
| 116 | MEISTER DER ARENA VI | 325.515 | 6.945 |
| 117 | MEISTER DER ARENA VII | 332.460 | 7.035 |
| 118 | MEISTER DER ARENA VIII | 339.495 | 7.130 |
| 119 | MEISTER DER ARENA IX | 346.625 | 7.225 |
| 120 | MEISTER DER ARENA X | 353.850 | 7.325 |
| 121 | MEISTER DER ARENA XI | 361.175 | 7.420 |
| 122 | MEISTER DER ARENA XII | 368.595 | 7.515 |
| 123 | MEISTER DER ARENA XIII | 376.110 | 7.615 |
| 124 | MEISTER DER ARENA XIV | 383.725 | 7.715 |
| 125 | TRIUMPHATOR I | 391.440 | 7.815 |
| 126 | TRIUMPHATOR II | 399.255 | 7.915 |
| 127 | TRIUMPHATOR III | 407.170 | 8.015 |
| 128 | TRIUMPHATOR IV | 415.185 | 8.115 |
| 129 | TRIUMPHATOR V | 423.300 | 8.215 |
| 130 | TRIUMPHATOR VI | 431.515 | 8.315 |
| 131 | TRIUMPHATOR VII | 439.830 | 8.420 |
| 132 | TRIUMPHATOR VIII | 448.250 | 8.525 |
| 133 | TRIUMPHATOR IX | 456.775 | 8.625 |
| 134 | TRIUMPHATOR X | 465.400 | 8.730 |
| 135 | TRIUMPHATOR XI | 474.130 | 8.835 |
| 136 | TRIUMPHATOR XII | 482.965 | 8.945 |
| 137 | TRIUMPHATOR XIII | 491.910 | 9.050 |
| 138 | IMPERATOR I | 500.960 | 9.155 |
| 139 | IMPERATOR II | 510.115 | 9.265 |
| 140 | IMPERATOR III | 519.380 | 9.370 |
| 141 | IMPERATOR IV | 528.750 | 9.480 |
| 142 | IMPERATOR V | 538.230 | 9.590 |
| 143 | IMPERATOR VI | 547.820 | 9.700 |
| 144 | IMPERATOR VII | 557.520 | 9.810 |
| 145 | IMPERATOR VIII | 567.330 | 9.920 |
| 146 | IMPERATOR IX | 577.250 | 10.035 |
| 147 | IMPERATOR X | 587.285 | 10.145 |
| 148 | IMPERATOR XI | 597.430 | 10.260 |
| 149 | IMPERATOR XII | 607.690 | 10.370 |
| 150 | CÄSAR | 618.060 | – |
