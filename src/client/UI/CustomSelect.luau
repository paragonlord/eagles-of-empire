--!strict
-- Custom battle: your nation and the enemy's, a field, a budget, and the regiments you buy from
-- the campaign's unit table (shared CustomBattle rules); the server builds the battle and the AI
-- buys its army for the same budget.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local EuropeData = require(Shared.EuropeData)
local CustomBattle = require(Shared.CustomBattle)
local Kit = require(script.Parent.Kit)

local CustomSelect = {}

export type Callbacks = {
	fight: (spec: CustomBattle.Spec) -> (),
	back: () -> (),
}

local MAP_NAMES: { [string]: string } = {
	jena = "Jena",
	auerstedt = "Auerstedt",
	austerlitz = "Austerlitz",
	waterloo = "Waterloo",
}

local gui: ScreenGui? = nil
local spec: CustomBattle.Spec = { player = "france", enemy = "austria", map = "jena", budget = 8000, units = {} }

local function mapName(id: string): string
	local prov = string.match(id, "^province:(.+)$")
	local p = prov and EuropeData.province(prov)
	return MAP_NAMES[id] or (if p then p.name else id)
end

local function count(): number
	local n = 0
	for _, v in spec.units do
		n += v
	end
	return n
end

local render: (cb: Callbacks) -> ()

local function choiceRow(parent: Instance, y: number, label: string, items: { any }, current: any, text: (any) -> string, pick: (any) -> (), width: number)
	Kit.label(parent, label, { size = UDim2.fromOffset(90, 28), position = UDim2.fromOffset(0, y), textSize = 15, colour = Kit.MUTED })
	local row = Instance.new("Frame") :: Frame
	row.Size = UDim2.new(1, -96, 0, 28)
	row.Position = UDim2.fromOffset(96, y)
	row.BackgroundTransparency = 1
	row.Parent = parent
	Kit.list(row, 5, true)
	for i, item in items do
		local b = Kit.button(row, text(item), function()
			pick(item)
		end, { size = UDim2.fromOffset(width, 28), order = i, textSize = 13, caps = false })
		Kit.setActiveLook(b, item == current)
	end
end

render = function(cb: Callbacks)
	if gui then
		gui:Destroy()
	end
	local sg = Kit.screen("EoECustomSelect", 31)
	gui = sg
	local panel = Kit.panel(sg, { size = UDim2.fromOffset(720, 640), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), padding = 20 })
	Kit.fit(panel, 720, 640)
	Kit.title(panel, "Custom battle", { size = UDim2.new(1, -130, 0, 34), textSize = 28, spaced = true, colour = Kit.GILT, rule = true })
	Kit.button(panel, "Back (Esc)", cb.back, { size = UDim2.fromOffset(110, 28), position = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0) })
	local function nationName(id: any): string
		return EuropeData.Nations[id].adjective
	end
	choiceRow(panel, 46, "You", CustomBattle.Nations, spec.player, nationName, function(n: any)
		spec.player = n
		if spec.enemy == n then
			spec.enemy = if n == "france" then "austria" else "france"
		end
		-- national regiments of the old nation do not carry over
		for t in spec.units do
			if not EuropeData.inRoster(t, n) then
				spec.units[t] = nil
			end
		end
		render(cb)
	end, 110)
	choiceRow(panel, 80, "Enemy", CustomBattle.Nations, spec.enemy, nationName, function(n: any)
		if n ~= spec.player then
			spec.enemy = n
			render(cb)
		end
	end, 110)
	choiceRow(panel, 114, "Field", { table.unpack(CustomBattle.Maps, 1, 4) }, spec.map, mapName, function(m: any)
		spec.map = m
		render(cb)
	end, 110)
	choiceRow(panel, 146, "", { table.unpack(CustomBattle.Maps, 5) }, spec.map, mapName, function(m: any)
		spec.map = m
		render(cb)
	end, 110)
	choiceRow(panel, 180, "Budget", CustomBattle.Budgets, spec.budget, function(b: any): string
		return tostring(b) .. " gold"
	end, function(b: any)
		spec.budget = b
		render(cb)
	end, 110)
	-- the regiments
	local spent = CustomBattle.cost(spec.units)
	local n = count()
	local over = spent > spec.budget
	Kit.label(panel, string.format("Spent %d of %d gold · %d of %d regiments", spent, spec.budget, n, CustomBattle.MAX_UNITS), { size = UDim2.new(1, 0, 0, 24), position = UDim2.fromOffset(0, 218), textSize = 15, colour = if over then Kit.HOSTILE else Kit.IVORY })
	local scroll = Instance.new("ScrollingFrame") :: ScrollingFrame
	scroll.Size = UDim2.new(1, 0, 1, -300)
	scroll.Position = UDim2.fromOffset(0, 248)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Kit.GILT
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = panel
	Kit.list(scroll, 4)
	local order = 0
	for _, t in EuropeData.UnitTypeOrder do
		local c = EuropeData.UnitClasses[t]
		if EuropeData.inRoster(t, spec.player) then
			order += 1
			local row = Instance.new("Frame") :: Frame
			row.Size = UDim2.new(1, -10, 0, 28)
			row.BackgroundTransparency = 1
			row.LayoutOrder = order
			row.Parent = scroll
			local have = spec.units[t] or 0
			Kit.label(row, string.format("%s · %d gold · %d men", c.name, c.cost, c.strength), { size = UDim2.new(1, -150, 1, 0), textSize = 14, caps = false })
			local minus = Kit.button(row, "−", function()
				spec.units[t] = if have > 1 then have - 1 else nil
				render(cb)
			end, { size = UDim2.fromOffset(36, 26), position = UDim2.new(1, -140, 0, 1), textSize = 16 })
			Kit.setEnabled(minus, have > 0, "None bought")
			Kit.label(row, tostring(have), { size = UDim2.fromOffset(50, 28), position = UDim2.new(1, -100, 0, 0), textSize = 16, align = Enum.TextXAlignment.Center })
			local plus = Kit.button(row, "+", function()
				spec.units[t] = have + 1
				render(cb)
			end, { size = UDim2.fromOffset(36, 26), position = UDim2.new(1, -46, 0, 1), textSize = 16 })
			Kit.setEnabled(plus, n < CustomBattle.MAX_UNITS and spent + c.cost <= spec.budget, if n >= CustomBattle.MAX_UNITS then "An army of twenty regiments at most" else "Over budget")
		end
	end
	local fight = Kit.button(panel, "Fight", function()
		cb.fight(spec)
	end, { size = UDim2.fromOffset(140, 40), position = UDim2.new(1, 0, 1, 0), anchor = Vector2.new(1, 1), primary = true, textSize = 18 })
	Kit.setEnabled(fight, n > 0 and not over, if n == 0 then "Buy at least one regiment" else "Over budget")
end

function CustomSelect.show(cb: Callbacks)
	render(cb)
end

function CustomSelect.isOpen(): boolean
	return gui ~= nil
end

function CustomSelect.hide()
	if gui then
		gui:Destroy()
		gui = nil
	end
end

return CustomSelect
