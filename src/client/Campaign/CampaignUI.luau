--!strict
-- Grand-campaign panels in the Kit style: top bar, selected army and province (left),
-- diplomacy (right) and the documents on top: event dispatches, the battle dialog, the
-- turn summary, victory/defeat and the choice of nation. Rebuilt from the view on each
-- render; every action goes back through `Callbacks.send`.

local Kit = require(script.Parent.Parent.UI.Kit)
local Data = require(script.Parent.Data)
local Logic = require(script.Parent.Logic)

local UI = {}

export type Callbacks = {
	send: (kind: string, data: { [string]: any }?) -> (),
	menu: () -> (),
	render: () -> (), -- re-render after a local UI change
}

export type Ctx = {
	view: any?,
	player: string,
	sessionOnly: boolean,
	army: any?, -- selected army
	province: string?, -- selected province
	others: { any }, -- the player's other armies in the selected army's province
	canAct: boolean,
	actReason: string,
}

local gui: ScreenGui? = nil
local cb: Callbacks? = nil
local diplomacyOpen = false
local objectivesOpen = false
local pickerReason: string? = nil -- nation choice open (with the reason it opened)
local summary: { lines: { string }, title: string }? = nil
local dismissed: { [any]: boolean } = {}
local split: { [any]: boolean } = {}
local splitArmy: any = nil
local toastLabel: TextLabel? = nil

-- ------------------------------------------------------------------ helpers

local function fmt(n: any): string
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(v)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(s, 1, 1) == "," then
		s = string.sub(s, 2)
	end
	return (if v < 0 then "-" else "") .. s
end

local function plural(n: number, word: string): string
	return string.format("%d %s%s", n, word, if n == 1 then "" else "s")
end

local function send(kind: string, data: { [string]: any }?)
	if cb then
		cb.send(kind, data)
	end
end

local function rerender()
	if cb then
		cb.render()
	end
end

local function flag(parent: Instance, nation: string, w: number, h: number, pos: UDim2?): Frame
	local f = Kit.flag(parent, nation, Vector2.new(w, h), pos or UDim2.new())
	if not Data.hasFlag(nation) then
		for _, c in f:GetChildren() do
			if c:IsA("Frame") and (c :: Frame).Size == UDim2.fromOffset(w, h) then
				(c :: Frame).BackgroundColor3 = Data.colour(nation)
			end
		end
	end
	return f
end

