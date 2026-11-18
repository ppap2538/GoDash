-- Ghost scenes (2026-11-18, owner: Thai riders delivering to lonely, dark places meet ghosts and then tell it on a
-- ghost radio show; "ขอเป็นคัทซีนด้วยนะ"). Spooky, never gory: a woman in white with long black hair over her face,
-- flickering light, a short fright, and she is gone. Phone > Settings turns ghost scenes off.
--   * "customer" (server/GhostService picks a late food delivery to a lonely place): she takes the bag, whispers
--     "ขอบใจจ้ะ…", the money in your hand turns into dry leaves, you look again and she is gone
--   * "roadside": on a dark suburban or rural road late at night, a figure stands under a big tree by the kerb;
--     ride up to her and the engine dies, she turns her head... and vanishes
--   * then: "call the Haunted Night Radio 13.13?" (our own show, not the real "The Ghost Radio"): a short on-air
--     chat with DJ Pong built from what happened; it goes on everyone's City Feed (server pays once)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Sounds = require(Shared.Config.Sounds)
local Map = require(Shared.Config.Maps.KhonKaen)
local Drive = require(script.Parent.Drive)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)
local Choice = require(script.Parent.Choice)

local Ghosts = {}
local L = Lang.pick
local player = Players.LocalPlayer
local playing = false
local gui, barTop, barBottom, caption, fade

local SKIN = Color3.fromRGB(226, 226, 230)
local DRESS = Color3.fromRGB(240, 240, 236)
local HAIR = Color3.fromRGB(12, 12, 14)

local function enabled(): boolean
	local s = State.data and State.data.settings
	return not (s and s.ghosts == false)
end

local function lateNight(): boolean
	local c = Lighting.ClockTime
	return c >= 21 or c < 4.5
end

---------------------------------------------------------------------------------------------------
-- the figure
---------------------------------------------------------------------------------------------------
local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?, transp: number?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Transparency = transp or 0
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

-- The lady in white: ReplicatedStorage.GoDashModels.GhostLady, a free Creator Store model ("Kuntilanak/Pontianak" by
-- KianataAzka_321, asset 9823957896, scripts stripped; docs/ASSETS.md). Its pivot is the bottom of her feet, facing
-- -Z. A see-through glow and mist are added here. Without it, a simple figure built from parts stands in.
local function decorate(m: Model, base: BasePart)
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(220, 226, 240))
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.75), NumberSequenceKeypoint.new(1, 1) })
	mist.Size = NumberSequence.new(2, 5)
	mist.Lifetime = NumberRange.new(2, 3)
	mist.Rate = 7
	mist.Speed = NumberRange.new(0.3, 0.8)
	mist.SpreadAngle = Vector2.new(180, 20)
	mist.LightEmission = 0.2
	mist.Parent = base
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(180, 200, 255)
	light.Range = 14
	light.Brightness = 1.3
	light.Parent = base
	-- a cold light just in front of her, so she reads in the dark
	local front = part(m, Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 4.6, -2.4), DRESS, nil, 1)
	local fl = Instance.new("PointLight")
	fl.Color = Color3.fromRGB(170, 190, 255)
	fl.Range = 8
	fl.Brightness = 1.8
	fl.Parent = front
end

