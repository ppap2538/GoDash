-- Season pass (2026-11-17 Tier-A plan): 30-day seasons, 50 tiers of 100 XP, a free and a premium
-- track (Config/Season). XP comes from jobs, five-star ratings, the daily reward, missions and Rush
-- Hour. A new season resets XP and claims; cosmetics already unlocked stay (d.unlocks).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Season = require(Shared.Config.Season)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Inventory = require(script.Parent.InventoryService)
local City = require(script.Parent.CityRemote)
local StoreService = require(script.Parent.StoreService)

local Service = {}

local function state(d)
	local id = Season.current()
	if type(d.season) ~= "table" or d.season.id ~= id then
		d.season = { id = id, xp = 0, premium = false, free = {}, prem = {} }
	end
	return d.season
end
Service.state = state

function Service.addXp(player: Player, amount: number)
	local d = Data.get(player)
	if not d or amount <= 0 then return end
	local s = state(d)
	local before = math.floor(s.xp / Season.XP_PER_TIER)
	s.xp = math.min(s.xp + math.floor(amount), Season.TIERS * Season.XP_PER_TIER)
	local after = math.floor(s.xp / Season.XP_PER_TIER)
	Data.touch(player, "season")
	if after > before then
		Net.fire(player, "Notify", "toast", { text = ("🎟 Season tier %d! Claim it in the Season app"):format(after), th = ("🎟 ซีซันขึ้นขั้น %d แล้ว! ไปรับรางวัลในแอปซีซัน"):format(after), good = true })
	end
end

local function give(player: Player, d, r, title: string)
	if not r then return end
	if r.money then Economy.add(player, r.money, "season") end
	if r.exp then Economy.addExp(player, r.exp) end
	if r.item and Items.ById[r.item] then Inventory.add(player, r.item, r.qty or 1) end
	if r.unlock then
		d.unlocks = type(d.unlocks) == "table" and d.unlocks or {}
		d.unlocks[r.unlock] = true
		Data.touch(player, "unlocks")
	end
	local c = r.unlock and Season.COSMETICS[r.unlock]
	Net.fire(player, "Reward", { title = title, money = r.money, exp = r.exp, item = (r.item and Items.ById[r.item] and Items.ById[r.item].name) or (c and (c.thai or c.text or c.name)), qty = r.qty })
end

function Service.start()
	-- purchases and codes call back here
	StoreService.onSeason(function(player, kind, value)
		local d = Data.get(player)
		if not d then return end
		if kind == "premium" then
			state(d).premium = true
			Data.touch(player, "season")
		elseif kind == "xp" then
			Service.addXp(player, value or 0)
		end
	end)
	City.register("season_claim", function(player, arg)
		local d = Data.get(player)
		if not d or type(arg) ~= "string" then return false, "Bad request" end
		local track, tierS = arg:match("^(%a+):(%d+)$")
		local tier = tonumber(tierS)
		if not tier or tier < 1 or tier > Season.TIERS or (track ~= "free" and track ~= "prem") then return false, "Bad request" end
		local s = state(d)
		if math.floor(s.xp / Season.XP_PER_TIER) < tier then return false, "Not reached yet" end
		local premium = track == "prem"
		if premium and not s.premium then return false, "Needs the Premium Season Pass" end
		local claimed = premium and s.prem or s.free
		local key = tostring(tier)
		if claimed[key] then return false, "Already claimed" end
		local r = Season.reward(tier, premium)
		if not r then return false, "Nothing on this tier" end
		claimed[key] = true -- flag first: a second request can never pay twice
		Data.touch(player, "season")
		give(player, d, r, ("Season %d · tier %d"):format(s.id, tier))
		return true, "Claimed"
	end)
	Data.onLoaded(function(player, d)
		state(d)
		Data.touch(player, "season")
	end)
end

return Service
