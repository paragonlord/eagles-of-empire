--!strict
-- Buildings (docs/rules.md "Buildings"): the heart of every village or farm (MapGen strongpoints)
-- holds one infantry battalion. A Garrison order marches it there and, if the building is free,
-- moves it in (shape "garrison", Config.Shapes). Any shape change away from "garrison" — a new
-- march, a Shape order, a rout — gives the building up.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Vec = require(Shared.Vec)
local Formation = require(script.Parent.Formation)

type Formation = Formation.Formation
type Vec = Vec.Vec

export type Strongpoint = { id: string, name: string, pos: Vec, holder: number? }

type SimLike = {
	tick: number,
	order: { number },
	formations: { [number]: Formation },
	strongpoints: { [string]: Strongpoint },
	map: any,
	emit: (any, any) -> (),
}

local Garrison = {}

local ENTER_DIST = 24 -- studs from the building's heart

function Garrison.init(sim: SimLike)
	sim.strongpoints = {}
	local list: { any } = sim.map.strongpoints or {}
	for _, sp in list do
		local entry: Strongpoint = { id = sp.id :: string, name = sp.name :: string, pos = sp.pos :: Vec }
		sim.strongpoints[entry.id] = entry
	end
end

local function release(sim: SimLike, f: Formation)
	local sp = f.garrison and sim.strongpoints[f.garrison]
	if sp and sp.holder == f.id then
		sp.holder = nil
	end
	f.garrison = nil
end

-- Leaving under orders: the battalion files out (reform time) and then carries out its order.
function Garrison.leave(f: Formation)
	if f.garrison and f.shape == "garrison" and f.pendingShape == nil then
		Formation.beginShape(f, "column", false)
	end
end

function Garrison.update(sim: SimLike)
	for _, id in sim.order do
		local f = sim.formations[id]
		if f and f.garrison then
			if not Formation.isActive(f) or f.state == "routing" then
				-- broken men pour out of the doors
				release(sim, f)
				if f.shape == "garrison" then
					f.shape = "column"
					f.pendingShape = nil
					Formation.refreshFootprint(f)
				end
			elseif f.shape ~= "garrison" and f.pendingShape ~= "garrison" then
				release(sim, f)
			end
		end
	end
	for _, id in sim.order do
		local f = sim.formations[id]
		local o = f and f.order
		if f and o and o.kind == "Garrison" and o.strongpoint and not f.garrison and Formation.isActive(f) and f.state ~= "routing" then
			local sp = sim.strongpoints[o.strongpoint]
			if not sp then
				Formation.clearOrder(f)
			elseif Vec.dist(f.pos, sp.pos) <= ENTER_DIST then
				local holder = sp.holder and sim.formations[sp.holder]
				if holder and holder.faction ~= f.faction then
					-- held by the enemy: storm it
					f.order = { kind = "Charge", targetId = holder.id, issuedTick = sim.tick, anchor = { x = f.pos.x, z = f.pos.z } }
					f.state = "charging"
					f.runUp = 0
				elseif holder then
					Formation.clearOrder(f)
					sim.emit(sim, { kind = "message", tick = sim.tick, id = f.id, faction = f.faction, text = f.name .. ": " .. sp.name .. " is already held" })
				else
					sp.holder = f.id
					f.garrison = sp.id
					f.pos = { x = sp.pos.x, z = sp.pos.z }
					f.path = nil
					f.order = { kind = "Hold", issuedTick = sim.tick }
					f.prevShape = nil
					Formation.beginShape(f, "garrison", false)
					sim.emit(sim, { kind = "message", tick = sim.tick, id = f.id, faction = f.faction, x = sp.pos.x, z = sp.pos.z, text = f.name .. " garrisons " .. sp.name })
				end
			end
		end
	end
end

return Garrison