local function makeGhost(): Model
	local m = Instance.new("Model")
	m.Name = "GoDashGhost"
	local store = ReplicatedStorage:FindFirstChild("GoDashModels")
	local tpl = store and store:FindFirstChild("GhostLady")
	if tpl and tpl:IsA("Model") then
		local body = tpl:Clone()
		for _, d in ipairs(body:GetDescendants()) do
			if d:IsA("LuaSourceContainer") or d:IsA("TouchTransmitter") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
				if d.Transparency < 1 then d.Transparency = 0.12 end -- a little see-through
			elseif d:IsA("Humanoid") then
				d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
		end
		body:PivotTo(CFrame.new(0, 0.35, 0)) -- feet a hand's width off the ground
		body.Parent = m
		decorate(m, part(m, Vector3.new(1, 0.2, 1), CFrame.new(0, 0.3, 0), DRESS, nil, 1))
		m.WorldPivot = CFrame.new()
		return m
	end
	local up = CFrame.Angles(0, 0, math.rad(90)) -- cylinders stand up
	-- a long A-line gown: tiers that narrow toward the waist, hem just off the ground (a play test showed the
	-- first build read as a chair: too short, too square)
	-- the gown glows faintly (Neon, see-through), like the ghosts of Thai films, so the black hair stands out against
	-- it at night; many thin tiers make a smooth bell
	local function gown(p: BasePart)
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(150, 156, 170)
		p.Transparency = 0.32
	end
	for k = 0, 8 do
		local d = 2.9 - k * 0.17
		gown(part(m, Vector3.new(0.48, d, d), CFrame.new(0, 0.6 + k * 0.42, 0) * up, DRESS, Enum.PartType.Cylinder))
	end
	gown(part(m, Vector3.new(1.4, 1.5, 0.85), CFrame.new(0, 5.0, 0), DRESS)) -- bodice
	gown(part(m, Vector3.new(1.62, 0.42, 0.9), CFrame.new(0, 5.62, 0), DRESS)) -- shoulders
	-- slender arms close to the body, hanging, pale hands
	local armL = part(m, Vector3.new(2.0, 0.34, 0.34), CFrame.new(-0.86, 4.6, -0.05) * CFrame.Angles(0, 0, math.rad(3)) * up, DRESS, Enum.PartType.Cylinder)
	armL.Name = "ArmL"
	gown(armL)
	local armR = part(m, Vector3.new(2.0, 0.34, 0.34), CFrame.new(0.86, 4.6, -0.05) * CFrame.Angles(0, 0, math.rad(-3)) * up, DRESS, Enum.PartType.Cylinder)
	armR.Name = "ArmR"
	gown(armR)
	part(m, Vector3.new(0.34, 0.4, 0.34), CFrame.new(-0.9, 3.45, -0.08), SKIN, Enum.PartType.Ball, 0.05)
	part(m, Vector3.new(0.34, 0.4, 0.34), CFrame.new(0.9, 3.45, -0.08), SKIN, Enum.PartType.Ball, 0.05)
	part(m, Vector3.new(0.42, 0.5, 0.42), CFrame.new(0, 5.95, 0) * up, SKIN, Enum.PartType.Cylinder, 0.05) -- neck
	part(m, Vector3.new(1.1, 1.25, 1.1), CFrame.new(0, 6.65, 0), SKIN, Enum.PartType.Ball, 0.05).Name = "Head"
	-- long black hair down the back to the waist, a crown, and a curtain over the face: no face is ever shown
	part(m, Vector3.new(1.3, 3.4, 0.4), CFrame.new(0, 5.35, 0.5), HAIR)
	part(m, Vector3.new(1.24, 0.5, 1.24), CFrame.new(0, 7.15, 0), HAIR, Enum.PartType.Ball)
	part(m, Vector3.new(1.08, 2.3, 0.16), CFrame.new(0, 6.15, -0.6), HAIR).Name = "Fringe"
	for _, sx in ipairs({ -0.6, 0.6 }) do part(m, Vector3.new(0.18, 2.6, 0.9), CFrame.new(sx, 6.0, -0.05), HAIR) end
	decorate(m, part(m, Vector3.new(1, 0.2, 1), CFrame.new(0, 0.3, 0), DRESS, nil, 1))
	m.WorldPivot = CFrame.new()
	return m
end

local function fadeOut(m: Model, t: number)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then TweenService:Create(p, TweenInfo.new(t), { Transparency = 1 }):Play()
		elseif p:IsA("ParticleEmitter") then p.Enabled = false
		elseif p:IsA("PointLight") then TweenService:Create(p, TweenInfo.new(t), { Brightness = 0 }):Play() end
	end
end

