-- The day recap (2026-11-19, viral pack; owner: "ทำได้เลยทั้งหมด"). A card with today's numbers (d.daily: jobs,
-- income, distance, crashes, jolts, fines, dog bites, loads dropped, scammers caught) and a funny title of the day,
-- built to be shown off:
--   * 🎬 "today's highlights": the day's kept moments (client/Replay.moments: crashes, red lights, scammers...)
--     played back to back in clip mode with the camera cutting by itself, all in ONE recorded clip (client/Capture,
--     30 s at most, so the three newest that fit)
--   * 📸 share the card itself as a picture (a screenshot capture, then the share sheet)
-- Opens from the phone (📊 Recap) and by itself after you go to bed at home (the "sleep" scene).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local UI = require(script.Parent.UI.Kit)
local Layers = require(script.Parent.UI.Core.Layers)
local UIState = require(script.Parent.UI.Core.UIState)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Phone = require(script.Parent.Phone)
local Feedback = require(script.Parent.Feedback)
local Drive = require(script.Parent.Drive)
local Replay = require(script.Parent.Replay)
local Capture = require(script.Parent.Capture)
local Clip = require(script.Parent.ClipMode)

local Recap = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local gui: ScreenGui? = nil

-- the title of the day: the first rule that fits
local TITLES = {
	{ function(t) return t.fines >= 250 end, "👮", "King of Tickets", "เจ้าพ่อใบสั่ง" },
	{ function(t) return t.crashes >= 3 end, "💥", "Fearless (and a bit dented)", "สายซิ่งหน้าบาน" },
	{ function(t) return t.drops >= 1 end, "📦", "The Flying Cargo Rider", "ไรเดอร์ขนของบิน" },
	{ function(t) return t.scams >= 1 end, "🕵️", "Scam Buster", "นักสืบจับโป๊ะ" },
	{ function(t) return t.dogs >= 2 end, "🐕", "Every Soi Dog's Best Friend", "ขวัญใจหมาซอย" },
	{ function(t) return t.jobs >= 15 end, "🔥", "Hard-working Beyond 100%", "ไรเดอร์ขยันเกินร้อย" },
	{ function(t) return t.jobs >= 3 and t.harsh == 0 and t.crashes == 0 end, "🍜", "Steady Hands, Not a Drop Spilled", "มือนิ่ง น้ำซุปไม่หกสักหยด" },
	{ function(t) return t.km >= 20 end, "🛣", "The Long-road Traveller", "นักเดินทางไกล" },
	{ function(t) return t.jobs == 0 end, "😴", "Day Off Mode", "วันนี้ขอพักก่อน" },
	{ function() return true end, "🛵", "An Ordinary Rider, Extraordinary", "ไรเดอร์ธรรมดาผู้ไม่ธรรมดา" },
}

local function today()
	local d = State.data
	local dd = d and type(d.daily) == "table" and d.daily or {}
	local function n(k) return tonumber(dd[k]) or 0 end
	return { jobs = n("jobs"), income = n("income"), km = n("dist") / 1000, crashes = n("crashes"), harsh = n("harsh"),
		fines = n("fines"), dogs = n("dogs"), drops = n("drops"), scams = n("scams") }
end

local function close()
	if gui then gui:Destroy(); gui = nil end
	UIState.set("modal", false)
end

