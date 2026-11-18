-- Photo mode (2026-11-17 growth plan: "screenshots people want to share"). P or the phone's Photo app.
--   * the game's HUD and Roblox's chat / player list step aside
--   * a free camera around you (or your vehicle): drag with the right mouse button or the arrow
--     buttons to turn, wheel or +/- to zoom, up/down to raise
--   * filters (colour looks), lens (wide / normal / zoom), soft background blur
--   * poses: wave, point, cheer, dance (Roblox's own R15 emotes)
--   * "Hide panel" leaves a clean picture: take it with Roblox's capture button or a screenshot
-- Walking and driving keys are held while it is open, so the picture doesn't move away.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local UI = require(script.Parent.UI.Kit)
local Layers = require(script.Parent.UI.Core.Layers)
local UIState = require(script.Parent.UI.Core.UIState)
local Lang = require(script.Parent.Lang)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)
local Phone = require(script.Parent.Phone)

local Photo = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local rad = math.rad

local open = false
local gui, panel, showBtn
local yaw, pitch, dist, lift = 0, rad(-8), 12, 0
local hold = { left = false, right = false, up = false, down = false, zin = false, zout = false }
local dragging = false
local hidden = {}
local filter, blur
local fov = 60
local poseTrack: AnimationTrack? = nil

local FILTERS = {
	{ id = "none", en = "Normal", th = "ปกติ" },
	{ id = "warm", en = "Golden", th = "แดดเย็น", tint = Color3.fromRGB(255, 228, 196), sat = 0.12, con = 0.05, bri = 0.02 },
	{ id = "cool", en = "Cool", th = "โทนฟ้า", tint = Color3.fromRGB(214, 232, 255), sat = 0.05, con = 0.04, bri = 0.01 },
	{ id = "vivid", en = "Vivid", th = "สดจัด", tint = Color3.new(1, 1, 1), sat = 0.38, con = 0.1, bri = 0.02 },
	{ id = "film", en = "Film", th = "ฟิล์ม", tint = Color3.fromRGB(246, 236, 214), sat = -0.18, con = -0.04, bri = 0.03 },
	{ id = "mono", en = "B&W", th = "ขาวดำ", tint = Color3.new(1, 1, 1), sat = -1, con = 0.12, bri = 0 },
}
local POSES = {
	{ en = "Wave", th = "โบกมือ", icon = "👋", id = "rbxassetid://507770239" },
	{ en = "Point", th = "ชี้", icon = "👉", id = "rbxassetid://507770453" },
	{ en = "Cheer", th = "เชียร์", icon = "🙌", id = "rbxassetid://507770677" },
	{ en = "Dance", th = "เต้น", icon = "💃", id = "rbxassetid://507771019" },
}

local function subject(): Vector3?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	local seat = hum and hum.SeatPart
	if seat and seat.Parent and seat.Parent:IsA("Model") and seat.Parent.PrimaryPart then
		return seat.Parent.PrimaryPart.Position + Vector3.new(0, 1.5, 0)
	end
	return root.Position + Vector3.new(0, 0.5, 0)
end

local function sink() return Enum.ContextActionResult.Sink end

local function setFilter(f)
	if not filter then return end
	filter.Enabled = f.id ~= "none"
	filter.TintColor = f.tint or Color3.new(1, 1, 1)
	filter.Saturation = f.sat or 0
	filter.Contrast = f.con or 0
	filter.Brightness = f.bri or 0
end

local function stopPose()
	if poseTrack then poseTrack:Stop(0.3); poseTrack = nil end
end

local function playPose(p)
	stopPose()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator or hum.SeatPart then return end
	local a = Instance.new("Animation")
	a.AnimationId = p.id
	local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
	if ok and tr then
		tr.Priority = Enum.AnimationPriority.Action
		tr.Looped = p.en == "Dance"
		tr:Play(0.2)
		poseTrack = tr
	end
end

