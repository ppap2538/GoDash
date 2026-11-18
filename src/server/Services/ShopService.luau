-- Shops, markets and the small services at landmarks (bus, hospital, stupa, police).
-- The client only names what it wants; price, stock, distance and money are checked here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local GameCfg = require(Shared.Config.Game)
local Crops = require(Shared.Config.Crops)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Inventory = require(script.Parent.InventoryService)
local NPC = require(script.Parent.NPCService)

local Shop = {}
local shops = {} -- [id] = { id, kind, name, thai, pos, stock = {itemId}, buys = "crop" | "cooked" | nil }
local world
local missions, lifestyle

local RANGE = 60

local function near(player: Player, pos: Vector3, range: number?): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root ~= nil and (root.Position - pos).Magnitude <= (range or RANGE)
end
Shop.near = near

local function sellPrice(item): number
	if item.kind == "crop" then
		return math.max(1, math.floor(item.sell * Crops.marketMult(item.id, Util.dayNumber()) + 0.5))
	end
	return item.sell or 0
end
Shop.sellPrice = sellPrice

-- The meal in a shop's stock that does most for one need ("hunger" / "energy"); cheaper wins a tie.
local function bestFor(stock, want: string, budget: number?)
	local best
	for _, sid in ipairs(stock) do
		local it = Items.ById[sid]
		if it and it.kind == "food" and (it.price or 0) > 0 and (not budget or it.price <= budget) then
			local v, bv = it[want] or 0, best and (best[want] or 0) or -1
			if v > bv or (v == bv and it.price < best.price) then best = it end
		end
	end
	return best
end

