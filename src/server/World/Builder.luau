-- Builds a province from its map data at 1:1 scale: ground, the real street network, water, parks,
-- railway, landmarks, street-front buildings, street furniture and filler.
-- Returns the registry the gameplay services work from.
--
-- opts.planOnly = true  -> compute the registry without creating the scenery (world already baked)
-- opts.radius / opts.center -> only build scenery within this distance (fast development boots)
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local S = require(script.Parent.Scenery)
local Places = require(script.Parent.Places)
local RoadGraph = require(ReplicatedStorage.Shared.RoadGraph)
local Traffic = require(ReplicatedStorage.Shared.Traffic)
local Housing = require(ReplicatedStorage.Shared.Config.Housing)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Shophouse = require(script.Parent.Shophouse)
local Life = require(script.Parent.StreetLife)
local VehicleFactory = require(script.Parent.VehicleFactory)
local Assets = require(script.Parent.Assets)

local M = Kit.M
local C = Kit.COLORS
local V3 = Vector3.new
local CF = CFrame.new
local rad = math.rad

local Builder = {}

local OCELL = 256

function Builder.build(map, opts)
	opts = opts or {}
	local t0 = os.clock()
	Kit.setupMaterials()
	if not opts.planOnly then Assets.load() end -- yields while the mesh props download
	local planRng = Random.new(20261114) -- layout decisions only: must not depend on what gets drawn
	local graph = RoadGraph.new(map)
	local bounds = map.bounds
	local emitAll = not opts.planOnly
	local center = opts.center or map.center
	local radius = opts.radius

	local function near(x: number, z: number): boolean
		if not emitAll then return false end
		if not radius then return true end
		return (x - center.X) ^ 2 + (z - center.Z) ^ 2 <= radius * radius
	end
	local function vrng(x: number, z: number): Random -- visual randomness, stable per spot
		return Random.new(math.floor(x) * 7919 + math.floor(z) * 104729 + 17)
	end

	local root, fGround, fRoads, fBuild, fProps, fPlaces
	if emitAll then
		local old = Workspace:FindFirstChild("Map")
		if old then old:Destroy() end
		root = Kit.folder(Workspace, "Map")
	else
		root = Instance.new("Folder") -- scratch: places still run to report their door/npc spots
	end
	fGround = Kit.folder(root, "Ground")
	fRoads = Kit.folder(root, "Roads")
	fBuild = Kit.folder(root, "Buildings")
	fProps = Kit.folder(root, "Props")
	fPlaces = Kit.folder(root, "Places")
	for _, n in ipairs({ "NPCs", "Vehicles", "Interactions", "Plots", "Farms" }) do
		if not Workspace:FindFirstChild(n) then Kit.folder(Workspace, n) end
	end

	local world = {
		map = map, graph = graph,
		pois = {}, addresses = {}, restaurants = {}, shops = {}, busStops = {}, plots = {}, farms = {},
	}

	-----------------------------------------------------------------------------------------------
	-- occupancy: oriented boxes in a grid
	-----------------------------------------------------------------------------------------------
	local grid = {}
	local function obb(cx, cz, ux, uz, hw, hd)
		return { cx = cx, cz = cz, ux = ux, uz = uz, hw = hw, hd = hd, r = math.sqrt(hw * hw + hd * hd) }
	end
	local function overlap(a, b): boolean
		local dx, dz = b.cx - a.cx, b.cz - a.cz
		if dx * dx + dz * dz > (a.r + b.r) ^ 2 then return false end
		-- separating axis test on both boxes' axes
		local axes = { { a.ux, a.uz }, { -a.uz, a.ux }, { b.ux, b.uz }, { -b.uz, b.ux } }
		for _, ax in ipairs(axes) do
			local x, z = ax[1], ax[2]
			local ra = a.hw * math.abs(a.ux * x + a.uz * z) + a.hd * math.abs(-a.uz * x + a.ux * z)
			local rb = b.hw * math.abs(b.ux * x + b.uz * z) + b.hd * math.abs(-b.uz * x + b.ux * z)
			if math.abs(dx * x + dz * z) > ra + rb then return false end
		end
		return true
	end
	local function cells(o)
		local out = {}
		for cx = math.floor((o.cx - o.r) / OCELL), math.floor((o.cx + o.r) / OCELL) do
			for cz = math.floor((o.cz - o.r) / OCELL), math.floor((o.cz + o.r) / OCELL) do
				table.insert(out, cx * 4096 + cz)
			end
		end
		return out
	end
	local function reserve(o)
		for _, k in ipairs(cells(o)) do
			local list = grid[k]
			if not list then list = {}; grid[k] = list end
			table.insert(list, o)
		end
		return o
	end
	local function free(o): boolean
		if o.cx - o.r < bounds.minX + 4 or o.cx + o.r > bounds.maxX - 4 or o.cz - o.r < bounds.minZ + 4 or o.cz + o.r > bounds.maxZ - 4 then return false end
		for _, k in ipairs(cells(o)) do
			local list = grid[k]
			if list then
				for _, other in ipairs(list) do
					if overlap(o, other) then return false end
				end
			end
		end
		return true
	end
	local function unreserve(o)
		for _, k in ipairs(cells(o)) do
			local list = grid[k]
			if list then
				local i = table.find(list, o)
				if i then table.remove(list, i) end
			end
		end
	end

	-- Lot beside edge `e` at distance `s` from node a, on side +1 / -1. Returns frame (front faces the road) and its box.
	local function lotAt(e, s: number, side: number, w: number, d: number, gap: number?)
		local nx, nz = -e.dz * side, e.dx * side
		local off = e.def.width / 2 + e.def.walk + (gap or 1.5) + d / 2
		local px, pz = e.a.x + e.dx * s, e.a.z + e.dz * s
		local cx, cz = px + nx * off, pz + nz * off
		local c = V3(cx, 0, cz)
		local base = CFrame.lookAt(c, c - V3(nx, 0, nz))
		return base, obb(cx, cz, e.dx, e.dz, w / 2, d / 2), cx, cz
	end

	-- Find free land beside a road near `at`. prefer(e) can veto edges.
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
								local base, box, cx, cz = lotAt(e, s, side, w, d, 2)
								if free(box) then
									reserve(box)
									return base, e, cx, cz
								end
							end
						end
					end
				end
			end
		end
		return nil
	end

	-----------------------------------------------------------------------------------------------
	-- ground
	-----------------------------------------------------------------------------------------------
	if emitAll then
		local tile = 2000
		local x0, x1, z0, z1 = bounds.minX - 300, bounds.maxX + 300, bounds.minZ - 300, bounds.maxZ + 300
		local nx, nz = math.ceil((x1 - x0) / tile), math.ceil((z1 - z0) / tile)
		local sx, sz = (x1 - x0) / nx, (z1 - z0) / nz
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				Kit.part(fGround, V3(sx, 8, sz), CF(x0 + sx * (i + 0.5), -4, z0 + sz * (j + 0.5)), Color3.fromRGB(196, 204, 176), M.Grass, { name = "Ground", variant = "GD_Grass" })
			end
		end
		local midX, midZ = (bounds.minX + bounds.maxX) / 2, (bounds.minZ + bounds.maxZ) / 2
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
		local _ = midX + midZ
	end

	-----------------------------------------------------------------------------------------------
	-- roads
	-----------------------------------------------------------------------------------------------
	local ROAD_COL = { highway = Color3.fromRGB(150, 152, 156), main = Color3.fromRGB(156, 158, 162), street = Color3.fromRGB(164, 164, 166), soi = Color3.fromRGB(176, 174, 172) }
	local ROAD_VARIANT = { highway = "GD_Asphalt", main = "GD_Asphalt", street = "GD_Asphalt", soi = "GD_AsphaltWorn" }
	for _, n in ipairs(graph.nodes) do
		n.deg = #n.links
		local walk = 0
		for _, l in ipairs(n.links) do walk = math.max(walk, l.edge.def.walk) end
		n.walk = walk
		n.trim = n.deg >= 3 and (n.r + walk + 5) or 0
	end
	for _, e in ipairs(graph.edges) do
		local def = e.def
		local a, b = e.a, e.b
		local mid = V3((a.x + b.x) / 2, 0, (a.z + b.z) / 2)
		local cf = CFrame.lookAt(mid, V3(b.x, 0, b.z)) -- local Z along the road, X across
		if emitAll then
			Kit.part(fRoads, V3(def.width, 0.4, e.len), cf * CF(0, def.y - 0.2, 0), ROAD_COL[e.type], M.Asphalt, { name = "Road", variant = ROAD_VARIANT[e.type] }):AddTag("Road")
			local ta, tb = a.trim, b.trim
			local span = e.len - ta - tb
			if def.walk > 0 and span > 4 then
				local shift = (tb - ta) / 2 -- local -Z points at b, so a larger trim at b moves the strip toward a (+Z)
				for _, s in ipairs({ -1, 1 }) do
					Kit.part(fRoads, V3(def.walk, 0.5, span), cf * CF(s * (def.width / 2 + def.walk / 2), 0.25, shift), C.walk, M.Pavement, { name = "Walk" })
				end
			end
			local lineSpan = e.len - a.r - b.r - 4
			if lineSpan > 12 then
				local shift = (b.r - a.r) / 2
				if e.type == "main" or e.type == "street" then
					Kit.part(fRoads, V3(0.6, 0.05, lineSpan), cf * CF(0, def.y + 0.03, shift), e.oneway and C.line or C.lineYellow, M.SmoothPlastic, { decor = true, name = "Line" })
				elseif e.type == "highway" then
					for _, s in ipairs({ -1, 1 }) do
						Kit.part(fRoads, V3(0.5, 0.05, lineSpan), cf * CF(s * def.width / 6, def.y + 0.03, shift), C.line, M.SmoothPlastic, { decor = true, name = "Line" })
					end
				end
			end
		end
		e.box = reserve(obb(mid.X, mid.Z, e.dx, e.dz, e.len / 2 + 2, def.width / 2 + def.walk + 1))
	end
	if emitAll then
		for i, n in ipairs(graph.nodes) do
			local top = 0
			local col = ROAD_COL.soi
			local variant = ROAD_VARIANT.soi
			local best = 9
			for _, l in ipairs(n.links) do
				top = math.max(top, l.edge.def.y)
				if l.edge.def.id < best then best = l.edge.def.id; col = ROAD_COL[l.edge.type]; variant = ROAD_VARIANT[l.edge.type] end
			end
			Kit.cyl(fRoads, n.r * 2, 0.4, CF(n.x, top - 0.18, n.z), col, M.Asphalt, { name = "Junction", variant = variant }):AddTag("Road")
			if n.deg >= 3 and n.walk > 0 then
				-- dropped-kerb apron fills the corners between sidewalks
				Kit.cyl(fRoads, (n.r + n.walk + 5) * 2, 0.3, CF(n.x, 0.02, n.z), Color3.fromRGB(170, 168, 160), M.Concrete, { name = "Apron" })
			end
			if i % 400 == 0 then task.wait() end
		end
	end
	task.wait()

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
				reserve(obb((xa + xb) / 2, z, 1, 0, (xb - xa) / 2 + 3, step / 2 + 3))
				if wm then
					local len = xb - xa
					local pieces = math.ceil(len / 2000)
					for k = 0, pieces - 1 do
						Kit.part(wm, V3(len / pieces, 0.7, step + 0.4), CF(xa + len / pieces * (k + 0.5), -0.1, z), C.water, M.SmoothPlastic, { name = "Water", reflectance = 0.28 })
					end
				end
			end
		end)
		if big then
			world.lake = { x = (minX + maxX) / 2, z = (minZ + maxZ) / 2, minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
			if wm then
				-- stone rim with lamps along the real shoreline
				local n = #w.pts // 2
				for i = 1, n do
					local j = i % n + 1
					local a = V3(w.pts[i * 2 - 1], 0, w.pts[i * 2])
					local b = V3(w.pts[j * 2 - 1], 0, w.pts[j * 2])
					local len = (b - a).Magnitude
					if len > 2 then
						local cf = CFrame.lookAt((a + b) / 2, b)
						Kit.part(wm, V3(2.4, 1.5, len + 1), cf * CF(0, 0.75, 0), Color3.fromRGB(214, 208, 196), M.Concrete, { name = "Rim" })
						if i % 3 == 0 then
							local lamp = Kit.ball(wm, 1.5, cf * CF(0, 9, 0), Color3.fromRGB(255, 236, 190), M.SmoothPlastic, { decor = true })
							Kit.cyl(wm, 0.5, 8, cf * CF(0, 4.6, 0), C.metalDark, M.Metal, { decor = true })
							Kit.nightLight(lamp, 40, Color3.fromRGB(255, 220, 170), 1.6); Kit.nightGlow(lamp)
						end
					end
				end
				-- fountain jets in the middle
				for k = -1, 1 do
					Kit.cyl(wm, 3, 26, CF(world.lake.x + k * 60, 13, world.lake.z + k * 200), Color3.fromRGB(190, 225, 240), M.Glass, { decor = true, transparency = 0.45 })
				end
			end
		end
		table.insert(world.water, { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ })
	end
	for pi, p in ipairs(F.parks) do
		local pm = emitAll and Kit.model(fPlaces, "Park" .. pi) or nil
		local prng = Random.new(900 + pi)
		scan(p.pts, 48, function(xa, xb, z)
			if xb - xa > 6 then
				local o = obb((xa + xb) / 2, z, 1, 0, (xb - xa) / 2, 24)
				if free(o) then
					reserve(o)
					if pm and near((xa + xb) / 2, z) then
						Kit.part(pm, V3(xb - xa, 0.3, 48.4), CF((xa + xb) / 2, 0.08, z), C.leafLight, M.Grass, { name = "Lawn", decor = true })
						for x = xa + 20, xb - 20, 70 do
							S.tree(pm, CF(x + prng:NextNumber(-14, 14), 0, z + prng:NextNumber(-16, 16)), prng, ({ "rain", "small", "palm", "bush" })[prng:NextInteger(1, 4)])
						end
					end
				end
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
				reserve(obb(midp.X, midp.Z, dir.X, dir.Z, len / 2 + 1, 9))
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
	local function buildPlace(poi, base, e)
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
		entry.road = e
		world.pois[poi.id] = entry
		table.insert(world.addresses, { pos = V3(entry.door.X, 0, entry.door.Z), zone = entry.zone, kind = poi.kind, name = poi.name })
		return entry
	end
	local notSoi = function(e) return e.type ~= "soi" end
	for _, poi in ipairs(map.pois) do
		local wantBig = poi.w >= 100
		local base, e = placeNear(poi.at, poi.w, poi.d, wantBig and notSoi or nil)
		if not base then base, e = placeNear(poi.at, poi.w, poi.d, nil) end
		if base then buildPlace(poi, base, e) else warn("[World] no room for " .. poi.id) end
	end
	-- fuel stations on real positions, spread out
	do
		local picked = {}
		for _, p in ipairs(F.pois) do
			if p[1] == "fuel" and #picked < map.gasStations then
				local pos = V3(p[2], 0, p[3])
				local ok = true
				for _, q in ipairs(picked) do
					if (q - pos).Magnitude < 2600 then ok = false break end
				end
				if ok then
					local poi = { id = "gas" .. (#picked + 1), kind = "gas", name = "Isan Fuel " .. (#picked + 1), thai = "ปั๊มน้ำมันอีสาน " .. (#picked + 1), at = pos, w = map.gasSize.w, d = map.gasSize.d }
					local base, e = placeNear(pos, poi.w, poi.d, notSoi)
					if base then buildPlace(poi, base, e); table.insert(picked, pos) end
				end
			end
		end
	end
	if world.pois.farm and world.pois.farm.allotments then
		for _, a in ipairs(world.pois.farm.allotments) do table.insert(world.farms, a) end
	end
	-- land for sale
	for _, g in ipairs(map.plotGroups) do
		local tier = Housing.TIERS[g.tier]
		for i = 1, g.count do
			local base = placeNear(g.at, tier.size.X + 6, tier.size.Y + 6, function(e) return e.type == "soi" or e.type == "street" end)
			if base then
				table.insert(world.plots, { id = g.tier:sub(1, 1):upper() .. i, tier = g.tier, base = base * CF(0, 0, 0) })
			else
				warn("[World] no room for plot " .. g.tier .. i)
			end
		end
	end
	task.wait()

	-----------------------------------------------------------------------------------------------
	-- street-front lots
	-----------------------------------------------------------------------------------------------
	local lots = {}
	local core2 = map.coreRadius * map.coreRadius
	local hero2 = (map.heroRadius or 1400) ^ 2
	local lite2 = (map.liteRadius or 2400) ^ 2
	local parkedDefs = {}
	for _, id in ipairs({ "sabai110", "zoomer125", "eco_city", "sedan_vios", "pickup_dmax", "suv_fortune", "oldmoped", "eco_city", "sedan_vios" }) do
		if Vehicles.ById[id] then table.insert(parkedDefs, Vehicles.ById[id]) end
	end
	for ei, e in ipairs(graph.edges) do
		local def = e.def
		local ta = e.a.deg >= 3 and e.a.trim + 3 or 3
		local tb = e.b.deg >= 3 and e.b.trim + 3 or 3
		local inCore = ((e.a.x + e.b.x) / 2 - center.X) ^ 2 + ((e.a.z + e.b.z) / 2 - center.Z) ^ 2 < core2
		for _, side in ipairs({ -1, 1 }) do
			local s = ta
			local stop = e.len - tb
			while s < stop do
				local remaining = stop - s
				local kind, w, d
				if e.type == "soi" then
					if inCore and planRng:NextNumber() < 0.42 then kind, w, d = "row", 52, 30 else kind, w, d = "house", 44, 40 end
				elseif e.type == "highway" and planRng:NextNumber() < 0.3 then
					kind, w, d = "bigbox", 120, 70
				else
					kind, w, d = "row", 78, 34
				end
				if w > remaining then
					if kind == "row" and remaining >= 40 then w = math.floor(remaining) else break end
				end
				local skip = kind == "house" and planRng:NextNumber() > (inCore and 0.8 or 0.6)
				local base, box, cx, cz = lotAt(e, s + w / 2, side, w, d)
				if skip then
					s += w
				elseif free(box) then
					reserve(box)
					table.insert(lots, { base = base, x = cx, z = cz, w = w, d = d, kind = kind, edge = e, core = inCore })
					s += w
				else
					s += 12
				end
			end
		end
		if ei % 500 == 0 then task.wait() end
	end

	-- partner shops on the lots nearest real restaurant / shop positions
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
	local function anchor(pos: Vector3, info)
		local best, bestD = nil, 700 * 700
		for _, lot in ipairs(lots) do
			if lot.kind == "row" and not lot.shop then
				local dd = (lot.x - pos.X) ^ 2 + (lot.z - pos.Z) ^ 2
				if dd < bestD then best, bestD = lot, dd end
			end
		end
		if best then best.shop = info end
		return best
	end
	local rn = map.restaurantNames
	for i, pos in ipairs(pickSpread("restaurant", map.restaurantCount, 620)) do
		local def = rn[(i - 1) % #rn + 1]
		anchor(pos, { id = "rest" .. i, kind = "restaurant", name = def[1], thai = def[2], menu = def[3], color = Color3.fromRGB(200, 70, 40) })
	end
	for i, pos in ipairs(pickSpread("convenience", map.convenienceCount, 900)) do
		anchor(pos, { id = "conv" .. i, kind = "convenience", name = "GoMart 24", thai = "โกมาร์ท 24", color = C.godash })
	end
	for i, pos in ipairs(pickSpread("cafe", map.cafeCount, 1200)) do
		anchor(pos, { id = "cafe" .. i, kind = "cafe", name = "Kaen Coffee", thai = "แก่นกาแฟ", color = Color3.fromRGB(120, 80, 50) })
	end

	local built = 0
	for li, lot in ipairs(lots) do
		local base = lot.base
		local zone = map.zoneAt(lot.x, lot.z).id
		local draw = near(lot.x, lot.z)
		local rng = vrng(lot.x, lot.z)
		if lot.kind == "row" then
			local shop = lot.shop
			-- level of detail: full facades in the hero district and for every named shop,
			-- lighter facades on the main streets of the core, simple terraces elsewhere
			local hero = (lot.x - center.X) ^ 2 + (lot.z - center.Z) ^ 2 < hero2
			local lite = lot.edge.type ~= "soi" and (lot.x - center.X) ^ 2 + (lot.z - center.Z) ^ 2 < lite2
			local detail = (hero or shop) and 2 or (lite and 1 or 0)
			local units = math.max(1, math.floor(lot.w / 15.5 + 0.5))
			local uw = lot.w / units
			local slotX = -lot.w / 2 + uw / 2 -- the named shop takes the first unit
			if draw then
				Kit.part(fBuild, V3(lot.w, 0.3, lot.d), base * CF(0, 0.15, 0), C.concrete, M.Concrete, { name = "LotPad", variant = "GD_ConcreteFloor" })
				if detail > 0 then
					Shophouse.row(fBuild, base * CF(0, 0.3, 0), lot.w, lot.d, rng, { shops = shop and { shop } or nil, lite = detail == 1,
						floors = (not lot.core) and rng:NextInteger(1, 3) or nil })
				else
					S.row(fBuild, base * CF(0, 0.3, 0), lot.w, lot.d, rng, { shops = shop and { shop } or nil, floors = (not lot.core) and rng:NextInteger(1, 3) or nil })
				end
				if detail == 2 then
					-- life on the pavement in front of each unit
					for u = 1, units do
						local ux = -lot.w / 2 + uw * (u - 0.5)
						local front = base * CF(ux, 0.3, -lot.d / 2 + 0.2)
						local r = rng:NextNumber()
						if shop and u == 1 then
							if shop.kind == "restaurant" then
								Life.tableSet(fProps, front * CF(uw * 0.9, 0, -1.6), rng)
								Life.pot(fProps, front * CF(-uw / 2 + 1.6, 0, -0.6), rng)
							else
								Life.pot(fProps, front * CF(uw / 2 - 1.4, 0, -0.6), rng)
							end
						elseif r < 0.22 then
							Life.pot(fProps, front * CF(rng:NextNumber(-uw / 3, uw / 3), 0, -0.6), rng)
						elseif r < 0.3 then
							S.parkedBikes(fBuild, front * CF(0, 0, -1.2), rng:NextInteger(1, 3), rng)
						elseif r < 0.36 then
							Life.foodCart(fProps, front * CF(0, 0.2, -2.2) * CFrame.Angles(0, rad(180), 0), rng, Life.CART_LABELS[rng:NextInteger(1, #Life.CART_LABELS)])
						elseif r < 0.42 then
							Life.tableSet(fProps, front * CF(0, 0, -1.8), rng)
						elseif r < 0.47 then
							Life.bin(fProps, front * CF(uw / 2 - 1.6, 0, -0.9), rng)
						end
					end
				elseif shop or rng:NextNumber() < 0.2 then
					S.parkedBikes(fBuild, base * CF(lot.w / 4, 0.3, -lot.d / 2 - 0.4), rng:NextInteger(2, 4), rng)
				end
				built += 1
			end
			if shop then
				local entry = {
					id = shop.id, kind = shop.kind, name = shop.name, thai = shop.thai, menu = shop.menu, zone = zone,
					pos = (base * CF(slotX, 3, -lot.d / 2 - 2)).Position, npc = base * CF(slotX + 4, 0.3, -lot.d / 2 + 0.3),
				}
				if shop.kind == "restaurant" then table.insert(world.restaurants, entry) end
				table.insert(world.shops, entry)
			end
			table.insert(world.addresses, { pos = (base * CF(-lot.w / 4, 0, -lot.d / 2 - 2)).Position, zone = zone, kind = "shop" })
			if lot.w >= 60 then
				table.insert(world.addresses, { pos = (base * CF(lot.w / 4, 0, -lot.d / 2 - 2)).Position, zone = zone, kind = "shop" })
			end
		elseif lot.kind == "bigbox" then
			if draw then S.bigbox(fBuild, base, lot.w, lot.d, rng); built += 1 end
			table.insert(world.addresses, { pos = (base * CF(0, 0, -lot.d / 2 - 2)).Position, zone = zone, kind = "office" })
		else
			if draw then S.house(fBuild, base, lot.w, lot.d, rng); built += 1 end
			table.insert(world.addresses, { pos = (base * CF(0, 0, -lot.d / 2 - 2)).Position, zone = zone, kind = "house" })
		end
		if li % 250 == 0 then task.wait() end
	end

	-----------------------------------------------------------------------------------------------
	-- street furniture
	-----------------------------------------------------------------------------------------------
	if emitAll then
		for ei, e in ipairs(graph.edges) do
			local def = e.def
			local mx, mz = (e.a.x + e.b.x) / 2, (e.a.z + e.b.z) / 2
			if e.type ~= "soi" and near(mx, mz) then
				local rng = vrng(mx, mz)
				local function spot(s: number, side: number, off: number): CFrame
					local nx, nz = -e.dz * side, e.dx * side
					local p = V3(e.a.x + e.dx * s + nx * off, 0, e.a.z + e.dz * s + nz * off)
					return CFrame.lookAt(p, p - V3(nx, 0, nz)) -- -Z looks at the road
				end
				local s0, s1 = e.a.trim + 10, e.len - e.b.trim - 10
				local i = 0
				for s = s0 + 20, s1, 150 do
					i += 1
					S.lamp(fProps, spot(s, i % 2 == 0 and 1 or -1, def.width / 2 + 1.6) * CF(0, 0.5, 0))
				end
				local lastTop
				for s = s0, s1, 115 do
					local top = S.pole(fProps, spot(s, -1, def.width / 2 + def.walk - 1) * CF(0, 0.5, 0) * CFrame.Angles(0, rad(90), 0))
					if lastTop then S.wire(fProps, lastTop, top) end
					lastTop = top
				end
				if e.type ~= "street" then
					for s = s0 + 60, s1, 130 do
						S.tree(fProps, spot(s, 1, def.width / 2 + def.walk - 1.8) * CF(0, 0.5, 0), rng, rng:NextNumber() < 0.3 and "palm" or "small")
					end
				end
				-- hero district: the small things on and beside the road
				if (mx - center.X) ^ 2 + (mz - center.Z) ^ 2 < hero2 then
					local along = CFrame.lookAt(V3(e.a.x, 0, e.a.z), V3(e.b.x, 0, e.b.z))
					for s = s0 + 30, s1, 64 do
						for _, side in ipairs({ -1, 1 }) do
							Life.grate(fProps, spot(s + (side > 0 and 20 or 0), side, def.width / 2 - 0.9) * CF(0, def.y, 0))
						end
					end
					for s = s0 + 70, s1, 230 do
						Life.manhole(fProps, (along * CF(rng:NextNumber(-def.width / 4, def.width / 4), def.y, -s)).Position)
						Life.patch(fProps, along * CF(rng:NextNumber(-def.width / 3, def.width / 3), def.y, -s - 60) * CFrame.Angles(0, rad(rng:NextNumber(-6, 6)), 0), rng)
					end
					for s = s0 + 46, s1, 190 do
						local side = rng:NextNumber() < 0.5 and 1 or -1
						local r = rng:NextNumber()
						if r < 0.35 then Life.cabinet(fProps, spot(s, side, def.width / 2 + def.walk - 1.4) * CF(0, 0.5, 0))
						elseif r < 0.7 then Life.trafficSign(fProps, spot(s, side, def.width / 2 + 1.2) * CF(0, 0.5, 0) * CFrame.Angles(0, rad(side > 0 and 90 or -90), 0), ({ "limit", "noparking", "noparking", "oneway" })[rng:NextInteger(1, 4)])
						else Life.bin(fProps, spot(s, side, def.width / 2 + def.walk - 1.6) * CF(0, 0.5, 0), rng) end
					end
					-- parked cars and bikes along the kerb
					for s = s0 + 110, s1 - 30, 210 do
						if rng:NextNumber() < 0.75 then
							local side = rng:NextNumber() < 0.5 and 1 or -1
							local vdef = parkedDefs[rng:NextInteger(1, #parkedDefs)]
							local nx, nz = -e.dz * side, e.dx * side
							local off = def.width / 2 - (vdef.class == "bike" and 1.6 or 4.2)
							local p = V3(e.a.x + e.dx * s + nx * off, def.y + vdef.wheelR + 0.9, e.a.z + e.dz * s + nz * off)
							local model = VehicleFactory.display(vdef, CFrame.lookAt(p, p + V3(e.dx, 0, e.dz) * -side), rng:NextInteger(1, 8))
							model.Name = "Parked"
							model.Parent = fProps
						end
					end
				end
			end
			if ei % 300 == 0 then task.wait() end
		end
		-- traffic lights where big roads meet
		for _, n in ipairs(graph.nodes) do
			if n.deg >= 3 and n.r >= 20 and near(n.x, n.z) then
				local bigLinks = 0
				for _, l in ipairs(n.links) do
					if l.edge.type ~= "soi" then bigLinks += 1 end
				end
				local signal = select(2, Traffic.signals(graph))[n.id]
				if bigLinks >= 3 and signal then
					-- one working signal per approach: on the kerb to the driver's right, arm over the road, lamps facing the driver
					for _, l in ipairs(n.links) do
						if l.edge.type ~= "soi" then
							local e = l.edge
							local sgn = e.a == n and 1 or -1
							local dx, dz = e.dx * sgn, e.dz * sgn
							local p = V3(n.x + dx * (n.r + 4) + dz * (e.def.width / 2 + 2), 0.5, n.z + dz * (n.r + 4) - dx * (e.def.width / 2 + 2))
							local sm = Kit.model(fProps, "Signal")
							sm:SetAttribute("Node", n.id)
							sm:SetAttribute("Group", signal.groups[e])
							sm:AddTag("TrafficSignal")
							S.trafficLight(sm, CFrame.lookAt(p, p + V3(-dz, 0, dx)))
							-- stop line
							local stop = V3(n.x + dx * (n.r + 9), 0, n.z + dz * (n.r + 9))
							Kit.part(sm, V3(e.def.width - 2, 0.05, 1), CFrame.lookAt(stop, stop + V3(dx, 0, dz)) * CF(0, e.def.y + 0.03, 0), C.line, M.SmoothPlastic, { decor = true, name = "StopLine" })
						end
					end
				end
			end
			-- blue road-name signs at junctions in the hero district
			if n.deg >= 3 and near(n.x, n.z) and (n.x - center.X) ^ 2 + (n.z - center.Z) ^ 2 < hero2 then
				local named = {}
				for _, l in ipairs(n.links) do
					local e = l.edge
					if e.name ~= "" and not named[e.name] then
						named[e.name] = true
						table.insert(named, e)
					end
				end
				if #named >= 1 then
					local a, b = named[1], named[2]
					local corner = V3(n.x + (n.r + n.walk + 2) * 0.72, 0.5, n.z + (n.r + n.walk + 2) * 0.72)
					Life.roadName(fProps, CFrame.lookAt(corner, corner + V3(a.dz, 0, -a.dx)), a.thai ~= "" and a.thai or a.name, a.name,
						b and (b.thai ~= "" and b.thai or b.name) or nil, b and b.name or nil)
				end
			end
		end
	end

	-- bus stops beside the places people travel between
	for _, id in ipairs({ "hub", "mall", "station", "nightmarket", "bus", "stupa", "agri", "hospital" }) do
		local poi = world.pois[id]
		if poi then
			local e, p = graph:nearest(poi.door, notSoi)
			if e then
				local toPoi = V3(poi.door.X - p.X, 0, poi.door.Z - p.Z)
				local nx, nz = -e.dz, e.dx
				if toPoi.X * nx + toPoi.Z * nz < 0 then nx, nz = -nx, -nz end
				local at = p + V3(nx, 0, nz) * (e.def.width / 2 + math.max(e.def.walk, 4) / 2 + 1)
				local base = CFrame.lookAt(at, at - V3(nx, 0, nz))
				if near(at.X, at.Z) then S.busStop(fProps, base * CF(0, 0.5, 0)) end
				table.insert(world.busStops, { id = "b_" .. id, name = poi.name, thai = poi.thai, pos = (base * CF(0, 3, -1)).Position })
			end
		end
	end

	-----------------------------------------------------------------------------------------------
	-- filler inside blocks
	-----------------------------------------------------------------------------------------------
	local fillCount = 0
	local sampleN = 0
	for x = bounds.minX + 60, bounds.maxX - 60, 104 do
		for z = bounds.minZ + 60, bounds.maxZ - 60, 104 do
			sampleN += 1
			local jx, jz = x + planRng:NextNumber(-20, 20), z + planRng:NextNumber(-20, 20)
			local roll = planRng:NextNumber()
			local inCore = (jx - center.X) ^ 2 + (jz - center.Z) ^ 2 < core2
			if inCore and roll < 0.34 then
				local o = obb(jx, jz, 1, 0, 22, 22)
				if free(o) then
					reserve(o)
					if near(jx, jz) then
						local rng = vrng(jx, jz)
						Kit.part(fBuild, V3(44, 0.3, 44), CF(jx, 0.15, jz), C.concrete, M.Concrete, { name = "LotPad" })
						S.tower(fBuild, CF(jx, 0.3, jz) * CFrame.Angles(0, rad(90 * rng:NextInteger(0, 1)), 0), rng:NextInteger(26, 36), rng:NextInteger(24, 32), rng)
						fillCount += 1
					end
				end
			elseif roll < 0.62 then
				local o = obb(jx, jz, 1, 0, 20, 20)
				if free(o) then
					reserve(o)
					if near(jx, jz) then
						local rng = vrng(jx, jz)
						S.house(fBuild, CF(jx, 0, jz) * CFrame.Angles(0, rad(90 * rng:NextInteger(0, 3)), 0), 40, 40, rng)
						fillCount += 1
					end
				end
			elseif roll < 0.9 then
				local o = obb(jx, jz, 1, 0, 5, 5)
				if free(o) and near(jx, jz) then
					local rng = vrng(jx, jz)
					S.tree(fProps, CF(jx, 0, jz), rng, ({ "rain", "small", "palm", "banana", "small" })[rng:NextInteger(1, 5)])
				end
			end
		end
		if sampleN % 600 < 131 then task.wait() end
	end

	world.buildSeconds = os.clock() - t0
	world.lots = #lots
	local parts = 0
	if emitAll then
		for _, dsc in ipairs(root:GetDescendants()) do
			if dsc:IsA("BasePart") then parts += 1 end
		end
		root:SetAttribute("Built", true)
		root:SetAttribute("Partial", radius ~= nil)
	else
		root:Destroy()
	end
	world.partCount = parts
	print(("[World] %s %s in %.2fs: %d parts, %d nodes, %d edges, %d lots (%d drawn), %d addresses, %d restaurants, %d shops, %d plots, %d farms")
		:format(map.name, emitAll and "built" or "planned", world.buildSeconds, parts, #graph.nodes, #graph.edges, #lots, built, #world.addresses,
			#world.restaurants, #world.shops, #world.plots, #world.farms))
	return world
end

return Builder
