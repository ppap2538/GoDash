-- Traffic signals. The state of every light is a pure function of the server clock, so the
-- server (fines) and every client (lamp colours, AI cars) agree without any networking.
--
-- 2026-11-18 rebuild (owner: junctions with several lights stacked together were confusing, and the lights hard to read):
--   * Only REAL signalled junctions get lights: the ones where OpenStreetMap has a traffic signal (Map.signals,
--     tools/osm_signals.py). The old rule ("three bigger roads meet on a wide road") lit 312 junctions, 4 in 5 of them
--     unsignalled in real life.
--   * A real junction of two divided roads is several graph nodes a few metres apart (each carriageway is its own
--     one-way street). They now form ONE junction with ONE controller: every lamp in it changes together.
--   * Lights stand only where traffic drives INTO the junction from outside ("approaches"); the short pieces between
--     its nodes have no lamps, no stop line and no fines (you clear the junction).
--   * Approaches on the same line (opposite each other) share a phase: 2 phases for a crossroads or a T, 3 for
--     five-way junctions.
local Traffic = {}

Traffic.GREEN = 14
Traffic.YELLOW = 3
Traffic.FINE = 100
local GREEN3 = 11 -- green per phase at three-phase junctions (keeps the wait about the same)
local NEAR_REAL = 75 -- studs: a junction node this close to a real signal is part of that junction
local JOIN = 72 -- studs: junction nodes joined by a big-road piece shorter than this belong together

local cache = setmetatable({}, { __mode = "k" })
local junctionOf = {} -- [nodeId] = junction (filled by Traffic.signals; same on server and every client)

local function bigLinks(n): number
	local k = 0
	for _, l in ipairs(n.links) do
		if not l.edge.minor then k += 1 end
	end
	return k
end


