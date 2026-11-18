-- The far city outline (2026-11-18, owner: "beyond 450-700 studs there is nothing; the city should look
-- like it goes on"). Players only receive real buildings within the streaming radius (700 studs), so
-- each client draws a cheap backdrop past that from a coarse grid the server works out here once:
-- one CELL x CELL square per character, holding the tallest thing that stands there (buildings) or a
-- tree mass. client/Backdrop turns it into a few hundred plain blocks and tree balls around the player.
--
-- Encoding (one character per cell, row by row along +X, rows along +Z):
--   "."            empty (fields, water, roads)
--   ALPHA[1..31]   buildings, height = value * 4 studs
--   ALPHA[32..47]  trees, height = 12 + (value - 32) * 2 studs
-- Runs of 4 or more empty cells are written "~" + ALPHA[count] (count <= 63).
local Skyline = {}
Skyline.CELL = 128
Skyline.ALPHA = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_" -- 64 symbols, index 0..63

local ROW_FLOORS = { core = 4, urban = 3, suburb = 2, rural = 1.5 }
local PLACE_H = {
	mall = 46, hospital = 54, government = 34, university = 30, school = 26, museum = 22, stadium = 34, station = 24,
	bus = 18, hub = 22, market = 18, nightmarket = 14, dealer = 22, homestore = 26, police = 26,
}

function Skyline.compute(world, bounds)
	local CELL = Skyline.CELL
	local x0, z0 = bounds.minX, bounds.minZ
	local nx = math.ceil((bounds.maxX - bounds.minX) / CELL)
	local nz = math.ceil((bounds.maxZ - bounds.minZ) / CELL)
	local bld = table.create(nx * nz, 0)
	local tree = table.create(nx * nz, 0)
	local function idx(x: number, z: number): number?
		local cx, cz = math.floor((x - x0) / CELL), math.floor((z - z0) / CELL)
		if cx < 0 or cz < 0 or cx >= nx or cz >= nz then return nil end
		return cz * nx + cx + 1
	end
	local function building(x: number, z: number, h: number)
		local i = idx(x, z)
		if i and h > bld[i] then bld[i] = h end
	end
	local function trees(x: number, z: number, h: number)
		local i = idx(x, z)
		if i and h > tree[i] then tree[i] = h end
	end
	world.skyMark = { building = building, trees = trees } -- the infill passes add theirs (Builder)

	for _, lot in ipairs(world.lotList or {}) do
		local k, use = lot.kind, lot.use
		local h = 0
		if k == "row" then h = (ROW_FLOORS[use] or 2) * 10 + 4
		elseif k == "townhouse" then h = 24
		elseif k == "house" then h = (use == "core" or use == "urban") and 20 or 16
		elseif k == "apartment" then h = use == "core" and 48 or 38
		elseif k == "tower" then h = use == "core" and 120 or 80
		elseif k == "bigbox" then h = 26
		elseif k == "farm" then h = 14
		end
		if h > 0 then
			building(lot.x, lot.z, h)
			-- a wide lot covers its neighbours' cells too
			if lot.w > CELL * 0.7 then
				local rv = lot.base.RightVector
				building(lot.x + rv.X * lot.w * 0.35, lot.z + rv.Z * lot.w * 0.35, h)
				building(lot.x - rv.X * lot.w * 0.35, lot.z - rv.Z * lot.w * 0.35, h)
			end
		elseif k == "yard" and (use == "rural" or use == "suburb") then
			trees(lot.x, lot.z, 18)
		end
	end
	for _, p in pairs(world.pois) do
		if p.pos and PLACE_H[p.kind] then
			building(p.pos.X, p.pos.Z, PLACE_H[p.kind])
			local w, d = p.w or 0, p.d or 0
			if w > CELL or d > CELL then
				for _, o in ipairs({ { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
					building(p.pos.X + o[1] * w * 0.3, p.pos.Z + o[2] * d * 0.3, PLACE_H[p.kind] * 0.8)
				end
			end
		end
	end
	-- park trees
	for _, p in ipairs(world.map.features.parks) do
		local pts = p.pts
		local n = #pts // 2
		local cx, cz = 0, 0
		for i = 1, n do cx += pts[i * 2 - 1]; cz += pts[i * 2] end
		if n > 0 then trees(cx / n, cz / n, 22) end
		for i = 1, n do trees(pts[i * 2 - 1], pts[i * 2], 20) end
	end
	return function() -- call after the infill passes
		local A = Skyline.ALPHA
		local out = table.create(nx * nz)
		local zeros = 0
		local function flush()
			while zeros > 0 do
				if zeros >= 4 then
					local run = math.min(zeros, 63)
					table.insert(out, "~" .. string.sub(A, run + 1, run + 1))
					zeros -= run
				else
					table.insert(out, string.rep(".", zeros))
					zeros = 0
				end
			end
		end
		local nb, nt = 0, 0
		for i = 1, nx * nz do
			local b, t = bld[i], tree[i]
			local v = 0
			if b > 0 then
				v = math.clamp(math.floor(b / 4 + 0.5), 1, 31)
				nb += 1
			elseif t > 0 then
				v = 32 + math.clamp(math.floor((t - 12) / 2 + 0.5), 0, 15)
				nt += 1
			end
			if v == 0 then
				zeros += 1
			else
				flush()
				table.insert(out, string.sub(A, v + 1, v + 1))
			end
		end
		flush()
		world.skyline = { cell = CELL, x0 = x0, z0 = z0, nx = nx, nz = nz, data = table.concat(out) }
		world.skyMark = nil
		print(("[World] skyline %dx%d cells: %d with buildings, %d with trees, %d characters"):format(nx, nz, nb, nt, #world.skyline.data))
	end
end

return Skyline
