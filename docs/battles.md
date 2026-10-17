# Battles

Four standalone battles, all condensed and historically inspired, never surveys. The player is
France in each. Maps are authored in `src/shared/MapGen.luau` (`MAPS.<id>`), orders of battle in
`src/shared/Scenarios.luau` (`Scenarios.<id>`); `Scenarios.list()` returns them in display order
(Jena, Auerstedt, Austerlitz, Waterloo). Strengths are balance values (infantry 600, Guards 700,
cavalry 400, battery 120, HQ 40), not returns; one formation stands for a regiment or a large
battalion. Distances are condensed as in `docs/rules.md`; map sizes are per battle
(`MapDef.width/depth`, multiples of 16 studs). `+z` is north on every map.

Victory is the same evaluator everywhere (`docs/rules.md`): collapse of either side, holding every
objective for 120 s after minute 10 having taken at least one from the enemy, or the time limit,
where the side holding more objectives wins. Weather (`scenario.weather`, `Config.Weather`) and
off-map reinforcements (`UnitDef.arrival`) are scenario data.

Name legend: **attested** = a formation known to have been present at that battle under that
name; *representative* = a real formation of that army and period, or a plausible name, placed to
stand for the troops that were there.

## Jena, 14 October 1806 (`jena`, 1600 × 1200)

**Historical note.** Napoleon crossed the Saale at Jena on the night of 13 October and massed on
the Landgrafenberg plateau above the town. In the morning fog Lannes took Closewitz and Cospeda,
Ney rushed Vierzehnheiligen prematurely and had to be rescued, then Soult, Augereau and the
reserve rolled Hohenlohe's Prussians and Saxons back; Rüchel's late counter-attack was destroyed
and Murat's cavalry pursued. The same morning Davout beat the Prussian main army at Auerstedt.

**Condensed.** One corps per division-sized block, Rüchel omitted, the Landgrafenberg–village
distances shortened to musket-range pacing. Fog for the first five minutes (`weather = "fog"`).

**Order of battle.** France: Napoléon HQ; V Corps Lannes (17e Légère, 34e, 40e de Ligne), VII
Corps Augereau (7e Légère, 44e), VI Corps Ney (6e Légère, 39e), IV Corps Soult (26e Légère, 36e),
Guard (Grenadiers à pied, Guard artillery), cavalry reserve Murat (1er Cuirassiers, 5e Hussards,
9e Chasseurs) — all attested regiments of those corps. Prussia: Hohenlohe HQ; Tauentzien's
advance guard (Füsilier-Bataillon Pelet, IR 20 Prinz Louis Ferdinand, IR 38 Pelchrzim —
attested), Grawert's division (IR 29 Treuenfels, IR 49 Müffling, Grenadier-Bataillon Hahn —
attested), Saxon contingent Zezschwitz (IR Prinz Clemens, IR Rechten, Dragoner Prinz Johann —
attested, `colour = "Saxony"`), Holtzendorff (IR 51 Kauffberg — attested), cavalry Prinz Wilhelm
(Kürassier Henckel, Husaren Gettkandt — attested).

**Map.** Landgrafenberg, Windknollen and Dornberg heights; Jena, Closewitz, Cospeda, Lützeroda,
Vierzehnheiligen, Isserstedt, Krippendorf, Kapellendorf; Isserstedt Wood; the Saale (east, in a
valley) and the Rau-Bach; four bridges.

**Objectives.** Vierzehnheiligen, Closewitz, Dornberg. All start neutral. 25 min.

## Auerstedt, 14 October 1806 (`auerstedt`, 2000 × 1504)

**Historical note.** Marshal Davout's III Corps (about 26,000) crossed the Saale at Kösen before
dawn and ran into the Prussian main army under the Duke of Brunswick (about 50,000) on the
plateau at Hassenhausen. The Prussians attacked piecemeal across the Lissbach: Blücher's cavalry
broke on Gudin's squares, Schmettau's and Wartensleben's divisions were fought to a standstill at
Hassenhausen, Friant extended the right through Spielberg and Morand the left over the
Sonnenkuppe. Brunswick and Schmettau were mortally wounded; the reserve under Kalckreuth was
never properly committed and by early afternoon the Prussians were retreating west.

**Condensed.** The field is shortened so the Lissbach, Hassenhausen and the Kösen bridge all fit
one map; the Saale runs diagonally across the south-east corner. The Prussians are all on the
field from the start (they historically arrived over several hours) but their reserve stands
well back behind the Eckartsberg. Morand's division enters as reinforcements from the Kösen road
between 2½ and 4½ minutes (`arrival`). Fog for the first four minutes.

