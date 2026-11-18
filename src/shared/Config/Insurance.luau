-- Vehicle insurance (2026-11-19, owner: "เพิ่มตามแนะนำ": ประกันรถชั้น 1 / 2+ / 3). Bought in the phone's Insurance
-- app for 24 real hours (buying again adds another 24 h). A made-up local insurer, no real company.
--   bills  = the share of an accident bill (server/AccidentService: the person or driver you hit) the insurer pays
--   repair = the share of a repair at KK Motors / a fuel station / home (server/VehicleService) the insurer pays
-- The bills are already capped by the daily limit (server/FineService: 2 bills, ฿600 a real day), so the prices
-- stay small: a careful rider does not need it, a busy or reckless one saves money and gets the claim scene with
-- the surveyor instead of paying.
local Insurance = {}

Insurance.COMPANY = { en = "Isan Safe Insurance", th = "อีสานเซฟ ประกันภัย" }
Insurance.HOURS = 24

Insurance.PLANS = {
	{ id = "c3", en = "Class 3", th = "ชั้น 3", price = 49, bills = 0.5, repair = 0,
		enText = "Pays half of what you owe the other side", thText = "จ่ายค่าเสียหายคู่กรณีให้ครึ่งหนึ่ง" },
	{ id = "c2", en = "Class 2+", th = "ชั้น 2+", price = 99, bills = 1, repair = 0.5,
		enText = "Pays the other side in full, half of your repairs", thText = "จ่ายคู่กรณีเต็ม + ค่าซ่อมรถเราครึ่งหนึ่ง" },
	{ id = "c1", en = "Class 1", th = "ชั้น 1", price = 169, bills = 1, repair = 1,
		enText = "Pays the other side and all your repairs", thText = "จ่ายคู่กรณีเต็ม + ซ่อมรถเราฟรีทั้งหมด" },
}
Insurance.BY_ID = {}
for _, p in ipairs(Insurance.PLANS) do Insurance.BY_ID[p.id] = p end

return Insurance
