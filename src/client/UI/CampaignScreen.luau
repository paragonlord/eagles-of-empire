--!strict
-- Campaign screen: stylised region map (nodes, roads, owner fills, army stacks), side panel
-- (resources, selected army, recruitment, objectives, log), End Turn, pending-battle dialog.
-- The server view is the only state; every action goes back through `callbacks.send`.

local Kit = require(script.Parent.Kit)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Assets = require(Shared.Assets)
local Factions = require(script.Parent.Parent.Factions)

local CampaignScreen = {}

export type Callbacks = {
	send: (action: string, data: { [string]: any }?) -> (),
	menu: () -> (),
}

local PLAYER = "france"
local OLIVE = Color3.fromRGB(128, 118, 70)
local OLIVE_DARK = Color3.fromRGB(96, 88, 52)
local ROAD = Color3.fromRGB(214, 200, 160)
local REASONS: { [string]: string } = {
	notYourArmy = "That army is not yours",
	alreadyMoved = "That army has already marched this turn",
	notAdjacent = "No road leads there",
	unknownUnit = "Unknown unit type",
	notYourRegion = "You do not hold that region",
	queueFull = "The recruitment queue is full",
	insufficientFunds = "Not enough treasury",
	wrongPhase = "Not during this phase",
	nothingToReplenish = "Nothing to replenish",
	badArgs = "Malformed order",
	unreadable = "Your saved campaign could not be read. It has been kept; starting a new campaign replaces it",
	unknownCommand = "Unknown order",
}

local gui: ScreenGui? = nil
local cb: Callbacks? = nil
local view: any = nil
local sessionOnly = false
local selectedArmy: number? = nil
local selectedRegion: string? = nil
local confirmNew = false

local mapFrame: Frame? = nil
local roadLayer: Frame? = nil
local nodeLayer: Frame? = nil
local side: ScrollingFrame? = nil
local toast: TextLabel? = nil
local dialog: Frame? = nil
local sizeConn: RBXScriptConnection? = nil

-- ------------------------------------------------------------------ helpers

local function regionById(id: string?): any
	if not view or not id then
		return nil
	end
	for _, r in view.regions do
		if r.id == id then
			return r
		end
	end
	return nil
end

local function armyById(id: number?): any
	if not view or not id then
		return nil
	end
	for _, a in view.armies do
		if a.id == id then
			return a
		end
	end
	return nil
end

local function armyStrength(a: any): number
	local s = 0
	for _, u in a.units do
		s += u.strength
	end
	return s
end

local function shortName(name: string): string
	local tail = string.match(name, "·%s*(.+)$")
	return tail or name
end

local function factionName(f: string?): string
	return Factions.name(f)
end

local function plural(n: number): string
	return if n == 1 then "" else "s"
end

local function isAdjacent(a: any, regionId: string): boolean
	return table.find(a.adjacent, regionId) ~= nil
end

local function nodePos(r: any): UDim2
	return UDim2.fromScale(0.08 + 0.84 * r.pos.x / 1000, 0.08 + 0.84 * r.pos.z / 1000)
end

local function playerPhase(): boolean
	return view ~= nil and view.phase == "player" and view.victory == nil and view.pendingBattle == nil
end

local function queueCount(): number
	local n = 0
	for _, q in view.recruitment do
		if q.faction == PLAYER then
			n += 1
		end
	end
	return n
end

local function send(action: string, data: { [string]: any }?)
	if cb then
		cb.send(action, data)
	end
end

-- ------------------------------------------------------------------ map

