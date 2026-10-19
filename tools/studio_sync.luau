-- Pulls every script from the repo into the place open in Studio (Edit mode), like a one-shot
-- Rojo sync. Run `python3 tools/build_place.py` (writes build/sync.json) and
-- `python3 -m http.server 8765 --bind 127.0.0.1` in the repo root, then execute this file's text
-- in Studio (MCP execute_luau, Edit). Scripts no longer in the repo are removed. Returns a summary.
local HS = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8765/"
local wasEnabled = HS.HttpEnabled
HS.HttpEnabled = true
local ok, result = pcall(function()
	local entries = HS:JSONDecode(HS:GetAsync(BASE .. "build/sync.json", true))
	local wanted: { [Instance]: boolean } = {}
	local roots: { Instance } = {}
	local made, updated = 0, 0
	local keys: { [string]: boolean } = {}
	for _, e in entries do
		keys[table.concat(e.path, "/")] = true
	end
	for _, e in entries do
		local node: Instance = game:GetService(e.path[1])
		for i = 2, #e.path do
			local name = e.path[i]
			local child = node:FindFirstChild(name)
			local cls = if i == #e.path then e.class else "Folder"
			if child and i == #e.path and child.ClassName ~= cls then
				-- class changed (e.g. a folder gained init.luau): replace it, keep its children
				local fresh = Instance.new(cls)
				fresh.Name = name
				for _, c in child:GetChildren() do
					c.Parent = fresh
				end
				child:Destroy()
				fresh.Parent = node
				child = fresh
			elseif not child then
				child = Instance.new(cls)
				child.Name = name
				child.Parent = node
				made += 1
			end
			node = child :: Instance
		end
		wanted[node] = true
		if not keys[table.concat(e.path, "/", 1, #e.path - 1)] then
			table.insert(roots, node) -- a mapped source root (EoE, EoEClient)
		end
		if e.file then
			local src = HS:GetAsync(BASE .. e.file, true)
			if (node :: any).Source ~= src then
				(node :: any).Source = src
				updated += 1
			end
		end
	end
	local removed = 0
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if not wanted[d] and d.Parent and (d:IsA("LuaSourceContainer") or d:IsA("Folder")) then
				d:Destroy()
				removed += 1
			end
		end
	end
	return string.format("%d entries: %d created, %d updated, %d removed", #entries, made, updated, removed)
end)
HS.HttpEnabled = wasEnabled
return if ok then result else "sync failed: " .. tostring(result)
