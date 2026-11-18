-- The phone's Gear app (2026-11-19, owner: "ทำตามที่แนะนำ"): rider gear bought once and kept (Config/Gear,
-- server/GearService). Thermal bags keep the food hot longer (client/Spill shows the heat while you carry an order).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared.Config.Gear)
local UI = require(script.Parent.UI.Kit)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Phone = require(script.Parent.Phone)

local App = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local TEAL = Color3.fromRGB(16, 130, 120)

local SLOTS = {
	{ id = "bag", en = "DELIVERY BAGS", th = "กระเป๋าส่งอาหาร" },
	{ id = "helmet", en = "HELMETS", th = "หมวกกันน็อก" },
}

local function screen()
	local ui = Phone.ui
	local d = State.data
	if not d then return end
	local gear = type(d.gear) == "table" and d.gear or {}
	local owned = type(gear.owned) == "table" and gear.owned or {}
	local hero = ui.bigCard(84, TEAL)
	local function noT(l) l:SetAttribute("NoTranslate", true) return l end
	noT(UI.label(hero, L("🎒 Rider gear", "🎒 อุปกรณ์ไรเดอร์"), 18, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) }))
	noT(UI.label(hero, L("Buy once, keep for good. Hot food earns a little extra; cold food loses part of the tip.",
		"ซื้อครั้งเดียวใช้ได้ตลอด ส่งอาหารตอนยังร้อนได้เงินเพิ่ม ถ้าเย็นชืดทิปจะลดลง"), 12, Color3.fromRGB(220, 245, 240), F.med,
		{ Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 40), TextWrapped = true }))
	local order = 10
	for _, slot in ipairs(SLOTS) do
		local items = {}
		for _, g in ipairs(Gear.ITEMS) do
			if g.slot == slot.id then table.insert(items, g) end
		end
		if #items > 0 then
			order += 1
			local sec = ui.section(L(slot.en, slot.th), order)
			sec:SetAttribute("NoTranslate", true)
			for _, g in ipairs(items) do
				order += 1
				local have = owned[g.id] == true or g.price == 0
				local using = have and (gear[g.slot] == g.id or (g.slot == "helmet" and not gear.helmetOff and gear.helmet == nil and g.price == 0))
				local btn = using and L("In use", "ใช้อยู่") or (have and L("Use", "ใช้") or ("฿" .. g.price))
				ui.row(g.icon, L(g.en, g.th), L(g.enText, g.thText), btn, function()
					if using then return end
					task.spawn(function()
						ui.call("City", have and "gear_use" or "gear_buy", g.id)
						Phone.refresh()
					end)
				end, { order = order, btnColor = using and TEAL or (have and C.dark or C.green), btnWidth = 76 })
			end
			if slot.id == "helmet" then
				order += 1
				local off = gear.helmetOff == true
				ui.row("🚫", L("No helmet", "ไม่ใส่หมวก"), L("Police checkpoints fine you, and crashes hurt more", "ด่านตรวจปรับเพิ่ม และล้มแล้วเจ็บกว่าเดิม"), off and L("Chosen", "เลือกอยู่") or L("Choose", "เลือก"), function()
					if off then return end
					task.spawn(function()
						ui.call("City", "gear_use", "none:helmet")
						Phone.refresh()
					end)
				end, { order = order, btnColor = off and Color3.fromRGB(190, 60, 50) or C.dark, btnWidth = 76 })
			end
		end
	end
end

function App.start()
	Phone.addApp({ id = "gear", name = "Gear", icon = "🎒", color = TEAL }, screen)
end

return App
