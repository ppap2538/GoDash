-- Career missions, three daily missions and the 7-day login reward. Progress comes from
-- gameplay events raised by other services; rewards are paid here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Game = require(Shared.Config.Game)
local Missions = require(Shared.Config.Missions)
local Items = require(Shared.Config.Items)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Inventory = require(script.Parent.InventoryService)
local StoreCfg = require(Shared.Config.Store)
local SeasonCfg = require(Shared.Config.Season)
local SeasonSvc = require(script.Parent.SeasonService)

local Service = {}

local function rollDaily(player: Player, d)
	local day = Util.dayNumber()
	if d.missions.day == day and #d.missions.daily > 0 then return end
	local pool = {}
	for _, m in ipairs(Missions.DAILY) do
		if not m.level or d.level >= m.level then table.insert(pool, m) end
	end
	local rng = Random.new(day * 31 + player.UserId % 9973)
	local picked = {}
	while #picked < Missions.DAILY_COUNT and #pool > 0 do
		local m = table.remove(pool, rng:NextInteger(1, #pool))
		local dup = false
		for _, p in ipairs(picked) do
			if Missions.ById[p.id].event == m.event then dup = true end
		end
		if not dup then table.insert(picked, { id = m.id, progress = 0, claimed = false }) end
	end
	d.missions.day = day
	d.missions.daily = picked
	Data.touch(player, "missions")
end

function Service.progress(player: Player, event: string, amount: number)
	local d = Data.get(player)
	if not d or amount <= 0 then return end
	rollDaily(player, d)
	local changed = false
	for _, def in ipairs(Missions.CAREER) do
		if def.event == event then
			local st = d.missions.career[def.id]
			if not st then st = { progress = 0, claimed = false }; d.missions.career[def.id] = st end
			if st.progress < def.goal then
				st.progress = math.min(def.goal, st.progress + amount)
				changed = true
				if st.progress >= def.goal then
					Net.fire(player, "Notify", "toast", { text = "🎯 Mission complete: " .. def.name .. " — claim it in Missions", good = true })
				end
			end
		end
	end
	for _, st in ipairs(d.missions.daily) do
		local def = Missions.ById[st.id]
		if def and def.event == event and st.progress < def.goal then
			st.progress = math.min(def.goal, st.progress + amount)
			changed = true
			if st.progress >= def.goal then
				Net.fire(player, "Notify", "toast", { text = "📅 Daily done: " .. def.name .. " — claim it in Missions", good = true })
			end
		end
	end
	if changed then Data.touch(player, "missions") end
end

local function pay(player: Player, def, title: string)
	if def.money then Economy.add(player, def.money, "mission") end
	if def.exp then Economy.addExp(player, def.exp) end
	if def.item then Inventory.add(player, def.item, def.qty or 1) end
	Net.fire(player, "Reward", { title = title, money = def.money, exp = def.exp, item = def.item and Items.ById[def.item].name, qty = def.qty })
end

function Service.start()
	Data.onLoaded(function(player, d) rollDaily(player, d) end)

	Net.fn("Mission", { "string", "string?" }, function(player, op, id)
		local d = Data.get(player)
		if not d then return false, "Not ready" end
		rollDaily(player, d)
		if op == "claim" then
			local def = id and Missions.ById[id]
			if not def then return false, "Unknown mission" end
			local st = d.missions.career[id]
			if not st then
				for _, s in ipairs(d.missions.daily) do
					if s.id == id then st = s end
				end
			end
			if not st then return false, "Mission not active" end
			if st.claimed then return false, "Already claimed" end
			if st.progress < def.goal then return false, "Not finished yet" end
			st.claimed = true -- flag first: a second request can never pay twice
			Data.touch(player, "missions")
			pay(player, def, def.name)
			SeasonSvc.addXp(player, SeasonCfg.XP.mission)
			return true, "Reward claimed"
		elseif op == "daily" then
			local day = Util.dayNumber()
			local dr = d.dailyReward
			if dr.day == day then return false, "Come back tomorrow" end
			dr.streak = (dr.day == day - 1) and (dr.streak % #Game.DAILY_REWARDS) + 1 or 1
			dr.day = day
			Data.touch(player, "dailyReward")
			-- VIP pass +20 %, members of the GoDash group +10 % (Config/Store)
			local rw = table.clone(Game.DAILY_REWARDS[dr.streak])
			local mult = 1
			if player:GetAttribute("VIP") then mult *= StoreCfg.VIP_DAILY end
			if player:GetAttribute("InGroup") then mult *= StoreCfg.GROUP_DAILY end
			if rw.money then rw.money = math.floor(rw.money * mult + 0.5) end
			pay(player, rw, "Daily Reward · Day " .. dr.streak)
			SeasonSvc.addXp(player, SeasonCfg.XP.daily)
			return true, "Daily reward claimed"
		end
		return false, "Bad request"
	end, 4)
end

return Service
