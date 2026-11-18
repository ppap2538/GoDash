-- Clip mode for TikTok (2026-11-19, owner: lots of content to play and post). B, or the phone's Clip app.
--   * the picture is pillarboxed to 9:16: black bars left and right, so a screen recording only needs
--     cropping to the middle; the clip mode's own buttons sit on the black bars and never show in the crop
--   * you keep riding or walking; on a computer the game's HUD and Roblox's menus step aside (on a touch
--     screen the driving controls stay, drawn over the bars, outside the crop)
--   * camera angles (N, or the arrows on the bar):
--       Follow   the game's own camera
--       Low      low behind you, a little lag: speed feels fast
--       Side     tracking beside you
--       Front    ahead of you, looking back at your face
--       Drone    a slow orbit from above
--       Roadside a camera on the kerb that pans as you pass, then jumps ahead of you
-- The cameras stay out of walls (a ray from you to the lens pulls it in front of anything solid).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local UI = require(script.Parent.UI.Kit)
local Layers = require(script.Parent.UI.Core.Layers)
local Lang = require(script.Parent.Lang)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)
local Phone = require(script.Parent.Phone)
local Drive = require(script.Parent.Drive)
local Replay = require(script.Parent.Replay)

local Clip = {}
Clip.active = false
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local MODES = {
	{ id = "follow", en = "Follow", th = "ตามหลัง", icon = "🎥" },
	{ id = "low", en = "Low chase", th = "ตามต่ำ", icon = "🏎" },
	{ id = "side", en = "Side", th = "ด้านข้าง", icon = "↔" },
	{ id = "front", en = "Front", th = "ด้านหน้า", icon = "🤳" },
	{ id = "drone", en = "Drone", th = "โดรน", icon = "🛸" },
	{ id = "road", en = "Roadside", th = "ข้างทาง", icon = "📹" },
}
local mode = 1
local gui, left, right, label
local hidden = {}
local camPos, lookPos: Vector3? = nil, nil
local orbit = 0
local roadCam: Vector3? = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- what the camera looks at: the vehicle you ride, or you
local function subject(): (Vector3?, Vector3, number)
	local c = Drive.current()
	if c and c.chassis and c.chassis.Parent then
		local cf = c.chassis.CFrame
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		local v = c.chassis.AssemblyLinearVelocity
		return cf.Position + Vector3.new(0, 1.6, 0), look.Magnitude > 0.05 and look.Unit or Vector3.new(0, 0, -1), Vector3.new(v.X, 0, v.Z).Magnitude
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil, Vector3.new(0, 0, -1), 0 end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local v = root.AssemblyLinearVelocity
	return root.Position + Vector3.new(0, 1, 0), look.Magnitude > 0.05 and look.Unit or Vector3.new(0, 0, -1), Vector3.new(v.X, 0, v.Z).Magnitude
end

-- keep the lens in front of walls between it and the subject
local function clear(from: Vector3, to: Vector3): Vector3
	local d = to - from
	local hit = Workspace:Raycast(from, d, rayParams)
	if hit then return hit.Position - d.Unit * 1.2 end
	return to
end

local function layout()
	if not gui then return end
	local cam = Workspace.CurrentCamera
	local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local w = vs.Y * 9 / 16
	local bar = math.max(0, (vs.X - w) / 2)
	left.Size = UDim2.new(0, bar, 1, 0)
	right.Size = UDim2.new(0, bar, 1, 0)
	right.Position = UDim2.new(1, -bar, 0, 0)
end

local function showMode()
	if label then
		local m = MODES[mode]
		label.Text = m.icon .. " " .. L(m.en, m.th)
	end
end

local function setMode(i: number)
	mode = (i - 1) % #MODES + 1
	camPos, lookPos, roadCam = nil, nil, nil
	if MODES[mode].id == "follow" then
		local cam = Workspace.CurrentCamera
		if cam and not Drive.current() then cam.CameraType = Enum.CameraType.Custom end
		cam.FieldOfView = 70
	end
	showMode()
end

local function build()
	-- a plain ScreenGui (no layout scale, no safe-area inset): the bars are measured in real pixels
	gui = Instance.new("ScreenGui")
	gui.Name = "GoDashClip"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = TOUCH and (Layers.HUD - 1) or (Layers.Modal + 7)
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	left = UI.new("Frame", { Name = "BarL", BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.new(0, 0, 1, 0), Parent = gui })
	right = UI.new("Frame", { Name = "BarR", BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.new(0, 0, 1, 0), Parent = gui })
	-- the controls live on the left bar, top: never in the 9:16 picture
	-- (touch: on the right bar a third of the way down, clear of the status card, the steering zone and the pedals)
	local box = UI.new("Frame", { BackgroundTransparency = 1, Position = TOUCH and UDim2.new(0, 12, 0.28, 0) or UDim2.fromOffset(12, 16),
		Size = UDim2.new(1, -24, 0, 150), ClipsDescendants = true, Parent = TOUCH and right or left })
	UI.list(box, 6, false)
	local title = UI.label(box, L("🎬 Clip 9:16", "🎬 ถ่ายคลิป 9:16"), 16, C.white, F.black, { Size = UDim2.new(1, 0, 0, 22) })
	title:SetAttribute("NoTranslate", true)
	label = UI.label(box, "", 14, Color3.fromRGB(255, 220, 120), F.bold, { Size = UDim2.new(1, 0, 0, 20) })
	label:SetAttribute("NoTranslate", true)
	local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = box })
	UI.list(row, 6, true)
	local function btn(text: string, w: number, cb, color: Color3?)
		local b = UI.button(row, text, { Size = UDim2.fromOffset(w, 34), TextSize = 14, BackgroundColor3 = color or C.dark }, cb)
		b:SetAttribute("NoTranslate", true)
		return b
	end
	btn("◀", 40, function() setMode(mode - 1) end)
	btn("▶", 40, function() setMode(mode + 1) end)
	btn("⏪", 40, function() Replay.instant() end, Color3.fromRGB(200, 30, 40)) -- the last 10 seconds again (client/Replay)
	btn("✖", 40, function() Clip.close() end, C.red)
	if not TOUCH then
		local hint = UI.label(box, L("N = camera · L = replay · B = exit", "N = เปลี่ยนมุม · L = รีเพลย์ · B = ออก"), 12, Color3.fromRGB(190, 196, 206), F.med, { Size = UDim2.new(1, 0, 0, 18) })
		hint:SetAttribute("NoTranslate", true)
	end
	local cam = Workspace.CurrentCamera
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
end

