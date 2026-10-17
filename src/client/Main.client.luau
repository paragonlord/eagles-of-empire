--!strict
-- Client bootstrap: waits for shared modules and remotes, builds the world per map, wires the
-- modules together and drives the match lifecycle from MatchState messages.

local RunService = game:GetService("RunService") :: RunService
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local MapGen = require(Shared.MapGen)

local Signal = require(script.Parent.Signal)
local Settings = require(script.Parent.Settings)
local Net = require(script.Parent.Net)
local BattleState = require(script.Parent.BattleState)
local Audio = require(script.Parent.Audio)
local Camera = require(script.Parent.Camera)
local Selection = require(script.Parent.Selection)
local Input = require(script.Parent.Input)
local Figures = require(script.Parent.Figures)
local Effects = require(script.Parent.Effects)
local Terrain = require(script.Parent.World.Terrain)
local Props = require(script.Parent.World.Props)
local WorldLighting = require(script.Parent.World.Lighting)
local Kit = require(script.Parent.UI.Kit)
local Menu = require(script.Parent.UI.Menu)
local HUD = require(script.Parent.UI.HUD)
local Deployment = require(script.Parent.UI.Deployment)
local Results = require(script.Parent.UI.Results)
local SettingsPanel = require(script.Parent.UI.SettingsPanel)
local Help = require(script.Parent.UI.Help)
local Loading = require(script.Parent.UI.Loading)
local DevPanel = require(script.Parent.UI.DevPanel)
local CampaignScreen = require(script.Parent.UI.CampaignScreen)
local BattleSelect = require(script.Parent.UI.BattleSelect)
local Grand = require(script.Parent.Campaign)
local Tutorial = require(script.Parent.Tutorial)
local Cinematic = require(script.Parent.Cinematic)

local DEFAULT_MAP = "jena"

local mapCache: { [string]: any } = {}
local builtMapId: string? = nil
local buildToken = 0
local needCameraReset = false
local pendingClock = 0
local lastMatchId = ""
local lastMenuArgs = { isCommander = false, campaignAvailable = false }
local campaignWanted = false -- a campaign view should take the screen when it arrives
local conns: { Signal.Connection } = {}

-- ------------------------------------------------------------------ world

-- Generates (cached) and builds terrain + props for a map. Yields. False if superseded.
local function ensureWorld(mapId: string): boolean
	if builtMapId == mapId then
		return true
	end
	buildToken += 1
	local token = buildToken
	Loading.show("Surveying the ground…")
	local map = mapCache[mapId]
	if not map then
		map = MapGen.generate(mapId)
		mapCache[mapId] = map
	end
	BattleState.map = map
	Camera.setMap(map)
	builtMapId = nil
	Terrain.clear()
	Props.clear()
	local ok = Terrain.build(map, function(p: number)
		Loading.setProgress(p * 0.7, "Raising the hills…")
	end)
	if not ok or token ~= buildToken then
		return false
	end
	ok = Props.build(map, Settings.get().quality, function(p: number)
		Loading.setProgress(0.6 + p * 0.25, "Planting woods and villages…")
	end)
	if not ok or token ~= buildToken then
		return false
	end
	-- Every voxel is written, but Roblox meshes a large map over several seconds (Studio showed
	-- holes for ~15 s on Austerlitz). Hold the loading screen, looking over the field so the
	-- centre meshes first, for a time scaled by map area.
	Camera.reset(map.width / 2, map.depth * 0.4)
	local settle = math.clamp(3 + 5 * (map.width * map.depth) / (1600 * 1200), 4, 14)
	local t0 = os.clock()
	while os.clock() - t0 < settle do
		if token ~= buildToken then
			return false
		end
		Loading.setProgress(0.85 + 0.15 * (os.clock() - t0) / settle, "Letting the ground settle…")
		task.wait(0.1)
	end
	builtMapId = mapId
	Loading.hide()
	return true
end

-- ------------------------------------------------------------------ panels

