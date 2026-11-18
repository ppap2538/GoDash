-- Player profiles: load, session lock, autosave, release. All gameplay state lives on the server
-- in `profile.data`; the client only receives copies of the keys that changed.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Game = require(Shared.Config.Game)
local Vehicles = require(Shared.Config.Vehicles)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local Data = {}

local LOCK_SECONDS = 150 -- a lock older than this is considered dead (server crashed)
local AUTOSAVE = 90

local function template()
	local start = Vehicles.ById[Game.START_VEHICLE]
	return {
		version = 1,
		money = Game.START_MONEY, bank = 0, level = 1, exp = 0,
		energy = 100, hunger = 100, happiness = 80,
		injury = 0, -- 0-100 from falls and crashes; the hospital treats it (server/HealthService)
		rating = 5, ratingCount = 0,
		reviews = {}, -- the last 30 customer reviews, newest first: { t, s (stars), m (mode), who, tip, tags, seed } (client/Reviews)
		stats = { deliveries = 0, rides = 0, distance = 0, earned = 0, harvests = 0, planted = 0, fiveStars = 0, playSeconds = 0 },
		daily = { day = 0, income = 0, jobs = 0, safeBonus = 0, merit = 0, interest = 0 },
		vehicles = { [Game.START_VEHICLE] = Vehicles.newOwned(start) },
		activeVehicle = Game.START_VEHICLE,
		plot = false, -- or { tier, furniture = { {uid, id, x, z, rot} }, fridge = {}, nextUid }
		farm = { beds = {} },
		inventory = { water = 1 },
		buffs = {},
		missions = { day = 0, daily = {}, career = {} },
		dailyReward = { day = 0, streak = 0 },
		settings = { steer = 1, assist = true, music = true, sfx = true, bgm = true, lang = "th", rideAlong = "friends" }, -- music = city ambience, bgm = background songs; rideAlong = who may ride with you
		win = false, -- member of the motorbike-taxi stands (server/StreetService)
		licence = { bike = false, car = false }, -- driving licences (server/LicenseService)
		loans = {}, -- [vehicleId] = { left, each, due, missed } (server/FinanceService)
		credit = 650, -- credit score 300-850 (Config/Credit)
		bankLoan = false, -- or { principal, total, each, terms, left, timer, missed, fee, paidPart } (KK Bank personal loan)
		week = { id = 0, earned = 0, jobs = 0, five = 0 }, -- this week's totals for the Top Riders boards (server/LeaderboardService)
		-- Tier-A plan (2026-11-17): server/Services/StoreService, SeasonService, CompanyService
		receipts = {}, -- Robux purchase ids already granted (newest last, the last 100)
		passes = { vip = false, neon = false }, -- last known game-pass ownership (Roblox is asked on every join)
		codes = {}, -- [CODE] = os.time() when redeemed
		unlocks = {}, -- [key] = true: season cosmetics and titles (Config/Season.COSMETICS)
		title = "", -- chosen title key ("" = the rank)
		season = { id = 0, xp = 0, premium = false, free = {}, prem = {} },
		company = { riders = 0, level = 1, bank = 0, last = 0 },
		badges = {}, -- [badge key] = true once awarded
		seenNews = "", -- the "What's new" version this rider has seen
		pet = false, -- or { look, name (Config/Pets.NAMES index), out = true, since } (server/PetService, 2026-11-19)
		crew = false, crewAt = false, -- rider crew id (Config/Crews) and when it last changed (server/CrewService, 2026-11-19)
		siao = false, -- or { [UserId string] = display name }: เสี่ยว tied at the Silk Festival (server/SilkFestivalService)
		regulars = false, -- or { [id] = deliveries } (server/RegularsService, Config/Regulars, 2026-11-19)
		gear = false, -- or { owned = { [id] = true }, bag = id, helmet = id } (server/GearService, Config/Gear, 2026-11-19)
		onboard = false, -- or { gift, style, lake, clip = true }: the first-ten-minutes tips already done (client/Guide, 2026-11-19)
		insurance = false, -- or { plan = "c1" | "c2" | "c3", untilT = os.time() } (server/InsuranceService, 2026-11-19)
		lapWeek = false, -- or { id = week, cs }: this week's best lake lap (server/TimeTrialService); all-time best = stats.bestLap
		firstJoin = 0, lastSeen = 0,
	}
end
Data.template = template

local store = nil
local mock = false -- Studio without API access: keep profiles in memory so the game is still testable
local mockStore = {}
local profiles = {} -- [player] = { data, key, dirty = {key=true}, loaded }
local loadedHooks, releaseHooks = {}, {}

local function log(...)
	if Game.DEBUG then print("[Data]", ...) end
end

local function getStore()
	if store or mock then return store end
	-- Studio play tests use their own store, so testing never touches (or is locked out by) live profiles
	local name = Game.DATASTORE .. (RunService:IsStudio() and "_Studio" or "")
	local ok, res = pcall(function() return DataStoreService:GetDataStore(name) end)
	if ok then
		-- a cheap probe tells us if API access is really on
		local ok2, err = pcall(function() return res:GetAsync("__probe") end)
		if ok2 then store = res else
			mock = true
			warn("[Data] DataStore unavailable (" .. tostring(err) .. "). Using an in-memory store: progress will NOT persist in this session.")
		end
	else
		mock = true
		warn("[Data] DataStore unavailable. Using an in-memory store: progress will NOT persist in this session.")
	end
	return store
end