local function close()
	if not open then return end
	open = false
	RunService:UnbindFromRenderStep("GoDashPhoto")
	ContextActionService:UnbindAction("GoDashPhotoHold")
	stopPose()
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	for g in pairs(hidden) do if g.Parent then g.Enabled = true end end
	hidden = {}
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
	if filter then filter.Enabled = false end
	if blur then blur.Enabled = false end
	if gui then gui.Enabled = false end
	UIState.set("modal", false)
end

local function build()
	gui = UI.screen("GoDashPhoto", Layers.Modal + 6)
	gui.Enabled = false
	panel = UI.new("Frame", { BackgroundColor3 = C.black, BackgroundTransparency = 0.35, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(660, 150), Parent = gui })
	UI.corner(panel, 18)
	local function btn(parent, text, w, cb, color)
		local b = UI.button(parent, text, { Size = UDim2.fromOffset(w, 34), TextSize = 13, BackgroundColor3 = color or C.dark }, cb)
		b:SetAttribute("NoTranslate", true)
		return b
	end
	local function holdBtn(parent, text, key)
		-- hold to keep moving; a tap moves one step (15 degrees, 1.5 studs)
		local b = btn(parent, text, 38, function()
			if key == "left" then yaw -= rad(15) elseif key == "right" then yaw += rad(15)
			elseif key == "up" then lift = math.min(lift + 1.5, 18) elseif key == "down" then lift = math.max(lift - 1.5, -2)
			elseif key == "zin" then dist = math.max(3, dist - 2) elseif key == "zout" then dist = math.min(40, dist + 2) end
		end)
		b.MouseButton1Down:Connect(function() hold[key] = true end)
		b.MouseButton1Up:Connect(function() hold[key] = false end)
		b.MouseLeave:Connect(function() hold[key] = false end)
		return b
	end
	local function rowAt(y)
		local r = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 34), Parent = panel })
		UI.list(r, 6, true)
		return r
	end
	-- row 1: camera
	local r1 = rowAt(10)
	local title = UI.label(r1, L("📷 Photo", "📷 ถ่ายรูป"), 15, C.white, F.black, { Size = UDim2.fromOffset(92, 34) })
	title:SetAttribute("NoTranslate", true)
	holdBtn(r1, "◀", "left"); holdBtn(r1, "▶", "right"); holdBtn(r1, "▲", "up"); holdBtn(r1, "▼", "down"); holdBtn(r1, "＋", "zin"); holdBtn(r1, "－", "zout")
	for _, lens in ipairs({ { L("Wide", "มุมกว้าง"), 85 }, { L("Normal", "ปกติ"), 60 }, { L("Zoom", "ซูม"), 32 } }) do
		btn(r1, lens[1], 64, function() fov = lens[2] end)
	end
	btn(r1, L("Blur", "เบลอฉากหลัง"), 86, function() if blur then blur.Enabled = not blur.Enabled end end)
	-- row 2: filters
	local r2 = rowAt(56)
	for _, f in ipairs(FILTERS) do
		btn(r2, L(f.en, f.th), 98, function() setFilter(f) end, Color3.fromRGB(70, 60, 110))
	end
	-- row 3: poses, hide, close
	local r3 = rowAt(102)
	for _, p in ipairs(POSES) do
		btn(r3, p.icon .. " " .. L(p.en, p.th), 92, function() playPose(p) end, Color3.fromRGB(40, 110, 80))
	end
	btn(r3, L("Hide panel (H)", "ซ่อนแผง (H)"), 120, function() panel.Visible = false; showBtn.Visible = true end, C.dark)
	btn(r3, L("Close (P)", "ปิด (P)"), 84, close, C.red)
	showBtn = UI.button(gui, "📷", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -12), Size = UDim2.fromOffset(40, 40), TextSize = 18,
		BackgroundColor3 = C.black, BackgroundTransparency = 0.6, Visible = false }, function() panel.Visible = true; showBtn.Visible = false end)
	filter = Instance.new("ColorCorrectionEffect")
	filter.Name = "GoDashPhotoFilter"
	filter.Enabled = false
	filter.Parent = Lighting
	blur = Instance.new("DepthOfFieldEffect")
	blur.Name = "GoDashPhotoBlur"
	blur.Enabled = false
	blur.FarIntensity = 0.6
	blur.NearIntensity = 0.2
	blur.InFocusRadius = 6
	blur.Parent = Lighting
