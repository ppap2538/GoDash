-- Ride-hailing specifics for the job system: passengers board the player's vehicle, chat during
-- the trip and rate speed, smoothness and safety. Shared flow, pay and rating live in JobService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Jobs = require(Shared.Config.Jobs)
local Net = require(Shared.Net)

local Passenger = {}
Passenger.mode = "ride"
Passenger.types = Jobs.RIDE
Passenger.event = "ride"
Passenger.stat = "rides"

local NAMES = { "Nong Mai", "Phi Ton", "Khun Dao", "Ajarn Wit", "Nong Bew", "Phi Jack", "Khun Kaew", "Nong Earth", "Phi Nan", "Khun Oat" }

function Passenger.targets(player: Player, root: Vector3, def, ctx)
	if def.civic then return require(script.Parent.CivicJobs).targets(player, root, def, ctx) end -- landmark rides (2026-11-18)
	local world = ctx.world
	local pick, pickD
	for _ = 1, 160 do -- (owner, 2026-11-16: "jobs should start from the nearest area")
		local a = world.addresses[ctx.rng:NextInteger(1, #world.addresses)]
		local dd = (a.pos - root).Magnitude
		if dd > 60 and dd < 3200 and (not pick or dd < pickD) then pick, pickD = a, dd end
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
	if v.def.seats == 0 then return false, "Rides need a motorbike or car with a passenger seat (KK Motors)" end
	if v.def.seats < def.seats then return false, "Needs " .. def.seats .. " passenger seats" end
	if def.comfort and v.stats.comfort < def.comfort then return false, "VIP riders want a more comfortable car" end
	-- friends riding along take passenger seats (VehicleService "PaxSeat")
	local free = v.def.seats
	for _, s in ipairs(v.model:GetChildren()) do
		if s.Name == "PaxSeat" and s:IsA("Seat") and s.Occupant then free -= 1 end
	end
	if free < def.seats then return false, "A friend is in the passenger seat" end
	return true
end

function Passenger.canAccept(player: Player, def, ctx): (boolean, string?)
	return vehicleOk(player, def, ctx)
end

local WALK = 7 -- studs per second the passenger walks in the boarding scene (client/Cutscene uses the same)

-- The passenger waits at the kerb, waving the rider down. A group ride waits together.
function Passenger.onAccept(player: Player, job, ctx)
	local pos = job.pickup.pos
	local _, p = ctx.world.graph:nearest(pos)
	local face = p and (Vector3.new(p.X, pos.Y, p.Z) - pos) or Vector3.new(0, 0, -1)
	if face.Magnitude < 0.1 then face = Vector3.new(0, 0, -1) end
	face = Vector3.new(face.X, 0, face.Z).Unit
	local names = ctx.npc.pedNames()
	job.peds = {}
	job.kerb = {}
	if #names > 0 then
		local sideways = Vector3.new(face.Z, 0, -face.X)
		for i = 1, job.def.seats do
			local name = names[ctx.rng:NextInteger(1, #names)]
			local at = Vector3.new(pos.X, 0.3, pos.Z) + sideways * (i - 1) * 2.6
			local fig = ctx.npc.figure(CFrame.lookAt(at, at + face), name, i == 1 and "hail" or "stand")
			if fig then
				table.insert(job.peds, name)
				table.insert(job.kerb, fig)
			end
		end
	end
	if #job.kerb == 0 then
		local at = Vector3.new(pos.X, 0.5, pos.Z)
		job.npc = ctx.npc.spawnTemp(CFrame.lookAt(at, at + face), ctx.rng:NextNumber() < 0.4 and "student" or nil)
	end
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

-- Boarding: the kerb figures go, the client shows the passenger walking to the vehicle and getting
-- on (client/Cutscene "board"), and when that walk is over the passengers sit on the seats for
-- everyone to see: behind the rider on a motorbike, inside a car.
function Passenger.onPickup(player: Player, job, ctx)
	local v = ctx.vehicles.get(player)
	if v then
		job.vehicleModel = v.model
		v.model:SetAttribute("PaxBusy", true) -- friends can't take the seat now (VehicleService "Ride along")
	end
	if v and job.npc then -- block figure (a place without the avatar models)
		local body = v.model:FindFirstChild("Body")
		local att = body and body:FindFirstChild("Pax1")
		if att then ctx.npc.board(job.npc, v.chassis, att.WorldCFrame) end
	end
	local body = v and v.model:FindFirstChild("Body")
	local seat1 = body and body:FindFirstChild("Pax1")
	if v and seat1 and job.kerb and #job.kerb > 0 then
		local kerbPos = job.kerb[1].model:GetPivot().Position
		for _, fig in ipairs(job.kerb) do ctx.npc.despawn(fig) end
		job.kerb = {}
		local cf = v.model:GetPivot()
		local seatPos = (seat1 :: Attachment).WorldPosition
		Net.fire(player, "Notify", "scene", {
			kind = "board", pos = kerbPos, seat = seatPos, ped = job.peds[1], name = job.customer,
			side = cf.RightVector, fwd = cf.LookVector, car = v.def.class == "car",
		})
		local walk = math.min((Vector3.new(kerbPos.X, 0, kerbPos.Z) - Vector3.new(seatPos.X, 0, seatPos.Z)).Magnitude, 28) / WALK
		local bike = v.def.class == "bike"
		task.delay(walk + 0.9, function()
			if job.cleaned or job.stage ~= "dropoff" or not v.model.Parent then return end
			job.riders = {}
			for i, name in ipairs(job.peds) do
				local att = body:FindFirstChild("Pax" .. i) :: Attachment?
				if att then
					local fig = ctx.npc.figure(att.WorldCFrame * CFrame.new(0, 0.15, 0), name, bike and "pillion" or "sit", nil)
					if fig then
						ctx.npc.weldTo(fig, v.chassis)
						table.insert(job.riders, fig)
					end
				end
			end
		end)
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

-- Arriving (called before the trip is scored): the passengers come off the seats; the client shows
-- them getting off and thanking the rider with a wai (client/Cutscene "alight"); afterwards they
-- stand at the door for a moment for everyone to see.
function Passenger.alight(player: Player, job, ctx)
	local v = ctx.vehicles.get(player)
	if job.vehicleModel then job.vehicleModel:SetAttribute("PaxBusy", nil) end
	local seatPos
	local body = v and v.model:FindFirstChild("Body")
	local att = body and body:FindFirstChild("Pax1")
	if att then seatPos = (att :: Attachment).WorldPosition end
	for _, fig in ipairs(job.riders or {}) do ctx.npc.despawn(fig) end
	job.riders = {}
	if job.npc then ctx.npc.despawn(job.npc); job.npc = nil end
	local door = Vector3.new(job.dropoff.pos.X, 0.3, job.dropoff.pos.Z)
	if v and seatPos and job.peds and #job.peds > 0 then
		local cf = v.model:GetPivot()
		Net.fire(player, "Notify", "scene", {
			kind = "alight", pos = door, seat = seatPos, ped = job.peds[1], name = job.customer,
			side = cf.RightVector, fwd = cf.LookVector, car = v.def.class == "car",
		})
	end
	local names = job.peds or {}
	task.delay(names[1] and 4.6 or 0, function()
		local placed = {}
		local face = seatPos and Vector3.new(seatPos.X - door.X, 0, seatPos.Z - door.Z) or Vector3.zAxis
		if face.Magnitude < 0.1 then face = Vector3.zAxis end
		for i, name in ipairs(names) do
			local at = door + Vector3.new(face.Unit.Z, 0, -face.Unit.X) * (i - 1) * 2.6
			local fig = ctx.npc.figure(CFrame.lookAt(at, at + face.Unit), name, "stand")
			if fig then table.insert(placed, fig) end
		end
		if #placed == 0 and not names[1] then
			local fig = ctx.npc.spawnTemp(CFrame.new(door + Vector3.new(0, 0.2, 0)), nil, true)
			if fig then table.insert(placed, fig) end
		end
		task.delay(6, function()
			for _, fig in ipairs(placed) do ctx.npc.despawn(fig) end
		end)
	end)
end

function Passenger.onDropoff(player: Player, job, stars: number, ctx)
	local key = stars >= 4.5 and "passenger_good" or (stars >= 3 and "passenger_ok" or "passenger_bad")
	task.delay(2.5, function() -- once the passenger is off the vehicle
		ctx.npc.say(player, job.dropoff.pos + Vector3.new(0, 4, 0), job.customer, ctx.npc.line(key))
	end)
end

function Passenger.cleanup(job, ctx)
	job.cleaned = true
	if job.vehicleModel then job.vehicleModel:SetAttribute("PaxBusy", nil) end
	if job.npc then ctx.npc.despawn(job.npc); job.npc = nil end
	for _, fig in ipairs(job.kerb or {}) do ctx.npc.despawn(fig) end
	for _, fig in ipairs(job.riders or {}) do ctx.npc.despawn(fig) end
	job.kerb, job.riders = {}, {}
end

return Passenger
