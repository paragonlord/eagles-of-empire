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
		Loading.setProgress(0.7 + p * 0.3, "Planting woods and villages…")
	end)
	if not ok or token ~= buildToken then
		return false
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
	help = openHelp,
	settings = openSettings,
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
end

local gotServerState = false

-- Diagnostic beacon (bottom-left, F10 toggles; shown by default only in Studio).
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
		l.Size = UDim2.new(0, 900, 0, 18)
		l.Position = UDim2.new(0, 8, 1, -22)
		l.AnchorPoint = Vector2.new(0, 0)
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
	BattleState.applyMatchState(msg)
	Net.setMatch(BattleState.matchId, BattleState.validateContext)
	if pauseToggle then
		-- keep figures, selection and HUD; just reflect the new state
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
		if campaignWanted and BattleState.isCommander then
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
				Deployment.setWaiting("Forming up…")
			end,
			settings = openSettings,
		})
		Input.setMode(if BattleState.isCommander then "deploy" else "off")
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
		Input.setMode(if BattleState.isCommander then "battle" else "off")
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
				Net.control("quit")
			end,
			campaign = if inCampaign then function()
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
	table.insert(conns, Net.onMatchState:Connect(function(msg: any)
		gotServerState = true
		task.spawn(onMatchState, msg)
	end))
	table.insert(conns, Net.onSnapshot:Connect(onSnapshot))
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
	table.insert(conns, BattleState.updated:Connect(function()
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