local function drawRoads()
	local layer = roadLayer
	local mf = mapFrame
	if not layer or not mf or not view then
		return
	end
	layer:ClearAllChildren()
	local size = mf.AbsoluteSize
	local done: { [string]: boolean } = {}
	for _, r in view.regions do
		for _, otherId in r.adjacent do
			local key = if r.id < otherId then r.id .. "|" .. otherId else otherId .. "|" .. r.id
			local o = regionById(otherId)
			if o and not done[key] then
				done[key] = true
				local ax, ay = (0.08 + 0.84 * r.pos.x / 1000) * size.X, (0.08 + 0.84 * r.pos.z / 1000) * size.Y
				local bx, by = (0.08 + 0.84 * o.pos.x / 1000) * size.X, (0.08 + 0.84 * o.pos.z / 1000) * size.Y
				local line = Instance.new("Frame") :: Frame
				line.AnchorPoint = Vector2.new(0.5, 0.5)
				line.BackgroundColor3 = ROAD
				line.BackgroundTransparency = 0.25
				line.BorderSizePixel = 0
				line.Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2)
				line.Size = UDim2.fromOffset(math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2), 3)
				line.Rotation = math.deg(math.atan2(by - ay, bx - ax))
				line.Parent = layer
			end
		end
	end
end

local function onRegionClick(r: any)
	local a = armyById(selectedArmy)
	if a and a.faction == PLAYER and playerPhase() and a.regionId ~= r.id and isAdjacent(regionById(a.regionId), r.id) and a.movesLeft > 0 then
		send("command", { kind = "move", armyId = a.id, regionId = r.id })
		return
	end
	selectedRegion = r.id
	selectedArmy = nil
	for _, id in r.armies do
		local army = armyById(id)
		if army and army.faction == PLAYER then
			selectedArmy = id
			break
		end
	end
	CampaignScreen.render()
end

local function armyStack(parent: Instance, a: any, order: number)
	local own = a.faction == PLAYER
	local b = Instance.new("TextButton") :: TextButton
	b.Size = UDim2.fromOffset(92, 18)
	b.BackgroundColor3 = if own then Kit.FRANCE else Color3.fromRGB(36, 37, 40)
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.Gotham
	b.TextSize = 10
	b.TextColor3 = Color3.fromRGB(240, 236, 224)
	b.Text = string.format("%s  %d", shortName(a.name), armyStrength(a))
	b.LayoutOrder = order
	b.ZIndex = 6
	b.Active = true
	b.Parent = parent
	local stroke = Instance.new("UIStroke") :: UIStroke
	stroke.Color = if selectedArmy == a.id then Kit.SELECT else Color3.fromRGB(20, 20, 20)
	stroke.Thickness = if selectedArmy == a.id then 2 else 1
	stroke.Parent = b
	local top = Instance.new("Frame") :: Frame
	top.Size = UDim2.new(1, 0, 0, 2)
	top.BackgroundColor3 = b.BackgroundColor3:Lerp(Color3.new(1, 1, 1), 0.3)
	top.BorderSizePixel = 0
	top.ZIndex = 7
	top.Parent = b
	if a.movesLeft <= 0 and own then
		b.TextTransparency = 0.35
	end
	b.Activated:Connect(function()
		selectedArmy = a.id
		selectedRegion = a.regionId
		CampaignScreen.render()
	end)
end

