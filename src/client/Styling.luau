-- Phone app "Styling" (แต่งซิ่ง, 2026-11-17 growth plan): underglow, a custom number plate, a sticker
-- and the horn for each owned vehicle. Looks only, no driving numbers. The server (VehicleService
-- "style") charges, filters the plate text and refits the vehicle if it is out on the road.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Vehicles = require(Shared.Config.Vehicles)
local Sounds = require(Shared.Config.Sounds)
local Util = require(Shared.Util)
local UI = require(script.Parent.UI.Kit)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)
local Phone = require(script.Parent.Phone)

local Styling = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local PURPLE = Color3.fromRGB(120, 60, 200)
local selected: string? = nil
local plateDraft = ""

local function noT(l: Instance)
	l:SetAttribute("NoTranslate", true)
	return l
end

local function preview(style: number)
	local function play(id: string, pitch: number, vol: number)
		local s = Instance.new("Sound")
		s.SoundId = id
		s.PlaybackSpeed = pitch
		s.Volume = vol
		s.SoundGroup = Feedback.sfxGroup
		s.Parent = SoundService
		s:Play()
		task.delay(3, function() s:Destroy() end)
	end
	if style == 5 then play(Sounds.bell, 1, 0.45)
	elseif style == 2 then play(Sounds.horn, 0.75, 0.6)
	elseif style == 3 then play(Sounds.horn, 0.82, 0.6); task.delay(0.22, function() play(Sounds.horn, 0.78, 0.6) end)
	elseif style == 4 then play(Sounds.horn, 1.6, 0.45); task.delay(0.16, function() play(Sounds.horn, 1.6, 0.45) end)
	else play(Sounds.horn, 1.05, 0.55) end
end

-- pass and season cosmetics (Config/Vehicles "need")
local function hasNeed(need: string?): boolean
	if not need then return true end
	local p = game.Players.LocalPlayer
	if need == "vip" then return p:GetAttribute("VIP") == true end
	if need == "neon" then return p:GetAttribute("NeonPro") == true end
	local d = State.data
	return d ~= nil and type(d.unlocks) == "table" and d.unlocks[need] == true
end

local function unlockHint(need: string?)
	local Store = require(Shared.Config.Store)
	local MarketplaceService = game:GetService("MarketplaceService")
	if need == "vip" then MarketplaceService:PromptGamePassPurchase(game.Players.LocalPlayer, Store.PASSES.vip.id)
	elseif need == "neon" then MarketplaceService:PromptGamePassPurchase(game.Players.LocalPlayer, Store.PASSES.neon.id)
	else Feedback.toast(L("Unlocked in the Season Pass (Season app)", "ปลดล็อกได้จาก Season Pass (แอปซีซัน)"), "bad") end
end