local function closePanels()
	Help.hide()
	SettingsPanel.hide()
	BattleSelect.hide()
end

local function openHelp()
	SettingsPanel.hide()
	Help.show()
end

local function openSettings()
	Help.hide()
	SettingsPanel.show()
end

local menuCallbacks: any
menuCallbacks = {
	play = function()
		Menu.hide()
		BattleSelect.show({
			fight = function(id: string)
				BattleSelect.hide()
				Net.control("start", id)
			end,
			difficulty = function(v: string)
				Net.control("difficulty", v)
			end,
			mode = function(v: string)
				Net.control("mode", v)
			end,
			back = function()
				BattleSelect.hide()
				Menu.show(menuCallbacks, lastMenuArgs.isCommander, lastMenuArgs.campaignAvailable)
			end,
		}, BattleState.isCommander)
	end,
	campaign = function()
		campaignWanted = true
		Net.campaign("open")
	end,
	grand = Grand.request,
	help = openHelp,
	settings = openSettings,
	tutorial = function()
		Menu.hide()
		Tutorial.begin()
		Net.control("start", "tutorial")
	end,
}

local campaignCallbacks = {
	send = function(action: string, data: { [string]: any }?)
		Net.campaign(action, data)
	end,
	menu = function()
		campaignWanted = false
		CampaignScreen.hide()
		if BattleState.state == "menu" then
			Menu.show(menuCallbacks, lastMenuArgs.isCommander, lastMenuArgs.campaignAvailable)
		else
			Net.control("quit")
		end
	end,
}

local function onCampaign(msg: any)
	if type(msg) ~= "table" then
		return
	end
	if Grand.handle(msg, BattleState.state == "menu" or BattleState.state == "results") then
		return
	end
	if msg.kind == "error" then
		if CampaignScreen.isOpen() then
			CampaignScreen.showError(tostring(msg.reason))
		elseif campaignWanted then
			HUD.toast(tostring(msg.reason))
			Menu.show(menuCallbacks, lastMenuArgs.isCommander, lastMenuArgs.campaignAvailable)
			campaignWanted = false
		end
		return
	end
	if msg.kind ~= "view" or type(msg.view) ~= "table" then
		return
	end
	if not campaignWanted then
		return -- e.g. a view echoed while a campaign battle is being fought
	end
	-- the campaign takes the screen over the menu or the results panel
	Menu.hide()
	Results.destroy()
	if CampaignScreen.isOpen() then
		CampaignScreen.setView(msg.view, msg.sessionOnly == true)
	else
		CampaignScreen.show(msg.view, msg.sessionOnly == true, campaignCallbacks)
	end
end

local hudCallbacks = {
	settings = openSettings,
	help = openHelp,
	menu = function()
		Net.control("quit")
	end,
}

-- ------------------------------------------------------------------ lifecycle

-- Removes everything a previous state created. Safe to call repeatedly.
local function teardown()
	Input.setMode("off")
	Figures.clear()
	Effects.clear()
	HUD.destroy()
	Deployment.destroy()
	Results.destroy()
	Menu.hide()
	Props.setDeployZone(nil, nil)
	Selection.reset()
	Figures.setPreview(nil)
	closePanels()
	CampaignScreen.hide()
	Grand.close()
	Cinematic.clear()
end

local gotServerState = false

