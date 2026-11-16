-- Owned vehicles: buying, upgrades, paint, fuel, repair, spawning and telemetry.
-- The driver's client simulates the vehicle (network owner); the server measures what matters
-- for money: distance, fuel, wear, crashes and harsh driving.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Game = require(Shared.Config.Game)
local Vehicles = require(Shared.Config.Vehicles)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local NPC = require(script.Parent.NPCService)
local Factory = require(script.Parent.Parent.World.VehicleFactory)

local Service = {}
local active = {} -- [player] = { model, chassis, seat, def, id, owned, lastPos, lastSpeed, tele, ... }
local world, missions
local lastSpawn = {}

-- Telemetry the job system reads: reset at pick-up, read at drop-off.
function Service.telemetry(player: Player)
	local v = active[player]
	return v and v.tele or nil
end
function Service.resetTelemetry(player: Player)
	local v = active[player]
	if v then v.tele = { harsh = 0, crashes = 0, dist = 0, top = 0 } end
end

function Service.get(player: Player)
	return active[player]
end

-- Is the player driving their own vehicle right now?
function Service.driving(player: Player)
	local v = active[player]
	if not v or not v.seat.Occupant then return nil end
	if Players:GetPlayerFromCharacter(v.seat.Occupant.Parent) ~= player then return nil end
	return v
end

function Service.speed(player: Player): number
	local v = active[player]
	if not v then return 0 end
	local vel = v.chassis.AssemblyLinearVelocity
	return Vector3.new(vel.X, 0, vel.Z).Magnitude
end

function Service.despawn(player: Player)
	local v = active[player]
	if not v then return end
	active[player] = nil
	if v.model then v.model:Destroy() end
	Data.touch(player, "vehicles")
end

-- A parked vehicle is anchored upright at its ride height; it is only simulated while driven.
local function park(v)
	if not v.model.Parent then return end
	local originY = v.model:GetAttribute("OriginY") or 0
	local ride = v.model:GetAttribute("RideHeight") or 2
	local origin = v.chassis.CFrame * CFrame.new(0, -originY, 0)
	local look = Vector3.new(origin.LookVector.X, 0, origin.LookVector.Z)
	if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { v.model }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then table.insert(ignore, pl.Character) end
	end
	table.insert(ignore, Workspace:FindFirstChild("NPCs"))
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(origin.Position + Vector3.new(0, 8, 0), Vector3.new(0, -60, 0), params)
	local y = hit and hit.Position.Y or (origin.Position.Y - ride)
	local p = Vector3.new(origin.X, y + ride, origin.Z)
	v.chassis.AssemblyLinearVelocity = Vector3.zero
	v.chassis.AssemblyAngularVelocity = Vector3.zero
	v.chassis.Anchored = true
	v.chassis.CFrame = CFrame.lookAt(p, p + look) * CFrame.new(0, originY, 0)
	local weld = v.chassis:FindFirstChild("BodyWeld")
	if weld then weld.C0 = CFrame.new(0, -originY, 0) end
end

local function sync(v)
	v.model:SetAttribute("Fuel", math.floor(v.owned.fuel * 100) / 100)
	v.model:SetAttribute("Condition", math.floor(v.owned.condition * 10) / 10)
end

