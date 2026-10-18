--!strict
-- World readiness gate. The loading screen stays up until (i) the server's world folder has
-- replicated (part count against its WorldReady attribute), (ii) terrain meshing has settled
-- (a grid of raycasts hits terrain three checks running) and (iii) two consecutive frames
-- ran under 20 ms. `step` is pure so the rule is testable; `wait` drives it on the engine.

local RunService = game:GetService("RunService") :: RunService

local Ready = {}

export type State = {
	t: number, -- seconds in the gate
	replicated: boolean,
	hits: number, -- consecutive raycast checks that all hit terrain
	settled: boolean,
	goodFrames: number, -- consecutive frames under the budget
	settleCap: number, -- seconds after which meshing counts as settled anyway
	replicateCap: number, -- seconds after which a missing world no longer blocks (offline menu)
}

export type Sample = {
	dt: number, -- seconds since the last sample
	replicated: boolean,
	allHit: boolean?, -- result of a raycast check, nil when none ran this sample
	frameMs: number?, -- last frame time, nil when no frame was measured
}

Ready.FRAME_MS = 20
Ready.CHECK_EVERY = 0.2
Ready.HITS_NEEDED = 3
Ready.FRAMES_NEEDED = 2

function Ready.new(settleCap: number?, replicateCap: number?): State
	return { t = 0, replicated = false, hits = 0, settled = false, goodFrames = 0, settleCap = settleCap or 20, replicateCap = replicateCap or 90 }
end

-- Feeds one sample; true once every condition holds.
function Ready.step(st: State, s: Sample): boolean
	st.t += s.dt
	st.replicated = s.replicated or st.t >= st.replicateCap
	if s.allHit ~= nil then
		st.hits = if s.allHit then st.hits + 1 else 0
	end
	if st.hits >= Ready.HITS_NEEDED or st.t >= st.settleCap then
		st.settled = true
	end
	if s.frameMs ~= nil then
		-- frames count only once the world is in and the ground has settled: earlier ones
		-- measure the loading itself
		if st.replicated and st.settled and s.frameMs < Ready.FRAME_MS then
			st.goodFrames += 1
		else
			st.goodFrames = 0
		end
	end
	return st.replicated and st.settled and st.goodFrames >= Ready.FRAMES_NEEDED
end

-- The server's world folder for `mapId`, when its WorldReady count of parts has replicated.
local function replicated(mapId: string): (boolean, number, number)
	local root = workspace:FindFirstChild("EoEWorld")
	if not root or root:GetAttribute("MapId") ~= mapId then
		return false, 0, 0
	end
	local expected = root:GetAttribute("WorldReady")
	if type(expected) ~= "number" then
		return false, 0, 0
	end
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n >= expected, n, expected
end

-- ~40 points over the map; true when a ray from above hits terrain at each of them.
local function allHit(map: any): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = false
	for i = 1, 8 do
		for j = 1, 5 do
			local x = map.width * (i - 0.5) / 8
			local z = map.depth * (j - 0.5) / 5
			local hit = workspace:Raycast(Vector3.new(x, 1000, z), Vector3.new(0, -2000, 0), params)
			if not hit or (hit.Instance :: Instance) ~= (workspace.Terrain :: Instance) then
				return false
			end
		end
	end
	return true
end

-- Blocks until the world for `mapId` is ready to show, or `alive` turns false (superseded).
function Ready.wait(mapId: string, map: any, alive: () -> boolean, onProgress: ((fraction: number, text: string) -> ())?): boolean
	local st = Ready.new()
	local sinceCheck = Ready.CHECK_EVERY
	local last = os.clock()
	while alive() do
		local dt = RunService.RenderStepped:Wait()
		local now = os.clock()
		local frameMs = (now - last) * 1000
		last = now
		sinceCheck += dt
		local rep, n, expected = replicated(mapId)
		local sample: Sample = { dt = dt, replicated = rep, frameMs = frameMs }
		if sinceCheck >= Ready.CHECK_EVERY then
			sinceCheck = 0
			sample.allHit = allHit(map)
		end
		if Ready.step(st, sample) then
			return alive()
		end
		if onProgress then
			if not st.replicated then
				onProgress(if expected > 0 then 0.6 * n / expected else 0, "Raising the hills…")
			elseif not st.settled then
				onProgress(0.6 + 0.3 * st.hits / Ready.HITS_NEEDED, "Letting the ground settle…")
			else
				onProgress(0.95, "Forming up…")
			end
		end
	end
	return false
end

return Ready
