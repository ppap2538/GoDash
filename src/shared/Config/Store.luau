-- Robux store, codes, ranks, the season pass and the rider company (2026-11-17 Tier-A plan).
-- Game passes and developer products were created on Roblox with Open Cloud the same day; their ids
-- are below. Prices are Roblox's (change them on the Creator Dashboard; the code only uses the ids).
local Store = {}

---------------------------------------------------------------------------------------------------
-- Robux
---------------------------------------------------------------------------------------------------
Store.PASSES = {
	vip = { id = 2094188568, name = "VIP Rider", thai = "ไรเดอร์ VIP", icon = "⭐",
		desc = "Gold VIP tag, gold and rainbow underglow, gold plate frame, daily rewards +20%",
		descTh = "ป้าย VIP สีทอง ไฟใต้ท้องสีทองและรุ้ง กรอบป้ายทะเบียนทอง รางวัลรายวัน +20%" },
	neon = { id = 2094392559, name = "Neon Pro", thai = "ไฟนีออนโปร", icon = "🌈",
		desc = "Rainbow cycling and pulsing underglow on every vehicle",
		descTh = "ไฟใต้ท้องสายรุ้งไล่สีและกระพริบเป็นจังหวะ ใช้ได้ทุกคัน" },
}
Store.PRODUCTS = {
	[3732707923] = { kind = "cash", amount = 5000, name = "฿5,000", icon = "💰" },
	[3732708044] = { kind = "cash", amount = 20000, name = "฿20,000", icon = "💰" },
	[3732708061] = { kind = "cash", amount = 60000, name = "฿60,000", icon = "💰", best = true },
	[3732708078] = { kind = "season", name = "Premium Season Pass", thai = "Season Pass พรีเมียม", icon = "🎟" },
}
Store.CASH_ORDER = { 3732707923, 3732708044, 3732708061 }
Store.SEASON_PRODUCT = 3732708078
Store.VIP_DAILY = 1.2 -- daily reward multiplier for VIPs

-- Roblox group for the community bonus. 0 = no group yet (the owner creates one, puts its id here).
Store.GROUP_ID = 0
Store.GROUP_DAILY = 1.1

---------------------------------------------------------------------------------------------------
-- codes (case doesn't matter; each rider can use each once). ends = last day, yyyy-mm-dd (Thai time).
---------------------------------------------------------------------------------------------------
Store.CODES = {
	SAWASDEE = { money = 1000, ends = "2027-12-31" },
	GODASH = { money = 2500, ends = "2027-12-31" },
	KHONKAEN = { money = 1500, item = "milk_tea", qty = 3, ends = "2027-12-31" },
	RIDER2026 = { money = 3000, seasonXp = 150, ends = "2026-12-31" },
	-- one code per TikTok clip (2026-11-19), so the Creator Dashboard shows which clip brought riders in
	-- (StoreService logs a custom event "Code <NAME>" on every use)
	LOY2569 = { money = 2000, seasonXp = 100, ends = "2026-12-07" }, -- the Loy Krathong teaser
	PHEE = { money = 1313, ends = "2026-12-31" }, -- the ghost + Haunted Night Radio 13.13 clip
	TIKTOK = { money = 1500, item = "milk_tea", qty = 2, ends = "2027-06-30" }, -- the profile bio / every clip
}

---------------------------------------------------------------------------------------------------
-- rider ranks: by jobs done (deliveries + rides). tip = extra tip share.
---------------------------------------------------------------------------------------------------
Store.RANKS = {
	{ jobs = 0, name = "Rookie", thai = "มือใหม่", color = Color3.fromRGB(200, 204, 210), tip = 0 },
	{ jobs = 10, name = "Trainee Rider", thai = "ไรเดอร์ฝึกหัด", color = Color3.fromRGB(140, 220, 160), tip = 0.02 },
	{ jobs = 30, name = "Rider", thai = "ไรเดอร์", color = Color3.fromRGB(60, 200, 110), tip = 0.04 },
	{ jobs = 75, name = "Pro Rider", thai = "ไรเดอร์มือโปร", color = Color3.fromRGB(70, 160, 255), tip = 0.06 },
	{ jobs = 150, name = "Gold Rider", thai = "ไรเดอร์ระดับทอง", color = Color3.fromRGB(255, 200, 60), tip = 0.08 },
	{ jobs = 300, name = "Diamond Rider", thai = "ไรเดอร์เพชร", color = Color3.fromRGB(120, 230, 255), tip = 0.1 },
	{ jobs = 600, name = "Legend of Khon Kaen", thai = "ตำนานแห่งขอนแก่น", color = Color3.fromRGB(255, 110, 200), tip = 0.12 },
}
function Store.rankFor(jobs: number): (number, any)
	local idx = 1
	for i, r in ipairs(Store.RANKS) do
		if jobs >= r.jobs then idx = i end
	end
	return idx, Store.RANKS[idx]
end

---------------------------------------------------------------------------------------------------
-- rider company: hire riders who deliver for you (income while you play; a capped share while away)
---------------------------------------------------------------------------------------------------
Store.COMPANY = {
	unlockRank = 3, -- "Rider" (30 jobs)
	maxRiders = function(rank: number) return math.max(0, rank - 1) * 2 end, -- 4 at rank 3 ... 12 at rank 7
	hireCost = function(n: number) return math.floor(3000 * 1.45 ^ n / 100 + 0.5) * 100 end, -- n = riders already hired
	perMinute = 4, -- baht per rider per minute at level 1
	levelBonus = 0.25, -- +25 % per bike level
	maxLevel = 5,
	levelCost = function(level: number) return 8000 * level * level end, -- to reach level+1
	offlineShare = 0.5,
	offlineHours = 3,
	bankCap = function(riders: number, level: number) return math.max(2000, riders * 4 * 60 * 6 * (1 + 0.25 * (level - 1))) end,
}

return Store
