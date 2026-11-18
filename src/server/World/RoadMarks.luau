-- Road markings and roundabouts (2026-11-18, owner: "roundabouts, zebra crossings, markings at the
-- soi mouths; stop for people at the crossing or get fined").
--
--   RoadMarks.zebra(parent, cf, width, depth)  white bars across a road (cf: road centre at the road's
--                                              surface, local Z along the road, X across it)
--   RoadMarks.plan(ctx)                         called by the Builder after the roads are reserved:
--     * roundabout islands where OpenStreetMap has a real ring (Config/Maps/<map>.roundabouts), reserved
--       so no lot or infill lands inside the ring
--     * a zebra crossing in front of every school, hospital and university gate, with signs; listed in
--       world.zebras for the crossing people (client/Peds) and the fine (server/TrafficService)
--     * a white stop line across every soi / lane where it meets a bigger street
-- Everything visible is registered with the Streamer (drawn only near players).
local Kit = require(script.Parent.Kit)
local S = require(script.Parent.Scenery)
local RoadGraph = require(game:GetService("ReplicatedStorage").Shared.RoadGraph)

local M = Kit.M
local C = Kit.COLORS
local V3 = Vector3.new
local CF = CFrame.new
local rad = math.rad

local RoadMarks = {}
local WHITE = Color3.fromRGB(242, 242, 238)

function RoadMarks.zebra(parent: Instance, cf: CFrame, width: number, depth: number)
	local bar, gap = 1.6, 1.4
	local n = math.max(2, math.floor((width - 1 + gap) / (bar + gap)))
	local span = n * bar + (n - 1) * gap
	for i = 0, n - 1 do
		local x = -span / 2 + bar / 2 + i * (bar + gap)
		Kit.part(parent, V3(bar, 0.06, depth), cf * CF(x, 0.03, 0), WHITE, M.SmoothPlastic, { decor = true, name = "Zebra" })
	end
end

-- Blue square "pedestrian crossing" sign on a post; cf stands on the pavement, -Z toward the road.
function RoadMarks.crossingSign(parent: Instance, cf: CFrame, school: boolean?)
	Kit.cyl(parent, 0.4, 9.5, cf * CF(0, 4.75, 0), Color3.fromRGB(150, 156, 162), M.Metal, { decor = true })
	local blue = Color3.fromRGB(24, 82, 176)
	local board = Kit.part(parent, V3(3, 3, 0.15), cf * CF(0, 8.4, -0.3), blue, M.SmoothPlastic, { decor = true })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do -- read from both directions
		Kit.sign(board, "🚶", { sub = "ทางข้าม", bg = blue, face = face, maxDistance = 140, pps = 36 })
	end
	if school then
		local y = Color3.fromRGB(250, 200, 30)
		local plate = Kit.part(parent, V3(3, 1.3, 0.15), cf * CF(0, 6.2, -0.3), y, M.SmoothPlastic, { decor = true })
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			Kit.sign(plate, "เขตโรงเรียน ขับช้าๆ", { color = Color3.fromRGB(30, 30, 30), bg = y, face = face, maxDistance = 120, pps = 30 })
		end
	end
end

-- yellow-and-white painted kerb edge beside a crossing (no stopping): flat paint along local Z
local function paintedKerb(parent: Instance, cf: CFrame, len: number)
	local n = math.max(1, math.floor(len / 3))
	for i = 0, n - 1 do
		local z = -len / 2 + (i + 0.5) * (len / n)
		Kit.part(parent, V3(0.7, 0.05, len / n), cf * CF(0, 0.025, z), i % 2 == 0 and Color3.fromRGB(240, 196, 30) or WHITE, M.SmoothPlastic, { decor = true })
	end
end

local CROSS_AT = { school = true, hospital = true, university = true }

function RoadMarks.plan(ctx)
	local graph, map, world = ctx.graph, ctx.map, ctx.world
	local emit, obb, reserve, hit, gridS = ctx.emit, ctx.obb, ctx.reserve, ctx.hit, ctx.gridS
	world.zebras = {}
	world.roundabouts = 0

	-------------------------------------------------------------------------------------------------
	-- roundabout islands
	-------------------------------------------------------------------------------------------------
	for _, rb in ipairs(map.roundabouts or {}) do
		local centre = V3(rb.x, 0, rb.z)
		local ring, inner, width = 0, 0, 0
		for _, e in ipairs(graph:edgesNear(centre, rb.r * 1.6 + 30)) do
			local mx, mz = (e.a.x + e.b.x) / 2, (e.a.z + e.b.z) / 2
			local d = math.sqrt((mx - rb.x) ^ 2 + (mz - rb.z) ^ 2)
			if d > rb.r * 0.55 and d < rb.r * 1.3 then
				ring += 1
				width = math.max(width, e.def.width)
			end
			-- a street running through the middle: this ring did not make it into the graph as a ring
			local _, _, _, dd = RoadGraph.project(e, rb.x, rb.z)
			if dd < (rb.r * 0.45) ^ 2 then inner += 1 end
		end
		local islandR = rb.r - width / 2 - 1.2
		if ring >= 3 and inner == 0 and islandR >= 5 then
			local box = obb(rb.x, rb.z, 1, 0, islandR * 0.7, islandR * 0.7, "island")
			local blocker = hit(gridS, box)
			if not blocker or blocker.kind == "road" then
				-- keep the whole disc free of lots and infill: an octagon of two squares (0 and 45 degrees)
				local s2 = math.sqrt(0.5)
				reserve(obb(rb.x, rb.z, 1, 0, islandR * 0.97, islandR * 0.97, "island"))
				reserve(obb(rb.x, rb.z, s2, s2, islandR * 0.97, islandR * 0.97, "island"))
				world.roundabouts += 1
				emit(rb.x, rb.z, function(parent)
					local rng = ctx.vrng(rb.x, rb.z)
					local m = Kit.model(parent, "Roundabout")
					local base = CF(rb.x, 0, rb.z)
					-- kerb ring in red and white blocks, grass on top
					local segs = math.clamp(math.floor(islandR * 2 * math.pi / 6), 10, 48)
					for i = 0, segs - 1 do
						local a = (i + 0.5) / segs * math.pi * 2
						local len = islandR * 2 * math.pi / segs + 0.3
						Kit.part(m, V3(1.2, 1, len), base * CFrame.Angles(0, -a, 0) * CF(islandR - 0.6, 0.5, 0) , i % 2 == 0 and Color3.fromRGB(200, 44, 40) or WHITE, M.Concrete, { name = "Kerb" })
					end
					Kit.cyl(m, (islandR - 1.1) * 2, 0.9, base * CF(0, 0.45, 0), Color3.fromRGB(110, 156, 80), M.Grass, { name = "IslandLawn", variant = "GD_Grass" })
					-- a ring of flowers
					local nf = math.clamp(math.floor(islandR / 3), 4, 18)
					for i = 0, nf - 1 do
						local a = (i + rng:NextNumber(0, 0.4)) / nf * math.pi * 2
						local fr = islandR - 3.6
						S.tree(m, base * CF(math.cos(a) * fr, 0.9, math.sin(a) * fr), rng, rng:NextNumber() < 0.6 and "flower" or "bush")
					end
					if islandR >= 28 then
						-- a fountain in a round basin, four palms around it
						Kit.cyl(m, 26, 2.2, base * CF(0, 1.1, 0), Color3.fromRGB(214, 206, 190), M.Concrete, { name = "Basin" })
						Kit.cyl(m, 23.6, 0.4, base * CF(0, 2.05, 0), C.water, M.SmoothPlastic, { decor = true, reflectance = 0.25 })
						Kit.cyl(m, 6, 4, base * CF(0, 3.6, 0), Color3.fromRGB(224, 216, 200), M.Concrete, { decor = true })
						for k = 0, 5 do
							local a = k / 6 * math.pi * 2
							Kit.cyl(m, 1.2, 9, base * CF(math.cos(a) * 6.5, 6, math.sin(a) * 6.5) * CFrame.Angles(math.cos(a) * 0.25, 0, -math.sin(a) * 0.25), Color3.fromRGB(196, 228, 246), M.Glass, { decor = true, transparency = 0.45 })
						end
						Kit.cyl(m, 1.6, 14, base * CF(0, 10, 0), Color3.fromRGB(196, 228, 246), M.Glass, { decor = true, transparency = 0.4 })
						for k = 0, 3 do
							local a = (k + 0.5) / 4 * math.pi * 2
							S.tree(m, base * CF(math.cos(a) * (islandR * 0.62), 0.9, math.sin(a) * (islandR * 0.62)), rng, "palm")
						end
					elseif islandR >= 12 then
						-- Khon Kaen's own flower: a golden-shower tree (ราชพฤกษ์) in the middle
						S.tree(m, base * CF(0, 0.9, 0), rng, "koon", { maxR = islandR - 1.5 }) -- its canopy stays over the island, not the lanes
						Kit.cyl(m, 7, 1.2, base * CF(0, 1.5, 0), Color3.fromRGB(214, 206, 190), M.Concrete, { decor = true })
					else
						S.tree(m, base * CF(0, 0.9, 0), rng, "bush")
					end
				end)
			end
		end
	end

	-------------------------------------------------------------------------------------------------
	-- zebra crossings in front of schools, hospitals and university gates
	-------------------------------------------------------------------------------------------------
	local notBig = function(e) return e.type ~= "highway" and e.len > 50 end
	for id, poi in pairs(world.pois) do
		if CROSS_AT[poi.kind] and poi.door then
			local e, p = graph:nearest(poi.door, notBig)
			if e and p and (p - V3(poi.door.X, 0, poi.door.Z)).Magnitude < 120 then
				local s = (p.X - e.a.x) * e.dx + (p.Z - e.a.z) * e.dz
				local lo, hi = e.a.r + 16, e.len - e.b.r - 16
				if hi > lo then
					s = math.clamp(s, lo, hi)
					local x, z = e.a.x + e.dx * s, e.a.z + e.dz * s
					local school = poi.kind == "school"
					table.insert(world.zebras, { id = id, kind = poi.kind, x = x, z = z, dx = e.dx, dz = e.dz, w = e.def.width, walk = e.def.walk, y = e.def.y, school = school })
					local def = e.def
					emit(x, z, function(parent)
						local m = Kit.model(parent, "Crossing")
						local mid = V3(x, 0, z)
						local along = CFrame.lookAt(mid, mid + V3(e.dx, 0, e.dz)) -- local -Z along the road
						RoadMarks.zebra(m, along * CF(0, def.y, 0), def.width - 1, 6)
						for _, sz in ipairs({ -1, 1 }) do
							-- give-way lines either side, and the painted kerb that says "don't stop here"
							Kit.part(m, V3(def.width / 2 - 0.8, 0.06, 0.6), along * CF(sz * (def.width / 4), def.y + 0.03, sz * 7.5), WHITE, M.SmoothPlastic, { decor = true, name = "GiveWay" })
							for _, sx in ipairs({ -1, 1 }) do
								if def.walk > 0 then
									paintedKerb(m, along * CF(sx * (def.width / 2 + 0.35), 0.5, sz * 13), 10) -- on the pavement's edge
								else
									paintedKerb(m, along * CF(sx * (def.width / 2 - 0.35), def.y, sz * 13), 10)
								end
							end
						end
						for _, side in ipairs({ -1, 1 }) do
							local nx, nz = -e.dz * side, e.dx * side
							local at = mid + V3(nx, 0, nz) * (def.width / 2 + 1.2) + V3(e.dx, 0, e.dz) * (side * 5)
							RoadMarks.crossingSign(m, CFrame.lookAt(at, at - V3(nx, 0, nz)) * CF(0, 0.5, 0) * CFrame.Angles(0, rad(side * 90), 0), school)
						end
					end)
				end
			end
		end
	end

	-------------------------------------------------------------------------------------------------
	-- stop lines where a soi or lane meets a bigger street
	-------------------------------------------------------------------------------------------------
	local lines = 0
	for _, n in ipairs(graph.nodes) do
		if #n.links >= 2 then
			local big = false
			for _, l in ipairs(n.links) do
				if not l.edge.minor then big = true break end
			end
			if big then
				for _, l in ipairs(n.links) do
					local e = l.edge
					if e.minor and e.len > n.r + 14 then
						local sgn = e.a == n and 1 or -1
						local dx, dz = e.dx * sgn, e.dz * sgn
						local at = V3(n.x + dx * (n.r + 3.5), 0, n.z + dz * (n.r + 3.5))
						local def = e.def
						lines += 1
						emit(at.X, at.Z, function(parent)
							local cf = CFrame.lookAt(at, at + V3(dx, 0, dz)) * CF(0, def.y + 0.03, 0)
							-- the half of the soi that leads out to the street (Thailand keeps left)
							Kit.part(parent, V3(def.width / 2 - 0.6, 0.06, 0.8), cf * CF(-def.width / 4, 0, 0), WHITE, M.SmoothPlastic, { decor = true, name = "StopLine" })
							Kit.part(parent, V3(0.35, 0.06, 7), cf * CF(0, 0, 4), WHITE, M.SmoothPlastic, { decor = true, name = "Line" })
						end)
					end
				end
			end
		end
	end
	world.stopLines = lines
end

return RoadMarks
