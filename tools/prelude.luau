-- Test-harness prelude: a minimal fake of the Roblox instance tree so modules written with
-- `require(script.Parent.X)` / `game:GetService(...)` load in the plain Luau CLI.
-- Not a Roblox emulator: no datatypes, no physics, no rendering. Sim code must not need them.
-- Injected by tools/test.py ahead of the bundled sources; SOURCES is defined by the bundle.

local SOURCES = __SOURCES__ -- { [path] = source }

local Node = {}
Node.__index = function(self, key)
	local v = rawget(Node, key)
	if v ~= nil then
		return v
	end
	local children = rawget(self, "_children")
	local child = children[key]
	if child then
		return child
	end
	error(string.format("%s is not a valid member of %s %q", tostring(key), rawget(self, "ClassName"), rawget(self, "Name")), 2)
end

local function newNode(name, className, parent, path)
	local n = setmetatable({ Name = name, ClassName = className, Parent = parent, _children = {}, _path = path }, Node)
	if parent then
		parent._children[name] = n
	end
	return n
end

function Node.WaitForChild(self, name)
	local c = self._children[name]
	if not c then
		error("WaitForChild: no child " .. tostring(name) .. " under " .. self.Name)
	end
	return c
end

function Node.FindFirstChild(self, name)
	return self._children[name]
end

function Node.GetChildren(self)
	local out = {}
	for _, c in self._children do
		out[#out + 1] = c
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

function Node.IsA(self, className)
	return self.ClassName == className
end

function Node.GetFullName(self)
	if self.Parent and self.Parent.Name ~= "game" then
		return self.Parent:GetFullName() .. "." .. self.Name
	end
	return self.Name
end

local game = newNode("game", "DataModel", nil, nil)
local services = {}
local function service(name)
	if not services[name] then
		services[name] = newNode(name, name, game, nil)
	end
	return services[name]
end
service("ReplicatedStorage")
service("ServerScriptService")
service("ServerStorage")
service("StarterPlayer")
service("Players")
service("Workspace")
service("Lighting")

local RunService = service("RunService")
RunService.IsServer = function()
	return true
end
RunService.IsClient = function()
	return false
end
RunService.IsStudio = function()
	return false
end
RunService.Heartbeat = { Connect = function()
	return { Disconnect = function() end }
end }

function game.GetService(_, name)
	return service(name)
end

-- Mount sources into the tree. Keys look like "ReplicatedStorage/EoE/Config".
local function mount(path, src)
	local parts = string.split(path, "/")
	local node = game
	for i = 1, #parts - 1 do
		local part = parts[i]
		node = node._children[part] or newNode(part, "Folder", node, nil)
	end
	local leaf = parts[#parts]
	local className = "ModuleScript"
	if string.sub(leaf, -7) == ".server" then
		className = "Script"
		leaf = string.sub(leaf, 1, -8)
	elseif string.sub(leaf, -7) == ".client" then
		className = "LocalScript"
		leaf = string.sub(leaf, 1, -8)
	end
	if leaf == "init" then
		node.ClassName = className
		node._path = path
		node._source = src
	else
		local n = node._children[leaf]
		if n then
			n.ClassName = className
			n._path = path
			n._source = src
		else
			n = newNode(leaf, className, node, path)
			n._source = src
		end
	end
end

for path, src in SOURCES do
	mount(path, src)
end

local cache = {}
local loading = {}
local ENV -- module environment, assigned below (forward-declared so requireNode sees it)

local function requireNode(node)
	if type(node) == "string" then
		local parts = string.split(node, "/")
		local n = game
		for _, p in parts do
			n = n._children[p] or error("no module " .. node)
		end
		node = n
	end
	local path = rawget(node, "_path")
	if not path or not rawget(node, "_source") then
		error("require: " .. tostring(rawget(node, "Name")) .. " is not a module")
	end
	if cache[path] ~= nil then
		return cache[path]
	end
	if loading[path] then
		error("circular require: " .. path)
	end
	loading[path] = true
	local fn, err = loadstring(node._source, "=" .. path)
	if not fn then
		error("compile error in " .. path .. ": " .. tostring(err))
	end
	local env = setmetatable({ script = node }, { __index = ENV })
	setfenv(fn, env)
	local result = fn()
	loading[path] = nil
	if result == nil then
		error("module did not return a value: " .. path)
	end
	cache[path] = result
	return result
end

-- The CLI's global table is read-only, so modules run in ENV, which shadows globals.
ENV = setmetatable({}, { __index = _G })
ENV.require = requireNode
ENV.game = game
ENV.workspace = service("Workspace")
ENV.warn = warn or function(...)
	print("[warn]", ...)
end
ENV.task = {
	wait = function(t)
		return t or 0
	end,
	spawn = function(f, ...)
		return f(...)
	end,
	defer = function(f, ...)
		return f(...)
	end,
	delay = function(_, f, ...)
		return f(...)
	end,
	cancel = function() end,
}
ENV.tick = tick or os.clock
ENV.settings = function()
	return { Rendering = { QualityLevel = 10 } }
end
ENV.typeof = typeof or type

-- Test API --------------------------------------------------------------------------------
local tests = {}
ENV.test = function(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end
ENV.assertEq = function(a, b, msg)
	if a ~= b then
		error(string.format("%s: expected %s, got %s", msg or "assertEq", tostring(b), tostring(a)), 2)
	end
end
ENV.assertNear = function(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-6) then
		error(string.format("%s: expected %s ± %s, got %s", msg or "assertNear", tostring(b), tostring(eps or 1e-6), tostring(a)), 2)
	end
end
ENV.assertTrue = function(v, msg)
	if not v then
		error(msg or "assertTrue failed", 2)
	end
end

local function runTests()
	local specs = {}
	for path in SOURCES do
		if string.sub(path, 1, 6) == "Tests/" then
			specs[#specs + 1] = path
		end
	end
	table.sort(specs)
	local failures = 0
	local passed = 0
	local filter = __FILTER__
	for _, path in specs do
		tests = {}
		local ok, err = pcall(function()
			local fn = assert(loadstring(SOURCES[path], "=" .. path))
			setfenv(fn, setmetatable({ script = newNode(path, "ModuleScript", nil, path) }, { __index = ENV }))
			fn()
		end)
		if not ok then
			failures += 1
			print("FAIL (load) " .. path .. ": " .. tostring(err))
		end
		for _, t in tests do
			local slow = string.sub(t.name, 1, 6) == "[slow]"
			if (not filter and not slow) or (filter and (string.find(t.name, filter, 1, true) or string.find(path, filter, 1, true))) then
				local t0 = os.clock()
				local okT, errT = xpcall(t.fn, debug.traceback)
				local dt = os.clock() - t0
				if okT then
					passed += 1
					print(string.format("ok   %-60s %6.0f ms", t.name, dt * 1000))
				else
					failures += 1
					print(string.format("FAIL %s\n%s", t.name, tostring(errT)))
				end
			end
		end
	end
	print(string.format("\n%d passed, %d failed", passed, failures))
	if failures > 0 then
		error("tests failed")
	end
end

runTests()
