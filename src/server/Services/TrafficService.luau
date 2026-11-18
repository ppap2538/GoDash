-- Road rules and road life.
--   * Red-light fines: the server watches each driver crossing a signalled junction.
--   * AI traffic: a handful of vehicles that follow fixed routes. The server only creates them
--     and gives each a route; every client moves them from the shared server clock, so they
--     look the same for everyone and cost no network traffic.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Traffic = require(Shared.Traffic)
local Vehicles = require(Shared.Config.Vehicles)
local Net = require(Shared.Net)
local Fines = require(script.Parent.FineService)
local Factory = require(script.Parent.Parent.World.VehicleFactory)

local Service = {}
local RED_GRACE = 1.5 -- seconds after a light turns red in which entering still counts as the yellow
local CARS = 70 -- (30 until the map became the whole tambon, 2026-11-18) route cars; each client adds its own local traffic around the player (client/Street) -- AI vehicles on the road (2026-11-16: was 14, the streets looked empty; half of them two-wheelers, as in any Thai town)
local CELL = 512

function Service.start(world, deps)
	local graph = world.graph
	local vehicles = deps.vehicles
	local signals, byId = Traffic.signals(graph)

	-- spatial lookup of signalled junctions
	local grid = {}
	for _, s in ipairs(signals) do
		local k = math.floor(s.node.x / CELL) * 4096 + math.floor(s.node.z / CELL)
		grid[k] = grid[k] or {}
		table.insert(grid[k], s)
	end
	local function nearestSignal(pos: Vector3)
		local best, bestD
		local cx, cz = math.floor(pos.X / CELL), math.floor(pos.Z / CELL)
		for dx = -1, 1 do
			for dz = -1, 1 do
				local list = grid[(cx + dx) * 4096 + cz + dz]
				if list then
					for _, s in ipairs(list) do
						local d = (s.node.x - pos.X) ^ 2 + (s.node.z - pos.Z) ^ 2
						if not best or d < bestD then best, bestD = s, d end
					end
				end
			end
		end
		return best, bestD and math.sqrt(bestD) or math.huge
	end

	-- red-light enforcement ----------------------------------------------------------------------
	-- (2026-11-16, the owner: "left turn always passes, why was I fined?") Thai rule "ซ้ายผ่านตลอด":
	-- turning left on red is allowed. Entering on red only marks the crossing; the fine comes when the
	-- driver leaves the junction any way but left (straight on, right, or a U-turn).
	local function fine(player: Player, st, nodeId: number)
		st.fined[nodeId] = os.clock()
		local tele = vehicles.telemetry(player)
		if tele then tele.red = (tele.red or 0) + 1 end
		-- (2026-11-19) the daily limit: past it the police only warn (server/FineService)
		local ok, amount, why, n, limit = Fines.charge(player, "ticket", Traffic.FINE, "redlight")
		if not ok then
			Fines.warn(player, "ticket", why, "🚦 Ran a red light", "🚦 ฝ่าไฟแดง")
			return
		end
		local en, th = Fines.countText(n, limit)
		Net.fire(player, "Notify", "toast", { text = ("🚦 Ran a red light! Fine %s"):format(amount > 0 and ("฿" .. amount) or "(no cash)") .. en,
			th = ("🚦 ฝ่าไฟแดง! ปรับ %s"):format(amount > 0 and ("฿" .. amount) or "(ไม่มีเงินสด)") .. th, bad = true })
		Net.fire(player, "Notify", "scene", { kind = "fine", reason = "redlight", amount = amount, n = n, limit = limit }) -- client/Cutscene: pulled over, a ticket
		Net.fire(player, "Notify", "feed", { key = "fine_redlight", vars = { amount = amount } })
	end
	-- (2026-11-18 rebuild) A junction is now one controller over several nodes (shared/Traffic). Entering it on red
	-- along a road that has a light marks the crossing; the pieces inside the junction never do. The decision (left
	-- turn = allowed, anything else = fine) comes once the vehicle is out of the whole junction, judged from its centre.
	local watch = {} -- [player] = { outside = Vector3, inside = nodeId?, fined = { [junctionId] = clock }, pending = { j, heading }? }
	Players.PlayerRemoving:Connect(function(p) watch[p] = nil end)
	task.spawn(function()
		while true do
			task.wait(0.15)
			for _, player in ipairs(Players:GetPlayers()) do
				local v = vehicles.driving(player)
				local st = watch[player]
				if not st then st = { fined = {} }; watch[player] = st end
				if v then
					local pos = v.chassis.Position
					local s, dist = nearestSignal(pos)
					if s and dist < s.node.r + 3 then
						if st.inside ~= s.node.id then
							st.inside = s.node.id
							local j = s.junction
							if st.pending and st.pending.j ~= j then st.pending = nil end
							local from = st.outside or pos
							local dir = Vector3.new(from.X - s.node.x, 0, from.Z - s.node.z)
							local speed = vehicles.speed(player)
							if dir.Magnitude > 1 and speed > 9 and not st.pending then
								dir = dir.Unit
								-- which road did they arrive on?
								local bestLink, bestDot = nil, -2
								for _, l in ipairs(s.node.links) do
									local dot = ((l.to.x - s.node.x) * dir.X + (l.to.z - s.node.z) * dir.Z) / l.len
									if dot > bestDot then bestLink, bestDot = l, dot end
								end
								-- only roads with a light (not sois, not the pieces inside the junction); a moment's grace
								-- when the light has only just gone red (2026-11-19): that was a yellow you were committed to
								local col, since
								if bestLink and not bestLink.edge.minor then
									col, since = Traffic.timing(s.node.id, s.groups[bestLink.edge], Workspace:GetServerTimeNow())
								end
								if col == "red" and since > RED_GRACE and os.clock() - (st.fined[j.id] or 0) > 8 then
									st.pending = { j = j, heading = -dir } -- decided on the way out of the junction
								end
							end
						end
					else
						local p = st.pending
						if p and ((pos.X - p.j.x) ^ 2 + (pos.Z - p.j.z) ^ 2) > (p.j.radius + 3) ^ 2 then
							st.pending = nil
							local out = Vector3.new(pos.X - p.j.x, 0, pos.Z - p.j.z)
							local right = p.heading:Cross(Vector3.yAxis)
							if out.Magnitude > 1 and out.Unit:Dot(right) < -0.45 then
								Net.fire(player, "Notify", "toast", { text = "⬅️ Left turn on red is allowed", th = "⬅️ ซ้ายผ่านตลอด ไม่โดนปรับ", good = true })
							else
								fine(player, st, p.j.id)
							end
						end
						if s == nil or dist > s.node.r + 12 then st.inside = nil end
						st.outside = pos
					end
				else
					st.inside = nil
					st.outside = nil
					st.pending = nil
				end
			end
		end
	end)

	-- zebra crossings (2026-11-18): the people crossing live on each client (client/Peds), so the client
	-- says when its player drove over a crossing with someone on it; the server checks the player really
	-- is driving, at speed, right at that crossing, and not fined there in the last minute.
	local zebraFined = {} -- [player] = clock
	Players.PlayerRemoving:Connect(function(p) zebraFined[p] = nil end)
	Net.on("ZebraRun", { "number" }, function(player, index)
		local z = world.zebras and world.zebras[index]
		local v = vehicles.driving(player)
		if not z or not v then return end
		if os.clock() - (zebraFined[player] or 0) < 60 then return end
		local pos = v.chassis.Position
		if (pos.X - z.x) ^ 2 + (pos.Z - z.z) ^ 2 > 40 * 40 or vehicles.speed(player) < 7 then return end
		zebraFined[player] = os.clock()
		local tele = vehicles.telemetry(player)
		if tele then tele.red = (tele.red or 0) + 1 end -- counts like a red light on the trip's safety
		local ok, amount, why, n, limit = Fines.charge(player, "ticket", Traffic.FINE, "zebra")
		if not ok then
			Fines.warn(player, "ticket", why, "🚸 Didn't stop at the zebra crossing", "🚸 ไม่หยุดให้คนข้ามทางม้าลาย")
			return
		end
		local en, th = Fines.countText(n, limit)
		Net.fire(player, "Notify", "toast", { text = ("🚸 Didn't stop for people on the zebra crossing! Fine %s"):format(amount > 0 and ("฿" .. amount) or "(no cash)") .. en,
			th = ("🚸 ไม่หยุดให้คนข้ามทางม้าลาย! ปรับ %s"):format(amount > 0 and ("฿" .. amount) or "(ไม่มีเงินสด)") .. th, bad = true })
		Net.fire(player, "Notify", "scene", { kind = "fine", reason = "zebra", amount = amount, n = n, limit = limit })
		Net.fire(player, "Notify", "feed", { key = "fine_zebra", vars = { amount = amount } })
	end, 2)

	-- AI traffic -----------------------------------------------------------------------------------
	local folder = Workspace:FindFirstChild("Traffic") or Instance.new("Folder")
	folder.Name = "Traffic"
	folder.Parent = Workspace
	local rng = Random.new(77)
	local radius = world.radius
	local centre = world.map.center
	local function usable(n): boolean
		return (not radius) or (Vector3.new(n.x, 0, n.z) - centre).Magnitude < radius - 150
	end
	local starts = {}
	for _, n in ipairs(graph.nodes) do
		if usable(n) then
			for _, l in ipairs(n.links) do
				if not l.edge.minor then table.insert(starts, n) break end
			end
		end
	end
	local pool = {}
	for _, id in ipairs({ "eco_city", "sabai110", "sedan_vios", "zoomer125", "pickup_dmax", "oldmoped", "suv_fortune", "sabai110", "sedan_vios", "zoomer125", "eco_city", "oldmoped", "lux_e300", "sabai110" }) do
		if Vehicles.ById[id] then table.insert(pool, Vehicles.ById[id]) end
	end
	local made = 0
	if #starts > 0 then
		for i = 1, CARS do
			-- a random walk along the bigger roads, never doubling straight back
			local node = starts[rng:NextInteger(1, #starts)]
			local path = { node.id }
			local prev
			local length = 0
			for _ = 1, 90 do -- streets are cut into shorter pieces by the lanes joining them
				local options = {}
				for _, l in ipairs(node.links) do
					if not l.edge.minor and l.to ~= prev and usable(l.to) then table.insert(options, l) end
				end
				if #options == 0 then break end
				local l = options[rng:NextInteger(1, #options)]
				prev = node
				node = l.to
				length += l.len
				table.insert(path, node.id)
			end
			if #path >= 4 and length > 600 then
				local def = pool[(i - 1) % #pool + 1]
				local first = graph.nodes[path[1]]
				local y = 0.3 + def.wheelR + 0.9
				local model = Factory.traffic(def, CFrame.new(first.x, y, first.z), rng:NextInteger(1, 8), i * 7919)
				model.Name = "TrafficCar"
				model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
				model:SetAttribute("Path", table.concat(path, ","))
				model:SetAttribute("Speed", def.class == "bike" and rng:NextNumber(30, 40) or rng:NextNumber(34, 48))
				model:SetAttribute("Offset", rng:NextNumber(0, length))
				model:SetAttribute("Y", y)
				model:AddTag("TrafficCar")
				model.Parent = folder
				made += 1
			end
		end
	end
	-- Models for the traffic every client runs around its own player (client/Street): two of each
	-- kind, riders included, kept in ReplicatedStorage and cloned locally.
	local kit = Instance.new("Folder")
	kit.Name = "GoDashTrafficKit"
	local seen, k = {}, 0
	for _, def in ipairs(pool) do
		for c = 1, 2 do
			local key = def.id .. c
			if not seen[key] then
				seen[key] = true
				k += 1
				local m = Factory.traffic(def, CFrame.new(0, -400, 0), rng:NextInteger(1, 8), k * 104729)
				m.Name = def.id
				m:SetAttribute("Y", 0.3 + def.wheelR + 0.9)
				m:SetAttribute("Speed", def.class == "bike" and 34 or 40)
				m.Parent = kit
			end
		end
	end
	kit:SetAttribute("Size", #kit:GetDescendants()) -- clients wait for all of it before cloning
	kit.Parent = game:GetService("ReplicatedStorage")
	print(("[Traffic] %d signalled junctions, %d route vehicles, %d kinds for local traffic"):format(#signals, made, k))
	local _ = byId
end

return Service
