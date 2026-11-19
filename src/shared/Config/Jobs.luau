-- GoDash job types. Pay = base + perStud * route length, then weather / rating / vehicle bonuses.
local Jobs = {}

Jobs.FOOD = {
	nearby = { id = "nearby", name = "Neighbourhood Delivery", icon = "🚲", color = Color3.fromRGB(60, 170, 150), level = 1, weight = 40, maxLevel = 5,
		base = 30, perStud = 0.03, minDist = 500, maxDist = 1700, par = 2.0, exp = 26, cargo = 1, tipMax = 0.3 },
	normal = { id = "normal", name = "Normal Delivery", icon = "🛵", color = Color3.fromRGB(28, 168, 84), level = 1, weight = 50,
		base = 28, perStud = 0.016, minDist = 1500, maxDist = 6000, par = 1.0, exp = 22, cargo = 1, tipMax = 0.25 },
	express = { id = "express", name = "Express Delivery", icon = "⚡", color = Color3.fromRGB(240, 150, 30), level = 2, weight = 22,
		base = 40, perStud = 0.024, minDist = 1500, maxDist = 6000, par = 0.72, exp = 34, cargo = 1, tipMax = 0.35, strict = true },
	large = { id = "large", name = "Large Order", icon = "📦", color = Color3.fromRGB(90, 120, 220), level = 5, weight = 14,
		base = 70, perStud = 0.026, minDist = 2000, maxDist = 7000, par = 1.15, exp = 46, cargo = 5, tipMax = 0.3 },
	special = { id = "special", name = "Special Food Delivery", icon = "🍲", color = Color3.fromRGB(200, 70, 150), level = 6, weight = 12,
		base = 65, perStud = 0.028, minDist = 2000, maxDist = 8000, par = 1.0, exp = 52, cargo = 2, tipMax = 0.4, fragile = true },
	vip = { id = "vip", name = "VIP Delivery", icon = "👑", color = Color3.fromRGB(212, 170, 50), level = 8, weight = 9,
		base = 120, perStud = 0.034, minDist = 3000, maxDist = 9000, par = 0.9, exp = 80, cargo = 2, tipMax = 0.6, strict = true },
	rainy = { id = "rainy", name = "Rainy Day Delivery", icon = "🌧", color = Color3.fromRGB(70, 150, 210), level = 1, weight = 45,
		base = 45, perStud = 0.024, minDist = 1500, maxDist = 5500, par = 1.25, exp = 36, cargo = 1, tipMax = 0.45, rainOnly = true },
	-- (2026-11-19, viral pack) absurd loads strapped onto whatever you ride: a fridge, a mattress, a pile of durians...
	-- (Jobs.BIGLOADS). It wobbles, slides when you brake hard and falls off in a crash (client/Cargo); pays well
	bigload = { id = "bigload", name = "Big Load by Bike", icon = "📦", color = Color3.fromRGB(230, 120, 40), level = 2, weight = 9,
		base = 90, perStud = 0.03, minDist = 900, maxDist = 4500, par = 1.3, exp = 55, cargo = 1, tipMax = 0.55, fragile = true, absurd = true },
	-- jobs at the real landmarks (server/CivicJobs, 2026-11-18): only at the hours they make sense
	docs = { id = "docs", name = "Urgent Documents", icon = "📄", color = Color3.fromRGB(70, 90, 160), level = 3, weight = 11,
		base = 60, perStud = 0.026, maxDist = 7000, par = 0.85, exp = 44, cargo = 1, tipMax = 0.3, strict = true,
		hours = { { 8.5, 16.5 } },
		civic = { from = { pois = { "government" } }, to = { pois = { "government", "police" } }, item = "Urgent documents",
			who = { "Officer Somsak", "Officer Wanpen", "Officer Prasit" } } },
	hospitalmeals = { id = "hospitalmeals", name = "Hospital Lunch Boxes", icon = "🍱", color = Color3.fromRGB(60, 160, 170), level = 4, weight = 11,
		base = 70, perStud = 0.026, maxDist = 7000, par = 1.05, exp = 48, cargo = 2, tipMax = 0.35, fragile = true,
		hours = { { 10.5, 13.5 }, { 17, 19 } },
		civic = { from = { kitchens = { "restaurant", "market" } }, to = { pois = { "hospital" } }, item = "Lunch boxes for the ward staff",
			who = { "Nurse Ploy", "Nurse Kik", "Dr. Anan" } } },
	schoollunch = { id = "schoollunch", name = "School Lunch Run", icon = "🏫", color = Color3.fromRGB(230, 130, 60), level = 2, weight = 9,
		base = 50, perStud = 0.024, maxDist = 6000, par = 0.95, exp = 38, cargo = 2, tipMax = 0.3,
		hours = { { 10, 11.9 } },
		civic = { from = { kitchens = { "restaurant", "market" } }, to = { pois = { "school" } }, item = "Teachers' lunch order",
			who = { "Teacher Noi", "Teacher Pong", "Teacher Jiap" } } },
	matchday = { id = "matchday", name = "Match Day Snacks", icon = "🏟", color = Color3.fromRGB(200, 60, 60), level = 3, weight = 8,
		base = 55, perStud = 0.026, maxDist = 7000, par = 0.9, exp = 40, cargo = 2, tipMax = 0.4,
		hours = { { 16, 19.5 } },
		civic = { from = { kitchens = { "convenience" } }, to = { pois = { "stadium" } }, item = "Ice and drinks for the stands",
			who = { "Coach Bird", "Fan club Kaen", "Khun Tee" } } },
	studysnacks = { id = "studysnacks", name = "Late-night Study Snacks", icon = "📚", color = Color3.fromRGB(110, 80, 180), level = 1, weight = 10,
		base = 40, perStud = 0.024, maxDist = 6000, par = 1.0, exp = 34, cargo = 1, tipMax = 0.35,
		hours = { { 19.5, 1.5 } },
		civic = { from = { kitchens = { "convenience", "cafe", "nightmarket" } }, to = { zone = "university", name = "Dormitory" }, item = "Snacks for exam night",
			who = { "Nong Mook", "Nong Pete", "Nong Fern" } } },
}

