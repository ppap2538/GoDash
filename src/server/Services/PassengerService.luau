-- Ride-hailing specifics for the job system: passengers board the player's vehicle, chat during
-- the trip and rate speed, smoothness and safety. Shared flow, pay and rating live in JobService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Jobs = require(Shared.Config.Jobs)

local Passenger = {}
Passenger.mode = "ride"
Passenger.types = Jobs.RIDE
Passenger.event = "ride"
Passenger.stat = "rides"

local NAMES = { "Nong Mai", "Phi Ton", "Khun Dao", "Ajarn Wit", "Nong Bew", "Phi Jack", "Khun Kaew", "Nong Earth", "Phi Nan", "Khun Oat" }

function Passenger.targets(player: Player, root: Vector3, def, ctx)
	local world = ctx.world
	local pick, pickD
	for _ = 1, 40 do
		local a = world.addresses[ctx.rng:NextInteger(1, #world.addresses)]
		local dd = (a.pos - root).Magnitude
		if dd < 3200 and (not pick or dd < pickD) then pick, pickD = a, dd end
	end
	if not pick then pick = world.addresses[ctx.rng:NextInteger(1, #world.addresses)] end
	local drop
	for _ = 1, 60 do
		local a = world.addresses[ctx.rng:NextInteger(1, #world.addresses)]
		local dd = (a.pos - pick.pos).Magnitude
		if dd >= def.minDist * 0.75 and dd <= def.maxDist * 0.8 then drop = a break end
	end
	if not drop then return nil end
	-- landmarks make better destinations than anonymous doors
	if ctx.rng:NextNumber() < 0.45 then
		local list = {}
		for _, poi in pairs(world.pois) do
			local dd = (poi.door - pick.pos).Magnitude
			if dd >= def.minDist * 0.75 and dd <= def.maxDist * 0.85 then table.insert(list, poi) end
		end
		if #list > 0 then
			local poi = list[ctx.rng:NextInteger(1, #list)]
			drop = { pos = Vector3.new(poi.door.X, 0, poi.door.Z), name = poi.name, kind = poi.kind }
		end
	end
	return {
		pickup = { pos = pick.pos, name = pick.name or "Pick-up point" },
		dropoff = { pos = drop.pos, name = drop.name or (drop.kind == "house" and "Home" or "Shop house") },
		item = def.seats > 1 and (def.seats .. " passengers") or "1 passenger",
		customer = NAMES[ctx.rng:NextInteger(1, #NAMES)],
	}
end

local function vehicleOk(player: Player, def, ctx): (boolean, string?)
	local v = ctx.vehicles.get(player)
	if not v then return false, "Bring out a vehicle first (Garage app)" end
	if v.def.seats < def.seats then return false, "Needs " .. def.seats .. " passenger seats" end
	if def.comfort and v.stats.comfort < def.comfort then return false, "VIP riders want a more comfortable car" end
	return true
end

function Passenger.canAccept(player: Player, def, ctx): (boolean, string?)
	return vehicleOk(player, def, ctx)
end

-- The passenger waits at the kerb.
function Passenger.onAccept(player: Player, job, ctx)
	local pos = job.pickup.pos
	local _, p = ctx.world.graph:nearest(pos)
	local face = p and (Vector3.new(p.X, pos.Y, p.Z) - pos) or Vector3.new(0, 0, -1)
	if face.Magnitude < 0.1 then face = Vector3.new(0, 0, -1) end
	local at = Vector3.new(pos.X, 0.5, pos.Z)
	job.npc = ctx.npc.spawnTemp(CFrame.lookAt(at, at + face.Unit), ctx.rng:NextNumber() < 0.4 and "student" or nil)
end

local function stopped(player: Player, ctx): (boolean, string?)
	local v = ctx.vehicles.driving(player)
	if not v then return false, "You need to be in your vehicle" end
	if ctx.vehicles.speed(player) > 7 then return false, "Stop the vehicle first" end
	return true
end

function Passenger.canPickup(player: Player, job, ctx): (boolean, string?)
	local ok, msg = vehicleOk(player, job.def, ctx)
	if not ok then return false, msg end
	return stopped(player, ctx)
end

function Passenger.onPickup(player: Player, job, ctx)
	local v = ctx.vehicles.get(player)
	if v and job.npc then
		local body = v.model:FindFirstChild("Body")
		local att = body and body:FindFirstChild("Pax1")
		if att then ctx.npc.board(job.npc, v.chassis, att.WorldCFrame) end
		job.vehicleModel = v.model
	end
	ctx.npc.say(player, job.pickup.pos + Vector3.new(0, 4, 0), job.customer, ctx.npc.line("passenger_pickup"))
	job.chatAt = os.clock() + ctx.rng:NextNumber(10, 18)
	job.scared = 0
end

-- Called every second while the passenger is on board.
function Passenger.tick(player: Player, job, ctx)
	if job.stage ~= "dropoff" then return end
	local tele = ctx.vehicles.telemetry(player)
	local v = ctx.vehicles.get(player)
	if not tele or not v then return end
	local bad = tele.crashes * 3 + tele.harsh
	if bad > (job.scared or 0) then
		job.scared = bad
		job.chatAt = os.clock() + 12
		ctx.npc.say(player, v.chassis.Position + Vector3.new(0, 5, 0), job.customer, ctx.npc.line("passenger_scared"))
	elseif os.clock() >= (job.chatAt or 0) then
		job.chatAt = os.clock() + ctx.rng:NextNumber(16, 28)
		ctx.npc.say(player, v.chassis.Position + Vector3.new(0, 5, 0), job.customer, ctx.npc.line("passenger_ride"))
	end
	-- the passenger left with the vehicle? (vehicle stored or replaced mid-ride)
	if job.vehicleModel and not job.vehicleModel.Parent then job.lostPassenger = true end
end

function Passenger.canDropoff(player: Player, job, ctx): (boolean, string?)
	if job.lostPassenger then return false, "Your passenger is gone. Cancel the ride." end
	return stopped(player, ctx)
end

function Passenger.onDropoff(player: Player, job, stars: number, ctx)
	local key = stars >= 4.5 and "passenger_good" or (stars >= 3 and "passenger_ok" or "passenger_bad")
	ctx.npc.say(player, job.dropoff.pos + Vector3.new(0, 4, 0), job.customer, ctx.npc.line(key))
	local rig = job.npc
	job.npc = nil
	if rig then
		-- step out onto the kerb, then leave
		local at = Vector3.new(job.dropoff.pos.X, 0.5, job.dropoff.pos.Z)
		local placed = ctx.npc.spawnTemp(CFrame.new(at), nil, true)
		ctx.npc.despawn(rig)
		task.delay(6, function() ctx.npc.despawn(placed) end)
	end
end

function Passenger.cleanup(job, ctx)
	if job.npc then ctx.npc.despawn(job.npc); job.npc = nil end
end

return Passenger
