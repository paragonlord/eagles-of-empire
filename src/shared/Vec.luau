--!strict
-- 2D vectors on the battlefield plane. Pure Luau; no Roblox datatypes.
-- Heading: radians, 0 along +x, increasing toward +z. right(f) = f rotated +90° (toward +z when f = +x).

export type Vec = { x: number, z: number }

local Vec = {}

function Vec.new(x: number, z: number): Vec
	return { x = x, z = z }
end

function Vec.add(a: Vec, b: Vec): Vec
	return { x = a.x + b.x, z = a.z + b.z }
end

function Vec.sub(a: Vec, b: Vec): Vec
	return { x = a.x - b.x, z = a.z - b.z }
end

function Vec.scale(a: Vec, s: number): Vec
	return { x = a.x * s, z = a.z * s }
end

function Vec.dot(a: Vec, b: Vec): number
	return a.x * b.x + a.z * b.z
end

function Vec.cross(a: Vec, b: Vec): number
	return a.x * b.z - a.z * b.x
end

function Vec.len2(a: Vec): number
	return a.x * a.x + a.z * a.z
end

function Vec.len(a: Vec): number
	return math.sqrt(a.x * a.x + a.z * a.z)
end

function Vec.dist(a: Vec, b: Vec): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

function Vec.dist2(a: Vec, b: Vec): number
	local dx, dz = a.x - b.x, a.z - b.z
	return dx * dx + dz * dz
end

function Vec.normalize(a: Vec): Vec
	local l = Vec.len(a)
	if l < 1e-9 then
		return { x = 1, z = 0 }
	end
	return { x = a.x / l, z = a.z / l }
end

function Vec.fromHeading(h: number): Vec
	return { x = math.cos(h), z = math.sin(h) }
end

function Vec.heading(a: Vec): number
	return math.atan2(a.z, a.x)
end

function Vec.right(f: Vec): Vec
	return { x = -f.z, z = f.x }
end

function Vec.rotate(a: Vec, ang: number): Vec
	local c, s = math.cos(ang), math.sin(ang)
	return { x = a.x * c - a.z * s, z = a.x * s + a.z * c }
end

function Vec.lerp(a: Vec, b: Vec, t: number): Vec
	return { x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t }
end

-- Smallest signed difference b - a wrapped to [-pi, pi].
function Vec.angleDiff(a: number, b: number): number
	local d = (b - a) % (2 * math.pi)
	if d > math.pi then
		d -= 2 * math.pi
	end
	return d
end

function Vec.wrapAngle(a: number): number
	local d = a % (2 * math.pi)
	if d > math.pi then
		d -= 2 * math.pi
	end
	return d
end

-- Signed angle of point p as seen from a formation at pos facing heading: 0 = dead ahead.
function Vec.bearing(pos: Vec, heading: number, p: Vec): number
	return Vec.angleDiff(heading, Vec.heading(Vec.sub(p, pos)))
end

-- Classify an attack arriving from `from` onto a formation at pos facing heading.
function Vec.attackSide(pos: Vec, heading: number, from: Vec): "front" | "flank" | "rear"
	local b = math.abs(Vec.bearing(pos, heading, from))
	if b <= math.pi / 4 then
		return "front"
	elseif b >= 3 * math.pi / 4 then
		return "rear"
	end
	return "flank"
end

function Vec.clamp(a: Vec, minX: number, minZ: number, maxX: number, maxZ: number): Vec
	return { x = math.clamp(a.x, minX, maxX), z = math.clamp(a.z, minZ, maxZ) }
end

function Vec.isFinite(a: any): boolean
	return type(a) == "table"
		and type(a.x) == "number"
		and type(a.z) == "number"
		and a.x == a.x
		and a.z == a.z
		and math.abs(a.x) ~= math.huge
		and math.abs(a.z) ~= math.huge
end

-- Distance from point p to segment ab.
function Vec.distToSegment(p: Vec, a: Vec, b: Vec): number
	local abx, abz = b.x - a.x, b.z - a.z
	local l2 = abx * abx + abz * abz
	if l2 < 1e-9 then
		return Vec.dist(p, a)
	end
	local t = ((p.x - a.x) * abx + (p.z - a.z) * abz) / l2
	t = math.clamp(t, 0, 1)
	local cx, cz = a.x + abx * t, a.z + abz * t
	local dx, dz = p.x - cx, p.z - cz
	return math.sqrt(dx * dx + dz * dz)
end

return Vec
