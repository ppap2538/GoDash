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
-- Live servers build the whole city; Studio builds only the centre so Play starts quickly.
local RunService = game:GetService("RunService")
local devRadius = nil
if not baked then devRadius = RunService:IsStudio() and Game.DEV_RADIUS or Game.LIVE_RADIUS end
local world = Builder.build(Map, baked and { planOnly = true } or { radius = devRadius })
Workspace:SetAttribute("WorldBaked", baked)
world.radius = devRadius
if devRadius then
	-- keep jobs inside the part of the city that exists in this session
	local function within(list)
		local out = {}
		for _, e in ipairs(list) do
			if (Vector3.new(e.pos.X, 0, e.pos.Z) - Map.center).Magnitude <= devRadius - 60 then table.insert(out, e) end
		end
		return out
	end
	world.addresses = within(world.addresses)
	world.restaurants = within(world.restaurants)
	print(("[GoDash] city built within %d studs of the centre (%d addresses, %d restaurants). See Game.DEV_RADIUS / Game.LIVE_RADIUS.")
		:format(devRadius, #world.addresses, #world.restaurants))
end

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

local deps = { missions = Missions, lifestyle = Lifestyle, weather = Weather, time = Time, vehicles = Vehicle, npc = NPC }

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
safe("Dogs", require(Services.DogService).start, world, deps)
safe("Farming", Farming.start, world, deps)
safe("Housing", HousingService.start, world, deps)

-- Static world info for the client's map and GPS.
Net.fn("GetWorld", {}, function(player)
	local pois = {}
	for id, p in pairs(world.pois) do
		table.insert(pois, { id = id, kind = p.kind, name = p.name, thai = p.thai, pos = p.door })
	end
	local shops = {}
	for _, s in ipairs(world.shops) do
		table.insert(shops, { id = s.id, kind = s.kind, name = s.name, pos = s.pos })
	end
	local farm = Farming.farmOf(player)
	return true, nil, {
		pois = pois, shops = shops, busStops = world.busStops, plots = HousingService.list(),
		farm = farm and { id = farm.id, pos = farm.base.Position } or nil, mock = Data.isMock(),
	}
end, 2)

Net.fn("Settings", { "string", "any" }, function(player, key, value)
	local d = Data.get(player)
	if not d then return false, "Not ready" end
	local s = d.settings
	if key == "steer" and type(value) == "number" and value == value then
		s.steer = math.clamp(value, 0.5, 2)
	elseif (key == "assist" or key == "music" or key == "sfx") and type(value) == "boolean" then
		s[key] = value
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
		local cf = base * CFrame.new(-12 + (spawnIndex % 4) * 6, 0.6, -hub.d / 2 + 22) * CFrame.Angles(0, math.rad(90), 0)
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
end

safe("Data", Data.start)

print(("[GoDash] server ready in %.1fs (%s world, %d addresses, %d restaurants, datastore=%s)")
	:format(os.clock() - t0, baked and "baked" or "generated", #world.addresses, #world.restaurants, "see [Data] line above if in memory"))
