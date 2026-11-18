-- Vehicle insurance (2026-11-19; plans and prices in Config/Insurance). City op "insure" <plan id> buys 24 h of
-- cover (adds to what is left; switching plan keeps the time left on the new plan). d.insurance = { plan, untilT }.
-- AccidentService and VehicleService ask Service.share(player, "bills" | "repair") for the part the insurer pays.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Insurance = require(Shared.Config.Insurance)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local City = require(script.Parent.CityRemote)

local Service = {}

-- the plan in force now, or nil
function Service.plan(player: Player)
	local d = Data.get(player)
	local ins = d and d.insurance
	if type(ins) ~= "table" or type(ins.untilT) ~= "number" or ins.untilT <= os.time() then return nil end
	return Insurance.BY_ID[ins.plan]
end

-- the share (0..1) of a bill ("bills") or a repair ("repair") the insurer pays for this player now
function Service.share(player: Player, what: string): number
	local p = Service.plan(player)
	if not p then return 0 end
	return math.clamp(tonumber(p[what]) or 0, 0, 1)
end

function Service.start()
	City.register("insure", function(player, arg)
		local d = Data.get(player)
		local p = type(arg) == "string" and Insurance.BY_ID[arg]
		if not d or not p then return false, "Bad request" end
		local ins = type(d.insurance) == "table" and d.insurance or nil
		local now = os.time()
		local left = (ins and type(ins.untilT) == "number" and ins.untilT > now) and (ins.untilT - now) or 0
		if left > 3 * 24 * 3600 then return false, "You are covered for 3 days already" end
		if not Economy.spend(player, p.price, "insurance:" .. p.id) then return false, "Not enough money" end
		d.insurance = { plan = p.id, untilT = now + left + Insurance.HOURS * 3600 }
		Data.touch(player, "insurance")
		return true, ("🛡 %s: covered for %d h"):format(p.en, math.floor((left + Insurance.HOURS * 3600) / 3600 + 0.5))
	end)
end

return Service
