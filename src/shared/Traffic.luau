-- Traffic signals. The state of every light is a pure function of the server clock, so the
-- server (fines) and every client (lamp colours, AI cars) agree without any networking.
local Traffic = {}

Traffic.GREEN = 14
Traffic.YELLOW = 3
Traffic.FINE = 100
local CYCLE = 2 * (Traffic.GREEN + Traffic.YELLOW)

local cache = setmetatable({}, { __mode = "k" })

-- Junctions with lights: three or more bigger roads (not sois or lanes) meeting on a wide road.
-- Returns { { node, groups = { [edge] = 0 | 1 } } } and a lookup by node id.
function Traffic.signals(graph)
	if cache[graph] then return cache[graph].list, cache[graph].byId end
	local list, byId = {}, {}
	for _, n in ipairs(graph.nodes) do
		if #n.links >= 3 and n.r >= 20 then
			local big = {}
			for _, l in ipairs(n.links) do
				if not l.edge.minor then table.insert(big, l) end
			end
			if #big >= 3 then
				local first = big[1]
				local ax, az = (first.to.x - n.x) / first.len, (first.to.z - n.z) / first.len
				local groups = {}
				for _, l in ipairs(n.links) do
					local dx, dz = (l.to.x - n.x) / l.len, (l.to.z - n.z) / l.len
					groups[l.edge] = math.abs(dx * ax + dz * az) > 0.7 and 0 or 1
				end
				local s = { node = n, groups = groups, big = big }
				table.insert(list, s)
				byId[n.id] = s
			end
		end
	end
	cache[graph] = { list = list, byId = byId }
	return list, byId
end

-- "green" | "yellow" | "red" for traffic arriving on a road of `group` at server time t.
function Traffic.colour(nodeId: number, group: number, t: number): string
	local phase = (t + (nodeId * 7) % CYCLE) % CYCLE
	local active, yellow
	if phase < Traffic.GREEN then active, yellow = 0, false
	elseif phase < Traffic.GREEN + Traffic.YELLOW then active, yellow = 0, true
	elseif phase < 2 * Traffic.GREEN + Traffic.YELLOW then active, yellow = 1, false
	else active, yellow = 1, true end
	if group ~= active then return "red" end
	return yellow and "yellow" or "green"
end

-- The colour plus how long it has been showing and how long it has left (seconds). The red-light check
-- uses `since` for its grace moment, auto drive uses `left` to decide whether a yellow can still be made.
function Traffic.timing(nodeId: number, group: number, t: number): (string, number, number)
	local G, Y = Traffic.GREEN, Traffic.YELLOW
	local phase = (t + (nodeId * 7) % CYCLE) % CYCLE
	if group == 0 then
		if phase < G then return "green", phase, G - phase end
		if phase < G + Y then return "yellow", phase - G, G + Y - phase end
		return "red", phase - G - Y, CYCLE - phase
	end
	if phase < G + Y then return "red", phase, G + Y - phase end
	if phase < 2 * G + Y then return "green", phase - G - Y, 2 * G + Y - phase end
	return "yellow", phase - 2 * G - Y, CYCLE - phase
end

return Traffic
