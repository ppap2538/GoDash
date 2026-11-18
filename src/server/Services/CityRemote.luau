-- One remote ("City") for the small city services that answer the phone apps: finance (instalments,
-- repo) and the driving licence. Each service registers its operations here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local City = {}
local ops = {} -- [op] = function(player, arg) -> (ok, message, extra)

function City.register(op: string, fn)
	ops[op] = fn
end

function City.start()
	Net.fn("City", { "string", "string?" }, function(player, op, arg)
		local fn = ops[op]
		if not fn then return false, "Unknown request" end
		return fn(player, arg)
	end, 4)
end

return City
