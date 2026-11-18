--!strict
-- Global tuning. Balance lives here so the economy can be changed without touching systems.
local Game = {}

Game.DEBUG = false -- extra server logs
Game.DATASTORE = "GoDash_Profiles_v1"
Game.MAP = "KhonKaen" -- which province map to load (Config/Maps/<name>)
-- The server plans the whole city at start-up and draws buildings only around the players
-- (World/Streamer), so there is no build radius any more (DEV_RADIUS / LIVE_RADIUS are gone).
-- AI route traffic, soi dogs, checkpoints and roadworks live within this distance of the centre: since
-- 2026-11-18 the whole tambon (was 2600 studs, ~730 m, round the old downtown box).
Game.TRAFFIC_RADIUS = math.huge

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
-- Below these, new orders pause and the Guide card leads the player to food / a coffee (2026-11-16:
-- orders kept popping up while the hunger toast repeated every 30 s and nothing showed where to eat).
-- The warning toast fires once on the way down and re-arms after NEED_REARM points of recovery.
Game.HUNGRY_AT = 15
Game.TIRED_AT = 12
Game.NEED_REARM = 10

-- Lakes and ponds (2026-11-19): Roblox terrain water (waves, sky reflections) whose surface is at WATER_Y.
-- The "Water" parts under it are the dark lake bed (top 0.05) and keep the collisions and raycasts.
Game.WATER_Y = 1.2

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
