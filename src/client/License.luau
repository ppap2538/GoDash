-- The driving test on this screen (server/LicenseService): the queue at the transport office
-- ("queue no. 999 · now serving 012" ... three hours later), the checklist while you ride the course,
-- the examiner's verdict and, when you pass, your new licence card.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)

local License = {}
local L = Lang.pick
local player = Players.LocalPlayer
local gui: ScreenGui
local panel, steps, timerLabel
local started = 0

local function new(class: string, props): any
	local i = Instance.new(class)
	for k, v in pairs(props) do (i :: any)[k] = v end
	return i
end
local function corner(i: Instance, r: number) new("UICorner", { CornerRadius = UDim.new(0, r), Parent = i }) end
local function label(parent: Instance, text: string, size: number, color: Color3, font: Enum.Font, props: any?): TextLabel
	local t = new("TextLabel", { BackgroundTransparency = 1, Text = text, TextSize = size, TextColor3 = color, Font = font, TextWrapped = true, Parent = parent })
	for k, v in pairs(props or {}) do (t :: any)[k] = v end
	t:SetAttribute("NoTranslate", true)
	return t
end

local function queueScene()
	local dim = new("Frame", { BackgroundColor3 = Color3.fromRGB(10, 14, 22), BackgroundTransparency = 0.15, Size = UDim2.fromScale(1, 1), Parent = gui })
	local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(300, 300), BackgroundColor3 = Color3.fromRGB(250, 248, 240), Parent = dim })
	corner(card, 16)
	label(card, L("Transport Office (pretend)", "สำนักงานขนส่ง (สมมติ)"), 16, Color3.fromRGB(40, 60, 120), Enum.Font.GothamBold, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 10) })
	label(card, L("QUEUE TICKET", "บัตรคิว"), 14, Color3.fromRGB(120, 120, 128), Enum.Font.GothamMedium, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 52) })
	label(card, "999", 96, Color3.fromRGB(200, 30, 40), Enum.Font.GothamBlack, { Size = UDim2.new(1, 0, 0, 110), Position = UDim2.fromOffset(0, 70) })
	local serving = label(card, L("Now serving: 012", "กำลังให้บริการคิวที่: 012"), 15, Color3.fromRGB(40, 40, 46), Enum.Font.GothamBold, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 190) })
	local wait = label(card, "", 22, Color3.fromRGB(40, 40, 46), Enum.Font.GothamBlack, { Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 226) })
	Feedback.notify()
	task.wait(1.3)
	local clocks = { "🕘", "🕙", "🕚", "🕛" }
	for i = 1, 12 do
		serving.Text = L("Now serving: ", "กำลังให้บริการคิวที่: ") .. string.format("%03d", 12 + i * 80)
		wait.Text = clocks[(i - 1) % #clocks + 1] .. "  " .. L("3 hours later...", "3 ชั่วโมงต่อมา...")
		task.wait(0.2)
	end
	serving.Text = L("Now serving: 999 → Course 1", "กำลังให้บริการคิวที่: 999 → สนาม 1")
	Feedback.play("tick", 0.6, 2.2, 0)
	task.wait(0.6)
	TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(card, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	for _, d in ipairs(card:GetDescendants()) do
		if d:IsA("TextLabel") then TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play() end
	end
	task.delay(0.35, function() dim:Destroy() end)
end

local function showPanel(class: string)
	if panel then panel:Destroy() end
	started = os.clock()
	panel = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(330, 150), BackgroundColor3 = Color3.fromRGB(250, 248, 240), Parent = gui })
	corner(panel, 14)
	new("UIStroke", { Color = Color3.fromRGB(40, 110, 190), Thickness = 3, Parent = panel })
	label(panel, class == "car" and L("📇 Driving test: car", "📇 สอบใบขับขี่: รถยนต์") or L("📇 Driving test: motorbike", "📇 สอบใบขับขี่: รถจักรยานยนต์"), 16, Color3.fromRGB(30, 50, 110), Enum.Font.GothamBlack,
		{ Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 6) })
	timerLabel = label(panel, "", 13, Color3.fromRGB(120, 120, 128), Enum.Font.GothamBold, { Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 32) })
	local list = class == "car" and { L("① Slalom: alternate sides, touch no cone", "① ซิกแซก สลับข้าง ห้ามชนกรวย"), L("② Stop inside the box", "② จอดในกรอบ") }
		or { L("① Narrow plank: no wheel on the ground", "① ทางแคบ ล้อห้ามแตะพื้น"), L("② Slalom: alternate sides, touch no cone", "② ซิกแซก สลับข้าง ห้ามชนกรวย"), L("③ Stop inside the box", "③ จอดในกรอบ") }
	steps = {}
	for i, s in ipairs(list) do
		table.insert(steps, label(panel, "⬜ " .. s, 14, Color3.fromRGB(40, 40, 46), Enum.Font.GothamMedium,
			{ Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 52 + (i - 1) * 26), TextXAlignment = Enum.TextXAlignment.Left }))
	end
	task.spawn(function()
		local me = panel
		while panel == me and me.Parent do
			timerLabel.Text = L("Time: ", "เวลา: ") .. math.floor(os.clock() - started) .. L(" s (limit 150)", " วิ (จำกัด 150)")
			task.wait(0.5)
		end
	end)
