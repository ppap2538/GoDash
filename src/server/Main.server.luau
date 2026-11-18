-- GoDash: Thai Driver Life — server entry.
-- Boot order: world (or its plan, when the city is baked into the place) -> services -> players.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
Players.CharacterAutoLoads = false

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Net = require(Shared.Net) -- creates the remotes
local Map = require(Shared.Config.Maps[Game.MAP])

local Services = script.Parent.Services
local Builder = require(script.Parent.World.Builder)

local function safe(name: string, fn, ...)
	local ok, err = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end, ...)
	if not ok then warn(("[GoDash] %s failed to start:\n%s"):format(name, tostring(err))) end
	return ok
end

local t0 = os.clock()
local mapFolder = Workspace:FindFirstChild("Map")
local baked = mapFolder ~= nil and mapFolder:GetAttribute("Built") == true and mapFolder:GetAttribute("Partial") ~= true
-- The whole city is planned here; buildings are drawn around the players as they move (World/Streamer),
-- so every address, shop and landmark on the map can be used for jobs.
local RunService = game:GetService("RunService")
local world = Builder.build(Map, baked and { planOnly = true } or nil)
Workspace:SetAttribute("WorldBaked", baked)
-- nothing is a ghost: posts, stalls, chairs and people block a walker (World/Solid)
local Solid = require(script.Parent.World.Solid)
Solid.start()
if world.stream then world.stream.onBuilt = function(folder) task.spawn(Solid.area, folder, true) end end
for _, name in ipairs({ "Places", "Chunks" }) do
	local f = Workspace.Map:FindFirstChild(name)
	if f then Solid.area(f) end
end
if baked then Solid.area(Workspace.Map) end
world.radius = Game.TRAFFIC_RADIUS -- AI traffic and street dogs stay within this distance of the centre

local Data = require(Services.PlayerDataService)
local Economy = require(Services.EconomyService)
local Inventory = require(Services.InventoryService)
local Lifestyle = require(Services.LifestyleService)
local Time = require(Services.TimeService)
local Weather = require(Services.WeatherService)
local Missions = require(Services.MissionService)
local NPC = require(Services.NPCService)
local Shop = require(Services.ShopService)
local Vehicle = require(Services.VehicleService)
local Job = require(Services.JobService)
local Farming = require(Services.FarmingService)
local HousingService = require(Services.HousingService)
local TrafficService = require(Services.TrafficService)
local PoliceService = require(Services.PoliceService)
local CityRemote = require(Services.CityRemote)
local StreetService = require(Services.StreetService)
local FinanceService = require(Services.FinanceService)
local LicenseService = require(Services.LicenseService)

local deps = { missions = Missions, lifestyle = Lifestyle, weather = Weather, time = Time, vehicles = Vehicle, npc = NPC }

safe("Metrics", require(Services.MetricsService).start)
safe("Time", Time.start)
safe("Weather", Weather.start)
safe("NPC", NPC.start, world)
safe("Economy", Economy.start)
safe("Lifestyle", Lifestyle.start)
safe("Inventory", Inventory.start, Lifestyle, Missions)
safe("Missions", Missions.start)
safe("Shop", Shop.start, world, deps)
safe("Vehicle", Vehicle.start, world, deps)
safe("Job", Job.start, world, deps)
safe("Traffic", TrafficService.start, world, deps)
safe("Police", PoliceService.start, world, deps)
safe("City", CityRemote.start)
safe("Board", require(Services.LeaderboardService).start, world)
-- Tier-A plan (2026-11-17): Robux store + codes + name tags, season pass, rider company, Rush Hour
safe("Store", require(Services.StoreService).start)
safe("Season", require(Services.SeasonService).start)
safe("Company", require(Services.CompanyService).start)
safe("Events", require(Services.EventService).start)
safe("Festival", require(Services.FestivalService).start, world) -- 2026-11-18: Loy Krathong at Bueng Kaen Nakhon, 20-30 Nov
safe("Referral", require(Services.ReferralService).start) -- 2026-11-18: invite friends, both get a reward
safe("Ghosts", require(Services.GhostService).start, world) -- 2026-11-18: ghosts on late deliveries + the radio call-in
safe("Accidents", require(Services.AccidentService).start) -- 2026-11-18: hitting people or cars costs money
safe("Health", require(Services.HealthService).start) -- 2026-11-18: falls add up to injuries; the hospital treats them
safe("Street", StreetService.start, world, deps)
safe("Finance", FinanceService.start, world, deps)
safe("Licence", LicenseService.start, world, deps)
safe("Dogs", require(Services.DogService).start, world, deps)
safe("Farming", Farming.start, world, deps)
safe("Housing", HousingService.start, world, deps)
safe("Solid", function()
	for _, name in ipairs({ "StreetLife", "PoliceCheckpoints" }) do
		local f = Workspace:FindFirstChild(name)
		if f then Solid.area(f) end
	end
end)

