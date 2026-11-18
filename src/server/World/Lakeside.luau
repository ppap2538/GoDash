-- Lakeside promenades (2026-11-18, owner: "Bueng Kaen Nakhon: the walk round the lake, people jogging in
-- the evening, the stalls by the water, the thing every Khon Kaen person thinks of").
--
-- Every big lake (OpenStreetMap outline wider than 900 studs) gets a red jogging path just back from its
-- stone rim, wherever the land there is free (a road, a landmark or land a player can own wins), with
-- benches facing the water and shade trees. The named lakes also get a name sign; Bueng Kaen Nakhon and
-- Bueng Thung Sang get a row of food stalls (the evening market by the water), an outdoor gym and a
-- wooden pier with swan pedal boats. world.lakes lists each path for the joggers (client/Peds) and
-- the lake sounds (client/Ambience). Drawn by the Streamer, so it only costs anything near a player.
-- Order: the path first, then the sign / stalls / gym / pier pick their spots, then benches and trees.
local Kit = require(script.Parent.Kit)
local S = require(script.Parent.Scenery)

local M = Kit.M
local C = Kit.COLORS
local V3 = Vector3.new
local CF = CFrame.new
local rad = math.rad

local Lakeside = {}

local OFF = 8 -- centre of the path, studs back from the shoreline
local WIDTH = 8
local PATH_COL = Color3.fromRGB(176, 104, 82) -- red rubber jogging track
local EDGE_COL = Color3.fromRGB(214, 208, 196)
local BIG_FEATURES = { ["Bueng Kaen Nakhon"] = true, ["Bueng Thung Sang"] = true }
local STALLS = { "ส้มตำ", "ไก่ย่าง", "ลูกชิ้นปิ้ง", "น้ำปั่น", "ข้าวเหนียวมะม่วง", "หมูปิ้ง", "ข้าวโพดปิ้ง", "ชาไทย" }
local PASS = { water = true, park = true } -- what the path may lie over

-- A lake mapped as a multipolygon arrives as several outer ways, each closed here by a straight line
-- across the water: that closing edge is not a shore (no rim, no path along it).
function Lakeside.isOpen(pts): boolean
	local n = #pts // 2
	if n < 3 then return true end
	local per = 0
	for i = 2, n do
		per += math.sqrt((pts[i * 2 - 1] - pts[i * 2 - 3]) ^ 2 + (pts[i * 2] - pts[i * 2 - 2]) ^ 2)
	end
	local gap = math.sqrt((pts[1] - pts[n * 2 - 1]) ^ 2 + (pts[2] - pts[n * 2]) ^ 2)
	return gap > 400 or gap > per * 0.25
end

local function drawSign(parent: Instance, at: Vector3, out: Vector3, thai: string, name: string, vrng)
	local m = Kit.model(parent, "LakeSign")
	local cf = CFrame.lookAt(at, at - out) -- faces the lake: read from the path and from the water
	Kit.part(m, V3(30, 1.2, 6), cf * CF(0, 0.6, 0), Color3.fromRGB(196, 176, 150), M.Brick, { name = "Plinth" })
	local wall = Kit.part(m, V3(28, 6.4, 1.6), cf * CF(0, 4.4, 0.8), Color3.fromRGB(236, 228, 210), M.Concrete, { name = "SignWall" })
	Kit.sign(wall, thai, { sub = string.upper(name), color = Color3.fromRGB(26, 84, 70), maxDistance = 420, pps = 18 })
	Kit.sign(wall, thai, { sub = string.upper(name), color = Color3.fromRGB(26, 84, 70), face = Enum.NormalId.Back, maxDistance = 420, pps = 18 })
	local rng = vrng(at.X, at.Z)
	-- flowers at the two ends of the wall and low along its foot behind it: the name stays readable
	for _, sx in ipairs({ -1, 1 }) do S.tree(m, cf * CF(sx * 17.5, 0.2, 0.6), rng, "flower") end
	for k = -1, 1 do S.tree(m, cf * CF(k * 9, 1.2, 2.4), rng, "bush") end
	local glow = Kit.part(m, V3(27, 0.4, 0.3), cf * CF(0, 1.4, -0.1), Color3.fromRGB(255, 226, 170), M.SmoothPlastic, { decor = true })
	Kit.nightLight(glow, 26, Color3.fromRGB(255, 220, 170), 1.4)
	Kit.nightGlow(glow)
end

local function drawGym(parent: Instance, at: Vector3, out: Vector3)
	local m = Kit.model(parent, "OutdoorGym")
	local cf = CFrame.lookAt(at, at - out)
	Kit.part(m, V3(18, 0.3, 11), cf * CF(0, 0.15, 0), Color3.fromRGB(70, 140, 110), M.SmoothPlastic, { name = "GymMat" })
	local yel, blu = Color3.fromRGB(250, 190, 40), Color3.fromRGB(40, 110, 200)
	for kx = -1, 1 do
		local b = cf * CF(kx * 5.5, 0, 0)
		Kit.cyl(m, 0.6, 7, b * CF(-1.6, 3.5, 0), kx == 0 and blu or yel, M.Metal)
		Kit.cyl(m, 0.6, 7, b * CF(1.6, 3.5, 0), kx == 0 and blu or yel, M.Metal)
		Kit.part(m, V3(3.8, 0.4, 0.4), b * CF(0, 6.8, 0), kx == 0 and yel or blu, M.Metal, { decor = true })
	end
end

local function drawPier(parent: Instance, shore: Vector3, out: Vector3, vrng)
	local m = Kit.model(parent, "Pier")
	local cf = CFrame.lookAt(shore, shore - out) -- -Z out over the water
	Kit.part(m, V3(7, 0.6, 34), cf * CF(0, 1.6, -15), C.wood, M.WoodPlanks, { name = "PierDeck" })
	for z = -2, -30, -7 do
		for _, sx in ipairs({ -3, 3 }) do Kit.cyl(m, 0.7, 4, cf * CF(sx, 0, z), C.woodDark, M.Wood, { decor = true }) end
	end
	for _, sx in ipairs({ -3.3, 3.3 }) do Kit.part(m, V3(0.3, 2.4, 34), cf * CF(sx, 3, -15), C.woodDark, M.Wood, { decor = true }) end
	local rng = vrng(shore.X, shore.Z)
	local white = Color3.fromRGB(246, 246, 242)
	-- (2026-11-19) the swans are rideable now (server/BoatService puts two beside each pier, out past the
	-- shore: tied-up decor swans here overlapped them and the stone rim and jammed them). Loop kept empty.
	for b = 2, 1 do
		local side = b % 2 == 0 and -1 or 1
		local bc = cf * CF(side * 8.5, 0.6, -8 - (b // 2) * 11) * CFrame.Angles(0, rad(rng:NextNumber(-12, 12)), 0)
		-- a swan pedal boat: a fat white tube half in the water, raised tail, red seat, neck and head
		Kit.cyl(m, 4.6, 8, bc * CF(0, 0.3, 0) * CFrame.Angles(rad(90), 0, 0), white, M.SmoothPlastic, { decor = true, name = "SwanBoat" })
		Kit.wedge(m, V3(4.4, 2.6, 2.6), bc * CF(0, 2.6, 3.4) * CFrame.Angles(0, rad(180), 0), white, M.SmoothPlastic, { decor = true })
		Kit.part(m, V3(3.8, 1.4, 3.4), bc * CF(0, 2.6, 0.6), Color3.fromRGB(220, 80, 70), M.SmoothPlastic, { decor = true })
		Kit.cyl(m, 0.9, 5, bc * CF(0, 3, -3.4) * CFrame.Angles(rad(-18), 0, 0), white, M.SmoothPlastic, { decor = true })
		Kit.ball(m, 1.8, bc * CF(0, 5.4, -4.4), white, M.SmoothPlastic, { decor = true })
		Kit.part(m, V3(0.5, 0.5, 1.2), bc * CF(0, 5.3, -5.6), Color3.fromRGB(240, 150, 40), M.SmoothPlastic, { decor = true })
	end
end

function Lakeside.plan(ctx)
	local map, world = ctx.map, ctx.world
	local emit, obb, reserve, cells, overlap, gridS = ctx.emit, ctx.obb, ctx.reserve, ctx.cells, ctx.overlap, ctx.gridS
	world.lakes = {}
	local function blocked(o): boolean
		if not ctx.inBounds(o) then return true end
		for _, k in ipairs(cells(o)) do
			local list = gridS[k]
			if list then
				for _, other in ipairs(list) do
					if not PASS[other.kind] and overlap(o, other) then return true end
				end
			end
		end
		return ctx.onPlot ~= nil and ctx.onPlot(o)
	end
	-- free dry land for something beside the path (bench, stall, tree, sign): reserves it
	local function spotFree(x: number, z: number, ux: number, uz: number, hw: number, hd: number): boolean
		local o = obb(x, z, ux, uz, hw, hd, "lakeside")
		if blocked(o) then return false end
		for _, k in ipairs(cells(o)) do
			local list = gridS[k]
			if list then
				for _, other in ipairs(list) do
					if other.kind == "water" and overlap(o, other) then return false end
				end
			end
		end
		reserve(o)
		return true
	end

	-- a lake split into several pieces gets its sign and stalls on its longest piece only
	local longest = {}
	for wi, w in ipairs(map.features.water) do
		local per = 0
		for i = 2, #w.pts // 2 do
			per += math.sqrt((w.pts[i * 2 - 1] - w.pts[i * 2 - 3]) ^ 2 + (w.pts[i * 2] - w.pts[i * 2 - 2]) ^ 2)
		end
		if w.name ~= "" and (not longest[w.name] or per > longest[w.name].per) then longest[w.name] = { wi = wi, per = per } end
	end

	for wi, w in ipairs(map.features.water) do
		local pts = w.pts
		local n = #pts // 2
		local open = Lakeside.isOpen(pts)
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		local area = 0
		for i = 1, n do
			local j = i % n + 1
			local x1, z1, x2, z2 = pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2]
			minX = math.min(minX, x1); maxX = math.max(maxX, x1); minZ = math.min(minZ, z1); maxZ = math.max(maxZ, z1)
			area += x1 * z2 - x2 * z1
		end
		if (maxX - minX) > 900 or (maxZ - minZ) > 900 then
			local sgn = area > 0 and 1 or -1 -- outward normal of edge (dx, dz) is sgn * (dz, -dx)
			-- 1. the path's centre line: each shore point pushed out along the mean of its two edge normals
			local path, normals, outs = {}, {}, {}
			for i = 1, n do
				local h = (i - 2) % n + 1
				local j = i % n + 1
				local ax, az = pts[i * 2 - 1] - pts[h * 2 - 1], pts[i * 2] - pts[h * 2]
				local bx, bz = pts[j * 2 - 1] - pts[i * 2 - 1], pts[j * 2] - pts[i * 2]
				local la, lb = math.max(math.sqrt(ax * ax + az * az), 0.01), math.max(math.sqrt(bx * bx + bz * bz), 0.01)
				local nx = sgn * (az / la + bz / lb)
				local nz = sgn * (-ax / la - bx / lb)
				local nl = math.max(math.sqrt(nx * nx + nz * nz), 0.01)
				nx, nz = nx / nl, nz / nl
				normals[i] = { nx, nz }
				outs[i] = V3(nx, 0, nz)
				path[i] = V3(pts[i * 2 - 1] + nx * OFF, 0, pts[i * 2] + nz * OFF)
			end
			local main = longest[w.name] ~= nil and longest[w.name].wi == wi
			local thai = main and map.lakeNames and map.lakeNames[w.name] or nil
			local big = main and BIG_FEATURES[w.name] == true
			-- the path in pieces of at most 40 studs; each piece is laid where its own land is free.
			-- okList = the laid pieces in order round the lake (the sign, stalls, gym, pier, benches and
			-- trees are placed beside them)
			local firstOk, lastOk = {}, {}
			local okList = {}
			for i = 1, n do
				local j = i % n + 1
				local a, b = path[i], path[j]
				local d = b - a
				local len = d.Magnitude
				if open and i == n then len = 0 end -- the closing line across the water
				if len > 1 then
					local u = d / len
					local np = math.max(1, math.ceil(len / 40))
					local plen = len / np
					local out = V3(sgn * u.Z, 0, -sgn * u.X) -- away from the water
					for k = 0, np - 1 do
						local pa = a + d * (k / np)
						local pb = a + d * ((k + 1) / np)
						local mid = (pa + pb) / 2
						local o = obb(mid.X, mid.Z, u.X, u.Z, plen / 2 + 0.3, WIDTH / 2, "promenade")
						local ok = not blocked(o)
						if k == 0 then firstOk[i] = ok end
						if k == np - 1 then lastOk[i] = ok end
						if ok then
							reserve(o)
							table.insert(okList, { mid = mid, u = u, out = out, len = plen, i = i })
							emit(mid.X, mid.Z, function(parent)
								local cf = CFrame.lookAt(mid, pb) * CF(0, 0.2, 0)
								Kit.part(parent, V3(WIDTH, 0.3, plen + 0.6), cf, PATH_COL, M.Concrete, { name = "Promenade", variant = "GD_ConcreteFloor" })
								for _, sx in ipairs({ -1, 1 }) do
									Kit.part(parent, V3(0.6, 0.36, plen + 0.6), cf * CF(sx * (WIDTH / 2 + 0.3), 0.03, 0), EDGE_COL, M.Concrete, { decor = true })
								end
							end)
						end
					end
				end
			end
			local pieces = #okList
			-- joints so the corners of the path have no gaps
			for i = 1, n do
				local h = (i - 2) % n + 1
				if firstOk[i] and lastOk[h] then
					local p = path[i]
					emit(p.X, p.Z, function(parent)
						Kit.cyl(parent, WIDTH, 0.3, CF(p.X, 0.2, p.Z), PATH_COL, M.Concrete, { decor = true, variant = "GD_ConcreteFloor" })
					end)
				end
			end
			-- the path for joggers (client/Peds): every vertex, in order round the lake
			local flat = table.create(n * 2)
			for i = 1, n do
				flat[i * 2 - 1] = math.floor(path[i].X + 0.5)
				flat[i * 2] = math.floor(path[i].Z + 0.5)
			end
			local entry = { name = w.name ~= "" and w.name or "Lake", thai = thai, path = flat, open = open, x = (minX + maxX) / 2, z = (minZ + maxZ) / 2,
				pieces = pieces }
			table.insert(world.lakes, entry)

			-- 2. the town side of a named lake: name sign, then (big lakes) stalls, gym and pier nearby
			local P = #okList
			if thai and P > 0 then
				local order = table.create(P)
				for k = 1, P do order[k] = k end
				table.sort(order, function(p, q) return (okList[p].mid - map.center).Magnitude < (okList[q].mid - map.center).Magnitude end)
				local base
				for ci = 1, math.min(P, 90) do
					local pc = okList[order[ci]]
					for _, off in ipairs({ WIDTH / 2 + 6, WIDTH / 2 + 10, WIDTH / 2 + 15, WIDTH / 2 + 22 }) do
						local at = pc.mid + pc.out * off
						if spotFree(at.X, at.Z, pc.u.X, pc.u.Z, 15, 3.4) then
							base = order[ci]
							entry.sign = { x = at.X, z = at.Z }
							local out = pc.out
							emit(at.X, at.Z, function(parent) drawSign(parent, at, out, thai, w.name, ctx.vrng) end)
							break
						end
					end
					if base then break end
				end
				base = base or order[1]
				if big then
					-- the evening food stalls along the path, walking away from the sign both ways
					local placed = 0
					for step = 1, 30 do
						for _, dir in ipairs({ 1, -1 }) do
							local pc = okList[((base - 1 + dir * step) % P) + 1]
							if placed < 6 then
								for _, off in ipairs({ WIDTH / 2 + 4.6, WIDTH / 2 + 8, WIDTH / 2 + 12 }) do
									local at = pc.mid + pc.out * off
									if spotFree(at.X, at.Z, pc.u.X, pc.u.Z, 4.6, 2.6) then
										placed += 1
										local label = STALLS[(placed - 1) % #STALLS + 1]
										local o2 = pc.out
										emit(at.X, at.Z, function(parent) S.stall(parent, CFrame.lookAt(at, at - o2), ctx.vrng(at.X, at.Z), label) end)
										break
									end
								end
							end
						end
						if placed >= 6 then break end
					end
					entry.stalls = placed
					-- an outdoor gym one way round from the sign, the pier the other way
					for step = 10, 80 do
						local pc = okList[((base - 1 - step) % P) + 1]
						local gm = pc.mid + pc.out * (WIDTH / 2 + 7)
						if spotFree(gm.X, gm.Z, pc.u.X, pc.u.Z, 9, 5.6) then
							entry.gym = { x = gm.X, z = gm.Z }
							local o3 = pc.out
							emit(gm.X, gm.Z, function(parent) drawGym(parent, gm, o3) end)
							break
						end
					end
					for step = 8, 80 do
						local pc = okList[((base - 1 + step) % P) + 1]
						local shore = pc.mid - pc.out * OFF
						-- the deck runs from the path out over open water: nothing there but the lake
						local deck = obb(shore.X - pc.out.X * 15, shore.Z - pc.out.Z * 15, pc.out.X, pc.out.Z, 17, 9, "pier")
						if not blocked(deck) then
							entry.pier = { x = shore.X, z = shore.Z, ox = pc.out.X, oz = pc.out.Z } -- out = away from the water (server/FestivalService)
							local pn = pc.out
							emit(shore.X, shore.Z, function(parent) drawPier(parent, shore, pn, ctx.vrng) end)
							break
						end
					end
				end
			end

			-- 3. benches facing the water and shade trees behind the path, on what land is left
			local benchAcc, treeAcc = 40, 20
			for _, pc in ipairs(okList) do
				benchAcc += pc.len
				treeAcc += pc.len
				local out = pc.out
				if benchAcc > 95 then
					local m = pc.mid + out * (WIDTH / 2 + 2.4)
					if spotFree(m.X, m.Z, pc.u.X, pc.u.Z, 3.4, 1.6) then
						benchAcc = 0
						emit(m.X, m.Z, function(parent) S.bench(parent, CFrame.lookAt(m, m - out) * CF(0, 0.3, 0)) end)
					end
				end
				if treeAcc > 62 then
					local m = pc.mid + out * (WIDTH / 2 + 9)
					if spotFree(m.X, m.Z, 1, 0, 3, 3) then
						treeAcc = 0
						emit(m.X, m.Z, function(parent)
							local rng = ctx.vrng(m.X, m.Z)
							S.tree(parent, CF(m.X, 0.2, m.Z), rng, ({ "rain", "koon", "small", "koon", "palm" })[rng:NextInteger(1, 5)])
						end)
					end
				end
			end
		end
	end
end

return Lakeside
