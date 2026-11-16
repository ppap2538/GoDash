-- Food delivery specifics for the job system: which orders exist, where they go, what the
-- customer says. The shared state machine, pay and rating live in JobService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Jobs = require(Shared.Config.Jobs)
local Items = require(Shared.Config.Items)

local Delivery = {}
Delivery.mode = "food"
Delivery.types = Jobs.FOOD
Delivery.event = "delivery"
Delivery.stat = "deliveries"

local FIRST = { "Khun Somchai", "Khun Malee", "Khun Nok", "Khun Lek", "Khun Ploy", "Khun Art", "Khun Fah", "Khun Boom", "Khun Mint", "Khun Tee", "Khun Aom", "Khun Bank" }

-- ctx: { world, rng, weather, vehicles, npc }
function Delivery.targets(player: Player, root: Vector3, def, ctx)
	local world = ctx.world
	if #world.restaurants == 0 then return nil end
	-- one of the restaurants closest to the rider (the very closest few on a bicycle)
	local sorted = table.clone(world.restaurants)
	table.sort(sorted, function(a, b) return (a.pos - root).Magnitude < (b.pos - root).Magnitude end)
	local v = ctx.vehicles.get(player)
	local slow = (not v) or v.def.topSpeed < 40
	local best = sorted[ctx.rng:NextInteger(1, math.min(#sorted, slow and 3 or 8))]
	local drop
	for _ = 1, 60 do
		local a = world.addresses[ctx.rng:NextInteger(1, #world.addresses)]
		local dd = (a.pos - best.pos).Magnitude
		if dd >= def.minDist * 0.75 and dd <= def.maxDist * 0.8 then drop = a break end
	end
	if not drop then return nil end
	local dish = Items.ById[best.menu[ctx.rng:NextInteger(1, #best.menu)]]
	return {
		pickup = { pos = best.pos, name = best.name, thai = best.thai },
		dropoff = { pos = drop.pos, name = drop.name or (drop.kind == "house" and "Home" or drop.kind == "dorm" and "Dormitory" or "Shop house") },
		item = dish and dish.name or "Food order",
		customer = FIRST[ctx.rng:NextInteger(1, #FIRST)],
	}
end

function Delivery.canAccept(player: Player, def, ctx): (boolean, string?)
	if def.cargo and def.cargo > 2 then
		local v = ctx.vehicles.get(player)
		if not v or v.def.cargo < def.cargo then
			return false, "This order needs a vehicle with cargo " .. def.cargo .. "+ (a car or pickup)"
		end
	end
	return true
end

-- Customer waits at the drop-off as soon as the job is accepted.
function Delivery.onAccept(player: Player, job, ctx)
	local pos = job.dropoff.pos
	local e, p = ctx.world.graph:nearest(pos)
	local face = p and (Vector3.new(p.X, pos.Y, p.Z) - pos) or Vector3.new(0, 0, -1)
	if face.Magnitude < 0.1 then face = Vector3.new(0, 0, -1) end
	local at = Vector3.new(pos.X, 0.5, pos.Z) - face.Unit * 1.5
	job.npc = ctx.npc.spawnTemp(CFrame.lookAt(at, at + face.Unit), nil, true)
end

function Delivery.canPickup(player: Player, job, ctx): (boolean, string?)
	return true
end

function Delivery.onPickup(player: Player, job, ctx)
	ctx.npc.say(player, job.pickup.pos + Vector3.new(0, 4, 0), job.pickup.name, ctx.npc.line("staff_ready"))
end

function Delivery.canDropoff(player: Player, job, ctx): (boolean, string?)
	return true
end

function Delivery.onDropoff(player: Player, job, stars: number, ctx)
	local key = stars >= 4.5 and "customer_good" or (stars >= 3 and "customer_ok" or "customer_bad")
	if stars >= 4 and ctx.weather.isRaining() then key = "customer_rain" end
	ctx.npc.say(player, job.dropoff.pos + Vector3.new(0, 4, 0), job.customer, ctx.npc.line(key))
	local rig = job.npc
	job.npc = nil
	if rig then task.delay(6, function() ctx.npc.despawn(rig) end) end
end

function Delivery.cleanup(job, ctx)
	if job.npc then ctx.npc.despawn(job.npc); job.npc = nil end
end

return Delivery
