-- Crops and the maths of growing them. The same code runs on server (truth) and client (display),
-- and works from timestamps so crops keep growing while the player is offline.
local Crops = {}

Crops.List = {
	{ id = "lettuce", name = "Lettuce", seed = "seed_lettuce", level = 1, grow = 120, thirst = 1 / 100, fertNeed = 0.2, yield = 3, color = Color3.fromRGB(120, 200, 90) },
	{ id = "chili", name = "Chili", seed = "seed_chili", level = 1, grow = 180, thirst = 1 / 130, fertNeed = 0.3, yield = 5, color = Color3.fromRGB(210, 50, 40) },
	{ id = "tomato", name = "Tomato", seed = "seed_tomato", level = 2, grow = 240, thirst = 1 / 110, fertNeed = 0.4, yield = 5, color = Color3.fromRGB(220, 60, 50) },
	{ id = "corn", name = "Corn", seed = "seed_corn", level = 4, grow = 360, thirst = 1 / 150, fertNeed = 0.5, yield = 4, color = Color3.fromRGB(240, 200, 60) },
	{ id = "rice", name = "Rice", seed = "seed_rice", level = 6, grow = 600, thirst = 1 / 80, fertNeed = 0.4, yield = 10, color = Color3.fromRGB(200, 190, 90) },
	{ id = "watermelon", name = "Watermelon", seed = "seed_watermelon", level = 9, grow = 900, thirst = 1 / 120, fertNeed = 0.7, yield = 2, color = Color3.fromRGB(60, 140, 70) },
}
Crops.ById = {}
for _, c in ipairs(Crops.List) do Crops.ById[c.id] = c end

Crops.BEDS = 8 -- beds per allotment
Crops.FREE_BEDS = 3
Crops.BED_PRICE = { 0, 0, 0, 600, 1500, 3500, 8000, 16000 }
Crops.GRADES = { { name = "C", mult = 0.7 }, { name = "B", mult = 1.0 }, { name = "A", mult = 1.35 }, { name = "S", mult = 1.8 } }

-- bed = { soil = 0..1, tilled = bool, crop = id?, progress = 0..1, water = 0..1, fert = 0..1, health = 0..1, t = lastUpdate }
function Crops.newBed()
	return { soil = 0.7, tilled = false }
end

-- Advance a bed to `now`. Growth only happens while there is water; a dry crop slowly loses health.
function Crops.advance(bed, now: number, raining: boolean?)
	if not bed.crop then bed.t = now; return bed end
	local def = Crops.ById[bed.crop]
	if not def then bed.crop = nil; return bed end
	local dt = math.max(0, now - (bed.t or now))
	bed.t = now
	if dt <= 0 or bed.progress >= 1 then
		if raining then bed.water = 1 end
		return bed
	end
	if raining then bed.water = 1 end
	local water = bed.water or 0
	local wetTime = raining and dt or math.min(dt, water / def.thirst)
	local dryTime = dt - wetTime
	if not raining then bed.water = math.max(0, water - dt * def.thirst) end
	local speed = 0.85 + 0.3 * (bed.soil or 0.7) -- good soil grows faster
	local remaining = (1 - bed.progress) * def.grow / speed
	local used = math.min(wetTime, remaining)
	bed.progress = math.min(1, bed.progress + used * speed / def.grow)
	if dryTime > 0 and bed.progress < 1 then
		-- a fully dry crop loses all health in about 3 grow-times
		bed.health = math.max(0.05, (bed.health or 1) - dryTime / (def.grow * 3))
	end
	return bed
end

function Crops.stage(bed): number -- 0 empty, 1 sprout, 2 growing, 3 mature-ish, 4 ready
	if not bed.crop then return 0 end
	local p = bed.progress or 0
	if p >= 1 then return 4 end
	if p >= 0.66 then return 3 end
	if p >= 0.25 then return 2 end
	return 1
end

-- Quality from health, fertilizer and soil. Returns grade index 1..4 and a 0..1 score.
function Crops.quality(bed): (number, number)
	local def = Crops.ById[bed.crop]
	local fert = math.clamp(bed.fert or 0, 0, 1)
	local fertScore = 1 - def.fertNeed * (1 - fert)
	local score = (bed.health or 1) * 0.5 + fertScore * 0.3 + (bed.soil or 0.7) * 0.2
	local grade = 1
	if score >= 0.9 then grade = 4 elseif score >= 0.76 then grade = 3 elseif score >= 0.58 then grade = 2 end
	return grade, score
end

-- Farmers' market price multiplier for a crop on a given day (0.75 .. 1.3), same on every server.
function Crops.marketMult(cropId: string, day: number): number
	local h = 0
	for i = 1, #cropId do h = (h * 31 + cropId:byte(i)) % 9973 end
	local r = Random.new(day * 9973 + h)
	return 0.75 + r:NextNumber() * 0.55
end

return Crops