---------------------------------------------------------------------------------------------------
-- scene helpers (own small letterbox, caption and fade)
---------------------------------------------------------------------------------------------------
local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "GoDashGhostScene"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 81
	gui.Enabled = false
	local function bar(y: number)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0, y)
		f.Position = UDim2.fromScale(0, y)
		f.Size = UDim2.fromScale(1, 0)
		f.Parent = gui
		return f
	end
	barTop, barBottom = bar(0), bar(1)
	caption = Instance.new("TextLabel")
	caption.BackgroundTransparency = 1
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.Position = UDim2.new(0.5, 0, 1, -20)
	caption.Size = UDim2.new(0.9, 0, 0, 36)
	caption.Font = Enum.Font.GothamBold
	caption.TextSize = 24
	caption.TextColor3 = Color3.fromRGB(230, 236, 255)
	caption.TextStrokeTransparency = 0.3
	caption.Text = ""
	caption.ZIndex = 3
	caption:SetAttribute("NoTranslate", true)
	caption.Parent = gui
	fade = Instance.new("Frame")
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.BorderSizePixel = 0
	fade.Size = UDim2.fromScale(1, 1)
	fade.ZIndex = 5
	fade.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function tw(inst: Instance, t: number, props)
	TweenService:Create(inst, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

-- runs fn(wait, say) as a scene; any key or tap skips to the end
local function scene(fn)
	if playing then return end
	if not gui then buildGui() end
	local cam = Workspace.CurrentCamera
	if not cam then return end
	playing = true
	State.cutscene = true
	local hidden = {}
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g ~= gui and g.Enabled and g.Name:sub(1, 6) == "GoDash" then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
	gui.Enabled = true
	tw(barTop, 0.3, { Size = UDim2.fromScale(1, 0.1) })
	tw(barBottom, 0.3, { Size = UDim2.fromScale(1, 0.12) })
	local skip = false
	local con = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		local t = input.UserInputType
		if t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then skip = true end
	end)
	local oldType, oldFov = cam.CameraType, cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	local hold = RunService:IsStudio() and Workspace:GetAttribute("QaSceneHold") and 5 or 1 -- Studio: slow it down for screenshots
	local function wait(t: number): boolean
		t *= hold
		local t0 = os.clock()
		while os.clock() - t0 < t do
			if skip then return false end
			RunService.RenderStepped:Wait()
		end
		return not skip
	end
	local function say(text: string, speed: number?)
		caption.Text = ""
		local n = utf8.len(text) or #text
		local i = 0
		for _, c in utf8.codes(text) do
			i += 1
			caption.Text ..= utf8.char(c)
			if skip then caption.Text = text break end
			if i % 2 == 0 then RunService.RenderStepped:Wait() end
		end
		local _ = n
		local __ = speed
	end
	local ok, err = pcall(fn, wait, say, cam)
	if not ok then warn("[Ghosts] " .. tostring(err)) end
	con:Disconnect()
	tw(fade, 0.2, { BackgroundTransparency = 0 })
	task.wait(0.22)
	cam.CameraType = oldType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or oldType
	cam.FieldOfView = oldFov
	for _, g in ipairs(hidden) do if g.Parent then g.Enabled = true end end
	caption.Text = ""
	tw(barTop, 0.25, { Size = UDim2.fromScale(1, 0) })
	tw(barBottom, 0.25, { Size = UDim2.fromScale(1, 0) })
	tw(fade, 0.35, { BackgroundTransparency = 1 })
	task.delay(0.4, function() if not playing then gui.Enabled = false end end)
	State.cutscene = false
	playing = false
end

local function sting(pos: Vector3?, speed: number)
	local s = Instance.new("Sound")
	s.SoundId = Sounds.boom
	s.Volume = 0.45
	s.PlaybackSpeed = speed
	s.SoundGroup = Feedback.sfxGroup
	s.Parent = Workspace.CurrentCamera
	s:Play()
	task.delay(3, function() s:Destroy() end)
	local _ = pos
end

local function groundAt(pos: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), params)
	return hit and hit.Position or Vector3.new(pos.X, 0.3, pos.Z)
end