local function drawNodes()
	local layer = nodeLayer
	if not layer or not view then
		return
	end
	layer:ClearAllChildren()
	local sel = armyById(selectedArmy)
	local canMove = sel ~= nil and sel.faction == PLAYER and sel.movesLeft > 0 and playerPhase()
	local from = if sel then regionById(sel.regionId) else nil
	for _, r in view.regions do
		local legal = canMove and from ~= nil and r.id ~= from.id and isAdjacent(from, r.id)
		local d = if r.isCity then 30 else 22
		local node = Instance.new("TextButton") :: TextButton
		node.Size = UDim2.fromOffset(d, d)
		node.AnchorPoint = Vector2.new(0.5, 0.5)
		node.Position = nodePos(r)
		node.BackgroundColor3 = Kit.factionColour(r.owner)
		node.Text = ""
		node.AutoButtonColor = true
		node.BorderSizePixel = 0
		node.ZIndex = 5
		node.Active = true
		node.Parent = layer
		local c = Instance.new("UICorner") :: UICorner
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = node
		local s = Instance.new("UIStroke") :: UIStroke
		s.Thickness = if legal or selectedRegion == r.id then 3 else 1.5
		s.Color = if legal then Kit.SELECT elseif selectedRegion == r.id then Kit.CREAM else Color3.fromRGB(30, 28, 24)
		s.Parent = node
		if r.isCity then
			local inner = Instance.new("Frame") :: Frame
			inner.Size = UDim2.fromScale(0.45, 0.45)
			inner.AnchorPoint = Vector2.new(0.5, 0.5)
			inner.Position = UDim2.fromScale(0.5, 0.5)
			inner.BackgroundColor3 = Kit.CREAM
			inner.BorderSizePixel = 0
			inner.ZIndex = 6
			inner.Parent = node
			local ic = Instance.new("UICorner") :: UICorner
			ic.CornerRadius = UDim.new(1, 0)
			ic.Parent = inner
		end
		node.Activated:Connect(function()
			onRegionClick(r)
		end)
		local objective = false
		for _, o in view.objectives.regions do
			if o.id == r.id then
				objective = true
			end
		end
		local label = Kit.label(layer, r.name .. (if objective then " ✦" else ""), { size = UDim2.fromOffset(140, 20), position = nodePos(r) + UDim2.fromOffset(0, d / 2 + 2), anchor = Vector2.new(0.5, 0), font = Enum.Font.Garamond, textSize = if r.isCity then 20 else 17, colour = Kit.CREAM, align = Enum.TextXAlignment.Center })
		label.TextStrokeTransparency = 0.5
		label.TextStrokeColor3 = Color3.fromRGB(30, 28, 20)
		label.ZIndex = 5
		if #r.armies > 0 then
			local stack = Instance.new("Frame") :: Frame
			stack.Size = UDim2.fromOffset(92, 20 * #r.armies)
			stack.Position = nodePos(r) + UDim2.fromOffset(d / 2 + 6, -10)
			stack.BackgroundTransparency = 1
			stack.ZIndex = 6
			stack.Parent = layer
			Kit.list(stack, 2)
			for i, id in r.armies do
				local a = armyById(id)
				if a then
					armyStack(stack, a, i)
				end
			end
		end
		-- recruitment in progress at this region
		local queued = 0
		for _, q in view.recruitment do
			if q.regionId == r.id then
				queued += 1
			end
		end
		if queued > 0 then
			local q = Kit.label(layer, string.format("+%d raising", queued), { size = UDim2.fromOffset(90, 14), position = nodePos(r) + UDim2.fromOffset(-d / 2 - 6, -7), anchor = Vector2.new(1, 0), textSize = 10, colour = Kit.CREAM, align = Enum.TextXAlignment.Right })
			q.ZIndex = 5
		end
	end
end

-- ------------------------------------------------------------------ side panel

local function section(parent: Instance, title: string, order: number): Frame
	local f = Instance.new("Frame") :: Frame
	f.Size = UDim2.new(1, 0, 0, 20)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundTransparency = 1
	f.LayoutOrder = order
	f.Parent = parent
	Kit.list(f, 4)
	local t = Kit.title(f, title, { size = UDim2.new(1, 0, 0, 24), textSize = 20 })
	t.LayoutOrder = 0
	return f
end

local function row(parent: Instance, text: string, order: number, props: Kit.TextProps?): TextLabel
	local p: Kit.TextProps = props or {}
	p.size = p.size or UDim2.new(1, 0, 0, 18)
	p.textSize = p.textSize or 13
	p.wrap = if p.wrap == nil then true else p.wrap
	local l = Kit.label(parent, text, p)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.LayoutOrder = order
	return l
end

local function unitRow(parent: Instance, u: any, order: number)
	local honours = if type(u.honours) == "table" and #u.honours > 0 then table.concat(u.honours, " · ") else nil
	local f = Instance.new("Frame") :: Frame
	f.Size = UDim2.new(1, 0, 0, if honours then 44 else 30)
	f.BackgroundTransparency = 1
	f.LayoutOrder = order
	f.Parent = parent
	local name = Kit.label(f, u.name, { size = UDim2.new(1, -40, 0, 16), textSize = 12 })
	name.TextTruncate = Enum.TextTruncate.AtEnd
	Kit.label(f, string.rep("›", math.clamp(u.experience or 0, 0, 3)), { size = UDim2.fromOffset(36, 16), position = UDim2.new(1, -36, 0, 0), textSize = 14, colour = Kit.MUTED, align = Enum.TextXAlignment.Right })
	local track = Instance.new("Frame") :: Frame
	track.Size = UDim2.new(1, -60, 0, 5)
	track.Position = UDim2.new(0, 0, 0, 20)
	track.BackgroundColor3 = Kit.INK
	track.BackgroundTransparency = 0.7
	track.BorderSizePixel = 0
	track.Parent = f
	local fill = Instance.new("Frame") :: Frame
	fill.Size = UDim2.fromScale(math.clamp(u.strength / math.max(u.maxStrength, 1), 0, 1), 1)
	fill.BackgroundColor3 = Kit.FRANCE
	fill.BorderSizePixel = 0
	fill.Parent = track
	Kit.label(f, string.format("%d/%d", u.strength, u.maxStrength), { size = UDim2.fromOffset(56, 12), position = UDim2.new(1, -56, 0, 17), textSize = 10, colour = Kit.MUTED, align = Enum.TextXAlignment.Right })
	if honours then
		-- battle honours under the name, like the battle names on a regiment's colour
		local h = Kit.label(f, honours, { size = UDim2.new(1, 0, 0, 12), position = UDim2.fromOffset(0, 29), textSize = 11, colour = Kit.GOLD })
		h.FontFace = Kit.ITALIC
		h.TextTruncate = Enum.TextTruncate.AtEnd
	end
end

local function armySection(parent: Instance, order: number)
	local a = armyById(selectedArmy)
	if not a then
		return
	end
	local s = section(parent, a.name, order)
	local r = regionById(a.regionId)
	local where: string = if r then tostring(r.name) else tostring(a.regionId)
	local supplyWord: string = if a.supplied then "supplied" else "out of supply"
	row(s, string.format("%s · %s · %d men · %s", factionName(a.faction), where, armyStrength(a), supplyWord), 1, { colour = if a.supplied then Kit.MUTED else Kit.HOSTILE })
	for i, u in a.units do
		unitRow(s, u, 10 + i)
	end
	if a.faction == PLAYER then
		local need = 0
		for _, u in a.units do
			need += math.max(u.maxStrength - u.strength, 0)
		end
		local cost = math.ceil(need * 0.5)
		local b = Kit.button(s, string.format("Replenish  (%d men · %d treasury)", need, cost), function()
			send("command", { kind = "replenish", armyId = a.id })
		end, { size = UDim2.new(1, 0, 0, 30), order = 100, textSize = 12 })
		local ok, why = true, nil
		if not playerPhase() then
			ok, why = false, REASONS.wrongPhase
		elseif need == 0 then
			ok, why = false, REASONS.nothingToReplenish
		elseif not r or r.owner ~= PLAYER then
			ok, why = false, "Replacements only arrive in a region you hold"
		elseif view.treasury < 1 or view.manpower < 1 then
			ok, why = false, "No treasury or manpower for replacements"
		end
		Kit.setEnabled(b, ok, why)
		local moveText = if a.movesLeft > 0 then "Can march this turn: click a highlighted region." else "Has marched this turn."
		row(s, moveText, 101, { colour = Kit.MUTED, textSize = 12 })
	end
end

local function regionSection(parent: Instance, order: number)
	local r = regionById(selectedRegion)
	if not r then
		return
	end
	local s = section(parent, r.name .. (if r.isCity then " (city)" else ""), order)
	local owner: string = factionName(r.owner)
	local income: number, men: number, ground: string = r.income, r.manpower, tostring(r.terrain)
	row(s, string.format("Held by %s · +%d treasury, +%d manpower per turn · %s ground", owner, income, men, ground), 1, { colour = Kit.MUTED, textSize = 12 })
	for _, q in view.recruitment do
		if q.regionId == r.id then
			local qName: string, left: number = tostring(q.name), q.turnsLeft
			row(s, string.format("Raising %s — %d turn%s left", qName, left, plural(left)), 2, { textSize = 12 })
		end
	end
	local sub = row(s, "Recruit here", 3, { font = Enum.Font.GothamBold, textSize = 12 })
	sub.LayoutOrder = 3
	local keys = {}
	for key, t in view.unitTypes do
		if t.recruitable then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(x: string, y: string)
		return view.unitTypes[x].cost < view.unitTypes[y].cost
	end)
	for i, key in keys do
		local t = view.unitTypes[key]
		local tName: string, cost: number, turns: number, size: number = tostring(t.name), t.cost, t.turns, t.strength
		local b = Kit.button(s, string.format("%s · %d treasury · %d turn%s · %d men", tName, cost, turns, plural(turns), size), function()
			send("command", { kind = "recruit", regionId = r.id, unitType = key })
		end, { size = UDim2.new(1, 0, 0, 28), order = 10 + i, textSize = 11 })
		b.TextXAlignment = Enum.TextXAlignment.Left
		local ok, why = true, nil
		if not playerPhase() then
			ok, why = false, REASONS.wrongPhase
		elseif r.owner ~= PLAYER then
			ok, why = false, REASONS.notYourRegion
		elseif queueCount() >= 6 then
			ok, why = false, REASONS.queueFull
		elseif view.treasury < t.cost then
			ok, why = false, string.format("Not enough treasury (%d needed)", t.cost)
		end
		Kit.setEnabled(b, ok, why)
	end
