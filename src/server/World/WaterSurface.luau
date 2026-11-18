-- Lakes and ponds as Roblox terrain water (2026-11-19, owner: "น้ำในบึงมีคลื่นเคลื่อนไหว และสะท้อนแสงไฟ").
--
-- The Builder still lays the "Water" parts along each outline: they are now the dark lake bed (top at
-- 0.05) and keep the collisions and the raycasts (krathongs, ...). Terrain water fills the same outline
-- above them up to Game.WATER_Y, so the surface has moving waves and reflects the sky and the lamps
-- (client/Water adds the long reflections of lamps at night).
-- The ground tiles under a lake have their top at 0; the bed parts cover them, so the troughs of the waves
-- show dark water instead of grass (an Edit-mode test showed green specks without them).
-- Cells are 4 studs (the terrain grid); a cell is water when its centre is at least INSET inside the
-- outline, so the water stops under the stone rim instead of spilling onto the path.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage.Shared.Config.Game)

local WaterSurface = {}

local CELL = 4
local INSET = 1
local BAND = 48 -- rows written per WriteVoxels call
local WATER = Enum.Material.Water

function WaterSurface.setup()
	local T = Workspace.Terrain
	-- the greenish teal of Bueng Kaen Nakhon on a clear day; client/Water darkens it after sunset
	T.WaterColor = Color3.fromRGB(30, 88, 84)
	T.WaterTransparency = 0.05
	T.WaterReflectance = 0.85
	T.WaterWaveSize = 0.1
	T.WaterWaveSpeed = 7
end

-- x positions where the outline crosses the line z, sorted
local function crossings(pts, z: number): { number }
	local xs = {}
	local n = #pts // 2
	for i = 1, n do
		local j = i % n + 1
		local x1, z1, x2, z2 = pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2]
		if (z1 <= z and z2 > z) or (z2 <= z and z1 > z) then
			table.insert(xs, x1 + (z - z1) / (z2 - z1) * (x2 - x1))
		end
	end
	table.sort(xs)
	return xs
end

local function inside(xs: { number }, x: number): boolean
	local c = 0
	for _, v in ipairs(xs) do
		if v < x then c += 1 else break end
	end
	return c % 2 == 1
end

-- Fill one outline (flat x, z list) with water.
function WaterSurface.fill(pts)
	local n = #pts // 2
	if n < 3 then return end
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, n do
		minX = math.min(minX, pts[i * 2 - 1]); maxX = math.max(maxX, pts[i * 2 - 1])
		minZ = math.min(minZ, pts[i * 2]); maxZ = math.max(maxZ, pts[i * 2])
	end
	local x0, x1 = math.floor(minX / CELL) * CELL, math.ceil(maxX / CELL) * CELL
	local z0, z1 = math.floor(minZ / CELL) * CELL, math.ceil(maxZ / CELL) * CELL
	local nx = (x1 - x0) // CELL
	local top = math.clamp(Game.WATER_Y / CELL, 0, 1) -- the second layer (0..4) is this full
	local T = Workspace.Terrain
	local zb = z0
	while zb < z1 do
		local rows = math.min(BAND, (z1 - zb) // CELL)
		local region = Region3.new(Vector3.new(x0, -CELL, zb), Vector3.new(x1, CELL, zb + rows * CELL))
		-- start from what is there: the boxes of a lake mapped in pieces, or of a pond beside it, overlap
		local mats, occ = T:ReadVoxels(region, CELL)
		local any = false
		for k = 1, rows do
			local z = zb + (k - 0.5) * CELL
			local mid, lo, hi = crossings(pts, z), crossings(pts, z - INSET), crossings(pts, z + INSET)
			if #mid > 0 then
				for i = 1, nx do
					local x = x0 + (i - 0.5) * CELL
					if inside(mid, x) and inside(mid, x - INSET) and inside(mid, x + INSET) and inside(lo, x) and inside(hi, x) then
						mats[i][1][k], occ[i][1][k] = WATER, 1
						mats[i][2][k], occ[i][2][k] = WATER, top
						any = true
					end
				end
			end
		end
		if any then T:WriteVoxels(region, CELL, mats, occ) end
		zb += rows * CELL
		task.wait()
	end
end

return WaterSurface