local function column(parent: Instance, order: number, gap: number?): Frame
	local f = Instance.new("Frame") :: Frame
	f.Size = UDim2.new(1, 0, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundTransparency = 1
	f.LayoutOrder = order
	f.Parent = parent
	Kit.list(f, gap or 4)
	return f
end

local function panel(parent: Instance, order: number, parchment: boolean?): Frame
	local p = Kit.panel(parent, { size = UDim2.new(1, 0, 0, 0), position = UDim2.new(), padding = 14, parchment = parchment })
	p.AutomaticSize = Enum.AutomaticSize.Y
	p.LayoutOrder = order
	Kit.list(p, 6)
	return p
end

local function text(parent: Instance, s: string, order: number, props: Kit.TextProps?): TextLabel
	local p: Kit.TextProps = props or {}
	p.size = p.size or UDim2.new(1, 0, 0, 18)
	p.wrap = if p.wrap == nil then true else p.wrap
	p.textSize = p.textSize or 14
	local l = Kit.label(parent, s, p)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.LayoutOrder = order
	return l
end

local function row(parent: Instance, order: number, h: number): Frame
	local f = Instance.new("Frame") :: Frame
	f.Size = UDim2.new(1, 0, 0, h)
	f.BackgroundTransparency = 1
	f.LayoutOrder = order
	f.Parent = parent
	return f
end

local function buttonRow(parent: Instance, order: number, h: number?): Frame
	local f = row(parent, order, h or 30)
	Kit.list(f, 6, true)
	return f
end

local function nationOf(view: any, id: string): any
	return view.nations and view.nations[id] or {}
end

local function contains(list: any, v: any): boolean
	return type(list) == "table" and table.find(list, v) ~= nil
end

-- ------------------------------------------------------------------ top bar

local function topBar(sg: ScreenGui, ctx: Ctx)
	local view = ctx.view
	local bar = Kit.panel(sg, { size = UDim2.new(1, -24, 0, 54), position = UDim2.new(0.5, 0, 0, 8), anchor = Vector2.new(0.5, 0), padding = 8, plain = true })
	local inner = Instance.new("Frame") :: Frame
	inner.Size = UDim2.fromScale(1, 1)
	inner.BackgroundTransparency = 1
	inner.Parent = bar
	local l = Kit.list(inner, 14, true)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	local function item(order: number, w: number): Frame
		local f = row(inner, order, 38)
		f.Size = UDim2.fromOffset(w, 38)
		return f
	end
	local me = if view then nationOf(view, ctx.player) else {}
	local fl = flag(item(1, 44), ctx.player, 36, 24, UDim2.fromOffset(0, 2))
	fl.Name = "Flag"
	local who = item(2, 220)
	Kit.title(who, Data.name(ctx.player), { size = UDim2.new(1, 0, 0, 22), textSize = 22, colour = Kit.GILT_BRIGHT })
	local date = Kit.label(who, if view then string.format("%s · turn %s of %s%s", tostring(view.date or "?"), tostring(view.turn or "?"), tostring(view.endTurn or "?"), if view.phase and view.phase ~= "player" then " · " .. (if view.phase == "battle" then "battle pending" else tostring(view.phase)) else "") else "", { size = UDim2.new(1, 0, 0, 16), position = UDim2.fromOffset(0, 22), textSize = 14, colour = Kit.MUTED })
	date.FontFace = Kit.ITALIC
	local money = item(3, 150)
	Kit.label(money, "TREASURY", { size = UDim2.new(1, 0, 0, 14), textSize = 11, colour = Kit.MUTED })
	Kit.label(money, fmt(me.treasury), { size = UDim2.new(1, 0, 0, 22), position = UDim2.fromOffset(0, 14), textSize = 20, font = Enum.Font.Garamond })
	local men = item(4, 150)
	Kit.label(men, "MANPOWER", { size = UDim2.new(1, 0, 0, 14), textSize = 11, colour = Kit.MUTED })
	Kit.label(men, fmt(me.manpower), { size = UDim2.new(1, 0, 0, 22), position = UDim2.fromOffset(0, 14), textSize = 20, font = Enum.Font.Garamond })
	local flow = item(5, 150)
	Kit.label(flow, "PER TURN", { size = UDim2.new(1, 0, 0, 14), textSize = 11, colour = Kit.MUTED })
	local net = (tonumber(me.income) or 0) - (tonumber(me.upkeep) or 0)
	Kit.label(flow, string.format("%s%s", if net >= 0 then "+" else "", fmt(net)), { size = UDim2.new(1, 0, 0, 22), position = UDim2.fromOffset(0, 14), textSize = 20, font = Enum.Font.Garamond, colour = if net < 0 then Kit.HOSTILE else Kit.IVORY })
	Kit.hoverTip(flow, function(): string
		return string.format("Income %s, upkeep %s, recruits +%s men", fmt(me.income), fmt(me.upkeep), fmt(me.manpowerIncome))
	end)
	if ctx.sessionOnly then
		local warn = item(6, 200)
		Kit.label(warn, "Saving unavailable: this campaign lasts the session only.", { size = UDim2.fromScale(1, 1), textSize = 12, wrap = true, colour = Kit.HOSTILE })
	end
	-- right-hand group
	local right = Instance.new("Frame") :: Frame
	right.Size = UDim2.new(0, 600, 1, 0)
	right.Position = UDim2.fromScale(1, 0)
	right.AnchorPoint = Vector2.new(1, 0)
	right.BackgroundTransparency = 1
	right.Parent = bar
	local rl = Kit.list(right, 8, true)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rl.VerticalAlignment = Enum.VerticalAlignment.Center
	local dip = Kit.button(right, "Diplomacy", function()
		diplomacyOpen = not diplomacyOpen
		rerender()
	end, { size = UDim2.fromOffset(120, 34), order = 1, tooltip = "Relations, wars and offers" })
	Kit.setActiveLook(dip, diplomacyOpen)
	local obj = Kit.button(right, "Objectives", function()
		objectivesOpen = not objectivesOpen
		rerender()
	end, { size = UDim2.fromOffset(120, 34), order = 0, tooltip = "What wins the campaign" })
	Kit.setActiveLook(obj, objectivesOpen)
	Kit.button(right, "Main Menu", function()
		if cb then
			cb.menu()
		end
	end, { size = UDim2.fromOffset(120, 34), order = 2 })
	local endTurn = Kit.button(right, "End Turn", function()
		send("endTurn")
	end, { size = UDim2.fromOffset(150, 38), primary = true, order = 3, textSize = 16, tooltip = "End the turn (E)" })
	Kit.setEnabled(endTurn, ctx.canAct, ctx.actReason)
end

-- ------------------------------------------------------------------ left: army and province

local function unitKey(u: any, i: number): any
	return u.key or u.id or i
end

local function armyPanel(parent: Instance, ctx: Ctx, order: number)
	local a = ctx.army
	if not a then
		return
	end
	local view = ctx.view or {}
	local own = a.nation == ctx.player
	if splitArmy ~= a.id then
		splitArmy = a.id
		table.clear(split)
	end
	local p = panel(parent, order)
	local head = row(p, 1, 30)
	flag(head, a.nation, 30, 20, UDim2.fromOffset(0, 2))
	local t = Kit.title(head, tostring(a.name or "Army"), { size = UDim2.new(1, -40, 1, 0), position = UDim2.fromOffset(40, 0), textSize = 22, caps = false })
	t.TextTruncate = Enum.TextTruncate.AtEnd
	local prov = Data.byId[a.provinceId]
	local stars = if a.rating then "  " .. string.rep("★", math.clamp(math.floor(tonumber(a.rating) or 0), 0, 5)) else ""
	text(p, string.format("%s%s · %s", if a.general then "General " .. tostring(a.general) else "No general", stars, tostring(if prov then prov.name else a.provinceId)), 2, { colour = Kit.MUTED })
	local moves = if a.movesLeft ~= nil then string.format(" · %d/%d moves", a.movesLeft, a.movesMax or a.movesLeft) else ""
	text(p, string.format("%s men · %s · strength %s%s", fmt(a.men or a.strength), plural(tonumber(a.unitCount) or 0, "unit"), fmt(a.strength), moves), 3, { font = Enum.Font.SourceSansSemibold })
	local units: any = a.units
	if type(units) == "table" and next(units) ~= nil and type(select(2, next(units))) ~= "table" then
		local list = {}
		for k, n in units do
			local c = Data.Europe.UnitClasses[k]
			table.insert(list, { key = k, name = string.format("%s × %s", if c then c.name else tostring(k), tostring(n)) })
		end
		units = list
	end
	if type(units) == "table" then
		for i, u in units do
			local k = unitKey(u, i)
			local honours = if type(u.honours) == "table" and #u.honours > 0 then table.concat(u.honours, " · ") else nil
			local r = row(p, 10 + i, if honours then 48 else 34)
			local x = 0
			if own then
				local pick = Kit.button(r, if split[k] then "✓" else "", function()
					split[k] = not split[k] or nil
					rerender()
				end, { size = UDim2.fromOffset(20, 20), position = UDim2.fromOffset(0, 4), caps = false, tooltip = "Mark for splitting off" })
				Kit.setActiveLook(pick, split[k] == true)
				x = 28
			end
			local name = Kit.label(r, tostring(u.name or u.type or "Unit"), { size = UDim2.new(1, -x - 50, 0, 16), position = UDim2.fromOffset(x, 0), textSize = 13 })
			name.TextTruncate = Enum.TextTruncate.AtEnd
			Kit.label(r, string.rep("›", math.clamp(math.floor(tonumber(u.experience) or 0), 0, 3)), { size = UDim2.fromOffset(46, 16), position = UDim2.new(1, -46, 0, 0), textSize = 16, colour = Kit.GILT, align = Enum.TextXAlignment.Right })
			if u.strength ~= nil then
				local s, m = tonumber(u.strength) or 0, tonumber(u.maxStrength) or tonumber(u.strength) or 1
				local fill = Kit.bar(r, UDim2.new(1, -x - 64, 0, 6), UDim2.fromOffset(x, 21), Data.colour(a.nation):Lerp(Kit.IVORY, 0.2))
				Kit.setBar(fill, s / math.max(m, 1))
				Kit.label(r, string.format("%s/%s", fmt(s), fmt(m)), { size = UDim2.fromOffset(60, 14), position = UDim2.new(1, -60, 0, 17), textSize = 11, colour = Kit.MUTED, align = Enum.TextXAlignment.Right })
			end
			if honours then
				-- battle honours under the name, like the battle names on a regiment's colour
				local h = Kit.label(r, honours, { size = UDim2.new(1, -x, 0, 13), position = UDim2.fromOffset(x, 32), textSize = 12, colour = Kit.GILT })
				h.FontFace = Kit.ITALIC
				h.TextTruncate = Enum.TextTruncate.AtEnd
			end
		end
	end
	if not own then
		return
	end
	local br = buttonRow(p, 100)
	local into = ctx.others[1]
	local merge = Kit.button(br, "Merge", function()
		if into then
			send("merge", { armyId = a.id, intoArmyId = into.id })
		end
	end, { size = UDim2.new(1 / 3, -4, 1, 0), tooltip = if into then "Join " .. tostring(into.name) else nil })
	Kit.setEnabled(merge, ctx.canAct and into ~= nil, if not ctx.canAct then ctx.actReason else "No other army of yours in this province")
	local keys, all = {}, 0
	if type(units) == "table" then
		for i, u in units do
			all += 1
			if split[unitKey(u, i)] then
				table.insert(keys, unitKey(u, i))
			end
		end
	end
	local sp = Kit.button(br, "Split", function()
		send("split", { armyId = a.id, unitKeys = keys })
		table.clear(split)
	end, { size = UDim2.new(1 / 3, -4, 1, 0), tooltip = "Form a new army from the marked units" })
	Kit.setEnabled(sp, ctx.canAct and #keys > 0 and #keys < all, if not ctx.canAct then ctx.actReason elseif #keys == 0 then "Mark the units to split off" else "Leave at least one unit behind")
	local losses = false
	if type(units) == "table" then
		for _, u in units do
			if (tonumber(u.maxStrength) or 0) > (tonumber(u.strength) or 0) then
				losses = true
			end
		end
	end
	local ps = view.provinces and view.provinces[a.provinceId]
	local home = ps and ps.owner == ctx.player and not ps.occupiedBy
	local rep = Kit.button(br, "Replenish", function()
		send("replenish", { armyId = a.id })
	end, { size = UDim2.new(1 / 3, -4, 1, 0), tooltip = "Draw replacements from treasury and manpower" })
	Kit.setEnabled(rep, ctx.canAct and losses and home == true, if not ctx.canAct then ctx.actReason elseif not losses then "At full strength" else "Replacements only reach armies in your own provinces")
	if ctx.canAct then
		text(p, "Right-click a province to march. Red marks where an enemy halts you.", 101, { colour = Kit.MUTED, textSize = 12 })
	end
end

local function recruitOptions(view: any, provinceId: string): { any }
	local opts = view.recruitment and view.recruitment.options
	return if type(opts) == "table" and type(opts[provinceId]) == "table" then opts[provinceId] else {}
end

local function provincePanel(parent: Instance, ctx: Ctx, order: number)
	local id = ctx.province
	local p = if id then Data.byId[id] else nil
	if not p or not id then
		return
	end
	local view = ctx.view or {}
	local ps = view.provinces and view.provinces[id] or {}
	local owner = ps.owner or p.owner1805
	local panelF = panel(parent, order)
	local head = row(panelF, 1, 30)
	flag(head, owner, 30, 20, UDim2.fromOffset(0, 2))
	Kit.title(head, p.name .. (if p.isCapital then "  ★" else ""), { size = UDim2.new(1, -40, 1, 0), position = UDim2.fromOffset(40, 0), textSize = 22, caps = false })
	text(panelF, "Held by " .. Data.name(owner), 2, { colour = Kit.MUTED })
	if ps.occupiedBy and ps.occupiedBy ~= owner then
		text(panelF, "Occupied by " .. Data.name(ps.occupiedBy), 3, { colour = Kit.HOSTILE })
	end
	local facts = { string.format("Income %s", fmt(p.income)), string.format("Manpower %s", fmt(p.manpower)) }
	if (p.fort or 0) > 0 then
		table.insert(facts, "Fortress " .. string.rep("I", p.fort))
	end
	if p.isPort then
		table.insert(facts, "Port")
	end
	text(panelF, table.concat(facts, " · "), 4)
	if ps.unrest and ps.unrest > 0 then
		text(panelF, string.format("Unrest %s", tostring(ps.unrest)), 5, { colour = Kit.HOSTILE })
	end
	local siege = ps.siege
	if type(siege) == "table" then
		text(panelF, string.format("Besieged by %s: falls in %s unless relieved.", Data.name(siege.by), plural(tonumber(siege.turnsLeft) or 0, "turn")), 6, { colour = Kit.HOSTILE })
	end
	if owner ~= ctx.player then
		return
	end
	-- recruitment queue and options
	local rec = view.recruitment or {}
	local queued = 0
	local q = column(panelF, 10)
	for _, e in rec.queue or {} do
		if type(e) == "table" and e.provinceId == id then
			queued += 1
			text(q, string.format("Raising %s: %s left", tostring(e.name or e.unitType), plural(tonumber(e.turnsLeft) or 0, "turn")), queued, { textSize = 13, colour = Kit.MUTED })
		end
	end
	local opts = recruitOptions(view, id)
	if #opts == 0 then
		return
	end
	Kit.title(panelF, "Recruit", { size = UDim2.new(1, 0, 0, 22), textSize = 18 }).LayoutOrder = 20
	for i, o in opts do
		local b = Kit.button(panelF, string.format("%s   ·   %s gold · %s men · %s · upkeep %s", tostring(o.name or o.unitType), fmt(o.cost), fmt(o.manpower), plural(tonumber(o.turns) or 1, "turn"), fmt(o.upkeep)), function()
			send("recruit", { provinceId = id, unitType = o.unitType })
		end, { size = UDim2.new(1, 0, 0, 28), order = 20 + i, textSize = 13, caps = false })
		b.TextXAlignment = Enum.TextXAlignment.Left
		local why: string? = if not ctx.canAct then ctx.actReason elseif o.available == false then Logic.reason(o.reason) else nil
		Kit.setEnabled(b, why == nil, why)
	end
end

-- ------------------------------------------------------------------ right: diplomacy

local function diplomacy(parent: Instance, ctx: Ctx)
	local view = ctx.view
	if not view then
		return
	end
	local p = panel(parent, 1)
	Kit.title(p, "Diplomacy", { size = UDim2.new(1, 0, 0, 28), textSize = 24, rule = true }).LayoutOrder = 1
	local me = nationOf(view, ctx.player)
	local offers = view.diplomacy and view.diplomacy.offers or {}
	if #offers > 0 then
		local col = column(p, 2, 6)
		for i, o in offers do
			local box = panel(col, i, true)
			text(box, Logic.offerText(o), 1, { textSize = 15, font = Enum.Font.Garamond })
			local br = buttonRow(box, 3, 28)
			Kit.button(br, "Accept", function()
				send("diplomacy", { nation = o.from, action = "accept", offerId = o.id })
			end, { size = UDim2.new(0.5, -3, 1, 0), primary = true })
			Kit.button(br, "Reject", function()
				send("diplomacy", { nation = o.from, action = "reject", offerId = o.id })
			end, { size = UDim2.new(0.5, -3, 1, 0) })
		end
	end
	local ids: { string } = {}
	for id in view.nations or {} do
		if id ~= ctx.player then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a: string, b: string): boolean
		local ma, mb = Data.Nations[a] and Data.Nations[a].major or false, Data.Nations[b] and Data.Nations[b].major or false
		if ma ~= mb then
			return ma
		end
		return Data.name(a) < Data.name(b)
	end)
	local list = Instance.new("ScrollingFrame") :: ScrollingFrame
	list.Size = UDim2.new(1, 0, 0, 420)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.LayoutOrder = 3
	list.Parent = p
	Kit.list(list, 8)
	for i, id in ids do
		local n = view.nations[id]
		local war, ally = contains(me.atWarWith, id), contains(me.allies, id)
		local alive = n.alive ~= false
		local truce = tonumber(n.truceUntil)
		local r = row(list, i, 58)
		r.Size = UDim2.new(1, -8, 0, 58)
		flag(r, id, 28, 18, UDim2.fromOffset(0, 2))
		local nameL = Kit.label(r, Data.name(id) .. (if n.major then "  ✦" else ""), { size = UDim2.new(1, -150, 0, 20), position = UDim2.fromOffset(38, 0), textSize = 17, font = Enum.Font.Garamond })
		local cap = Data.byId[n.capital or ""]
		Kit.hoverTip(nameL, function(): string
			return (if n.major then "Great power. " else "") .. (if cap then "Capital: " .. cap.name else "")
		end)
		local status = if not alive then "Fallen" elseif war then (if n.warScore then string.format("At war (%+d)", n.warScore) else "At war") elseif ally then "Allied" elseif truce then "Truce to " .. Data.Europe.dateOf(truce) else "At peace"
		Kit.label(r, status, { size = UDim2.fromOffset(100, 18), position = UDim2.new(1, -100, 0, 1), textSize = 13, align = Enum.TextXAlignment.Right, colour = if war then Kit.HOSTILE elseif ally then Kit.GILT_BRIGHT else Kit.MUTED })
		local rel = math.clamp(tonumber(n.relationToPlayer) or 0, -100, 100)
		local fill = Kit.bar(r, UDim2.new(1, -38, 0, 5), UDim2.fromOffset(38, 24), Color3.fromRGB(184, 52, 40):Lerp(Color3.fromRGB(96, 150, 70), (rel + 100) / 200))
		Kit.setBar(fill, (rel + 100) / 200)
		Kit.hoverTip(fill.Parent :: Frame, function(): string
			return string.format("Relations %+d", rel)
		end)
		local br = Instance.new("Frame") :: Frame
		br.Size = UDim2.new(1, -38, 0, 22)
		br.Position = UDim2.fromOffset(38, 34)
		br.BackgroundTransparency = 1
		br.Parent = r
		Kit.list(br, 6, true)
		local function act(label: string, kind: string, ok: boolean, why: string, primary: boolean?)
			local b = Kit.button(br, label, function()
				send("diplomacy", { nation = id, action = kind })
			end, { size = UDim2.fromOffset(96, 22), textSize = 12, primary = primary })
			Kit.setEnabled(b, ok and ctx.canAct, if ctx.canAct then why else ctx.actReason)
		end
		if not alive then
			nameL.TextTransparency = 0.5
			for _, c in r:GetDescendants() do
				if c:IsA("Frame") then
					(c :: Frame).BackgroundTransparency = math.max((c :: Frame).BackgroundTransparency, 0.6)
				end
			end
		else
			act("Peace", "peace", war, "You are not at war")
			act("Alliance", "alliance", not war and not ally, if war then "Make peace first" else "Already allied")
			act("War", "war", not war and not ally and truce == nil, if ally then "You will not strike an ally" elseif truce then Logic.REASONS.truce else "Already at war", true)
		end
	end
