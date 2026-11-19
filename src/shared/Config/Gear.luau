-- Rider gear (2026-11-19, owner: "ทำตามที่แนะนำ"): things a rider buys once and keeps, sold in the phone's Gear app
-- (client/GearApp, server/GearService; d.gear = { owned = { [id] = true }, bag = id?, helmet = id? }).
--   helmets (2026-11-19): worn on the head while riding a motorbike (server/GearService welds one on); the free half
--         helmet is everyone's by default; better ones protect more (server/HealthService: less injury in a crash).
--         Riding a motorbike without one at a police checkpoint costs an extra fine (server/PoliceService).
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
-- (2026-11-19, owner: "เอาหมวกกันนอคออกเลย") helmets are gone from the game: nobody wears one, checkpoints don't
-- fine for it, crashes hurt the same. The old list stays only so server/GearService can refund what riders paid.
Gear.HELMETS = false
Gear.RETIRED_HELMETS = {}
for _, h in ipairs({
	{ id = "helmet_half", price = 0, protect = 0.75, shape = "half", color = Color3.fromRGB(236, 236, 232), icon = "⛑",
		en = "Half helmet (free)", th = "หมวกครึ่งใบ (แถมฟรี)", enText = "Comes with every rider", thText = "ไรเดอร์ทุกคนได้ฟรี" },
	{ id = "helmet_full", price = 600, protect = 0.5, shape = "full", color = Color3.fromRGB(30, 32, 38), icon = "🪖",
		en = "Full-face helmet", th = "หมวกเต็มใบ", enText = "Half the injury in a crash", thText = "ล้มแล้วเจ็บน้อยลงครึ่งหนึ่ง" },
	{ id = "helmet_dog", price = 900, protect = 0.6, shape = "half", ears = true, color = Color3.fromRGB(232, 150, 60), icon = "🐶",
		en = "Soi-dog ears helmet", th = "หมวกหูหมาซอย", enText = "Cute ears; good for clips", thText = "มีหูน่ารัก ถ่ายคลิปปัง" },
	{ id = "helmet_silk", price = -1, festival = true, protect = 0.6, shape = "half", color = Color3.fromRGB(170, 30, 110), icon = "🧵", shiny = true,
		en = "Silk-pattern helmet", th = "หมวกลายผ้าไหม", enText = "Free at the Khon Kaen Silk Festival", thText = "ของที่ระลึก ไปงานเทศกาลไหมรับฟรี" },
	{ id = "helmet_gold", price = 1500, protect = 0.5, shape = "full", color = Color3.fromRGB(230, 185, 60), icon = "👑",
		en = "Gold rider helmet", th = "หมวกทองไรเดอร์", enText = "Shiny, and half the injury", thText = "เงาวับ ล้มแล้วเจ็บน้อยลงครึ่งหนึ่ง", shiny = true },
}) do
	h.slot = "helmet"
	if Gear.HELMETS then table.insert(Gear.ITEMS, h) else Gear.RETIRED_HELMETS[h.id] = h end
end
Gear.DEFAULT_HELMET = "helmet_half"

Gear.BY_ID = {}
for _, g in ipairs(Gear.ITEMS) do Gear.BY_ID[g.id] = g end

-- owns item id (free items count as owned)
function Gear.owns(gear, id: string): boolean
	local g = Gear.BY_ID[id]
	if not g then return false end
	if g.price == 0 then return true end
	return type(gear) == "table" and type(gear.owned) == "table" and gear.owned[id] == true
end

-- the gear in use in a slot (from a profile's d.gear), or nil. Helmets: the free half helmet unless the rider
-- chose to ride without one (gear.helmetOff)
function Gear.worn(gear, slot: string)
	local t = type(gear) == "table" and gear or {}
	if slot == "helmet" and (t.helmetOff or not Gear.HELMETS) then return nil end
	local id = t[slot]
	local g = id and Gear.BY_ID[id]
	if g and Gear.owns(t, id) then return g end
	if slot == "helmet" then return Gear.BY_ID[Gear.DEFAULT_HELMET] end
	return nil
end

-- how warm an order is (0..1) after `seconds` since the pick-up, with this profile's gear
function Gear.heat(gear, seconds: number): number
	local bag = Gear.worn(gear, "bag")
	local keep = bag and bag.keep or 1
	return math.clamp(1 - math.max(0, seconds - Gear.WARM_GRACE) / (Gear.COOL_SECONDS * keep), 0, 1)
end

return Gear