end

local function buildSide()
	local s = side
	if not s or not view then
		return
	end
	s:ClearAllChildren()
	Kit.list(s, 10)
	local order = 0
	local function next(): number
		order += 1
		return order
	end
	-- header
	local head = section(s, string.format("Turn %d of %d", view.turn, view.turnLimit), next())
	local phaseText = if view.victory then (if view.victory.outcome == "victory" then "Campaign won" else "Campaign lost") elseif view.pendingBattle then "A battle awaits" elseif view.phase == "player" then "Your orders" else "The enemy moves"
	row(head, phaseText, 1, { colour = Kit.MUTED })
	row(head, string.format("Treasury %d   ·   Manpower %d   ·   Supply %d%%", view.treasury, view.manpower, view.supply), 2, { font = Enum.Font.GothamBold })
	if view.supply <= 25 then
		row(head, "Supply is low: unpaid upkeep bleeds strength each turn.", 3, { colour = Kit.HOSTILE, textSize = 12 })
	end
	if sessionOnly then
		row(head, "Saving unavailable: progress lasts this session only.", 4, { colour = Kit.HOSTILE, textSize = 12 })
	end
	local endTurn = Kit.button(head, "End Turn", function()
		send("command", { kind = "endTurn" })
	end, { size = UDim2.new(1, 0, 0, 36), primary = true, order = 5, textSize = 15 })
	Kit.setEnabled(endTurn, playerPhase(), if view.pendingBattle then "Resolve the pending battle first" elseif view.victory then "The campaign is over" else REASONS.wrongPhase)

	if view.victory then
		local v = section(s, if view.victory.outcome == "victory" then "Victory" else "Defeat", next())
		row(v, tostring(view.victory.reason), 1)
		Kit.button(v, "Start again", function()
			send("command", { kind = "restart" })
		end, { size = UDim2.new(1, 0, 0, 30), order = 2 })
	end

	armySection(s, next())
	regionSection(s, next())

	local obj = section(s, "Objectives", next())
	for i, o in view.objectives.regions do
		row(obj, (if o.held then "■  " else "□  ") .. o.name, i, { colour = if o.held then Kit.IVORY else Kit.MUTED })
	end
	local ok = view.objectives.armyStrength >= view.objectives.minArmyStrength
	row(obj, string.format("Army strength %d / %d required", view.objectives.armyStrength, view.objectives.minArmyStrength), 20, { colour = if ok then Kit.IVORY else Kit.MUTED })

	local lg = section(s, "Dispatches", next())
	local lines = view.log or {}
	for i = #lines, math.max(1, #lines - 9), -1 do
		row(lg, "· " .. tostring(lines[i]), 100 - i, { textSize = 12, colour = Kit.MUTED })
	end

	local tools = section(s, "", next())
	Kit.button(tools, if confirmNew then "Confirm: abandon and start new" else "New Campaign", function()
		if confirmNew then
			confirmNew = false
			send("new")
		else
			confirmNew = true
			CampaignScreen.render()
		end
	end, { size = UDim2.new(1, 0, 0, 30), order = 1, primary = confirmNew })
	if confirmNew then
		Kit.button(tools, "Cancel", function()
			confirmNew = false
			CampaignScreen.render()
		end, { size = UDim2.new(1, 0, 0, 28), order = 2 })
	end
	Kit.button(tools, "Main Menu", function()
		if cb then
			cb.menu()
		end
	end, { size = UDim2.new(1, 0, 0, 30), order = 3 })
