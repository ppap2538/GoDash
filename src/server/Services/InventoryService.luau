-- Items carried by the player. Counts only ever change here, on the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)

local Inventory = {}
Inventory.FOOD_LIMIT = 16 -- meals and drinks you can carry; the fridge at home holds more

function Inventory.count(player: Player, id: string): number
	local d = Data.get(player)
	return d and d.inventory[id] or 0
end

function Inventory.foodCount(player: Player): number
	local d = Data.get(player)
	if not d then return 0 end
	local n = 0
	for id, c in pairs(d.inventory) do
		local it = Items.ById[id]
		if it and it.kind == "food" then n += c end
	end
	return n
end

function Inventory.canAdd(player: Player, id: string, qty: number): boolean
	local it = Items.ById[id]
	if not it then return false end
	if it.kind == "food" then return Inventory.foodCount(player) + qty <= Inventory.FOOD_LIMIT end
	return Inventory.count(player, id) + qty <= 999
end

function Inventory.add(player: Player, id: string, qty: number): boolean
	local d = Data.get(player)
	if not d or not Items.ById[id] or qty <= 0 then return false end
	d.inventory[id] = (d.inventory[id] or 0) + math.floor(qty)
	Data.touch(player, "inventory")
	return true
end

function Inventory.remove(player: Player, id: string, qty: number): boolean
	local d = Data.get(player)
	if not d or qty <= 0 then return false end
	local have = d.inventory[id] or 0
	if have < qty then return false end
	have -= math.floor(qty)
	d.inventory[id] = have > 0 and have or nil
	Data.touch(player, "inventory")
	return true
end

function Inventory.start(lifestyle, missions)
	Net.fn("Inventory", { "string", "string", "int?" }, function(player, op, id, qty)
		local it = Items.ById[id]
		if not it then return false, "Unknown item" end
		if op == "eat" then
			if it.kind ~= "food" then return false, "You can't eat that" end
			if not Inventory.remove(player, id, 1) then return false, "You don't have any" end
			lifestyle.consume(player, it)
			missions.progress(player, "eat", 1)
			return true, "Ate " .. it.name
		elseif op == "drop" then
			local n = math.clamp(qty or 1, 1, 99)
			if not Inventory.remove(player, id, n) then return false, "You don't have that many" end
			return true, "Dropped"
		end
		return false, "Bad request"
	end, 5)
end

return Inventory