---------------------------------------------------------------------------------------------------
-- the radio call-in
---------------------------------------------------------------------------------------------------
local function radio()
	task.wait(1.5)
	local n = Choice.ask({ icon = "📻", title = L("Call the Haunted Night Radio 13.13?", "โทรเข้ารายการ วิทยุคืนหลอน 13.13 ไหม?"),
		text = L("Tell the whole town what just happened (+฿100, +season XP)", "เล่าเรื่องที่เพิ่งเจอให้คนทั้งเมืองฟัง (+฿100 +XP ซีซั่น)"),
		answers = { { L("📞 Call now", "📞 โทรเลย") }, { L("Not tonight", "ไม่ล่ะ") } }, seconds = 25 })
	if n ~= 1 then return end
	local ok, _, extra = Net.call("City", "ghost_radio")
	if not ok or type(extra) ~= "table" then return end
	local place = tostring(extra.place or "")
	-- the on-air card
	local g = Instance.new("ScreenGui")
	g.Name = "GoDashGhostRadio"
	g.ResetOnSpawn = false
	g.DisplayOrder = 70
	g.Parent = player.PlayerGui
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 0.86, 0)
	card.Size = UDim2.fromOffset(460, 168)
	card.BackgroundColor3 = Color3.fromRGB(24, 14, 40)
	card.BackgroundTransparency = 0.05
	card.Parent = g
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 18); corner.Parent = card
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(170, 90, 255); stroke.Thickness = 2; stroke.Parent = card
	local function label(y: number, h: number, size: number, color: Color3, font: Enum.Font): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(16, y)
		t.Size = UDim2.new(1, -32, 0, h)
		t.Font = font
		t.TextSize = size
		t.TextColor3 = color
		t.TextWrapped = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextYAlignment = Enum.TextYAlignment.Top
		t:SetAttribute("NoTranslate", true)
		t.Parent = card
		return t
	end
	label(10, 22, 16, Color3.fromRGB(255, 120, 120), Enum.Font.GothamBlack).Text = "🔴 ON AIR  ·  " .. L("Haunted Night Radio 13.13 FM", "วิทยุคืนหลอน 13.13 FM")
	local who = label(38, 20, 14, Color3.fromRGB(200, 170, 255), Enum.Font.GothamBold)
	local line = label(60, 100, 17, Color3.new(1, 1, 1), Enum.Font.GothamMedium)
	local function speak(name: string, text: string, hold: number)
		who.Text = name
		line.Text = ""
		for _, c in utf8.codes(text) do
			line.Text ..= utf8.char(c)
			task.wait(0.022)
		end
		task.wait(hold)
	end
	local dj, me = L("📻 DJ Pong", "📻 ดีเจป๋อง"), L("🛵 You (rider)", "🛵 คุณ (ไรเดอร์)")
	local at = place ~= "" and place or L("the edge of town", "ชานเมือง")
	speak(dj, L("Good evening, night owls... we have a rider on the line. Go ahead.", "สวัสดีครับคุณผู้ฟังคืนหลอน... มีไรเดอร์โทรเข้ามาครับ เชิญเล่าเลยครับ"), 1.2)
	if extra.variant == "customer" then
		speak(me, L(("I had a late delivery near %s. The whole house was dark."):format(at), ("ผมไปส่งอาหารแถว%s ดึกมากครับ บ้านมืดทั้งหลัง"):format(at)), 1.1)
		speak(me, L("A woman in white came out for the bag and whispered 'thank you'... then the money turned into leaves!", "ผู้หญิงชุดขาวออกมารับ กระซิบว่า ขอบใจจ้ะ... พอดูเงินอีกที กลายเป็นใบไม้แห้ง!"), 1.3)
		speak(dj, L("Brrr... and the customer?", "โห... ขนลุกเลยครับ แล้วลูกค้าล่ะครับ?"), 0.9)
		speak(me, L("Gone. Just the dark house.", "หายไปแล้วครับ เหลือแต่บ้านมืด ๆ"), 1.0)
	else
		speak(me, L(("I was riding a lonely road near %s and saw a woman standing under a big tree."):format(at), ("ผมขี่ผ่านถนนเปลี่ยวแถว%s เห็นผู้หญิงยืนอยู่ใต้ต้นไม้ใหญ่ครับ"):format(at)), 1.1)
		speak(me, L("My engine just died. When I looked again... she was gone.", "เครื่องดับไปเฉย ๆ พอมองอีกที เธอหายไปแล้วครับ"), 1.2)
		speak(dj, L("Big trees by dark roads... best not to stop there.", "ต้นไม้ใหญ่ริมทางมืด ๆ ... อย่าจอดแวะนะครับ"), 0.9)
	end
	card.Visible = false
	local feel = Choice.ask({ icon = "📻", title = L("DJ Pong: how did you feel?", "ดีเจป๋อง: ตอนนั้นรู้สึกยังไงครับ?"),
		answers = { { L("😱 Scared stiff", "😱 กลัวจนขนลุก") }, { L("😎 Not scared at all", "😎 ไม่กลัวเลย") }, { L("😂 Still laughing", "😂 ขำ ๆ ครับ") } }, seconds = 20 })
	card.Visible = true
	if feel == 2 then
		speak(dj, L("A brave one! Ride safe, and maybe pay with real money next time, ghosts.", "ใจกล้ามากครับ! ขับขี่ปลอดภัยนะครับ ส่วนคุณผี คราวหน้าจ่ายเงินจริงด้วยนะ"), 1.4)
	elseif feel == 3 then
		speak(dj, L("Laughing at ghosts... I like this rider. Ride safe!", "ขำผีได้... ชอบไรเดอร์คนนี้ครับ ขับขี่ปลอดภัยนะครับ!"), 1.4)
	else
		speak(dj, L(("Anyone near %s tonight, take care... thanks for calling!"):format(at), ("ใครอยู่แถว%s คืนนี้ระวังกันด้วยนะครับ... ขอบคุณที่โทรมาเล่าครับ!"):format(at)), 1.4)
	end
	g:Destroy()
	Feedback.coins()
	Feedback.toast(L("📻 +฿100 +XP · your story is on the City Feed", "📻 +฿100 +XP · เรื่องของคุณขึ้นฟีดเมืองแล้ว"), "good")