-- Static world info for the client's map and GPS.
Net.fn("GetWorld", {}, function(player)
	local pois = {}
	for id, p in pairs(world.pois) do
		table.insert(pois, { id = id, kind = p.kind, name = p.name, thai = p.thai, pos = p.door })
	end
	local shops = {}
	for _, s in ipairs(world.shops) do
		table.insert(shops, { id = s.id, kind = s.kind, name = s.name, thai = s.thai, pos = s.pos })
	end
	local farm = Farming.farmOf(player)
	-- 2026-11-18: zebra crossings (client/Peds sends people across, the fine is in TrafficService) and the
	-- lakeside paths (joggers, lake sounds)
	local lakes = {}
	for _, l in ipairs(world.lakes or {}) do
		table.insert(lakes, { name = l.name, thai = l.thai, path = l.path, open = l.open, x = l.x, z = l.z, stalls = l.stalls, sign = l.sign, pier = l.pier,
			gym = l.gym, pieces = l.pieces })
	end
	return true, nil, {
		pois = pois, shops = shops, food = Shop.places(), busStops = world.busStops, plots = HousingService.list(),
		farm = farm and { id = farm.id, pos = farm.base.Position } or nil, mock = Data.isMock(),
		zebras = world.zebras or {}, lakes = lakes,
	}
end, 2)

-- The far city outline (World/Skyline): asked for once by client/Backdrop.
Net.fn("GetSkyline", {}, function()
	local s = world.skyline
	if not s then return false, "Not ready" end
	return true, nil, s
end, 2)

Net.fn("Settings", { "string", "any" }, function(player, key, value)
	local d = Data.get(player)
	if not d then return false, "Not ready" end
	local s = d.settings
	if key == "steer" and type(value) == "number" and value == value then
		s.steer = math.clamp(value, 0.5, 2)
	elseif (key == "assist" or key == "music" or key == "sfx" or key == "bgm" or key == "lane" or key == "autoGas" or key == "ghosts") and type(value) == "boolean" then
		s[key] = value -- lane = lane assist, autoGas = phone cruise (2026-11-18), ghosts = night ghost scenes
	elseif key == "camera" and (value == "near" or value == "normal" or value == "far") then
		s.camera = value -- client/ChaseCam distance (2026-11-18)
	elseif key == "rideAlong" and (value == "friends" or value == "all" or value == "off") then
		s.rideAlong = value
	elseif key == "quality" and (value == "auto" or value == "low" or value == "medium" or value == "high") then
		s.quality = value -- client/Perf: graphics detail (2026-11-18)
	elseif key == "lang" and (value == "en" or value == "th") then
		s.lang = value
		s.langChosen = true
	else
		return false, "Bad setting"
	end
	Data.touch(player, "settings")
	return true
end, 6)

-- Characters: spawn at the rider hub, bring the starter vehicle, respawn after death.
local hub = world.pois.hub
-- the streets around the hub stand before the first player arrives
if not baked then world.stream:ensureAround(hub and hub.pos or Map.center, 560) end
local spawnIndex = 0
local function spawnCf(): CFrame
	spawnIndex += 1
	if hub and hub.spawns and #hub.spawns > 0 then return hub.spawns[(spawnIndex - 1) % #hub.spawns + 1] end
	return CFrame.new(Map.center + Vector3.new(0, 5, 0))
end

local function onCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	local rootPart = char:WaitForChild("HumanoidRootPart", 10)
	if not hum or not rootPart then return end
	task.defer(function() char:PivotTo(spawnCf()) end)
	hum.Died:Connect(function()
		Lifestyle.stopRest(player)
		task.wait(3.5)
		if player.Parent then player:LoadCharacter() end
	end)
end

