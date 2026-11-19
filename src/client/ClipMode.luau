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
-- Recording in the game (owner, 2026-11-19: "a record button, so I can take the real file to TikTok"):
--   * ⏺ records up to 30 seconds with Roblox's own video capture (client/Capture); then a card offers
--     📤 share (the phone's share sheet, straight into TikTok; a computer downloads the file) or 💾 keep it in
--     Captures in the Roblox menu. A device that can't capture says so: use the screen recorder then.
--   * "keep this moment": after an accident, a red light or the zebra fine (client/Cutscene keeps it in
--     client/Replay), a button offers the replay of it, the camera cutting by itself with slow motion round the
--     hit, recorded the same way.
--   * 🏷 a small GoDash name in the corner of the picture (on by default), so a shared clip leads back here.
--   * ❓ how to record and post, in the game.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local UI = require(script.Parent.UI.Kit)
local Layers = require(script.Parent.UI.Core.Layers)
local UIState = require(script.Parent.UI.Core.UIState)
local Lang = require(script.Parent.Lang)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)
local Phone = require(script.Parent.Phone)
local Drive = require(script.Parent.Drive)
local Replay = require(script.Parent.Replay)
local Capture = require(script.Parent.Capture)

local Clip = {}
Clip.active = false
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local RED = Color3.fromRGB(200, 30, 40)

local MODES = {
	{ id = "follow", en = "Follow", th = "ตามหลัง", icon = "🎥" },
	{ id = "low", en = "Low chase", th = "ตามต่ำ", icon = "🏎" },
	{ id = "side", en = "Side", th = "ด้านข้าง", icon = "↔" },
	{ id = "front", en = "Front", th = "ด้านหน้า", icon = "🤳" },
	{ id = "drone", en = "Drone", th = "โดรน", icon = "🛸" },
	{ id = "road", en = "Roadside", th = "ข้างทาง", icon = "📹" },
}
local mode = 1
local gui, left, right, label, recBtn, logo, help
local logoOn = true
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
	-- the name sits top left in the picture, under where TikTok puts its own tabs
	logo.Position = UDim2.fromOffset(math.floor(bar + vs.Y * 0.025), math.floor(vs.Y * 0.11))
	logo.TextSize = math.clamp(math.floor(vs.Y * 0.03), 14, 44)
	logo.Size = UDim2.fromOffset(math.floor(w * 0.6), logo.TextSize + 8)
	logo.Visible = logoOn
end