end

-- ------------------------------------------------------------------ documents

local function modal(sg: ScreenGui, w: number, parchment: boolean?): Frame
	local shade = Instance.new("Frame") :: Frame
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.55
	shade.BorderSizePixel = 0
	shade.Active = true
	shade.Parent = sg
	local p = Kit.panel(shade, { size = UDim2.fromOffset(w, 0), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), padding = 22, parchment = parchment })
	p.AutomaticSize = Enum.AutomaticSize.Y
	local l = Kit.list(p, 10)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	return p
end

local function eventDoc(sg: ScreenGui, ev: any)
	local p = modal(sg, 480, true)
	local top = row(p, 0, 40)
	Kit.seal(top, UDim2.fromScale(0.5, 0.5), 40)
	Kit.title(p, tostring(ev.title or "Dispatch"), { size = UDim2.new(1, 0, 0, 30), textSize = 26, align = Enum.TextXAlignment.Center, caps = false, rule = true }).LayoutOrder = 1
	local body = text(p, tostring(ev.text or ""), 2, { textSize = 17, font = Enum.Font.Garamond })
	body.LineHeight = 1.1
	local choices = ev.choices
	local col = column(p, 3, 6)
	if type(choices) == "table" and #choices > 0 then
		for i, c in choices do
			local label = if type(c) == "table" then tostring(c.text or c.label or c.id) else tostring(c)
			local value = if type(c) == "table" then (c.id or i) else i
			local b = Kit.button(col, label, function()
				dismissed[ev.id] = true
				send("eventChoice", { eventId = ev.id, choice = value })
				rerender()
			end, { size = UDim2.new(1, 0, 0, 32), order = i :: number, caps = false, textSize = 15, primary = i == 1 })
			b.TextWrapped = true
		end
	else
		Kit.button(col, "Very well", function()
			dismissed[ev.id] = true
			send("eventChoice", { eventId = ev.id })
			rerender()
		end, { size = UDim2.new(1, 0, 0, 32), primary = true, textSize = 15 })
	end
