--!strict
-- Selected formation ids, control groups and the hovered formation. Pure state + signal.

local Signal = require(script.Parent.Signal)
local BattleState = require(script.Parent.BattleState)

local Selection = {}

local selected: { [number]: boolean } = {}
local groups: { [number]: { number } } = {}
local hovered: number? = nil

Selection.changed = Signal.new() -- fired after any selection change
Selection.hoverChanged = Signal.new()

local function fire()
	Selection.changed:Fire()
end

function Selection.ids(): { number }
	local out = {}
	for id in selected do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

function Selection.count(): number
	local n = 0
	for _ in selected do
		n += 1
	end
	return n
end

function Selection.isSelected(id: number): boolean
	return selected[id] == true
end

function Selection.set(ids: { number })
	table.clear(selected)
	for _, id in ids do
		selected[id] = true
	end
	fire()
end

function Selection.toggle(id: number)
	if selected[id] then
		selected[id] = nil
	else
		selected[id] = true
	end
	fire()
end

function Selection.add(ids: { number })
	for _, id in ids do
		selected[id] = true
	end
	fire()
end

function Selection.clear()
	if next(selected) == nil then
		return
	end
	table.clear(selected)
	fire()
end

-- Drops ids that no longer exist on our side (destroyed, exited, new match).
function Selection.prune()
	local changed = false
	for id in selected do
		local f = BattleState.formations[id]
		if not f or f.faction ~= BattleState.viewerFaction then
			selected[id] = nil
			changed = true
		end
	end
	if changed then
		fire()
	end
end

function Selection.first(): number?
	local ids = Selection.ids()
	return ids[1]
end

function Selection.assignGroup(n: number)
	groups[n] = Selection.ids()
end

function Selection.recallGroup(n: number)
	local g = groups[n]
	if g and #g > 0 then
		Selection.set(g)
	end
end

function Selection.setHovered(id: number?)
	if hovered ~= id then
		hovered = id
		Selection.hoverChanged:Fire(id)
	end
end

function Selection.hovered(): number?
	return hovered
end

function Selection.reset()
	table.clear(selected)
	table.clear(groups)
	hovered = nil
	fire()
end

return Selection
