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
}

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