Data.onLoaded(function(player, d)
	player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
	player:LoadCharacter()
	-- first minute: park the active vehicle next to the hub so a new rider can start right away
	task.delay(2.5, function()
		if not player.Parent or not hub then return end
		local base = hub.base
		-- nose towards the street (the lot's front is -Z); side by side, 6 studs apart
		-- (2026-11-16: was turned 90° and every new rider started facing the next building's wall)
		local cf = base * CFrame.new(-12 + (spawnIndex % 4) * 6, 0.6, -hub.d / 2 + 22)
		Vehicle.spawnAt(player, d.activeVehicle, cf)
		if d.stats.deliveries == 0 and d.stats.playSeconds < 30 then
			Net.fire(player, "Notify", "welcome", { name = player.DisplayName, city = Map.name })
		end
	end)
end)

-- Studio-only test hooks (ignored on live servers): set a Workspace attribute from the command bar.
--   QaMoney = number -> gives money to every player     QaLevel = number -> sets the level
--   QaClock / QaWeather are read by the time and weather services
if RunService:IsStudio() then
	-- QA window into the plan (command bar / tests): ServerStorage.GoDashQa:Invoke("stats") or
	-- :Invoke("lots", x1, z1, x2, z2) -> "x,z,ux,uz,w,dp,kind;..." for the lots in that box.
	local qa = Instance.new("BindableFunction")
	qa.Name = "GoDashQa"
	qa.OnInvoke = function(op, x1, z1, x2, z2)
		if op == "stats" then
			local st = world.stream:stats()
			local parts = 0
			for _, d in ipairs(Workspace.Map:GetDescendants()) do
				if d:IsA("BasePart") then parts += 1 end
			end
			return ("lots=%d addresses=%d chunks=%d built=%d queued=%d parts=%d planSeconds=%.2f lotSeconds=%.2f")
				:format(world.lots, #world.addresses, st.chunks, st.built, st.queued, parts, world.buildSeconds, world.planLotsSeconds)
		elseif op == "lots" then
			local out = {}
			for _, lot in ipairs(world.lotList) do
				if lot.x >= x1 and lot.x <= x2 and lot.z >= z1 and lot.z <= z2 then
					local r = lot.base.RightVector
					table.insert(out, ("%d,%d,%.3f,%.3f,%d,%d,%s"):format(lot.x, lot.z, r.X, r.Z, lot.w, lot.dp, lot.kind))
				end
			end
			return table.concat(out, ";")
		end
		return nil
	end
	qa.Parent = game:GetService("ServerStorage")
	-- QaFocus = Vector3: stream (and so build) the city around that point for every player; nil = back to the character
	local focusPart: Part? = nil
	Workspace:GetAttributeChangedSignal("QaFocus"):Connect(function()
		local v = Workspace:GetAttribute("QaFocus")
		if typeof(v) == "Vector3" then
			if not focusPart then
				local f = Instance.new("Part")
				f.Name = "QaFocus"; f.Anchored = true; f.Transparency = 1; f.CanCollide = false; f.CanQuery = false; f.CanTouch = false
				f.Size = Vector3.new(1, 1, 1)
				f.Parent = Workspace
				focusPart = f
			end
			(focusPart :: Part).Position = v
			for _, p in ipairs(Players:GetPlayers()) do p.ReplicationFocus = focusPart end
		else
			for _, p in ipairs(Players:GetPlayers()) do p.ReplicationFocus = nil end
		end
	end)
	Workspace:GetAttributeChangedSignal("QaMoney"):Connect(function()
		local n = Workspace:GetAttribute("QaMoney")
		if type(n) ~= "number" then return end
		for _, p in ipairs(Players:GetPlayers()) do Economy.add(p, n, "qa") end
		Workspace:SetAttribute("QaMoney", nil)
	end)
	Workspace:GetAttributeChangedSignal("QaLevel"):Connect(function()
		local n = Workspace:GetAttribute("QaLevel")
		if type(n) ~= "number" then return end
		for _, p in ipairs(Players:GetPlayers()) do
			local d = Data.get(p)
			if d then d.level = math.clamp(math.floor(n), 1, Game.MAX_LEVEL); Data.touch(p, "level") end
		end
		Workspace:SetAttribute("QaLevel", nil)
	end)
	-- QaInjury = number: set every player's injury (server/HealthService) to test the hospital
	Workspace:GetAttributeChangedSignal("QaInjury"):Connect(function()
		local n = Workspace:GetAttribute("QaInjury")
		if type(n) ~= "number" then return end
		for _, p in ipairs(Players:GetPlayers()) do
			local d = Data.get(p)
			if d then d.injury = math.clamp(math.floor(n), 0, 100); Data.touch(p, "injury"); p:SetAttribute("Injury", d.injury) end
		end
		Workspace:SetAttribute("QaInjury", nil)
	end)
	-- QaNeeds = true: fill energy, hunger and happiness (orders pause while a rider is starving)
	Workspace:GetAttributeChangedSignal("QaNeeds"):Connect(function()
		if not Workspace:GetAttribute("QaNeeds") then return end
		for _, p in ipairs(Players:GetPlayers()) do
			local d = Data.get(p)
			if d then d.energy, d.hunger, d.happiness = 100, 100, 100; Data.touch(p, "energy"); Data.touch(p, "hunger"); Data.touch(p, "happiness") end
		end
		Workspace:SetAttribute("QaNeeds", nil)
	end)
end

safe("Data", Data.start)

print(("[GoDash] server ready in %.1fs (%s world, %d addresses, %d restaurants, datastore=%s)")
	:format(os.clock() - t0, baked and "baked" or "generated", #world.addresses, #world.restaurants, "see [Data] line above if in memory"))