end

local function battleDoc(sg: ScreenGui, ctx: Ctx, pb: any)
	local view = ctx.view or {}
	local p = modal(sg, 520)
	local prov = Data.byId[pb.provinceId]
	Kit.title(p, "Battle at " .. (if prov then prov.name else tostring(pb.provinceId)), { size = UDim2.new(1, 0, 0, 32), textSize = 28, align = Enum.TextXAlignment.Center, caps = false, rule = true }).LayoutOrder = 1
	local function side(v: any): (string, string)
		local a = Logic.army(view, v)
		if a then
			return a.nation, string.format("%s · %s men", tostring(a.name), fmt(a.men or a.strength))
		end
		return tostring(v), ""
	end
	local an, ad = side(pb.attacker)
	local dn, dd = side(pb.defender)
	an, dn = pb.attackerNation or an, pb.defenderNation or dn
	local sides = row(p, 2, 70)
	for i, s in { { an, ad, "Attacker" }, { dn, dd, "Defender" } } do
		local f = Instance.new("Frame") :: Frame
		f.Size = UDim2.new(0.5, -30, 1, 0)
		f.Position = if i == 1 then UDim2.new() else UDim2.new(0.5, 30, 0, 0)
		f.BackgroundTransparency = 1
		f.Parent = sides
		flag(f, s[1], 36, 24, UDim2.new(0.5, -20, 0, 0))
		Kit.label(f, string.format("%s: %s", s[3], Data.name(s[1])), { size = UDim2.new(1, 0, 0, 18), position = UDim2.fromOffset(0, 36), textSize = 15, font = Enum.Font.Garamond, align = Enum.TextXAlignment.Center })
		Kit.label(f, s[2], { size = UDim2.new(1, 0, 0, 14), position = UDim2.fromOffset(0, 54), textSize = 12, colour = Kit.MUTED, align = Enum.TextXAlignment.Center })
	end
	Kit.title(sides, "vs", { size = UDim2.fromOffset(60, 30), position = UDim2.new(0.5, 0, 0, 0), anchor = Vector2.new(0.5, 0), textSize = 22, colour = Kit.GILT, align = Enum.TextXAlignment.Center })
	local odds = tostring(pb.odds or "even")
	text(p, "The odds are " .. odds .. ".", 3, { align = Enum.TextXAlignment.Center, textSize = 16, colour = if odds == "favourable" then Kit.MORALE.steady elseif odds == "poor" then Kit.HOSTILE else Kit.IVORY })
	if pb.scenarioId then
		text(p, "This is the field of a famous battle: the historical engagement will be fought.", 4, { align = Enum.TextXAlignment.Center, textSize = 13, colour = Kit.MUTED })
	end
	local br = buttonRow(p, 5, 38)
	Kit.button(br, "Fight", function()
		send("fight")
	end, { size = UDim2.new(1 / 3, -4, 1, 0), primary = true, textSize = 15, tooltip = "Command the battle yourself" })
	Kit.button(br, "Auto-resolve", function()
		send("autoResolve")
	end, { size = UDim2.new(1 / 3, -4, 1, 0), textSize = 15, tooltip = "The staff decides from strength, ground and experience" })
	Kit.button(br, "Retreat", function()
		send("retreat")
	end, { size = UDim2.new(1 / 3, -4, 1, 0), textSize = 15, tooltip = "Withdraw to a neighbouring province, losing some stragglers" })
