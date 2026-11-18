-- Plans a province from its map data at 1:1 scale and draws it.
--
-- PLAN (the whole map, once, at start-up): the street network (real streets plus the lanes laid
-- out by tools/plan_streets.py), water, parks, railway, the authored landmark sites and land for
-- sale, and then every property: each street side is cut into lots whose depth reaches the middle
-- of the block, so a block is filled edge to edge (no building stands alone on open ground).
-- What a lot becomes follows the land use (core / urban / suburb / rural) and the class of its street.
--
-- DRAW: streets, water, parks and landmarks exist from the start; everything else (buildings,
-- walls, yards, fields, street furniture) is registered with the Streamer and drawn only near players.
--
-- Returns the registry the gameplay services work from.
-- opts.planOnly = true -> compute the registry without creating any scenery
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local S = require(script.Parent.Scenery)
local Places = require(script.Parent.Places)
local RoadGraph = require(ReplicatedStorage.Shared.RoadGraph)
local Traffic = require(ReplicatedStorage.Shared.Traffic)
local Housing = require(ReplicatedStorage.Shared.Config.Housing)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Life = require(script.Parent.StreetLife)
local VehicleFactory = require(script.Parent.VehicleFactory)
local Assets = require(script.Parent.Assets)
local Blocks = require(script.Parent.Blocks)
local Streamer = require(script.Parent.Streamer)
local RoadMarks = require(script.Parent.RoadMarks) -- 2026-11-18: zebras, stop lines, roundabout islands
local Lakeside = require(script.Parent.Lakeside) -- 2026-11-18: lakeside promenades (Bueng Kaen Nakhon ...)
local Skyline = require(script.Parent.Skyline) -- 2026-11-18: the far city outline the clients draw (client/Backdrop)
local WaterSurface = require(script.Parent.WaterSurface) -- 2026-11-19: terrain water with waves in every lake and pond

local M = Kit.M
local C = Kit.COLORS
local V3 = Vector3.new
local CF = CFrame.new
local rad = math.rad

local Builder = {}

local OCELL = 128 -- occupancy grid cell
local CHUNK = 384 -- streaming chunk
local GAP = 1.5 -- between the road (or its sidewalk) and a property line

-- Lot kinds: narrowest frontage, shallowest and deepest property.
local KIND = {
	row = { wMin = 15, dMin = 22, dMax = 46 },
	townhouse = { wMin = 17, dMin = 24, dMax = 46 },
	house = { wMin = 34, dMin = 24, dMax = 62 },
	apartment = { wMin = 50, dMin = 40, dMax = 66 },
	tower = { wMin = 56, dMin = 50, dMax = 74 },
	bigbox = { wMin = 96, dMin = 52, dMax = 84 },
	yard = { wMin = 12, dMin = 8, dMax = 50 },
	field = { wMin = 30, dMin = 16, dMax = 96 },
	farm = { wMin = 44, dMin = 38, dMax = 80 },
}

-- What gets built along a street: weights by land use and street class.
local PROGRAM = {
	core = {
		highway = { { "row", 62 }, { "tower", 16 }, { "apartment", 6 }, { "bigbox", 8 }, { "yard", 4 } },
		main = { { "row", 66 }, { "tower", 18 }, { "apartment", 8 }, { "yard", 4 } },
		street = { { "row", 76 }, { "apartment", 11 }, { "tower", 6 }, { "yard", 4 } },
		soi = { { "row", 42 }, { "townhouse", 30 }, { "apartment", 13 }, { "house", 9 }, { "yard", 3 } },
		lane = { { "townhouse", 52 }, { "row", 12 }, { "apartment", 11 }, { "house", 19 }, { "yard", 3 } },
	},
	urban = {
		highway = { { "bigbox", 30 }, { "row", 52 }, { "apartment", 6 }, { "tower", 3 }, { "yard", 5 } },
		main = { { "row", 70 }, { "apartment", 10 }, { "bigbox", 5 }, { "house", 6 }, { "yard", 5 } },
		street = { { "row", 62 }, { "apartment", 10 }, { "townhouse", 10 }, { "house", 10 }, { "yard", 4 } },
		soi = { { "townhouse", 32 }, { "house", 38 }, { "row", 14 }, { "apartment", 8 }, { "yard", 4 } },
		lane = { { "house", 52 }, { "townhouse", 33 }, { "apartment", 6 }, { "yard", 5 } },
	},
	suburb = {
		highway = { { "bigbox", 32 }, { "row", 30 }, { "house", 16 }, { "yard", 12 } },
		main = { { "row", 34 }, { "house", 44 }, { "apartment", 8 }, { "yard", 8 } },
		street = { { "row", 26 }, { "house", 52 }, { "apartment", 6 }, { "yard", 9 } },
		soi = { { "house", 76 }, { "townhouse", 9 }, { "yard", 8 } },
		lane = { { "house", 78 }, { "townhouse", 8 }, { "yard", 8 } },
	},
	rural = {
		highway = { { "field", 46 }, { "farm", 18 }, { "bigbox", 10 }, { "row", 12 }, { "yard", 14 } },
		main = { { "field", 48 }, { "farm", 24 }, { "row", 12 }, { "house", 8 }, { "yard", 8 } },
		street = { { "field", 50 }, { "farm", 26 }, { "row", 8 }, { "house", 8 }, { "yard", 8 } },
		soi = { { "field", 46 }, { "farm", 36 }, { "house", 12 }, { "yard", 6 } },
		lane = { { "field", 46 }, { "farm", 36 }, { "house", 12 }, { "yard", 6 } },
	},
}
for _, byClass in pairs(PROGRAM) do
	for _, list in pairs(byClass) do
		local total = 0
		for _, it in ipairs(list) do total += it[2] end
		list.total = total
	end
end

-- When the land is too narrow or too shallow for what was picked, build the next smaller thing
-- (an empty yard is the last resort, not the first).
local FALLBACK = { tower = "apartment", apartment = "townhouse", bigbox = "row", house = "townhouse", townhouse = "row", farm = "field" }

-- what a lot's back can look onto that people see from the other side (Blocks.backDress)
local VIEW = { water = true, promenade = true, lakeside = true, park = true, pier = true }

local ADDRESS_KIND = { row = "shop", townhouse = "house", house = "house", apartment = "house", tower = "office", bigbox = "office", farm = "house" }
local GROUND = {
	core = { Color3.fromRGB(170, 158, 138), M.Ground },
	urban = { Color3.fromRGB(170, 158, 138), M.Ground },
	suburb = { Color3.fromRGB(150, 150, 112), M.Grass },
	rural = { Color3.fromRGB(150, 156, 110), M.Grass },
}