**Order of battle.** France (experience 2 throughout): Davout HQ; Division Gudin (25e, 85e, 21e,
12e de Ligne, battery — attested), Division Friant (33e, 48e, 108e, 111e de Ligne — attested),
corps battery, Vialannes' cavalry (1er, 12e Chasseurs à cheval — attested), Division Morand
arriving (13e Légère, 17e, 30e, 61e de Ligne, battery — attested). 18 formations.
Prussia: Brunswick HQ; Division Schmettau (IR 21 Herzog von Braunschweig, IR 30 Borcke —
attested; IR 22 Pirch, Grenadier-Bataillon Hanstein — *representative*; battery), Division
Wartensleben (IR 23 Winning, IR 55 Manstein, Grenadier-Bataillon Rheinbaben, Dragoner Königin
Nr. 5 — *representative*; battery), Division Oranien (IR 19 Prinz von Oranien, IR 25 Möllendorff,
Füsilier-Bataillon Oswald — *representative*; battery), Kalckreuth's reserve (IR 15 Garde,
Grenadier-Garde Nr. 6 — attested), Blücher's cavalry (Garde du Corps, Gensd'armes, Husaren
Blücher Nr. 8 — attested; Leib-Kürassier Nr. 3 — *representative*; horse battery). 22 formations.

**Map.** Hassenhausen (centre, on a low plateau), Poppel, Spielberg, Taugwitz, Rehausen,
Gernstedt, Kösen and Eckartsberga; the Sonnenkuppe and Eckartsberg heights in the west; the
Lissbach stream crossing north–south with three bridges (road, Poppel, Taugwitz); the Saale in
the south-east with the Kösen bridge. French deploy around Hassenhausen (x 900–1760), Prussians
in the west (x 60–620) and must cross the Lissbach.

**Objectives.** Hassenhausen, Poppel, Kösen bridge. 25 min. Difficulty: hard, outnumbered 2:1.

## Austerlitz, 2 December 1805 (`austerlitz`, 2400 × 1792)

**Historical note.** Napoleon abandoned the Pratzen plateau to tempt the Russo-Austrian army
under Kutuzov (nominally; the Tsar and Weyrother drove the plan) into marching its columns south
off the heights against his right along the Goldbach at Telnitz and Sokolnitz. Friant's division
of Davout's corps arrived from Vienna in time to hold the south; as the fog lifted Soult's
divisions climbed the emptied Pratzen, held it against the Russian Guard, and swung south onto
the rear of the allied columns, which broke across the frozen Satschan ponds. Lannes and Murat
fought Bagration and Liechtenstein to a standstill in the north around the Santon.

**Condensed.** The Goldbach villages are drawn one map-width apart from the plateau; Blasowitz,
Krzenowitz and Austerlitz town are present but the Olmütz road fight is a flank. Fog for the first
eight minutes (`weather = "fog"`, the "sun of Austerlitz"). Friant's three regiments enter from
the south-west edge at 2–3 minutes (`arrival`). The ponds are water (impassable); they are
rendered through the river list so they look like broad still water.

**Order of battle.** France: Napoléon HQ on the Zuran; IV Corps Soult — Saint-Hilaire (10e
Légère, 14e, 36e), Vandamme (24e Légère, 4e, 28e, 57e), Legrand (26e Légère, 3e, Tirailleurs du
Pô), battery — attested; V Corps Lannes (17e Légère, 34e, 13e Légère, battery — attested, the 13e
Légère served under Caffarelli); I Corps Bernadotte (8e de Ligne, 27e Légère — attested); Guard
(Grenadiers à pied, Chasseurs à pied, Grenadiers à cheval, artillery — attested); cavalry reserve
Murat (1er Cuirassiers, 2e Carabiniers, 5e Hussards — attested); Friant arriving (48e, 108e, 15e
Légère — attested). 27 formations.
Allies (`faction = "russia"`): Kutuzov HQ; Kienmayer's Austrian advance guard (Hessen-Homburg
Hussars, Székler Grenz, O'Reilly Chevaulegers — attested, `colour = "Austria"`); 1st column
Dokhturov (Novo-Ingermanland, Yaroslavl, Kiev Grenadiers — attested; battery); 2nd column
Langeron (Vyborg, Perm, Fanagoria Grenadiers — attested; battery); 3rd column Przhebishevsky
(Galicia, Narva — attested); 4th column Kolowrat/Miloradovich (Novgorod, Apsheron — attested;
IR 23 Salzburg, IR 20 Kaunitz, Austrian battery — attested, `colour = "Austria"`); 5th column
Liechtenstein (Uhlans Grand Duke Constantine, Elisabethgrad Hussars — attested; Kürassier Nassau
— attested, Austrian); Bagration's advance guard (Pavlograd Hussars, 5th Jägers,
Arkhangelgorod — attested; battery); Russian Guard (Preobrazhensky, Semenovsky, Chevalier
Guards — attested; battery). 31 formations.

