# Krokero / Kroko — erstes echtes Skinned-Mesh-Modell

Stand: 29. Oktober 2026. Separates Asset-Projekt; keine Änderungen an Claudes Spielcode.

## Öffnen und prüfen

`Krokero.blend` in Blender 5.2 öffnen. Die Datei enthält den texturierten Charakter, das echte Armature-Skelett, vier Actions und eine beleuchtete Vorschau-Szene. Das Körpermesh ist standardmäßig ausgewählt. Zum Prüfen der Bones im Outliner `Krokero_Rig` auswählen, bei Bedarf „In Front“ einschalten und in den Pose Mode wechseln. Die Actions liegen im Action Editor; `Kroko_Idle` ist beim Öffnen aktiv.

`previews/Krokero_hero.png`, `Krokero_front.png` und `Krokero_back.png` zeigen den echten Blender-Render. `Krokero_strike.png` zeigt die Ausholbewegung. `Krokero_skeleton.png` visualisiert die tatsächlichen Bone-Positionen, `Krokero_walk.gif` den skinned Laufzyklus.

## Was gebaut wurde

- Ein zusammenhängender Körper mit verformbarer Haut, einschließlich Kopf, Armen, Händen, Beinen, Füßen und langem Schwanz. Der Körper hat genau eine verbundene Geometriekomponente.
- 25 echte Bones: Root, Becken, Wirbelsäule, Brust, Hals, Kopf, Kiefer, Arme/Hände, Beine/Füße und sechs Schwanzknochen.
- Skinning durch Blenders Bone-Heat-Verfahren; lineare Verformung. Maximal vier normalisierte Bone-Einflüsse pro Vertex. Root hat keine Deform-Gewichte.
- Vier skinned Mesh-Objekte: `Krokero_Body` (8.800 Dreiecke), `Krokero_Details` (9.000), `Krokero_Shield` (3.320), `Krokero_TrainingClub` (1.680). Insgesamt rund 22.800 Dreiecke vor einer möglichen weiteren Mobiloptimierung.
- Eine gemeinsame UV-Textur mit BaseColor, Metalness und Roughness, jeweils 2048 × 2048. Haut, Holz, Leder und Bronze behalten dadurch ihre unterschiedlichen Oberflächen.

Gestaltung nach dem kanonischen Brief: junger, freundlicher Beschützer; kräftiger grüner Körper; gelbgrüner Bauch und Unterkiefer; große goldbraune Augen; kleine runde Zähne; dunkle abgerundete Rückenplatten; Lederharnisch; ein Bronze-Schulterpanzer; Holzschild und Trainingskeule; dunkelroter Stoffakzent. Die früheren Originalbilder lagen nicht als Referenzdateien vor.

## Animationen / Exporte

Alle Clips laufen mit 30 fps. Jede FBX enthält genau einen Clip mit demselben Skelett; `Krokero_Bind.fbx` enthält die Ruhepose ohne Animation.

| Datei | Inhalt | Dauer |
|---|---|---|
| `exports/Krokero_Bind.fbx` | Meshes, UVs, eingebettete Texturen, Skinning, Bones | Ruhepose |
| `exports/Kroko_Idle.fbx` | Atmen, Bereitschaft, ruhiger Schwanz | 2 s |
| `exports/Kroko_Walk.fbx` | Laufzyklus auf der Stelle | 1 s |
| `exports/Kroko_ClubStrike.fbx` | Ausholen, Keulenschlag, Erholung | 1,5 s |
| `exports/Kroko_Stagger.fbx` | Zurückweichen und Erholen | 1 s |

Beim Keulenschlag endet das Ausholen ungefähr bei 0,6 s, der Schlag erreicht ungefähr 0,85 s, die Erholung endet bei 1,5 s. Trefferfenster im Spiel müssen daran angepasst werden; die alten Parts-Animationen dürfen nicht gleichzeitig auf diesen Rig angewandt werden. Die Clips sind erste Bewegungsentwürfe, noch keine abschließend abgestimmten Kampfanimationen.

## Übergabe an die Roblox-Integration

1. `Krokero_Bind.fbx` mit dem 3D Importer als benutzerdefinierten skinned NPC importieren. Es ist kein R15-Marketplace-Avatar und benötigt keine Avatar-Käfige für das vorhandene feste Equipment.
2. Orientierung und Maßstab im Import-Preview prüfen. Quelle: Blender Z oben, Blickrichtung −Y; FBX-Export Y oben / −Z vorwärts. Zielhöhe im Spiel etwa 9–10 Studs, anhand der vorhandenen Arena prüfen.
3. Prüfen, ob der Importer die drei Texturen übernimmt; sonst über `SurfaceAppearance.ColorMap`, `MetalnessMap` und `RoughnessMap` zuweisen. Für dünne Stoffflächen kann `DoubleSided` erforderlich sein.
4. Die vier Animationsdateien einzeln auf denselben Rig importieren und die Animations-IDs im passenden Roblox-Projekt hinterlegen.
5. Bestehende Server-KI, HP und Trefferlogik beibehalten. Ein eigener unsichtbarer physischer Root/Kollisionskörper bewegt das Modell. Bones selbst ersetzen keine Spiel-Kollisionen.
6. Den bisherigen Motor6D-Animator für diesen importierten Rig ausschalten und die Animationen über einen passenden Animator abspielen. Die optische Trefferposition und das Server-Trefferfenster zusammen testen.

Bone-Zuordnung zur bisherigen gemeinsamen Basis: Schulter → `UpperArm.L/R`, Ellbogen → `Forearm.L/R`, Hand → `Hand.L/R`, Hüfte → `Thigh.L/R`, Knie → `Shin.L/R`, Fuß → `Foot.L/R`, Schwanz → `Tail01` bis `Tail06`. `Root` ist der nicht verformende Ursprung; `Pelvis`, `Spine` und `Chest` steuern den Körper.

**Noch offen:** tatsächlicher Roblox-Import, Upload/Asset-IDs, Prüfung im Studio-Rendering, Anpassung der Kampfanimationen und Performance auf Mobilgeräten. Im Spiel ist bislang keine Figur ausgetauscht worden.

## Reproduzierbarkeit und Prüfung

`source/build_krokero.py` erzeugt Modell, Texturen, Actions, FBX-Dateien und Standbilder. `source/validate_krokero.py` prüft das gespeicherte Modell und importiert die exportierte Bind- und Angriffs-FBX unabhängig erneut. `source/render_motion.py` erzeugt Lauf-Frames und die Skelettansicht.

Beispiel: `blender --background --factory-startup --python source/build_krokero.py`.

34 technische Prüfungen bestanden; Einzelheiten in `verification.json`, Mesh- und Clipdaten in `validation.json`. Diese Tests bestätigen Dateistruktur und grundlegende Verformungen, nicht die noch ausstehende Roblox-Kompatibilitätsprüfung.

Offizielle Importhinweise: https://create.roblox.com/docs/art/modeling/export-requirements und https://create.roblox.com/docs/art/modeling/rigging.
