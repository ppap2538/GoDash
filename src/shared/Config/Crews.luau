-- Rider crews (2026-11-19, owner: "ทำตามที่แนะนำ": groups of riders with their own colours and a weekly table).
-- Chosen from this list (nobody types a name others see: all ages). Each crew rides in its own vest
-- (server/CrewService), and every delivery a member makes counts for the crew's weekly total.
local Crews = {}

Crews.LIST = {
	{ id = "orange", en = "Orange Vests", th = "วินเสื้อส้ม", icon = "🟠", color = Color3.fromRGB(240, 120, 40) },
	{ id = "lime", en = "Team Lime", th = "ทีมมะนาว", icon = "🍋", color = Color3.fromRGB(140, 205, 60) },
	{ id = "tea", en = "Milk Tea Gang", th = "แก๊งชานม", icon = "🧋", color = Color3.fromRGB(196, 140, 92) },
	{ id = "bolt", en = "Isan Bolts", th = "สายฟ้าอีสาน", icon = "⚡", color = Color3.fromRGB(250, 205, 40) },
	{ id = "dogs", en = "Soi Dog Riders", th = "หมาซอยไรเดอร์", icon = "🐕", color = Color3.fromRGB(150, 104, 70) },
	{ id = "lake", en = "Lake Racers", th = "บึงแก่นนครเรซซิ่ง", icon = "🌊", color = Color3.fromRGB(40, 150, 214) },
}
Crews.BY_ID = {}
for _, c in ipairs(Crews.LIST) do Crews.BY_ID[c.id] = c end
Crews.SWITCH_HOURS = 24 -- you can change crew once a day

return Crews