-- Diagnostic beacon (top-right under the top bar, F10 toggles; shown by default only in Studio).
local beacon: TextLabel? = nil
local beaconGui: ScreenGui? = nil
local function diag(text: string)
	print("[EoE client] " .. text)
	if not beacon then
		local sg = Instance.new("ScreenGui") :: ScreenGui
		sg.Name = "EoEDiag"
		sg.DisplayOrder = 100
		sg.ResetOnSpawn = false
		sg.Enabled = RunService:IsStudio()
		sg.Parent = (game:GetService("Players") :: Players).LocalPlayer:WaitForChild("PlayerGui")
		beaconGui = sg
		local l = Instance.new("TextLabel") :: TextLabel
		l.AnchorPoint = Vector2.new(1, 0)
		l.Position = UDim2.new(1, -8, 0, 90)
		l.Size = UDim2.fromOffset(0, 18)
		l.AutomaticSize = Enum.AutomaticSize.X
		l.BackgroundTransparency = 0.4
		l.BackgroundColor3 = Color3.new(0, 0, 0)
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Font = Enum.Font.Code
		l.TextSize = 12
		l.Parent = sg
		beacon = l
	end
	if beacon then
		beacon.Text = "EoE build 5 | " .. text
	end
end

local function onMatchState(msg: any)
	if type(msg) ~= "table" then
		return
	end
	diag(string.format("state=%s match=%s commander=%s", tostring(msg.state), tostring(msg.matchId), tostring(msg.isCommander)))
	local prevState = BattleState.state
	local sameMatch = msg.matchId == lastMatchId and msg.matchId ~= ""
	local pauseToggle = sameMatch and ((prevState == "running" and msg.state == "paused") or (prevState == "paused" and msg.state == "running"))
	local wasCoop = BattleState.coop() or BattleState.pvp()
	local prevFaction = BattleState.viewerFaction
	BattleState.applyMatchState(msg)
	-- co-op: votes, ready ticks, joins and wing changes resend the same state; refresh in place
	local s = BattleState.state
	-- a PvP side switch changes the view: rebuild instead (new zone, camera, full snapshot)
	local coopRefresh = sameMatch and s == prevState and (wasCoop or BattleState.coop() or BattleState.pvp()) and BattleState.viewerFaction == prevFaction and (s == "deployment" or s == "running" or s == "paused")
	WorldLighting.setWeather(if type(msg.scenario) == "table" then msg.scenario.weather else nil)
	Net.setMatch(BattleState.matchId, BattleState.validateContext)
	Tutorial.onMatchState(BattleState.state, if msg.scenario then msg.scenario.id else nil)
	if pauseToggle or coopRefresh then
		-- keep figures, selection and HUD; just reflect the new state
		if coopRefresh then
			Input.setMode(if not BattleState.canOrder() then "off" elseif s == "deployment" then "deploy" else "battle")
			Deployment.refresh()
		end
		BattleState.updated:Fire(nil)
		return
	end
	if not sameMatch then
		BattleState.reset()
		lastMatchId = msg.matchId or ""
		needCameraReset = true
	end
	teardown()
	local state = msg.state
	local scenario = msg.scenario
	local mapId = if scenario and scenario.map then scenario.map else DEFAULT_MAP

	if state == "menu" then
		lastMenuArgs = { isCommander = BattleState.isCommander, campaignAvailable = msg.campaignAvailable == true }
		if Grand.wanted() and BattleState.isCommander then
			Grand.request() -- back from a grand-campaign battle
		elseif campaignWanted and BattleState.isCommander then
			Net.campaign("return") -- back from a campaign battle: show the map again
		else
			campaignWanted = false
			Menu.show(menuCallbacks, lastMenuArgs.isCommander, lastMenuArgs.campaignAvailable)
		end
		Camera.setEnabled(true)
		local built = ensureWorld(DEFAULT_MAP)
		diag(string.format("menu shown (commander=%s), world built=%s", tostring(BattleState.isCommander), tostring(built)))
		if built then
			local m = BattleState.map
			Camera.reset(m.width / 2, m.depth * 0.45)
		end
	elseif state == "loading" then
		Loading.show("The army is forming…")
		ensureWorld(mapId)
		Loading.show("Waiting for the server…")
	elseif state == "deployment" then
		campaignWanted = msg.campaignBattle ~= nil
		if not ensureWorld(mapId) then
			return
		end
		Figures.init()
		Effects.init()
		local zone = BattleState.map.deployZones[BattleState.viewerFaction]
		Props.setDeployZone(zone, BattleState.viewerFaction)
		Deployment.show({
			ready = function()
				Net.control("ready")
				if BattleState.coop() and BattleState.role == "commander" and not BattleState.pvp() then
					Deployment.setWaiting("Start now", true) -- a second ready forces the start
				else
					Deployment.setWaiting("Forming up…")
				end
			end,
			assign = function(userId: number)
				local ids = Selection.ids()
				if #ids > 0 then
					Net.control("assign", { ids = ids, userId = userId })
				end
			end,
			mode = function(v: string)
				Net.control("mode", v)
			end,
			side = function(faction: string)
				Net.control("side", faction)
			end,
			balance = function()
				Net.control("balance")
			end,
			settings = openSettings,
		})
		Input.setMode(if BattleState.canOrder() then "deploy" else "off")
		Camera.setEnabled(true)
		if zone then
			Camera.reset((zone.x0 + zone.x1) / 2, (zone.z0 + zone.z1) / 2)
			Camera.playIntro() -- sweep over the field while the briefing is read
			needCameraReset = false
		end
	elseif state == "running" or state == "paused" then
		if not ensureWorld(mapId) then
			return
		end
		Figures.init()
		Effects.init()
		HUD.show(hudCallbacks)
		Input.setMode(if BattleState.canOrder() then "battle" else "off")
		Camera.setEnabled(true)
		if msg.reason then
			HUD.message(tostring(msg.reason))
		end
	elseif state == "results" then
		if not ensureWorld(mapId) then
			return
		end
		Figures.init() -- the field stays visible, frozen, behind the panel
		local inCampaign = BattleState.campaignBattle ~= nil
		Results.show(msg.results or {}, {
			restart = function()
				Net.control("restart")
			end,
			menu = function()
				campaignWanted = false
				Grand.forget()
				Net.control("quit")
			end,
			campaign = if inCampaign then function()
				if Grand.wanted() then
					Grand.request()
					return
				end
				campaignWanted = true
				Net.campaign("return")
			end else nil,
		})
		Camera.setEnabled(true)
	end
	-- a snapshot may already be in BattleState: render it now
	if next(BattleState.formations) ~= nil then
		Figures.onSnapshot()
	end