local function fmt(s: number): string
	s = math.max(0, math.floor(s))
	return ("%d:%02d"):format(s // 60, s % 60)
end

local function showMode()
	if not label then return end
	local m = MODES[mode]
	local cam = m.icon .. " " .. L(m.en, m.th)
	if Capture.state == "rec" then
		label.Text = ("🔴 REC %s / %s  ·  %s"):format(fmt(math.min(Capture.elapsed(), Capture.MAX)), fmt(Capture.MAX), cam)
	elseif Capture.state == "starting" then
		label.Text = "⏳ " .. cam
	else
		label.Text = cam
	end
end

local function showRec()
	if not recBtn then return end
	if Capture.state == "rec" then
		recBtn.Text = "⏹ " .. L("Stop", "หยุด")
		recBtn.BackgroundColor3 = C.dark
	elseif Capture.state == "starting" then
		recBtn.Text = "⏳"
	else
		recBtn.Text = "⏺ " .. L("Record", "อัดคลิป")
		recBtn.BackgroundColor3 = RED
	end
	showMode()
end

local function toggleRec()
	if Capture.state == "rec" then Capture.stop() return end
	if Capture.state ~= "idle" then return end
	task.spawn(function()
		local ok, why = Capture.start()
		if not ok then Capture.say(Capture.explain(why), "bad") end
	end)
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

-- ❓ how to record and post, over the picture (it is never in a clip: you read it before you record)
local function toggleHelp()
	if help then help:Destroy(); help = nil; return end
	local vs = Workspace.CurrentCamera.ViewportSize
	help = UI.new("Frame", { Name = "Help", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(math.min(440, vs.X - 32), math.min(340, vs.Y - 24)), BackgroundColor3 = Color3.fromRGB(16, 18, 24),
		BackgroundTransparency = 0.04, Parent = gui })
	UI.corner(help, 14)
	UI.pad(help, 16, 12, 16, 12)
	local t = UI.label(help, L("🎬 How to make a clip for TikTok", "🎬 วิธีอัดคลิปลง TikTok"), 18, C.white, F.black, { Size = UDim2.new(1, -40, 0, 24) })
	t:SetAttribute("NoTranslate", true)
	local lines = {
		L("1. ⏺ Record: the game records up to 30 seconds. Press it again to stop.",
			"1. กด ⏺ อัดคลิป เกมอัดให้สูงสุด 30 วิ กดอีกครั้งเพื่อหยุด"),
		L("2. Then 📤 Share sends it to TikTok (a computer downloads the file), or 💾 keeps it in Captures in the Roblox menu.",
			"2. อัดเสร็จ กด 📤 แชร์ ส่งเข้า TikTok ได้เลย (บนคอมฯ จะได้ไฟล์ดาวน์โหลด) หรือ 💾 เก็บไว้ในคลัง Captures ในเมนู Roblox"),
		L("3. Just crashed, ran a red or got stopped by the police? After the scene, press 🎬 Keep this moment: the replay plays in slow motion and records itself.",
			"3. เพิ่งชน ฝ่าไฟแดง หรือโดนตำรวจเรียก? หลังฉากจบกด 🎬 เก็บคลิปเหตุการณ์นี้ เกมเล่นภาพย้อนหลังแบบสโลว์โมชันแล้วอัดให้เอง"),
		L("4. ⏪ replays your last 10 seconds; ⏺ on the replay panel records it.",
			"4. ⏪ ดูรีเพลย์ 10 วิล่าสุด แล้วกด ⏺ อัด ในแผงรีเพลย์ได้ด้วย"),
		L("5. Black bars in the clip? Zoom to fill in TikTok: the middle is exactly 9:16.",
			"5. คลิปมีแถบดำซ้ายขวา? ซูมให้เต็มจอใน TikTok ภาพกรอบกลางคือ 9:16 พอดี"),
		L("6. A device that can't record in the game: use its screen recorder and crop to the middle.",
			"6. เครื่องที่อัดในเกมไม่ได้ ใช้ตัวอัดหน้าจอของเครื่อง แล้วครอปตรงกลาง"),
	}
	if not TOUCH then
		table.insert(lines, L("N camera · L replay · B exit · 🏷 name on/off", "N เปลี่ยนมุม · L รีเพลย์ · B ออก · 🏷 เปิด/ปิดชื่อเกมในภาพ"))
	end
	local body = UI.label(help, table.concat(lines, "\n"), 14, Color3.fromRGB(214, 220, 230), F.med, {
		Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30), TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top, LineHeight = 1.1 })
	body:SetAttribute("NoTranslate", true)
	UI.fitText(body, 14, 9)
	local x = UI.button(help, "✖", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -2), Size = UDim2.fromOffset(32, 30), TextSize = 14, BackgroundColor3 = C.red }, toggleHelp)
	x:SetAttribute("NoTranslate", true)
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
	logo = UI.label(gui, "🛵 GoDash", 20, Color3.new(1, 1, 1), F.black, { Name = "Logo", TextTransparency = 0.25, TextStrokeTransparency = 0.55 })
	logo:SetAttribute("NoTranslate", true)
	-- the controls live on the left bar, top: never in the 9:16 picture
	-- (touch: on the right bar a third of the way down, clear of the status card, the steering zone and the pedals)
	-- (computer: under Roblox's own top-left buttons, which stay on screen; client/Replay's panel goes below it)
	local inset = game:GetService("GuiService"):GetGuiInset()
	local box = UI.new("Frame", { Name = "Controls", BackgroundTransparency = 1, Position = TOUCH and UDim2.new(0, 12, 0.28, 0) or UDim2.fromOffset(12, inset.Y + 8),
		Size = UDim2.new(1, -24, 0, 160), ClipsDescendants = true, Parent = TOUCH and right or left })
	UI.list(box, 6, false)
	local title = UI.label(box, L("🎬 Clip 9:16", "🎬 ถ่ายคลิป 9:16"), 16, C.white, F.black, { Size = UDim2.new(1, 0, 0, 22) })
	title:SetAttribute("NoTranslate", true)
	label = UI.label(box, "", 14, Color3.fromRGB(255, 220, 120), F.bold, { Size = UDim2.new(1, 0, 0, 20) })
	label:SetAttribute("NoTranslate", true)
	local rows = 0
	local function rowOf(): Frame
		rows += 1
		local row = UI.new("Frame", { Name = "Row" .. rows, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = box })
		UI.list(row, 6, true)
		return row
	end
	local function btn(row: Frame, text: string, w: number, cb, color: Color3?)
		local b = UI.button(row, text, { Size = UDim2.fromOffset(w, 34), TextSize = 14, BackgroundColor3 = color or C.dark }, cb)
		b:SetAttribute("NoTranslate", true)
		return b
	end
	local row = rowOf()
	btn(row, "◀", 40, function() setMode(mode - 1) end)
	btn(row, "▶", 40, function() setMode(mode + 1) end)
	btn(row, "⏪", 40, function() Replay.instant() end, Color3.fromRGB(150, 40, 60)) -- the last 10 seconds again (client/Replay)
	btn(row, "✖", 40, function() Clip.close() end, C.red)
	local row2 = rowOf()
	recBtn = btn(row2, "", 100, toggleRec, RED)
	recBtn.Name = "Rec"
	local logoBtn = btn(row2, "🏷", 40, function()
		logoOn = not logoOn
		layout()
	end)
	logoBtn.Name = "LogoBtn"
	local helpBtn = btn(row2, "❓", 40, toggleHelp)
	helpBtn.Name = "HelpBtn"
	showRec()
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