end

-- ------------------------------------------------------------------ battle dialog

local function buildDialog(sg: ScreenGui)
	if dialog then
		dialog:Destroy()
		dialog = nil
	end
	local pb = view and view.pendingBattle
	if not pb then
		return
	end
	local r = regionById(pb.regionId)
	local d = Kit.panel(sg, { size = UDim2.fromOffset(420, 200), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), padding = 18 })
	d.ZIndex = 20
	Kit.title(d, "Battle at " .. (if r then r.name else pb.regionId), { size = UDim2.new(1, 0, 0, 32), textSize = 26 })
	local ground: string = if r then tostring(r.terrain) else "open"
	Kit.label(d, string.format("%s attacks %s. Fight it on the %s ground, or let the staff resolve it.", factionName(pb.attacker), factionName(pb.defender), ground), { size = UDim2.new(1, 0, 0, 60), position = UDim2.new(0, 0, 0, 40), wrap = true, textSize = 13 })
	local rowF = Instance.new("Frame") :: Frame
	rowF.Size = UDim2.new(1, 0, 0, 38)
	rowF.Position = UDim2.new(0, 0, 1, -38)
	rowF.BackgroundTransparency = 1
	rowF.Parent = d
	Kit.list(rowF, 8, true)
	Kit.button(rowF, "Fight", function()
		send("battle")
	end, { size = UDim2.new(0.5, -4, 1, 0), primary = true, order = 1, textSize = 15 })
	Kit.button(rowF, "Auto-resolve", function()
		send("skip")
	end, { size = UDim2.new(0.5, -4, 1, 0), order = 2, textSize = 15, tooltip = "The staff decides the outcome from strength and ground" })
	dialog = d
