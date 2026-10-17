--!strict
-- Map edges as a faction's "home" (where routers flee, where rallied units turn back from).
-- A home is one of four sides, chosen as the side facing away from the enemy's deployment.
-- Edges are identified from the home point, which always lies just beyond its edge.

export type Side = "n" | "s" | "e" | "w"
export type Point = { x: number, z: number }

local Edges = {}

-- Side of a point lying beyond the map rectangle 0..w × 0..d (+z is north).
function Edges.sideOf(p: Point, w: number, d: number): Side
	if p.x < 0 then
		return "w"
	elseif p.x > w then
		return "e"
	elseif p.z > d then
		return "n"
	end
	return "s"
end

-- Unit vector pointing from the edge into the map.
function Edges.inward(side: Side): Point
	if side == "w" then
		return { x = 1, z = 0 }
	elseif side == "e" then
		return { x = -1, z = 0 }
	elseif side == "n" then
		return { x = 0, z = -1 }
	end
	return { x = 0, z = 1 }
end

-- Distance from p to the edge.
function Edges.distance(side: Side, p: Point, w: number, d: number): number
	if side == "w" then
		return p.x
	elseif side == "e" then
		return w - p.x
	elseif side == "n" then
		return d - p.z
	end
	return p.z
end

-- Point `offset` studs inside the edge, keeping p's position along the edge (clamped by `pad`).
function Edges.inside(side: Side, p: Point, offset: number, w: number, d: number, pad: number): Point
	if side == "w" then
		return { x = offset, z = math.clamp(p.z, pad, d - pad) }
	elseif side == "e" then
		return { x = w - offset, z = math.clamp(p.z, pad, d - pad) }
	elseif side == "n" then
		return { x = math.clamp(p.x, pad, w - pad), z = d - offset }
	end
	return { x = math.clamp(p.x, pad, w - pad), z = offset }
end

-- Home point (beyond the edge by `margin`) for a deployment centre `own` facing an enemy centre.
function Edges.home(own: Point, enemy: Point?, w: number, d: number, margin: number): Point
	local dx, dz
	if enemy then
		dx, dz = own.x - enemy.x, own.z - enemy.z
	else
		dx, dz = own.x - w / 2, own.z - d / 2
	end
	-- Compare normalised by map size so a wide map does not always pick east/west.
	local nx, nz = dx / w, dz / d
	if math.abs(nx) > math.abs(nz) then
		return if nx < 0 then { x = -margin, z = own.z } else { x = w + margin, z = own.z }
	end
	return if nz < 0 then { x = own.x, z = -margin } else { x = own.x, z = d + margin }
end

return Edges
