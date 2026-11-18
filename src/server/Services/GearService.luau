-- Rider gear (2026-11-19; Config/Gear): City op "gear_buy" <id> buys an item once and puts it on; "gear_use" <id>
-- switches to an item already owned ("gear_use" "none:<slot>" takes that slot off). d.gear = { owned, bag, helmet }.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Gear = require(ReplicatedStorage.Shared.Config.Gear)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local City = require(script.Parent.CityRemote)

local Service = {}

local function gearOf(d)
	if type(d.gear) ~= "table" then d.gear = {} end
	if type(d.gear.owned) ~= "table" then d.gear.owned = {} end
	return d.gear
end

function Service.start()
	City.register("gear_buy", function(player, arg)
		local d = Data.get(player)
		local g = type(arg) == "string" and Gear.BY_ID[arg]
		if not d or not g then return false, "Bad request" end
		local gear = gearOf(d)
		if gear.owned[g.id] then return false, "You already have it" end
		if not Economy.spend(player, g.price, "gear:" .. g.id) then return false, "Not enough money" end
		gear.owned[g.id] = true
		gear[g.slot] = g.id
		Data.touch(player, "gear")
		return true, ("%s %s: bought and in use"):format(g.icon, g.en)
	end)
	City.register("gear_use", function(player, arg)
		local d = Data.get(player)
		if not d or type(arg) ~= "string" then return false, "Bad request" end
		local gear = gearOf(d)
		local slot = arg:match("^none:(%a+)$")
		if slot then
			gear[slot] = nil
		else
			local g = Gear.BY_ID[arg]
			if not g or not gear.owned[g.id] then return false, "Bad request" end
			gear[g.slot] = g.id
		end
		Data.touch(player, "gear")
		return true, ""
	end)
end

return Service
