-- Game feel: toasts, reward cards, level-up banners, speech bubbles, UI sounds, camera kicks.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local Sounds = require(Shared.Config.Sounds)
local TextService = game:GetService("TextService")
local UI = require(script.Parent.UI.Kit)
local Layout = require(script.Parent.UI.Core.Layout)
local Layers = require(script.Parent.UI.Core.Layers)
local UIState = require(script.Parent.UI.Core.UIState)
local State = require(script.Parent.State)

local Feedback = {}
Feedback.top = nil :: Frame?
local gui, toastStack, modalCenter
local rewardToken = 0
local C, F = UI.C, UI.F
local lastPlay = {}

---------------------------------------------------------------------------------------------------
-- sound
---------------------------------------------------------------------------------------------------
local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = "GoDashSfx"
sfxGroup.Parent = SoundService
Feedback.sfxGroup = sfxGroup

local function sfxOn(): boolean
	return not (State.data and State.data.settings and State.data.settings.sfx == false)
end

-- One-shot. gap = minimum seconds between two plays of the same name (no machine-gun sounds).
function Feedback.play(name: string, volume: number?, speed: number?, gap: number?)
	local sid = Sounds[name]
	if not sid or sid == "" or not sfxOn() then return end
	local now = os.clock()
	local key = name .. (speed or 1)
	if lastPlay[key] and now - lastPlay[key] < (gap or 0.06) then return end
	lastPlay[key] = now
	local s = Instance.new("Sound")
	s.SoundId = sid
	s.Volume = volume or 0.5
	s.PlaybackSpeed = speed or 1
	s.SoundGroup = sfxGroup
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
	task.delay(6, function() if s.Parent then s:Destroy() end end)
end

-- Little melodies from the engine's tick sound: no external audio needed.
local function chime(notes: { number }, step: number, volume: number?)
	for i, n in ipairs(notes) do
		task.delay((i - 1) * step, function() Feedback.play("tick", volume or 0.7, n, 0) end)
	end
end
function Feedback.click() Feedback.play("tick", 0.35, 1.5, 0.04) end
function Feedback.good() chime({ 1.6, 2.0, 2.4 }, 0.08) end
function Feedback.bad() chime({ 0.9, 0.7 }, 0.1, 0.5) end
function Feedback.notify() chime({ 2.0, 2.6, 2.0, 2.6 }, 0.11, 0.8) end
function Feedback.coins() chime({ 2.2, 2.5, 2.8, 3.1, 3.4 }, 0.06, 0.6) end
function Feedback.fanfare() chime({ 1.5, 1.9, 2.25, 3.0, 2.25, 3.0 }, 0.12, 0.8) end

---------------------------------------------------------------------------------------------------
-- camera
---------------------------------------------------------------------------------------------------
function Feedback.fovKick(amount: number, time: number?)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local base = cam.FieldOfView
	UI.tween(cam, 0.12, { FieldOfView = base + amount })
	task.delay(0.12, function() UI.tween(cam, time or 0.5, { FieldOfView = 70 }) end)
end

---------------------------------------------------------------------------------------------------
-- toasts
---------------------------------------------------------------------------------------------------
function Feedback.toast(text: string, kind: string?)
	if not toastStack or text == "" then return end
	local col = kind == "bad" and C.red or (kind == "good" and C.green or C.textDim)
	-- Toasts live in the top-centre strip between the status column and the navigation cluster and
	-- wrap instead of growing past it. (AbsoluteSize is read once per toast, never per frame.)
	local stripW = toastStack.AbsoluteSize.X / math.max(Layout.scale, 0.01)
	local maxW = math.clamp(stripW > 1 and stripW or 420, 200, 560)
	local textMax = maxW - 46
	local ok, size = pcall(function() return TextService:GetTextSize(text, 14, F.med, Vector2.new(textMax, 400)) end)
	local tw = (ok and size) and math.min(size.X + 6, textMax) or textMax
	local th = (ok and size) and size.Y or 18
	local t = UI.panel(toastStack, { Name = "Toast", Size = UDim2.fromOffset(tw + 46, math.max(36, th + 18)), BackgroundTransparency = 0.08 }, 18)
	local dot = UI.new("Frame", { BackgroundColor3 = col, AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0, 14, 0.5, 0), Parent = t })
	UI.corner(dot, 4)
	UI.label(t, text, 14, C.white, F.med, { Size = UDim2.new(0, tw, 1, 0), Position = UDim2.fromOffset(32, 0), TextTruncate = Enum.TextTruncate.None, TextWrapped = true })
	local sc = Instance.new("UIScale"); sc.Scale = 0.6; sc.Parent = t
	UI.tween(sc, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	if kind == "bad" then Feedback.bad() elseif kind == "good" then Feedback.play("tick", 0.4, 2.2) end
	task.delay(3.4, function()
		UI.tween(t, 0.25, { BackgroundTransparency = 1 })
		for _, d in ipairs(t:GetDescendants()) do
			if d:IsA("TextLabel") then UI.tween(d, 0.25, { TextTransparency = 1 })
			elseif d:IsA("Frame") then UI.tween(d, 0.25, { BackgroundTransparency = 1 })
			elseif d:IsA("UIStroke") then UI.tween(d, 0.25, { Transparency = 1 }) end
		end
		task.wait(0.3)
		t:Destroy()
	end)
	-- never more than four on screen
	local n = 0
	for _, c in ipairs(toastStack:GetChildren()) do
		if c.Name == "Toast" then n += 1 end
	end
	if n > 4 then
		for _, c in ipairs(toastStack:GetChildren()) do
			if c.Name == "Toast" then c:Destroy() break end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- reward card
---------------------------------------------------------------------------------------------------
local function stars(parent: Instance, value: number)
	local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = parent })
	UI.list(row, 4, true, Enum.HorizontalAlignment.Center)
	for i = 1, 5 do
		local lit = value >= i - 0.25
		local half = not lit and value >= i - 0.75
		local s = UI.label(row, "★", 30, lit and C.yellow or (half and Color3.fromRGB(230, 200, 120) or C.line), F.black, { Size = UDim2.fromOffset(30, 34), TextXAlignment = Enum.TextXAlignment.Center })
		local sc = Instance.new("UIScale"); sc.Scale = 0; sc.Parent = s
		task.delay(0.15 + i * 0.09, function()
			UI.tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			if lit then Feedback.play("tick", 0.5, 1.6 + i * 0.25, 0) end
		end)
	end
