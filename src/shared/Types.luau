--!strict
-- Shared type definitions. Runtime-free; `require` for types only.

local Vec = require(script.Parent.Vec)

export type Vec = Vec.Vec

export type UnitClass = "infantry" | "cavalry" | "artillery" | "hq"
export type Shape = "line" | "column" | "square" | "travel" | "limbered" | "deployed" | "wedge" | "staff"
export type State = "idle" | "moving" | "reforming" | "firing" | "charging" | "melee" | "retreating" | "routing" | "rallying" | "destroyed" | "exited" | "offmap"
export type MoraleBand = "steady" | "shaken" | "routing" | "shattered"

export type Order = {
	kind: string,
	pos: Vec?,
	heading: number?,
	targetId: number?,
	frontage: number?,
	issuedTick: number,
	anchor: Vec?, -- leash anchor for Engage/AttackMove
}

export type Command = {
	matchId: string,
	requestId: string,
	kind: string,
	ids: { number },
	data: { [string]: any }?,
	-- stamped by the server
	seq: number?,
	effectiveTick: number?,
	faction: string?,
}

export type CommandResult = {
	requestId: string,
	accepted: boolean,
	reason: string?,
	effectiveTick: number?,
}

-- Per-formation public view sent to clients (own side: full; enemy: visible subset).
export type FormationView = {
	id: number,
	faction: string,
	name: string?,
	corps: string?,
	class: UnitClass,
	colour: string?,
	x: number,
	z: number,
	heading: number,
	shape: Shape,
	state: State,
	strength: number,
	startStrength: number,
	morale: number?,
	moraleBand: MoraleBand,
	fatigue: number?,
	ammo: number?,
	reload: number?,
	cohesion: number?,
	width: number,
	depth: number,
	orderKind: string?,
	targetId: number?,
	fireAtWill: boolean?,
	limbered: boolean?,
	status: string?, -- strongest current cause of poor performance
	rallyCd: number?,
	commander: boolean?,
	dest: Vec?,
	destHeading: number?,
	experience: number?,
	ammoMode: string?,
	queue: { Vec }?,
	general: string?, -- own HQ: id in src/shared/Generals.luau
	abilityReadyAt: number?, -- own HQ: sim clock (s) when the general's ability is ready again
	tags: string?, -- own: comma-joined trait / ability ids affecting this formation now
}

export type LastKnown = {
	id: number,
	faction: string,
	class: UnitClass,
	x: number,
	z: number,
	heading: number,
	shape: Shape,
	ageSeconds: number,
	name: string?,
	colour: string?,
	width: number,
	depth: number,
}

export type ObjectiveView = {
	id: string,
	name: string,
	x: number,
	z: number,
	radius: number,
	owner: string?,
	contested: boolean,
	progress: number, -- 0..1 toward the capturing faction
	capturing: string?,
}

export type Event = {
	kind: string, -- volley | cannon | melee | charge | rout | rally | capture | destroyed | message
	x: number?,
	z: number?,
	id: number?,
	targetId: number?,
	faction: string?,
	text: string?,
	tick: number,
	tx: number?,
	tz: number?,
	n: number?,
}

export type Snapshot = {
	matchId: string,
	tick: number,
	seq: number,
	kind: "full" | "delta",
	state: string,
	formations: { FormationView },
	lastKnown: { LastKnown },
	events: { Event },
	objectives: { ObjectiveView },
	clock: number, -- simulation seconds
	timeLimit: number,
	speed: number,
	simLag: number,
	viewer: string,
	removed: { number }?,
	reinforcements: { { id: number, name: string, corps: string, eta: number } }?, -- own side, not yet arrived
	weather: string?, -- key into Config.Weather
}

export type Results = {
	outcome: "victory" | "defeat" | "draw",
	reason: string,
	clock: number,
	objectives: { ObjectiveView },
	sides: {
		[string]: {
			deployed: number,
			casualties: number,
			remaining: number,
			surviving: number,
			routed: number,
			shattered: number,
			destroyed: number,
			exited: number,
			formations: number,
		},
	},
	feedback: { string },
	log: { string },
}

return {}
