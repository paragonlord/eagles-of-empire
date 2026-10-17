--!strict
-- Historical moments: scripted, condition-driven beats of a battle (docs/vision.md pillar 3).
-- Data lives on each scenario (`Scenarios.<id>.moments`); the server evaluates them in
-- src/server/Sim/Moments.luau and the client presents them in src/client/Cinematic.luau.
--
-- A Selector picks formations. Every field given must match: faction exactly, class exactly,
-- name and corps as plain substrings (no Lua patterns). Conditions are tables whose keys are all
-- required (AND); `any` gives OR, `all` groups. Effects are deliberately small: morale changes are
-- clamped to +/- MoraleLimit, a release brings named off-map formations on now, weather sets the
-- sky (a scenario's weatherUntil still clears it once passed).

local Moments = {}

export type Selector = {
	faction: string?,
	name: string?, -- plain substring of the formation name
	corps: string?, -- plain substring of the corps label
	class: string?,
	-- condition/effect extras
	fraction: number?, -- strengthBelow: current / starting strength of the selection
	objective: string?, -- formationNear: objective id to measure from
	pos: { x: number, z: number }?, -- formationNear: point to measure from (instead of objective)
	radius: number?, -- formationNear
	amount: number?, -- morale effect, clamped to +/- MoraleLimit
}

export type Condition = {
	time: number?, -- sim seconds >= time
	before: number?, -- sim seconds < before
	weatherCleared: boolean?, -- current weather is (true) / is not (false) clear
	objectiveTaken: { id: string, by: string, seconds: number? }?, -- owned by `by` (for `seconds`)
	formationRouted: Selector?, -- any selected formation routing, shattered or destroyed
	strengthBelow: Selector?, -- selected strength below `fraction` of its start
	formationNear: Selector?, -- any selected formation, on the field and not routing, within radius
	all: { Condition }?,
	any: { Condition }?,
}

export type Effect = {
	morale: { Selector }?, -- each selector with `amount`
	release: string?, -- substring of off-map formation names to bring on now
	weather: string?, -- key into Config.Weather
}

export type Moment = {
	id: string,
	title: string,
	text: string,
	when: Condition,
	camera: { x: number, z: number, height: number? }?,
	effect: Effect?,
	faction: string?, -- only this faction is told (when the text would be wrong for the other)
}

Moments.MoraleLimit = 15
Moments.EveryTicks = 10

-- Works on UnitDefs and Formations alike (both carry faction, name, corps, class).
function Moments.matches(sel: Selector, f: { faction: string, name: string, corps: string, class: string }): boolean
	if sel.faction and f.faction ~= sel.faction then
		return false
	end
	if sel.class and f.class ~= sel.class then
		return false
	end
	if sel.name and not string.find(f.name, sel.name, 1, true) then
		return false
	end
	if sel.corps and not string.find(f.corps, sel.corps, 1, true) then
		return false
	end
	return true
end

return Moments
