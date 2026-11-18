-- Personal bests for stunts (2026-11-19, client/Stunts): the longest wheelie and burnout, kept in d.stats.
-- City op "stunt_best" = "w,<seconds>" or "b,<seconds>". The client times it; the server only keeps a
-- plausible number (a stunt is done on the vehicle you are driving, and no longer than LIMIT seconds).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Data = require(script.Parent.PlayerDataService)
local City = require(script.Parent.CityRemote)
local Metrics = require(script.Parent.MetricsService)

local Service = {}
local LIMIT = 300
local _ = ReplicatedStorage

function Service.start(deps)
	local vehicles = deps and deps.vehicles
	City.register("stunt_best", function(player, arg)
		local d = Data.get(player)
		if not d then return false, "" end
		local kind, sec = string.match(tostring(arg or ""), "^([wb]),(%d+%.?%d*)$")
		local s = tonumber(sec)
		if not kind or not s or s <= 0 or s > LIMIT then return false, "" end
		if vehicles and not vehicles.driving(player) then return false, "" end
		local key = kind == "w" and "bestWheelie" or "bestBurnout"
		d.stats[key] = d.stats[key] or 0
		if s <= d.stats[key] then return true, "" end
		d.stats[key] = math.floor(s * 10 + 0.5) / 10
		Data.touch(player, "stats")
		Metrics.event(player, kind == "w" and "Wheelie record" or "Burnout record", d.stats[key])
		local th = not (d.settings and d.settings.lang == "en")
		if kind == "w" then
			return true, th and ("🔥 สถิติใหม่! ยกล้อ %.1f วินาที"):format(d.stats[key]) or ("🔥 New record! Wheelie %.1f s"):format(d.stats[key])
		end
		return true, th and ("🔥 สถิติใหม่! เบิร์นเอาท์ %.1f วินาที"):format(d.stats[key]) or ("🔥 New record! Burnout %.1f s"):format(d.stats[key])
	end)
end

return Service