end

-- ------------------------------------------------------------------ public

local function build()
	if gui then
		return
	end
	local sg = Kit.screen("EoECampaign", 32)
	local back = Instance.new("Frame") :: Frame
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(28, 26, 22)
	back.BackgroundTransparency = 0.35
	back.BorderSizePixel = 0
	back.Active = true
	back.Parent = sg
	local mapPanel = Kit.panel(sg, { size = UDim2.new(1, -420, 1, -32), position = UDim2.new(0, 16, 0, 16), transparency = 0 })
	mapPanel.BackgroundColor3 = OLIVE
	local grad = (mapPanel:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")) :: UIGradient
	mapPanel.BackgroundColor3 = Color3.new(1, 1, 1)
	grad.Color = ColorSequence.new(OLIVE, OLIVE_DARK)
	grad.Rotation = 60
	grad.Parent = mapPanel
	local mf = Instance.new("Frame") :: Frame
	mf.Size = UDim2.fromScale(1, 1)
	mf.AnchorPoint = Vector2.new(0.5, 0.5)
	mf.Position = UDim2.fromScale(0.5, 0.5)
	mf.BackgroundTransparency = 1
	mf.Parent = mapPanel
	local aspect = Instance.new("UIAspectRatioConstraint") :: UIAspectRatioConstraint
	aspect.AspectRatio = 1.15
	aspect.Parent = mf
	-- the parchment map: the Saale, the Ilm and the Elster, hills and woods (tools/thuringia_map.py)
	local parchment = Instance.new("ImageLabel") :: ImageLabel
	parchment.Size = UDim2.fromScale(1, 1)
	parchment.BackgroundTransparency = 1
	parchment.Image = Assets.paintings.thuringia
	parchment.Parent = mf
	local rl = Instance.new("Frame") :: Frame
	rl.Size = UDim2.fromScale(1, 1)
	rl.BackgroundTransparency = 1
	rl.Parent = mf
	local nl = Instance.new("Frame") :: Frame
	nl.Size = UDim2.fromScale(1, 1)
	nl.BackgroundTransparency = 1
	nl.ZIndex = 5
	nl.Parent = mf
	local t = Kit.title(mapPanel, "Thuringia, October 1806", { size = UDim2.new(1, -20, 0, 30), position = UDim2.new(0, 12, 0, 6), textSize = 24, colour = Kit.CREAM })
	t.ZIndex = 8
	local compass = Kit.label(mapPanel, "N ▲", { size = UDim2.fromOffset(60, 20), position = UDim2.new(1, -12, 0, 10), anchor = Vector2.new(1, 0), textSize = 12, colour = Kit.CREAM, align = Enum.TextXAlignment.Right })
	compass.ZIndex = 8
	local sidePanel = Kit.panel(sg, { size = UDim2.new(0, 380, 1, -32), position = UDim2.new(1, -16, 0, 16), anchor = Vector2.new(1, 0), padding = 14 })
	local sc = Instance.new("ScrollingFrame") :: ScrollingFrame
	sc.Size = UDim2.fromScale(1, 1)
	sc.BackgroundTransparency = 1
	sc.BorderSizePixel = 0
	sc.ScrollBarThickness = 6
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.CanvasSize = UDim2.new()
	sc.Active = true
	sc.Parent = sidePanel
	toast = Kit.label(sg, "", { size = UDim2.new(1, -420, 0, 24), position = UDim2.new(0, 16, 1, -40), textSize = 13, align = Enum.TextXAlignment.Center, colour = Kit.CREAM })
	toast.TextStrokeTransparency = 0.3
	toast.TextStrokeColor3 = Kit.INK
	toast.ZIndex = 9
	toast.Visible = false
	gui = sg
	mapFrame = mf
	roadLayer = rl
	nodeLayer = nl
	side = sc
	sizeConn = mf:GetPropertyChangedSignal("AbsoluteSize"):Connect(drawRoads)
end

function CampaignScreen.render()
	if not gui or not view then
		return
	end
	-- keep the selection valid against the new view
	if selectedArmy and not armyById(selectedArmy) then
		selectedArmy = nil
	end
	if selectedRegion and not regionById(selectedRegion) then
		selectedRegion = nil
	end
	drawRoads()
	drawNodes()
	buildSide()
	buildDialog(gui :: ScreenGui)
end

function CampaignScreen.show(v: any, isSessionOnly: boolean, callbacks: Callbacks)
	build()
	cb = callbacks
	view = v
	sessionOnly = isSessionOnly
	if gui then
		gui.Enabled = true
	end
	CampaignScreen.render()
end

function CampaignScreen.setView(v: any, isSessionOnly: boolean)
	view = v
	sessionOnly = isSessionOnly
	confirmNew = false
	CampaignScreen.render()
end

function CampaignScreen.showError(reason: string)
	local text = REASONS[reason] or reason
	if toast then
		toast.Text = text
		toast.Visible = true
		task.delay(4, function()
			if toast and toast.Text == text then
				toast.Visible = false
			end
		end)
	end
end

function CampaignScreen.isOpen(): boolean
	return gui ~= nil and (gui :: ScreenGui).Enabled
end

function CampaignScreen.hide()
	if gui then
		gui.Enabled = false
	end
end

function CampaignScreen.destroy()
	if sizeConn then
		sizeConn:Disconnect()
		sizeConn = nil
	end
	if gui then
		gui:Destroy()
		gui = nil
	end
	mapFrame = nil
	roadLayer = nil
	nodeLayer = nil
	side = nil
	toast = nil
	dialog = nil
	view = nil
	cb = nil
	selectedArmy = nil
	selectedRegion = nil
	confirmNew = false
end

return CampaignScreen
