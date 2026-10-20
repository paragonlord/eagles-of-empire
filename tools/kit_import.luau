-- Turns a model made by Studio's mesh generator (segmented: torso, head, headgear, left arm,
-- right arm, left leg, right leg, musket ...) into an Assets.kits entry: prints Luau to paste
-- into src/shared/Assets.luau. Execute in Studio (MCP execute_luau, Edit) with the two lines
-- below set. The figure frame is the one Soldiers uses: +X forward, +Y up, +Z right, origin on
-- the ground between the feet, HEIGHT studs tall.
local MODEL = "Spike3" -- the generated model's name in Workspace
local HEIGHT = 3.2 -- infantry with headgear; 3.9 for horse and rider

local NAMES = { torso = "torso", head = "head", headgear = "headgear", ["left arm"] = "armL", ["right arm"] = "armR", ["left leg"] = "legL", ["right leg"] = "legR", musket = "musket", ["horse body with saddle and tail"] = "body", ["horse head and neck"] = "neck", rider = "rider", ["rider headgear"] = "riderHead", ["front left leg"] = "legFL", ["front right leg"] = "legFR", ["back left leg"] = "legBL", ["back right leg"] = "legBR" }

local model = workspace:FindFirstChild(MODEL) :: Model
assert(model, "no model " .. MODEL)
local parts: { [string]: MeshPart } = {}
for _, d in model:GetDescendants() do
	if d:IsA("MeshPart") then
		local raw = string.lower((string.gsub(d.Name, '[%[%]"\\]', "")))
		raw = (string.gsub(raw, "_geom$", ""))
		local key = NAMES[raw]
		assert(key, "unknown piece " .. raw)
		parts[key] = d
	end
end
local box, size = model:GetBoundingBox()
local bottom = box.Position.Y - size.Y / 2
local s = HEIGHT / size.Y
local up = Vector3.yAxis
-- The generator authors a figure facing its pieces' -Z (LookVector) and turns the whole model
-- toward the Studio camera, so the facing is read from a piece, not guessed.
local look = (parts.torso or parts.body).CFrame.LookVector
local fwd = Vector3.new(look.X, 0, look.Z).Unit
local mid: Vector3
if parts.legL and parts.legR then
	mid = (parts.legL.Position + parts.legR.Position) / 2
else -- a horse stands between its four legs
	mid = (parts.legFL.Position + parts.legFR.Position + parts.legBL.Position + parts.legBR.Position) / 4
end
local frame = CFrame.fromMatrix(Vector3.new(mid.X, bottom, mid.Z), fwd, up, fwd:Cross(up))

local function n(v: number): string
	return string.format("%.3f", v)
end
local lines = {}
local order = { "torso", "head", "headgear", "armL", "armR", "legL", "legR", "musket", "body", "neck", "rider", "riderHead", "legFL", "legFR", "legBL", "legBR" }
for _, key in order do
	local p = parts[key]
	if p then
		local rel = frame:ToObjectSpace(p.CFrame)
		local rx, ry, rz = rel:ToEulerAnglesXYZ()
		local pos = rel.Position * s
		local ms = p.MeshSize
		table.insert(lines, string.format(
			'\t\t%s = { mesh = "%s", texture = "%s", size = { %s, %s, %s }, scale = { %s, %s, %s }, cf = { %s, %s, %s, %s, %s, %s } },',
			key, p.MeshId, p.TextureID,
			n(p.Size.X * s), n(p.Size.Y * s), n(p.Size.Z * s),
			n(p.Size.X * s / ms.X), n(p.Size.Y * s / ms.Y), n(p.Size.Z * s / ms.Z),
			n(pos.X), n(pos.Y), n(pos.Z), n(rx), n(ry), n(rz)
		))
	end
end
return table.concat(lines, "\n")
