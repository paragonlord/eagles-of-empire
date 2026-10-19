--!strict
-- Scripted events (EuropeData.Events): each fires once, at the first turn of its window whose
-- conditions hold. Base effects apply at once; a chooser picks one of the choices: the player
-- through a pop-up (default = the first choice, applied at the end of the turn if unanswered), an
-- AI always the first (historical) one. Every fired event is reported to the player's inbox.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local EuropeData = require(Shared.EuropeData)
local State = require(script.Parent.State)
local Diplomacy = require(script.Parent.Diplomacy)
local Economy = require(script.Parent.Economy)

type State = State.State

local Events = {}

local byId: { [string]: EuropeData.Event } = {}
for _, e in EuropeData.Events do
	byId[e.id] = e
end

local function check(s: State, c: { any }): boolean
	local k = c[1]
	if k == "atWar" then
		return State.atWar(s, c[2], c[3])
	elseif k == "notAtWar" then
		return not State.atWar(s, c[2], c[3])
	elseif k == "allied" then
		return State.allied(s, c[2], c[3])
	elseif k == "notAllied" then
		return not State.allied(s, c[2], c[3])
	elseif k == "controls" then
		return State.controller(s, c[3]) == c[2]
	elseif k == "notControls" then
		return State.controller(s, c[3]) ~= c[2]
	elseif k == "enemyControls" then
		return State.atWar(s, c[2], State.controller(s, c[3]))
	elseif k == "flag" then
		return s.flags[c[2]] == true
	elseif k == "notFlag" then
		return s.flags[c[2]] ~= true
	elseif k == "lostTo" then
		local p = s.peaces[State.pair(c[2], c[3])]
		return p ~= nil and p.winner == c[3]
	elseif k == "any" then
		for i = 2, #c do
			if check(s, c[i]) then
				return true
			end
		end
		return false
	end
	error("unknown event condition " .. tostring(k))
end
Events.check = check

function Events.conditionsHold(s: State, e: EuropeData.Event): boolean
	for _, c in e.condition or {} do
		if not check(s, c) then
			return false
		end
	end
	return true
end

local function abdicate(s: State, nation: string)
	local enemies = State.enemiesOf(s, nation)
	s.abdicatedTo = enemies
	s.flags.abdicated = true
	for _, e in enemies do
		Diplomacy.makePeace(s, e, nation, e)
	end
end

function Events.apply(s: State, effects: { EuropeData.Effect })
	for _, f in effects do
		local op = f.op
		if op == "war" then
			if not State.atWar(s, f.a, f.b) then
				if State.allied(s, f.a, f.b) then
					Diplomacy.breakAlliance(s, f.a, f.b)
				end
				Diplomacy.declareWar(s, f.a, f.b)
			end
		elseif op == "coalition" then
			Diplomacy.coalition(s, f.members, f.against)
		elseif op == "alliance" then
			Diplomacy.makeAlliance(s, f.a, f.b)
		elseif op == "forcedAlliance" then
			if not State.atWar(s, f.a, f.b) then
				Diplomacy.makeAlliance(s, f.a, f.b)
			end
		elseif op == "breakAlliance" then
			Diplomacy.breakAlliance(s, f.a, f.b)
		elseif op == "peace" then
			Diplomacy.makePeace(s, f.a, f.b)
		elseif op == "flag" then
			s.flags[f.name] = if f.value == false then nil else true
		elseif op == "sinkFleets" then
			for i = #s.fleets, 1, -1 do
				if table.find(f.nations, s.fleets[i].nation) then
					table.remove(s.fleets, i)
				end
			end
		elseif op == "relation" then
			State.addRelation(s, f.a, f.b, f.delta)
		elseif op == "treasury" then
			local ns = s.nations[f.nation]
			ns.treasury = math.max(0, ns.treasury + f.amount)
		elseif op == "attrition" then
			for _, a in State.armiesOf(s, f.nation) do
				if s.provinces[a.provinceId].owner == f.inOwnedBy then
					Economy.attrit(s, a, f.fraction)
				end
			end
			Economy.removeEmpty(s)
		elseif op == "spawnArmy" then
			for _, pid in f.provinces do
				local c = State.controller(s, pid)
				if State.friendly(s, f.nation, c) and not State.hostileArmyIn(s, pid, f.nation) then
					local wanted: State.General? = f.general
					local general: State.General? = if wanted and not State.generalInService(s, wanted.name) then wanted else nil
					local a = State.newArmy(s, f.nation, f.name, pid, general)
					State.addUnits(s, a, f.units, f.experience or 0)
					State.log(s, string.format("%s takes the field at %s.", f.name, State.province(pid).name))
					break
				end
			end
		elseif op == "abdicate" then
			abdicate(s, f.nation)
		else
			error("unknown event effect " .. tostring(op))
		end
	end
end

-- Fires the events due this turn.
function Events.run(s: State, autoplay: boolean?)
	for _, e in EuropeData.Events do
		if not s.fired[e.id] and s.turn >= e.turn and s.turn <= (e.untilTurn or e.turn) and Events.conditionsHold(s, e) then
			s.fired[e.id] = true
			State.log(s, e.title .. ".")
			Events.apply(s, e.effects)
			local entry: State.Inbox = { id = e.id, title = e.title, text = e.text, turn = s.turn, choices = nil }
			if e.choices then
				if e.chooser == s.playerNation and not autoplay then
					local list = {}
					for _, c in e.choices do
						list[#list + 1] = { id = c.id, label = c.label }
					end
					entry.choices = list
				else
					Events.apply(s, e.choices[1].effects)
				end
			end
			s.inbox[#s.inbox + 1] = entry
			if s.flags.abdicated then
				return
			end
		end
	end
end

-- Player answer. Choiceless events can be acknowledged (choice nil) to drop them from the inbox.
function Events.choose(s: State, eventId: string, choiceId: string?): (boolean, string?)
	for i, entry in s.inbox do
		if entry.id == eventId then
			if entry.choices == nil then
				table.remove(s.inbox, i)
				return true, nil
			end
			local e = byId[eventId]
			local pick: EuropeData.Choice? = nil
			for _, c in (e.choices :: { EuropeData.Choice }) do
				if c.id == choiceId then
					pick = c
				end
			end
			if not pick then
				return false, "unknownChoice"
			end
			table.remove(s.inbox, i)
			State.log(s, e.title .. ": " .. (pick :: EuropeData.Choice).label .. ".")
			Events.apply(s, (pick :: EuropeData.Choice).effects)
			return true, nil
		end
	end
	return false, "unknownEvent"
end

-- End of turn: unanswered choices take their default; the read news is cleared.
function Events.closeTurn(s: State)
	for _, entry in table.clone(s.inbox) do
		if entry.choices then
			Events.choose(s, entry.id, entry.choices[1].id)
		end
	end
	table.clear(s.inbox)
end

return Events