end

---------------------------------------------------------------------------------------------------
-- 1. the ghost customer (server Notify "scene" kind "ghost")
---------------------------------------------------------------------------------------------------
local function customerScene(info)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or typeof(info.pos) ~= "Vector3" then return end
	local folder = Instance.new("Folder")
	folder.Name = "GoDashGhostProps"
	folder.Parent = Workspace
	local ignore = { char, folder }
	local here = root.Position
	local door = groundAt(info.pos, ignore)
	local dir = Vector3.new(door.X - here.X, 0, door.Z - here.Z)
	if dir.Magnitude < 1 then dir = root.CFrame.LookVector end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	-- she waits a step short of the door, facing you
	local spot = door - dir * 3
	local ghost = makeGhost()
	ghost:PivotTo(CFrame.lookAt(spot, spot - dir) * CFrame.new(0, 0.3, 0))
	ghost.Parent = folder
	-- the porch lamp that flickers
	local lampPart = part(folder, Vector3.new(0.6, 0.6, 0.6), CFrame.new(door + Vector3.new(0, 9, 0) + side * 2), Color3.fromRGB(255, 220, 160), Enum.PartType.Ball)
	lampPart.Material = Enum.Material.Neon
	local lamp = Instance.new("PointLight")
	lamp.Range = 22
	lamp.Brightness = 1.6
	lamp.Color = Color3.fromRGB(255, 214, 160)
	lamp.Parent = lampPart
	local flicker = true
	task.spawn(function()
		while flicker do
			lamp.Enabled = math.random() > 0.35
			lampPart.Transparency = lamp.Enabled and 0 or 0.8
			task.wait(0.05 + math.random() * 0.25)
		end
	end)
	scene(function(wait, say, cam)
		-- 1. from beside the bike: she is at the gate
		local eye = here - dir * 5 + side * 3.5 + Vector3.new(0, 4.2, 0)
		cam.CFrame = CFrame.lookAt(eye, spot + Vector3.new(0, 4.5, 0))
		cam.FieldOfView = 55
		tw(cam, 2.6, { CFrame = CFrame.lookAt(eye + dir * 3, spot + Vector3.new(0, 5, 0)) })
		say(L("Customer: ...thank you, dear...", "ลูกค้า: ...ขอบใจจ้ะ..."))
		if not wait(2.4) then return end
		-- 2. the money in your hand
		local camCf = CFrame.lookAt(here + Vector3.new(0, 4, 0), here + Vector3.new(0, 4, 0) + dir)
		cam.CFrame = camCf
		local note = part(folder, Vector3.new(1.6, 0.04, 0.8), camCf * CFrame.new(0, -0.6, -2.4) * CFrame.Angles(math.rad(60), 0, 0), Color3.fromRGB(150, 70, 160))
		say(L("The money she gave you...", "เงินที่ได้มา..."))
		if not wait(1.0) then return end
		note:Destroy()
		for i = 1, 3 do
			local leaf = part(folder, Vector3.new(0.9, 0.04, 0.5), camCf * CFrame.new((i - 2) * 0.5, -0.6, -2.4) * CFrame.Angles(math.rad(60), math.rad(i * 25), 0), Color3.fromRGB(130, 96, 50))
			tw(leaf, 1.4, { CFrame = leaf.CFrame * CFrame.new(0, -1.6, 0) * CFrame.Angles(0, math.rad(80), math.rad(40)) })
		end
		sting(nil, 1.6)
		say(L("...turned into dry leaves!?", "...กลายเป็นใบไม้แห้ง!?"))
		if not wait(1.6) then return end
		-- 3. look again: nobody there
		ghost.Parent = nil
		flicker = false
		lamp.Enabled = false
		lampPart.Transparency = 1
		cam.CFrame = CFrame.lookAt(eye + dir * 3, spot + Vector3.new(0, 5, 0))
		say(L("Huh... where did she go?", "เอ๊ะ... ลูกค้าหายไปไหน"))
		if not wait(1.8) then return end
		-- 4. right behind you (a short, mild fright)
		local lookBack = CFrame.lookAt(here + Vector3.new(0, 4.6, 0), here + Vector3.new(0, 4.6, 0) - dir)
		cam.CFrame = lookBack
		ghost.Parent = folder
		ghost:PivotTo(CFrame.lookAt(here - dir * 3.4, here) * CFrame.new(0, -1.2, 0))
		sting(nil, 0.42)
		Feedback.fovKick(-8, 0.25)
		say(L("😱 RUN!!!", "😱 หนีเร็ววว!!!"))
		wait(0.7)
	end)
	flicker = false
	folder:Destroy()
	task.spawn(radio)