-- quiet = no "clip mode" note (the "keep this moment" replay starts recording at once: it would be in the clip)
function Clip.open(quiet: boolean?)
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
	-- (a Capture note, not a toast: on a computer the toasts are hidden with the rest of the HUD here)
	if not quiet then Capture.say(L("Clip mode: ⏺ records a clip · N changes the camera · ❓ how to", "โหมดถ่ายคลิป: ⏺ อัดคลิป · N เปลี่ยนมุมกล้อง · ❓ วิธีใช้"), "good") end
end

function Clip.close()
	if not Clip.active then return end
	Clip.active = false
	if Capture.state == "rec" then Capture.stop() end -- the clip ends with clip mode
	if help then help:Destroy(); help = nil end
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

---------------------------------------------------------------------------------------------------
-- The clip is ready: share it or keep it
---------------------------------------------------------------------------------------------------
local card
local function closeCard()
	if card then card:Destroy(); card = nil end
end

local function doneCard(video, secs: number, why: string?)
	closeCard()
	if not video then
		warn("[Clip] no clip: " .. tostring(why))
		Capture.say(L("🎬 The clip didn't record: use your screen recorder and crop to the middle",
			"🎬 อัดคลิปไม่สำเร็จ ใช้ตัวอัดหน้าจอของเครื่องแทน แล้วครอปตรงกลาง"), "bad")
		return
	end
	-- its own ScreenGui without the GoDash prefix: clip mode and replays hide those, this one must stay up
	card = Instance.new("ScreenGui")
	card.Name = "ClipDoneCard"
	card.ResetOnSpawn = false
	card.IgnoreGuiInset = true
	card.DisplayOrder = Layers.Modal + 8
	card:SetAttribute("NoTranslate", true)
	card.Parent = player:WaitForChild("PlayerGui")
	local box = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(310, 206),
		BackgroundColor3 = Color3.fromRGB(16, 18, 24), BackgroundTransparency = 0.04, Parent = card })
	UI.corner(box, 14)
	UI.stroke(box, Color3.new(1, 1, 1), 1, 0.8)
	UI.pad(box, 14)
	UI.list(box, 8, false)
	UI.label(box, L("✅ Your clip is ready", "✅ คลิปพร้อมแล้ว") .. ("  ·  %s"):format(fmt(secs + 0.5)), 18, C.white, F.black, { Size = UDim2.new(1, 0, 0, 24) })
	UI.label(box, L("Share it (TikTok and the like; a computer downloads the file) or keep it in Captures in the Roblox menu.",
		"แชร์ได้เลย (เข้า TikTok ฯลฯ บนคอมฯ จะได้ไฟล์ดาวน์โหลด) หรือเก็บไว้ในคลัง Captures ในเมนู Roblox"), 13, Color3.fromRGB(200, 206, 216), F.med,
		{ Size = UDim2.new(1, 0, 0, 52), TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top })
	UI.button(box, "📤 " .. L("Share / download", "แชร์ / ดาวน์โหลด"), { Size = UDim2.new(1, 0, 0, 38), TextSize = 15, BackgroundColor3 = RED }, function()
		Capture.share(video, function(ok) if ok then Capture.say(L("🎬 Shared!", "🎬 แชร์แล้ว!"), "good") end end)
	end)
	local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = box })
	UI.list(row, 8, true)
	UI.button(row, "💾 " .. L("Keep in Captures", "เก็บในคลัง"), { Size = UDim2.new(0.62, -4, 1, 0), TextSize = 14, BackgroundColor3 = Color3.fromRGB(60, 66, 80) }, function()
		Capture.save(video, function(saved)
			if saved then Capture.say(L("💾 Kept in Captures (Roblox menu)", "💾 เก็บลงคลัง Captures แล้ว (ในเมนู Roblox)"), "good") end
		end)
	end)
	UI.button(row, "✖ " .. L("Close", "ปิด"), { Size = UDim2.new(0.38, -4, 1, 0), TextSize = 14, BackgroundColor3 = C.red }, closeCard)
