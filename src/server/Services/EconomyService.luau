-- The only place money and EXP change. Every transaction is server-side and logged by reason.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Game = require(Shared.Config.Game)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)

local Economy = {}
local levelHooks = {}

local function rollDay(d)
	local day = Util.dayNumber()
	if d.daily.day ~= day then
		d.daily = { day = day, income = 0, jobs = 0, safeBonus = 0, merit = 0, interest = 0 }
	end
end
Economy.rollDay = rollDay

function Economy.onLevelUp(fn) table.insert(levelHooks, fn) end

-- income = true counts toward daily income and lifetime earnings (jobs, farming)
function Economy.add(player: Player, amount: number, reason: string, income: boolean?): boolean
	local d = Data.get(player)
	if not d or not Util.isFinite(amount) or amount <= 0 then return false end
	amount = math.floor(amount + 0.5)
	d.money += amount
	if income then
		rollDay(d)
		d.daily.income += amount
		d.stats.earned += amount
		Data.touch(player, "daily", "stats")
	end
	Data.touch(player, "money")
	if Game.DEBUG then print(("[Eco] +%d %s (%s)"):format(amount, player.Name, reason)) end
	return true
end

function Economy.canAfford(player: Player, amount: number): boolean
	local d = Data.get(player)
	return d ~= nil and Util.isFinite(amount) and amount >= 0 and d.money >= amount
end

function Economy.spend(player: Player, amount: number, reason: string): boolean
	local d = Data.get(player)
	if not d or not Util.isFinite(amount) or amount < 0 then return false end
	amount = math.floor(amount + 0.5)
	if d.money < amount then return false end
	d.money -= amount
	Data.touch(player, "money")
	if Game.DEBUG then print(("[Eco] -%d %s (%s)"):format(amount, player.Name, reason)) end
	return true
end

function Economy.addExp(player: Player, amount: number)
	local d = Data.get(player)
	if not d or not Util.isFinite(amount) or amount <= 0 then return end
	d.exp += math.floor(amount + 0.5)
	local leveled = false
	while d.level < Game.MAX_LEVEL and d.exp >= Game.expForLevel(d.level) do
		d.exp -= Game.expForLevel(d.level)
		d.level += 1
		leveled = true
		local bonus = 100 + d.level * 50
		d.money += bonus
		Net.fire(player, "Notify", "levelup", { level = d.level, bonus = bonus })
		for _, fn in ipairs(levelHooks) do task.spawn(fn, player, d.level) end
	end
	Data.touch(player, "exp", "level")
	if leveled then Data.touch(player, "money") end
end

-- Bank: deposit / withdraw, and 1% daily interest paid on the first login of each day.
local function bank(player: Player, op: string, amount: number)
	local d = Data.get(player)
	if not d then return false, "Not ready" end
	amount = math.floor(amount)
	if amount <= 0 or amount > 1e9 then return false, "Enter an amount" end
	if op == "deposit" then
		if d.money < amount then return false, "Not enough cash" end
		d.money -= amount; d.bank += amount
	elseif op == "withdraw" then
		if d.bank < amount then return false, "Not enough in the bank" end
		d.bank -= amount; d.money += amount
	else
		return false, "Bad request"
	end
	Data.touch(player, "money", "bank")
	return true, op == "deposit" and "Deposited " .. Util.money(amount) or "Withdrew " .. Util.money(amount)
end

function Economy.start()
	Net.fn("Bank", { "string", "number" }, bank, 4)
	Data.onLoaded(function(player, d)
		rollDay(d)
		if d.daily.interest == 0 and d.bank > 0 then
			local pay = math.min(Game.BANK_INTEREST_CAP, math.floor(d.bank * Game.BANK_INTEREST))
			d.daily.interest = 1
			if pay > 0 then
				d.bank += pay
				task.delay(6, function() Net.fire(player, "Notify", "toast", { text = "🏦 Bank interest +" .. Util.money(pay), good = true }) end)
			end
		end
	end)
end

return Economy
