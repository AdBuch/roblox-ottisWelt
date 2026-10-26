# Lobbyring und Boss-Test

Branch: `feature/lobby-und-rom`.

Der Hub bildet einen durchgehenden Ring unter den Tribünen. In Kreisrichtung:

| Winkel | Bereich |
| --- | --- |
| 0° | Otti-Statue und bestehendes Co-op-Mosaik |
| 60° | Schildshop zwischen Otti und Schili |
| 120° | Schili-Statue und blaues Team-Mosaik |
| 180° | Rüstungsshop zwischen Schili und Krokero |
| 240° | Krokero-Statue und rotes Team-Mosaik |
| 300° | Waffenshop zwischen Krokero und Otti |

Alle Ausrüstungsgegenstände werden weiterhin aus den vorhandenen Definitionen erzeugt.
Jeder Shop trägt ein Bodenmosaik mit beiden angrenzenden Helden und zwei Wandmosaike
mit ihren einzelnen Arenakämpfen: Otti/Schili im Schildshop, Schili/Krokero im
Rüstungsshop und Krokero/Otti im Waffenshop. Goldene Mäander, sichtbare Steinchenfugen,
Legionäre und Kolosseumsbögen rahmen Schildwall, Verteidigung und Waffenkampf ein.
Die neun Bilder entstehen ohne externe Bildassets auf nicht kollidierenden Flächen.
Kaufen und Ausrüsten prüfen serverseitig die Position im jeweiligen Shop sowie die Nähe zum Gegenstand.
Die Team-Mosaike behalten ihre bisherigen IDs und den Ablauf mit zwei bereiten Kapitänen.

Jede Statuenlobby hat eine Treppe auf die begehbare Tribüne und eine ins Hypogeum.
Unten liegen sechs Trainingskäfige mit den echten Zombie-Modellen und ein gemeinsamer
Treffpunkt mit Zugang zur Partyverwaltung. Trainingszombies nehmen Übungstreffer an,
regenerieren nach drei Sekunden, vergeben keine Belohnungen und verursachen keinen Schaden.
Der letzte Zombie ermöglicht weiterhin Block- und Parierübungen.

Von jeder Lobby und dem Treffpunkt öffnet **F** das Spielmenü mit Solo, Co-op,
allen drei Team-Modi, Bosskämpfen und Live-Zuschauen. Otti hat zusätzlich ein direktes
Boss-Auswahlschild. Das Tor nach Rom bleibt als beschrifteter, geschlossener Ausgang vorbereitet;
eine begehbare Stadt ist nicht Teil dieses Umbaus.

## Testen

Mit `scripts/build-places.ps1` beide Places erzeugen:

- `build/OttiHub.rbxlx`: Lobby besichtigen; beim Boss-Schild mit **F** die Auswahl öffnen.
  In veröffentlichten Places startet die Auswahl einen reservierten Arena-Server.
  Studio unterstützt keine Teleports zwischen Places; der Hub simuliert dort die Reservierung.
- `build/OttiArena.rbxlx`: In Studio **Play** drücken und eines der drei
  Boss-Podeste beim Startplatz mit **F** benutzen: **OTTI**, **SCHILI**, **KROKERO**.
  `ExperienceConfig.Studio.ArenaMockMode` steht für diesen Branch auf `BOSS_SOLO`.
  Erst die Auswahl startet den Countdown; die Zombie-Wellen werden übersprungen.
  Nach Kampfende und dem bestehenden Reset kann ein anderer Boss gewählt werden.
  Für andere lokale Spieltests `ArenaMockMode` auf einen vorhandenen Modus setzen.

Automatische Prüfungen:

```powershell
./scripts/test-lobby-ring.ps1 -LuauPath <luau.exe>
./scripts/test-pad-teams.ps1 -LuauPath <luau.exe>
./scripts/test-combat-animation.ps1 -LuauPath <luau.exe> -CompilePath <luau-compile.exe>
./scripts/test-passive-momentum.ps1 -LuauPath <luau.exe>
```

Der Ring-Test führt den echten Lobby-Builder mit einer Geometrieadapter-Umgebung aus.
Er prüft die Bereiche, Shopfreigaben und 180 Treppenpositionen auf Kopffreiheit.
Diese Prüfungen ersetzen keinen visuellen Durchlauf und keinen Physik-/Kampftest in Studio.