end

function Photo.open()
	if open or State.cutscene then return end
	if not gui then build() end
	open = true
	Phone.setOpen(false)
	local cam = Workspace.CurrentCamera
	-- start from where the game camera is now, around the same subject
	local s = subject()
	if s then
		local off = cam.CFrame.Position - s
		yaw = math.atan2(off.X, off.Z)
		dist = math.clamp(off.Magnitude, 6, 30)
		pitch = math.clamp(-math.asin(math.clamp(off.Y / math.max(off.Magnitude, 0.01), -1, 1)), rad(-70), rad(30))
	end
	lift = 0
	fov = 60
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g ~= gui and g.Name:sub(1, 6) == "GoDash" then
			g.Enabled = false
			hidden[g] = true
		end
	end
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
	panel.Visible = true
	showBtn.Visible = false
	gui.Enabled = true
	UIState.set("modal", true)
	-- hold the movement and driving keys while the picture is set up
	ContextActionService:BindActionAtPriority("GoDashPhotoHold", sink, false, Enum.ContextActionPriority.High.Value + 50,
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
		Enum.KeyCode.LeftShift, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.G, Enum.KeyCode.F, Enum.KeyCode.Thumbstick1)
	RunService:BindToRenderStep("GoDashPhoto", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local sp = subject()
		if not sp then return end
		local k = dt * 1.6
		if hold.left then yaw -= k end
		if hold.right then yaw += k end
		if hold.up then lift = math.min(lift + dt * 6, 18) end
		if hold.down then lift = math.max(lift - dt * 6, -2) end
		if hold.zin then dist = math.max(3, dist - dt * 10) end
		if hold.zout then dist = math.min(40, dist + dt * 10) end
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView += (fov - cam.FieldOfView) * math.min(1, dt * 6)
		local dir = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		local eye = sp + dir:VectorToWorldSpace(Vector3.new(0, 0, dist)) + Vector3.new(0, lift, 0)
		cam.CFrame = CFrame.lookAt(eye, sp + Vector3.new(0, lift * 0.35, 0))
		if blur and blur.Enabled then blur.FocusDistance = (eye - sp).Magnitude end
	end)
	Feedback.toast(L("Photo mode: drag with the right mouse button to turn · H hides the panel", "โหมดถ่ายรูป: คลิกขวาค้างแล้วลากเพื่อหมุน · กด H ซ่อนแผง"), "good")
end

function Photo.start()
	Phone.addApp({ id = "photo", name = "Photo", icon = "📷", color = Color3.fromRGB(40, 44, 52) }, function()
		task.defer(Photo.open)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and open then dragging = true end
		if processed then return end
		if input.KeyCode == Enum.KeyCode.P then
			if open then close() else Photo.open() end
		elseif input.KeyCode == Enum.KeyCode.H and open and panel then
			panel.Visible = not panel.Visible
			showBtn.Visible = not panel.Visible
		elseif input.KeyCode == Enum.KeyCode.Escape and open then
			close()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then dragging = false end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not open then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
			yaw -= input.Delta.X * 0.006
			pitch = math.clamp(pitch - input.Delta.Y * 0.005, rad(-70), rad(30))
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			dist = math.clamp(dist - input.Position.Z * 1.5, 3, 40)
		elseif input.UserInputType == Enum.UserInputType.Touch and input.Delta.Magnitude > 0 and not panel.Visible then
			yaw -= input.Delta.X * 0.006
			pitch = math.clamp(pitch - input.Delta.Y * 0.005, rad(-70), rad(30))
		end
	end)
end

return Photo
