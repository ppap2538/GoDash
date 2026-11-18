-- Roblox Analytics (Creator Dashboard > Analytics), added 2026-11-17 so we can see where new riders give
-- up and where the money comes from and goes, instead of guessing.
--   * Onboarding funnel (new riders only, each step once, in order): joined, got on a vehicle, went
--     online, accepted an order, picked up, first / second / third job done
--   * Economy events for every cash change that EconomyService makes (currency "Baht")
-- Every call is wrapped: analytics must never break the game.
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local Data = require(script.Parent.PlayerDataService)

local Metrics = {}

Metrics.STEPS = {
	"Joined", "Got on a vehicle", "Went online", "Accepted an order", "Picked up",
	"First job done", "Second job done", "Third job done",
}
local INDEX = {}
for i, name in ipairs(Metrics.STEPS) do INDEX[name] = i end

local nextStep = {} :: { [Player]: number } -- only new riders have an entry

-- Log `name` and any earlier step that it implies (you can't pick up without accepting).
function Metrics.step(player: Player, name: string)
	local n = INDEX[name]
	local from = nextStep[player]
	if not n or not from or n < from then return end
	for i = from, n do
		pcall(function() AnalyticsService:LogOnboardingFunnelStepEvent(player, i, Metrics.STEPS[i]) end)
	end
	nextStep[player] = n + 1
	if n >= #Metrics.STEPS then nextStep[player] = nil end
end

-- A finished job (delivery or ride): counts toward the first three.
function Metrics.jobDone(player: Player, total: number)
	if total == 1 then Metrics.step(player, "First job done")
	elseif total == 2 then Metrics.step(player, "Second job done")
	elseif total == 3 then Metrics.step(player, "Third job done") end
end

local SOURCE = Enum.AnalyticsEconomyFlowType.Source
local SINK = Enum.AnalyticsEconomyFlowType.Sink
local GAMEPLAY = Enum.AnalyticsEconomyTransactionType.Gameplay.Name
local SHOP = Enum.AnalyticsEconomyTransactionType.Shop.Name

-- reason: what EconomyService was told ("job:food_noodle", "mission", "fuel", "loan", ...)
function Metrics.money(player: Player, amount: number, reason: string, spent: boolean)
	if reason == "qa" or amount <= 0 then return end
	local d = Data.get(player)
	local balance = d and d.money or 0
	local sku = string.split(reason, ":")[1]
	pcall(function()
		AnalyticsService:LogEconomyEvent(player, spent and SINK or SOURCE, "Baht", amount, balance, spent and SHOP or GAMEPLAY, sku)
	end)
end

function Metrics.start()
	Data.onLoaded(function(player, d)
		local st = d.stats or {}
		local jobs = (st.deliveries or 0) + (st.rides or 0)
		if jobs == 0 and (d.level or 1) <= 1 then
			nextStep[player] = 1
			Metrics.step(player, "Joined")
		end
		local function character(char: Model)
			local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
			if not hum then return end
			hum.Seated:Connect(function(active, seat)
				if active and seat and seat:IsA("VehicleSeat") then Metrics.step(player, "Got on a vehicle") end
			end)
		end
		if player.Character then task.spawn(character, player.Character) end
		player.CharacterAdded:Connect(character)
	end)
	Players.PlayerRemoving:Connect(function(p) nextStep[p] = nil end)
end

return Metrics
