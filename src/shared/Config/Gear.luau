-- Rider gear (2026-11-19, owner: "ทำตามที่แนะนำ"): things a rider buys once and keeps, sold in the phone's Gear app
-- (client/GearApp, server/GearService; d.gear = { owned = { [id] = true }, bag = id?, helmet = id? }).
--   bags: keep the food hot longer (server/JobService: the food cools from the pick-up; a hot delivery earns a
--         little extra, a cold one loses part of the tip; client/Spill shows it); the best one also holds the
--         order steadier (fewer spill points per jolt)
-- Made-up products only, no real brands.
local Gear = {}

Gear.COOL_SECONDS = 240 -- how long plain food stays warm enough after the pick-up (seconds of riding)
Gear.WARM_GRACE = 30 -- the first seconds cost nothing

Gear.ITEMS = {
	{ id = "bag_foam", slot = "bag", icon = "🎒", price = 350, keep = 1.7, steady = 1,
		en = "Foam thermal bag", th = "กระเป๋าโฟมเก็บความร้อน", enText = "Food stays hot 70 % longer", thText = "อาหารร้อนนานขึ้น 70%" },
	{ id = "bag_pro", slot = "bag", icon = "🧳", price = 1200, keep = 2.6, steady = 0.7,
		en = "Pro delivery box liner", th = "กล่องเก็บอุณหภูมิรุ่นโปร", enText = "Hot 2.6x as long, and the order sloshes less", thText = "ร้อนนานขึ้น 2.6 เท่า และน้ำซุปกระฉอกน้อยลง" },
}
Gear.BY_ID = {}
for _, g in ipairs(Gear.ITEMS) do Gear.BY_ID[g.id] = g end

-- the gear in use in a slot (from a profile's d.gear), or nil
function Gear.worn(gear, slot: string)
	if type(gear) ~= "table" then return nil end
	local id = gear[slot]
	local g = id and Gear.BY_ID[id]
	if g and type(gear.owned) == "table" and gear.owned[id] then return g end
	return nil
end

-- how warm an order is (0..1) after `seconds` since the pick-up, with this profile's gear
function Gear.heat(gear, seconds: number): number
	local bag = Gear.worn(gear, "bag")
	local keep = bag and bag.keep or 1
	return math.clamp(1 - math.max(0, seconds - Gear.WARM_GRACE) / (Gear.COOL_SECONDS * keep), 0, 1)
end

return Gear
