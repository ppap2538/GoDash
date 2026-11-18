-- Road network: nodes (junctions and bends) and straight edges at any angle, with a spatial grid.
-- Shared by the world builder, the GPS (shortest path), the job dispatcher and pedestrians.
local RoadGraph = {}
RoadGraph.__index = RoadGraph

local CELL = 512

local function cellKey(cx: number, cz: number): number
	return cx * 4096 + cz
end

function RoadGraph.new(map)
	local self = setmetatable({}, RoadGraph)
	self.map = map
	self.nodes = {}
	self.edges = {}
	self.grid = {}
	local rawNodes, rawEdges, names = map.loadGraph()
	for i, n in ipairs(rawNodes) do
		self.nodes[i] = { id = i, x = n[1], z = n[2], pos = Vector3.new(n[1], 0, n[2]), links = {}, r = 0 }
	end
	for _, e in ipairs(rawEdges) do
		local a, b = self.nodes[e[1]], self.nodes[e[2]]
		if a and b and a ~= b then
			local dx, dz = b.x - a.x, b.z - a.z
			local len = math.sqrt(dx * dx + dz * dz)
			if len > 0.5 then
				local def = map.roadTypes[e[3]]
				local nm = names[e[4]]
				local edge = {
					id = #self.edges + 1, a = a, b = b, type = e[3], def = def, len = len,
					dx = dx / len, dz = dz / len, name = nm and nm[1] or "", thai = nm and nm[2] or "", oneway = e[5],
					minor = e[3] == "soi" or e[3] == "lane", -- small streets: no signals, no through traffic, thin on the map
				}
				table.insert(self.edges, edge)
				table.insert(a.links, { to = b, len = len, edge = edge })
				table.insert(b.links, { to = a, len = len, edge = edge })
				a.r = math.max(a.r, def.width / 2)
				b.r = math.max(b.r, def.width / 2)
				local x1, x2 = math.min(a.x, b.x), math.max(a.x, b.x)
				local z1, z2 = math.min(a.z, b.z), math.max(a.z, b.z)
				for cx = math.floor(x1 / CELL), math.floor(x2 / CELL) do
					for cz = math.floor(z1 / CELL), math.floor(z2 / CELL) do
						local k = cellKey(cx, cz)
						local list = self.grid[k]
						if not list then list = {}; self.grid[k] = list end
						table.insert(list, edge)
					end
				end
			end
		end
	end
	return self
end

-- Closest point on edge e to (x, z): returns px, pz, t (0..1), squared distance.
local function project(e, x: number, z: number)
	local t = ((x - e.a.x) * e.dx + (z - e.a.z) * e.dz) / e.len
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	local px, pz = e.a.x + e.dx * e.len * t, e.a.z + e.dz * e.len * t
	return px, pz, t, (px - x) ^ 2 + (pz - z) ^ 2
end
RoadGraph.project = project

-- All edges whose grid cells are within `radius` of the point (unsorted, no duplicates).
function RoadGraph:edgesNear(pos: Vector3, radius: number)
	local out, seen = {}, {}
	for cx = math.floor((pos.X - radius) / CELL), math.floor((pos.X + radius) / CELL) do
		for cz = math.floor((pos.Z - radius) / CELL), math.floor((pos.Z + radius) / CELL) do
			local list = self.grid[cellKey(cx, cz)]
			if list then
				for _, e in ipairs(list) do
					if not seen[e] then seen[e] = true; table.insert(out, e) end
				end
			end
		end
	end
	return out
end

-- Closest point on the network: edge, point, t, distance.
function RoadGraph:nearest(pos: Vector3, filter: ((any) -> boolean)?)
	local radius = CELL
	local best, bestD, bx, bz, bt = nil, math.huge, 0, 0, 0
	for _ = 1, 8 do
		for _, e in ipairs(self:edgesNear(pos, radius)) do
			if not filter or filter(e) then
				local px, pz, t, d = project(e, pos.X, pos.Z)
				if d < bestD then best, bestD, bx, bz, bt = e, d, px, pz, t end
			end
		end
		if best and bestD <= radius * radius then break end
		radius *= 2
	end
	if not best then return nil, pos, 0, math.huge end
	return best, Vector3.new(bx, 0, bz), bt, math.sqrt(bestD)
end

---------------------------------------------------------------------------------------------------
-- shortest path (Dijkstra with a binary heap)
---------------------------------------------------------------------------------------------------
local function push(heap, id, d)
	local n = #heap + 1
	heap[n] = { id, d }
	while n > 1 do
		local p = n // 2
		if heap[p][2] <= heap[n][2] then break end
		heap[p], heap[n] = heap[n], heap[p]
		n = p
	end
end
local function pop(heap)
	local top = heap[1]
	local n = #heap
	heap[1] = heap[n]
	heap[n] = nil
	n -= 1
	local i = 1
	while true do
		local l, r, s = i * 2, i * 2 + 1, i
		if l <= n and heap[l][2] < heap[s][2] then s = l end
		if r <= n and heap[r][2] < heap[s][2] then s = r end
		if s == i then break end
		heap[i], heap[s] = heap[s], heap[i]
		i = s
	end
	return top
end

-- Route between two world positions. Returns points (y = 0) and length in studs.
function RoadGraph:path(from: Vector3, to: Vector3): ({ Vector3 }, number)
	local e1, p1, t1 = self:nearest(from)
	local e2, p2, t2 = self:nearest(to)
	if not e1 or not e2 then return { from, to }, (to - from).Magnitude end
	if e1 == e2 then return { p1, p2 }, (p2 - p1).Magnitude end
	local dist, prev, done = {}, {}, {}
	local heap = {}
	dist[e1.a.id] = t1 * e1.len; push(heap, e1.a.id, dist[e1.a.id])
	dist[e1.b.id] = (1 - t1) * e1.len; push(heap, e1.b.id, dist[e1.b.id])
	local goalA, goalB = e2.a.id, e2.b.id
	local nodes = self.nodes
	while #heap > 0 do
		local top = pop(heap)
		local u, ud = top[1], top[2]
		if not done[u] then
			done[u] = true
			if done[goalA] and done[goalB] then break end
			for _, l in ipairs(nodes[u].links) do
				local v = l.to.id
				local nd = ud + l.len
				if not done[v] and (not dist[v] or nd < dist[v]) then
					dist[v] = nd
					prev[v] = u
					push(heap, v, nd)
				end
			end
		end
	end
	local da = dist[goalA] and dist[goalA] + t2 * e2.len or math.huge
	local db = dist[goalB] and dist[goalB] + (1 - t2) * e2.len or math.huge
	if da == math.huge and db == math.huge then return { p1, p2 }, (p2 - p1).Magnitude end
	local cur = da <= db and goalA or goalB
	local rev = { p2 }
	while cur do
		table.insert(rev, nodes[cur].pos)
		cur = prev[cur]
	end
	table.insert(rev, p1)
	local out = {}
	for i = #rev, 1, -1 do
		local p = rev[i]
		if #out == 0 or (out[#out] - p).Magnitude > 0.5 then table.insert(out, p) end
	end
	return out, math.min(da, db)
end

function RoadGraph:distance(from: Vector3, to: Vector3): number
	local _, len = self:path(from, to)
	return len
end

function RoadGraph:roadNameAt(pos: Vector3): string
	local e = self:nearest(pos, function(edge) return edge.name ~= "" end)
	return e and e.name or ""
end

return RoadGraph
