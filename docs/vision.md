# Eagles of Empire — vision and roadmap

What should stay with a player after they close the game: **the moment the fog lifted over the
Pratzen, the Guard advancing up the slope at Waterloo, the battalion that held the village and
earned its name.** Not "a strategy game on Roblox", but *their* Napoleonic war.

## Pillars (every feature must serve at least one)

1. **History you can feel.** Real battles, real places, real units and dates, presented like the
   best documentary you have ever *played*: dispatches, maps, music cues, cinematic moments. Accuracy
   in the facts; drama in the presentation.
2. **Command, not clicking.** Decisions that matter: formation against cavalry, ground and line of
   sight, the reserve committed at the right minute, the general's rally. Morale decides battles,
   not body counts.
3. **Moments.** Every battle is built around 2–3 scripted, condition-driven moments drawn from what
   actually happened (the sun of Austerlitz, the Guard's last attack, Davout holding at
   Hassenhausen). They fire when the player's battle makes them plausible, not on a timer alone.
4. **Your army has a story.** Named regiments that survive carry battle honours, experience and a
   short chronicle; generals gain traits; losses are remembered in the campaign.
5. **Play together.** A battle is better with a friend commanding the other wing.

## Tone

Historical with drama. Strict accuracy in names, dates, orders of battle and outcomes (documented in
`docs/battles.md`); heroic framing in presentation (music swells, speeches, slow camera on the
key moment). Where they conflict, the facts win and the drama adapts.

## Modes and session length

- **Quick battles (8–10 min):** "episodes" — a historically real slice of each battle (e.g. Lannes
  at Vierzehnheiligen, the defence of La Haye Sainte) with ~8 formations a side and one objective.
  The default for new and casual players.
- **Full battles (20–30 min):** the whole field.
- **Grand campaign (1805–1815)** and the **Thuringian campaign** (short).
- **Tutorial:** the prologue.

## Roadmap (order chosen for impact; each phase ends with Studio playtests)

1. **Make it unforgettable solo** *(now)*: historical moments system, sound and music (needs Creator
   Store audio ids, see below), generals with abilities, quick-battle episodes, the art polish loop.
2. **Co-op** vs AI: 2–4 players split the army by corps/wing, shared pause by vote, ping markers.
3. **PvP**: historical battles and episodes player vs player, balance pass, simple matchmaking by
   lobby; ranked later.
4. **Mobile**: touch controls (tap select, drag move, radial orders), larger UI scale.
5. **Live polish**: more battles (Marengo, Borodino, Wagram, Leipzig), more campaign events.

## Audio (the one thing code alone cannot provide)

Sound is half of what makes battles memorable, and the game is silent today. Roblox requires
sounds to be assets: they must come from the Creator Store (free, licensed for use in Roblox
experiences) or be uploaded by the owner. Needed, in priority order: musket volley (several
variants), cannon, distant cannon, drums (march, pas de charge), fife/bugle calls, cavalry
gallop/charge, crowd "Vive l'Empereur!", ambient wind/birds, 3–4 music tracks (calm deployment,
battle, victory, defeat; public-domain period pieces such as Marseillaise arrangements, Beethoven,
period marches are ideal). Ids go into `src/client/Audio.luau`'s registry; nothing else changes.
