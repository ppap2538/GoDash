-- "Reviews" phone app (2026-11-18, owner: "a history of customer reviews: how many stars lately, what
-- they said, what to improve, realistic"). server/JobService keeps the last 30 reviews in d.reviews:
-- { t, s = stars, m = "food" | "ride", who, tip, tags, seed }. The tags say why (late, bumpy, crash,
-- red light...); this turns them into what the customer wrote, and the most common complaints of the
-- last 15 into advice.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local UI = require(script.Parent.UI.Kit)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Phone = require(script.Parent.Phone)

local Reviews = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local GOLD = Color3.fromRGB(236, 160, 20)
local seen = 0 -- reviews counted when the app was last opened (for the red dot)

-- what customers write, per tag (a few ways each; the review's seed picks one)
local SAY = {
	fast = { { "Super fast! Arrived before I even put my phone down.", "ไวมากกก วางโทรศัพท์ยังไม่ทันก็มาถึงแล้ว" }, { "Lightning delivery, thank you!", "ส่งไวทันใจ ขอบคุณค่ะ" } },
	hot = { { "The food was still hot. 10/10.", "อาหารยังร้อนอยู่เลย ให้สิบเต็มสิบ" }, { "Arrived steaming, soup not spilled at all.", "ร้อนๆ น้ำซุปไม่หกสักหยด" } },
	great = { { "Polite rider, smooth and on time. Will order again.", "ไรเดอร์สุภาพ ขับนุ่ม ตรงเวลา จะสั่งอีกแน่นอน" }, { "Perfect. Have a five-star day!", "เพอร์เฟกต์ ขอให้วันนี้เป็นวันห้าดาวนะ" } },
	ok = { { "Fine. Nothing special.", "โอเค ไม่มีอะไรพิเศษ" }, { "Got it. Thanks.", "ได้ของแล้ว ขอบคุณ" } },
	late = { { "A bit late, the noodles got soggy.", "มาช้าไปหน่อย เส้นอืดแล้ว" }, { "Took longer than the app said.", "นานกว่าที่แอปบอกนะ" } },
	verylate = { { "Way too late. I nearly cooked something myself.", "ช้ามากกก เกือบจะลุกไปทำกับข้าวเองแล้ว" }, { "My food arrived cold. Please hurry next time.", "อาหารเย็นชืดหมดแล้ว คราวหน้ารีบหน่อยนะ" } },
	bumpy = { { "The bag looked like it went through a storm.", "ถุงมาสภาพเหมือนผ่านพายุมา" }, { "Rode like a race, everything shook loose.", "ขี่อย่างกับแข่ง ของในถุงกระจายหมด" } },
	spilled = { { "The soup spilled all over the bag!", "น้ำแกงหกเลอะทั้งถุงเลย!" }, { "Fragile order, rough ride. Half of it broke.", "ของแตกง่ายแต่ขี่โหด เสียหายไปครึ่งนึง" } },
	rough = { { "Braked so hard I nearly flew off.", "เบรกแรงจนเกือบหลุดจากเบาะ" }, { "Hold on tight, they said. Now I know why.", "บอกให้จับแน่นๆ ตอนนี้เข้าใจแล้วว่าทำไม" } },
	comfy = { { "So smooth I nearly fell asleep.", "ขี่นุ่มมาก เกือบหลับเลย" }, { "Comfortable ride, nice and careful.", "นั่งสบาย ขับระวังดีมาก" } },
	crash = { { "We crashed on the way. Are you OK?!", "ชนระหว่างทางด้วย เป็นอะไรไหมเนี่ย!" }, { "My order arrived... after a crash.", "ของมาถึงนะ... หลังจากชนมาแล้ว" } },
	redlight = { { "Ran a red light. Please be careful!", "ฝ่าไฟแดงด้วย ระวังหน่อยนะ!" }, { "Fast, but the red light was red, you know.", "ไวก็ไวแหละ แต่ไฟแดงก็คือแดงนะ" } },
}
-- the advice for the most common complaints
local FIX = {
	late = { "⏰ Often late: take orders closer to you and follow the green line.", "⏰ ส่งช้าบ่อย: รับงานที่ใกล้ตัว แล้วขี่ตามเส้นสีเขียว" },
	verylate = { "⏰ Very late deliveries: don't stop on the way with food in the box.", "⏰ ส่งช้ามาก: อย่าแวะระหว่างทางตอนมีอาหารในกล่อง" },
	bumpy = { "🛵 Bumpy ride: ease off the throttle and brake gently, slow for speed bumps.", "🛵 ขี่กระชาก: ค่อยๆ เร่ง เบรกเบาๆ ชะลอตรงลูกระนาด" },
	spilled = { "🍲 Spilled orders: fragile food needs a smooth ride.", "🍲 อาหารหก: ของแตกง่ายต้องขี่นุ่มๆ" },
	rough = { "🧍 Passengers felt unsafe: brake earlier and corner gently.", "🧍 ผู้โดยสารไม่สบายใจ: เบรกก่อนถึง เข้าโค้งช้าๆ" },
	crash = { "💥 Crashes cost stars, money and injuries: keep your distance.", "💥 ชนบ่อย เสียทั้งดาว เงิน และบาดเจ็บ: เว้นระยะห่างหน่อย" },
	redlight = { "🚦 Red lights: stop at red (left on red is OK).", "🚦 ไฟแดง: หยุดรอ (เลี้ยวซ้ายผ่านตลอดได้)" },
}
local BAD = { late = 1, verylate = 2, bumpy = 1, spilled = 2, rough = 1, crash = 2, redlight = 1 }

local function stars(s: number): string
	local full = math.floor(s + 0.25)
	local out = string.rep("★", full) .. string.rep("☆", 5 - full)
	return out
end

local function ago(t: number): string
	local s = math.max(0, os.time() - (t or os.time()))
	if s < 60 then return L("just now", "เมื่อสักครู่") end
	if s < 3600 then local m = s // 60; return L(m .. " min ago", m .. " นาทีที่แล้ว") end
	if s < 86400 then local h = s // 3600; return L(h .. " h ago", h .. " ชม.ที่แล้ว") end
	local dd = s // 86400
	return L(dd .. " d ago", dd .. " วันที่แล้ว")
end

local function sentence(r): string
	local parts = {}
	for i, tag in ipairs(r.tags or {}) do
		local list = SAY[tag]
		if list then
			local pick = list[((r.seed or 1) + i) % #list + 1]
			table.insert(parts, Lang.code == "th" and pick[2] or pick[1])
		end
	end
	return table.concat(parts, " ")
end

local function screen()
	local ui = Phone.ui
	local d = State.data
	if not d then return end
	local list = type(d.reviews) == "table" and d.reviews or {}
	seen = #list > 0 and (list[1].t or 0) or seen
	-- the headline: the overall rating, and the last 10
	local recent, rn = 0, 0
	for i = 1, math.min(10, #list) do recent += list[i].s or 0; rn += 1 end
	local hero = ui.bigCard(104, GOLD)
	UI.label(hero, L("⭐ My reviews", "⭐ รีวิวจากลูกค้า"), 18, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) })
	UI.label(hero, ("★ %.2f"):format(d.rating or 5), 30, C.white, F.black, { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(0.5, 0, 0, 36) })
	UI.label(hero, L(("%d ratings in total"):format(d.ratingCount or 0), ("จากทั้งหมด %d รีวิว"):format(d.ratingCount or 0)), 12, C.white, F.med,
		{ Position = UDim2.fromOffset(14, 74), Size = UDim2.new(0.5, -14, 0, 18) })
	if rn > 0 then
		local avg = recent / rn
		local trend = avg >= (d.rating or 5) + 0.05 and "↗" or (avg <= (d.rating or 5) - 0.05 and "↘" or "→")
		UI.label(hero, rn == 1 and L("Last job", "งานล่าสุด") or L(("Last %d jobs"):format(rn), ("%d งานล่าสุด"):format(rn)), 12, C.white, F.med, { Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.new(0.5, -14, 0, 16), TextXAlignment = Enum.TextXAlignment.Right })
		UI.label(hero, ("%s ★ %.1f"):format(trend, avg), 22, C.white, F.black, { Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.new(0.5, -14, 0, 28), TextXAlignment = Enum.TextXAlignment.Right })
	end
	if #list == 0 then
		UI.label(ui.content(), L("No reviews yet. Deliver an order and the customer will rate you.", "ยังไม่มีรีวิว ส่งงานแรกแล้วลูกค้าจะให้คะแนน"), 13, C.sub, F.med, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 34) })
		return
	end
	-- what to improve: the complaints that come up most in the last 15
	local count = {}
	for i = 1, math.min(15, #list) do
		for _, tag in ipairs(list[i].tags or {}) do
			if BAD[tag] then count[tag] = (count[tag] or 0) + BAD[tag] end
		end
	end
	local top = {}
	for tag, n in pairs(count) do table.insert(top, { tag = tag, n = n }) end
	table.sort(top, function(a, b) return a.n > b.n end)
	ui.section(L("WHAT TO IMPROVE", "สิ่งที่ควรปรับปรุง"))
	if #top == 0 then
		UI.label(ui.content(), L("🎉 No complaints lately. Keep it up!", "🎉 ช่วงนี้ไม่มีใครบ่นเลย รักษามาตรฐานไว้นะ!"), 13, C.green, F.bold, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 22) })
	else
		for i = 1, math.min(3, #top) do
			local f = FIX[top[i].tag]
			if f then
				local lbl = UI.label(ui.content(), Lang.code == "th" and f[2] or f[1], 13, C.text, F.med, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 34) })
				lbl:SetAttribute("NoTranslate", true)
			end
		end
	end
	-- the reviews, newest first
	ui.section(L("LATEST REVIEWS", "รีวิวล่าสุด"))
	for _, r in ipairs(list) do
		local good = (r.s or 0) >= 4.5
		local card = UI.card(ui.content(), { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = good and Color3.fromRGB(255, 250, 236) or ((r.s or 0) < 3 and Color3.fromRGB(255, 240, 238) or C.card) })
		UI.pad(card, 12, 8, 12, 8)
		UI.list(card, 3)
		local who = (r.who and r.who ~= "") and Lang.t(r.who) or L("Customer", "ลูกค้า")
		local head = UI.label(card, ("%s  %.1f  ·  %s %s  ·  %s"):format(stars(r.s or 0), r.s or 0, r.m == "ride" and "🧍" or "🍱", who, ago(r.t)), 12, GOLD, F.bold, { Size = UDim2.new(1, 0, 0, 18) })
		head:SetAttribute("NoTranslate", true)
		local body = UI.label(card, "“" .. sentence(r) .. "”", 14, C.text, F.med, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true })
		body:SetAttribute("NoTranslate", true)
		if (r.tip or 0) > 0 then
			local tipL = UI.label(card, L("💰 Tip ", "💰 ทิป ") .. Util.money(r.tip), 11, C.green, F.bold, { Size = UDim2.new(1, 0, 0, 14) })
			tipL:SetAttribute("NoTranslate", true)
		end
	end
end

function Reviews.start()
	Phone.addApp({ id = "reviews", name = "Reviews", icon = "⭐", color = GOLD, badge = function()
		local list = State.data and State.data.reviews
		return type(list) == "table" and #list > 0 and (list[1].t or 0) > seen
	end }, screen)
end

return Reviews