end

local function summaryDoc(sg: ScreenGui, s: { lines: { string }, title: string })
	local p = modal(sg, 500, true)
	Kit.title(p, s.title, { size = UDim2.new(1, 0, 0, 30), textSize = 24, align = Enum.TextXAlignment.Center, caps = false, rule = true }).LayoutOrder = 1
	local col = column(p, 2, 4)
	if #s.lines == 0 then
		text(col, "All quiet along the frontiers.", 1, { font = Enum.Font.Garamond, textSize = 16 })
	end
	for i, line in s.lines do
		text(col, "·  " .. line, i, { font = Enum.Font.Garamond, textSize = 16 })
	end
	Kit.button(p, "Continue", function()
		summary = nil
		rerender()
	end, { size = UDim2.fromOffset(180, 32), primary = true, order = 3, textSize = 15 })
end

local function victoryDoc(sg: ScreenGui, ctx: Ctx, v: any)
	local won, draw = v.outcome == "victory", v.outcome == "draw"
	local p = modal(sg, 520)
	Kit.title(p, if won then "Victory" elseif draw then "Draw" else "Defeat", { size = UDim2.new(1, 0, 0, 48), textSize = 44, spaced = true, align = Enum.TextXAlignment.Center, colour = if won then Kit.GILT_BRIGHT elseif draw then Kit.IVORY else Kit.HOSTILE, rule = true }).LayoutOrder = 1
	Kit.tricolour(p, UDim2.fromOffset(150, 6), UDim2.new()).LayoutOrder = 2
	text(p, tostring(v.reason or ""), 3, { align = Enum.TextXAlignment.Center, textSize = 18, font = Enum.Font.Garamond })
	local br = buttonRow(p, 4, 36)
	Kit.button(br, "New Campaign", function()
		pickerReason = ""
		rerender()
	end, { size = UDim2.new(0.5, -3, 1, 0), primary = true })
	Kit.button(br, "Main Menu", function()
		if cb then
			cb.menu()
		end
	end, { size = UDim2.new(0.5, -3, 1, 0) })