end

local function onSnapshot(snap: any)
	if type(snap) ~= "table" then
		return
	end
	BattleState.applySnapshot(snap)
end

-- ------------------------------------------------------------------ wiring

local function wire()
	Grand.init({
		shown = function()
			Menu.hide()
			Results.destroy()
		end,
		menu = function()
			if BattleState.state == "menu" then
				Menu.show(menuCallbacks, lastMenuArgs.isCommander, lastMenuArgs.campaignAvailable)
				Camera.setEnabled(true)
			else
				Net.control("quit")
			end
		end,
	})
	table.insert(conns, Net.onMatchState:Connect(function(msg: any)
		gotServerState = true
		task.spawn(onMatchState, msg)
	end))
	table.insert(conns, Net.onSnapshot:Connect(onSnapshot))
	table.insert(conns, Net.onPing:Connect(function(msg: any)
		if type(msg) ~= "table" or type(msg.x) ~= "number" or type(msg.z) ~= "number" then
			return
		end
		local p = BattleState.player(msg.userId)
		local slot = if p and type(p.slot) == "number" then p.slot else 0
		local now = os.clock()
		local keep = {}
		for _, pg in BattleState.pings do
			if now - pg.t0 < 6 then
				table.insert(keep, pg)
			end
		end
		local kind = if msg.kind == "attack" or msg.kind == "defend" then msg.kind else "look"
		table.insert(keep, { x = msg.x, z = msg.z, slot = slot, kind = kind, t0 = now })
		BattleState.pings = keep
		Effects.ping(msg.x, msg.z, Kit.slotColour(slot))
		Audio.play("ping")
		local word = if kind == "attack" then "attack here!" elseif kind == "defend" then "hold here." else "look here."
		HUD.message(string.format("%s: %s", tostring(msg.name or (p and p.name) or "An officer"), word), Kit.slotColour(slot))
	end))
	table.insert(conns, Net.onCampaign:Connect(onCampaign))
	table.insert(conns, Net.onResult:Connect(function(res: any)
		if type(res) == "table" then
			BattleState.applyResult(res)
		end
	end))
	table.insert(conns, Net.onDebug:Connect(function(msg: any)
		if type(msg) == "table" and type(msg.aiGoals) == "table" then
			DevPanel.setGoals(msg.aiGoals)
		end
	end))
	table.insert(conns, BattleState.updated:Connect(function(snap: any)
		if type(snap) == "table" then
			WorldLighting.setWeather(snap.weather)
		end
		Selection.prune()
		Figures.onSnapshot()
		Props.updateObjectives(BattleState.objectives)
		if needCameraReset and next(BattleState.formations) ~= nil then
			needCameraReset = false
			local c = BattleState.armyCentre()
			Camera.reset(c.x, c.z)
		end
	end))
	table.insert(conns, BattleState.event:Connect(function(ev: any)
		Effects.onEvent(ev)
		HUD.onEvent(ev)
		Cinematic.onEvent(ev)
		if ev.kind == "volley" or ev.kind == "cannon" or ev.kind == "melee" or ev.kind == "charge" or ev.kind == "rout" or ev.kind == "rally" or ev.kind == "capture" then
			Audio.play(ev.kind)
		end
	end))
	table.insert(conns, BattleState.pendingChanged:Connect(Figures.onPendingChanged))
	table.insert(conns, Selection.hoverChanged:Connect(Figures.markDirty))
	table.insert(conns, Selection.changed:Connect(Figures.markDirty))
	table.insert(conns, Input.action:Connect(function(name: string)
		if name == "escape" then
			closePanels()
		elseif name == "dev" then
			DevPanel.toggle()
		elseif name == "help" then
			if Help.isOpen() then
				Help.hide()
			else
				openHelp()
			end
		end
	end))
	table.insert(conns, Settings.changed:Connect(function(key: string)
		if key == "quality" then
			Effects.applySettings()
			WorldLighting.apply(Settings.get().quality)
			local id = builtMapId
			if id then
				task.spawn(function()
					Props.build(mapCache[id], Settings.get().quality, nil)
				end)
			end
		elseif key == "reducedEffects" then
			Effects.applySettings()
		end
	end))
