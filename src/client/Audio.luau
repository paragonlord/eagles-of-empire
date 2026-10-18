--!strict
-- The audio layer: a mixer of buses (master → sfx / music / ambience / ui, each a SoundGroup
-- bound live to Settings), positional one-shots anchored at the event with a roll-off scaled
-- by camera height (loud and crisp from low, quieter and muffled from high), per-key cooldowns
-- and concurrency caps so twenty volleys do not stack into a wall, random variant and pitch,
-- faded loops (marching drums per faction near the camera, a melee loop while a melee is in
-- view, ambience by weather) and a music state machine (menu → deployment → battle calm/tense
-- by a tension score of the last 20 s of events → victory/defeat sting) with crossfades.
-- Asset ids live in Assets.sounds; a slot with no id plays nothing and creates nothing.
-- Settings.debugAudio prints "[EoE audio] key (variant) at d=… vol=…" for every hook.

local SoundService = game:GetService("SoundService") :: SoundService
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Assets = require(Shared.Assets)
local Settings = require(script.Parent.Settings)
local Signal = require(script.Parent.Signal)
local BattleState = require(script.Parent.BattleState)
local Camera = require(script.Parent.Camera)

local Audio = {}

type Slot = Assets.Sound
type Bus = "sfx" | "music" | "ambience" | "ui"
type Gate = { last: number, live: number }
type Loop = { sound: Sound, level: number, target: number, base: number }

local SOUNDS = Assets.sounds :: { [string]: Slot }

-- Per-key floor between plays (s) and cap on simultaneous instances; others take the default.
local COOLDOWN: { [string]: number } = { musketVolley = 0.12, musketScatter = 0.3, cannonFire = 0.1, cannonBounce = 0.15, canister = 0.2, cavalryCharge = 0.5, bugleCharge = 2, bugleRally = 2, rout = 0.8, unitDestroyed = 1, uiHover = 0.05, uiPaper = 0.3, uiSeal = 0.3, capture = 1, objectiveLost = 1 }
local CAP: { [string]: number } = { musketVolley = 5, cannonFire = 4, cannonBounce = 4, canister = 3, cavalryCharge = 2, cavalryImpact = 2, rout = 2, unitDestroyed = 2, uiHover = 1, uiClick = 2 }
Audio.DEFAULT_COOLDOWN = 0.05
Audio.DEFAULT_CAP = 4

-- Tension: weight per event kind, summed with linear decay over TENSION_WINDOW seconds;
-- the music turns tense above TENSE_ON and calm again below TENSE_OFF (hysteresis).
local TENSION_WEIGHT: { [string]: number } = { volley = 1, cannon = 1.5, charge = 3, melee = 2, rout = 4, destroyed = 5, capture = 3 }
Audio.TENSION_WINDOW = 20
Audio.TENSE_ON = 12
Audio.TENSE_OFF = 5

local NEAR = 400 -- studs from the camera focus for drums and melee loops
local DRUMS: { [string]: string } = { france = "drumsMarchFr", saxony = "drumsMarchFr", bavaria = "drumsMarchFr", prussia = "drumsMarchPr", austria = "drumsMarchAt", russia = "drumsMarchRu", britain = "drumsMarchGb", netherlands = "drumsMarchGb" }
local FADE_IN, FADE_OUT = 1.5, 2.5 -- seconds (loops; music crossfades use the same)
local DUCK = 0.25 -- music level under a moment sting
local DUCK_FOR = 5

local buses: { [string]: SoundGroup } = {}
local master: SoundGroup? = nil
local eq: EqualizerSoundEffect? = nil
local anchors: Folder? = nil
local gates: { [string]: Gate } = {}
local loops: { [string]: Loop } = {}
local events: { { t: number, w: number } } = {}
local tense = false
local scene = "menu"
local musicKey: string? = nil
local duckUntil = 0
local scanClock = 0
local settingsConn: Signal.Connection? = nil

-- ------------------------------------------------------------------ pure (tests/audio.spec)

-- Roll-off for a camera `height` studs above the ground: the reach of a positional sound, the
-- volume scale and the treble cut (dB) of the sfx bus. Low: short reach, full, bright. High:
-- long reach (the listener is far from everything), quieter, muffled.
function Audio.rolloff(height: number): (number, number, number)
	local h = math.max(height, 0)
	local reach = 250 + h * 2.5
	local scale = math.clamp(1 - (h - 150) / 1200, 0.4, 1)
	return reach, scale, -12 * (1 - scale) / 0.6