function Builder.build(map, opts)
	opts = opts or {}
	local t0 = os.clock()
	Kit.setupMaterials()
	if not opts.planOnly then Assets.load() end -- yields while the mesh props download
	local planRng = Random.new(20261116) -- layout decisions only
	local graph = RoadGraph.new(map)
	local bounds = map.bounds
	local emitAll = not opts.planOnly
	local center = map.center
	local landUse = map.landUse

	local function vrng(x: number, z: number): Random -- visual randomness, stable per spot
		return Random.new(math.floor(x) * 7919 + math.floor(z) * 104729 + 17)
	end

	local root, fGround, fRoads, fPlaces
	if emitAll then
		local old = Workspace:FindFirstChild("Map")
		if old then old:Destroy() end
		root = Kit.folder(Workspace, "Map")
	else
		root = Instance.new("Folder") -- scratch: places still run to report their door/npc spots
	end
	fGround = Kit.folder(root, "Ground")
	fRoads = Kit.folder(root, "Roads")
	fPlaces = Kit.folder(root, "Places")
	for _, n in ipairs({ "NPCs", "Vehicles", "Interactions", "Plots", "Farms" }) do
		if not Workspace:FindFirstChild(n) then Kit.folder(Workspace, n) end
	end
	local stream = Streamer.new(root, CHUNK)
	local function emit(x: number, z: number, fn)
		if emitAll then stream:add(x, z, fn) end
	end

	local world = {
		map = map, graph = graph, stream = stream,
		pois = {}, addresses = {}, restaurants = {}, shops = {}, busStops = {}, plots = {}, farms = {},
	}

	-----------------------------------------------------------------------------------------------
	-- occupancy: oriented boxes in two grids. gridS = streets, water, parks, railway, sites;
	-- gridL = lots. A lot is probed against gridS for how deep its block is, then against gridL.
	-----------------------------------------------------------------------------------------------
	local gridS, gridL = {}, {}
	local function obb(cx, cz, ux, uz, hw, hd, kind)
		return { cx = cx, cz = cz, ux = ux, uz = uz, hw = hw, hd = hd, r = math.sqrt(hw * hw + hd * hd), kind = kind }
	end
	local function overlap(a, b): boolean
		local dx, dz = b.cx - a.cx, b.cz - a.cz
		if dx * dx + dz * dz > (a.r + b.r) ^ 2 then return false end
		-- separating axis test on both boxes' axes
		local x, z = a.ux, a.uz
		for i = 1, 4 do
			if i == 2 then x, z = -a.uz, a.ux elseif i == 3 then x, z = b.ux, b.uz elseif i == 4 then x, z = -b.uz, b.ux end
			local ra = a.hw * math.abs(a.ux * x + a.uz * z) + a.hd * math.abs(-a.uz * x + a.ux * z)
			local rb = b.hw * math.abs(b.ux * x + b.uz * z) + b.hd * math.abs(-b.uz * x + b.ux * z)
			if math.abs(dx * x + dz * z) > ra + rb then return false end
		end
		return true
	end
	local function cells(o)
		if o.cells then return o.cells end
		local out = {}
		for cx = math.floor((o.cx - o.r) / OCELL), math.floor((o.cx + o.r) / OCELL) do
			for cz = math.floor((o.cz - o.r) / OCELL), math.floor((o.cz + o.r) / OCELL) do
				table.insert(out, (cx + 2048) * 4096 + cz + 2048)
			end
		end
		o.cells = out
		return out
	end
	local function put(grid, o)
		for _, k in ipairs(cells(o)) do
			local list = grid[k]
			if not list then list = {}; grid[k] = list end
			table.insert(list, o)
		end
		return o
	end
	local function hit(grid, o)
		for _, k in ipairs(cells(o)) do
			local list = grid[k]
			if list then
				for _, other in ipairs(list) do
					if overlap(o, other) then return other end
				end
			end
		end
		return nil
	end
	local function inBounds(o): boolean
		return not (o.cx - o.r < bounds.minX + 4 or o.cx + o.r > bounds.maxX - 4 or o.cz - o.r < bounds.minZ + 4 or o.cz + o.r > bounds.maxZ - 4)
	end
	local function reserve(o) return put(gridS, o) end
	local function free(o): boolean
		return inBounds(o) and hit(gridS, o) == nil and hit(gridL, o) == nil
	end

	-- Lot beside edge `e` at distance `s` from node a, on side +1 / -1. Returns frame (front faces the road) and its box.
	local function lotAt(e, s: number, side: number, w: number, d: number, gap: number?)
		local nx, nz = -e.dz * side, e.dx * side
		local off = e.def.width / 2 + e.def.walk + (gap or GAP) + d / 2
		local px, pz = e.a.x + e.dx * s, e.a.z + e.dz * s
		local cx, cz = px + nx * off, pz + nz * off
		local c = V3(cx, 0, cz)
		local base = CFrame.lookAt(c, c - V3(nx, 0, nz))
		return base, obb(cx, cz, e.dx, e.dz, w / 2, d / 2, "lot"), cx, cz
	end

	-- Find free land beside a road near `at` (only for places that have no authored site yet).
	local function placeNear(at: Vector3, w: number, d: number, prefer: ((any) -> boolean)?)
		for _, searchR in ipairs({ 500, 1100, 2200, 4000 }) do
			local cands = {}
			for _, e in ipairs(graph:edgesNear(at, searchR)) do
				if not prefer or prefer(e) then
					local _, _, t, dd = RoadGraph.project(e, at.X, at.Z)
					if dd <= searchR * searchR then table.insert(cands, { e = e, t = t, d = dd }) end
				end
			end
			table.sort(cands, function(a, b) return a.d < b.d end)
			for i = 1, math.min(#cands, 40) do
				local c = cands[i]
				local e = c.e
				local s0 = c.t * e.len
				for k = 0, 10 do
					for _, sign in ipairs({ 1, -1 }) do
						local s = s0 + sign * k * 24
						if s >= 0 and s <= e.len and not (k == 0 and sign == -1) then
							for _, side in ipairs({ 1, -1 }) do
								local base, box = lotAt(e, s, side, w, d, 2)
								box.kind = "site"
								if free(box) then
									reserve(box)
									return base
								end
							end
						end
					end
				end
			end
		end
		return nil
	end
	-- An authored site (data/sites.json -> Config/Maps/<map>Data/Plan): the lot centre and its street front.
	local function siteBase(id: string, w: number, d: number): CFrame?
		local s = map.sites and map.sites[id]
		if not s then return nil end
		local c = V3(s.x, 0, s.z)
		reserve(obb(s.x, s.z, -s.lz, s.lx, w / 2, d / 2, "site"))
		return CFrame.lookAt(c, c + V3(s.lx, 0, s.lz))
	end

	-----------------------------------------------------------------------------------------------
	-- ground: packed earth under the town, grass under the countryside
	-----------------------------------------------------------------------------------------------
	if emitAll then
		local tile = 1000 -- (500 until the map became the whole tambon, 2026-11-18: ~1,000 tiles instead of ~4,000)
		local x0, x1, z0, z1 = bounds.minX - 300, bounds.maxX + 300, bounds.minZ - 300, bounds.maxZ + 300
		local nx, nz = math.ceil((x1 - x0) / tile), math.ceil((z1 - z0) / tile)
		local sx, sz = (x1 - x0) / nx, (z1 - z0) / nz
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				local gx, gz = x0 + sx * (i + 0.5), z0 + sz * (j + 0.5)
				local g = GROUND[landUse(math.clamp(gx, bounds.minX, bounds.maxX), math.clamp(gz, bounds.minZ, bounds.maxZ))]
				Kit.part(fGround, V3(sx, 8, sz), CF(gx, -4, gz), g[1], g[2], { name = "Ground", variant = g[2] == M.Grass and "GD_Grass" or nil })
			end
		end
		local lenX, lenZ = bounds.maxX - bounds.minX, bounds.maxZ - bounds.minZ
		local function wall(size, cf)
			local p = Kit.part(fGround, size, cf, C.grass, M.SmoothPlastic, { name = "Wall", transparency = 1 })
			p.CastShadow = false
		end
		-- walls longer than 2048 studs are split
		for k = 0, math.ceil(lenX / 2000) - 1 do
			local seg = lenX / math.ceil(lenX / 2000)
			wall(V3(seg, 90, 2), CF(bounds.minX + seg * (k + 0.5), 45, bounds.minZ))
			wall(V3(seg, 90, 2), CF(bounds.minX + seg * (k + 0.5), 45, bounds.maxZ))
		end
		for k = 0, math.ceil(lenZ / 2000) - 1 do
			local seg = lenZ / math.ceil(lenZ / 2000)
			wall(V3(2, 90, seg), CF(bounds.minX, 45, bounds.minZ + seg * (k + 0.5)))
			wall(V3(2, 90, seg), CF(bounds.maxX, 45, bounds.minZ + seg * (k + 0.5)))
		end
	end

	-----------------------------------------------------------------------------------------------
	-- roads
	-----------------------------------------------------------------------------------------------
	local ROAD_COL = { highway = Color3.fromRGB(150, 152, 156), main = Color3.fromRGB(156, 158, 162), street = Color3.fromRGB(164, 164, 166), soi = Color3.fromRGB(176, 174, 172), lane = Color3.fromRGB(184, 180, 176) }
	local ROAD_VARIANT = { highway = "GD_Asphalt", main = "GD_Asphalt", street = "GD_Asphalt", soi = "GD_AsphaltWorn", lane = "GD_AsphaltWorn" }
	local function half(e): number return e.def.width / 2 + e.def.walk end
	for _, n in ipairs(graph.nodes) do
		n.deg = #n.links
		local walk, walked = 0, 0
		for _, l in ipairs(n.links) do
			walk = math.max(walk, l.edge.def.walk)
			if l.edge.def.walk > 0 then walked += 1 end
		end
		n.walk = walk
		n.walked = walked
	end
	-- How far from each end a street's sidewalks and lots must stay clear of the other streets
	-- meeting there, for each side separately: a lane joining from the left opens a lane-wide gap
	-- in the left frontage only; the right side of the street carries on unbroken.
	--   e.sa / e.sb [side] = sidewalk,  e.pa / e.pb [side] = property line,  e.ta / e.tb = the larger (furniture)
	for _, e in ipairs(graph.edges) do
		for _, which in ipairs({ "a", "b" }) do
			local n = e[which]
			local sgn = which == "a" and 1 or -1
			local dx, dz = e.dx * sgn, e.dz * sgn
			local walkT = { [-1] = 0, [1] = 0 }
			local propT = { [-1] = 0, [1] = 0 }
			local lineT = 0
			for _, l in ipairs(n.links) do
				local o = l.edge
				if o ~= e then
					local osgn = o.a == n and 1 or -1
					local qx, qz = o.dx * osgn, o.dz * osgn
					local cos = dx * qx + dz * qz
					local sin = math.sqrt(math.max(0, 1 - cos * cos))
					if cos > -0.93 and (e.minor or not o.minor) then lineT = n.r + 2 end
					for side = -1, 1, 2 do
						local lat = qx * -e.dz * side + qz * e.dx * side -- > 0: the other street leaves on this side
						if lat > 0.08 then
							if cos > -0.93 then
								local need = math.max(2.5, (half(o) + half(e) * cos) / math.max(sin, 0.3) + 2.5)
								walkT[side] = math.max(walkT[side], need)
								propT[side] = math.max(propT[side], need)
							else
								-- a gentle bend: properties on the inside of the curve stop short of the corner
								local sinHalf = math.sqrt(math.max(0, (1 + cos) / 2))
								propT[side] = math.max(propT[side], (half(e) + 40) * sinHalf / math.max(math.sqrt(1 - sinHalf * sinHalf), 0.5) + 1)
							end
						end
					end
				end
			end
			local cap = e.len * 0.45
			for side = -1, 1, 2 do
				walkT[side] = math.min(walkT[side], cap)
				propT[side] = math.min(math.max(propT[side], walkT[side]), cap)
			end
			local t = math.max(walkT[-1], walkT[1])
			if which == "a" then e.sa, e.pa, e.ta, e.la = walkT, propT, t, lineT else e.sb, e.pb, e.tb, e.lb = walkT, propT, t, lineT end
		end
	end
	for _, e in ipairs(graph.edges) do
		local def = e.def
		local a, b = e.a, e.b
		local mid = V3((a.x + b.x) / 2, 0, (a.z + b.z) / 2)
		local cf = CFrame.lookAt(mid, V3(b.x, 0, b.z)) -- local Z along the road, X across
		if emitAll then
			Kit.part(fRoads, V3(def.width, 0.4, e.len), cf * CF(0, def.y - 0.2, 0), ROAD_COL[e.type], M.Asphalt, { name = "Road", variant = ROAD_VARIANT[e.type] }):AddTag("Road")
			if def.walk > 0 then
				-- cf's local +X is side +1 of the edge (RightVector = look x up = (-dz, dx))
				for _, s in ipairs({ -1, 1 }) do
					local ta, tb = e.sa[s], e.sb[s]
					local span = e.len - ta - tb
					if span > 4 then
						-- local -Z points at b, so a larger trim at b moves the strip toward a (+Z)
						Kit.part(fRoads, V3(def.walk, 0.5, span), cf * CF(s * (def.width / 2 + def.walk / 2), 0.25, (tb - ta) / 2), C.walk, M.Pavement, { name = "Walk" })
					end
				end
			end
			local lineSpan = e.len - e.la - e.lb
			if lineSpan > 12 then
				local shift = (e.lb - e.la) / 2
				if e.type == "main" or e.type == "street" then
					Kit.part(fRoads, V3(0.6, 0.05, lineSpan), cf * CF(0, def.y + 0.03, shift), e.oneway and C.line or C.lineYellow, M.SmoothPlastic, { decor = true, name = "Line" })
				elseif e.type == "highway" then
					for _, s in ipairs({ -1, 1 }) do
						Kit.part(fRoads, V3(0.5, 0.05, lineSpan), cf * CF(s * def.width / 6, def.y + 0.03, shift), C.line, M.SmoothPlastic, { decor = true, name = "Line" })
					end
				end
			end
		end
		e.box = reserve(obb(mid.X, mid.Z, e.dx, e.dz, e.len / 2 + 2, def.width / 2 + def.walk + 1, "road"))
	end
	if emitAll then
		for i, n in ipairs(graph.nodes) do
			local top = 0
			local col = ROAD_COL.lane
			local variant = ROAD_VARIANT.lane
			local best = 9
			for _, l in ipairs(n.links) do
				top = math.max(top, l.edge.def.y)
				if l.edge.def.id < best then best = l.edge.def.id; col = ROAD_COL[l.edge.type]; variant = ROAD_VARIANT[l.edge.type] end
			end
			Kit.cyl(fRoads, n.r * 2, 0.4, CF(n.x, top - 0.18, n.z), col, M.Asphalt, { name = "Junction", variant = variant }):AddTag("Road")
			if n.walked >= 3 then
				-- dropped-kerb apron fills the corners between sidewalks
				Kit.cyl(fRoads, (n.r + n.walk + 5) * 2, 0.3, CF(n.x, 0.02, n.z), Color3.fromRGB(170, 168, 160), M.Concrete, { name = "Apron" })
			end
			if i % 400 == 0 then task.wait() end
		end
	end
	task.wait()

	-----------------------------------------------------------------------------------------------
	-- authored sites first (landmarks and land for sale keep their place whatever else changes)
	-----------------------------------------------------------------------------------------------
	local placeJobs = {} -- built after water and parks exist
	local notMinor = function(e) return not e.minor end
	for _, p in ipairs(map.pois) do
		local poi = p
		local site = map.sites and map.sites[p.id]
		if site and (site.w ~= p.w or site.d ~= p.d) then
			poi = table.clone(p) -- the planner chose the size that fits the land (data/sites.json)
			poi.w, poi.d = site.w, site.d
		end
		local base = siteBase(poi.id, poi.w, poi.d)
		table.insert(placeJobs, { poi = poi, base = base })
	end
	for i = 1, map.gasStations do
		local id = "gas" .. i
		local poi = { id = id, kind = "gas", name = "Isan Fuel " .. i, thai = "ปั๊มน้ำมันอีสาน " .. i, w = map.gasSize.w, d = map.gasSize.d }
		local base = siteBase(id, poi.w, poi.d)
		if base then table.insert(placeJobs, { poi = poi, base = base }) else warn("[World] no site for " .. id .. " (add it to data/sites.json)") end
	end
	local plotJobs = {}
	for _, g in ipairs(map.plotGroups) do
		local tier = Housing.TIERS[g.tier]
		for i = 1, g.count do
			local id = g.tier:sub(1, 1):upper() .. i
			table.insert(plotJobs, { id = id, tier = g.tier, at = g.at, size = tier.size, base = siteBase("plot_" .. id, tier.size.X + 6, tier.size.Y + 6) })
		end
	end

	-----------------------------------------------------------------------------------------------
	-- water, parks, railway (real outlines)
	-----------------------------------------------------------------------------------------------
	local function scan(pts, step, fn)
		local n = #pts // 2
		local minZ, maxZ = math.huge, -math.huge
		for i = 1, n do
			local z = pts[i * 2]
			minZ = math.min(minZ, z); maxZ = math.max(maxZ, z)
		end
		local z = minZ + step / 2
		while z < maxZ do
			local xs = {}
			for i = 1, n do
				local j = i % n + 1
				local x1, z1, x2, z2 = pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2]
				if (z1 <= z and z2 > z) or (z2 <= z and z1 > z) then
					table.insert(xs, x1 + (z - z1) / (z2 - z1) * (x2 - x1))
				end
			end
			table.sort(xs)
			for k = 1, #xs - 1, 2 do fn(xs[k], xs[k + 1], z) end
			z += step
		end
	end
	local F = map.features
	world.water = {}
	local LAKE_BED = Color3.fromRGB(30, 62, 58)
	if emitAll then WaterSurface.setup() end
	for wi, w in ipairs(F.water) do
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for i = 1, #w.pts, 2 do
			minX = math.min(minX, w.pts[i]); maxX = math.max(maxX, w.pts[i])
			minZ = math.min(minZ, w.pts[i + 1]); maxZ = math.max(maxZ, w.pts[i + 1])
		end
		local big = (maxX - minX) > 900 or (maxZ - minZ) > 900
		local step = big and 30 or 20
		local wm = emitAll and Kit.model(fPlaces, big and "Lake" or ("Pond" .. wi)) or nil
		scan(w.pts, step, function(xa, xb, z)
			if xb - xa > 2 then
				reserve(obb((xa + xb) / 2, z, 1, 0, (xb - xa) / 2 + 3, step / 2 + 3, "water"))
				if wm then
					-- the dark lake bed under the terrain water (World/WaterSurface); still named "Water": it
					-- carries the collisions and the raycasts
					local len = xb - xa
					local pieces = math.ceil(len / 2000)
					for k = 0, pieces - 1 do
						Kit.part(wm, V3(len / pieces, 0.7, step + 0.4), CF(xa + len / pieces * (k + 0.5), -0.3, z), LAKE_BED, M.SmoothPlastic, { name = "Water" })
					end
				end
			end
		end)
		if wm then WaterSurface.fill(w.pts) end
		if big then
			world.lake = { x = (minX + maxX) / 2, z = (minZ + maxZ) / 2, minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
			if wm then
				-- stone rim with lamps along the real shoreline (not along the line that closes one piece of
				-- a lake mapped in several pieces: that runs across the water, World/Lakeside.isOpen)
				local n = #w.pts // 2
				local open = Lakeside.isOpen(w.pts)
				for i = 1, n do
					local j = i % n + 1
					local a = V3(w.pts[i * 2 - 1], 0, w.pts[i * 2])
					local b = V3(w.pts[j * 2 - 1], 0, w.pts[j * 2])
					local len = (b - a).Magnitude
					if len > 2 and not (open and i == n) then
						local cf = CFrame.lookAt((a + b) / 2, b)
						Kit.part(wm, V3(2.4, 1.5, len + 1), cf * CF(0, 0.75, 0), Color3.fromRGB(214, 208, 196), M.Concrete, { name = "Rim" })
						if i % 3 == 0 then
							local lamp = Kit.ball(wm, 1.5, cf * CF(0, 9, 0), Color3.fromRGB(255, 236, 190), M.SmoothPlastic, { decor = true })
							Kit.cyl(wm, 0.5, 8, cf * CF(0, 4.6, 0), C.metalDark, M.Metal, { decor = true })
							Kit.nightLight(lamp, 40, Color3.fromRGB(255, 220, 170), 1.6); Kit.nightGlow(lamp)
						end
					end
				end
				-- fountain jets in the middle (of a whole lake: a piece's middle can be dry land)
				for k = open and 2 or -1, 1 do
					Kit.cyl(wm, 3, 26, CF(world.lake.x + k * 60, 13, world.lake.z + k * 200), Color3.fromRGB(190, 225, 240), M.Glass, { decor = true, transparency = 0.45 })
				end
			end
		end
		table.insert(world.water, { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ })
	end
	-- land players can own wins over a park outline (2026-11-18: with the newer OSM park around Bueng Kaen
	-- Nakhon two lakeside plots fall inside it; plots never move)
	local plotBoxes = {}
	for id, s in pairs(map.sites or {}) do
		if string.sub(id, 1, 5) == "plot_" or id == "farm" or id == "hub" then
			table.insert(plotBoxes, obb(s.x, s.z, -s.lz, s.lx, s.w / 2 + 4, s.d / 2 + 4, "site"))
		end
	end
	local function onPlot(o): boolean
		for _, b in ipairs(plotBoxes) do
			if overlap(o, b) then return true end
		end
		return false
	end
	for pi, p in ipairs(F.parks) do
		local pm = emitAll and Kit.model(fPlaces, "Park" .. pi) or nil
		-- lawn in cells, so a road, the water or a landmark only takes out the cells it stands on
		scan(p.pts, 48, function(xa, xb, z)
			local n = math.max(1, math.floor((xb - xa) / 64 + 0.5))
			local cw = (xb - xa) / n
			local runStart, runEnd = nil, nil
			local function flush()
				if runStart and pm then
					Kit.part(pm, V3(runEnd - runStart, 0.3, 48.4), CF((runStart + runEnd) / 2, 0.08, z), C.leafLight, M.Grass, { name = "Lawn", decor = true, variant = "GD_Grass" })
				end
				runStart, runEnd = nil, nil
			end
			if xb - xa > 6 then
				for i = 0, n - 1 do
					local cx = xa + cw * (i + 0.5)
					local o = obb(cx, z, 1, 0, cw / 2, 24, "park")
					if inBounds(o) and hit(gridS, o) == nil and not onPlot(o) then
						if not runStart then runStart = cx - cw / 2 end
						runEnd = cx + cw / 2
						reserve(o)
						local trng = vrng(cx, z)
						if trng:NextNumber() < 0.75 then
							local tx, tz = cx + trng:NextNumber(-cw / 3, cw / 3), z + trng:NextNumber(-16, 16)
							local kind = ({ "rain", "small", "palm", "bush", "rain" })[trng:NextInteger(1, 5)]
							emit(tx, tz, function(parent) S.tree(parent, CF(tx, 0.2, tz), vrng(tx, tz), kind) end)
						end
					else
						flush()
					end
				end
				flush()
			end
		end)
	end
	for _, run in ipairs(F.rails) do
		for i = 1, #run - 3, 2 do
			local a, b = V3(run[i], 0, run[i + 1]), V3(run[i + 2], 0, run[i + 3])
			local len = (b - a).Magnitude
			if len > 2 then
				local midp = (a + b) / 2
				local dir = (b - a).Unit
				reserve(obb(midp.X, midp.Z, dir.X, dir.Z, len / 2 + 1, 9, "rail"))
				if emitAll then
					local cf = CFrame.lookAt(midp, b)
					Kit.part(fRoads, V3(13, 0.5, len + 1), cf * CF(0, 0.2, 0), Color3.fromRGB(120, 112, 104), M.Pebble, { name = "Ballast" })
					for _, s in ipairs({ -2.6, 2.6 }) do
						Kit.part(fRoads, V3(0.5, 0.4, len + 1), cf * CF(s, 0.6, 0), Color3.fromRGB(90, 80, 74), M.Metal, { name = "Rail", decor = true })
					end
				end
			end
		end
	end
	task.wait()

	-----------------------------------------------------------------------------------------------
	-- hand-designed places
	-----------------------------------------------------------------------------------------------
	local function buildPlace(poi, base)
		local m = Kit.model(fPlaces, poi.id)
		local out = {}
		local fn = Places[poi.kind]
		if fn then
			local ok, err = pcall(fn, m, base, poi, vrng(base.X, base.Z), out)
			if not ok then warn("[World] place " .. poi.id .. " failed: " .. tostring(err)) end
		end
		local entry = table.clone(poi)
		entry.base = base
		entry.pos = base.Position
		entry.door = out.door or (base * CF(0, 3, -poi.d / 2 - 3)).Position
		entry.npc = out.npc
		entry.extra = out.extra or {}
		entry.spawns = out.spawns
		entry.display = out.display
		entry.allotments = out.allotments
		entry.zone = map.zoneAt(base.X, base.Z).id
		world.pois[poi.id] = entry
		table.insert(world.addresses, { pos = V3(entry.door.X, 0, entry.door.Z), zone = entry.zone, kind = poi.kind, name = poi.name })
		return entry
	end
	for _, job in ipairs(placeJobs) do
		local poi, base = job.poi, job.base
		if not base then
			warn("[World] " .. poi.id .. " has no authored site (data/sites.json); searching for room")
			base = placeNear(poi.at, poi.w, poi.d, poi.w >= 100 and notMinor or nil) or placeNear(poi.at, poi.w, poi.d, nil)
		end
		if base then buildPlace(poi, base) else warn("[World] no room for " .. poi.id) end
	end
	if world.pois.farm and world.pois.farm.allotments then
		for _, a in ipairs(world.pois.farm.allotments) do table.insert(world.farms, a) end
	end
	-- land for sale
	for _, job in ipairs(plotJobs) do
		local base = job.base
		if not base then
			warn("[World] plot " .. job.id .. " has no authored site (data/sites.json); searching for room")
			base = placeNear(job.at, job.size.X + 6, job.size.Y + 6, function(e) return e.minor or e.type == "street" end)
		end
		if base then table.insert(world.plots, { id = job.id, tier = job.tier, base = base }) else warn("[World] no room for plot " .. job.id) end
	end
	task.wait()

	-- roundabout islands, zebra crossings at schools / hospitals / university gates, soi-mouth stop lines
	-- (World/RoadMarks, 2026-11-18); the islands are reserved here, before the lots are cut
	local ctx = {
		graph = graph, map = map, world = world, emit = emit, emitAll = emitAll, obb = obb, reserve = reserve, hit = hit,
		put = put, free = free, overlap = overlap, cells = cells, gridS = gridS, gridL = gridL, vrng = vrng, onPlot = onPlot,
		fRoads = fRoads, fPlaces = fPlaces, inBounds = inBounds,
	}
	RoadMarks.plan(ctx)
	Lakeside.plan(ctx)
	task.wait()

	-----------------------------------------------------------------------------------------------
	-- properties: every street side is cut into lots that reach the middle of the block
	-----------------------------------------------------------------------------------------------
	local lots = {}
	local hero2 = (map.heroRadius or 1400) ^ 2
	-- "hero" detail (pavement life, parked vehicles, kerb props, street-name signs): until 2026-11-18 only
	-- within heroRadius of the old downtown; now everywhere in town (core and urban land) across the tambon.
	-- It only costs anything where a player is: all of it is drawn by the Streamer.
	local function heroAt(x: number, z: number): boolean
		if (x - center.X) ^ 2 + (z - center.Z) ^ 2 < hero2 then return true end
		local u = landUse(x, z)
		return u == "core" or u == "urban"
	end
	local tPlan = os.clock()

	local function pick(list): string
		local r = planRng:NextNumber() * list.total
		for _, it in ipairs(list) do
			r -= it[2]
			if r <= 0 then return it[1] end
		end
		return list[1][1]
	end
	local function widthFor(kind: string, use: string): number
		if kind == "row" then return 15.5 * planRng:NextInteger(3, 6)
		elseif kind == "townhouse" then return 17 * planRng:NextInteger(2, 5)
		elseif kind == "house" then return use == "suburb" and planRng:NextNumber(48, 62) or planRng:NextNumber(40, 54)
		elseif kind == "apartment" then return planRng:NextNumber(60, 80)
		elseif kind == "tower" then return planRng:NextNumber(62, 76)
		elseif kind == "bigbox" then return planRng:NextNumber(110, 136)
		elseif kind == "yard" then return planRng:NextNumber(22, 44)
		elseif kind == "field" then return planRng:NextNumber(70, 110)
		end
		return planRng:NextNumber(56, 76)
	end
	local function boxFor(e, sMid: number, side: number, w: number, d: number)
		local nx, nz = -e.dz * side, e.dx * side
		local f = e.def.width / 2 + e.def.walk + GAP
		local fx, fz = e.a.x + e.dx * sMid + nx * f, e.a.z + e.dz * sMid + nz * f
		return obb(fx + nx * d / 2, fz + nz * d / 2, e.dx, e.dz, w / 2 - 0.05, d / 2, "lot"), fx, fz, nx, nz
	end
	-- How far box h is from a lot's front line, looking only at the part of h that lies within the
	-- lot's width (a lane crossing at an angle is close at one end of the lot and far at the other).
	-- (fx, fz) = middle of the front line, (ax, az) = unit vector along it, (nx, nz) = depth direction.
	local function depthTo(h, fx: number, fz: number, ax: number, az: number, nx: number, nz: number, hw: number): number
		local vx, vz = -h.uz, h.ux
		local lat, dep = table.create(4), table.create(4)
		local k = 0
		for sa = -1, 1, 2 do
			for sb = -1, 1, 2 do
				-- corner order (-,-) (-,+) (+,+) (+,-): walk round the box
				local b2 = (sa == -1) and sb or -sb
				local px, pz = h.cx + h.ux * h.hw * sa + vx * h.hd * b2 - fx, h.cz + h.uz * h.hw * sa + vz * h.hd * b2 - fz
				k += 1
				lat[k], dep[k] = px * ax + pz * az, px * nx + pz * nz
			end
		end
		local best = math.huge
		for i = 1, 4 do
			local j = i % 4 + 1
			local l1, d1, l2, d2 = lat[i], dep[i], lat[j], dep[j]
			if l1 > l2 then l1, d1, l2, d2 = l2, d2, l1, d1 end
			if l2 >= -hw and l1 <= hw then
				local span = l2 - l1
				local t1 = span > 1e-6 and math.max(0, (-hw - l1) / span) or 0
				local t2 = span > 1e-6 and math.min(1, (hw - l1) / span) or 1
				best = math.min(best, d1 + (d2 - d1) * t1, d1 + (d2 - d1) * t2)
			end
		end
		return best
	end
	-- How deep can a lot here be? Returns the depth and what stops it ("road", "water", "site", ...).
	local function probe(grid, e, sMid: number, side: number, w: number, cap: number): (number, string?)
		local b, fx, fz, nx, nz = boxFor(e, sMid, side, w, cap)
		local h = hit(grid, b)
		local edge = not inBounds(b)
		if not h and not edge then return cap, nil end
		local d = cap
		local kind = h and h.kind or "edge"
		for _ = 1, 5 do
			if h then
				d = math.min(d - 0.5, depthTo(h, fx, fz, e.dx, e.dz, nx, nz, w / 2) - 0.4)
				kind = h.kind
			else
				d -= 12
			end
			if d < 6 then return 0, kind end
			b = boxFor(e, sMid, side, w, d)
			h = hit(grid, b)
			edge = not inBounds(b)
			if not h and not edge then return d, kind end
		end
		return 0, kind
	end

	local order = table.clone(graph.edges)
	table.sort(order, function(a, b)
		if a.def.id ~= b.def.id then return a.def.id < b.def.id end -- bigger streets claim their corners first
		return a.id < b.id
	end)
	for ei, e in ipairs(order) do
		local def = e.def
		for _, side in ipairs({ -1, 1 }) do
			local s = e.pa[side] + 1.5
			local stop = e.len - e.pb[side] - 1.5
			local prevLot, prevEnd = nil, nil
			while stop - s >= 12 do
				local remaining = stop - s
				local mx = e.a.x + e.dx * (s + 20) - e.dz * side * (def.width / 2 + 30)
				local mz = e.a.z + e.dz * (s + 20) + e.dx * side * (def.width / 2 + 30)
				local use = landUse(mx, mz)
				local kind = pick(PROGRAM[use][e.type])
				if kind == "house" and map.zoneAt(mx, mz).id == "university" and planRng:NextNumber() < 0.65 then
					kind = "apartment" -- dormitories and student apartments instead of family houses
				end
				local K = KIND[kind]
				local w = math.min(widthFor(kind, use), remaining)
				if remaining - w < 30 then -- what is left after this lot could not hold a building: no slivers
					w = (remaining <= w * 1.45) and remaining or remaining / 2
				end
				local function fit(depth: number)
					while kind ~= "yard" and (depth < K.dMin or w < K.wMin) do
						kind = FALLBACK[kind] or "yard"
						K = KIND[kind]
					end
				end
				local sMid = s + w / 2
				local cap = 2 * K.dMax + 8
				local D, blocker = probe(gridS, e, sMid, side, w, cap)
				local dp
				if not blocker then
					dp = K.dMax
				elseif blocker == "road" and D >= 2 * 22 + 3 then
					dp = math.min(K.dMax, (D - 3) / 2) -- share the block with the lots on the street behind
				else
					dp = math.min(K.dMax, D - 0.6)
				end
				if blocker == "road" and not e.minor and (kind == "tower" or kind == "bigbox" or kind == "apartment") then
					-- big buildings on the main streets take the depth they need; the lane behind keeps a shallow row
					dp = math.min(K.dMax, math.max(dp, D - 27))
				end
				if dp < K.dMin and w >= 60 then
					-- beside a lane that meets this street at an angle the land is a wedge: a narrower lot reaches deeper
					w = w / 2
					sMid = s + w / 2
					D, blocker = probe(gridS, e, sMid, side, w, cap)
					dp = (not blocker) and K.dMax or ((blocker == "road" and D >= 47) and math.min(K.dMax, (D - 3) / 2) or math.min(K.dMax, D - 0.6))
				end
				fit(dp)
				dp = math.min(dp, K.dMax)
				local placed = false
				if dp >= K.dMin then
					-- lots already placed from another street (corners, shallow blocks)
					local D2 = probe(gridL, e, sMid, side, w, dp)
					if D2 < dp then
						dp = D2 - 0.4
						fit(dp)
						dp = math.min(dp, K.dMax)
					end
					if dp >= K.dMin then
						local base, box, cx, cz = lotAt(e, sMid, side, w, dp)
						box.hw -= 0.05
						put(gridL, box)
						local along = base.RightVector.X * e.dx + base.RightVector.Z * e.dz >= 0 and 1 or -1
						local lot = { base = base, x = cx, z = cz, w = w, dp = dp, kind = kind, edge = e, use = use, prev = -along, endWall = true }
						-- its back looks onto a lake or a park: dress the back (Blocks.backDress)
						lot.view = VIEW[blocker or ""] == true and D - dp < 40
						if prevLot and math.abs(prevEnd - s) < 0.01 then prevLot.endWall = false end
						prevLot, prevEnd = lot, s + w
						table.insert(lots, lot)
						s += w
						placed = true
					end
				end
				if not placed then s += 6 end
			end
		end
		if ei % 300 == 0 then task.wait() end
	end
	world.planLotsSeconds = os.clock() - tPlan
	-- the far outline every client draws past its streaming radius (World/Skyline -> client/Backdrop)
	world.lotList = lots
	local skyDone = Skyline.compute(world, bounds)
	local sky = world.skyMark

	-- partner shops on the terraces nearest real restaurant / shop positions
	local function pickSpread(kind: string, count: number, spacing: number)
		local out = {}
		for _, p in ipairs(F.pois) do
			if #out >= count then break end
			if p[1] == kind then
				local pos = V3(p[2], 0, p[3])
				local ok = true
				for _, q in ipairs(out) do
					if (q - pos).Magnitude < spacing then ok = false break end
				end
				if ok then table.insert(out, pos) end
			end
		end
		return out
	end
	local rowLots = {}
	for _, lot in ipairs(lots) do
		if lot.kind == "row" and lot.w >= 30 and not lot.edge.minor then table.insert(rowLots, lot) end
	end
	local function anchor(pos: Vector3, info)
		local best, bestD = nil, 700 * 700
		for _, lot in ipairs(rowLots) do
			if not lot.shop then
				local dd = (lot.x - pos.X) ^ 2 + (lot.z - pos.Z) ^ 2
				if dd < bestD then best, bestD = lot, dd end
			end
		end
		if best then best.shop = info end
		return best
	end
	local rn = map.restaurantNames
	for i, pos in ipairs(pickSpread("restaurant", map.restaurantCount, 620)) do
		local d = rn[(i - 1) % #rn + 1]
		anchor(pos, { id = "rest" .. i, kind = "restaurant", name = d[1], thai = d[2], menu = d[3], color = Color3.fromRGB(200, 70, 40) })
	end
	for i, pos in ipairs(pickSpread("convenience", map.convenienceCount, 900)) do
		anchor(pos, { id = "conv" .. i, kind = "convenience", name = "GoMart 24", thai = "โกมาร์ท 24", color = C.godash })
	end
	for i, pos in ipairs(pickSpread("cafe", map.cafeCount, 1200)) do
		anchor(pos, { id = "cafe" .. i, kind = "cafe", name = "Kaen Coffee", thai = "แก่นกาแฟ", color = Color3.fromRGB(120, 80, 50) })
	end

	local FLOORS = { core = { 3, 5 }, urban = { 2, 4 }, suburb = { 1, 3 }, rural = { 1, 2 } }
	local function drawLot(parent: Instance, lot)
		local rng = vrng(lot.x, lot.z)
		local base, w, dp = lot.base, lot.w, lot.dp
		local o = { prev = lot.prev, endWall = lot.endWall, use = lot.use, view = lot.view }
		local k = lot.kind
		if k == "row" then
			local shop = lot.shop
			local hero = lot.use == "core" or lot.use == "urban" or (lot.x - center.X) ^ 2 + (lot.z - center.Z) ^ 2 < hero2
			local detail = (hero or shop) and 2 or ((not lot.edge.minor) and 1 or 0)
			local fl = FLOORS[lot.use]
			o.shop, o.detail = shop, detail
			o.floors = rng:NextInteger(fl[1], lot.edge.minor and math.max(fl[1], fl[2] - 1) or fl[2])
			local bb = Blocks.shophouses(parent, base, w, dp, rng, o)
			local bd = math.min(34, dp)
			if detail == 2 then
				-- life on the pavement in front of each unit
				local units = math.max(1, math.floor(w / 15.5 + 0.5))
				local uw = w / units
				for u = 1, units do
					local ux = -w / 2 + uw * (u - 0.5)
					local front = bb * CF(ux, 0.3, -bd / 2 + 0.2)
					local r = rng:NextNumber()
					if shop and u == 1 then
						if shop.kind == "restaurant" then
							Life.diners(parent, Life.tableSet(parent, front * CF(uw * 0.9, 0, -1.6), rng), rng, 2)
							Life.pot(parent, front * CF(-uw / 2 + 1.6, 0, -0.6), rng)
						else
							Life.pot(parent, front * CF(uw / 2 - 1.4, 0, -0.6), rng)
						end
					elseif r < 0.22 then
						Life.pot(parent, front * CF(rng:NextNumber(-uw / 3, uw / 3), 0, -0.6), rng)
					elseif r < 0.3 then
						S.parkedBikes(parent, front * CF(0, 0, -1.2), rng:NextInteger(1, 3), rng)
					elseif r < 0.36 then
						Life.foodCart(parent, front * CF(0, 0.2, -2.2) * CFrame.Angles(0, rad(180), 0), rng, Life.CART_LABELS[rng:NextInteger(1, #Life.CART_LABELS)])
					elseif r < 0.42 then
						local seats = Life.tableSet(parent, front * CF(0, 0, -1.8), rng)
						if rng:NextNumber() < 0.4 then Life.diners(parent, seats, rng, rng:NextInteger(1, 2)) end
					elseif r < 0.47 then
						Life.bin(parent, front * CF(uw / 2 - 1.6, 0, -0.9), rng)
					end
				end
			elseif shop or rng:NextNumber() < 0.2 then
				S.parkedBikes(parent, bb * CF(w / 4, 0.3, -bd / 2 - 0.4), rng:NextInteger(2, 4), rng)
			end
		elseif k == "townhouse" then
			Blocks.townhouses(parent, base, w, dp, rng, o)
		elseif k == "house" then
			o.two = lot.use == "core" and 0.7 or (lot.use == "urban" and 0.5 or 0.3)
			Blocks.home(parent, base, w, dp, rng, o)
		elseif k == "apartment" then
			o.tall = lot.use == "core"
			Blocks.apartment(parent, base, w, dp, rng, o)
		elseif k == "tower" then
			if lot.use ~= "core" then o.minFloors, o.maxFloors = 5, 8 end
			Blocks.tower(parent, base, w, dp, rng, o)
		elseif k == "bigbox" then
			Blocks.bigbox(parent, base, w, dp, rng, o)
		elseif k == "field" then
			Blocks.field(parent, base, w, dp, rng, o)
		elseif k == "farm" then
			Blocks.farmstead(parent, base, w, dp, rng, o)
		else
			Blocks.yard(parent, base, w, dp, rng, o)
		end
	end

	local count = {}
	for _, lot in ipairs(lots) do
		local base = lot.base
		local zone = map.zoneAt(lot.x, lot.z).id
		count[lot.kind] = (count[lot.kind] or 0) + 1
		if lot.view then count.backView = (count.backView or 0) + 1 end
		if lot.kind == "row" then
			local shop = lot.shop
			local bd = math.min(34, lot.dp)
			local bb = base * CF(0, 0, -lot.dp / 2 + bd / 2)
			local units = math.max(1, math.floor(lot.w / 15.5 + 0.5))
			local slotX = -lot.w / 2 + lot.w / units / 2 -- the named shop takes the first unit
			if shop then
				local entry = {
					id = shop.id, kind = shop.kind, name = shop.name, thai = shop.thai, menu = shop.menu, zone = zone,
					pos = (bb * CF(slotX, 3, -bd / 2 - 2)).Position, npc = bb * CF(slotX + 4, 0.3, -bd / 2 + 0.3),
				}
				if shop.kind == "restaurant" then table.insert(world.restaurants, entry) end
				table.insert(world.shops, entry)
			end
			table.insert(world.addresses, { pos = (base * CF(-lot.w / 4, 0, -lot.dp / 2 - 2)).Position, zone = zone, kind = "shop" })
			if lot.w >= 60 then
				table.insert(world.addresses, { pos = (base * CF(lot.w / 4, 0, -lot.dp / 2 - 2)).Position, zone = zone, kind = "shop" })
			end
		elseif ADDRESS_KIND[lot.kind] then
			table.insert(world.addresses, { pos = (base * CF(0, 0, -lot.dp / 2 - 2)).Position, zone = zone, kind = ADDRESS_KIND[lot.kind] })
		end
		emit(lot.x, lot.z, function(parent) drawLot(parent, lot) end)
	end

	-----------------------------------------------------------------------------------------------
	-- street furniture
	-----------------------------------------------------------------------------------------------
	local parkedDefs = {}
	for _, id in ipairs({ "sabai110", "zoomer125", "eco_city", "sedan_vios", "pickup_dmax", "suv_fortune", "oldmoped", "eco_city", "sedan_vios" }) do
		if Vehicles.ById[id] then table.insert(parkedDefs, Vehicles.ById[id]) end
	end
	if emitAll then
		local _, signalsById = Traffic.signals(graph)
		for ei, e in ipairs(graph.edges) do
			local def = e.def
			local mx, mz = (e.a.x + e.b.x) / 2, (e.a.z + e.b.z) / 2
			local rng = vrng(mx, mz)
			local function spot(s: number, side: number, off: number): CFrame
				local nx, nz = -e.dz * side, e.dx * side
				local p = V3(e.a.x + e.dx * s + nx * off, 0, e.a.z + e.dz * s + nz * off)
				return CFrame.lookAt(p, p - V3(nx, 0, nz)) -- -Z looks at the road
			end
			local s0, s1 = e.ta + 6, e.len - e.tb - 6
			if e.minor then
				-- sois and lanes: concrete power poles on one side, wires between them, a lamp on every other pole
				local side = (e.id % 2 == 0) and 1 or -1
				local lastTop, i = nil, 0
				for s = s0 + 8, s1, 110 do
					i += 1
					local cf = spot(s, side, def.width / 2 + 0.8) * CF(0, 0.3, 0) * CFrame.Angles(0, rad(90), 0)
					local top = (cf * CF(0, 24.9, 0)).Position
					local lamp = true -- every pole in a soi carries a lamp: no dark lanes
					local prevTop = lastTop
					emit(top.X, top.Z, function(parent)
						S.pole(parent, cf)
						if lamp then
							local lcf = spot(s, side, def.width / 2 + 0.8) * CF(0, 0.3, 0)
							Kit.part(parent, V3(0.4, 0.4, 5), lcf * CF(0, 18, -2.4), C.metalDark, M.Metal, { decor = true })
							local head = Kit.part(parent, V3(1.4, 0.4, 2.4), lcf * CF(0, 17.8, -4.6), Color3.fromRGB(250, 240, 210), M.SmoothPlastic, { decor = true })
							Kit.nightLight(head, 44, Color3.fromRGB(255, 214, 160), 1.0)
							Kit.nightGlow(head)
						end
						if prevTop then S.wire(parent, prevTop, top) end
					end)
					lastTop = top
				end
			else
				local i = e.id -- alternate sides from one street piece to the next as well
				for s = s0 + 14, s1, 100 do
					i += 1
					local cf = spot(s, i % 2 == 0 and 1 or -1, def.width / 2 + 1.6) * CF(0, 0.5, 0)
					emit(cf.X, cf.Z, function(parent) S.lamp(parent, cf) end)
				end
				local lastTop
				for s = s0, s1, 115 do
					local cf = spot(s, -1, def.width / 2 + def.walk - 1) * CF(0, 0.5, 0) * CFrame.Angles(0, rad(90), 0)
					local top = (cf * CF(0, 24.9, 0)).Position
					local prevTop = lastTop
					emit(top.X, top.Z, function(parent)
						S.pole(parent, cf)
						if prevTop then S.wire(parent, prevTop, top) end
					end)
					lastTop = top
				end
				-- shade trees along both sidewalks, offset from the power poles
				do
					local side = 1
					for s = s0 + 35, s1, e.type == "street" and 90 or 70 do
						local kind = rng:NextNumber() < 0.18 and "palm" or "street"
						local cf = spot(s, side, def.width / 2 + def.walk - 1.8) * CF(0, 0.5, 0)
						emit(cf.X, cf.Z, function(parent) S.tree(parent, cf, vrng(cf.X, cf.Z), kind) end)
						side = -side
					end
				end
				-- hero district: the small things on and beside the road
				if heroAt(mx, mz) then
					local along = CFrame.lookAt(V3(e.a.x, 0, e.a.z), V3(e.b.x, 0, e.b.z))
					emit(mx, mz, function(parent)
						local r2 = vrng(mx + 3, mz + 7)
						for s = s0 + 30, s1, 64 do
							for _, side in ipairs({ -1, 1 }) do
								Life.grate(parent, spot(s + (side > 0 and 20 or 0), side, def.width / 2 - 0.9) * CF(0, def.y, 0))
							end
						end
						for s = s0 + 70, s1, 230 do
							Life.manhole(parent, (along * CF(r2:NextNumber(-def.width / 4, def.width / 4), def.y, -s)).Position)
							Life.patch(parent, along * CF(r2:NextNumber(-def.width / 3, def.width / 3), def.y, -s - 60) * CFrame.Angles(0, rad(r2:NextNumber(-6, 6)), 0), r2)
						end
						for s = s0 + 46, s1, 190 do
							local side = r2:NextNumber() < 0.5 and 1 or -1
							local r = r2:NextNumber()
							if r < 0.35 then Life.cabinet(parent, spot(s, side, def.width / 2 + def.walk - 1.4) * CF(0, 0.5, 0))
							elseif r < 0.7 then Life.trafficSign(parent, spot(s, side, def.width / 2 + 1.2) * CF(0, 0.5, 0) * CFrame.Angles(0, rad(side > 0 and 90 or -90), 0), ({ "limit", "noparking", "noparking", "oneway" })[r2:NextInteger(1, 4)])
							else Life.bin(parent, spot(s, side, def.width / 2 + def.walk - 1.6) * CF(0, 0.5, 0), r2) end
						end
						-- parked cars and bikes along the kerb
						for s = s0 + 110, s1 - 30, 210 do
							if r2:NextNumber() < 0.75 and #parkedDefs > 0 then
								local side = r2:NextNumber() < 0.5 and 1 or -1
								local vdef = parkedDefs[r2:NextInteger(1, #parkedDefs)]
								local nx, nz = -e.dz * side, e.dx * side
								local off = def.width / 2 - (vdef.class == "bike" and 1.6 or 4.2)
								local p = V3(e.a.x + e.dx * s + nx * off, def.y + vdef.wheelR + 0.9, e.a.z + e.dz * s + nz * off)
								local model = VehicleFactory.display(vdef, CFrame.lookAt(p, p + V3(e.dx, 0, e.dz) * -side), r2:NextInteger(1, 8))
								model.Name = "Parked"
								model.Parent = parent
							end
						end
					end)
				end
			end
			if ei % 600 == 0 then task.wait() end
		end
		-- traffic lights (2026-11-18 rebuild): only at real signalled junctions, one signal per road coming INTO the
		-- junction (shared/Traffic: signal.groups holds exactly those), none on the short pieces inside it
		for _, n in ipairs(graph.nodes) do
			local signal = signalsById[n.id]
			if signal and next(signal.groups) then
				emit(n.x, n.z, function(parent)
					for _, l in ipairs(n.links) do
						local group = signal.groups[l.edge]
						if group ~= nil then
							local e = l.edge
							local sgn = e.a == n and 1 or -1
							local dx, dz = e.dx * sgn, e.dz * sgn -- from the junction out along this road, toward the drivers
							local half = e.def.width / 2
							-- drivers keep left: the inbound lanes are the left half of a two-way road, all of a one-way one
							local span = e.oneway and e.def.width or half
							local lx, lz = -dz, dx -- the driver's left
							local p = V3(n.x + dx * (n.r + 7) + lx * (half + 2), 0.5, n.z + dz * (n.r + 7) + lz * (half + 2))
							local sm = Kit.model(parent, "Signal")
							sm:SetAttribute("Node", n.id)
							sm:SetAttribute("Group", group)
							sm:AddTag("TrafficSignal")
							-- pole on the left kerb, the arm reaching over the middle of the inbound lanes
							S.trafficLight(sm, CFrame.lookAt(p, p + V3(dx, 0, dz)), 2 + span / 2)
							-- stop line across the inbound lanes only, and the zebra crossing between it and the junction
							local stopAt = V3(n.x + dx * (n.r + 9) + lx * (half - span / 2), 0, n.z + dz * (n.r + 9) + lz * (half - span / 2))
							Kit.part(sm, V3(span - 1, 0.05, 1), CFrame.lookAt(stopAt, stopAt + V3(dx, 0, dz)) * CF(0, e.def.y + 0.03, 0), C.line, M.SmoothPlastic, { decor = true, name = "StopLine" })
							local zAt = V3(n.x + dx * (n.r + 4.6), 0, n.z + dz * (n.r + 4.6))
							RoadMarks.zebra(sm, CFrame.lookAt(zAt, zAt + V3(dx, 0, dz)) * CF(0, e.def.y, 0), e.def.width - 1.5, 4.6)
						end
					end
				end)
			end
			-- blue road-name signs at junctions in the hero district: on the pavement corner between two of
			-- the streets that meet there (until 2026-11-16 the post stood at a fixed offset from the
			-- junction and, at lane mouths, that was the middle of the road)
			if n.deg >= 3 and heroAt(n.x, n.z) then
				local arms = {}
				local big = false
				for _, l in ipairs(n.links) do
					local e = l.edge
					local sgn = e.a == n and 1 or -1
					table.insert(arms, { e = e, ang = math.atan2(e.dz * sgn, e.dx * sgn) })
					if not e.minor then big = true end
				end
				table.sort(arms, function(p, q) return p.ang < q.ang end)
				-- the corner whose opening is nearest a right angle
				local best, bestScore
				for i, p in ipairs(arms) do
					local q = arms[i % #arms + 1]
					local gap = (q.ang - p.ang) % (2 * math.pi)
					local score = math.abs(gap - math.pi / 2)
					if gap > 0.5 and gap < 2.6 and (p.e.name ~= "" or q.e.name ~= "") and (not bestScore or score < bestScore) then
						best, bestScore = { p = p, q = q, gap = gap }, score
					end
				end
				if big and best then
					local a, b = best.p.e, best.q.e
					if a.name == "" then a, b = b, a end
					local mid = best.p.ang + best.gap / 2
					local dist = (math.max(half(a), half(b)) + 1.6) / math.max(math.sin(best.gap / 2), 0.45)
					local corner = V3(n.x + math.cos(mid) * dist, 0.5, n.z + math.sin(mid) * dist)
					local second = b.name ~= "" and b.name ~= a.name
					emit(corner.X, corner.Z, function(parent)
						Life.roadName(parent, CFrame.lookAt(corner, corner + V3(a.dz, 0, -a.dx)), a.thai ~= "" and a.thai or a.name, a.name,
							second and (b.thai ~= "" and b.thai or b.name) or nil, second and b.name or nil)
					end)
				end
			end
		end
	end

	-- bus stops beside the places people travel between
	for _, id in ipairs({ "hub", "mall", "station", "nightmarket", "bus", "stupa", "agri", "hospital" }) do
		local poi = world.pois[id]
		if poi then
			local e, p = graph:nearest(poi.door, notMinor)
			if e then
				local toPoi = V3(poi.door.X - p.X, 0, poi.door.Z - p.Z)
				local nx, nz = -e.dz, e.dx
				if toPoi.X * nx + toPoi.Z * nz < 0 then nx, nz = -nx, -nz end
				local at = p + V3(nx, 0, nz) * (e.def.width / 2 + math.max(e.def.walk, 4) / 2 + 1)
				local base = CFrame.lookAt(at, at - V3(nx, 0, nz))
				emit(at.X, at.Z, function(parent) S.busStop(parent, base * CF(0, 0.5, 0)) end)
				table.insert(world.busStops, { id = "b_" .. id, name = poi.name, thai = poi.thai, pos = (base * CF(0, 3, -1)).Position })
			end
		end
	end

	-- district gateways: a sign gantry over the big roads where one district ends and the next begins
	do
		local placed = {}
		for _, e in ipairs(graph.edges) do
			if (e.type == "highway" or e.type == "main") and e.len > 70 then
				local za, zb = map.zoneAt(e.a.x, e.a.z), map.zoneAt(e.b.x, e.b.z)
				if za.id ~= zb.id then
					local mid = V3((e.a.x + e.b.x) / 2, 0, (e.a.z + e.b.z) / 2)
					local ok = true
					for _, q in ipairs(placed) do
						if (q - mid).Magnitude < 800 then ok = false break end
					end
					if ok then
						table.insert(placed, mid)
						local cf = CFrame.lookAt(mid, V3(e.b.x, 0, e.b.z))
						local span = e.def.width + 4
						emit(mid.X, mid.Z, function(parent) S.gateway(parent, cf, span, za, zb) end)
					end
				end
			end
		end
		world.gateways = #placed
	end

	-----------------------------------------------------------------------------------------------
	-- what is left inside blocks. 2026-11-18 (the real street plan of the whole tambon has far fewer
	-- invented lanes, so much more land is inside blocks): in town the inside of a block is small
	-- houses packed along a footpath (ซอยย่อย), as in a real Thai town; school, university, hospital and
	-- government grounds (OSM land use "campus") are lawns, shade trees, sports fields and long
	-- teaching blocks; fields and the countryside are farmland.
	-----------------------------------------------------------------------------------------------
	local darker = S.darker
	local function campusBlock(parent, base: CFrame, w: number, d: number, rng: Random)
		-- the long open-corridor building of a Thai school or faculty
		local m = Kit.model(parent, "CampusBlock")
		local floors = rng:NextInteger(2, 4)
		local fh = 10
		local h = floors * fh
		local col = ({ Color3.fromRGB(238, 232, 214), Color3.fromRGB(232, 222, 200), Color3.fromRGB(226, 230, 232) })[rng:NextInteger(1, 3)]
		local trim = ({ Color3.fromRGB(150, 60, 50), Color3.fromRGB(60, 90, 150), Color3.fromRGB(70, 120, 80) })[rng:NextInteger(1, 3)]
		Kit.part(m, V3(w, h, d - 6), base * CF(0, h / 2, 3), col, M.Concrete)
		for f = 1, floors do
			local y = (f - 1) * fh
			Kit.part(m, V3(w, 0.6, 6), base * CF(0, y + 0.3, -d / 2 + 3), darker(col, 0.85), M.Concrete, { decor = true }) -- corridor floor
			if f > 1 then Kit.part(m, V3(w, 2.8, 0.4), base * CF(0, y + 1.7, -d / 2 + 0.3), trim, M.Concrete, { decor = true }) end -- balustrade
			local win = Kit.part(m, V3(w - 4, 4.2, 0.3), base * CF(0, y + 5.2, -d / 2 + 6.1), C.glass, M.Glass, { decor = true })
			if rng:NextNumber() < 0.4 then Kit.nightGlow(win) end
		end
		Kit.part(m, V3(w, 0.6, 6), base * CF(0, h + 0.3, -d / 2 + 3), darker(col, 0.85), M.Concrete, { decor = true })
		Kit.gable(m, base * CF(0, 0, 0), w + 4, d + 4, 7, h, trim, M.Slate)
		return m
	end
	local function sportsField(parent, base: CFrame, rng: Random)
		local g = Kit.part(parent, V3(84, 0.35, 56), base * CF(0, 0.2, 0), Color3.fromRGB(96, 150, 70), M.Grass, { name = "Pitch", decor = true })
		local _ = g
		local white = Color3.fromRGB(240, 240, 236)
		for _, l in ipairs({ { V3(80, 0.1, 0.6), CF(0, 0.42, -26) }, { V3(80, 0.1, 0.6), CF(0, 0.42, 26) }, { V3(0.6, 0.1, 52), CF(-40, 0.42, 0) },
			{ V3(0.6, 0.1, 52), CF(40, 0.42, 0) }, { V3(0.6, 0.1, 52), CF(0, 0.42, 0) } }) do
			Kit.part(parent, l[1], base * l[2], white, M.SmoothPlastic, { decor = true })
		end
		for _, sx in ipairs({ -1, 1 }) do -- goals
			Kit.part(parent, V3(0.5, 6, 0.5), base * CF(sx * 40, 3, -7), white, M.Metal, { decor = true })
			Kit.part(parent, V3(0.5, 6, 0.5), base * CF(sx * 40, 3, 7), white, M.Metal, { decor = true })
			Kit.part(parent, V3(0.5, 0.5, 14.5), base * CF(sx * 40, 6, 0), white, M.Metal, { decor = true })
		end
		local _r = rng
	end
	local fillCount, sampleN = 0, 0
	local STEP = 92
	local LAWN = Color3.fromRGB(118, 158, 84)
	for x = bounds.minX + 60, bounds.maxX - 60, STEP do
		for z = bounds.minZ + 60, bounds.maxZ - 60, STEP do
			sampleN += 1
			local o = obb(x, z, 1, 0, STEP / 2 - 0.5, STEP / 2 - 0.5, "fill")
			if free(o) then
				put(gridL, o)
				fillCount += 1
				local use = landUse(x, z)
				local raw = map.landUseRaw and map.landUseRaw(x, z) or nil
				do -- what this cell will hold, for the far outline (the same draws as the function below)
					local pr = vrng(x, z)
					pr:NextInteger(0, 3)
					local r = pr:NextNumber()
					if raw == "campus" or raw == "military" then
						if raw == "campus" and r >= 0.07 and r < 0.45 then sky.building(x, z, 30) else sky.trees(x, z, 20) end
					elseif use == "rural" or raw == "green" or (use == "suburb" and r < 0.4) then
						if (math.floor(x / 92) * 31 + math.floor(z / 92) * 17) % 10 < 3 then sky.trees(x, z, 18) end
					elseif use == "suburb" then
						sky.building(x, z, 16); sky.trees(x, z, 18)
					else
						sky.building(x, z, 16)
					end
				end
				emit(x, z, function(parent)
					local rng = vrng(x, z)
					local base = CF(x, 0, z)
					local turn = CFrame.Angles(0, rad(90 * rng:NextInteger(0, 3)), 0)
					if raw == "campus" or raw == "military" then
						Kit.part(parent, V3(STEP - 1, 0.3, STEP - 1), base * CF(0, 0.1, 0), LAWN, M.Grass, { name = "Lawn", decor = true, variant = "GD_Grass" })
						local r = rng:NextNumber()
						if raw == "campus" and r < 0.07 then
							sportsField(parent, base * turn, rng)
						elseif raw == "campus" and r < 0.45 then
							campusBlock(parent, base * turn, STEP - 14, 40, rng)
						else
							for _ = 1, rng:NextInteger(2, 4) do
								S.tree(parent, base * CF(rng:NextNumber(-36, 36), 0.2, rng:NextNumber(-36, 36)), rng, ({ "rain", "rain", "small", "bush" })[rng:NextInteger(1, 4)])
							end
						end
					elseif use == "rural" or raw == "green" or (use == "suburb" and rng:NextNumber() < 0.4) then
						Blocks.field(parent, base * CFrame.Angles(0, rad(90 * rng:NextInteger(0, 1)), 0), STEP - 1, STEP - 1, rng, {})
					elseif use == "suburb" then
						-- a house or two with a big garden
						Kit.part(parent, V3(STEP - 1, 0.3, STEP - 1), base * CF(0, 0.1, 0), Color3.fromRGB(132, 150, 92), M.Grass, { name = "Garden", decor = true, variant = "GD_Grass" })
						S.house(parent, base * turn * CF(0, 0, -14), 44, 44, rng)
						if rng:NextNumber() < 0.5 then S.house(parent, base * turn * CFrame.Angles(0, math.pi, 0) * CF(rng:NextNumber(-20, 20), 0, -30), 40, 40, rng) end
						for _ = 1, rng:NextInteger(1, 3) do
							S.tree(parent, base * CF(rng:NextNumber(-38, 38), 0.2, rng:NextNumber(-38, 38)), rng, ({ "banana", "small", "rain", "bush" })[rng:NextInteger(1, 4)])
						end
					elseif rng:NextNumber() < 0.12 then
						-- now and then a pocket of unbuilt land in town: dusty ground with a few trees
						Kit.part(parent, V3(STEP - 1, 0.3, STEP - 1), base * CF(0, 0.1, 0), Color3.fromRGB(146, 136, 110), M.Ground, { name = "Vacant", decor = true })
						for _ = 1, rng:NextInteger(1, 3) do
							S.tree(parent, base * CF(rng:NextNumber(-34, 34), 0.2, rng:NextNumber(-34, 34)), rng, ({ "rain", "small", "banana", "bush" })[rng:NextInteger(1, 4)])
						end
					else
						-- town: four small houses facing a footpath down the middle
						local cell = base * CFrame.Angles(0, rad(90 * rng:NextInteger(0, 1)), 0)
						Kit.part(parent, V3(7, 0.25, STEP - 1), cell * CF(0, 0.12, 0), Color3.fromRGB(176, 170, 160), M.Concrete, { name = "Footpath", decor = true })
						for _, sx in ipairs({ -1, 1 }) do
							for _, sz in ipairs({ -1, 1 }) do
								if rng:NextNumber() < 0.9 then
									-- the house's front (-Z) faces the footpath (x = 0)
									local hf = cell * CF(sx * 24, 0, sz * 23) * CFrame.Angles(0, sx * math.pi / 2, 0)
									S.house(parent, hf, 42, 40, rng)
								end
							end
						end
					end
				end)
			end
		end
		if sampleN % 2000 < 148 then task.wait() end
	end
	-- second pass with half-size cells for the irregular gaps between lots in town (a big cell rarely fits
	-- there): one small house, a shed and trees, or a garden; only inside the suburb ring (plan time)
	do
		local STEP2 = 46
		local lu = map.landUseCfg
		local cx0, cz0 = center.X, center.Z
		local R2 = ((lu and lu.suburbRadius) or 9000) ^ 2
		local n2 = 0
		for x = bounds.minX + 40, bounds.maxX - 40, STEP2 do
			for z = bounds.minZ + 40, bounds.maxZ - 40, STEP2 do
				n2 += 1
				local inner = (x - cx0) ^ 2 + (z - cz0) ^ 2 < R2
				do
					local o = obb(x, z, 1, 0, STEP2 / 2 - 0.5, STEP2 / 2 - 0.5, "fill")
					if free(o) then
						local use = landUse(x, z)
						if use == "rural" then
							-- 2026-11-18: the ragged grass gaps between fields become farmland too: a small paddy,
							-- a dirt yard with the track through it, a clump of sugar palms and bushes, or grazing
							put(gridL, o)
							fillCount += 1
							local raw = map.landUseRaw and map.landUseRaw(x, z) or nil
							local pr = vrng(x + 11, z + 5)
							local turnK = pr:NextInteger(0, 3)
							local r = pr:NextNumber()
							if raw == "military" or raw == "green" or (r >= 0.72 and r < 0.9) then sky.trees(x, z, raw and 18 or 30) end
							emit(x, z, function(parent)
								local rng = vrng(x + 13, z + 7)
								local base = CF(x, 0, z) * CFrame.Angles(0, rad(90 * turnK), 0)
								if raw == "military" or raw == "green" then
									Kit.part(parent, V3(STEP2 - 1, 0.3, STEP2 - 1), CF(x, 0.1, z), LAWN, M.Grass, { name = "Lawn", decor = true, variant = "GD_Grass" })
									if r < 0.5 then S.tree(parent, base * CF(rng:NextNumber(-12, 12), 0.2, rng:NextNumber(-12, 12)), rng, rng:NextNumber() < 0.5 and "rain" or "small") end
								elseif r < 0.5 then
									Blocks.field(parent, base, STEP2 - 1, STEP2 - 1, rng, {})
								elseif r < 0.72 then
									Kit.part(parent, V3(STEP2 - 1, 0.3, STEP2 - 1), CF(x, 0.12, z), Color3.fromRGB(150, 124, 94), M.Ground, { name = "Dirt", decor = true })
									Kit.part(parent, V3(6, 0.34, STEP2 - 1), base * CF(0, 0.16, 0), Color3.fromRGB(168, 134, 98), M.Ground, { name = "Track", decor = true })
									if rng:NextNumber() < 0.6 then S.tree(parent, base * CF(rng:NextNumber(8, 18) * (rng:NextNumber() < 0.5 and -1 or 1), 0.2, rng:NextNumber(-16, 16)), rng, "bush") end
								elseif r < 0.9 then
									-- a clump: one or two sugar palms with bushes and a banana round their feet
									S.tree(parent, base * CF(rng:NextNumber(-8, 8), 0.2, rng:NextNumber(-8, 8)), rng, "sugarpalm")
									if rng:NextNumber() < 0.5 then S.tree(parent, base * CF(rng:NextNumber(-16, 16), 0.2, rng:NextNumber(-16, 16)), rng, "sugarpalm") end
									for _ = 1, rng:NextInteger(1, 3) do
										S.tree(parent, base * CF(rng:NextNumber(-17, 17), 0.2, rng:NextNumber(-17, 17)), rng, ({ "bush", "banana", "small" })[rng:NextInteger(1, 3)])
									end
								else
									for _ = 1, 3 do S.tree(parent, base * CF(rng:NextNumber(-18, 18), 0.2, rng:NextNumber(-18, 18)), rng, "grass") end
								end
							end)
						elseif inner and (use == "core" or use == "urban" or use == "suburb") then
							put(gridL, o)
							fillCount += 1
							local raw = map.landUseRaw and map.landUseRaw(x, z) or nil
							if raw == "campus" or raw == "military" or raw == "green" then sky.trees(x, z, 20) else sky.building(x, z, 14) end
							emit(x, z, function(parent)
								local rng = vrng(x + 7, z + 3)
								local base = CF(x, 0, z) * CFrame.Angles(0, rad(90 * rng:NextInteger(0, 3)), 0)
								if raw == "campus" or raw == "military" or raw == "green" then
									Kit.part(parent, V3(STEP2 - 1, 0.3, STEP2 - 1), CF(x, 0.1, z), LAWN, M.Grass, { name = "Lawn", decor = true, variant = "GD_Grass" })
									S.tree(parent, base * CF(rng:NextNumber(-12, 12), 0.2, rng:NextNumber(-12, 12)), rng, "rain")
								elseif use == "suburb" and rng:NextNumber() < 0.5 then
									Kit.part(parent, V3(STEP2 - 1, 0.3, STEP2 - 1), CF(x, 0.1, z), Color3.fromRGB(132, 150, 92), M.Grass, { name = "Garden", decor = true, variant = "GD_Grass" })
									for _ = 1, rng:NextInteger(1, 2) do
										S.tree(parent, base * CF(rng:NextNumber(-16, 16), 0.2, rng:NextNumber(-16, 16)), rng, ({ "banana", "small", "rain" })[rng:NextInteger(1, 3)])
									end
								elseif rng:NextNumber() < 0.8 then
									S.house(parent, base, 42, 40, rng)
								else
									S.tree(parent, base * CF(rng:NextNumber(-12, 12), 0.2, rng:NextNumber(-12, 12)), rng, ({ "small", "banana", "bush" })[rng:NextInteger(1, 3)])
								end
							end)
						end
					end
				end
			end
			if n2 % 4000 < 760 then task.wait() end
		end
	end
	skyDone()

	world.buildSeconds = os.clock() - t0
	world.lots = #lots
	world.lotList = lots
	if emitAll then
		root:SetAttribute("Built", true)
		root:SetAttribute("Partial", true) -- drawn around players by the Streamer, never the whole map
		stream:start()
	else
		root:Destroy()
	end
	local kinds = {}
	for k, n in pairs(count) do table.insert(kinds, k .. "=" .. n) end
	table.sort(kinds)
	local st = stream:stats()
	print(("[World] %s planned in %.2fs (lots %.2fs): %d nodes, %d edges, %d lots (%s), %d infill, %d addresses, %d restaurants, %d shops, %d plots, %d farms, %d chunks")
		:format(map.name, world.buildSeconds, world.planLotsSeconds, #graph.nodes, #graph.edges, #lots, table.concat(kinds, " "), fillCount, #world.addresses,
			#world.restaurants, #world.shops, #world.plots, #world.farms, st.chunks))
	return world
end

return Builder
