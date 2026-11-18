-- Regular customers (2026-11-19; people and lines in Config/Regulars). Each has a home: the address nearest their
-- anchor place (a market, the university, KK Motors...) but at least 150 studs away from it, chosen when the
-- server starts so it is the same house all session. DeliveryService asks Service.pick when it builds a food
-- order; JobService calls Service.done after the drop-off (trust +1, the line to say, the gift at the 12th).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Regulars = require(ReplicatedStorage.Shared.Config.Regulars)
local Data = require(script.Parent.PlayerDataService)

local Service = {}
local homes = {} -- [id] = address { pos, name, kind }
local lastFor = {} -- [UserId] = { [id] = os.clock() of the last order offered }

function Service.init(world)
	local pois = {}
	for k, p in pairs(world.pois or {}) do
		if type(p) == "table" and p.pos then pois[p.id or k] = p end
	end
	for _, r in ipairs(Regulars.LIST) do
		local anchor = pois[r.anchor]
		if anchor then
			local best, bd
			for _, a in ipairs(world.addresses or {}) do
				local d = (a.pos - anchor.pos).Magnitude
				if d > 150 and (not bd or d < bd) and (a.kind == "house" or a.kind == "dorm" or a.kind == nil) then best, bd = a, d end
			end
			homes[r.id] = best
		end
	end
	Players.PlayerRemoving:Connect(function(p) lastFor[p.UserId] = nil end)
end

-- a regular who could order from this kitchen now (or nil): awake at this hour, home within the order's range,
-- not offered to this rider in the last 8 minutes; about one order in four when one fits
function Service.pick(player: Player, kitchenPos: Vector3, def, clock: number, rng: Random)
	if rng:NextNumber() > 0.27 then return nil end
	local mine = lastFor[player.UserId] or {}
	lastFor[player.UserId] = mine
	local options = {}
	for _, r in ipairs(Regulars.LIST) do
		local home = homes[r.id]
		if home and Regulars.awake(r, clock) and os.clock() - (mine[r.id] or -1e9) > 480 then
			local dd = (home.pos - kitchenPos).Magnitude
			if dd >= def.minDist * 0.5 and dd <= def.maxDist then table.insert(options, { r = r, home = home }) end
		end
	end
	if #options == 0 then return nil end
	local o = options[rng:NextInteger(1, #options)]
	mine[o.r.id] = os.clock()
	return o
end

-- how many deliveries this rider has made to regular id
function Service.count(player: Player, id: string): number
	local d = Data.get(player)
	return (d and type(d.regulars) == "table" and tonumber(d.regulars[id])) or 0
end

-- a delivery to regular id is done: returns the new count, the line for it (or nil) and the gift (0 or more)
function Service.done(player: Player, id: string)
	local d = Data.get(player)
	local r = Regulars.BY_ID[id]
	if not d or not r then return 0, nil, 0 end
	if type(d.regulars) ~= "table" then d.regulars = {} end
	local n = (tonumber(d.regulars[id]) or 0) + 1
	d.regulars[id] = n
	Data.touch(player, "regulars")
	return n, r.lines[n], (n == 12) and Regulars.GIFT or 0
end

return Service
