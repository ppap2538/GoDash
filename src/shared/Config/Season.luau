-- Season pass (2026-11-17 Tier-A plan). Seasons are 30 days, the first one starting 2026-11-17 00:00
-- Thai time; every season has 50 tiers of 100 season XP. Everyone has the free track; the premium
-- track is the "Premium Season Pass" developer product (Config/Store.SEASON_PRODUCT) for that season.
-- Rewards: money, EXP, items, and cosmetics that only the season gives (glow colours, stickers,
-- titles), kept forever in d.unlocks.
local Season = {}

Season.START = 1794848400 -- 2026-11-17 00:00 Thai time (UTC+7) = 2026-11-16 17:00 UTC
Season.LENGTH = 30 * 86400
Season.TIERS = 50
Season.XP_PER_TIER = 100
Season.XP = { job = 20, fiveStar = 10, daily = 25, mission = 30, rush = 15 }

function Season.current(t: number?): number
	return math.max(1, math.floor(((t or os.time()) - Season.START) / Season.LENGTH) + 1)
end
function Season.endsAt(id: number): number
	return Season.START + id * Season.LENGTH
end

-- Exclusive cosmetics. Glow / sticker entries are appended to Config/Vehicles' lists at load
-- (index = position there), and need d.unlocks[key] to be fitted.
Season.COSMETICS = {
	glow_sunset = { kind = "glow", name = "Sunset", thai = "สีพระอาทิตย์ตก", color = Color3.fromRGB(255, 120, 80) },
	glow_mint = { kind = "glow", name = "Mint", thai = "สีมิ้นต์", color = Color3.fromRGB(120, 255, 210) },
	sticker_s1 = { kind = "sticker", icon = "🏆", text = "ซีซัน 1", color = Color3.fromRGB(150, 70, 230) },
	sticker_legend = { kind = "sticker", icon = "👑", text = "ตำนานไรเดอร์", color = Color3.fromRGB(200, 150, 20) },
	title_s1 = { kind = "title", name = "Season 1 Rider", thai = "ไรเดอร์ซีซัน 1" },
	title_s1_pro = { kind = "title", name = "Season 1 Pro", thai = "โปรซีซัน 1" },
}

-- reward for tier n on each track
function Season.reward(tier: number, premium: boolean)
	if premium then
		if tier == 10 then return { unlock = "glow_sunset" } end
		if tier == 20 then return { unlock = "sticker_s1" } end
		if tier == 30 then return { unlock = "glow_mint" } end
		if tier == 40 then return { unlock = "sticker_legend" } end
		if tier == 50 then return { unlock = "title_s1_pro", money = 20000 } end
		if tier % 5 == 0 then return { money = 2500, exp = 200 } end
		return { money = 600 + tier * 20 }
	end
	if tier == 25 then return { unlock = "title_s1" } end
	if tier == 50 then return { money = 8000, exp = 500 } end
	if tier % 5 == 0 then return { money = 1000, item = "milk_tea", qty = 2 } end
	if tier % 2 == 0 then return { money = 250 + tier * 10 } end
	return nil -- odd free tiers are empty: the premium track carries more
end

return Season
