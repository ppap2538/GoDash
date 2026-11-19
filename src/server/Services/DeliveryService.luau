-- Food delivery specifics for the job system: which orders exist, where they go, what the
-- customer says. The shared state machine, pay and rating live in JobService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Jobs = require(Shared.Config.Jobs)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Civic = require(script.Parent.CivicJobs)
local Regulars = require(script.Parent.RegularsService)
local RegularsCfg = require(Shared.Config.Regulars)

local Delivery = {}
Delivery.mode = "food"
Delivery.types = Jobs.FOOD
Delivery.event = "delivery"
Delivery.stat = "deliveries"

local FIRST = { "Khun Somchai", "Khun Malee", "Khun Nok", "Khun Lek", "Khun Ploy", "Khun Art", "Khun Fah", "Khun Boom", "Khun Mint", "Khun Tee", "Khun Aom", "Khun Bank" }

-- Every place an order can come from: restaurants, cafés, convenience stores and the markets.
local FOOD_POI = { market = true, nightmarket = true, reststop = true }
-- Opening hours on the game clock (2026-11-18, owner: "orders should follow the time of day"): late at
-- night only the 24-hour GoMart, the night market and the rest stop still cook; the fresh market sells
-- cooked food in the morning; cafés close in the evening.
local HOURS = {
	restaurant = { { 6.5, 22 } }, cafe = { { 6.5, 18 } }, convenience = nil, market = { { 4.5, 13 } },
	nightmarket = { { 16.5, 24 }, { 0, 2 } }, reststop = nil,
}
local function isOpen(kind: string, clock: number): boolean
	local h = HOURS[kind]
	if not h then return true end
	for _, w in ipairs(h) do
		if clock >= w[1] and clock < w[2] then return true end
	end
	return false
end
local pool
local function kitchens(world)
	if pool then return pool end
	pool = {}
	for _, s in ipairs(world.shops) do
		local stock = s.kind == "restaurant" and s.menu or Items.SHOPS[s.kind]
		if stock and #stock > 0 then table.insert(pool, { id = s.id, kind = s.kind, pos = s.pos, name = s.name, thai = s.thai, stock = stock }) end
	end
	for id, p in pairs(world.pois) do
		local stock = FOOD_POI[p.kind] and Items.SHOPS[p.kind]
		if stock and p.door then table.insert(pool, { id = id, kind = p.kind, pos = p.door, name = p.name, thai = p.thai, stock = stock }) end
	end
	return pool
end
local function openKitchens(world, clock: number)
	local out = {}
	for _, k in ipairs(kitchens(world)) do
		if isOpen(k.kind, clock) then table.insert(out, k) end
	end
	if #out == 0 then return kitchens(world) end
	return out
end
Delivery.isOpen = isOpen
local offered = {} -- [UserId] = { last pick-up offered, the one before }

-- ctx: { world, rng, weather, vehicles, npc }
-- (owner, 2026-11-16: "jobs should start from the nearest area".) The order comes from the kitchen
-- closest to the rider; the last two offered (and not taken) step aside for the next closest, so
-- declining walks outwards from where the rider is.
-- (2026-11-19) a big load (Jobs.BIGLOADS): from the nearest open shop of a fitting kind (the mall counts) to a home
local function bigLoad(root: Vector3, def, ctx, list)
	local load = Jobs.BIGLOADS[ctx.rng:NextInteger(1, #Jobs.BIGLOADS)]
	local best, bd
	local function consider(kind: string, pos: Vector3, name: string, thai: string?)
		if not table.find(load.from, kind) then return end
		local dd = (pos - root).Magnitude
		if not bd or dd < bd then best, bd = { pos = pos, name = name, thai = thai }, dd end
	end
	for _, k in ipairs(list) do consider(k.kind, k.pos, k.name, k.thai) end
	for _, p in pairs(ctx.world.pois) do
		if p.door and p.kind == "mall" then consider("mall", p.door, p.name, p.thai) end
	end
	if not best then return nil end
	local drop
	for _ = 1, 60 do
		local a = ctx.world.addresses[ctx.rng:NextInteger(1, #ctx.world.addresses)]
		local dd = (a.pos - best.pos).Magnitude
		if dd >= def.minDist * 0.75 and dd <= def.maxDist * 0.8 then drop = a break end
	end
	if not drop then return nil end
	return {
		pickup = best,
		dropoff = { pos = drop.pos, name = drop.name or (drop.kind == "house" and "Home" or "Shop house") },
		item = load.en, cargo = load.id,
		customer = FIRST[ctx.rng:NextInteger(1, #FIRST)],
	}
end

function Delivery.targets(player: Player, root: Vector3, def, ctx)
	local world = ctx.world
	local list = openKitchens(world, ctx.time.clock())
	if def.civic then return Civic.targets(player, root, def, ctx, list) end
	if def.absurd then return bigLoad(root, def, ctx, list) end
	if #list == 0 then return nil end
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b) return (a.pos - root).Magnitude < (b.pos - root).Magnitude end)
	local last = offered[player.UserId] or {}
	local best = sorted[1]
	for _, k in ipairs(sorted) do
		if not table.find(last, k.id) then best = k break end
	end
	offered[player.UserId] = { best.id, last[1] }
	-- (2026-11-19) one of the regular customers (Config/Regulars), at their hours, from their own home
	local reg = Regulars.pick(player, best.pos, def, ctx.time.clock(), ctx.rng)
	if reg then
		local dishR = Items.ById[best.stock[ctx.rng:NextInteger(1, #best.stock)]]
		return {
			pickup = { pos = best.pos, name = best.name, thai = best.thai },
			dropoff = { pos = reg.home.pos, name = reg.home.name or "Home" },
			item = dishR and dishR.name or "Food order",
			customer = reg.r.en, regular = reg.r.id,
		}
	end
	local drop
	for _ = 1, 60 do
		local a = world.addresses[ctx.rng:NextInteger(1, #world.addresses)]
		local dd = (a.pos - best.pos).Magnitude
		if dd >= def.minDist * 0.75 and dd <= def.maxDist * 0.8 then drop = a break end
	end
	if not drop then return nil end
	local dish = Items.ById[best.stock[ctx.rng:NextInteger(1, #best.stock)]]
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
	if (job.lateRatio or 0) > 1.5 then key = "customer_late" end -- (2026-11-19) the auntie gives you an earful
	if job.cargo then key = job.cargoDropped and "customer_bigload_dropped" or "customer_bigload" end
	if job.regularLine then
		-- a regular's own words at this point of their story (JobService set it)
		local r = RegularsCfg.BY_ID[job.regular]
		Net.fire(player, "Dialogue", { pos = job.dropoff.pos + Vector3.new(0, 4, 0), name = r and r.en or job.customer, th = job.regularLine[2], text = job.regularLine[1],
			nameTh = r and r.th or nil })
	else
		ctx.npc.say(player, job.dropoff.pos + Vector3.new(0, 4, 0), job.customer, ctx.npc.line(key))
	end
	local rig = job.npc
	job.npc = nil
	if rig then task.delay(6, function() ctx.npc.despawn(rig) end) end
end

function Delivery.cleanup(job, ctx)
	if job.npc then ctx.npc.despawn(job.npc); job.npc = nil end
end

return Delivery