end

---------------------------------------------------------------------------------------------------
-- 2. the figure under the tree (client-side, on dark lonely roads late at night)
---------------------------------------------------------------------------------------------------
local lastRoadside = -1e9
local roadsideNight = -1
local function roadsideScene(folder: Folder, ghost: Model, at: Vector3)
	local c = Drive.current()
	local chassis = c and c.chassis
	if not chassis then return end
	scene(function(wait, say, cam)
		Drive.stallUntil = os.clock() + 3
		local p = chassis.Position
		local to = Vector3.new(at.X - p.X, 0, at.Z - p.Z)
		if to.Magnitude < 1 then to = chassis.CFrame.LookVector end
		to = to.Unit
		local eye = p + Vector3.new(0, 5, 0) - to * 4
		cam.FieldOfView = 50
		cam.CFrame = CFrame.lookAt(eye, at + Vector3.new(0, 5, 0))
		tw(cam, 2.4, { CFrame = CFrame.lookAt(eye + to * 4, at + Vector3.new(0, 5.4, 0)) })
		say(L("...who is standing under that tree?!", "...ใครยืนอยู่ใต้ต้นไม้ตรงนั้น!?"))
		if not wait(2.2) then return end
		-- she turns toward you and lifts a hand
		local arm = ghost:FindFirstChild("ArmR") :: BasePart?
		if arm then tw(arm, 0.8, { CFrame = arm.CFrame * CFrame.new(0.4, 0.6, -0.6) * CFrame.Angles(0, 0, math.rad(-50)) }) end
		ghost:PivotTo(CFrame.lookAt(ghost:GetPivot().Position, Vector3.new(p.X, ghost:GetPivot().Position.Y, p.Z)))
		sting(nil, 0.5)
		say(L("The engine just died...", "เครื่องดับไปเฉย ๆ..."))
		if not wait(1.6) then return end
		fadeOut(ghost, 0.6)
		say(L("...and she is gone.", "...แล้วเธอก็หายไป"))
		wait(1.4)
	end)
	folder:Destroy()
	local ok = Net.call("City", "ghost_seen", "roadside")
	if ok then
		Feedback.toast(L("👻 +฿30 for the fright", "👻 +฿30 ค่าขวัญเสีย"), "good")
		task.spawn(radio)
	end
