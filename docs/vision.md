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

Sound is half of what makes battles memorable. The audio layer is built (`src/client/Audio.luau`:
buses, positional one-shots rolled off by camera height, cooldowns and caps, faded loops, ambience
by weather, a music state machine with a tension score, moment stings that duck the music) and every
hook fires; only the asset ids are missing, so the game is silent until they are filled. Roblox
requires sounds to be assets owned or licensed for the experience: free audio from the Creator Store
is fine, as is audio the owner uploads. One slot per sound lives in `Assets.sounds`
(`src/shared/Assets.luau`): `{ id = "", volume, pitch = { min, max }, variants = n }`, keys in
priority order musketVolley (3 variants), cannonFire (3), canister, cannonBounce, cavalryCharge,
cavalryImpact, meleeClash (loop), drumsMarchFr/Pr/At/Ru/Gb (loops), bugleCharge, bugleRally,
rout, unitDestroyed, capture, objectiveLost, victory, defeat, momentSting, ambienceField / Rain /
Fog (loops), menuMusic, battleMusicCalm, battleMusicTense, campaignMusic, and the interface
(uiClick, uiHover, uiPaper, uiSeal, ping).

To fill a slot in Studio: Toolbox → Audio → filter Free → pick a sound → copy its asset id → set
`id = "rbxassetid://<id>"` (for a slot with `variants` > 1, a list:
`id = { "rbxassetid://a", "rbxassetid://b", "rbxassetid://c" }`). Nothing else changes: a slot
with no id plays nothing and costs nothing. Turn on **Audio log** in the settings panel
(`Settings.debugAudio`) to see every hook as `[EoE audio] key (variant) at d=… vol=…` in the
output before any id exists. Music: public-domain period pieces (Marseillaise arrangements,
Beethoven, period marches) suit the calm / tense / campaign / menu slots.
