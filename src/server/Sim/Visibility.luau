--!strict
-- Per-faction visibility: which enemy formations are currently seen, and last-known memory.
-- Recomputed every Config.Sim.VisibilityEveryTicks ticks (step 5). The AI and the snapshot
-- filter both read this; nothing else decides what a faction knows.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Vec = require(Shared.Vec)
local Types = require(Shared.Types)

local Formation = require(script.Parent.Formation)

type Formation = Formation.Formation

export type FactionView = {
	visible: { [number]: boolean },
	lastKnown: { [number]: Types.LastKnown },
	lastSeenTick: { [number]: number },
	lastSeenPos: { [number]: { x: number, z: number, heading: number, shape: Types.Shape, width: number, depth: number } },
}

export type SimLike = {
	grid: Grid.Grid,
	tick: number,
	formations: { [number]: Formation },
	order: { number },
	factions: { string },
	views: { [string]: FactionView },
	weather: string?,
}

local Visibility = {}

function Visibility.newView(): FactionView
	return { visible = {}, lastKnown = {}, lastSeenTick = {}, lastSeenPos = {} }
end

local function canSee(sim: SimLike, observer: Formation, target: Formation): boolean
	local spot = Formation.unitConfig(observer).spot * ((Config.Weather :: any)[sim.weather or "clear"] or Config.Weather.clear).spot
	local d = Vec.dist(observer.pos, target.pos)
	if target.inWoods then
		spot = math.min(spot, Config.Vision.WoodsReveal)
	end
	if d > spot then
		return false
	end
	if d <= Config.Vision.WoodsReveal then
		return true
	end
	return Grid.lineOfSight(sim.grid, observer.pos, target.pos)
end

function Visibility.update(sim: SimLike)
	local dt = Config.Sim.DT
	for _, faction in sim.factions do
		local view = sim.views[faction]
		local newVisible: { [number]: boolean } = {}
		for _, tid in sim.order do
			local target = sim.formations[tid]
			if target and target.faction ~= faction and Formation.isActive(target) then
				local seen = false
				for _, oid in sim.order do
					local obs = sim.formations[oid]
					if obs and obs.faction == faction and Formation.isActive(obs) and obs.state ~= "routing" then
						if canSee(sim, obs, target) then
							seen = true
							break
						end
					end
				end
				if seen then
					newVisible[tid] = true
					view.lastSeenTick[tid] = sim.tick
					view.lastSeenPos[tid] = { x = target.pos.x, z = target.pos.z, heading = target.heading, shape = target.shape, width = target.width, depth = target.depth }
					view.lastKnown[tid] = nil
				elseif view.visible[tid] then
					-- Just lost sight: freeze what was last actually seen (not the current state).
					local seenAt = view.lastSeenPos[tid]
					if seenAt then
						view.lastKnown[tid] = {
							id = tid,
							faction = target.faction,
							class = target.class,
							x = seenAt.x,
							z = seenAt.z,
							heading = seenAt.heading,
							shape = seenAt.shape,
							ageSeconds = 0,
							name = target.name,
							colour = target.colour,
							width = seenAt.width,
							depth = seenAt.depth,
						}
					end
				end
			elseif target and not Formation.isActive(target) then
				view.lastKnown[tid] = nil
			end
		end
		view.visible = newVisible
		for id, lk in view.lastKnown do
			lk.ageSeconds = (sim.tick - (view.lastSeenTick[id] or sim.tick)) * dt
			if lk.ageSeconds > Config.Vision.LastKnownForgetSeconds then
				view.lastKnown[id] = nil
			end
		end
	end
	-- Mirror onto formations for cheap checks.
	for _, id in sim.order do
		local f = sim.formations[id]
		if f then
			for _, faction in sim.factions do
				f.visibleTo[faction] = faction == f.faction or sim.views[faction].visible[id] == true
			end
		end
	end
end

function Visibility.isVisibleTo(sim: SimLike, viewer: string, id: number): boolean
	local f = sim.formations[id]
	if not f then
		return false
	end
	if f.faction == viewer then
		return true
	end
	local view = sim.views[viewer]
	return view ~= nil and view.visible[id] == true
end

return Visibility