end

-- Admits a play of a key at `now` unless its last play was under `cooldown` ago or `cap`
-- instances are live; on admission the gate counts the instance (Audio.release returns it).
function Audio.gate(g: Gate, now: number, cooldown: number, cap: number): boolean
	if now - g.last < cooldown or g.live >= cap then
		return false
	end
	g.last = now
	g.live += 1
	return true
end

function Audio.release(g: Gate)
	g.live = math.max(0, g.live - 1)
end

-- Tension score: the weights of events in the last `window` seconds, each fading linearly.
function Audio.tension(list: { { t: number, w: number } }, now: number, window: number): number
	local s = 0
	for _, e in list do
		local age = now - e.t
		if age >= 0 and age < window then
			s += e.w * (1 - age / window)
		end
	end
	return s
end

-- The music mood with hysteresis: tense once the score passes TENSE_ON, calm again under TENSE_OFF.
function Audio.mood(score: number, wasTense: boolean): boolean
	if wasTense then
		return score > Audio.TENSE_OFF
	end
	return score >= Audio.TENSE_ON
end

-- A loop's level for the nearest source at `dist` studs: full inside a quarter of NEAR, gone at NEAR.
function Audio.nearLevel(dist: number): number
	return math.clamp((NEAR - dist) / (NEAR * 0.75), 0, 1)
end

-- ------------------------------------------------------------------ slots

