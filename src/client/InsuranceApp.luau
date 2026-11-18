-- The phone's Insurance app (2026-11-19, owner: "เพิ่มตามแนะนำ": ประกันรถ). Three plans for 24 real hours each
-- (Config/Insurance; server/InsuranceService buys them). With cover, an accident bill is paid by the insurer (the
-- claim scene brings their surveyor, client/Cutscene) and repairs get cheaper or free.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Insurance = require(Shared.Config.Insurance)
local UI = require(script.Parent.UI.Kit)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Phone = require(script.Parent.Phone)

local App = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local BLUE = Color3.fromRGB(30, 96, 180)

-- the plan in force and the seconds left, or nil
function App.active()
	local d = State.data
	local ins = d and d.insurance
	if type(ins) ~= "table" or type(ins.untilT) ~= "number" then return nil, 0 end
	local left = ins.untilT - Workspace:GetServerTimeNow()
	if left <= 0 then return nil, 0 end
	return Insurance.BY_ID[ins.plan], left
end

local function screen()
	local ui = Phone.ui
	if not State.data then return end
	local plan, left = App.active()
	local function noT(l) l:SetAttribute("NoTranslate", true) return l end
	local hero = ui.bigCard(112, plan and BLUE or C.dark)
	noT(UI.label(hero, "🛡 " .. L(Insurance.COMPANY.en, Insurance.COMPANY.th), 18, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) }))
	local status
	if plan then
		local h, m = math.floor(left / 3600), math.floor(left % 3600 / 60)
		status = L(("Covered: %s · %d h %02d min left"):format(plan.en, h, m), ("คุ้มครองอยู่: %s · เหลือ %d ชม. %02d นาที"):format(plan.th, h, m))
	else
		status = L("No cover: accident bills and repairs come out of your pocket", "ยังไม่มีประกัน: ชนแล้วจ่ายเองทั้งหมด")
	end
	noT(UI.label(hero, status, 14, C.white, F.bold, { Position = UDim2.fromOffset(14, 40), Size = UDim2.new(1, -28, 0, 20), TextWrapped = true }))
	noT(UI.label(hero, L("Hit someone? The insurer pays them and sends a surveyor. Repairs get cheaper.",
		"ชนคนหรือชนรถ ประกันจ่ายแทนและส่งพนักงานเคลมมาที่เกิดเหตุ ค่าซ่อมก็ถูกลง"), 12, Color3.fromRGB(220, 230, 245), F.med,
		{ Position = UDim2.fromOffset(14, 64), Size = UDim2.new(1, -28, 0, 40), TextWrapped = true }))
	ui.section(L("PLANS · 24 HOURS EACH", "เลือกแผน · ครั้งละ 24 ชม."))
	for i, p in ipairs(Insurance.PLANS) do
		local mine = plan and plan.id == p.id
		ui.row(mine and "✅" or "🛡", L(p.en, p.th) .. "  ·  ฿" .. p.price, L(p.enText, p.thText), mine and L("Extend", "ต่ออายุ") or L("Buy", "ซื้อ"), function()
			task.spawn(function()
				ui.call("City", "insure", p.id)
				Phone.refresh()
			end)
		end, { order = 10 + i, btnColor = mine and BLUE or C.green })
	end
	noT(UI.label(ui.content(), L("You can buy up to 3 days ahead. Changing plan keeps the time you have left.",
		"ซื้อล่วงหน้าได้สูงสุด 3 วัน เปลี่ยนแผนแล้วเวลาที่เหลือยังอยู่"), 12, C.sub, F.med, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 20 }))
end

function App.start()
	Phone.addApp({ id = "insurance", name = "Insurance", icon = "🛡", color = BLUE }, screen)
end

return App
