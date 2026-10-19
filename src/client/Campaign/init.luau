--!strict
-- Grand campaign client: the server's grandView is the only state. Owns the board, the
-- camera, the panels and the board input while open; `close()` removes all of it (Main calls
-- it on every lifecycle change) and `request()` asks for the view again (menu, back from battle).

local UserInputService = game:GetService("UserInputService") :: UserInputService
local Net = require(script.Parent.Net)
local Data = require(script.Data)
local Board = require(script.Board)
local CampaignCamera = require(script.CampaignCamera)
local UI = require(script.CampaignUI)
local Logic = require(script.Logic)

local Grand = {}

export type Hooks = {
	shown: () -> (), -- the board took the screen: hide the menu / results
	menu: () -> (), -- the player left for the main menu
}

local hooks: Hooks? = nil
local isOpen = false
local wanted = false -- the player is in the grand campaign (survives battles)
local requested = false -- a view was asked for and may take the screen
local view: any = nil
local sessionOnly = false
local ours: { [string]: boolean } = {}
local conns: { RBXScriptConnection } = {}
local selArmy: any = nil
local selSpy: any = nil
local selProv: string? = nil
local hoverProv: string? = nil
local lastTurn: number? = nil

-- ------------------------------------------------------------------ helpers

local function send(kind: string, data: { [string]: any }?)
	local d: { [string]: any } = table.clone(data or {})
	d.kind = kind
	local rid = Net.campaign("grand", d)
	if rid then
		ours[rid] = true
	end
end

local function player(): string
	return if view then tostring(view.playerNation) else ""
end

local function armyById(id: any): any
	return Logic.army(view, id)
end

local function spyById(id: any): any
	for _, ag in (view and view.agents) or {} do
		if ag.id == id then
			return ag
		end
	end
	return nil
end

local function canAct(): (boolean, string)
	return Logic.canAct(view)
end

local function route(a: any, goal: string): { Board.Step }?
	return Logic.route(view, a, goal)
end

-- ------------------------------------------------------------------ render

local function render()
	if not isOpen then
		return
	end
	local a = armyById(selArmy)
	if not a then
		selArmy = nil
	end
	local own = a ~= nil and a.nation == player()
	local others = {}
	if own then
		for _, o in view.armies or {} do
			if o.id ~= a.id and o.nation == a.nation and o.provinceId == a.provinceId then
				table.insert(others, o)
			end
		end
	end
	local ok, why = canAct()
	local spy = spyById(selSpy)
	if not spy then
		selSpy = nil
	end
	UI.render({ view = view, player = player(), sessionOnly = sessionOnly, army = a, spy = spy, province = selProv, others = others, canAct = ok, actReason = why })
	Board.setSelection(selArmy or selSpy, selProv, if own and ok then Logic.reachable(view, a) else nil)
	local path = nil
	if own and ok then
		path = if hoverProv then route(a, hoverProv) else nil
		if not path and type(a.path) == "table" and #a.path > 0 then
			path = {}
			for i, id in a.path do
				table.insert(path, { id = id, turn = i, stop = false })
			end
		end
	end
	Board.setPath(if a then a.provinceId else nil, path)
end

local function select(armyId: any, provId: string?)
	selArmy, selSpy, selProv, hoverProv = armyId, nil, provId, nil
	render()
end

-- ------------------------------------------------------------------ input