local function register(id, kind, name, thai, pos, stock, buys)
	shops[id] = { id = id, kind = kind, name = name, thai = thai, pos = pos, stock = stock or {}, buys = buys }
	local action = (#(stock or {}) > 0) and "Shop" or "Sell"
	if buys and stock and #stock > 0 then action = "Shop / Sell" end
	NPC.prompt(pos, action, name, "shop", id)
end

local function openShop(player: Player, id: string)
	local s = shops[id]
	if not s then return end
	local sells = {}
	if s.buys then
		for _, it in ipairs(Items.List) do
			if (s.buys == "crop" and it.kind == "crop") or (s.buys == "cooked" and it.cooked) then
				table.insert(sells, { id = it.id, price = sellPrice(it) })
			end
		end
	end
	NPC.say(player, s.pos, s.name, NPC.line(s.kind == "restaurant" and "staff_idle" or (s.kind == "agri" and "farmer" or "shopkeeper")))
	Net.fire(player, "OpenUI", "shop", { id = id, name = s.name, thai = s.thai, kind = s.kind, stock = s.stock, sells = sells })
end

local function handle(player: Player, op: string, id: string, itemId: string?, qty: number?)
	local d = Data.get(player)
	if not d then return false, "Not ready" end
	Economy.rollDay(d)
	if op == "buy" or op == "sell" then
		local s = shops[id]
		local item = itemId and Items.ById[itemId]
		if not s or not item then return false, "Unknown shop or item" end
		if not near(player, s.pos) then return false, "Too far from the shop" end
		local n = math.clamp(qty or 1, 1, op == "sell" and 999 or 50)
		if op == "buy" then
			if not table.find(s.stock, item.id) then return false, "Not sold here" end
			if not Inventory.canAdd(player, item.id, n) then return false, "Your bag is full (eat something or use your fridge)" end
			local cost = item.price * n
			if not Economy.spend(player, cost, "shop:" .. item.id) then return false, "Not enough money" end
			Inventory.add(player, item.id, n)
			return true, ("Bought %d × %s"):format(n, item.name)
		else
			if not ((s.buys == "crop" and item.kind == "crop") or (s.buys == "cooked" and item.cooked)) then return false, "They don't buy that here" end
			n = math.min(n, 999)
			local have = Inventory.count(player, item.id)
			if qty == 0 then n = have end -- 0 = sell all
			if n <= 0 or have < n then return false, "You don't have that many" end
			if not Inventory.remove(player, item.id, n) then return false, "You don't have that many" end
			local gain = sellPrice(item) * n
			Economy.add(player, gain, "sell:" .. item.id, true)
			if item.kind == "crop" then missions.progress(player, "sell_crop", n) end
			missions.progress(player, "earn", gain)
			Net.fire(player, "Reward", { title = "Sold " .. n .. " × " .. item.name, money = gain, small = true })
			return true, "Sold for " .. Util.money(gain)
		end
	elseif op == "eatnow" then
		-- buy one meal and eat it on the spot (no bag, no phone). itemId = an item, or "hunger" /
		-- "energy" to let the shop pick what helps most with what the player can afford.
		local s = shops[id]
		if not s then return false, "Unknown shop or item" end
		if not near(player, s.pos) then return false, "Too far from the shop" end
		local item = itemId and Items.ById[itemId]
		if not item then
			local want = itemId == "energy" and "energy" or "hunger"
			item = bestFor(s.stock, want, d.money)
			if not item then
				return false, bestFor(s.stock, want) and "Not enough money" or "Nothing to eat here"
			end
		end
		if item.kind ~= "food" or not table.find(s.stock, item.id) then return false, "Not sold here" end
		if not Economy.spend(player, item.price, "eat:" .. item.id) then return false, "Not enough money" end
		lifestyle.consume(player, item)
		missions.progress(player, "eat", 1)
		-- the client plays "walk in and eat / drink" (client/Cutscene)
		Net.fire(player, "Notify", "scene", { kind = (item.hunger or 0) < 12 and "drink" or "eat", pos = s.pos, item = item.name })
		return true, "Ate " .. item.name
	elseif op == "bus" then
		-- id = stop you are at, itemId = destination stop
		local from, to
		for _, b in ipairs(world.busStops) do
			if b.id == id then from = b end
			if b.id == itemId then to = b end
		end
		if not from or not to or from == to then return false, "Pick a destination" end
		if not near(player, from.pos, 40) then return false, "Go to the bus stop" end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.SeatPart then return false, "Get off your vehicle first" end
		if not Economy.spend(player, 30, "bus") then return false, "The fare is ฿30" end
		char:PivotTo(CFrame.new(to.pos + Vector3.new(0, 3, 0)))
		return true, "Arrived at " .. to.name
	elseif op == "heal" then
		-- any hospital: Khon Kaen Hospital or Srinagarind (2026-11-18), the one the player is at
		local poi
		for _, p in pairs(world.pois) do
			if p.kind == "hospital" and near(player, p.door) then poi = p break end
		end
		if not poi then return false, "Go to the hospital" end
		-- injuries from falls first (server/HealthService): the gold card visit + medicine, then the
		-- treatment scene (client/Cutscene "treat"). Otherwise the old check-up for the tired and hungry.
		local Health = require(script.Parent.HealthService)
		local cost = Health.treatCost(player)
		if cost then
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.SeatPart then return false, "Get off your vehicle first" end
			if not Economy.spend(player, cost, "hospital") then return false, "Treatment costs " .. Util.money(cost) end
			local inj = Health.get(player)
			Health.heal(player)
			d.energy = math.max(0, d.energy - 6) -- the queue is long
			Data.touch(player, "energy")
			Net.fire(player, "Notify", "scene", { kind = "treat", amount = cost, injury = inj, pos = poi.door, name = poi.name, thai = poi.thai })
			return true, ""
		end
		if d.energy >= 70 and d.hunger >= 70 then return false, "You're healthy already" end
		if not Economy.spend(player, 150, "hospital") then return false, "Treatment costs ฿150" end
		d.energy = math.max(d.energy, 70); d.hunger = math.max(d.hunger, 70)
		Data.touch(player, "energy", "hunger")
		return true, "You feel much better"
	elseif op == "merit" then
		local poi = world.pois.stupa
		if not poi or not near(player, poi.door) then return false, "Go to the stupa" end
		if d.daily.merit >= 1 then return false, "You already visited today" end
		d.daily.merit = 1
		Data.touch(player, "daily")
		lifestyle.add(player, nil, nil, 25)
		return true, "A peaceful moment. Happiness +25"
	elseif op == "safedriver" then
		local poi = world.pois.police
		if not poi or not near(player, poi.door) then return false, "Go to the police station" end
		if d.daily.safeBonus >= 1 then return false, "Already claimed today" end
		if d.ratingCount < 3 or d.rating < 4.5 then return false, "Needs a 4.5★ rating (3+ jobs)" end
		d.daily.safeBonus = 1
		Data.touch(player, "daily")
		Economy.add(player, 120, "safedriver")
		return true, "Safe driver bonus +฿120"
	end
	return false, "Bad request"
end

function Shop.start(w, deps)
	world = w
	missions, lifestyle = deps.missions, deps.lifestyle
	-- Free rest spots (the hub benches, the lakeside sala). The places listed them, the Guide and the
	-- "tired" pop-up send players there, but until 2026-11-16 nothing ever made the prompt: a rider
	-- with no home had no way to rest.
	NPC.handle("rest", function(player, _id, part)
		lifestyle.startRest(player, part.Position, GameCfg.REST_BENCH_RATE, "Resting", 0.05)
		-- sit them on the nearest free bench, then the client films it (client/Cutscene "rest")
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local best, bd
		for _, seat in ipairs(game:GetService("CollectionService"):GetTagged("RestSeat")) do
			if seat:IsA("Seat") and not seat.Occupant then
				local d = (seat.Position - part.Position).Magnitude
				if d < 13 and (not bd or d < bd) then best, bd = seat, d end
			end
		end
		if hum and best and not hum.SeatPart then best:Sit(hum) end
		Net.fire(player, "Notify", "scene", { kind = "rest", pos = best and best.Position or part.Position })
	end)
	for id, poi in pairs(world.pois) do
		for i, ex in ipairs(poi.extra or {}) do
			if ex.kind == "rest" then NPC.prompt(ex.pos, ex.action, ex.object, "rest", id .. "_rest" .. i) end
		end
	end
	for _, s in ipairs(world.shops) do
		local stock = s.kind == "restaurant" and s.menu or Items.SHOPS[s.kind]
		register(s.id, s.kind, s.name, s.thai, s.pos, stock)
	end
	local P = world.pois
	local function poiShop(id, kind, stock, buys)
		local p = P[id]
		if p then register("poi_" .. id, kind, p.name, p.thai, p.door, stock, buys) end
	end
	poiShop("nightmarket", "nightmarket", Items.SHOPS.nightmarket)
	poiShop("freshmarket", "market", Items.SHOPS.market, "cooked")
	poiShop("seedshop", "seedshop", Items.SHOPS.seedshop)
	poiShop("agri", "agri", {}, "crop")
	poiShop("reststop", "reststop", Items.SHOPS.reststop)
	poiShop("mall", "convenience", { "water", "energy_drink", "milk_tea", "coffee", "moo_ping", "mango_sticky", "chicken_rice" })
	poiShop("station", "reststop", Items.SHOPS.reststop)
	NPC.handle("shop", openShop)

	for _, b in ipairs(world.busStops) do
		NPC.prompt(b.pos, "Take the bus (฿30)", b.name, "bus", b.id)
	end
	NPC.handle("bus", function(player, id)
		local list = {}
		for _, b in ipairs(world.busStops) do table.insert(list, { id = b.id, name = b.name, thai = b.thai }) end
		Net.fire(player, "OpenUI", "bus", { from = id, stops = list })
	end)
	local function service(poiId, action, object, op)
		local p = P[poiId]
		if p then
			NPC.prompt(p.door, action, object, "service_" .. op, poiId, 0.6)
			NPC.handle("service_" .. op, function(player)
				local ok, msg = handle(player, op, poiId)
				if msg and msg ~= "" then Net.fire(player, "Notify", "toast", { text = msg, good = ok, bad = not ok }) end
			end)
		end
	end
	service("hospital", "Get treated (gold card ฿30+)", "Khon Kaen Hospital", "heal")
	service("hospital2", "Get treated (gold card ฿30+)", "Srinagarind Hospital", "heal")
	service("stupa", "Pay respects", "Kaen Nakhon Stupa", "merit")
	service("police", "Safe driver bonus", "Police Station", "safedriver")

	Net.fn("Shop", { "string", "string", "string?", "int?" }, handle, 6)
end

function Shop.get(id: string) return shops[id] end

-- Every place that sells something to eat or drink, for the client's "go and eat" navigation:
-- { id, name, thai, pos, hunger = { id, price, value }?, energy = { id, price, value }? }
function Shop.places()
	local out = {}
	for id, s in pairs(shops) do
		local h, e = bestFor(s.stock, "hunger"), bestFor(s.stock, "energy")
		if h or e then
			table.insert(out, {
				id = id, name = s.name, thai = s.thai, pos = s.pos,
				hunger = h and { id = h.id, price = h.price, value = h.hunger or 0 } or nil,
				energy = e and { id = e.id, price = e.price, value = e.energy or 0 } or nil,
			})
		end
	end
	return out
end

return Shop
