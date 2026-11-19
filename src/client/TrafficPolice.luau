-- Player traffic police, the client side (2026-11-19, viral pack; server/TrafficPoliceService).
--   * phone app 🚔: sign on / off duty, how it works
--   * over every rider who is wanted: a pulsing 🚨; over every officer on duty: a flashing red-and-blue light and
--     "🚔 Traffic police" (player attributes Wanted / WantedUntil / PoliceDuty)
--   * an officer's card (top of the screen): the nearest wanted rider, what they did, how far, the time left, and
--     the "🚔 Pull over" button (or T) once close enough
--   * a wanted rider's card: "🚨 The traffic police are after you! 0:42"
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local UI = require(script.Parent.UI.Kit)
local Layers = require(script.Parent.UI.Core.Layers)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Phone = require(script.Parent.Phone)
local Feedback = require(script.Parent.Feedback)
local Net = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Net)

local TP = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local BLUE = Color3.fromRGB(30, 70, 170)
local STOP_RANGE = 16
local WHAT = {
	redlight = { "ran a red light", "ฝ่าไฟแดง" },
	zebra = { "skipped a zebra crossing", "ไม่หยุดที่ทางม้าลาย" },
	sidewalk = { "rode on the pavement", "ขี่บนทางเท้า" },
}

local function noT(l) l:SetAttribute("NoTranslate", true) return l end

local function screen()
	local ui = Phone.ui
	local on = player:GetAttribute("PoliceDuty") == true
	local hero = ui.bigCard(118, BLUE)
	noT(UI.label(hero, L("🚔 Traffic police", "🚔 ตำรวจจราจร"), 18, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) }))
	noT(UI.label(hero, L("Catch riders who run a red light, skip a zebra crossing or ride on the pavement near you. Ride up close and pull them over: they pay the fine, you get ฿100.",
		"จับคนที่ฝ่าไฟแดง ไม่หยุดที่ทางม้าลาย หรือขี่บนทางเท้าใกล้ๆ คุณ ขี่เข้าไปใกล้แล้วกดเรียกจอด: เขาจ่ายค่าปรับ คุณได้ ฿100"), 12, Color3.fromRGB(220, 230, 255), F.med,
		{ Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 72), TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top }))
	ui.section(L("DUTY", "เข้าเวร"))
	ui.row(on and "🟢" or "⚪", on and L("On duty", "กำลังเข้าเวร") or L("Off duty", "ยังไม่เข้าเวร"),
		L("No delivery orders while you are on duty", "ระหว่างเข้าเวรจะไม่มีงานส่งของเข้ามา"),
		on and L("Sign off", "ออกเวร") or L("Sign on", "เข้าเวร"), function()
			task.spawn(function()
				ui.call("City", "police_duty", "")
				task.wait(0.3)
				Phone.refresh()
			end)
		end, { btnWidth = 84, btnColor = on and Color3.fromRGB(190, 60, 50) or BLUE })
	ui.section(L("HOW IT WORKS", "วิธีเล่น"))
	for _, r in ipairs({
		{ "🚨", L("Only real offences: nobody can be ticketed for nothing.", "จับได้เฉพาะคนที่ทำผิดจริง ใส่ร้ายใครไม่ได้") },
		{ "⏱", L("A wanted rider has one minute. Catch them, or they get away.", "คนที่ถูกตามมีเวลา 1 นาที จับให้ทัน ไม่งั้นเขาหนีรอด") },
		{ "🚔", L("Within a few metres: press 🚔 Pull over (or U).", "เข้าใกล้ไม่กี่เมตร แล้วกด 🚔 เรียกจอด (หรือ U)") },
		{ "💰", L("฿100 for each catch that is fined, up to 10 a day.", "ได้ ฿100 ต่อคนที่โดนปรับจริง วันละไม่เกิน 10 ครั้ง") },
	}) do
		local row = ui.row(r[1], r[2], nil, nil, nil, { height = 44 })
		for _, x in ipairs(row:GetDescendants()) do if x:IsA("TextLabel") then x:SetAttribute("NoTranslate", true) end end
	end
end

---------------------------------------------------------------------------------------------------
-- markers over riders
---------------------------------------------------------------------------------------------------
local markers = {} :: { [Player]: any }
local holder: Instance

local function marker(p: Player, kind: string?)
	local m = markers[p]
	local head = p.Character and p.Character:FindFirstChild("Head") :: BasePart?
	if m and (m.kind ~= kind or not head or m.gui.Adornee ~= head) then
		m.gui:Destroy()
		markers[p] = nil
		m = nil
	end
	if not kind or not head or m then return m end
	local g = Instance.new("BillboardGui")
	g.Name = "Cop_" .. p.UserId
	g.Adornee = head
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.MaxDistance = 320
	g.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	g:SetAttribute("NoTranslate", true)
	local entry = { gui = g, kind = kind }
	if kind == "wanted" then
		g.Size = UDim2.fromOffset(70, 46)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.Text = "🚨"
		t.Parent = g
		entry.label = t
	else
		g.Size = UDim2.fromOffset(150, 46)
		local bar = Instance.new("Frame")
		bar.BackgroundTransparency = 1
		bar.Size = UDim2.new(0, 60, 0, 12)
		bar.AnchorPoint = Vector2.new(0.5, 0)
		bar.Position = UDim2.fromScale(0.5, 0)
		bar.Parent = g
		local a = Instance.new("Frame")
		a.BorderSizePixel = 0
		a.Size = UDim2.fromScale(0.5, 1)
		a.BackgroundColor3 = Color3.fromRGB(240, 40, 40)
		a.Parent = bar
		local b = a:Clone()
		b.Position = UDim2.fromScale(0.5, 0)
		b.BackgroundColor3 = Color3.fromRGB(40, 90, 255)
		b.Parent = bar
		UI.corner(a, 4); UI.corner(b, 4)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(0, 14)
		t.Size = UDim2.new(1, 0, 0, 28)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.3
		t.Text = L("🚔 Traffic police", "🚔 ตำรวจจราจร")
		t.Parent = g
		entry.a, entry.b = a, b
	end
	g.Parent = holder
	markers[p] = entry
	return entry
