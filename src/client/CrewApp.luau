-- The phone's Crews app (2026-11-19; Config/Crews, server/CrewService): pick a crew from the list, see this week's
-- table (deliveries by each crew's members), leave. Members ride in the crew's vest.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Crews = require(Shared.Config.Crews)
local UI = require(script.Parent.UI.Kit)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Phone = require(script.Parent.Phone)

local App = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local PURPLE = Color3.fromRGB(110, 60, 170)
local boardCache, boardAt = {}, -1e9

local function screen()
	local ui = Phone.ui
	local d = State.data
	if not d then return end
	local mine = type(d.crew) == "string" and Crews.BY_ID[d.crew] or nil
	local function noT(l) l:SetAttribute("NoTranslate", true) return l end
	local hero = ui.bigCard(84, mine and mine.color or PURPLE)
	noT(UI.label(hero, mine and (mine.icon .. " " .. L(mine.en, mine.th)) or L("🏍 Rider crews", "🏍 กลุ่มไรเดอร์"), 18, C.white, F.black,
		{ Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) }))
	noT(UI.label(hero, mine and L("You ride in the crew vest; every delivery counts for the crew this week.", "ขี่ด้วยเสื้อกั๊กของกลุ่ม ทุกงานที่ส่งนับคะแนนให้กลุ่มในสัปดาห์นี้")
		or L("Pick a crew: ride in its colours and help it top the weekly table.", "เลือกกลุ่มไรเดอร์ ใส่เสื้อสีเดียวกัน ช่วยกันขึ้นอันดับประจำสัปดาห์"),
		12, C.white, F.med, { Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 40), TextWrapped = true }))
	-- this week's table
	if os.clock() - boardAt > 30 then
		boardAt = os.clock()
		task.spawn(function()
			local ok, _, res = Net.call("City", "crew_board")
			if ok and type(res) == "table" then
				boardCache = res
				Phone.refresh()
			end
		end)
	end
	noT(ui.section(L("THIS WEEK", "อันดับสัปดาห์นี้"), 10))
	local rankOf = {}
	for i, e in ipairs(boardCache) do rankOf[e.id] = { i, e.n } end
	local order = 10
	local sorted = table.clone(Crews.LIST)
	table.sort(sorted, function(a, b)
		local ra, rb = rankOf[a.id], rankOf[b.id]
		return (ra and ra[2] or 0) > (rb and rb[2] or 0)
	end)
	for i, c in ipairs(sorted) do
		order += 1
		local n = rankOf[c.id] and rankOf[c.id][2] or 0
		local isMine = mine and mine.id == c.id
		ui.row(c.icon, ("%d. %s"):format(i, L(c.en, c.th)), L(("%d deliveries this week"):format(n), ("ส่งแล้ว %d งานสัปดาห์นี้"):format(n)),
			isMine and L("Leave", "ออก") or L("Join", "เข้าร่วม"), function()
				task.spawn(function()
					if isMine then ui.call("City", "crew_leave") else ui.call("City", "crew_join", c.id) end
					Phone.refresh()
				end)
			end, { order = order, btnWidth = 72, btnColor = isMine and Color3.fromRGB(150, 158, 170) or c.color })
	end
	noT(UI.label(ui.content(), L("You can change crew once a day.", "เปลี่ยนกลุ่มได้วันละครั้ง"), 12, C.sub, F.med, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 40 }))
end

function App.start()
	Phone.addApp({ id = "crews", name = "Crews", icon = "🏍", color = PURPLE }, screen)
end

return App