-- Group approach directions into phases: approaches on the same line (θ mod 180°) share one.
local function phasesFor(apps): number
	local axes = {} -- { angle (0..π), members }
	for _, a in ipairs(apps) do
		local phi = a.ang % math.pi
		local best, bestD
		for _, ax in ipairs(axes) do
			local d = math.abs(phi - ax.phi)
			d = math.min(d, math.pi - d)
			if d < math.rad(32) and (not bestD or d < bestD) then best, bestD = ax, d end
		end
		if best then
			table.insert(best.members, a)
		else
			table.insert(axes, { phi = phi, members = { a } })
		end
	end
	-- at most three phases: fold the smallest axis into its nearest neighbour
	while #axes > 3 do
		table.sort(axes, function(p, q) return #p.members < #q.members end)
		local small = table.remove(axes, 1)
		local best, bestD
		for _, ax in ipairs(axes) do
			local d = math.abs(small.phi - ax.phi)
			d = math.min(d, math.pi - d)
			if not bestD or d < bestD then best, bestD = ax, d end
		end
		for _, m in ipairs(small.members) do table.insert(best.members, m) end
	end
	-- stable order: by angle, so every machine numbers the phases the same way
	table.sort(axes, function(p, q) return p.phi < q.phi end)
	for i, ax in ipairs(axes) do
		for _, m in ipairs(ax.members) do m.phase = i - 1 end
	end
	return math.max(#axes, 1)
end

-- Old rule, kept for maps without signal data: three or more bigger roads meeting on a wide road.
local function legacyCandidates(graph): { any }
	local out = {}
	for _, n in ipairs(graph.nodes) do
		if #n.links >= 3 and n.r >= 20 and bigLinks(n) >= 3 then table.insert(out, { n }) end
	end
	return out
end

-- Junctions at the real signals: the junction nodes near each signal, plus the nodes joined to them by short
-- big-road pieces (the other carriageway of a divided road).
local function realJunctions(graph, real): { any }
	local CELL = 256
	local grid = {}
	-- only nodes where three or more big-road pieces meet: a soi mouth on a main road (two big pieces) is not part
	-- of a signalled junction, or a run of soi mouths would chain a junction 50 m down the road
	for _, n in ipairs(graph.nodes) do
		if bigLinks(n) >= 3 then
			local k = math.floor(n.x / CELL) * 4096 + math.floor(n.z / CELL)
			grid[k] = grid[k] or {}
			table.insert(grid[k], n)
		end
	end
	local owner = {} -- [node] = set id
	local sets = {}
	local function claim(n, id)
		local o = owner[n]
		if o == id then return end
		if o then
			-- merge set o into id
			for _, m in ipairs(sets[o]) do owner[m] = id; table.insert(sets[id], m) end
			sets[o] = {}
		else
			owner[n] = id
			table.insert(sets[id], n)
		end
	end
	for i, p in ipairs(real) do
		local x, z = p[1], p[2]
		sets[i] = {}
		local near = {}
		local cx, cz = math.floor(x / CELL), math.floor(z / CELL)
		for dx = -1, 1 do
			for dz = -1, 1 do
				for _, n in ipairs(grid[(cx + dx) * 4096 + cz + dz] or {}) do
					if (n.x - x) ^ 2 + (n.z - z) ^ 2 < NEAR_REAL * NEAR_REAL then table.insert(near, n) end
				end
			end
		end
		-- a signal touching nodes of an earlier junction joins (and merges) it; its own set may stay empty
		local target = i
		for _, n in ipairs(near) do
			if owner[n] then target = owner[n] break end
		end
		for _, n in ipairs(near) do claim(n, target) end
	end
	-- grow each set along short big-road pieces to other junction nodes
	for id, set in pairs(sets) do
		local i = 1
		while i <= #set do
			local n = set[i]
			if owner[n] == id then
				for _, l in ipairs(n.links) do
					local m = l.to
					if not l.edge.minor and l.len < JOIN and bigLinks(m) >= 3 and owner[m] ~= id then
						claim(m, id)
					end
				end
			end
			i += 1
		end
	end
	local out = {}
	for id, set in pairs(sets) do
		local nodes = {}
		for _, n in ipairs(set) do
			if owner[n] == id then table.insert(nodes, n) end
		end
		if #nodes > 0 then
			table.sort(nodes, function(a, b) return a.id < b.id end)
			table.insert(out, nodes)
		end
	end
	table.sort(out, function(a, b) return a[1].id < b[1].id end)
	return out
end

-- Returns { record } and a lookup by node id. One record per node of a signalled junction:
--   { node, groups = { [edge] = phase } (approach edges only), big = { links }, junction = J }
-- J = { id, nodes, x, z, radius, phases, green, offset, approaches = { { node, link, edge, dir, phase } } }
function Traffic.signals(graph)
	if cache[graph] then return cache[graph].list, cache[graph].byId end
	local real = graph.map and graph.map.signals or {}
	local groupsOfNodes = (#real > 0) and realJunctions(graph, real) or legacyCandidates(graph)
	local list, byId = {}, {}
	for _, nodes in ipairs(groupsOfNodes) do
		local inJ = {}
		local x, z = 0, 0
		for _, n in ipairs(nodes) do inJ[n] = true; x += n.x; z += n.z end
		x, z = x / #nodes, z / #nodes
		local radius = 0
		for _, n in ipairs(nodes) do radius = math.max(radius, math.sqrt((n.x - x) ^ 2 + (n.z - z) ^ 2) + n.r) end
		-- approaches: big roads into the junction from a node outside it. (The map keeps a one-way flag but not its
		-- direction: tools/osm_to_map.py stores each street with its ends sorted. So the exit carriageway of a divided
		-- road gets a light too, facing a road nobody drives in on.)
		local apps = {}
		for _, n in ipairs(nodes) do
			for _, l in ipairs(n.links) do
				if not l.edge.minor and not inJ[l.to] then
					local dx, dz = (n.x - l.to.x) / l.len, (n.z - l.to.z) / l.len -- direction of travel into the junction
					table.insert(apps, { node = n, link = l, edge = l.edge, dir = Vector3.new(dx, 0, dz), ang = math.atan2(dz, dx) })
				end
			end
		end
		-- a divided road arrives as two parallel one-way carriageways. Thailand keeps left, so the one on the LEFT (seen
		-- driving toward the junction) brings traffic in and the other takes it away: that one gets no light.
		local exit = {}
		for i, a in ipairs(apps) do
			for k, b in ipairs(apps) do
				if i < k and a.edge.oneway and b.edge.oneway and a.dir:Dot(b.dir) > 0.9 then
					local left = Vector3.new(a.dir.Z, 0, -a.dir.X)
					local side = Vector3.new(b.link.to.x - a.link.to.x, 0, b.link.to.z - a.link.to.z):Dot(left)
					local apart = math.abs(side)
					if apart > 3 and apart < 90 then
						if side > 0 then exit[a] = true else exit[b] = true end
					end
				end
			end
		end
		if next(exit) then
			local kept = {}
			for _, a in ipairs(apps) do
				if not exit[a] then table.insert(kept, a) end
			end
			apps = kept
		end
		local phases = #apps >= 2 and phasesFor(apps) or 0
		-- one phase = every lit road on the same line (a straight road with only sois joining): the light could only
		-- ever be green, so the junction gets none
		if phases >= 2 then
			local j = {
				id = nodes[1].id, nodes = nodes, x = x, z = z, radius = radius, phases = phases,
				green = phases >= 3 and GREEN3 or Traffic.GREEN, approaches = apps,
			}
			j.offset = (j.id * 7) % (phases * (j.green + Traffic.YELLOW))
			local groupsByNode = {}
			for _, a in ipairs(apps) do
				groupsByNode[a.node] = groupsByNode[a.node] or {}
				groupsByNode[a.node][a.edge] = a.phase
			end
			for _, n in ipairs(nodes) do
				local big = {}
				for _, l in ipairs(n.links) do
					if not l.edge.minor then table.insert(big, l) end
				end
				local s = { node = n, groups = groupsByNode[n] or {}, big = big, junction = j }
				table.insert(list, s)
				byId[n.id] = s
				junctionOf[n.id] = j
			end
		end
	end
	cache[graph] = { list = list, byId = byId }
	return list, byId
end

-- The colour for traffic arriving on a road of phase `group`, plus how long it has been showing and how long it
-- has left (seconds). The red-light check uses `since` for its grace moment, auto drive uses `left` to decide
-- whether a yellow can still be made. nil when that road has no light (a soi, or a piece inside the junction).
function Traffic.timing(nodeId: number, group: number?, t: number): (string?, number, number)
	if group == nil then return nil, 0, 0 end
	local j = junctionOf[nodeId]
	local P, G, Y = 2, Traffic.GREEN, Traffic.YELLOW
	local offset = (nodeId * 7) % (2 * (G + Y))
	if j then P, G, offset = j.phases, j.green, j.offset end
	local slotLen = G + Y
	local cycle = P * slotLen
	local phase = (t + offset) % cycle
	local active = math.floor(phase / slotLen)
	local inSlot = phase - active * slotLen
	if group == active then
		if inSlot < G then return "green", inSlot, G - inSlot end
		return "yellow", inSlot - G, slotLen - inSlot
	end
	local ourStart = group * slotLen
	local untilGreen = (ourStart - phase) % cycle
	local since = (phase - (ourStart + slotLen)) % cycle
	return "red", since, untilGreen
end

-- "green" | "yellow" | "red" (nil: no light on that road)
function Traffic.colour(nodeId: number, group: number?, t: number): string?
	return (Traffic.timing(nodeId, group, t))
end

-- the junction a signalled node belongs to (nil if none)
function Traffic.junction(nodeId: number)
	return junctionOf[nodeId]
end

return Traffic