-- the newest kept moments that are on the vehicle you ride now and fit in one 30-second clip
local function reelMoments()
	local c = Drive.current()
	local out, total = {}, 0
	for _, ev in ipairs(Replay.moments) do
		if c and ev.model == c.model and ev.samples and #ev.samples >= 30 then
			local len = ev.samples[#ev.samples].t - ev.samples[1].t + 2.2 -- (plus the slow motion and the hold)
			if total + len > 28 then break end
			total += len
			table.insert(out, 1, ev) -- oldest first
		end
		if #out >= 3 then break end
	end
	return out
end

local function playReel()
	local list = reelMoments()
	if #list == 0 then
		Feedback.toast(L("🎬 No moments kept yet today: crash, run a red or catch a scammer first!", "🎬 วันนี้ยังไม่มีเหตุการณ์เด็ด ลองชน ฝ่าไฟแดง หรือจับโป๊ะคนแกล้งล้มก่อนนะ"), "bad")
		return
	end
	local c = Drive.current()
	local v = c and c.chassis and c.chassis.AssemblyLinearVelocity
	if not c or (v and Vector3.new(v.X, 0, v.Z).Magnitude > 12) then
		Feedback.toast(L("🎬 Get on your vehicle and stop first", "🎬 ขึ้นรถแล้วจอดนิ่งๆ ก่อนนะ"), "bad")
		return
	end
	close()
	if not Clip.active then Clip.open(true) end
	task.spawn(function()
		task.wait(0.3)
		local ok, why = Capture.start()
		if not ok then Capture.say(Capture.explain(why), "bad") end
		for i, ev in ipairs(list) do
			if ok and Capture.state ~= "rec" then break end -- stopped (⏹, or the 30 seconds ran out)
			local done = false
			Replay.instant({ samples = ev.samples, hitAt = ev.hitAt, director = true, external = true, chain = i < #list,
				onDone = function() done = true end })
			local t0 = os.clock()
			while not done and os.clock() - t0 < 40 do task.wait(0.1) end
			while Replay.isBusy() do task.wait(0.05) end
		end
		if ok then Capture.stop() end -- client/ClipMode's card offers share / keep
	end)
end

local function shareCard()
	if not Capture.available() then
		Feedback.toast(L("📸 This device can't take the picture: use a screenshot", "📸 เครื่องนี้ถ่ายรูปในเกมไม่ได้ ใช้แคปหน้าจอแทนนะ"), "bad")
		return
	end
	Capture.screenshot(function(shot)
		if shot then
			Capture.share(shot)
		else
			Feedback.toast(L("📸 The picture didn't work: use a screenshot", "📸 ถ่ายรูปไม่สำเร็จ ใช้แคปหน้าจอแทนนะ"), "bad")
		end
	end)
end

function Recap.show()
	if gui then return end
	local t = today()
	local title
	for _, r in ipairs(TITLES) do
		if r[1](t) then title = r break end
	end
	gui = UI.screen("GoDashRecap", Layers.Modal + 2)
	UIState.set("modal", true)
	UI.scrim(gui, 0.45)
	local card = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, 360),
		BackgroundColor3 = C.card, Parent = gui })
	UI.corner(card, 22)
	UI.stroke(card, Color3.fromRGB(28, 168, 84), 3)
	local head = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 96), BackgroundColor3 = Color3.fromRGB(28, 168, 84), Parent = card })
	UI.corner(head, 22)
	UI.new("Frame", { Position = UDim2.new(0, 0, 1, -22), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = Color3.fromRGB(28, 168, 84), Parent = head })
	local function noT(x) x:SetAttribute("NoTranslate", true); return x end
	noT(UI.label(head, L("📊 Rider's day", "📊 สรุปวันไรเดอร์") .. "  ·  " .. os.date("%d/%m"), 15, C.white, F.bold, { Position = UDim2.fromOffset(18, 8), Size = UDim2.new(1, -36, 0, 20), ZIndex = 2 }))
	noT(UI.label(head, title[2] .. " " .. L(title[3], title[4]), 24, C.white, F.black, { Position = UDim2.fromOffset(18, 32), Size = UDim2.new(1, -36, 0, 34), ZIndex = 2 }))
	noT(UI.label(head, player.DisplayName .. "  ·  GoDash 🛵", 12, Color3.fromRGB(220, 255, 230), F.med, { Position = UDim2.fromOffset(18, 68), Size = UDim2.new(1, -36, 0, 16), ZIndex = 2 }))
	-- the numbers, three by three
	local grid = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 108), Size = UDim2.new(1, -32, 0, 180), Parent = card })
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.new(1 / 3, -6, 0, 54)
	g.CellPadding = UDim2.fromOffset(8, 8)
	g.Parent = grid
	local cells = {
		{ "🧾", tostring(t.jobs), L("orders", "ออร์เดอร์") },
		{ "💰", Util.money(t.income), L("earned", "รายได้") },
		{ "🛣", ("%.1f km"):format(t.km), L("ridden", "ระยะทาง") },
		{ "💥", tostring(t.crashes), L("crashes", "ชน") },
		{ "🍜", tostring(t.harsh), L("jolts", "กระชาก") },
		{ "👮", Util.money(t.fines), L("in fines", "ค่าปรับ") },
		{ "🐕", tostring(t.dogs), L("dog bites", "โดนหมางับ") },
		{ "📦", tostring(t.drops), L("loads dropped", "ของตก") },
		{ "🕵️", tostring(t.scams), L("scams caught", "จับโป๊ะ") },
	}
	for _, c in ipairs(cells) do
		local f = UI.new("Frame", { BackgroundColor3 = C.bg, Parent = grid })
		UI.corner(f, 12)
		noT(UI.label(f, c[1] .. " " .. c[2], 17, C.text, F.black, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 24) }))
		noT(UI.label(f, c[3], 11, C.sub, F.med, { Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -20, 0, 16) }))
	end
	-- the buttons
	local row = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 16, 1, -60), Size = UDim2.new(1, -32, 0, 44), Parent = card })
	UI.list(row, 8, true)
	noT(UI.button(row, L("🎬 Today's highlights", "🎬 อัดไฮไลต์วันนี้"), { Size = UDim2.new(0.42, -6, 1, 0), TextSize = 14, BackgroundColor3 = Color3.fromRGB(200, 30, 40) }, playReel))
	noT(UI.button(row, L("📸 Share", "📸 แชร์การ์ด"), { Size = UDim2.new(0.3, -6, 1, 0), TextSize = 14, BackgroundColor3 = Color3.fromRGB(60, 110, 200) }, shareCard))
	noT(UI.button(row, L("Close", "ปิด"), { Size = UDim2.new(0.28, -6, 1, 0), TextSize = 14, BackgroundColor3 = C.dark }, close))
	local sc = Instance.new("UIScale")
	sc.Scale = 0.7
	sc.Parent = card
	UI.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	Feedback.play("tick", 0.5, 1.1, 0.1)
end

function Recap.start()
	Phone.addApp({ id = "recap", name = "Recap", icon = "📊", color = Color3.fromRGB(28, 140, 80) }, function()
		task.defer(Recap.show)
	end)
	-- after going to bed at home (server HousingService sends the "sleep" scene): the day's card
	Net.listen("Notify", function(kind, info)
		if kind == "scene" and type(info) == "table" and info.kind == "sleep" then
			task.delay(6, function()
				local t0 = os.clock()
				while (State.cutscene or UIState.get("modal")) and os.clock() - t0 < 30 do task.wait(0.5) end
				if not State.cutscene and not UIState.get("modal") then Recap.show() end
			end)
		end
	end)
end

return Recap