**Map.** Pratzen Heights plateau in the centre (with Staré Vinohrady and the Pratzeberg), the
Santon and Zuran in the north-west, the Goldbach running north–south with bridges at the Olmütz
road, Girzikowitz, Puntowitz, Kobelnitz, Sokolnitz and Telnitz, the Sokolnitz pheasantry, the
Satschan and Mönitz ponds in the south, Augezd, Blasowitz, Krzenowitz, Holubitz, Austerlitz and
Schlapanitz. French deploy west of the Goldbach (x 60–660), allies on and east of the Pratzen
(x 1000–2330).

**Objectives.** Pratzen Heights, Sokolnitz, Santon (the Santon starts inside the French zone).
30 min. Difficulty: hard.

## Waterloo, 18 June 1815 (`waterloo`, 2400 × 1600)

**Historical note.** Wellington's Anglo-allied army held the Mont-Saint-Jean ridge behind the
sunken Ohain road with Hougoumont, La Haye Sainte and Papelotte garrisoned in front. Napoleon
waited for the sodden ground to dry, then attacked frontally: Reille was sucked into Hougoumont
all day, d'Erlon's columns were broken by Picton's division and the Union Brigade, Ney's massed
cavalry charged the squares without support, La Haye Sainte fell only around 18:00. Bülow's
Prussian IV Corps came in from the east through the Bois de Paris and fought for Plancenoit,
Zieten joined the allied left, and the repulse of the Guard at dusk ended the battle and the war.

**Condensed.** The ridges are 600 studs apart; Braine-l'Alleud and Merbe-Braine mark the allied
right, Frichermont and Smohain the left. Mud all battle (`weather = "mud"`: cannon ×0.7,
speed ×0.8). Bülow's corps is represented by four Prussian formations (`colour = "Prussia"`, on
the `britain` side) entering at the east edge near Plancenoit at minutes 12, 14, 16 and 18
(`arrival`); Zieten's I Corps is omitted.

**Order of battle.** France: Napoléon HQ at Rossomme; Grand Battery (two formations —
*representative* split of the 80-gun battery); II Corps Reille — Jérôme (1er Légère, 1er de
Ligne), Foy (92e, 100e), Bachelu (2e Légère, 61e), Piré (6e Lanciers) — attested; I Corps
d'Erlon — Quiot (54e, 105e), Donzelot (13e Légère, 51e), Marcognet (45e), Durutte (85e),
Jacquinot (3e Chasseurs) — attested; VI Corps Lobau (5e, 84e — attested); Guard (Grenadiers à
pied, Chasseurs à pied, 1er Tirailleurs, Grenadiers à cheval, artillery — attested); Milhaud
(1er, 10e Cuirassiers — attested); Kellermann (1er Carabiniers, 8e Cuirassiers — attested).
28 formations.
Anglo-allied (`faction = "britain"`): Wellington HQ; Alten's 3rd Division (2nd Light Bn KGL in La
Haye Sainte, 5th Line Bn KGL, 30th, 73rd — attested); Picton's 5th Division (28th, 79th, 92nd,
42nd, 1/95th Rifles — attested); Cooke's Guards (2/3rd Foot Guards and 2/2nd Coldstream at
Hougoumont, 2/1st Foot Guards — attested); Netherlands contingent (`colour = "Netherlands"`): 7e
Ligne, 27e Jagers (Bylandt), 2nd Nassau at Papelotte (Saxe-Weimar), Bijleveld's horse battery —
attested; Uxbridge's cavalry (1st Life Guards, Royal Dragoons, Scots Greys, 12th Light Dragoons,
1st Hussars KGL — attested); Mercer's and Ross's Troops RHA — attested. 24 formations, plus
Bülow's Prussians arriving: 15. and 18. Infanterie-Regiment (attested in IV Corps at
Plancenoit), Schlesisches Landwehr-Regiment and Schlesisches Husaren-Regiment (*representative*
of the Silesian Landwehr and reserve cavalry).

**Map.** Mont-Saint-Jean ridge with the Ohain road along its crest and the Brussels road crossing
it at the crossroads; La Haye Sainte on the road below the crest; Hougoumont with its wood in
front of the allied right; Papelotte, La Haye, Smohain and Frichermont on the left with the
Smohain brook and two bridges; La Belle Alliance ridge and Rossomme for the French; Plancenoit
and the Bois de Paris in the south-east; Forêt de Soignes along the north edge. The low ground
between the ridges is open; its cost is the weather, not a terrain class.

**Objectives.** La Haye Sainte, Hougoumont, Mont-Saint-Jean crossroads — all inside the allied
deployment zone, so the French must take them. 30 min. Difficulty: very hard.
