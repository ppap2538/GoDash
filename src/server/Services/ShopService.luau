-- Shops, markets and the small services at landmarks (bus, hospital, stupa, police).
-- The client only names what it wants; price, stock, distance and money are checked here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
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
		local poi = world.pois.hospital
		if not poi or not near(player, poi.door) then return false, "Go to the hospital" end
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
				Net.fire(player, "Notify", "toast", { text = msg or "", good = ok, bad = not ok })
			end)
		end
	end
	service("hospital", "Get treatment (฿150)", "Khon Kaen Hospital", "heal")
	service("stupa", "Pay respects", "Kaen Nakhon Stupa", "merit")
	service("police", "Safe driver bonus", "Police Station", "safedriver")

	Net.fn("Shop", { "string", "string", "string?", "int?" }, handle, 6)
end

function Shop.get(id: string) return shops[id] end

return Shop
