-- First-join card: pick a language, then three lines that say what the game is and how to start.
-- Shown once (until the player has picked a language); the Guide card takes over afterwards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local UI = require(script.Parent.UI.Kit)
local Layout = require(script.Parent.UI.Core.Layout)
local Layers = require(script.Parent.UI.Core.Layers)
local UIState = require(script.Parent.UI.Core.UIState)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)

local Welcome = {}
local C, F = UI.C, UI.F
local touch = Layout.isTouch
local shown = false

local function noT(l: Instance)
	l:SetAttribute("NoTranslate", true)
	return l
end

local function show()
	if shown then return end
	shown = true
	local gui = UI.screen("GoDashWelcome", Layers.Modal + 5)
	local dim = UI.scrim(gui, 0.45)
	local center = Layout.region(Layout.stage(gui), "Center")
	local card = UI.new("Frame", { BackgroundColor3 = C.card, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, 380), Parent = center })
	UI.corner(card, 24)
	UI.stroke(card, C.green, 3)
	UIState.set("modal", true)

	local function close()
		UI.tween(card, 0.18, { Position = UDim2.fromScale(0.5, 0.6) })
		UI.tween(dim, 0.2, { BackgroundTransparency = 1 })
		task.delay(0.2, function()
			gui:Destroy()
			UIState.set("modal", false)
		end)
	end

	local function intro()
		UI.clear(card)
		local L = Lang.pick
		local head = UI.new("Frame", { BackgroundColor3 = C.green, Size = UDim2.new(1, 0, 0, 74), Parent = card })
		UI.corner(head, 24)
		UI.new("Frame", { BackgroundColor3 = C.green, Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 24), Parent = head })
		noT(UI.label(head, "🛵  GoDash", 26, C.white, F.black, { Position = UDim2.fromOffset(20, 8), Size = UDim2.new(1, -40, 0, 32), ZIndex = 2 }))
		noT(UI.label(head, L("You are a delivery rider in Khon Kaen", "คุณคือไรเดอร์ส่งอาหารในเมืองขอนแก่น"), 14, C.white, F.bold,
			{ Position = UDim2.fromOffset(20, 42), Size = UDim2.new(1, -40, 0, 20), ZIndex = 2 }))
		local steps = {
			{ "🚲", L("Get on your bicycle", "ขึ้นจักรยาน"), touch and L("walk to it and tap Drive", "เดินไปแล้วแตะ 'ขับ'") or L("walk to it and press F", "เดินไปแล้วกด F") },
			{ "📲", L("Go online", "เปิดรับงาน"), touch and L("tap the button at the top", "แตะปุ่มที่แถบด้านบน") or L("press J — orders pop up by themselves", "กด J แล้วออร์เดอร์จะเด้งขึ้นมาเอง") },
			{ "🟢", L("Follow the green line", "ขี่ตามเส้นสีเขียว"), L("collect the food, deliver it, get paid", "ไปรับอาหาร ไปส่ง แล้วรับเงิน") },
		}
		for i, s in ipairs(steps) do
			local y = 88 + (i - 1) * 62
			local row = UI.new("Frame", { BackgroundColor3 = C.bg, Position = UDim2.fromOffset(18, y), Size = UDim2.new(1, -36, 0, 54), Parent = card })
			UI.corner(row, 14)
			local num = UI.new("Frame", { BackgroundColor3 = C.green, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(36, 36), Parent = row })
			UI.corner(num, 18)
			noT(UI.label(num, s[1], 20, C.white, F.med, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None }))
			noT(UI.label(row, i .. ". " .. s[2], 16, C.text, F.black, { Position = UDim2.fromOffset(56, 7), Size = UDim2.new(1, -66, 0, 22) }))
			noT(UI.label(row, s[3], 13, C.sub, F.med, { Position = UDim2.fromOffset(56, 28), Size = UDim2.new(1, -66, 0, 18) }))
		end
		noT(UI.label(card, L("No need to remember this: the bar at the top always tells you what to do next.", "ไม่ต้องจำ แถบด้านบนจอจะบอกเสมอว่าต้องทำอะไรต่อ"), 13, C.greenDark, F.bold,
			{ Position = UDim2.fromOffset(20, 276), Size = UDim2.new(1, -40, 0, 36), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None }))
		noT(UI.button(card, L("Let's ride!", "เริ่มเล่นเลย!"), { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(1, -36, 0, 46), TextSize = 18 }, close))
	end

	-- page 1: language
	noT(UI.label(card, "🛵  GoDash: Thai Driver Life", 22, C.text, F.black, { Position = UDim2.fromOffset(20, 24), Size = UDim2.new(1, -40, 0, 30), TextXAlignment = Enum.TextXAlignment.Center }))
	noT(UI.label(card, "เลือกภาษา  ·  Choose your language", 15, C.sub, F.bold, { Position = UDim2.fromOffset(20, 62), Size = UDim2.new(1, -40, 0, 22), TextXAlignment = Enum.TextXAlignment.Center }))
	local function pick(code: string)
		Lang.set(code)
		task.spawn(function() Net.call("Settings", "lang", code) end)
		intro()
	end
	noT(UI.button(card, "🇹🇭  ภาษาไทย", { Position = UDim2.fromOffset(30, 110), Size = UDim2.new(1, -60, 0, 64), TextSize = 22 }, function() pick("th") end))
	noT(UI.button(card, "🇬🇧  English", { Position = UDim2.fromOffset(30, 190), Size = UDim2.new(1, -60, 0, 64), TextSize = 22, BackgroundColor3 = C.dark }, function() pick("en") end))
	noT(UI.label(card, "เปลี่ยนได้ทีหลังในมือถือ → ตั้งค่า  ·  Change it later in Phone → Settings", 11, C.sub, F.med,
		{ Position = UDim2.fromOffset(20, 276), Size = UDim2.new(1, -40, 0, 30), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None }))
	local sc = Instance.new("UIScale")
	sc.Scale = 0.6
	sc.Parent = card
	UI.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

function Welcome.start()
	local function check()
		local d = State.data
		if d and d.settings and not d.settings.langChosen then show() end
	end
	State.onData(function(keys) if keys.settings then check() end end)
	check()
end

return Welcome