end

---------------------------------------------------------------------------------------------------
-- "Keep this moment": after an accident, a red light or the zebra fine
---------------------------------------------------------------------------------------------------
local offerGui
local function closeOffer()
	if offerGui then offerGui:Destroy(); offerGui = nil end
end

local function playMoment(ev)
	closeOffer()
	if not Clip.active then Clip.open(true) end
	task.defer(function()
		Replay.instant({ samples = ev.samples, hitAt = ev.hitAt, record = true, director = true })
	end)
end

local function speed(): number
	local c = Drive.current()
	if not c or not c.chassis then return 0 end
	local v = c.chassis.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

local function offer(ev)
	-- once the scene is over, no other card is up (it would cover this button) and you are back on that vehicle
	local t = os.clock()
	while State.cutscene and os.clock() - t < 120 do task.wait(0.25) end
	t = os.clock()
	while os.clock() - t < 20 do
		local c = Drive.current()
		if not State.cutscene and not UIState.get("modal") and c and c.model == ev.model then break end
		task.wait(0.25)
	end
	local c = Drive.current()
	if Replay.lastEvent ~= ev or State.cutscene or UIState.get("modal") or not c or c.model ~= ev.model then return end
	closeOffer()
	-- (destroyed when it goes, never just hidden: clip mode and replays put back the GoDash GUIs they hid)
	offerGui = Instance.new("ScreenGui")
	offerGui.Name = "GoDashClipOffer"
	offerGui.ResetOnSpawn = false
	offerGui.DisplayOrder = Layers.Modal + 6
	offerGui:SetAttribute("NoTranslate", true)
	offerGui.Parent = player:WaitForChild("PlayerGui")
	local mine = offerGui
	local b = UI.button(offerGui, "", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.66), Size = UDim2.fromOffset(300, 46),
		TextSize = 16, BackgroundColor3 = RED }, function() playMoment(ev) end)
	local corner = b:FindFirstChildOfClass("UICorner")
	if corner then corner.CornerRadius = UDim.new(0, 23) end
	UI.stroke(b, Color3.new(1, 1, 1), 2, 0.3)
	UI.button(offerGui, "✖", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 158, 0.66, 0), Size = UDim2.fromOffset(34, 34),
		TextSize = 14, BackgroundColor3 = C.dark }, closeOffer)
	Feedback.play("tick", 0.4, 1.2, 0.1)
	local shown = os.clock()
	while offerGui == mine and mine.Parent do
		local remain = 12 - (os.clock() - shown)
		-- it goes after a while, when you ride off, or when something newer happens
		if remain <= 0 or State.cutscene or UIState.get("modal") or Replay.lastEvent ~= ev or (os.clock() - shown > 1.5 and speed() > 14) then break end
		b.Text = ("🎬 %s  ·  %d"):format(L("Keep this moment as a clip", "เก็บคลิปเหตุการณ์นี้"), math.ceil(remain))
		task.wait(0.2)
	end
	if offerGui == mine then closeOffer() end
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
	Capture.changed:Connect(function() showRec() end)
	Capture.done:Connect(doneCard)
	-- QA hook (Studio only): Studio says a capture started but never hands a clip back, so Workspace QaClipCard
	-- = true shows the done card with a stand-in clip, to check its layout (its buttons then do nothing)
	if RunService:IsStudio() then
		Workspace:GetAttributeChangedSignal("QaClipCard"):Connect(function()
			if Workspace:GetAttribute("QaClipCard") then doneCard({}, 14) else closeCard() end
		end)
	end
	Replay.eventKept:Connect(function()
		local ev = Replay.lastEvent
		if ev then task.spawn(offer, ev) end
	end)
	-- the REC clock on the bar
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if Capture.state ~= "rec" then return end
		acc += dt
		if acc < 0.25 then return end
		acc = 0
		showMode()
	end)
end

return Clip
