-- Phone app "Company" (2026-11-17 Tier-A plan): your rank, and from the "Rider" rank your own rider
-- company: hire riders, give them better bikes, collect what they earned (server/CompanyService).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Store = require(Shared.Config.Store)
local Util = require(Shared.Util)
local UI = require(script.Parent.UI.Kit)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Phone = require(script.Parent.Phone)

local CompanyApp = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local CO = Store.COMPANY
local ORANGE = Color3.fromRGB(230, 120, 30)

local function noT(l: Instance)
	l:SetAttribute("NoTranslate", true)
	return l
end

local function screen()
	local ui = Phone.ui
	local content = ui.content()
	local d = State.data
	if not d then return end
	local jobs = (d.stats.deliveries or 0) + (d.stats.rides or 0)
	local rank, r = Store.rankFor(jobs)
	local nextR = Store.RANKS[rank + 1]
	local hero = ui.bigCard(96, r.color)
	noT(UI.label(hero, "🏅 " .. L(r.name, r.thai), 18, C.black, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) }))
	noT(UI.label(hero, nextR and L(("%d jobs · next rank at %d"):format(jobs, nextR.jobs), ("ส่งแล้ว %d งาน · ยศถัดไปที่ %d งาน"):format(jobs, nextR.jobs)) or L(("%d jobs · top rank"):format(jobs), ("ส่งแล้ว %d งาน · ยศสูงสุดแล้ว"):format(jobs)),
		13, C.black, F.bold, { Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 18) }))
	noT(UI.label(hero, L(("Rank bonus: tips +%d%%"):format(r.tip * 100), ("โบนัสยศ: ทิป +%d%%"):format(r.tip * 100)), 12, C.black, F.med, { Position = UDim2.fromOffset(14, 58), Size = UDim2.new(1, -28, 0, 16) }))
	if nextR then
		local track, set = UI.bar(hero, C.black, 6)
		track.Position = UDim2.fromOffset(14, 80)
		track.Size = UDim2.new(1, -28, 0, 6)
		set((jobs - r.jobs) / math.max(1, nextR.jobs - r.jobs))
	end

	ui.section(L("MY RIDER COMPANY", "บริษัทไรเดอร์ของฉัน"))
	if rank < CO.unlockRank then
		noT(UI.label(content, L(("Reach the \"Rider\" rank (%d jobs) to open your own company and hire riders."):format(Store.RANKS[CO.unlockRank].jobs),
			("ถึงยศ \"ไรเดอร์\" (%d งาน) เพื่อเปิดบริษัทและจ้างไรเดอร์มาทำงานให้"):format(Store.RANKS[CO.unlockRank].jobs)), 13, C.sub, F.med, { Size = UDim2.new(1, 0, 0, 44), TextWrapped = true }))
		return
	end
	local c = type(d.company) == "table" and d.company or { riders = 0, level = 1, bank = 0 }
	local rate = c.riders * CO.perMinute * (1 + CO.levelBonus * (c.level - 1))
	local card = ui.bigCard(104, ORANGE)
	noT(UI.label(card, L(("🏢 %d riders · bikes level %d"):format(c.riders, c.level), ("🏢 ไรเดอร์ %d คน · รถระดับ %d"):format(c.riders, c.level)), 16, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 22) }))
	noT(UI.label(card, L(("Earning %s a minute while you play (half while away, up to %d h)"):format(Util.money(rate), CO.offlineHours),
		("ได้ %s ต่อนาทีระหว่างเล่น (ตอนไม่อยู่ได้ครึ่งเดียว สูงสุด %d ชม.)"):format(Util.money(rate), CO.offlineHours)), 12, C.white, F.med, { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 32), TextWrapped = true }))
	noT(UI.label(card, L("In the account: ", "ในบัญชีบริษัท: ") .. Util.money(math.floor(c.bank)), 15, C.white, F.black, { Position = UDim2.fromOffset(14, 70), Size = UDim2.new(1, -120, 0, 22) }))
	noT(UI.button(card, L("Collect", "เก็บเงิน"), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 66), Size = UDim2.fromOffset(96, 30), TextSize = 14, BackgroundColor3 = C.white, TextColor3 = ORANGE }, function()
		if ui.call("City", "company_collect") then Phone.refresh() end
	end))
	local maxR = CO.maxRiders(rank)
	ui.row("🧑", L(("Hire a rider (%d / %d)"):format(c.riders, maxR), ("จ้างไรเดอร์ (%d / %d)"):format(c.riders, maxR)),
		c.riders >= maxR and L("Rank up to hire more", "เลื่อนยศเพื่อจ้างเพิ่ม") or (L("Cost ", "ค่าจ้าง ") .. Util.money(CO.hireCost(c.riders))),
		L("Hire", "จ้าง"), function() if ui.call("City", "company_hire") then Phone.refresh() end end, { btnWidth = 62, disabled = c.riders >= maxR })
	ui.row("🛵", L(("Better bikes (level %d / %d)"):format(c.level, CO.maxLevel), ("รถที่ดีขึ้น (ระดับ %d / %d)"):format(c.level, CO.maxLevel)),
		c.level >= CO.maxLevel and L("Top level", "ระดับสูงสุดแล้ว") or (L("+25% for every rider · ", "+25% ทุกคน · ") .. Util.money(CO.levelCost(c.level))),
		L("Upgrade", "อัปเกรด"), function() if ui.call("City", "company_upgrade") then Phone.refresh() end end, { btnWidth = 70, disabled = c.level >= CO.maxLevel or c.riders == 0 })
end

function CompanyApp.start()
	Phone.addApp({ id = "company", name = "Company", icon = "🏢", color = ORANGE, badge = function()
		local d = State.data
		return d ~= nil and type(d.company) == "table" and (d.company.bank or 0) >= 500
	end }, screen)
end

return CompanyApp