end

function Feedback.reward(r)
	if not gui then return end
	if r.small then
		local parts = {}
		if r.money then table.insert(parts, "+" .. Util.money(r.money)) end
		if r.item then table.insert(parts, "+" .. (r.qty or 1) .. " " .. r.item) end
		if r.exp then table.insert(parts, "+" .. r.exp .. " EXP") end
		Feedback.toast((r.harvest and "🌾 " or "💰 ") .. r.title .. "  " .. table.concat(parts, "  "), "good")
		Feedback.coins()
		return
	end
	local old = modalCenter:FindFirstChild("Reward")
	if old then old:Destroy() end
	-- modal layer: above everything; UIState hides the interaction prompts while it is up
	rewardToken += 1
	local token = rewardToken
	UIState.set("modal", true)
	local card = UI.new("Frame", { Name = "Reward", BackgroundColor3 = C.card, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(330, 100), AutomaticSize = Enum.AutomaticSize.Y, Parent = modalCenter })
	UI.corner(card, 22)
	UI.stroke(card, C.green, 3)
	UI.pad(card, 20, 18, 20, 18)
	UI.list(card, 8, false, Enum.HorizontalAlignment.Center)
	UI.label(card, r.title or "Reward", 22, C.text, F.black, { TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 28) })
	if r.stars then stars(card, r.stars) end
	local function line(left: string, right: string, color: Color3?)
		local row = UI.new("Frame", { BackgroundColor3 = C.bg, Size = UDim2.new(1, 0, 0, 36), Parent = card })
		UI.corner(row, 10)
		UI.label(row, left, 15, C.sub, F.med, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.6, 0, 1, 0) })
		UI.label(row, right, 17, color or C.text, F.bold, { Position = UDim2.new(0.4, 0, 0, 0), Size = UDim2.new(0.6, -12, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	end
	if r.money then line(r.job and "Fare" or "Money", "+" .. Util.money(r.money), C.greenDark) end
	if r.tip and r.tip > 0 then line("Tip", "+" .. Util.money(r.tip), C.orange) end
	if r.exp then line("Experience", "+" .. r.exp .. " EXP", C.blue) end
	if r.item then line("Item", (r.qty or 1) .. " × " .. r.item, C.purple) end
	if r.detail then
		local d = r.detail
		local function pct(v: number): string return math.floor(v * 100 + 0.5) .. "%" end
		UI.label(card, ("⏱ %s   🛣 Smooth %s   🛡 Safe %s"):format(Util.duration(d.seconds), pct(d.smooth), pct(d.safety)), 13, C.sub, F.med,
			{ TextXAlignment = Enum.TextXAlignment.Center })
	end
	for _, n in ipairs(r.notes or {}) do
		UI.label(card, n, 13, C.red, F.med, { TextXAlignment = Enum.TextXAlignment.Center })
	end
	local sc = Instance.new("UIScale"); sc.Scale = 0.5; sc.Parent = card
	UI.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	Feedback.coins()
	Feedback.fovKick(-6, 0.6)
	local closed = false
	local function close()
		if closed then return end
		closed = true
		UI.tween(sc, 0.18, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.2, function()
			card:Destroy()
			if rewardToken == token then UIState.set("modal", false) end
		end)
	end
	-- click / tap the card to close it (a full-size button inside the auto-sized list would make
	-- the card grow without end)
	card.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then close() end
	end)
	task.delay(5.5, close)
end

function Feedback.banner(title: string, text: string, icon: string?, color: Color3?)
	if not gui then return end
	-- banners share the top-centre stack with the toasts (first in line), so the two never overlap
	-- and never grow past the strip (text shrinks to fit)
	local stripW = toastStack.AbsoluteSize.X / math.max(Layout.scale, 0.01)
	local width = math.clamp(stripW > 1 and stripW or 360, 220, 360)
	local b = UI.new("Frame", { Name = "Banner", BackgroundColor3 = color or C.green, LayoutOrder = -1, Size = UDim2.fromOffset(width, 74), Parent = toastStack })
	UI.corner(b, 20)
	local bsc = Instance.new("UIScale"); bsc.Scale = 0.5; bsc.Parent = b
	UI.label(b, icon or "⭐", 36, C.white, F.bold, { Size = UDim2.fromOffset(60, 74), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Center })
	UI.fitText(UI.label(b, title, 21, C.white, F.black, { Position = UDim2.fromOffset(72, 12), Size = UDim2.new(1, -84, 0, 26) }), 21, 12)
	UI.fitText(UI.label(b, text, 15, C.white, F.med, { Position = UDim2.fromOffset(72, 40), Size = UDim2.new(1, -84, 0, 22) }), 15, 10)
	UI.tween(bsc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	Feedback.fanfare()
	Feedback.fovKick(8, 0.8)
	task.delay(4, function()
		UI.tween(bsc, 0.3, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.35)
		b:Destroy()
	end)
end

---------------------------------------------------------------------------------------------------
-- speech bubbles in the world
---------------------------------------------------------------------------------------------------
function Feedback.bubble(pos: Vector3, name: string, text: string)
	local anchor = Instance.new("Part")
	anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false; anchor.CanTouch = false
	anchor.Transparency = 1; anchor.Size = Vector3.new(0.2, 0.2, 0.2); anchor.CFrame = CFrame.new(pos)
	anchor.Parent = Workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(280, 74)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 220
	bb.Parent = anchor
	local card = UI.new("Frame", { BackgroundColor3 = C.card, Size = UDim2.fromScale(1, 1), Parent = bb })
	UI.corner(card, 16)
	UI.stroke(card, C.green, 2)
	UI.label(card, name, 13, C.greenDark, F.bold, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 18) })
	UI.label(card, text, 15, C.text, F.med, { Position = UDim2.fromOffset(12, 24), Size = UDim2.new(1, -24, 1, -30), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None })
	local sc = Instance.new("UIScale"); sc.Scale = 0; sc.Parent = card
	UI.tween(sc, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	Feedback.play("tick", 0.3, 1.2)
	task.delay(4.6, function()
		UI.tween(sc, 0.2, { Scale = 0 })
		task.wait(0.25)
		anchor:Destroy()
	end)
end

function Feedback.start()
	-- notifications: the top-centre strip between the status column and the navigation cluster
	gui = UI.screen("GoDashFeedback", Layers.Notification)
	toastStack = Layout.region(Layout.stage(gui), "TopCenter")
	Feedback.top = toastStack -- the Guide card sits first in this stack
	-- modal: reward card, centred in whatever the docked phone leaves free
	local modalGui = UI.screen("GoDashModal", Layers.Modal)
	modalCenter = Layout.region(Layout.stage(modalGui), "Center")
	UI.clickSound = Feedback.click

	Net.listen("Notify", function(kind, p)
		if kind == "toast" then
			Feedback.toast(p.text, p.bad and "bad" or (p.good and "good" or nil))
		elseif kind == "levelup" then
			Feedback.banner("LEVEL UP!  Lv " .. p.level, "Bonus +" .. Util.money(p.bonus) .. " · new jobs may be unlocked", "🎉")
		elseif kind == "bigwin" then
			Feedback.banner(p.title, p.text, p.icon, C.blue)
		elseif kind == "crash" then
			Feedback.play("thud", 0.9, 0.7, 0.5)
			Feedback.fovKick(10, 0.4)
			Feedback.toast("💥 Crash! Your vehicle took damage", "bad")
		elseif kind == "welcome" then
			Feedback.banner("Sawasdee, " .. p.name .. "!", "Welcome to " .. p.city .. ". Open your phone (M) and go Online.", "🛵")
		end
	end)
	Net.listen("Reward", Feedback.reward)
	Net.listen("Dialogue", function(d) Feedback.bubble(d.pos, d.name, d.text) end)
end

return Feedback
