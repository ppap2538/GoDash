--!strict
-- Global tuning. Balance lives here so the economy can be changed without touching systems.
local Game = {}

Game.DEBUG = false -- extra server logs
Game.DATASTORE = "GoDash_Profiles_v1"
Game.MAP = "KhonKaen" -- which province map to load (Config/Maps/<name>)
-- When the place has no baked Workspace.Map, the server builds the city at start-up.
-- nil = build everything (slow, ~1:1 city); a number = only scenery within that many studs of the
-- centre, for quick development boots. A baked place ignores this.
Game.DEV_RADIUS = 2000
-- Live servers: how much of the city to build around the centre. Measured: 2000 studs = ~63k parts in ~8 s.
-- nil = the whole 1:1 city (not measured since the detailed facades went in; raise this step by step).
Game.LIVE_RADIUS = 2600

Game.START_MONEY = 500
Game.START_VEHICLE = "bicycle"
Game.MAX_LEVEL = 60

function Game.expForLevel(level: number): number
	return math.floor(60 * level ^ 1.55 + 60)
end

-- Level gates (shown in the phone so players have goals)
Game.UNLOCKS = {
	express = 2,
	ride = 3,
	rainy = 1,
	large = 5,
	special = 6,
	vip = 8,
}

-- Lifestyle (per second unless stated)
-- (2026-11-15: slowed down about 3x; at 14-16 minutes a new rider spent more time eating and
-- resting than riding, which made the game feel hard)
Game.HUNGER_DECAY = 100 / (45 * 60) -- empty in about 45 minutes
Game.ENERGY_DRIVE_DECAY = 100 / (40 * 60) -- while driving
Game.ENERGY_IDLE_DECAY = 100 / (120 * 60)
Game.HAPPY_DECAY = 100 / (90 * 60)
Game.ENERGY_PER_JOB = 1.5
Game.STARVING_ENERGY_DECAY = 100 / (15 * 60)
Game.TIRED_PAY_MULT = 0.8 -- energy below 10
Game.REST_BENCH_RATE = 1.2 -- energy per second on a public bench
Game.BED_RATE = 6 -- energy per second in your own bed

-- World clock: one in-game day
Game.DAY_LENGTH = 16 * 60 -- real seconds per in-game day
Game.START_CLOCK = 7.5

-- Fuel
Game.FUEL_PRICE = 12 -- per litre
Game.REPAIR_PRICE = 6 -- per condition point

-- Bank
Game.BANK_INTEREST = 0.01 -- per day, paid on first login of the day
Game.BANK_INTEREST_CAP = 2500

-- Jobs
Game.OFFER_SECONDS = 22
Game.INTERACT_RANGE = 26
Game.KMH = 1.0 -- studs/s -> km/h shown on the speedometer

-- Daily reward track (7-day streak)
Game.DAILY_REWARDS = {
	{ money = 300 },
	{ money = 450, item = "milk_tea", qty = 2 },
	{ money = 600 },
	{ money = 800, item = "fertilizer", qty = 3 },
	{ money = 1000 },
	{ money = 1300, item = "seed_watermelon", qty = 4 },
	{ money = 2500, exp = 300 },
}

return Game