end

local function pickerDoc(sg: ScreenGui, reason: string)
	local p = modal(sg, 560)
	Kit.title(p, "Choose your nation", { size = UDim2.new(1, 0, 0, 32), textSize = 26, align = Enum.TextXAlignment.Center, rule = true }).LayoutOrder = 1
	local sub = text(p, "Europe, January 1805. Eleven years to decide its fate.", 2, { align = Enum.TextXAlignment.Center, textSize = 16, colour = Kit.MUTED })
	sub.FontFace = Kit.ITALIC
	if reason ~= "" then
		text(p, Logic.reason(reason), 3, { align = Enum.TextXAlignment.Center, textSize = 13, colour = Kit.MUTED })
	end
	local grid = row(p, 4, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	local g = Instance.new("UIGridLayout") :: UIGridLayout
	g.CellSize = UDim2.fromOffset(160, 44)
	g.CellPadding = UDim2.fromOffset(8, 8)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.HorizontalAlignment = Enum.HorizontalAlignment.Center
	g.Parent = grid
	local ids = {}
	for id, n in Data.Nations do
		if n.playable then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a: string, b: string): boolean
		return Data.name(a) < Data.name(b)
	end)
	for i, id in ids do
		local b = Kit.button(grid, Data.name(id), function()
			pickerReason = nil
			send("newCampaign", { nation = id })
		end, { order = i :: number, textSize = 16, caps = false })
		b.TextXAlignment = Enum.TextXAlignment.Right
		flag(b, id, 30, 20, UDim2.fromOffset(6, 7))
	end
	Kit.button(p, "Main Menu", function()
		if cb then
			cb.menu()
		end
	end, { size = UDim2.fromOffset(160, 30), order = 5 })