end

---------------------------------------------------------------------------------------------------
-- the cards
---------------------------------------------------------------------------------------------------
local gui: ScreenGui
local card: Frame
local line1: TextLabel
local line2: TextLabel
local stopBtn: TextButton
local target: Player? = nil

local function buildCards()
	gui = UI.screen("GoDashCop", Layers.Interaction + 2)
	card = UI.panel(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.fromOffset(340, 74), Visible = false })
	line1 = noT(UI.label(card, "", 15, C.white, F.black, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 22) }))
	line2 = noT(UI.label(card, "", 12, Color3.fromRGB(220, 226, 236), F.med, { Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -130, 0, 34), TextWrapped = true }))
	stopBtn = UI.button(card, L("🚔 Pull over", "🚔 เรียกจอด"), { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10), Size = UDim2.fromOffset(110, 34), TextSize = 14, BackgroundColor3 = BLUE }, function()
		TP.pullOver()
	end)
	noT(stopBtn)
end

function TP.pullOver()
	if not target or player:GetAttribute("PoliceDuty") ~= true then return end
	local tid = target.UserId
	task.spawn(function()
		local ok, msg = Net.call("City", "police_stop", tostring(tid))
		if msg and msg ~= "" then Feedback.toast(Lang.t(msg), ok and "good" or "bad") end
	end)
end

local function root(p: Player): Vector3?
	local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return r and r.Position or nil
end

local function update()
	local now = Workspace:GetServerTimeNow()
	local me = root(player)
	local cop = player:GetAttribute("PoliceDuty") == true
	local best, bd
	for _, p in ipairs(Players:GetPlayers()) do
		local w = p:GetAttribute("Wanted")
		local m = marker(p, (type(w) == "string" and "wanted") or (p:GetAttribute("PoliceDuty") and "cop") or nil)
		if m and m.kind == "wanted" and m.label then
			m.label.TextTransparency = (os.clock() % 0.6) < 0.35 and 0 or 0.5
		elseif m and m.kind == "cop" and m.a then
			local on = (os.clock() % 0.5) < 0.25
			m.a.BackgroundTransparency = on and 0 or 0.7
			m.b.BackgroundTransparency = on and 0.7 or 0
		end
		if cop and p ~= player and type(w) == "string" and me then
			local pr = root(p)
			if pr then
				local d = (pr - me).Magnitude
				if d < 600 and (not bd or d < bd) then best, bd = p, d end
			end
		end
	end
	for p in pairs(markers) do
		if not p.Parent then markers[p].gui:Destroy(); markers[p] = nil end
	end
	target = best
	local myWanted = player:GetAttribute("Wanted")
	if cop and best then
		local w = WHAT[best:GetAttribute("Wanted")] or { "broke a rule", "ทำผิดกฎ" }
		local left = math.max(0, math.floor((best:GetAttribute("WantedUntil") or now) - now))
		line1.Text = ("🚨 %s · %s"):format(best.DisplayName, L(w[1], w[2]))
		line2.Text = L(("%d m away · %d s left"):format(math.floor(bd / 3.57), left), ("ห่าง %d ม. · เหลือ %d วิ"):format(math.floor(bd / 3.57), left))
		stopBtn.Visible = true
		stopBtn.BackgroundColor3 = bd <= STOP_RANGE and BLUE or C.dark
		stopBtn.Text = bd <= STOP_RANGE and L("🚔 Pull over (U)", "🚔 เรียกจอด (U)") or L("Get closer", "เข้าใกล้อีก")
		card.Visible = true
	elseif type(myWanted) == "string" then
		local left = math.max(0, math.floor((player:GetAttribute("WantedUntil") or now) - now))
		line1.Text = L("🚨 The traffic police are after you!", "🚨 ตำรวจจราจรกำลังตามคุณ!")
		line2.Text = L(("Get away for %d s more, or get pulled over"):format(left), ("หนีให้พ้นอีก %d วิ ไม่งั้นโดนเรียกจอด"):format(left))
		stopBtn.Visible = false
		card.Visible = true
	elseif cop then
		line1.Text = L("🚔 On duty", "🚔 กำลังเข้าเวร")
		line2.Text = L("Waiting for someone to break the rules near you...", "รอจับคนทำผิดกฎใกล้ๆ คุณ...")
		stopBtn.Visible = false
		card.Visible = true
	else
		card.Visible = false
	end
end

function TP.start()
	-- (the billboards go straight into PlayerGui: a Folder in between is not a safe place for a LayerCollector)
	holder = player:WaitForChild("PlayerGui") :: any
	buildCards()
	Phone.addApp({ id = "trafficcop", name = "Traffic Police", icon = "🚔", color = BLUE }, screen)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		-- (U: T talks to people on the street, V / Y / K are taken)
		if input.KeyCode == Enum.KeyCode.U and target and player:GetAttribute("PoliceDuty") then TP.pullOver() end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then return end
		acc = 0
		update()
	end)
end

return TP
