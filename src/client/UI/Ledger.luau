--!strict
-- What the client saw of its own army during one battle, for the results report: one record per
-- own formation (start, last strength, final status) and counts of squares, charges, routs,
-- rallies and losses. Survives the HUD teardown at the end of a battle; resets per match.

local BattleState = require(script.Parent.Parent.BattleState)

local Ledger = {}

export type Record = {
	id: number,
	name: string,
	corps: string,
	class: string,
	start: number,
	last: number,
	status: string,
	shape: string,
	squares: number,
	kills: number, -- enemy casualties it inflicted (own formations; the server counts)
}

export type Counts = {
	squares: number,
	ownCharges: number,
	enemyCharges: number,
	ownRouts: number,
	enemyRouts: number,
	ownRallies: number,
	ownDestroyed: number,
	enemyDestroyed: number,
	gunsLost: number,
	ownIntoSquares: number, -- our charges that met a formed square
	enemyIntoSquares: number,
}

local matchId = ""
local records: { [number]: Record } = {}
local order: { number } = {}
local counts: Counts

local STATUS: { [string]: string } = { idle = "Holding", moving = "Marching", reforming = "Reforming", firing = "Firing", charging = "Charging", melee = "In melee", retreating = "Retreating", routing = "Routing", rallying = "Rallying" }

local FINAL: { [string]: boolean } = { Destroyed = true, ["Off the field"] = true, ["Guns abandoned"] = true, ["Fled the field"] = true }

local function reset()
	table.clear(records)
	table.clear(order)
	counts = { squares = 0, ownCharges = 0, enemyCharges = 0, ownRouts = 0, enemyRouts = 0, ownRallies = 0, ownDestroyed = 0, enemyDestroyed = 0, gunsLost = 0, ownIntoSquares = 0, enemyIntoSquares = 0 }
end
reset()

local function sync()
	if BattleState.matchId ~= matchId then
		matchId = BattleState.matchId
		reset()
	end
end

-- Called on every snapshot with the own formations currently on the field.
function Ledger.observe(forms: { any })
	sync()
	local present: { [number]: boolean } = {}
	for _, f in forms do
		present[f.id] = true
		local found = records[f.id]
		local r: Record
		if found then
			r = found
		else
			r = { id = f.id :: number, name = tostring(f.name or ("#" .. f.id)), corps = tostring(f.corps or ""), class = tostring(f.class), start = tonumber(f.startStrength) or 0, last = tonumber(f.strength) or 0, status = "", shape = tostring(f.shape), squares = 0, kills = 0 }
			records[f.id] = r
			table.insert(order, f.id)
		end
		local shape: string = tostring(f.shape)
		local was: string = r.shape
		if shape == "square" and was ~= "square" then
			r.squares += 1
			counts.squares += 1
		end
		r.shape = shape
		r.last = tonumber(f.strength) or 0
		r.kills = tonumber(f.kills) or r.kills
		r.status = if f.moraleBand == "shattered" then "Shattered" else (STATUS[f.state] or f.state)
	end
	for id, r in records do
		if not present[id] and not FINAL[r.status] then
			r.status = "Off the field"
		end
	end
end

function Ledger.onEvent(ev: any)
	sync()
	local ours = ev.faction == BattleState.viewerFaction
	local r = if ev.id then records[ev.id] else nil
	if ev.kind == "charge" then
		local square = ev.text == "square"
		if ours then
			counts.ownCharges += 1
			counts.ownIntoSquares += if square then 1 else 0
		else
			counts.enemyCharges += 1
			counts.enemyIntoSquares += if square then 1 else 0
		end
	elseif ev.kind == "rout" then
		if r or ours then
			counts.ownRouts += 1
		else
			counts.enemyRouts += 1
		end
	elseif ev.kind == "rally" and (r or ours) then
		counts.ownRallies += 1
	elseif ev.kind == "destroyed" then
		local text = tostring(ev.text or "")
		if r then
			counts.ownDestroyed += 1
			if string.find(text, "guns abandoned", 1, true) then
				r.status = "Guns abandoned"
				counts.gunsLost += 1
			elseif string.find(text, "fled the field", 1, true) then
				r.status = "Fled the field"
			else
				r.status = "Destroyed"
				r.last = 0
				if r.class == "artillery" then
					counts.gunsLost += 1
				end
			end
		elseif not ours then
			counts.enemyDestroyed += 1
		end
	end
end

-- Own formations in roster order.
function Ledger.records(): { Record }
	sync()
	local out = {}
	for _, id in order do
		table.insert(out, records[id])
	end
	table.sort(out, function(a: Record, b: Record)
		return a.id < b.id
	end)
	return out
end

function Ledger.counts(): Counts
	sync()
	return counts
end

return Ledger