local function retry(fn, tries: number)
	local lastErr
	for i = 1, tries do
		local ok, res = pcall(fn)
		if ok then return true, res end
		lastErr = res
		task.wait(1.5 * i)
	end
	return false, lastErr
end

function Data.isMock(): boolean
	return mock
end

function Data.onLoaded(fn) table.insert(loadedHooks, fn) end
function Data.onRelease(fn) table.insert(releaseHooks, fn) end

function Data.get(player: Player)
	local p = profiles[player]
	return p and p.loaded and p.data or nil
end

-- Mark top-level keys as changed so the client gets them on the next flush.
function Data.touch(player: Player, ...: string)
	local p = profiles[player]
	if not p then return end
	for _, k in ipairs({ ... }) do p.dirty[k] = true end
end

local function load(player: Player)
	local key = "p_" .. player.UserId
	local ds = getStore()
	local data
	if mock then
		data = mockStore[key] and Util.deepCopy(mockStore[key]) or template()
	else
		local locked = false
		for attempt = 1, 5 do
			locked = false
			local ok, err = pcall(function()
				ds:UpdateAsync(key, function(old)
					local now = os.time()
					if old and old._lock and old._lock.job ~= game.JobId and now - (old._lock.t or 0) < LOCK_SECONDS then
						locked = true
						return nil -- someone else's live session: do not touch
					end
					local d = old or template()
					d._lock = { job = game.JobId, t = now }
					data = d
					return d
				end)
			end)
			if ok and not locked and data then break end
			if not ok then warn("[Data] load failed for " .. player.Name .. ": " .. tostring(err)) end
			data = nil
			task.wait(locked and 6 or 2 * attempt)
			if not player.Parent then return nil end
		end
		if not data then
			player:Kick(locked and "Your data is still saving in another server. Please rejoin in a minute." or "Could not load your data. Please rejoin.")
			return nil
		end
	end
	Util.reconcile(data, template())
	if data.firstJoin == 0 then data.firstJoin = os.time() end
	return { data = data, key = key, dirty = {}, loaded = true, lastSave = os.clock() }
end

local function save(player: Player, release: boolean?): boolean
	local p = profiles[player]
	if not p or not p.loaded then return false end
	p.data.lastSeen = os.time()
	if mock then
		mockStore[p.key] = Util.deepCopy(p.data)
		return true
	end
	local ok, err = retry(function()
		store:UpdateAsync(p.key, function(old)
			if old and old._lock and old._lock.job ~= game.JobId and os.time() - (old._lock.t or 0) < LOCK_SECONDS then
				return nil -- we lost the lock; never overwrite another session
			end
			local d = Util.deepCopy(p.data)
			d._lock = if release then nil else { job = game.JobId, t = os.time() }
			return d
		end)
	end, 3)
	if not ok then warn("[Data] save failed for " .. player.Name .. ": " .. tostring(err)) end
	p.lastSave = os.clock()
	return ok
end
Data.save = save

local function release(player: Player)
	local p = profiles[player]
	if not p then return end
	for _, fn in ipairs(releaseHooks) do
		local ok, err = pcall(fn, player, p.data)
		if not ok then warn("[Data] release hook: " .. tostring(err)) end
	end
	save(player, true)
	profiles[player] = nil
end

function Data.start()
	local function added(player: Player)
		if profiles[player] then return end
		profiles[player] = { loaded = false, dirty = {} }
		local p = load(player)
		if not p or not player.Parent then
			profiles[player] = nil
			return
		end
		profiles[player] = p
		local stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		local money = Instance.new("IntValue"); money.Name = "Money"; money.Value = p.data.money; money.Parent = stats
		local lvl = Instance.new("IntValue"); lvl.Name = "Level"; lvl.Value = p.data.level; lvl.Parent = stats
		stats.Parent = player
		for _, fn in ipairs(loadedHooks) do
			local ok, err = pcall(fn, player, p.data)
			if not ok then warn("[Data] loaded hook: " .. tostring(err)) end
		end
		player:SetAttribute("DataLoaded", true)
		Net.fire(player, "DataSync", p.data, true)
		log("loaded", player.Name)
	end
	Players.PlayerAdded:Connect(added)
	for _, pl in ipairs(Players:GetPlayers()) do task.spawn(added, pl) end
	Players.PlayerRemoving:Connect(release)

	-- the client asks again once its scripts are listening
	Net.on("ClientReady", {}, function(player)
		local p = profiles[player]
		if p and p.loaded then Net.fire(player, "DataSync", p.data, true) end
	end, 1)

	game:BindToClose(function()
		if RunService:IsStudio() and mock then return end
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			pending += 1
			task.spawn(function()
				release(player)
				pending -= 1
			end)
		end
		local t = os.clock()
		while pending > 0 and os.clock() - t < 25 do task.wait(0.2) end
	end)

	-- flush changed keys to clients, autosave on a stagger
	task.spawn(function()
		while true do
			task.wait(0.25)
			for player, p in pairs(profiles) do
				if p.loaded and next(p.dirty) then
					local delta = {}
					for k in pairs(p.dirty) do delta[k] = p.data[k] end
					p.dirty = {}
					local ls = player:FindFirstChild("leaderstats")
					if ls then
						ls.Money.Value = p.data.money
						ls.Level.Value = p.data.level
					end
					Net.fire(player, "DataSync", delta, false)
				end
				if p.loaded and os.clock() - p.lastSave > AUTOSAVE then
					p.lastSave = os.clock()
					task.spawn(save, player, false)
				end
			end
		end
	end)
end

return Data