Jobs.RIDE = {
	ride = { id = "ride", name = "GoDash Ride", icon = "🧍", color = Color3.fromRGB(28, 168, 84), level = 3, weight = 50,
		base = 35, perStud = 0.02, minDist = 2000, maxDist = 7000, par = 1.05, exp = 30, seats = 1, tipMax = 0.3 },
	student = { id = "student", name = "Rush Hour Ride", icon = "⏱", color = Color3.fromRGB(240, 150, 30), level = 4, weight = 25,
		base = 40, perStud = 0.024, minDist = 1500, maxDist = 6000, par = 0.78, exp = 38, seats = 1, tipMax = 0.35, strict = true },
	group = { id = "group", name = "Group Ride", icon = "👥", color = Color3.fromRGB(90, 120, 220), level = 6, weight = 14,
		base = 80, perStud = 0.03, minDist = 2500, maxDist = 8000, par = 1.1, exp = 55, seats = 3, tipMax = 0.3 },
	viprider = { id = "viprider", name = "VIP Ride", icon = "👑", color = Color3.fromRGB(212, 170, 50), level = 10, weight = 9,
		base = 150, perStud = 0.042, minDist = 3000, maxDist = 9000, par = 1.0, exp = 90, seats = 1, tipMax = 0.7, comfort = 1.3 },
	-- rides to and from the real landmarks (server/CivicJobs, 2026-11-18)
	busrun = { id = "busrun", name = "Student to the Bus Terminal", icon = "🎒", color = Color3.fromRGB(60, 140, 200), level = 3, weight = 13,
		base = 45, perStud = 0.024, maxDist = 9000, par = 0.95, exp = 38, seats = 1, tipMax = 0.3,
		hours = { { 15, 20.5 } },
		civic = { from = { pois = { "university" } }, to = { pois = { "bus" } }, item = "1 passenger", who = { "Nong Mai", "Nong Bew", "Nong Earth" } } },
	clinic = { id = "clinic", name = "Hospital Appointment", icon = "🏥", color = Color3.fromRGB(40, 170, 150), level = 3, weight = 11,
		base = 45, perStud = 0.024, maxDist = 7000, par = 1.1, exp = 38, seats = 1, tipMax = 0.45, fragile = true,
		hours = { { 6.5, 11 } },
		civic = { from = { home = true }, to = { pois = { "hospital" } }, item = "1 passenger", who = { "Grandma Boon", "Grandpa Sin", "Khun Dao" } } },
	train = { id = "train", name = "Catch the Train", icon = "🚆", color = Color3.fromRGB(150, 90, 60), level = 4, weight = 9,
		base = 50, perStud = 0.026, maxDist = 8000, par = 0.75, exp = 40, seats = 1, tipMax = 0.35, strict = true,
		hours = { { 6, 9 }, { 17, 21 } },
		civic = { from = { home = true }, to = { pois = { "station" } }, item = "1 passenger", who = { "Phi Ton", "Khun Kaew", "Phi Jack" } } },
	museum = { id = "museum", name = "Museum Visit", icon = "🏺", color = Color3.fromRGB(170, 120, 70), level = 3, weight = 7,
		base = 45, perStud = 0.024, maxDist = 8000, par = 1.05, exp = 36, seats = 1, tipMax = 0.4,
		hours = { { 9, 15.5 } },
		civic = { from = { home = true }, to = { pois = { "museum" } }, item = "1 passenger", who = { "Ajarn Wit", "Khun Oat", "Phi Nan" } } },
}
-- the loads of a "bigload" order (2026-11-19): id = the model client/Cargo builds, from = shop kinds it is picked up
-- at (DeliveryService), en / th = the order text
Jobs.BIGLOADS = {
	{ id = "fridge", from = { "mall", "convenience" }, en = "A two-door fridge", th = "ตู้เย็น 2 ประตู" },
	{ id = "mattress", from = { "mall" }, en = "A king-size mattress", th = "ฟูกนอน 6 ฟุต" },
	{ id = "durian", from = { "market", "nightmarket" }, en = "A pile of durians", th = "ทุเรียนกองโต" },
	{ id = "plant", from = { "market" }, en = "A giant potted palm", th = "ต้นปาล์มกระถางยักษ์" },
	{ id = "water", from = { "convenience" }, en = "Twelve packs of drinking water", th = "น้ำดื่ม 12 แพ็ค" },
	{ id = "fans", from = { "mall", "convenience" }, en = "Four electric fans", th = "พัดลม 4 ตัว" },
}
Jobs.BIGLOAD_BY_ID = {}
for _, b in ipairs(Jobs.BIGLOADS) do Jobs.BIGLOAD_BY_ID[b.id] = b end

Jobs.MEAL_BONUS = 0.15 -- food orders at the lunch (11:00-13:00) and dinner (17:30-19:30) rush

Jobs.RAIN_BONUS = 0.25 -- extra pay for any job done in the rain
Jobs.STORM_BONUS = 0.4
Jobs.NIGHT_BONUS = 0.1
Jobs.PAR_SPEED = 42 -- studs/s the "expected" trip assumes
Jobs.PAR_PAD = 22 -- seconds added for loading

-- Star rating from the trip. Each input is 0..1 (1 = perfect).
function Jobs.stars(timeScore: number, smooth: number, safety: number, strict: boolean?): number
	local w = strict and { 0.55, 0.15, 0.3 } or { 0.35, 0.25, 0.4 }
	local s = timeScore * w[1] + smooth * w[2] + safety * w[3]
	return math.clamp(math.floor((1 + s * 4) * 10 + 0.5) / 10, 1, 5)
end

return Jobs