end

-- ------------------------------------------------------------------ public

function UI.open(callbacks: Callbacks)
	cb = callbacks
	if not gui then
		gui = Kit.screen("EoEGrandCampaign", 32)
	end
end

function UI.render(ctx: Ctx)
	local sg = gui
	if not sg then
		return
	end
	for _, c in sg:GetChildren() do
		if c ~= toastLabel then
			c:Destroy()
		end
	end
	Kit.hideTooltip()
	local view = ctx.view
	topBar(sg, ctx)
	local left = Instance.new("ScrollingFrame") :: ScrollingFrame
	left.Size = UDim2.new(0, 350, 1, -84)
	left.Position = UDim2.fromOffset(12, 72)
	left.BackgroundTransparency = 1
	left.BorderSizePixel = 0
	left.ScrollBarThickness = 0
	left.AutomaticCanvasSize = Enum.AutomaticSize.Y
	left.CanvasSize = UDim2.new()
	left.Parent = sg
	Kit.list(left, 10)
	armyPanel(left, ctx, 1)
	provincePanel(left, ctx, 2)
	left.Active = #left:GetChildren() > 1
	if (diplomacyOpen or objectivesOpen) and view then
		local right = Instance.new("Frame") :: Frame
		right.Size = UDim2.new(0, 380, 0, 0)
		right.Position = UDim2.new(1, -12, 0, 72)
		right.AnchorPoint = Vector2.new(1, 0)
		right.AutomaticSize = Enum.AutomaticSize.Y
		right.BackgroundTransparency = 1
		right.Parent = sg
		Kit.list(right, 8)
		if objectivesOpen then
			local op = panel(right, 0)
			Kit.title(op, "Objectives", { size = UDim2.new(1, 0, 0, 28), textSize = 24, rule = true }).LayoutOrder = 0
			for i, o in view.objectives or {} do
				text(op, (if o.done then "■  " else "□  ") .. tostring(o.text), i, { textSize = 15, font = Enum.Font.Garamond, colour = if o.done then Kit.GILT_BRIGHT else Kit.IVORY })
			end
		end
		if diplomacyOpen then
			diplomacy(right, ctx)
		end
	end
	-- one document at a time, most pressing first
	local ev = nil
	for _, e in (if view then view.events else nil) or {} do
		if not dismissed[e.id] then
			ev = e
			break
		end
	end
	if view and view.victory then
		if pickerReason then
			pickerDoc(sg, pickerReason)
		else
			victoryDoc(sg, ctx, view.victory)
		end
	elseif pickerReason then
		pickerDoc(sg, pickerReason)
	elseif view and view.pendingBattle then
		battleDoc(sg, ctx, view.pendingBattle)
	elseif ev then
		eventDoc(sg, ev)
	elseif summary then
		summaryDoc(sg, summary)
	end
	if toastLabel then
		toastLabel.Parent = nil
		toastLabel.Parent = sg -- stays on top
	end