-- cf: chassis origin frame (forward = -Z). The model is lifted to its ride height.
function Service.spawnAt(player: Player, vehicleId: string, cf: CFrame)
	local d = Data.get(player)
	if not d then return nil end
	local owned = d.vehicles[vehicleId]
	local def = Vehicles.ById[vehicleId]
	if not owned or not def then return nil end
	Service.despawn(player)
	local model = Factory.build(def, owned, cf, player.UserId)
	local ride = model:GetAttribute("RideHeight")
	model:PivotTo(model:GetPivot() + Vector3.new(0, ride + 0.6, 0))
	model.Parent = Workspace:FindFirstChild("Vehicles") or Workspace
	local chassis = model.PrimaryPart
	local seat = model:FindFirstChild("DriveSeat")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Drive"
	prompt.ObjectText = def.name
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.Parent = chassis
	prompt.Triggered:Connect(function(p)
		if p ~= player then
			Net.fire(p, "Notify", "toast", { text = "That's " .. player.DisplayName .. "'s vehicle", bad = true })
			return
		end
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not seat.Occupant then seat:Sit(hum) end
	end)
	local entry = {
		model = model, chassis = chassis, seat = seat, def = def, id = vehicleId, owned = owned,
		lastPos = chassis.Position, lastSpeed = 0, tele = { harsh = 0, crashes = 0, dist = 0, top = 0 },
		stats = Vehicles.computeStats(def, owned), distAcc = 0, harshAt = 0,
	}
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = seat.Occupant
		prompt.Enabled = occ == nil
		if occ then
			local who = Players:GetPlayerFromCharacter(occ.Parent)
			if who ~= player then
				occ.Sit = false
			else
				chassis.Anchored = false
				pcall(function() chassis:SetNetworkOwner(player) end)
			end
		else
			-- let it roll to a stop for a moment, then park it
			task.delay(1.2, function()
				if model.Parent and not seat.Occupant then park(entry) end
			end)
		end
	end)
	park(entry)
	active[player] = entry
	d.activeVehicle = vehicleId
	Data.touch(player, "activeVehicle")
	return active[player]
end

-- Bring the vehicle to the road beside the player.
local function spawnNearPlayer(player: Player, vehicleId: string): (boolean, string)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false, "No character" end
	local now = os.clock()
	if lastSpawn[player] and now - lastSpawn[player] < 4 then return false, "Wait a moment" end
	local e, p, _, dist = world.graph:nearest(root.Position)
	if not e or dist > 260 then return false, "Stand closer to a road" end
	lastSpawn[player] = now
	-- park on the player's side of the road, near the kerb, facing along the road
	local nx, nz = -e.dz, e.dx
	local side = ((root.Position.X - p.X) * nx + (root.Position.Z - p.Z) * nz) >= 0 and 1 or -1
	local off = math.max(2, e.def.width / 2 - 5)
	local pos = Vector3.new(p.X + nx * side * off, 0.3, p.Z + nz * side * off)
	local fwd = Vector3.new(e.dx, 0, e.dz) * -side -- keep the kerb on the left (Thailand drives on the left)
	local v = Service.spawnAt(player, vehicleId, CFrame.lookAt(pos, pos + fwd))
	if not v then return false, "You don't own that vehicle" end
	return true, v.def.name .. " is parked beside you"
end
Service.spawnNearPlayer = spawnNearPlayer

local function nearService(player: Player, kinds: { string }): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	for _, poi in pairs(world.pois) do
		if table.find(kinds, poi.kind) and (root.Position - poi.pos).Magnitude < math.max(poi.w, poi.d) / 2 + 60 then return true end
	end
	return player:GetAttribute("AtHomeBench") == true and table.find(kinds, "home") ~= nil
end

