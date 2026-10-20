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

-- Roblox datatypes (Vector3, CFrame, Color3, Enum) good enough for WorldGen's geometry: exact
-- arithmetic, no rendering. CFrame.Angles composes X, Y, Z like Roblox; lookAt looks down -Z.
local V3 = {}
V3.__index = V3
local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, V3)
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	return v3(a.X / b, a.Y / b, a.Z / b)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(a)
	return string.format("%g, %g, %g", a.X, a.Y, a.Z)
end
function V3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a, b, t)
	return a + (b - a) * t
end
local v3index = V3.__index
V3.__index = function(self, k)
	if k == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif k == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		return v3(self.X / m, self.Y / m, self.Z / m)
	end
	return v3index[k]
end
ENV.Vector3 = {
	new = function(x, y, z)
		return v3(x or 0, y or 0, z or 0)
	end,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

local CF = {}
local function cf(x, y, z, r)
	return setmetatable({ X = x, Y = y, Z = z, R = r }, CF)
end
local IDENT = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function fromAxes(pos, vx, vy, vz)
	return cf(pos.X, pos.Y, pos.Z, { vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z })
end
local function mulRot(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function rotVec(r, v)
	return v3(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then
		local p = rotVec(a.R, b)
		return v3(p.X + a.X, p.Y + a.Y, p.Z + a.Z)
	end
	local p = rotVec(a.R, v3(b.X, b.Y, b.Z))
	return cf(p.X + a.X, p.Y + a.Y, p.Z + a.Z, mulRot(a.R, b.R))
end
CF.__add = function(a, b)
	return cf(a.X + b.X, a.Y + b.Y, a.Z + b.Z, a.R)
end
CF.__sub = function(a, b)
	return cf(a.X - b.X, a.Y - b.Y, a.Z - b.Z, a.R)
end
CF.__index = function(self, k)
	if k == "Position" then
		return v3(self.X, self.Y, self.Z)
	elseif k == "LookVector" then
		local r = self.R
		return v3(-r[3], -r[6], -r[9])
	elseif k == "RightVector" or k == "XVector" then
		local r = self.R
		return v3(r[1], r[4], r[7])
	elseif k == "UpVector" or k == "YVector" then
		local r = self.R
		return v3(r[2], r[5], r[8])
	elseif k == "Rotation" then
		return cf(0, 0, 0, self.R)
	end
	return CF[k]
end
CF.__tostring = function(a)
	return string.format("%g, %g, %g, %s", a.X, a.Y, a.Z, table.concat(a.R, ", "))
end
function CF.GetComponents(self)
	local r = self.R
	return self.X, self.Y, self.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end
function CF.Inverse(self)
	local r = self.R
	local t = { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
	local p = rotVec(t, v3(self.X, self.Y, self.Z))
	return cf(-p.X, -p.Y, -p.Z, t)
end
function CF.PointToWorldSpace(self, v)
	return self * v
end
function CF.VectorToWorldSpace(self, v)
	return rotVec(self.R, v)
end
local function angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local X = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Y = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Z = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return cf(0, 0, 0, mulRot(mulRot(X, Y), Z))
end
ENV.CFrame = {
	new = function(x, y, z, ...)
		if x == nil then
			return cf(0, 0, 0, IDENT)
		elseif getmetatable(x) == V3 then
			return cf(x.X, x.Y, x.Z, IDENT)
		end
		local n = select("#", ...)
		if n == 9 then
			return cf(x, y, z, { ... })
		end
		return cf(x, y, z, IDENT)
	end,
	Angles = angles,
	fromEulerAnglesXYZ = angles,
	fromMatrix = function(pos, vx, vy, vz)
		return fromAxes(pos, vx, vy, vz or vx:Cross(vy))
	end,
	lookAt = function(from, to, up)
		up = up or v3(0, 1, 0)
		local f = (to - from).Unit
		local z = -f
		local x = up:Cross(z)
		if x.Magnitude < 1e-6 then
			x = v3(1, 0, 0)
		end
		x = x.Unit
		local y = z:Cross(x)
		return fromAxes(from, x, y, z)
	end,
	identity = cf(0, 0, 0, IDENT),
}

local C3 = {}
C3.__index = C3
local function c3(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, C3)
end
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3.__tostring = function(a)
	return string.format("%g, %g, %g", a.R, a.G, a.B)
end
function C3.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
ENV.Color3 = {
	new = function(r, g, b)
		return c3(r or 0, g or 0, b or 0)
	end,
	fromRGB = function(r, g, b)
		return c3(r / 255, g / 255, b / 255)
	end,
}

-- Enum.X.Y: one stable item per name, comparable by identity, printable by name.
local enumItem = { __tostring = function(e)
	return "Enum." .. e.EnumType .. "." .. e.Name
end }
ENV.Enum = setmetatable({}, { __index = function(enums, enumName)
	local items = setmetatable({}, { __index = function(t, name)
		local e = setmetatable({ Name = name, EnumType = enumName }, enumItem)
		rawset(t, name, e)
		return e
	end })
	rawset(enums, enumName, items)
	return items
end })

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
