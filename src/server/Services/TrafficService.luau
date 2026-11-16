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
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Factory = require(script.Parent.Parent.World.VehicleFactory)

local Service = {}
local CARS = 14
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
	local watch = {} -- [player] = { outside = Vector3, inside = nodeId?, fined = { [nodeId] = clock } }
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
							local from = st.outside or pos
							local dir = Vector3.new(from.X - s.node.x, 0, from.Z - s.node.z)
							local speed = vehicles.speed(player)
							if dir.Magnitude > 1 and speed > 9 then
								dir = dir.Unit
								-- which road did they arrive on?
								local bestLink, bestDot = nil, -2
								for _, l in ipairs(s.node.links) do
									local dot = ((l.to.x - s.node.x) * dir.X + (l.to.z - s.node.z) * dir.Z) / l.len
									if dot > bestDot then bestLink, bestDot = l, dot end
								end
								local now = os.clock()
								if bestLink and bestLink.edge.type ~= "soi"
									and Traffic.colour(s.node.id, s.groups[bestLink.edge], Workspace:GetServerTimeNow()) == "red"
									and now - (st.fined[s.node.id] or 0) > 8 then
									st.fined[s.node.id] = now
									local d = Data.get(player)
									local fine = d and math.min(d.money, Traffic.FINE) or 0
									if fine > 0 then Economy.spend(player, fine, "redlight") end
									local tele = vehicles.telemetry(player)
									if tele then tele.red = (tele.red or 0) + 1 end
									Net.fire(player, "Notify", "toast", { text = ("🚦 Ran a red light! Fine %s"):format(fine > 0 and ("฿" .. fine) or "(no cash)"), bad = true })
								end
							end
						end
					else
						if s == nil or dist > s.node.r + 12 then st.inside = nil end
						st.outside = pos
					end
				else
					st.inside = nil
					st.outside = nil
				end
			end
		end
	end)

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
				if l.edge.type ~= "soi" then table.insert(starts, n) break end
			end
		end
	end
	local pool = {}
	for _, id in ipairs({ "eco_city", "sedan_vios", "pickup_dmax", "suv_fortune", "sabai110", "zoomer125", "sedan_vios", "eco_city", "oldmoped", "lux_e300" }) do
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
			for _ = 1, 45 do
				local options = {}
				for _, l in ipairs(node.links) do
					if l.edge.type ~= "soi" and l.to ~= prev and usable(l.to) then table.insert(options, l) end
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
				local model = Factory.display(def, CFrame.new(first.x, y, first.z), rng:NextInteger(1, 8))
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
	print(("[Traffic] %d signalled junctions, %d AI vehicles on the road"):format(#signals, made))
	local _ = byId
end

return Service