end

function UI.showPicker(reason: string)
	pickerReason = reason
end

function UI.showSummary(title: string, lines: { string })
	summary = { title = title, lines = lines }
end

-- Closes the topmost dismissible thing; false when nothing was open.
function UI.escape(): boolean
	if summary then
		summary = nil
		return true
	elseif diplomacyOpen or objectivesOpen then
		diplomacyOpen, objectivesOpen = false, false
		return true
	end
	return false
end

function UI.toast(reason: string)
	local sg = gui
	if not sg then
		return
	end
	local t = toastLabel
	if not t then
		local l = Kit.label(sg, "", { size = UDim2.new(0, 520, 0, 30), position = UDim2.new(0.5, 0, 1, -48), anchor = Vector2.new(0.5, 0), textSize = 15, align = Enum.TextXAlignment.Center, colour = Kit.IVORY })
		l.BackgroundColor3 = Kit.INSET
		l.BackgroundTransparency = 0.1
		local s = Instance.new("UIStroke") :: UIStroke
		s.Color = Kit.CRIMSON_LIGHT
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = l
		toastLabel = l
		t = l
	end
	local label = t :: TextLabel
	local msg = Logic.reason(reason)
	label.Text = msg
	label.Visible = true
	task.delay(4, function()
		if toastLabel == label and label.Text == msg then
			label.Visible = false
		end
	end)
end

function UI.destroy()
	if gui then
		gui:Destroy()
	end
	gui, cb, toastLabel, summary, pickerReason, splitArmy = nil, nil, nil, nil, nil, nil
	diplomacyOpen, objectivesOpen = false, false
	table.clear(split)
	table.clear(dismissed)
	Kit.hideTooltip()
end

return UI