local function onInput(input: InputObject, gp: boolean)
	if gp or UserInputService:GetFocusedTextBox() then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.E then
			if canAct() then
				send("endTurn")
			end
		elseif input.KeyCode == Enum.KeyCode.Escape then
			if not UI.escape() then
				selArmy, selSpy, selProv = nil, nil, nil
			end
			render()
		end
	elseif t == Enum.UserInputType.MouseButton1 then
		local kind, id = Board.pick()
		if kind == "army" then
			local a = armyById(id)
			select(id, if a then a.provinceId else nil)
		elseif kind == "spy" then
			local ag = spyById(id)
			select(nil, if ag then ag.provinceId else nil)
			selSpy = id
			render()
		elseif kind == "province" then
			select(nil, id)
		else
			select(nil, nil)
		end
	elseif t == Enum.UserInputType.MouseButton2 then
		local a = armyById(selArmy)
		local kind, id = Board.pick()
		local spy = spyById(selSpy)
		if spy and canAct() then
			-- a spy goes where it is sent, over any border, within its marches
			local target = if kind == "province" then id elseif kind == "army" then (armyById(id) or {}).provinceId else nil
			if target and target ~= spy.provinceId then
				send("moveSpy", { agentId = spy.id, provinceId = target })
			end
			return
		end
		if kind == "army" then
			local target = armyById(id)
			id = if target then target.provinceId else nil
		end
		if a and a.nation == player() and canAct() and id then
			local r = route(a, id)
			if r then
				local ids = {}
				for _, s in r do
					table.insert(ids, s.id)
				end
				send("move", { armyId = a.id, path = ids })
			else
				UI.toast("No road leads there")
			end
		end
	end
end

local function onMove(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	local a = armyById(selArmy)
	if not a or a.nation ~= player() then
		return
	end
	local kind, id = Board.pick()
	if kind == "army" then
		local t = armyById(id)
		id = if t then t.provinceId else nil
	end
	local p: string? = if kind then id else nil
	if p ~= hoverProv then
		hoverProv = p
		local ok = canAct()
		Board.setPath(a.provinceId, if ok and p then route(a, p) else nil)
	end
end

-- ------------------------------------------------------------------ lifecycle

local function open()
	if isOpen then
		return
	end
	isOpen = true
	Board.build()
	UI.open({
		send = send,
		render = render,
		menu = function()
			wanted = false
			Grand.close()
			if hooks then
				hooks.menu()
			end
		end,
	})
	local x0, z0, x1, z1, y = Board.bounds()
	local nation = Data.Nations[player()]
	local cap = nation and Data.byId[nation.capital]
	local focus = if cap then Board.toWorld(cap.centre.x, cap.centre.z) else Vector3.new((x0 + x1) / 2, y, (z0 + z1) / 2)
	CampaignCamera.start(x0, z0, x1, z1, y, focus.X, focus.Z)
	table.insert(conns, UserInputService.InputBegan:Connect(onInput))
	table.insert(conns, UserInputService.InputChanged:Connect(onMove))
	table.insert(conns, (game:GetService("RunService") :: RunService).RenderStepped:Connect(function()
		Board.updateLabels(CampaignCamera.height())
	end))
	if hooks then
		hooks.shown()
	end
end

function Grand.init(h: Hooks)
	hooks = h
end

function Grand.wanted(): boolean
	return wanted
end

-- Ask for the current view; it takes the screen when it arrives.
function Grand.request()
	wanted = true
	requested = true
	send("view")
end

-- Results "Main Menu": the player has left the campaign.
function Grand.forget()
	wanted = false
	requested = false
end

-- Routes a Campaign-remote message; true when it was the grand campaign's.
function Grand.handle(msg: any, canShow: boolean): boolean
	if msg.kind == "grandView" then
		if type(msg.view) ~= "table" then
			return true
		end
		local prevTurn = lastTurn
		view = msg.view
		sessionOnly = msg.sessionOnly == true
		lastTurn = tonumber(view.turn)
		if not isOpen and requested and canShow then
			requested = false
			open()
		end
		if isOpen then
			if prevTurn and lastTurn and lastTurn > prevTurn then
				UI.showSummary("Dispatches · " .. tostring(view.date or ""), Logic.turnLines(view, prevTurn))
			end
			Board.setView(view)
			render()
		end
		return true
	end
	if msg.kind == "error" and ours[msg.requestId] then
		ours[msg.requestId] = nil
		local reason = tostring(msg.reason)
		if isOpen then
			UI.toast(reason)
		elseif requested and canShow then
			-- no campaign to continue: open on the 1805 map and offer the nations
			requested = false
			view = nil
			open()
			Board.setView(nil)
			UI.showPicker(reason)
			render()
		end
		return true
	end
	return false
end

function Grand.close()
	if not isOpen then
		return
	end
	isOpen = false
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	CampaignCamera.stop()
	UI.destroy()
	Board.destroy()
	selArmy, selSpy, selProv, hoverProv = nil, nil, nil, nil
end

return Grand