local function idOf(key: string): (string?, number)
	local slot = SOUNDS[key]
	if not slot then
		return nil, 0
	end
	local id = slot.id
	if type(id) == "table" then
		if #id == 0 then
			return nil, 0
		end
		local i = math.random(1, #id)
		return id[i], i
	end
	if id == "" then
		return nil, 0
	end
	return id, 1
end

local function busOf(key: string): Bus
	if string.sub(key, 1, 2) == "ui" then
		return "ui"
	elseif string.sub(key, 1, 8) == "ambience" then
		return "ambience"
	elseif string.find(key, "Music") then
		return "music"
	end
	return "sfx"
end

local function debug(key: string, variant: number, dist: number?, vol: number, note: string?)
	if Settings.get().debugAudio then
		print(string.format("[EoE audio] %s (%d) at d=%s vol=%.2f%s", key, variant, if dist then string.format("%.0f", dist) else "-", vol, note or ""))
	end
end

local function focusDist(x: number?, z: number?): number?
	if not x or not z then
		return nil
	end
	local fx, fz = Camera.getFocus()
	return math.sqrt((x - fx) ^ 2 + (z - fz) ^ 2)
end

local function makeSound(key: string, id: string, slot: Slot, bus: Bus): Sound
	local s = Instance.new("Sound") :: Sound
	s.Name = key
	s.SoundId = id
	s.Looped = slot.loop == true
	s.SoundGroup = buses[bus]
	s.PlaybackSpeed = slot.pitch[1] + math.random() * (slot.pitch[2] - slot.pitch[1])
	return s
end

-- ------------------------------------------------------------------ mixer

local function applyVolumes()
	local v = Settings.get()
	if master then
		master.Volume = v.master
	end
	for name, g in buses do
		local level = (v :: any)[name]
		g.Volume = if type(level) == "number" then level else 1
	end
end

function Audio.init()
	if master then
		return
	end
	local m = Instance.new("SoundGroup") :: SoundGroup
	m.Name = "EoEAudio"
	m.Parent = SoundService
	master = m
	for _, name in { "sfx", "music", "ambience", "ui" } do
		local g = Instance.new("SoundGroup") :: SoundGroup
		g.Name = name
		g.Parent = m
		buses[name] = g
	end
	local e = Instance.new("EqualizerSoundEffect") :: EqualizerSoundEffect
	e.LowGain = 0
	e.MidGain = 0
	e.HighGain = 0
	e.Parent = buses.sfx
	eq = e
	local f = Instance.new("Folder") :: Folder
	f.Name = "EoEAudio"
	f.Parent = workspace
	anchors = f
	applyVolumes()
	settingsConn = Settings.changed:Connect(applyVolumes)
end

-- True when no slot has an id (the settings panel says so).
function Audio.isSilent(): boolean
	for _, slot in SOUNDS do
		local id = slot.id
		if (type(id) == "table" and #id > 0) or (type(id) == "string" and id ~= "") then
			return false
		end
	end
	return true
end

-- ------------------------------------------------------------------ one-shots

-- Plays `key` once: at (x, z) on the field as a positional sound, else flat. No id: nothing.
function Audio.play(key: string, x: number?, z: number?)
	local slot = SOUNDS[key]
	if not slot or slot.loop then
		return
	end
	local g = gates[key]
	if not g then
		g = { last = -math.huge, live = 0 }
		gates[key] = g
	end
	if not Audio.gate(g, os.clock(), COOLDOWN[key] or Audio.DEFAULT_COOLDOWN, CAP[key] or Audio.DEFAULT_CAP) then
		return
	end
	local id, variant = idOf(key)
	local reach, scale = Audio.rolloff(Camera.height())
	local vol = slot.volume * (if x then scale else 1)
	debug(key, variant, focusDist(x, z), vol, if id then "" else " (no id)")
	if not id or not master then
		Audio.release(g)
		return
	end
	local s = makeSound(key, id, slot, busOf(key))
	s.Volume = vol
	local parent: Instance = master :: SoundGroup
	if x and z and anchors then
		local p = Instance.new("Part") :: Part
		p.Name = key
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.new(1, 1, 1)
		p.CFrame = CFrame.new(x, Camera.groundHeight(x, z) + 2, z)
		p.Parent = anchors
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 60
		s.RollOffMaxDistance = reach
		parent = p
	end
	s.Parent = parent
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		Audio.release(g)
		parent:Destroy()
	end
	s.Ended:Connect(finish)
	task.delay(12, finish) -- a sound that never loads still frees its slot
	s:Play()
end

-- ------------------------------------------------------------------ loops

-- Holds a loop at `level` (0..1 of its slot volume): started on the first call above 0,
-- faded by Audio.update, stopped and destroyed once faded out. No id: nothing.
local function setLoop(key: string, level: number)
	local l = loops[key]
	if l then
		l.target = level
		return
	end
	if level <= 0 then
		return
	end
	local slot = SOUNDS[key]
	if not slot or not slot.loop then
		return
	end
	local id, variant = idOf(key)
	debug(key, variant, nil, slot.volume * level, if id then " loop" else " loop (no id)")
	if not id or not master then
		return
	end
	local s = makeSound(key, id, slot, busOf(key))
	s.Volume = 0
	s.Parent = master
	s:Play()
	loops[key] = { sound = s, level = 0, target = level, base = slot.volume }
end

local function stepLoops(dt: number)
	local duck = if os.clock() < duckUntil then DUCK else 1
	for key, l in loops do
		local rate = if l.target > l.level then dt / FADE_IN else dt / FADE_OUT
		l.level = if l.target > l.level then math.min(l.target, l.level + rate) else math.max(l.target, l.level - rate)
		if l.level <= 0 and l.target <= 0 then
			l.sound:Destroy()
			loops[key] = nil
		else
			l.sound.Volume = l.base * l.level * (if busOf(key) == "music" then duck else 1)
		end
	end
end

-- Drums per faction with a marching formation near the camera, a melee loop near a melee.
local function scanField()
	local fx, fz = Camera.getFocus()
	local want: { [string]: number } = {}
	for _, f in BattleState.formations do
		local key = if f.state == "moving" and f.class == "infantry" then DRUMS[f.faction] elseif f.state == "melee" then "meleeClash" else nil
		if key then
			local d = math.sqrt((f.x - fx) ^ 2 + (f.z - fz) ^ 2)
			local level = Audio.nearLevel(d)
			if level > (want[key] or 0) then
				want[key] = level
			end
		end
	end
	for key, slot in SOUNDS do
		if slot.loop and (string.sub(key, 1, 5) == "drums" or key == "meleeClash") then
			setLoop(key, want[key] or 0)
		end
	end
end

-- ------------------------------------------------------------------ ambience and music

-- Scenario weather: fog → the muffled loop, rain/mud/snow → rain, anything else → the field.
function Audio.setWeather(weather: string?)
	local key = if weather == "fog" then "ambienceFog" elseif weather == "rain" or weather == "mud" or weather == "snow" then "ambienceRain" else "ambienceField"
	for _, k in { "ambienceField", "ambienceRain", "ambienceFog" } do
		setLoop(k, if k == key then 1 else 0)
	end
end

local function setMusic(key: string?)
	if key == musicKey then
		return
	end
	if musicKey then
		setLoop(musicKey, 0)
	end
	musicKey = key
	if key then
		setLoop(key, 1)
	end
end

local function musicFor(): string?
	if scene == "menu" then
		return "menuMusic"
	elseif scene == "campaign" then
		return "campaignMusic"
	elseif scene == "deployment" then
		return "battleMusicCalm"
	elseif scene == "battle" then
		return if tense then "battleMusicTense" else "battleMusicCalm"
	end
	return nil
end

-- The screen the player is on; results stop the music and play the verdict's sting.
function Audio.setScene(name: "menu" | "campaign" | "deployment" | "battle" | "results", outcome: string?)
	if name ~= scene then
		table.clear(events)
		tense = false
		scene = name
	end
	setMusic(musicFor())
	if name == "results" then
		if outcome == "victory" then
			Audio.play("victory")
		elseif outcome == "defeat" then
			Audio.play("defeat")
		end
	end
end

-- ------------------------------------------------------------------ events

local function at(ev: any): (number?, number?)
	if type(ev.x) == "number" and type(ev.z) == "number" then
		return ev.x, ev.z
	end
	local f = BattleState.formations[ev.id or -1]
	if f then
		return f.x, f.z
	end
	return nil, nil
end

-- A snapshot event from the server (Types.Event), as Effects draws it.
function Audio.onEvent(ev: any)
	if type(ev) ~= "table" then
		return
	end
	local kind = ev.kind
	local w = TENSION_WEIGHT[kind]
	if w then
		table.insert(events, { t = os.clock(), w = w })
	end
	local x, z = at(ev)
	local f = BattleState.formations[ev.id or -1]
	local cavalry = f ~= nil and f.class == "cavalry"
	if kind == "volley" then
		-- a line thinned under a third of its strength fires ragged, scattered shots
		Audio.play(if f and f.strength < f.startStrength * 0.35 then "musketScatter" else "musketVolley", x, z)
	elseif kind == "cannon" then
		Audio.play(if ev.text == "canister" then "canister" else "cannonFire", x, z)
		if ev.text ~= "canister" and type(ev.tx) == "number" and type(ev.tz) == "number" then
			local d = math.sqrt((ev.tx - (x or ev.tx)) ^ 2 + (ev.tz - (z or ev.tz)) ^ 2)
			task.delay(d / 280, Audio.play, "cannonBounce", ev.tx, ev.tz)
		end
	elseif kind == "charge" then
		Audio.play("bugleCharge", x, z)
		if cavalry then
			Audio.play("cavalryCharge", x, z)
		end
	elseif kind == "melee" then
		if cavalry then
			Audio.play("cavalryImpact", x, z)
		end
	elseif kind == "rout" then
		Audio.play("rout", x, z)
	elseif kind == "rally" then
		Audio.play("bugleRally", x, z)
	elseif kind == "destroyed" then
		Audio.play("unitDestroyed", x, z)
	elseif kind == "capture" then
		Audio.play(if ev.faction == BattleState.viewerFaction then "capture" else "objectiveLost")
	elseif kind == "moment" then
		duckUntil = os.clock() + DUCK_FOR
		Audio.play("momentSting")
	end
end

-- ------------------------------------------------------------------ frame

function Audio.update(dt: number)
	if not master then
		return
	end
	stepLoops(dt)
	scanClock += dt
	if scanClock < 0.25 then
		return
	end
	scanClock = 0
	if eq then
		local _, _, cut = Audio.rolloff(Camera.height())
		eq.HighGain = cut
	end
	if scene == "battle" or scene == "deployment" then
		scanField()
	end
	if scene == "battle" then
		local now = os.clock()
		for i = #events, 1, -1 do
			if now - events[i].t > Audio.TENSION_WINDOW then
				table.remove(events, i)
			end
		end
		local was = tense
		tense = Audio.mood(Audio.tension(events, now, Audio.TENSION_WINDOW), tense)
		if tense ~= was then
			setMusic(musicFor())
		end
	end
end

function Audio.destroy()
	if settingsConn then
		settingsConn:Disconnect()
		settingsConn = nil
	end
	for _, l in loops do
		l.sound:Destroy()
	end
	table.clear(loops)
	table.clear(gates)
	table.clear(events)
	musicKey = nil
	if anchors then
		anchors:Destroy()
		anchors = nil
	end
	if master then
		master:Destroy()
		master = nil
	end
	table.clear(buses)
	eq = nil
end

return Audio