end

-- ------------------------------------------------------------------ boot

-- Morning light, haze and post effects (World/Lighting); re-applied when quality changes.
WorldLighting.apply(Settings.get().quality)

BattleState.userId = ((game:GetService("Players") :: Players).LocalPlayer :: Player).UserId
Audio.init()
Camera.init()
Input.init()
diag("starting; waiting for remotes")
Net.init()
diag("remotes hooked; requesting state")
-- The server announced the match state when we joined, possibly before we were listening:
-- ask for it again now that the remotes are hooked.
Net.control("spectate")
wire()

local UserInputService = game:GetService("UserInputService") :: UserInputService
UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
	if not gp and input.KeyCode == Enum.KeyCode.F10 and beaconGui then
		beaconGui.Enabled = not beaconGui.Enabled
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	Figures.update(dt)
	Effects.update(dt)
	HUD.update(dt)
	Props.updateLabels(Camera.height())
	pendingClock += dt
	if pendingClock > 1 then
		pendingClock = 0
		BattleState.expirePending(6)
	end
end)

-- Until the server speaks, show the menu over the default battlefield.
task.spawn(function()
	task.wait(1)
	if not gotServerState then
		Net.control("spectate")
	end
	task.wait(1.5)
	if not gotServerState then
		diag("no reply from server after 2.5 s; showing offline menu")
		onMatchState({ matchId = "", state = "menu", viewerFaction = "", isCommander = false, difficulty = "normal", speed = 1 })
	end
end)