local function garage(player: Player, op: string, vehicleId: string?, arg: any)
	local d = Data.get(player)
	if not d then return false, "Not ready" end
	if op == "despawn" then
		Service.despawn(player)
		return true, "Vehicle stored"
	end
	local def = vehicleId and Vehicles.ById[vehicleId]
	if not def then return false, "Unknown vehicle" end
	local owned = d.vehicles[def.id]

	if op == "buy" then
		if owned then return false, "You already own it" end
		if d.level < def.level then return false, "Reach level " .. def.level .. " first" end
		if not nearService(player, { "dealer" }) then return false, "Visit KK Motors to buy vehicles" end
		if not Economy.spend(player, def.price, "vehicle:" .. def.id) then return false, "Not enough money" end
		d.vehicles[def.id] = Vehicles.newOwned(def)
		Data.touch(player, "vehicles")
		missions.progress(player, "buy_vehicle", 1)
		Net.fire(player, "Notify", "bigwin", { title = "New vehicle!", text = def.name, icon = def.class == "bike" and "🛵" or "🚗" })
		return true, "You bought the " .. def.name
	end
	if not owned then return false, "You don't own that vehicle" end

	if op == "spawn" then
		return spawnNearPlayer(player, def.id)
	elseif op == "upgrade" then
		local up
		for _, u in ipairs(Vehicles.UPGRADES) do
			if u.id == arg then up = u end
		end
		if not up then return false, "Unknown upgrade" end
		local lvl = owned[up.id] or 0
		if lvl >= Vehicles.MAX_UPGRADE then return false, "Already at max level" end
		if not nearService(player, { "dealer", "home" }) then return false, "Upgrades are fitted at KK Motors" end
		local price = Vehicles.upgradePrice(def, up.id, lvl + 1)
		if not Economy.spend(player, price, "upgrade:" .. up.id) then return false, "Not enough money" end
		owned[up.id] = lvl + 1
		Data.touch(player, "vehicles")
		missions.progress(player, "upgrade", 1)
		local v = active[player]
		if v and v.id == def.id then
			v.model:SetAttribute("Up_" .. up.id, lvl + 1)
			v.stats = Vehicles.computeStats(def, owned)
		end
		return true, up.name .. " upgraded to level " .. (lvl + 1)
	elseif op == "paint" then
		local idx = tonumber(arg)
		if not idx or not Vehicles.COLORS[idx] then return false, "Unknown colour" end
		if owned.color == idx then return false, "Already that colour" end
		if not nearService(player, { "dealer", "home" }) then return false, "Paint jobs are done at KK Motors" end
		if not Economy.spend(player, Vehicles.PAINT_PRICE, "paint") then return false, "Not enough money" end
		owned.color = idx
		Data.touch(player, "vehicles")
		local v = active[player]
		if v and v.id == def.id then
			local cf = v.chassis.CFrame * CFrame.new(0, -(v.model:GetAttribute("OriginY") or 0), 0)
			Service.spawnAt(player, def.id, cf - Vector3.new(0, v.model:GetAttribute("RideHeight"), 0))
		end
		return true, "Painted " .. Vehicles.COLORS[idx].name
	elseif op == "refuel" then
		local need = def.fuelCap - owned.fuel
		if need < 0.05 then return false, "Tank is full" end
		local atPump = nearService(player, { "gas", "dealer" })
		local price = Game.FUEL_PRICE * (atPump and 1 or 2.5) -- roadside delivery costs more
		if not atPump then need = math.min(need, def.fuelCap * 0.3) end
		local cost = math.ceil(need * price)
		if d.money < cost then
			need = math.floor(d.money / price * 10) / 10
			cost = math.ceil(need * price)
			if need <= 0 then return false, "Not enough money for fuel" end
		end
		if not Economy.spend(player, cost, "fuel") then return false, "Not enough money" end
		owned.fuel = math.min(def.fuelCap, owned.fuel + need)
		Data.touch(player, "vehicles")
		local v = active[player]
		if v and v.id == def.id then sync(v) end
		return true, (atPump and "Refuelled " or "Emergency fuel ") .. string.format("%.1f L for %s", need, Util.money(cost))
	elseif op == "repair" then
		local need = 100 - owned.condition
		if need < 1 then return false, "No repairs needed" end
		local home = nearService(player, { "home" })
		if not home and not nearService(player, { "dealer", "gas" }) then return false, "Repairs are done at KK Motors or a fuel station" end
		local cost = math.ceil(need * Game.REPAIR_PRICE * (home and 0.5 or 1) * math.max(0.6, math.sqrt(math.max(def.price, 3000) / 30000)))
		if not Economy.spend(player, cost, "repair") then return false, "Repair costs " .. Util.money(cost) end
		owned.condition = 100
		Data.touch(player, "vehicles")
		local v = active[player]
		if v and v.id == def.id then sync(v); v.stats = Vehicles.computeStats(def, owned) end
		return true, "Repaired for " .. Util.money(cost)
	end
	return false, "Bad request"
end