end

local function verdict(passed: boolean, whyText: string?, class: string?)
	if panel then panel:Destroy(); panel = nil end
	local LINES = {
		L("A wheel touched the line just a little... that's a fail, kid", "ล้อแตะเส้นนิดเดียวก็ตกนะน้อง"),
		L("Go and practise, come back next time. Next queue please!", "ไปซ้อมมาใหม่นะ คิวต่อไปค่ะ!"),
		L("Everybody fails the plank the first time. (Not everybody.)", "ทางแคบใครๆ ก็ตกครั้งแรก (ไม่ใช่ทุกคน)"),
	}
	if not passed then
		local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(360, 110), BackgroundColor3 = Color3.fromRGB(160, 24, 30), Parent = gui })
		corner(card, 14)
		label(card, L("❌ Test failed", "❌ สอบไม่ผ่าน"), 20, Color3.new(1, 1, 1), Enum.Font.GothamBlack, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 8) })
		label(card, whyText or "", 14, Color3.new(1, 1, 1), Enum.Font.GothamBold, { Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 40) })
		label(card, "👮 " .. LINES[math.random(1, #LINES)], 13, Color3.fromRGB(255, 220, 220), Enum.Font.GothamMedium, { Size = UDim2.new(1, -20, 0, 36), Position = UDim2.fromOffset(10, 64) })
		Feedback.bad()
		task.delay(5, function() card:Destroy() end)
		return
	end
	-- the licence card
	local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(420, 250), BackgroundColor3 = Color3.fromRGB(232, 240, 250), Parent = gui })
	corner(card, 16)
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(220, 235, 252), Color3.fromRGB(250, 236, 220)), Rotation = 30, Parent = card })
	new("UIStroke", { Color = Color3.fromRGB(40, 90, 160), Thickness = 2, Parent = card })
	local cls = class == "car"
	label(card, L("TEMPORARY DRIVING LICENCE", "ใบอนุญาตขับขี่ชั่วคราว"), 18, Color3.fromRGB(30, 50, 110), Enum.Font.GothamBlack, { Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 10) })
	label(card, cls and L("Private car", "รถยนต์ส่วนบุคคล") or L("Private motorcycle", "รถจักรยานยนต์ส่วนบุคคล"), 14, Color3.fromRGB(60, 70, 100), Enum.Font.GothamBold, { Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 38) })
	local photo = new("ImageLabel", { Position = UDim2.fromOffset(18, 70), Size = UDim2.fromOffset(110, 130), BackgroundColor3 = Color3.fromRGB(200, 210, 225), Parent = card })
	corner(photo, 8)
	task.spawn(function()
		local ok, img = pcall(function() return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150) end)
		if ok and photo.Parent then photo.Image = img end
	end)
	local function row(y: number, k: string, v: string)
		label(card, k, 11, Color3.fromRGB(110, 116, 130), Enum.Font.GothamMedium, { Size = UDim2.fromOffset(260, 14), Position = UDim2.fromOffset(144, y), TextXAlignment = Enum.TextXAlignment.Left })
		label(card, v, 15, Color3.fromRGB(30, 30, 40), Enum.Font.GothamBold, { Size = UDim2.fromOffset(260, 20), Position = UDim2.fromOffset(144, y + 14), TextXAlignment = Enum.TextXAlignment.Left })
	end
	row(70, L("Name", "ชื่อ"), player.DisplayName)
	row(108, L("Licence no.", "เลขที่"), ("64-%05d"):format(player.UserId % 100000))
	row(146, L("Valid until", "ใช้ได้ถึง"), L("forever (in this game)", "ตลอดไป (ในเกมนี้)"))
	label(card, L("Issued by the Khon Kaen Transport Office (pretend)", "ออกให้ ณ สำนักงานขนส่งขอนแก่น (สมมติ)"), 11, Color3.fromRGB(110, 116, 130), Enum.Font.GothamMedium, { Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 222) })
	local sc = new("UIScale", { Scale = 0.3, Parent = card })
	TweenService:Create(sc, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Feedback.fanfare()
	task.delay(6.5, function() card:Destroy() end)
end

function License.start()
	gui = new("ScreenGui", { Name = "GoDashLicence", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 70, Parent = player:WaitForChild("PlayerGui") })
	Net.listen("Notify", function(kind, p)
		if kind ~= "licence" or type(p) ~= "table" then return end
		if p.stage == "queue" then
			task.spawn(queueScene)
		elseif p.stage == "start" then
			showPanel(p.class)
			Feedback.toast(L("📇 The test begins: follow the course", "📇 เริ่มสอบ! ขี่ตามสนามไปเลย"), "good")
		elseif p.stage == "step" and steps and steps[p.n] then
			steps[p.n].Text = steps[p.n].Text:gsub("^⬜", "✅")
			steps[p.n].TextColor3 = Color3.fromRGB(30, 140, 70)
			Feedback.good()
		elseif p.stage == "fail" then
			local why = type(p.why) == "table" and (Lang.code == "th" and p.why.th or p.why.en) or nil
			verdict(false, why)
		elseif p.stage == "pass" then
			verdict(true, nil, p.class)
		end
	end)
end

return License
