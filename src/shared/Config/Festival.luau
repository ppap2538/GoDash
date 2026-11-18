-- Festivals (2026-11-18, owner: "ทำทั้งหมดที่เสนอมาได้เลย" — the Loy Krathong plan for TikTok clips).
-- Loy Krathong 2026 falls on Tuesday 24 November; Bueng Kaen Nakhon holds Khon Kaen's big one in real life.
-- Culture only: krathongs, lights and fireworks; no monks, no rites, no religious images.
local Festival = {}

-- days since 1970-01-01 for a calendar date (same counting as Util.dayNumber, which is Thai time)
local function dayOf(y: number, m: number, d: number): number
	y -= m <= 2 and 1 or 0
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end
Festival.dayOf = dayOf

Festival.LOY = {
	id = "loykrathong",
	lake = "Bueng Kaen Nakhon",
	from = dayOf(2026, 11, 20),
	to = dayOf(2026, 11, 30),
	peak = dayOf(2026, 11, 24),
	price = 20, -- baht for a krathong (the first one each day is free)
	lifetime = 240, -- seconds a krathong floats before it drifts out of sight
	maxOnWater = 40,
	xp = 15, -- season XP for the first krathong of the day
	happy = 12,
	-- preset wishes only (no typed text: the game must suit all ages)
	wishes = {
		{ en = "Lots of money 💰", th = "ขอให้รวย ๆ 💰" },
		{ en = "Pass my exams 📚", th = "ขอให้สอบผ่าน 📚" },
		{ en = "No more fines 🚦", th = "ขอให้ส่งของไม่โดนปรับ 🚦" },
		{ en = "A happy family 🏡", th = "ขอให้ครอบครัวมีความสุข 🏡" },
		{ en = "Meet my match 💛", th = "ขอให้เจอคนที่ใช่ 💛" },
		{ en = "Five stars every job ⭐", th = "ขอให้ได้ห้าดาวทุกงาน ⭐" },
	},
	-- krathong styles: base, leaf, flowers
	styles = {
		{ en = "Banana leaf", th = "ใบตอง", leaf = Color3.fromRGB(70, 150, 60), flower = Color3.fromRGB(250, 170, 40) },
		{ en = "Flower", th = "ดอกไม้", leaf = Color3.fromRGB(60, 130, 70), flower = Color3.fromRGB(240, 110, 160) },
		{ en = "Bread (feeds the fish)", th = "ขนมปัง (ให้ปลากิน)", leaf = Color3.fromRGB(214, 168, 100), flower = Color3.fromRGB(255, 240, 200) },
	},
	-- fireworks over the lake at night: a show every SHOW_EVERY seconds lasting SHOW_LENGTH (server clock)
	SHOW_EVERY = 150,
	SHOW_LENGTH = 30,
}

return Festival