function Service.start(w, deps)
	world = w
	missions = deps.missions

	Net.fn("Garage", { "string", "string?", "any?" }, garage, 4)

	-- lights / brake lights / indicators: cosmetic state the driver reports, replicated by attributes
	Net.on("VehicleState", { "boolean", "boolean", "int" }, function(player, lights, brake, signal)
		local v = Service.driving(player)
		if not v then return end
		if v.model:GetAttribute("Lights") ~= lights then v.model:SetAttribute("Lights", lights) end
		if v.model:GetAttribute("Brake") ~= brake then v.model:SetAttribute("Brake", brake) end
		signal = math.clamp(signal, -1, 2)
		if v.model:GetAttribute("Signal") ~= signal then v.model:SetAttribute("Signal", signal) end
	end, 12)

	-- the driver's client reports going down / rolling over in a corner
	Net.on("VehicleFall", {}, function(player)
		local v = Service.driving(player)
		if not v then return end
		v.tele.crashes += 1
		v.owned.condition = math.max(5, v.owned.condition - 4 / v.stats.crashResist)
		v.stats = Vehicles.computeStats(v.def, v.owned)
		sync(v)
		Net.fire(player, "Notify", "crash", { damage = true })
	end, 0.5)

	NPC.handle("dealer", function(player) Net.fire(player, "OpenUI", "garage", { mode = "dealer" }) end)
	NPC.handle("service", function(player) Net.fire(player, "OpenUI", "garage", { mode = "service" }) end)
	NPC.handle("gas", function(player) Net.fire(player, "OpenUI", "garage", { mode = "fuel" }) end)
	for id, poi in pairs(world.pois) do
		if poi.kind == "dealer" then
			NPC.prompt(poi.door, "Browse vehicles", poi.name, "dealer", id)
			-- showroom cars on the podiums
			local shown = { "eco_city", "raptor300", "sedan_vios" }
			for i, cf in ipairs(poi.display or {}) do
				local def = Vehicles.ById[shown[i]]
				if def then
					local m = Factory.display(def, cf * CFrame.new(0, def.wheelR + 1.2, 0) * CFrame.Angles(0, math.rad(200), 0), i + 2)
					m.Parent = Workspace:FindFirstChild("Vehicles")
				end
			end
		elseif poi.kind == "gas" then
			NPC.prompt(poi.door, "Refuel / Repair", poi.name, "gas", id)
		end
		for _, ex in ipairs(poi.extra or {}) do
			if ex.kind == "service" then NPC.prompt(ex.pos, ex.action, ex.object, "service", id) end
		end
	end

	Players.PlayerRemoving:Connect(function(p)
		local v = active[p]
		if v and v.model then v.model:Destroy() end
		active[p] = nil
		lastSpawn[p] = nil
	end)

	-- telemetry: 4 times a second
	local STEP = 0.25
	task.spawn(function()
		local n = 0
		while true do
			task.wait(STEP)
			n += 1
			for player, v in pairs(active) do
				if not v.model.Parent or not v.chassis.Parent then
					active[player] = nil
				else
					local pos = v.chassis.Position
					local vel = v.chassis.AssemblyLinearVelocity
					local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
					local driving = Service.driving(player) ~= nil
					if pos.Y < -40 then
						-- fell out of the world: put it back on the nearest road
						local _, p = world.graph:nearest(pos)
						v.model:PivotTo(CFrame.new(p + Vector3.new(0, 5, 0)))
						v.chassis.AssemblyLinearVelocity = Vector3.zero
					elseif driving then
						local step = Util.flatDist(pos, v.lastPos)
						if step < 90 then -- ignore teleports / respawns
							v.tele.dist += step
							v.distAcc += step
							v.owned.fuel = math.max(0, v.owned.fuel - step / 1000 * v.stats.fuelUse)
							v.owned.condition = math.max(5, v.owned.condition - step / 9000)
						end
						v.tele.top = math.max(v.tele.top, speed)
						local dv = speed - v.lastSpeed
						if dv < -24 then
							-- a wall, not a brake pedal
							v.tele.crashes += 1
							v.owned.condition = math.max(5, v.owned.condition - math.min(18, -dv / 3) / v.stats.crashResist)
							v.stats = Vehicles.computeStats(v.def, v.owned)
							Net.fire(player, "Notify", "crash", { damage = true })
						elseif math.abs(dv) > 10 and os.clock() - v.harshAt > 1.2 then
							v.tele.harsh += 1
							v.harshAt = os.clock()
						end
						if n % 2 == 0 then sync(v) end
					end
					v.lastPos = pos
					v.lastSpeed = speed
					if n % 12 == 0 and v.distAcc > 1 then
						local d = Data.get(player)
						if d then
							local metres = v.distAcc * Util.METRES
							d.stats.distance += metres
							Data.touch(player, "stats", "vehicles")
							missions.progress(player, "distance", metres)
						end
						v.distAcc = 0
					end
				end
			end
		end
	end)
end

return Service
