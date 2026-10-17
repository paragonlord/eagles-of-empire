# Battles

Four standalone battles, all condensed and historically inspired, never surveys. The player is
France in each. Maps are authored in `src/shared/MapGen.luau` (`MAPS.<id>`), orders of battle in
`src/shared/Scenarios.luau` (`Scenarios.<id>`); `Scenarios.list()` returns them in display order
(Jena, Auerstedt, Austerlitz, Waterloo), each followed by its quick-battle episodes (below). Strengths are balance values (infantry 600, Guards 700,
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
Guards — attested; battery). 31 formations, plus the Life Guard Horse held off the map (see
Historical moments).

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

## Historical moments

Every listed battle carries 2–3 **moments** (`scenario.moments`, types in
`src/shared/Moments.luau`): scripted beats drawn from what happened, fired when the player's battle
makes them plausible. The server checks them every 10 ticks after objectives
(`src/server/Sim/Moments.luau`); each fires at most once, in list order, and is deterministic.

- **Conditions** (all keys of a table must hold; `any` = OR, `all` groups): `time` (≥ s), `before`
  (< s), `weatherCleared`, `objectiveTaken {id, by, seconds?}` (owned, optionally for `seconds`),
  `formationRouted <selector>` (any selected formation routing, shattered or destroyed),
  `strengthBelow <selector + fraction>` (selection's current / starting strength),
  `formationNear <selector + objective|pos + radius>` (on the field and not routing).
  A selector filters by `faction`, `class`, and plain substrings of `name` and `corps`.
- **Effects** (small on purpose): morale ± up to 15 to the selected formations (it recovers or
  drains through the normal morale rules afterwards), `release` a held off-map formation now,
  `weather` (a scenario's `weatherUntil` still clears it once passed).
- **Output**: an event `{kind = "moment", momentId, title, text, x?, z?, height?, faction?}` to both
  sides, or only to `faction` when the text would be wrong for the other; the title goes into the
  results chronicle (`log`). The client shows a letterboxed title card and pans the camera to
  `x, z` and back (`src/client/Cinematic.luau`); any input skips it.

Facts behind each moment (Chandler, *The Campaigns of Napoleon*; Petre, *Napoleon's Conquest of
Prussia*; Duffy, *Austerlitz 1805*; Adkin, *The Waterloo Companion*; Hofschröer, *1815: The
Waterloo Campaign*):

| Battle | Moment | Fires when | Effect | What happened |
|---|---|---|---|---|
| Jena | The fog lifts | fog clears (5 min) | France +6 | The morning fog over the Landgrafenberg lifted around 9–10 a.m., revealing the French massed on the plateau. |
| Jena | Ney goes in alone (France only) | a VI Corps formation within 150 of Vierzehnheiligen before minute 10 | VI Corps −6 | Ney attacked Vierzehnheiligen around 10 a.m. without orders with his advance guard, was nearly surrounded, and Napoleon sent Lannes and cavalry to extricate him. |
| Jena | Vierzehnheiligen is taken | France owns it | Prussia −8 | Grawert's infantry stood about two hours in the open in front of the burning village, firing volleys at French skirmishers under cover. |
| Auerstedt | Davout holds Hassenhausen | minute 10, France has held it 5 min | France +8 | Gudin's division held Hassenhausen alone through the morning until Friant and Morand came into line. |
| Auerstedt | Brunswick is struck down | Brunswick's HQ hit, or Prussia below 85 %, or Prussian infantry within 250 of Hassenhausen after minute 8 | Prussia −10 | Leading grenadiers forward at Hassenhausen around 10 a.m., the Duke was shot through both eyes and died on 10 November; command collapsed and the reserve was never committed. |
| Austerlitz | The Sun of Austerlitz | fog clears (8 min) | France +8 | The sun broke through the mist over the Pratzen as the allied columns marched off it; Napoleon invoked the "sun of Austerlitz" for years after. |
| Austerlitz | Soult on the Pratzen | France owns the Pratzen | 4th column −10, 3rd −6 | Asked how long he needed to reach the heights, Soult answered "less than twenty minutes"; Saint-Hilaire and Vandamme took the plateau and split the allied army. |
| Austerlitz | The Russian Guard | minute 15, France has held the Pratzen 2 min | releases the held Life Guard Horse Regiment | Around 1 p.m. Grand Duke Constantine's Guard counter-attacked near Staré Vinohrady; the Chevalier Guard and Life Guard Horse broke French battalions (the 4e de Ligne lost an eagle) before Rapp's Guard cavalry drove them off. |
| Waterloo | Hougoumont ablaze | minute 10, French within 180 of Hougoumont | Byng's Guards −5 | French howitzers set the château and barn on fire in the afternoon; the Guards held the burning buildings all day. |
| Waterloo | The Prussians at Plancenoit | a Bülow formation on the field | France −4 | Bülow's IV Corps came out of the Bois de Paris around 4:30 p.m. and attacked Plancenoit, forcing Lobau and then the Young Guard to face east. |
| Waterloo | La Garde recule ! | a Guard infantry formation routs | France −12 | The repulse of the Middle Guard around 8 p.m. set off the cry "La Garde recule!" and the French army dissolved. |

**Austerlitz order of battle addition.** The *Life Guard Horse Regiment* (attested in Constantine's
Guard at Austerlitz) is held off the map (`arrival` at 3600 s, past the time limit) and only enters
through "The Russian Guard". It counts as surviving in the results if it never comes on.

## Episodes (quick battles)

Eight 10-minute battles (`mode = "episode"`, `parent` = the full battle, `timeLimit = 600`), each a
real slice of its parent: the same ground (MapGen ids `<battle>_<episode>` clone the parent map's
features and seed, so the grid is identical) with its own deployment zones, one or two objectives,
6–9 formations a side and two moments. `Scenarios.list()` returns each full battle followed by its
episodes. Victory rules are unchanged (`docs/rules.md`); with 10 minutes the time limit usually
decides, so holding more objectives at the end wins. Home edges are north/south in the sim, so each
side's episode zone keeps its centre on its own half of the map. Names follow the legend above:
unless marked *representative*, every formation is attested at that battle (most are the same as in
the full battle).

- **Lannes on the Landgrafenberg** (`jena_landgrafenberg`, dawn, fog 4 min). Lannes' V Corps comes
  down off the plateau against Tauentzien at Closewitz and Cospeda (both objectives, in the Prussian
  zone). France: Lannes HQ; Suchet's 17e Légère, 34e, 40e, 64e, 88e; Gazan's 21e Légère; corps
  battery. Prussia: Tauentzien HQ; Pelet, IR 20, IR 38, battery, IR Rechten and Dragoner Prinz
  Johann (Saxons); Holtzendorff's IR 51 (its place on this flank *representative*). Moments: the
  fog lifts (France +6); Closewitz carried (Tauentzien −8).
- **The fight for Vierzehnheiligen** (`jena_vierzehnheiligen`, late morning). Ney's advance guard
  and Lannes' flank regiments against Grawert's line beyond the village (objective, neutral between
  the zones). France: Ney HQ; Marchand's 6e Légère, 39e, 69e; VI Corps battery; Colbert's 10e
  Chasseurs; Lannes' 17e Légère, 40e and battery. Prussia: Grawert HQ, IR 29, IR 49, Grenadiers
  Hahn, battery, Kürassiere Henckel, Husaren Gettkandt, IR Prinz Clemens (Saxon). Moments: Lannes to
  the rescue (France only, VI Corps below 80 %: VI Corps +6); Vierzehnheiligen taken (Prussia −8).
- **Gudin at Hassenhausen** (`auerstedt_hassenhausen`, morning, fog 3 min). Gudin's division
  meets the head of the Prussian army with Schmettau already over the Lissbach. Objectives:
  Hassenhausen (French zone) and the Lissbach road bridge (Prussian side). France: Davout HQ; 25e,
  85e, 21e, 12e, battery; Friant's 108e and 111e arriving at 4 and 5 min. Prussia: Brunswick HQ;
  Schmettau's IR 21, IR 30, IR 22, Grenadiers Hanstein, battery; IR 23 Winning (*representative*
  of Wartensleben coming up); Blücher's Garde du Corps and Husaren Blücher. Moments: Gudin's
  squares (Blücher's cavalry routed or below 75 %: France +6); Brunswick struck down (Prussia −10).
- **Friant at Spielberg** (`auerstedt_spielberg`, midday). Friant swings round the Prussian left;
  objectives Spielberg (neutral) and Poppel (by the Prussian zone). France: Friant HQ; 33e, 48e,
  108e, 111e; III Corps battery; 12e Chasseurs. Prussia: Orange's division as in the full battle
  (*representative* names) with the Leib-Kürassiere and Dragoner Königin. Moments: Spielberg falls
  (Orange's division −6); the reserve does not come (minute 7 and Prussia below 80 %: Prussia −6).
- **Soult on the Pratzen** (`austerlitz_pratzen`, morning, fog 2½ min). Saint-Hilaire and
  Vandamme climb the plateau; objectives Pratzen Heights and Staré Vinohrady (allied zone). France:
  Soult HQ; 10e Légère, 14e, 36e; 24e Légère, 4e, 28e, 57e; IV Corps battery. Allies: Kutuzov HQ
  (he was with the 4th column and was wounded on the plateau); Novgorod, Apsheron, IR 23 Salzburg,
  IR 20 Kaunitz, Austrian battery; Preobrazhensky and Semenovsky Guards arriving at 4 and 5 min;
  Chevalier Guards held. Moments: the Sun of Austerlitz (France +8); the Chevalier Guards (minute 5
  and the Pratzen held 1 min: releases them).
- **Davout at Sokolnitz** (`austerlitz_sokolnitz`, morning, fog 3 min). Legrand holds Telnitz and
  Sokolnitz (both objectives, French zone) against three columns coming down from the Pratzen;
  Friant arrives up the Raigern road at 1½–2½ min. France: Davout HQ; Legrand's 3e de Ligne (who
  held Telnitz), 26e Légère, Tirailleurs du Pô; Legrand's battery (*representative*); 15e Dragons
  (*representative* of Bourcier's dragoon division); Friant's 48e, 108e, 15e Légère. Allies:
  Buxhöwden HQ (he commanded the allied left); Székler Grenz; Dokhturov's Novo-Ingermanland,
  Yaroslavl and battery; Langeron's Vyborg and Perm; Przhebishevsky's Galicia and Narva. Moments:
  Friant comes up (108e within 200 of Sokolnitz: France +6; Friant's men marched about 110 km from
  Vienna in roughly two days); the columns are stuck (minute 6, both villages French: allies −6).
- **The struggle for Hougoumont** (`waterloo_hougoumont`, from 11:30, mud). Reille against the
  farm (objective, allied zone). France: Reille HQ; Jérôme's 1er Légère, 3e and 1er de Ligne; Foy's
  92e and 100e; Bachelu's 2e Légère; II Corps battery (*representative*); Piré's 6e Lanciers.
  Allies: Cooke HQ; 2/3rd Foot Guards (in the château), 2/2nd Coldstream, 2/1st and 3/1st Foot
  Guards; 1st Bn 2nd Nassau (in the orchard); Bull's Troop RHA (its howitzers shelled the wood).
  Moments: the north gate (a French formation within 45 of the farm: Byng's Guards +8 —
  Sous-lieutenant Legros of the 1er Légère axed the gate open and Lt-Col Macdonell's Coldstreamers
  forced it shut); Hougoumont ablaze (minute 4, French within 180: Guards and Nassauers −5).
- **The fall of La Haye Sainte** (`waterloo_lahayesainte`, evening, mud). Ney's final attack on
  the farm on the Brussels road; objectives La Haye Sainte and the crossroads (allied zone). France:
  Ney HQ; Donzelot's 13e Légère and 51e; Quiot's 54e, 55e and 105e; the 12-pounders of the Grand
  Battery; Milhaud's 1er and 4e Cuirassiers (Dubois' brigade). Allies: Alten HQ; Baring's 2nd Light
  Battalion KGL in the farm; 1/95th Rifles in the sandpit; Ompteda's 5th and 8th Line KGL;
  Halkett's 30th and 73rd; Ross's Troop RHA. Moments: the rifles fall silent (minute 4, French
  within 200 of the farm: 2nd Light KGL −10 — Baring's Baker-rifle ammunition never arrived); La
  Haye Sainte has fallen (Alten's division −8; it fell around 18:30 and French guns came up to
  within musket range of Wellington's centre).
