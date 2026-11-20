-- Owned vehicles: buying, upgrades, paint, fuel, repair, spawning and telemetry.
-- The driver's client simulates the vehicle (network owner); the server measures what matters
-- for money: distance, fuel, wear, crashes and harsh driving.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
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

-- (2026-11-19) today's counters for the day recap (client/Recap): crashes, harsh jolts, loads dropped
local function countDay(player: Player, field: string)
	local d = Data.get(player)
	if not d then return end
	Economy.rollDay(d)
	d.daily[field] = (tonumber(d.daily[field]) or 0) + 1
	Data.touch(player, "daily")
end

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
	-- (2026-11-19) upkeep: client/Drive reads these into its stats (Vehicles.computeStats)
	v.model:SetAttribute("Tread", math.floor(v.owned.tread or 100))
	v.model:SetAttribute("OilDue", not v.def.pedal and (v.owned.oil or 0) > Vehicles.OIL_INTERVAL or nil)
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
	prompt:SetAttribute("ForUser", player.UserId) -- only the owner sees "Drive" (client UI/Interactions/Prompt)
	prompt.Parent = chassis
	local mounting = false
	prompt.Triggered:Connect(function(p)
		if p ~= player or mounting then return end
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or hum.Health <= 0 or seat.Occupant or not root then return end
		-- walk up to the seat's side first (left of a motorbike, the driver's door of a car), then get on
		-- (2026-11-18 realism pass: no more popping onto the seat from a few metres away)
		mounting = true
		local lx = chassis.CFrame:PointToObjectSpace(seat.Position).X
		local sideSign = def.class == "car" and (lx >= 0 and 1 or -1) or -1
		local out = def.class == "car" and (def.wid / 2 + 1.4) or 2.1
		local side = (chassis.CFrame * CFrame.new(sideSign * out, 0, 0)).Position
		local flat = Vector3.new(side.X - root.Position.X, 0, side.Z - root.Position.Z)
		if flat.Magnitude > 2.5 then
			hum:MoveTo(Vector3.new(side.X, root.Position.Y, side.Z))
			local t0 = os.clock()
			while os.clock() - t0 < 1.8 and hum.Parent and hum.Health > 0 do
				task.wait(0.05)
				local f = Vector3.new(side.X - root.Position.X, 0, side.Z - root.Position.Z)
				if f.Magnitude < 2 then break end
			end
		end
		mounting = false
		if hum.Parent and hum.Health > 0 and not seat.Occupant and model.Parent then seat:Sit(hum) end
	end)
	-- Friends ride along (2026-11-17 growth plan): everyone else sees "Ride along" on the vehicle.
	-- The owner decides who may: friends (default), anyone, or nobody (Phone > Settings).
	if (model:GetAttribute("Seats") or 0) > 0 then
		local ride = Instance.new("ProximityPrompt")
		ride.Name = "RideAlong"
		ride.ActionText = "Ride along"
		ride.ObjectText = player.DisplayName
		ride.MaxActivationDistance = 10
		ride.RequiresLineOfSight = false
		ride.KeyboardKeyCode = Enum.KeyCode.F
		ride:SetAttribute("NotForUser", player.UserId)
		ride.Parent = chassis
		ride.Triggered:Connect(function(p)
			if p == player then return end
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 or hum.SeatPart then return end
			local od = Data.get(player)
			local rule = od and od.settings and od.settings.rideAlong or "friends"
			if rule == "off" then
				Net.fire(p, "Notify", "toast", { text = player.DisplayName .. " isn't taking passengers", th = player.DisplayName .. " ไม่รับคนซ้อน", bad = true })
				return
			end
			if rule ~= "all" then
				local okF, friends = pcall(function() return p:IsFriendsWith(player.UserId) end)
				if not (okF and friends) then
					Net.fire(p, "Notify", "toast", { text = "Only " .. player.DisplayName .. "'s friends can ride along", th = "เฉพาะเพื่อนของ " .. player.DisplayName .. " ที่ขึ้นได้", bad = true })
					return
				end
			end
			-- a free passenger point (job passengers use the first ones; friends fill from the back)
			local body = model:FindFirstChild("Body")
			if not body then return end
			local taken = {}
			for _, s in ipairs(model:GetChildren()) do
				if s.Name == "PaxSeat" and s:IsA("Seat") then
					if s.Occupant then taken[s:GetAttribute("Slot")] = true else s:Destroy() end
				end
			end
			local slot
			for i = model:GetAttribute("Seats") or 0, 1, -1 do
				if not taken[i] and body:FindFirstChild("Pax" .. i) then slot = i break end
			end
			if not slot or model:GetAttribute("PaxBusy") then
				Net.fire(p, "Notify", "toast", { text = "No free seat", th = "ที่นั่งเต็มแล้ว", bad = true })
				return
			end
			local att = body:FindFirstChild("Pax" .. slot) :: Attachment
			local s = Instance.new("Seat")
			s.Name = "PaxSeat"
			s:SetAttribute("Slot", slot)
			s.Size = Vector3.new(1.4, 0.3, 1.4)
			s.Transparency = 1
			s.CanCollide = false
			s.CanTouch = false
			s.CanQuery = false
			s.Massless = true
			s.CFrame = att.WorldCFrame
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = s
			w.Parent = s
			s.Parent = model
			s:Sit(hum)
			s:GetPropertyChangedSignal("Occupant"):Connect(function()
				if not s.Occupant then task.delay(0.5, function() if s.Parent and not s.Occupant then s:Destroy() end end) end
			end)
			Net.fire(player, "Notify", "toast", { text = "👫 " .. p.DisplayName .. " is riding with you", th = "👫 " .. p.DisplayName .. " ขึ้นรถมาด้วยแล้ว", good = true })
			Net.fire(p, "Notify", "toast", { text = "👫 Riding with " .. player.DisplayName .. " · Space to get off", th = "👫 นั่งไปกับ " .. player.DisplayName .. " · กด Space เพื่อลง", good = true })
		end)
	end
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
		local loan = d.loans and d.loans[def.id]
		if loan and loan.repo then return false, "Repossessed! Pay the overdue instalments in the Finance app" end
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
	elseif op == "style" then
		-- arg = { kind = "glow" | "sticker" | "horn" | "plate", value = index or plate text }
		if type(arg) ~= "table" then return false, "Bad request" end
		local kind, value = arg.kind, arg.value
		local price = Vehicles.STYLE_PRICES[kind]
		if not price then return false, "Bad request" end
		if def.pedal and kind ~= "horn" then return false, "A bicycle can only change its bell" end
		if kind == "box" and def.class ~= "bike" then return false, "Only motorbikes have a delivery box" end
		owned.style = type(owned.style) == "table" and owned.style or {}
		local st = owned.style
		local free = false
		if kind == "plate" then
			-- (2026-11-19, all ages) picked, not typed: { w = word index, n = 1-999 } (Config/Vehicles.PLATE_WORDS),
			-- or "" for the standard plate. Typed plates are no longer accepted.
			local text
			if value == "" then
				free = true
				text = ""
			elseif type(value) == "table" and type(value.w) == "number" and type(value.n) == "number" then
				text = Vehicles.plateText(value.w, value.n)
				if not text then return false, "Unknown choice" end
			else
				return false, "Bad request"
			end
			local _ = TextService
			if (st.plate or "") == text then return false, "That's already your plate" end
			value = text
		else
			value = tonumber(value)
			if value == nil then return false, "Bad request" end
			local list = kind == "glow" and Vehicles.GLOWS or (kind == "sticker" and Vehicles.STICKERS or (kind == "exhaust" and Vehicles.EXHAUSTS
				or (kind == "box" and Vehicles.BOXES or Vehicles.HORNS)))
			if kind == "horn" or kind == "exhaust" then
				if not list[value] then return false, "Unknown choice" end
				free = value == 1
			else
				if value ~= 0 and not list[value] then return false, "Unknown choice" end
				free = value == 0
				-- pass and season cosmetics (Config/Vehicles "need")
				local need = value ~= 0 and list[value].need
				if need == "vip" and not player:GetAttribute("VIP") then return false, "Needs the VIP pass" end
				if need == "neon" and not player:GetAttribute("NeonPro") then return false, "Needs the Neon Pro pass" end
				if need and need ~= "vip" and need ~= "neon" and not (type(d.unlocks) == "table" and d.unlocks[need]) then return false, "Unlocked in the Season Pass" end
				if need then free = true end -- already paid for with the pass / the season
			end
			if (st[kind] or ((kind == "horn" or kind == "exhaust") and 1 or 0)) == value then return false, "Already fitted" end
		end
		if not free and not Economy.spend(player, price, "style:" .. kind) then return false, "Not enough money (" .. Util.money(price) .. ")" end
		st[kind] = value
		Data.touch(player, "vehicles")
		require(script.Parent.StoreService).badge(player, "style")
		local v = active[player]
		if v and v.id == def.id and v.model and v.model.Parent then
			if kind == "plate" then v.model:SetAttribute("PlateText", value) end
			pcall(Factory.style, v.model, def, owned, player.UserId)
		end
		return true, free and "Changed" or ("Fitted for " .. Util.money(price))
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
	elseif op == "oil" or op == "tyres" then
		-- (2026-11-19) upkeep at KK Motors, a fuel station or home; not paid by insurance
		if op == "oil" and def.pedal then return false, "A bicycle has no engine oil" end
		if op == "oil" and (owned.oil or 0) < Vehicles.OIL_INTERVAL * 0.25 then return false, "The oil is still fresh" end
		if op == "tyres" and (owned.tread or 100) > 85 then return false, "The tyres are still good" end
		local home = nearService(player, { "home" })
		if not home and not nearService(player, { "dealer", "gas" }) then return false, "Done at KK Motors, a fuel station or home" end
		local cost = Vehicles.upkeepPrice(def, op)
		if not Economy.spend(player, cost, op) then return false, "Costs " .. Util.money(cost) end
		if op == "oil" then owned.oil = 0 else owned.tread = 100 end
		Data.touch(player, "vehicles")
		local v = active[player]
		if v and v.id == def.id then sync(v); v.stats = Vehicles.computeStats(def, owned) end
		return true, (op == "oil" and "Oil changed for " or "New tyres for ") .. Util.money(cost)
	elseif op == "repair" then
		local need = 100 - owned.condition
		if need < 1 then return false, "No repairs needed" end
		local home = nearService(player, { "home" })
		if not home and not nearService(player, { "dealer", "gas" }) then return false, "Repairs are done at KK Motors or a fuel station" end
		local cost = math.ceil(need * Game.REPAIR_PRICE * (home and 0.5 or 1) * math.max(0.6, math.sqrt(math.max(def.price, 3000) / 30000)))
		-- (2026-11-19) insurance class 2+ / 1 pays half / all of it (server/InsuranceService)
		local covered = math.floor(cost * require(script.Parent.InsuranceService).share(player, "repair") + 0.5)
		cost -= covered
		if cost > 0 and not Economy.spend(player, cost, "repair") then return false, "Repair costs " .. Util.money(cost) end
		if covered > 0 then
			owned.condition = 100
			Data.touch(player, "vehicles")
			local v = active[player]
			if v and v.id == def.id then sync(v); v.stats = Vehicles.computeStats(def, owned) end
			return true, ("Repaired: insurance paid %s, you paid %s"):format(Util.money(covered), Util.money(cost))
		end
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
	Net.on("VehicleState", { "boolean", "boolean", "int", "int?" }, function(player, lights, brake, signal, stunt)
		local v = Service.driving(player)
		if not v then return end
		if v.model:GetAttribute("Lights") ~= lights then v.model:SetAttribute("Lights", lights) end
		if v.model:GetAttribute("Brake") ~= brake then v.model:SetAttribute("Brake", brake) end
		signal = math.clamp(signal, -1, 2)
		if v.model:GetAttribute("Signal") ~= signal then v.model:SetAttribute("Signal", signal) end
		-- 2026-11-19: 1 = wheelie, 2 = burnout (bikes only), drawn for everyone by client/Stunts
		stunt = (v.def.class == "bike") and math.clamp(stunt or 0, 0, 2) or 0
		if (v.model:GetAttribute("Stunt") or 0) ~= stunt then v.model:SetAttribute("Stunt", stunt) end
	end, 12)

	-- (2026-11-20, owner: "กดลงรถไม่ได้") client/Drive asks when its own Sit = false has not freed the rider
	-- within a moment: the seat weld is the server's, so the server lets go
	Net.on("LeaveSeat", {}, function(player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		if not (char and seat) then return end
		for _, w in ipairs(seat:GetChildren()) do
			if w.Name == "SeatWeld" and w:IsA("JointInstance") and (w :: JointInstance).Part1 and ((w :: JointInstance).Part1 :: BasePart):IsDescendantOf(char) then w:Destroy() end
		end
		hum.Sit = false
	end, 2)

	-- the driver's client reports going down (thrown off in a crash, a speed bump at full speed) or a
	-- hard landing; speed = studs/s at the moment. The rider is hurt too (server/HealthService).
	Net.on("VehicleFall", { "number?" }, function(player, speed)
		local v = Service.driving(player)
		if not v then return end
		v.tele.crashes += 1
		v.owned.condition = math.max(5, v.owned.condition - 4 / v.stats.crashResist)
		v.stats = Vehicles.computeStats(v.def, v.owned)
		sync(v)
		-- (2026-11-19) a big load strapped on (JobService "Cargo") is thrown off: every client draws it falling (client/Cargo)
		if v.model:GetAttribute("Cargo") then v.model:SetAttribute("CargoDrop", workspace:GetServerTimeNow()); countDay(player, "drops") end
		countDay(player, "crashes")
		Net.fire(player, "Notify", "crash", { damage = true, crashes = v.tele.crashes })
		require(script.Parent.HealthService).injure(player, v.def.class == "car" and "car" or "bike", math.clamp(tonumber(speed) or 30, 0, 200))
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
			-- (the real time since the last look: a busy server waits longer than STEP, and the jolt limits below are
			-- accelerations over this span, not over a fixed quarter second)
			local span = math.max(task.wait(STEP), STEP)
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
							v.owned.tread = math.max(0, (v.owned.tread or 100) - step * 100 / Vehicles.TREAD_LIFE)
							if not v.def.pedal then v.owned.oil = (v.owned.oil or 0) + step end
						end
						v.tele.top = math.max(v.tele.top, speed)
						local dv = speed - v.lastSpeed
						-- (2026-11-19, the food-spill meter: client/Spill) a hard corner and a big bump shake the order
						-- too, not only hard braking and flooring it: the sideways part of the change of velocity in
						-- this quarter second and a jump in the vertical speed (kerbs, potholes); the limits are below
						-- (a velocity from before the rider got off is no reference: compare only with the last look)
						local fresh = v.lastVel ~= nil and os.clock() - (v.lastVelAt or 0) < span + 0.3
						local lastVel = fresh and v.lastVel or vel
						if not fresh then dv = 0 end
						local dFlat = Vector3.new(vel.X - lastVel.X, 0, vel.Z - lastVel.Z).Magnitude
						local sideways = math.sqrt(math.max(0, dFlat * dFlat - dv * dv))
						local bumpY = math.abs(vel.Y - lastVel.Y)
						v.lastVel = vel
						v.lastVelAt = os.clock()
						-- (later 2026-11-19, owner: "ยังไม่ขับชนอะไรเลยแต่...เสียหายแล้ว" with the order at 21 %): the fixed limits
						-- (10 studs/s along, 13 sideways per quarter second) sat below what the vehicle does when ridden
						-- normally: the steering allows 2 g (2.6 g in the easy style) and S is a full brake on a keyboard, so
						-- every full-lock corner above ~25 km/h and every stop from speed counted as a jolt. A jolt is now only
						-- what the vehicle's own controls can't do: brake + handbrake together, a kerb, a pothole, a knock.
						-- (Studio, Sabai 110: a full brake from 40 lost up to 12.2 studs/s a quarter second, a full-lock swerve
						-- at 30 up to 16 sideways; the limits for that bike are 14.4 and 23.1)
						local st = v.stats
						local roll = 0.1 * math.max(speed, v.lastSpeed) + 2 -- rolling resistance and air at the faster end
						local brakeCap = (st.brake * 1.12 + roll) * span + 2.5 -- a full press of the brake (easy style 1.12x)
						local gasCap = st.accel * 1.18 * span + 2.5 -- flat out with the boost
						local turnCap = 35 * 2.0 * 1.3 * (st.grip / 10.5) * span + 2.5 -- the tightest corner the steering allows (Drive LAT_G x easy)
						local hardLon = dv < -brakeCap or dv > gasCap
						local hardTurn = sideways > turnCap and speed > 15
						-- a crash: more than brake + handbrake can stop it (a fast car's emergency stop is not a wall)
						local crashCap = math.max(24, (st.brake * 1.72 + roll) * span + 4)
						-- (2026-11-20, owner, twice: "ขับรถยังไม่ชนอะไรเลยได้รับความเสียหายแล้ว" ... "ตัดความเสียหายเรื่องนี้ออกไป
						-- เลย") a sudden drop seen only in these quarter-second server samples no longer counts as a crash
						-- or damages anything: the samples also catch network hiccups and road seams. A real crash is
						-- still caught where it happens, on the driver's client (client/Drive: the hit throws the rider
						-- off and sends VehicleFall, which does the damage).
						if dv < -crashCap then
							-- (nothing: not a crash, and not a jolt either)
						elseif (hardLon or hardTurn or bumpY > 9) and os.clock() - v.harshAt > 1.2 then
							v.tele.harsh += 1
							v.harshAt = os.clock()
							countDay(player, "harsh")
							local kind = hardLon and (dv < 0 and "brake" or "gas") or (hardTurn and "turn" or "bump")
							Net.fire(player, "Notify", "harsh", { kind = kind, harsh = v.tele.harsh, crashes = v.tele.crashes })
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
							-- (2026-11-19) today's distance for the day recap (client/Recap)
							Economy.rollDay(d)
							d.daily.dist = (tonumber(d.daily.dist) or 0) + metres
							Data.touch(player, "stats", "vehicles", "daily")
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