local function step(dt: number)
	local cam = Workspace.CurrentCamera
	local m = MODES[mode].id
	Drive.cameraBusy = m ~= "follow" and not State.cutscene -- Drive leaves the lens alone then
	if m == "follow" or State.cutscene then return end
	local s, fwd, speed = subject()
	if not s then return end
	local right3 = Vector3.new(-fwd.Z, 0, fwd.X)
	local want, look, fov, k
	if m == "low" then
		want = s - fwd * (8 + speed * 0.05) + Vector3.new(0, 1.4, 0) + right3 * 1.2
		look = s + fwd * 10 + Vector3.new(0, 0.6, 0)
		fov, k = 58 + math.min(speed, 80) * 0.12, 5
	elseif m == "side" then
		-- (14 studs out: at 10 a play test only fitted the rider's middle into the 9:16 frame)
		want = s + right3 * 14 + fwd * (2 + speed * 0.04) + Vector3.new(0, 2.6, 0)
		look = s + fwd * (1 + speed * 0.04)
		fov, k = 56, 4
	elseif m == "front" then
		want = s + fwd * (9 + speed * 0.06) + Vector3.new(0, 2.6, 0) + right3 * 1.5
		look = s + Vector3.new(0, 0.8, 0)
		fov, k = 52, 5
	elseif m == "drone" then
		orbit += dt * 0.16
		want = s + Vector3.new(math.cos(orbit) * 42, 30, math.sin(orbit) * 42)
		look = s
		fov, k = 62, 2
	else -- roadside: a fixed spot on the kerb ahead of you; jump ahead again once you have passed it
		if not roadCam or (roadCam - s).Magnitude > (Drive.current() and 130 or 60) then
			local ahead = Drive.current() and (40 + speed * 1.6) or 22
			roadCam = clear(s, s + fwd * ahead + right3 * (Drive.current() and 9 or 5) + Vector3.new(0, 3.2, 0))
			camPos = roadCam
		end
		want = roadCam :: Vector3
		look = s
		fov, k = 42, 50
	end
	rayParams.FilterDescendantsInstances = { player.Character, Drive.current() and Drive.current().model or nil, Workspace:FindFirstChild("GoDashLocalTraffic"),
		Workspace:FindFirstChild("GoDashPedestrians"), Workspace:FindFirstChild("WaterLights"), Workspace:FindFirstChild("GoDashFireworks") }
	if m ~= "drone" and m ~= "road" then want = clear(s, want) end
	local a = 1 - math.exp(-dt * k)
	camPos = camPos and camPos:Lerp(want, a) or want
	lookPos = lookPos and lookPos:Lerp(look, math.min(1, a * 1.6)) or look
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView += (fov - cam.FieldOfView) * math.min(1, dt * 4)
	cam.CFrame = CFrame.lookAt(camPos :: Vector3, lookPos :: Vector3)
end

function Clip.open()
	if Clip.active or State.cutscene then return end
	if not gui then build() end
	Clip.active = true
	Phone.setOpen(false)
	if not TOUCH then
		for _, g in ipairs(player.PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled and g ~= gui and g.Name:sub(1, 6) == "GoDash" then
				g.Enabled = false
				hidden[g] = true
			end
		end
		pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
	end
	layout()
	gui.Enabled = true
	setMode(mode)
	-- after ChaseCam (Camera priority) so these angles win while they are on
	RunService:BindToRenderStep("GoDashClip", Enum.RenderPriority.Camera.Value + 3, step)
	Feedback.toast(L("Clip mode: record your screen and crop to the middle · N changes the camera", "โหมดถ่ายคลิป: อัดหน้าจอแล้วครอปตรงกลาง · กด N เปลี่ยนมุมกล้อง"), "good")
end

function Clip.close()
	if not Clip.active then return end
	Clip.active = false
	Drive.cameraBusy = false
	RunService:UnbindFromRenderStep("GoDashClip")
	local cam = Workspace.CurrentCamera
	cam.FieldOfView = 70
	if not Drive.current() and not State.cutscene then cam.CameraType = Enum.CameraType.Custom end
	for g in pairs(hidden) do if g.Parent then g.Enabled = true end end
	hidden = {}
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
	if gui then gui.Enabled = false end
end

function Clip.start()
	Phone.addApp({ id = "clip", name = "Clip", icon = "🎬", color = Color3.fromRGB(150, 40, 60) }, function()
		task.defer(Clip.open)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.B then
			if Clip.active then Clip.close() else Clip.open() end
		elseif input.KeyCode == Enum.KeyCode.N and Clip.active then
			setMode(mode + 1)
		end
	end)
end

return Clip