local function screen()
	local ui = Phone.ui
	local content = ui.content()
	local d = State.data
	if not d then return end
	if not selected or not d.vehicles[selected] then selected = d.activeVehicle end
	local def = Vehicles.ById[selected]
	local owned = d.vehicles[selected]
	if not def or not owned then return end
	local st = type(owned.style) == "table" and owned.style or {}
	local function fit(kind: string, value: any)
		if ui.call("Garage", "style", def.id, { kind = kind, value = value }) then Phone.refresh() end
	end

	local hero = ui.bigCard(84, PURPLE)
	noT(UI.label(hero, L("🔧 Styling", "🔧 แต่งซิ่ง"), 18, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) }))
	noT(UI.label(hero, L("Make it yours: light, plate, sticker, horn. Looks only.", "แต่งให้เป็นของเรา: ไฟใต้ท้อง ป้ายทะเบียน สติกเกอร์ แตร (สวยอย่างเดียว ไม่เพิ่มความเร็ว)"), 12, C.white, F.med,
		{ Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 40), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }))

	-- which vehicle
	ui.section(L("VEHICLE", "รถ"))
	local pick = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = content })
	UI.list(pick, 6, true)
	local ids = {}
	for id in pairs(d.vehicles) do table.insert(ids, id) end
	table.sort(ids, function(a, b) return (Vehicles.ById[a] and Vehicles.ById[a].price or 0) < (Vehicles.ById[b] and Vehicles.ById[b].price or 0) end)
	for _, id in ipairs(ids) do
		local vd = Vehicles.ById[id]
		if vd then
			local sel = id == selected
			noT(UI.button(pick, Lang.code == "th" and vd.thai or vd.name, { Size = UDim2.new(1 / math.max(#ids, 3), -5, 1, 0), TextSize = 11, BackgroundColor3 = sel and PURPLE or C.card, TextColor3 = sel and C.white or C.text }, function()
				selected = id
				Phone.refresh()
			end))
		end
	end
	if def.pedal then
		noT(UI.label(content, L("A bicycle has no plate or wiring: only the bell can change.", "จักรยานไม่มีป้ายทะเบียนและไฟ เปลี่ยนได้แค่กระดิ่ง"), 12, C.sub, F.med, { Size = UDim2.new(1, 0, 0, 30), TextWrapped = true }))
	end

	if not def.pedal then
		-- underglow
		ui.section(L("UNDERGLOW · ", "ไฟใต้ท้อง · ") .. Util.money(Vehicles.STYLE_PRICES.glow))
		local grid = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, math.ceil((#Vehicles.GLOWS + 1) / 5) * 48), Parent = content })
		local g = Instance.new("UIGridLayout")
		g.CellSize = UDim2.new(0.2, -6, 0, 42)
		g.CellPadding = UDim2.fromOffset(6, 6)
		g.Parent = grid
		for i = 0, #Vehicles.GLOWS do
			local gl = Vehicles.GLOWS[i]
			local on = (st.glow or 0) == i
			local locked = gl ~= nil and not hasNeed(gl.need)
			local b = noT(UI.button(grid, gl and (gl.need and (locked and "🔒" or (gl.rainbow and "🌈" or "⭐")) or "") or L("None", "ไม่มี"),
				{ TextSize = 16, BackgroundColor3 = gl and gl.color or C.card, TextColor3 = C.black }, function()
					if locked then unlockHint(gl.need) else fit("glow", i) end
				end))
			if gl and gl.rainbow then
				local grad = Instance.new("UIGradient")
				grad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)), ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 220, 60)),
					ColorSequenceKeypoint.new(0.66, Color3.fromRGB(60, 200, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 80, 255)) })
				grad.Parent = b
			end
			if on then UI.stroke(b, C.text, 3) end
			if on and gl then noT(UI.label(b, "✓", 20, C.black, F.black, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })) end
		end
		noT(UI.label(content, L("⭐ VIP pass · 🌈 Neon Pro pass · 🔒 others come from the Season Pass", "⭐ พาส VIP · 🌈 พาสนีออนโปร · 🔒 สีอื่นได้จาก Season Pass"), 11, C.sub, F.med,
			{ Size = UDim2.new(1, 0, 0, 16) }))

		-- plate
		ui.section(L("NUMBER PLATE · ", "ป้ายทะเบียน · ") .. Util.money(Vehicles.STYLE_PRICES.plate))
		local card = ui.bigCard(96)
		noT(UI.label(card, L("Now: ", "ตอนนี้: ") .. ((st.plate and st.plate ~= "") and st.plate or (Vehicles.defaultPlate(game.Players.LocalPlayer.UserId) .. L(" (standard)", " (ป้ายปกติ)"))), 13, C.text, F.bold,
			{ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18) }))
		local box = Instance.new("TextBox")
		box.PlaceholderText = L("e.g. ซิ่ง 99", "เช่น ซิ่ง 99")
		box.Text = plateDraft
		box.ClearTextOnFocus = false
		box.Font = F.bold
		box.TextSize = 16
		box.TextColor3 = C.text
		box.BackgroundColor3 = C.bg
		box.Position = UDim2.fromOffset(12, 32)
		box.Size = UDim2.new(1, -110, 0, 36)
		box.Parent = card
		box:SetAttribute("NoTranslate", true)
		UI.corner(box, 10)
		box:GetPropertyChangedSignal("Text"):Connect(function()
			plateDraft = box.Text
			if utf8.len(plateDraft) and utf8.len(plateDraft) > Vehicles.PLATE_MAX then
				local cut = utf8.offset(plateDraft, Vehicles.PLATE_MAX + 1)
				if cut then box.Text = plateDraft:sub(1, cut - 1) end
			end
		end)
		noT(UI.button(card, L("Fit", "ติดป้าย"), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 32), Size = UDim2.fromOffset(86, 36), TextSize = 14, BackgroundColor3 = PURPLE }, function()
			if plateDraft ~= "" then fit("plate", plateDraft) end
		end))
		noT(UI.label(card, L(("Up to %d characters: Thai letters, A-Z, numbers. Everyone can see it, so it is checked."):format(Vehicles.PLATE_MAX),
			("ไม่เกิน %d ตัว: ตัวอักษรไทย A-Z ตัวเลข ทุกคนเห็นได้ จึงมีการตรวจคำ"):format(Vehicles.PLATE_MAX)), 11, C.sub, F.med,
			{ Position = UDim2.fromOffset(12, 72), Size = UDim2.new(1, -24, 0, 18), TextWrapped = true }))
		if st.plate and st.plate ~= "" then
			ui.row("↩", L("Back to the standard plate", "กลับไปใช้ป้ายปกติ"), nil, L("Free", "ฟรี"), function() fit("plate", "") end, { btnWidth = 60 })
		end

		-- sticker
		ui.section(L("STICKER · ", "สติกเกอร์ · ") .. Util.money(Vehicles.STYLE_PRICES.sticker))
		for i = 0, #Vehicles.STICKERS do
			local s = Vehicles.STICKERS[i]
			local on = (st.sticker or 0) == i
			local locked = s ~= nil and not hasNeed(s.need)
			local r = ui.row(s and s.icon or "🚫", s and (s.text .. (s.need and L("  · season", "  · ซีซัน") or "")) or L("No sticker", "ไม่ติดสติกเกอร์"), nil,
				on and "✓" or (locked and "🔒" or L("Fit", "ติด")), function()
					if locked then unlockHint(s.need) elseif not on then fit("sticker", i) end
				end, { btnWidth = 54, height = 42, btnColor = on and C.green or (locked and C.dark or PURPLE) })
			for _, x in ipairs(r:GetDescendants()) do if x:IsA("TextLabel") then x:SetAttribute("NoTranslate", true) end end
		end
	end

	-- exhaust (not on a bicycle)
	if not def.pedal then
		ui.section(L("EXHAUST · ", "ท่อไอเสีย · ") .. Util.money(Vehicles.STYLE_PRICES.exhaust))
		for i, e in ipairs(Vehicles.EXHAUSTS) do
			local on = (st.exhaust or 1) == i
			local r = ui.row(i == 2 and "🔥" or (i == 3 and "🤫" or "🔩"), Lang.code == "th" and e.thai or e.name,
				i == 2 and L("Louder, deeper, rougher", "ดังขึ้น ทุ้มขึ้น ซิ่งขึ้น") or (i == 3 and L("Quieter for the neighbours", "เงียบ ไม่กวนเพื่อนบ้าน") or nil),
				on and "✓" or L("Fit", "ใส่"), function() if not on then fit("exhaust", i) end end, { btnWidth = 54, height = 46, btnColor = on and C.green or PURPLE })
			for _, x in ipairs(r:GetDescendants()) do if x:IsA("TextLabel") then x:SetAttribute("NoTranslate", true) end end
		end
		noT(UI.label(content, L("A new exhaust is heard the next time you get on.", "ท่อใหม่จะได้ยินตอนขึ้นรถครั้งถัดไป"), 11, C.sub, F.med, { Size = UDim2.new(1, 0, 0, 16) }))
	end

	-- horn
	ui.section(L("HORN · ", "แตร · ") .. Util.money(Vehicles.STYLE_PRICES.horn))
	for i, h in ipairs(Vehicles.HORNS) do
		local on = (st.horn or 1) == i
		local r = ui.row("📯", Lang.code == "th" and h.thai or h.name, nil, on and "✓" or L("Fit", "ใส่"), function() if not on then fit("horn", i) end end,
			{ btnWidth = 54, height = 42, btnColor = on and C.green or PURPLE })
		noT(UI.button(r, "▶", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -72, 0.5, 0), Size = UDim2.fromOffset(34, 28), TextSize = 13, BackgroundColor3 = C.dark }, function() preview(i) end))
		for _, x in ipairs(r:GetDescendants()) do if x:IsA("TextLabel") then x:SetAttribute("NoTranslate", true) end end
	end
end

function Styling.start()
	Phone.addApp({ id = "styling", name = "Styling", icon = "🔧", color = PURPLE }, screen)
end

return Styling
