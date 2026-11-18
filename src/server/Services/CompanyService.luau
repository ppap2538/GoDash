-- Your own rider company (2026-11-17 Tier-A plan): from the "Rider" rank you can hire riders who
-- deliver for you. They earn into the company's account every minute you play and a smaller,
-- capped share while you are away; you collect it in the phone's Company app. Better bikes
-- (company level) make every rider earn more. Numbers: Config/Store.COMPANY.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage.Shared
local Store = require(Shared.Config.Store)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local City = require(script.Parent.CityRemote)

local Service = {}
local C = Store.COMPANY

local function company(d)
	if type(d.company) ~= "table" then d.company = { riders = 0, level = 1, bank = 0, last = 0 } end
	return d.company
end

local function rankOf(d): number
	local jobs = (d.stats.deliveries or 0) + (d.stats.rides or 0)
	return (Store.rankFor(jobs))
end

local function rate(c): number -- baht per minute
	return c.riders * C.perMinute * (1 + C.levelBonus * (c.level - 1))
end

function Service.start()
	Data.onLoaded(function(player, d)
		local c = company(d)
		local now = os.time()
		if c.last > 0 and c.riders > 0 then
			local minutes = math.min(now - c.last, C.offlineHours * 3600) / 60
			local earned = math.floor(rate(c) * minutes * C.offlineShare)
			if earned > 0 then
				c.bank = math.min(c.bank + earned, C.bankCap(c.riders, c.level))
				task.delay(8, function()
					Net.fire(player, "Notify", "toast", { text = ("🏢 Your riders earned %s while you were away: collect it in the Company app"):format(Util.money(earned)),
						th = ("🏢 ไรเดอร์ในบริษัททำเงินได้ %s ระหว่างที่คุณไม่อยู่ ไปเก็บในแอปบริษัท"):format(Util.money(earned)), good = true })
				end)
			end
		end
		c.last = now
		Data.touch(player, "company")
	end)
	-- every minute of play
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				local d = Data.get(player)
				if d then
					local c = company(d)
					if c.riders > 0 then
						c.bank = math.min(c.bank + math.floor(rate(c)), C.bankCap(c.riders, c.level))
					end
					c.last = os.time()
					Data.touch(player, "company")
				end
			end
		end
	end)
	City.register("company_hire", function(player)
		local d = Data.get(player)
		if not d then return false, "Not ready" end
		local c = company(d)
		local rank = rankOf(d)
		if rank < C.unlockRank then return false, "Reach the Rider rank first (30 jobs)" end
		if c.riders >= C.maxRiders(rank) then return false, "Rank up to hire more riders" end
		local cost = C.hireCost(c.riders)
		if not Economy.spend(player, cost, "company:hire") then return false, "Not enough money (" .. Util.money(cost) .. ")" end
		c.riders += 1
		Data.touch(player, "company")
		return true, "Hired a rider"
	end)
	City.register("company_upgrade", function(player)
		local d = Data.get(player)
		if not d then return false, "Not ready" end
		local c = company(d)
		if c.riders == 0 then return false, "Hire a rider first" end
		if c.level >= C.maxLevel then return false, "Already at the top level" end
		local cost = C.levelCost(c.level)
		if not Economy.spend(player, cost, "company:upgrade") then return false, "Not enough money (" .. Util.money(cost) .. ")" end
		c.level += 1
		Data.touch(player, "company")
		return true, "Better bikes for everyone"
	end)
	City.register("company_collect", function(player)
		local d = Data.get(player)
		if not d then return false, "Not ready" end
		local c = company(d)
		local amount = math.floor(c.bank)
		if amount <= 0 then return false, "Nothing to collect yet" end
		c.bank = 0
		Data.touch(player, "company")
		Economy.add(player, amount, "company", true)
		return true, "Collected " .. Util.money(amount)
	end)
end

return Service