end

local function roadside()
	task.spawn(function()
		while true do
			task.wait(1)
			local c = Drive.current()
			-- Studio: Workspace attribute QaGhostRoad = true shows her on the next check, anywhere, any time
			local force = RunService:IsStudio() and Workspace:GetAttribute("QaGhostRoad") == true
			if c and c.chassis and enabled() and (force or (lateNight() and os.clock() - lastRoadside > 6 * 60 and roadsideNight ~= Workspace:GetAttribute("Day")))
				and not State.cutscene and not playing then
				local cf = c.chassis.CFrame
				local vel = c.chassis.AssemblyLinearVelocity
				local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
				local okUse, use = pcall(Map.landUse, cf.Position.X, cf.Position.Z)
				if force or (speed > 15 and okUse and (use == "rural" or use == "suburb") and math.random() < 1 / 45) then
					if force then Workspace:SetAttribute("QaGhostRoad", nil) end
					if speed < 1 then vel = cf.LookVector end
					lastRoadside = os.clock()
					roadsideNight = Workspace:GetAttribute("Day")
					local fwd = Vector3.new(vel.X, 0, vel.Z).Unit
					local left = Vector3.new(fwd.Z, 0, -fwd.X)
					local folder = Instance.new("Folder")
					folder.Name = "GoDashGhostProps"
					folder.Parent = Workspace
					local at = groundAt(cf.Position + fwd * 85 + left * 11, { player.Character, c.model, folder })
					-- a big dark tree, and her under it
					part(folder, Vector3.new(14, 1.6, 1.6), CFrame.new(at + left * 3 + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 32, 26), Enum.PartType.Cylinder)
					part(folder, Vector3.new(16, 11, 16), CFrame.new(at + left * 3 + Vector3.new(0, 16, 0)), Color3.fromRGB(16, 30, 18), Enum.PartType.Ball)
					local ghost = makeGhost()
					ghost:PivotTo(CFrame.lookAt(at, at + fwd) * CFrame.new(0, 0.3, 0))
					ghost.Parent = folder
					-- wait for the rider to come close (or ride away)
					local t0 = os.clock()
					local fired = false
					while os.clock() - t0 < 30 do
						task.wait(0.1)
						local c2 = Drive.current()
						if not c2 or not c2.chassis then break end
						local d = (c2.chassis.Position - at).Magnitude
						if d < 26 then fired = true break end
						if d > 260 then break end
					end
					if fired and not State.cutscene then roadsideScene(folder, ghost, at) else folder:Destroy() end
				end
			end
		end
	end)
end

function Ghosts.start()
	Net.listen("Notify", function(kind, p)
		if kind == "scene" and type(p) == "table" and p.kind == "ghost" then
			task.spawn(customerScene, p)
		end
	end)
	roadside()
end

return Ghosts
