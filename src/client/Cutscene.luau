-- Short scenes for the things a rider really does: getting off to eat or drink, collecting the
-- order from the shop, handing it to the customer (with a wai). Until 2026-11-16 these were a
-- button press and a toast.
--
-- The server says when (Notify "scene", { kind = "eat" | "drink" | "pickup" | "deliver", pos, name });
-- everything here is local show: the real character is hidden for a few seconds and a copy of it
-- (the "actor") walks from the bike to the spot and plays the gesture, while the camera cuts to a
-- side shot and then a closer one. Any key or tap skips. The real character and vehicle never
-- move, so nothing the server tracks changes.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local RiderPose = require(Shared.RiderPose)
local Vehicles = require(Shared.Config.Vehicles)
local Drive = require(script.Parent.Drive)
local Feed = require(script.Parent.Feed)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)
local Peds = require(script.Parent.Peds)
local Replay = require(script.Parent.Replay)

local Cutscene = {}
local player = Players.LocalPlayer
local L = Lang.pick
local rad = math.rad
-- Roblox's current R15 walk; its steps match about 6.4 studs/s at normal height. (Until 2026-11-17 the
-- old 507777826 walk was sped up, so everyone's legs went twice as fast as they moved: it looked
-- like jogging.)
local WALK_ANIM = "rbxassetid://913402848"
local WALK_NATURAL = 6.4
local WALK_SPEED = 6.6
local function walkRate(hum: Humanoid, speed: number): number
	return speed / (WALK_NATURAL * math.max(0.6, hum.HipHeight / 2))
end
local playing = false
local gui, barTop, barBottom, caption, fade

local function joint(model: Model, part: string, name: string): any
	local p = model:FindFirstChild(part)
	local m = p and p:FindFirstChild(name)
	if m and (m:IsA("Motor6D") or m:IsA("AnimationConstraint")) then return m end
	return nil
end

local function ground(pos: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
	return hit and hit.Position or Vector3.new(pos.X, 0.3, pos.Z)
end

local function clear(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return Workspace:Raycast(from, to - from, params) == nil
end

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "GoDashCutscene"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 80
	gui.Enabled = false
	local function bar(anchorY: number)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0, anchorY)
		f.Position = UDim2.fromScale(0, anchorY)
		f.Size = UDim2.fromScale(1, 0)
		f.Parent = gui
		return f
	end
	barTop, barBottom = bar(0), bar(1)
	caption = Instance.new("TextLabel")
	caption.BackgroundTransparency = 1
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.Position = UDim2.new(0.5, 0, 1, -18)
	caption.Size = UDim2.new(0.9, 0, 0, 34)
	caption.Font = Enum.Font.GothamBold
	caption.TextSize = 22
	caption.TextColor3 = Color3.new(1, 1, 1)
	caption.TextStrokeTransparency = 0.4
	caption.Text = ""
	caption.ZIndex = 3
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

local function tween(inst: Instance, t: number, props: { [string]: any })
	TweenService:Create(inst, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

-- A local copy of the player's character that this script moves (no physics, no scripts).
local function makeActor(char: Model): (Model?, BasePart?, Humanoid?, number)
	local was = char.Archivable
	char.Archivable = true
	local ok, actor = pcall(function() return char:Clone() end)
	char.Archivable = was
	if not ok or not actor then return nil, nil, nil, 0 end
	actor.Name = "GoDashActor"
	for _, d in ipairs(actor:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ForceField") or d:IsA("BillboardGui") or d:IsA("Sound") or d:IsA("Weld") and d.Name == "SeatWeld" then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false; d.CanTouch = false; d.CanQuery = false
			d.LocalTransparencyModifier = 0
			d.AssemblyLinearVelocity = Vector3.zero
		end
	end
	local hum = actor:FindFirstChildOfClass("Humanoid")
	local root = actor:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then actor:Destroy(); return nil, nil, nil, 0 end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.Sit = false
	pcall(function() hum.EvaluateStateMachine = false end)
	root.Anchored = true
	return actor, root, hum, hum.HipHeight + root.Size.Y / 2
end

local function prop(kind: string): BasePart
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	if kind == "bag" then
		p.Size = Vector3.new(1.5, 1.5, 0.9)
		p.Color = Color3.fromRGB(28, 168, 84)
	elseif kind == "cup" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.95, 0.5, 0.5) -- a tall cup: the cylinder's axis (X) is stood upright when held
		p.Color = Color3.fromRGB(240, 150, 70)
	else
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.32, 0.95, 0.95)
		p.Color = Color3.fromRGB(240, 236, 226)
	end
	return p
end

-- Resting. "rest": the server has sat the rider on a bench; the camera comes round to the front and
-- moves in slowly. "sleep": a copy of the rider lies down on the bed (the real one keeps standing
-- beside it, hidden for the scene) and the picture dims. Both show a rising "Zzz".
local function restScene(kind: string, info: any)
	local char = player.Character
	local realRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local realHum = char and char:FindFirstChildOfClass("Humanoid")
	local cam = Workspace.CurrentCamera
	if not char or not realRoot or not realHum or not cam then return end
	if not gui then buildGui() end
	playing = true
	State.cutscene = true
	local sleep = kind == "sleep"
	local ignore: { Instance } = { char }

	-- who the camera looks at, and where
	local actor: Model? = nil
	local subject: Vector3
	local facing: Vector3
	local hidden = {}
	if sleep then
		local a, aroot = makeActor(char)
		local pos = (info and typeof(info.pos) == "Vector3") and info.pos or realRoot.Position
		local dir = (info and typeof(info.dir) == "Vector3" and info.dir.Magnitude > 0.1) and Vector3.new(info.dir.X, 0, info.dir.Z).Unit or Vector3.zAxis
		if a and aroot then
			actor = a
			table.insert(ignore, a)
			-- the top of the mattress under the middle of the bed
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = ignore
			local hit = Workspace:Raycast(pos + Vector3.new(0, 7, 0), Vector3.new(0, -12, 0), params)
			local top = hit and hit.Position.Y or pos.Y + 1.4
			-- flat on the back, head toward the head of the bed (-dir is the bed's back)
			local at = Vector3.new(pos.X, top + aroot.Size.Z / 2, pos.Z) - dir * 1.2 -- the root is at the hips: slide up so the feet stay on the bed
			aroot.CFrame = CFrame.lookAt(at, at + dir) * CFrame.Angles(rad(90), 0, 0)
			a.Parent = Workspace
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Decal") then table.insert(hidden, d) end
			end
			subject = at
		else
			subject = realRoot.Position
		end
		facing = dir:Cross(Vector3.yAxis) -- film from the side of the bed
	else
		-- give the server a moment to seat the rider
		local t0 = os.clock()
		while not realHum.SeatPart and os.clock() - t0 < 0.8 do task.wait(0.05) end
		subject = realRoot.Position
		facing = Vector3.new(realRoot.CFrame.LookVector.X, 0, realRoot.CFrame.LookVector.Z).Unit
	end

	local right = facing:Cross(Vector3.yAxis)
	local function eyeAt(dist: number, sideways: number, up: number): Vector3
		for _, s in ipairs({ 1, -1 }) do
			local eye = subject + facing * dist + right * sideways * s + Vector3.new(0, up, 0)
			if clear(subject + Vector3.new(0, 1, 0), eye, ignore) then return eye end
		end
		return subject + facing * (dist * 0.6) + Vector3.new(0, up + 4, 0)
	end
	local from = sleep and eyeAt(11, 4, 7) or eyeAt(11, 5, 2.6)
	local to = sleep and eyeAt(8, 2, 5.5) or eyeAt(6.5, 2.6, 1.4)
	local look = subject + Vector3.new(0, sleep and 0.2 or 0.6, 0)

	local huds = {}
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g ~= gui and g.Name:sub(1, 6) == "GoDash" then
			g.Enabled = false
			table.insert(huds, g)
		end
	end
	local oldType, oldFov = cam.CameraType, cam.FieldOfView
	local length = sleep and 5 or 4.4
	local started = os.clock()
	local skip = false
	local skipConn = UserInputService.InputBegan:Connect(function(input)
		if os.clock() - started < 0.6 then return end
		local ty = input.UserInputType
		if ty == Enum.UserInputType.Keyboard or ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch or ty == Enum.UserInputType.Gamepad1 then skip = true end
	end)
	RunService:BindToRenderStep("GoDashCutscene", Enum.RenderPriority.Last.Value + 2, function()
		local k = math.clamp((os.clock() - started) / length, 0, 1)
		k = k * k * (3 - 2 * k)
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(from:Lerp(to, k), look)
		cam.FieldOfView = 55
		for _, d in ipairs(hidden) do (d :: any).LocalTransparencyModifier = 1 end
	end)

	-- "Zzz" rising beside the head
	local zPart = Instance.new("Part")
	zPart.Anchored = true; zPart.CanCollide = false; zPart.CanQuery = false; zPart.CanTouch = false
	zPart.Transparency = 1
	zPart.Size = Vector3.new(0.2, 0.2, 0.2)
	zPart.CFrame = CFrame.new(subject + Vector3.new(0, sleep and 1.4 or 2.6, 0))
	zPart.Parent = Workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(90, 60)
	bb.AlwaysOnTop = true
	bb.Parent = zPart
	local z = Instance.new("TextLabel")
	z.BackgroundTransparency = 1
	z.Size = UDim2.fromScale(1, 1)
	z.Text = "💤"
	z.TextScaled = true
	z.Parent = bb
	task.spawn(function()
		while zPart.Parent do
			bb.StudsOffset = Vector3.new(0.6, 0, 0)
			z.TextTransparency = 0
			TweenService:Create(bb, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(1.6, 2.4, 0) }):Play()
			TweenService:Create(z, TweenInfo.new(1.5), { TextTransparency = 1 }):Play()
			task.wait(1.55)
		end
	end)

	caption.Text = sleep and L("Sleeping… strength comes back fast", "นอนหลับพักผ่อน… แรงกลับมาเร็ว") or L("Taking a rest on the bench", "นั่งพักเหนื่อยที่ม้านั่ง")
	caption.TextTransparency = 1
	gui.Enabled = true
	fade.BackgroundTransparency = 1
	tween(barTop, 0.3, { Size = UDim2.fromScale(1, 0.1) })
	tween(barBottom, 0.3, { Size = UDim2.fromScale(1, 0.12) })
	tween(caption, 0.4, { TextTransparency = 0 })
	if sleep then tween(fade, 2.5, { BackgroundTransparency = 0.55 }) end -- eyes closing

	while os.clock() - started < length and not skip do task.wait(0.05) end

	skipConn:Disconnect()
	tween(fade, 0.2, { BackgroundTransparency = 0 })
	task.wait(0.22)
	RunService:UnbindFromRenderStep("GoDashCutscene")
	for _, d in ipairs(hidden) do
		if d.Parent then (d :: any).LocalTransparencyModifier = 0 end
	end
	zPart:Destroy()
	if actor then actor:Destroy() end
	cam.CameraType = oldType
	cam.FieldOfView = oldFov
	for _, g in ipairs(huds) do
		if g.Parent then g.Enabled = true end
	end
	tween(barTop, 0.25, { Size = UDim2.fromScale(1, 0) })
	tween(barBottom, 0.25, { Size = UDim2.fromScale(1, 0) })
	tween(fade, 0.3, { BackgroundTransparency = 1 })
	playing = false
	State.cutscene = false
	task.delay(0.35, function()
		if not playing then gui.Enabled = false end
	end)
end

-- Ride-hailing. The rider stays on the vehicle; a copy of the passenger's avatar (info.ped) walks.
-- "board": from the kerb (info.pos) to the side of the vehicle; it fades as the seated passenger the
-- server adds appears on the seat (info.seat). "alight": from beside the seat to the door (info.pos),
-- then a wai to the rider. info.side / info.fwd = the vehicle's right / forward, info.car = a car.
local PAX_WALK = 7 -- studs per second; PassengerService waits for the same walk
local function passengerScene(kind: string, info: any)
	local store = ReplicatedStorage:FindFirstChild("GoDashModels")
	local template = store and info and info.ped and store:FindFirstChild(info.ped)
	local cam = Workspace.CurrentCamera
	if not template or not cam or typeof(info.seat) ~= "Vector3" or typeof(info.pos) ~= "Vector3" then return end
	if not gui then buildGui() end
	playing = true
	State.cutscene = true
	local char = player.Character
	local ignore: { Instance } = { char }
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then table.insert(ignore, vehicles) end
	local npcs = Workspace:FindFirstChild("NPCs")
	if npcs then table.insert(ignore, npcs) end

	-- the passenger
	local actor = template:Clone()
	actor.Name = "GoDashActor"
	RiderPose.relaxArms(actor)
	local hum = actor:FindFirstChildOfClass("Humanoid")
	local root = actor:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then actor:Destroy(); playing = false; State.cutscene = false; return end
	for _, d in ipairs(actor:GetDescendants()) do
		if d:IsA("BasePart") then d.CanCollide = false; d.CanTouch = false; d.CanQuery = false
		elseif d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") then d:Destroy() end
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	pcall(function() hum.EvaluateStateMachine = false end)
	root.Anchored = true
	table.insert(ignore, actor)
	local height = hum.HipHeight + root.Size.Y / 2

	-- the path
	local side = typeof(info.side) == "Vector3" and Vector3.new(info.side.X, 0, info.side.Z).Unit or Vector3.xAxis
	local fwd = typeof(info.fwd) == "Vector3" and Vector3.new(info.fwd.X, 0, info.fwd.Z).Unit or Vector3.zAxis
	local seat = info.seat
	local out = info.car and 5.2 or 2.6
	local kerb = Vector3.new(info.pos.X, seat.Y, info.pos.Z)
	local sx = ((kerb - seat):Dot(side) >= 0) and 1 or -1
	local doorPt = seat + side * sx * out
	local a, b
	if kind == "board" then
		a, b = kerb, doorPt
		if (a - b).Magnitude > 28 then a = b + (a - b).Unit * 28 end
	else
		a, b = doorPt, kerb
		if (b - a).Magnitude > 14 then b = a + (b - a).Unit * 14 end
		if (b - a).Magnitude < 4 then b = a + side * sx * 6 end
	end
	a = ground(a, ignore); b = ground(b, ignore)
	local look = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	look = look.Magnitude > 0.1 and look.Unit or fwd
	local pos = a
	local function place()
		local at = pos + Vector3.new(0, height, 0)
		root.CFrame = CFrame.lookAt(at, at + look)
	end
	place()
	actor.Parent = Workspace

	-- camera: beside the path, framing the walker and the vehicle
	local mid = ((a + b) / 2):Lerp(seat, 0.3) + Vector3.new(0, 2.4, 0)
	local perp = Vector3.new(-look.Z, 0, look.X)
	local camCf
	for _, s in ipairs({ 1, -1 }) do
		for _, dist in ipairs({ 15, 10, 7 }) do
			local eye = mid + perp * s * dist + Vector3.new(0, 4, 0) - look * 3
			if clear(mid, eye, ignore) then camCf = CFrame.lookAt(eye, mid) break end
		end
		if camCf then break end
	end
	camCf = camCf or CFrame.lookAt(mid + Vector3.new(0, 12, 0) - look * 10, mid)
	local huds = {}
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g ~= gui and g.Name:sub(1, 6) == "GoDash" then
			g.Enabled = false
			table.insert(huds, g)
		end
	end
	local oldType, oldFov = cam.CameraType, cam.FieldOfView
	local started = os.clock()
	local skip = false
	local skipConn = UserInputService.InputBegan:Connect(function(input)
		if os.clock() - started < 0.6 then return end
		local ty = input.UserInputType
		if ty == Enum.UserInputType.Keyboard or ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch or ty == Enum.UserInputType.Gamepad1 then skip = true end
	end)
	RunService:BindToRenderStep("GoDashCutscene", Enum.RenderPriority.Last.Value + 2, function()
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = camCf
		cam.FieldOfView = 60
	end)
	caption.Text = (kind == "board" and L("Your passenger is getting on", "ผู้โดยสารกำลังขึ้นรถ") or L("Your passenger is getting off", "ผู้โดยสารลงรถ"))
		.. (info.name and (" · " .. Lang.t(info.name)) or "")
	caption.TextTransparency = 1
	gui.Enabled = true
	fade.BackgroundTransparency = 1
	tween(barTop, 0.3, { Size = UDim2.fromScale(1, 0.1) })
	tween(barBottom, 0.3, { Size = UDim2.fromScale(1, 0.12) })
	tween(caption, 0.4, { TextTransparency = 0 })

	local ok, err = pcall(function()
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = hum
		local walk
		pcall(function()
			local anim = Instance.new("Animation")
			anim.AnimationId = WALK_ANIM
			walk = animator:LoadAnimation(anim)
			walk.Looped = true
			walk:Play(0.15)
			walk:AdjustSpeed(walkRate(hum, PAX_WALK))
		end)
		local dist = (b - a).Magnitude
		local walked = 0
		while walked < dist and not skip do
			local dt = RunService.RenderStepped:Wait()
			walked = math.min(dist, walked + PAX_WALK * dt)
			pos = a:Lerp(b, dist > 0 and walked / dist or 1)
			place()
		end
		if walk then walk:Stop(0.2) end
		pos = b
		if skip then return end
		if kind == "board" then
			-- turn to face the way the vehicle faces and climb on: the seated passenger takes over
			look = fwd
			place()
			task.wait(0.35)
			for _, d in ipairs(actor:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Decal") then
					TweenService:Create(d, TweenInfo.new(0.35), { LocalTransparencyModifier = 1 }):Play()
				end
			end
			-- a closer look at the vehicle with its passenger on it
			task.wait(0.5)
			local focus = seat + Vector3.new(0, 1.6, 0)
			local eye = seat + fwd * 7 + side * sx * 5 + Vector3.new(0, 2.4, 0)
			if clear(focus, eye, ignore) then camCf = CFrame.lookAt(eye, focus) end
			local t0 = os.clock()
			while os.clock() - t0 < 1.8 and not skip do task.wait(0.05) end
		else
			-- face the rider and give a wai
			local toward = Vector3.new(seat.X - pos.X, 0, seat.Z - pos.Z)
			if toward.Magnitude > 0.1 then look = toward.Unit end
			place()
			local J = {
				rs = joint(actor, "RightUpperArm", "RightShoulder"), ls = joint(actor, "LeftUpperArm", "LeftShoulder"),
				re = joint(actor, "RightLowerArm", "RightElbow"), le = joint(actor, "LeftLowerArm", "LeftElbow"),
				waist = joint(actor, "UpperTorso", "Waist"), neck = joint(actor, "Head", "Neck"),
			}
			local t = 0
			while t < 1.6 and not skip do
				local dt = RunService.RenderStepped:Wait()
				t += dt
				local k = math.clamp(t / 0.4, 0, 1)
				if J.rs then J.rs.Transform = CFrame.Angles(rad(42 * k), 0, rad(-30 * k)) end
				if J.ls then J.ls.Transform = CFrame.Angles(rad(42 * k), 0, rad(30 * k)) end
				if J.re then J.re.Transform = CFrame.Angles(rad(112 * k), 0, 0) end
				if J.le then J.le.Transform = CFrame.Angles(rad(112 * k), 0, 0) end
				if J.waist then J.waist.Transform = CFrame.Angles(rad(-13 * k), 0, 0) end
				if J.neck then J.neck.Transform = CFrame.Angles(rad(-10 * k), 0, 0) end
			end
			Feedback.good()
		end
	end)
	if not ok then warn("[Cutscene] " .. tostring(err)) end

	skipConn:Disconnect()
	tween(fade, 0.18, { BackgroundTransparency = 0 })
	task.wait(0.2)
	RunService:UnbindFromRenderStep("GoDashCutscene")
	actor:Destroy()
	cam.CameraType = oldType
	cam.FieldOfView = oldFov
	for _, g in ipairs(huds) do
		if g.Parent then g.Enabled = true end
	end
	tween(barTop, 0.25, { Size = UDim2.fromScale(1, 0) })
	tween(barBottom, 0.25, { Size = UDim2.fromScale(1, 0) })
	tween(fade, 0.3, { BackgroundTransparency = 1 })
	playing = false
	State.cutscene = false
	task.delay(0.35, function()
		if not playing then gui.Enabled = false end
	end)
end

-- Thrown off in a hard crash (owner, 2026-11-17: "a cutscene when the vehicle crashes hard and you fly
-- off it"). Drive calls this (Drive.onCrash) when one physics step loses a lot of speed. A copy of the
-- rider flies on in the direction of travel, arms and legs flailing, tumbling, in slow motion at first;
-- it may bounce once, slides and lies still with stars over the head. Then the real rider stands up
-- where the copy came down, off the vehicle and a little dizzy; the vehicle stays where it hit.
-- info = { dir = Vector3, speed = number, at = Vector3, model = Model, car = boolean }
local function dust(pos: Vector3)
	for i = 1, 7 do
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = Color3.fromRGB(196, 186, 168)
		p.Transparency = 0.45
		local a = math.rad(i * 51)
		local start = pos + Vector3.new(math.cos(a), 0.2, math.sin(a)) * 0.6
		p.Size = Vector3.new(0.9, 0.9, 0.9)
		p.CFrame = CFrame.new(start)
		p.Parent = Workspace
		TweenService:Create(p, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(2.6, 2.6, 2.6), Transparency = 1, CFrame = CFrame.new(start + Vector3.new(math.cos(a) * 1.6, 0.8, math.sin(a) * 1.6)),
		}):Play()
		task.delay(0.75, function() p:Destroy() end)
	end
end

local function dizzy(head: BasePart?, seconds: number)
	if not head then return end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(70, 40)
	bb.StudsOffset = Vector3.new(0, 1.7, 0)
	bb.AlwaysOnTop = false
	bb.Adornee = head
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = "💫"
	t.TextScaled = true
	t.Parent = bb
	bb:SetAttribute("NoTranslate", true)
	bb.Parent = head
	task.spawn(function()
		local t0 = os.clock()
		while bb.Parent and os.clock() - t0 < seconds do
			local dt = RunService.RenderStepped:Wait()
			t.Rotation = (t.Rotation + dt * 220) % 360
		end
		bb:Destroy()
	end)
end

local function crashScene(info: any)
	local char = player.Character
	local realRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local realHum = char and char:FindFirstChildOfClass("Humanoid")
	local cam = Workspace.CurrentCamera
	if not char or not realRoot or not realHum or not cam then return end
	if not gui then buildGui() end
	local Y = Vector3.yAxis
	local actor, aroot, _, height = makeActor(char)
	if not actor or not aroot then return end
	playing = true
	State.cutscene = true -- Drive holds the vehicle where it stopped
	local vehicle = info and info.model
	local ignore: { Instance } = { char, actor }
	if vehicle then table.insert(ignore, vehicle) end
	for _, n in ipairs({ "NPCs", "Vehicles", "Traffic", "GoDashLocalTraffic", "GoDashPedestrians", "GoDashDogs", "GoDashGPS" }) do
		local f = Workspace:FindFirstChild(n)
		if f then table.insert(ignore, f) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local function groundAt(p: Vector3): number?
		local hit = Workspace:Raycast(p + Y * 3, Vector3.new(0, -16, 0), params)
		return hit and hit.Position.Y or nil
	end

	local dir = (info and typeof(info.dir) == "Vector3") and Vector3.new(info.dir.X, 0, info.dir.Z) or Vector3.zero
	if dir.Magnitude < 0.1 then dir = Vector3.new(realRoot.CFrame.LookVector.X, 0, realRoot.CFrame.LookVector.Z) end
	if dir.Magnitude < 0.1 then dir = Vector3.zAxis end
	dir = dir.Unit
	local side = dir:Cross(Y)
	local speed = math.clamp(tonumber(info and info.speed) or 24, 10, 80)
	local car = info and info.car == true

	-- the real rider stays on the seat for now, hidden; the copy does the flying
	local hidden = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then table.insert(hidden, d) end
	end
	local J = {
		rs = joint(actor, "RightUpperArm", "RightShoulder"), ls = joint(actor, "LeftUpperArm", "LeftShoulder"),
		rh = joint(actor, "RightUpperLeg", "RightHip"), lh = joint(actor, "LeftUpperLeg", "LeftHip"),
		neck = joint(actor, "Head", "Neck"),
	}
	local pose = { rs = CFrame.identity, ls = CFrame.identity, rh = CFrame.identity, lh = CFrame.identity, neck = CFrame.identity }
	local pos = realRoot.Position + Y * (car and 2.6 or 1.1)
	local vel = dir * math.clamp(speed * 0.55, 12, 30) + Y * math.clamp(8 + speed * 0.22, 10, 19)
	local spin, spinRate = 0, math.clamp(speed * 0.22, 5, 10)
	local rollSign = math.random() < 0.5 and -1 or 1
	local G = 75
	local phase = "fly"
	local bounced = false
	local slideDir, slideV = dir, 0
	local restT = 0
	local bodyCf = CFrame.lookAt(pos, pos + dir)
	aroot.CFrame = bodyCf
	actor.Parent = Workspace

	-- camera: from the open side, a little behind, following the body
	local camSide = 1
	for _, sg in ipairs({ 1, -1 }) do
		if clear(pos, pos + side * sg * 15 + Y * 5, ignore) then camSide = sg break end
	end
	local camPos = pos + side * camSide * 15 + Y * 5.5 - dir * 7
	local shakeT = 0.45
	local huds = {}
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g ~= gui and g.Name:sub(1, 6) == "GoDash" then
			g.Enabled = false
			table.insert(huds, g)
		end
	end
	local oldType, oldFov = cam.CameraType, cam.FieldOfView
	local started = os.clock()
	local skip = false
	local skipConn = UserInputService.InputBegan:Connect(function(input)
		if os.clock() - started < 1.0 then return end
		local ty = input.UserInputType
		if ty == Enum.UserInputType.Keyboard or ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch or ty == Enum.UserInputType.Gamepad1 then skip = true end
	end)
	RunService:BindToRenderStep("GoDashCutscene", Enum.RenderPriority.Last.Value + 2, function(rdt)
		local want = pos + side * camSide * (phase == "rest" and 10 or 15) + Y * (phase == "rest" and 6.5 or 5.5) - dir * (phase == "rest" and 2 or 6)
		camPos = camPos:Lerp(want, math.min(1, rdt * 3.5))
		local cf = CFrame.lookAt(camPos, pos + Y * 0.4)
		if shakeT > 0 then
			shakeT -= rdt
			local a = shakeT / 0.45
			cf *= CFrame.new(math.random() * 0.5 * a - 0.25 * a, math.random() * 0.5 * a - 0.25 * a, 0) * CFrame.Angles(0, 0, (math.random() - 0.5) * 0.05 * a)
		end
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = cf
		cam.FieldOfView = 60
		for _, d in ipairs(hidden) do (d :: any).LocalTransparencyModifier = 1 end
	end)
	-- the hit: a white flash and the rider hitting the vehicle
	local flash = Instance.new("Frame")
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 0.3
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 4
	flash.Parent = gui
	TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	task.delay(0.5, function() flash:Destroy() end)
	Feedback.play("bodyHit", 0.75, 1, 0.5)
	-- (2026-11-19) the rider's "oof" and the vehicle grinding on the road as it goes down
	Feedback.play(math.random() < 0.5 and "grunt" or "grunt2", 0.55, 0.95 + math.random() * 0.15, 0.3)
	Feedback.play("scrape", 0.42, 1.05, 0.3)
	caption.Text = (info and type(info.caption) == "string" and info.caption) or L("💥 Hard crash! Thrown off the vehicle", "💥 ชนแรง! ปลิวลงจากรถ") -- client/SpeedBumps brings its own
	caption.TextTransparency = 1
	gui.Enabled = true
	fade.BackgroundTransparency = 1
	tween(barTop, 0.25, { Size = UDim2.fromScale(1, 0.1) })
	tween(barBottom, 0.25, { Size = UDim2.fromScale(1, 0.12) })
	tween(caption, 0.4, { TextTransparency = 0 })

	local ok, err = pcall(function()
		while not skip do
			local rdt = RunService.RenderStepped:Wait()
			local el = os.clock() - started
			if el > 6 then break end
			-- slow motion right after the hit, back to normal speed in the air
			local ts = el < 0.45 and 0.3 or math.min(1, 0.3 + (el - 0.45) * 2.2)
			local dt = math.min(rdt, 1 / 30) * ts
			if phase == "fly" then
				vel -= Y * (G * dt)
				local h = Vector3.new(vel.X, 0, vel.Z)
				if h.Magnitude > 0.5 then
					local hit = Workspace:Raycast(pos, h.Unit * (h.Magnitude * dt + 1.3), params)
					if hit and hit.Normal.Y < 0.6 then
						-- a wall: bounce off it
						local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
						n = n.Magnitude > 0.1 and n.Unit or -h.Unit
						vel = vel - n * (2 * vel:Dot(n))
						vel = Vector3.new(vel.X * 0.35, vel.Y, vel.Z * 0.35)
						pos = Vector3.new(hit.Position.X, pos.Y, hit.Position.Z) + n * 1.3
						Feedback.play("bump", 0.6, 0.9, 0.2)
					end
				end
				pos += vel * dt
				spin += spinRate * dt
				bodyCf = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(-spin, 0, rollSign * 0.5 * math.sin(spin * 0.5))
				local gy = groundAt(pos)
				if gy and vel.Y < 0 and pos.Y - gy < 1.0 then
					pos = Vector3.new(pos.X, gy + 1.0, pos.Z)
					dust(Vector3.new(pos.X, gy, pos.Z))
					if not bounced and vel.Y < -16 then
						bounced = true
						vel = Vector3.new(vel.X * 0.55, -vel.Y * 0.3, vel.Z * 0.55)
						spinRate *= 0.5
						Feedback.play("bodyFall2", 0.7, 1, 0.2)
					else
						phase = "slide"
						Feedback.play("scrape", 0.2, 0.62, 0.3) -- the body skidding on the road
						local hv = Vector3.new(vel.X, 0, vel.Z)
						slideDir = hv.Magnitude > 0.5 and hv.Unit or dir
						slideV = math.min(hv.Magnitude * 0.7, 18)
						Feedback.play("bodyFall", 0.85, 1, 0.2)
					end
				elseif not gy and el > 2.5 then
					break -- fell off the map: end the scene here (the rider stands up by the vehicle)
				end
				-- arms and legs flailing
				local w = el * 13
				pose.rs = CFrame.Angles(rad(140 + 25 * math.sin(w)), 0, rad(15))
				pose.ls = CFrame.Angles(rad(140 + 25 * math.sin(w + 1.7)), 0, rad(-15))
				pose.rh = CFrame.Angles(rad(-25 + 25 * math.sin(w * 0.8)), 0, rad(10))
				pose.lh = CFrame.Angles(rad(-25 + 25 * math.sin(w * 0.8 + 2)), 0, rad(-10))
			elseif phase == "slide" then
				slideV = math.max(0, slideV - 28 * dt)
				local step = slideDir * slideV * dt
				local hit = slideV > 0.2 and Workspace:Raycast(pos, slideDir * (slideV * dt + 1.2), params)
				if hit and hit.Normal.Y < 0.6 then slideV = 0 else pos += step end
				local gy = groundAt(pos)
				if gy then pos = Vector3.new(pos.X, gy + 0.6, pos.Z) end
				-- flat on the back, feet the way it was sliding
				local lie = CFrame.lookAt(pos, pos + slideDir) * CFrame.Angles(rad(90), 0, 0)
				bodyCf = bodyCf:Lerp(lie, math.min(1, dt * 9))
				bodyCf = bodyCf - bodyCf.Position + pos
				-- (the pose is kept in our own table: an Animator may reset Transform between frames)
				local k = math.min(1, dt * 8)
				pose.rs = pose.rs:Lerp(CFrame.Angles(0, 0, rad(75)), k)
				pose.ls = pose.ls:Lerp(CFrame.Angles(0, 0, rad(-75)), k)
				pose.rh = pose.rh:Lerp(CFrame.Angles(0, 0, rad(14)), k)
				pose.lh = pose.lh:Lerp(CFrame.Angles(0, 0, rad(-14)), k)
				if slideV <= 0 then
					phase = "rest"
					dizzy(actor:FindFirstChild("Head") :: BasePart?, 3)
				end
			else
				restT += rdt
				bodyCf = bodyCf:Lerp(CFrame.lookAt(pos, pos + slideDir) * CFrame.Angles(rad(90), 0, 0), math.min(1, rdt * 6))
				pose.neck = CFrame.Angles(0, rad(25 * math.sin(restT * 2.2)), 0) -- shaking the head clear
				if restT > 1.7 then break end
			end
			aroot.CFrame = bodyCf
			for name, j in pairs(J) do j.Transform = pose[name] end
		end
	end)
	if not ok then warn("[Cutscene] crash: " .. tostring(err)) end

	skipConn:Disconnect()
	tween(fade, 0.2, { BackgroundTransparency = 0 })
	task.wait(0.22)
	-- the real rider gets off and stands where the copy came down (or beside the vehicle)
	local restPos = pos
	local gy = groundAt(restPos)
	if not gy or (restPos - realRoot.Position).Magnitude > 120 then
		restPos = realRoot.Position + side * 4
		gy = groundAt(restPos)
	end
	realHum.Sit = false
	pcall(function() realHum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
	local t1 = os.clock()
	while realHum.SeatPart and os.clock() - t1 < 1 do task.wait() end
	local stand = Vector3.new(restPos.X, (gy or restPos.Y) + height + 0.15, restPos.Z)
	local vp = vehicle and vehicle.PrimaryPart and vehicle.PrimaryPart.Position
	local face = vp and Vector3.new(vp.X, stand.Y, vp.Z) or (stand - dir)
	if (face - stand).Magnitude < 0.5 then face = stand - dir end
	pcall(function()
		char:PivotTo(CFrame.lookAt(stand, face))
		realRoot.AssemblyLinearVelocity = Vector3.zero
	end)
	RunService:UnbindFromRenderStep("GoDashCutscene")
	for _, d in ipairs(hidden) do
		if d.Parent then (d :: any).LocalTransparencyModifier = 0 end
	end
	actor:Destroy()
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = oldFov
	local _ = oldType
	for _, g in ipairs(huds) do
		if g.Parent then g.Enabled = true end
	end
	tween(barTop, 0.25, { Size = UDim2.fromScale(1, 0) })
	tween(barBottom, 0.25, { Size = UDim2.fromScale(1, 0) })
	tween(fade, 0.35, { BackgroundTransparency = 1 })
	dizzy(char:FindFirstChild("Head") :: BasePart?, 3)
	Feedback.toast(L("🤕 You're OK. Walk back to your vehicle and press F", "🤕 ไม่เป็นไรนะ เดินกลับไปขึ้นรถ (กด F)"), "bad")
	local feedKey = (info and type(info.feed) == "string" and info.feed) or "crash"
	task.delay(2.5, function() Feed.post(feedKey, { pos = restPos }, true) end)
	playing = false
	State.cutscene = false
	task.delay(0.4, function()
		if not playing then gui.Enabled = false end
	end)
end

-- Pulled over (owner, 2026-11-16: "there must be a cutscene when you are fined or run a red light").
-- info = { reason = "checkpoint" | "redlight", amount }. The vehicle brakes to a stop (State.cutscene
-- holds it), a police officer walks up to the rider (the kerb side on a two-wheeler, the driver's
-- window on the right of a car), holds out the ticket, and the ticket card shows the charge and fine.
local function ticketCard(reason: string, amount: number, n: number?, limit: number?, waived: boolean?, insured: number?): Frame
	local ins = (insured or 0) > 0 and not waived
	local card = Instance.new("Frame")
	card.Name = "Ticket"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.74, 0.46)
	card.Size = UDim2.fromOffset(280, (n and limit) and 196 or 176)
	card.BackgroundColor3 = Color3.fromRGB(250, 248, 240)
	card.Rotation = -3
	card.ZIndex = 4
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 10); corner.Parent = card
	local claim = reason:sub(1, 4) == "hit_" -- a damage claim after an accident (client/Accident), not a police ticket
	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 40)
	band.BackgroundColor3 = waived and Color3.fromRGB(40, 150, 80) or (ins and Color3.fromRGB(30, 100, 190)) or (claim and Color3.fromRGB(214, 110, 20) or Color3.fromRGB(190, 28, 36))
	band.ZIndex = 4
	band.Parent = card
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 10); bc.Parent = band
	local function text(parent: Instance, s: string, y: number, h: number, size: number, color: Color3, font: Enum.Font)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(14, y)
		t.Size = UDim2.new(1, -28, 0, h)
		t.Text = s
		t.TextSize = size
		t.TextColor3 = color
		t.Font = font
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextWrapped = true
		t.ZIndex = 5
		t.Parent = parent
		return t
	end
	text(band, waived and L("🤝 THEY LET IT GO", "🤝 คู่กรณีไม่เอาเรื่อง") or (ins and L("🛡 INSURANCE CLAIM", "🛡 เคลมประกัน")) or (claim and L("🧾 DAMAGE CLAIM", "🧾 ใบเรียกค่าเสียหาย") or L("🚔 TRAFFIC TICKET", "🚔 ใบสั่ง · TRAFFIC TICKET")), 0, 40, 18, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
	local CHARGE = {
		redlight = L("Ran a red light", "ฝ่าสัญญาณไฟแดง"), sidewalk = L("Riding on the pavement", "ขับขี่บนทางเท้า"),
		nolicence = L("No driving licence", "ไม่มีใบอนุญาตขับขี่"), nohelmet = L("Riding without a helmet", "ไม่สวมหมวกกันน็อก"),
		hit_ped = L("Ran into a pedestrian", "ชนคนเดินถนน"), hit_car = L("Crashed into another vehicle", "ชนรถคันอื่น"),
		zebra = L("Didn't stop at a zebra crossing", "ไม่หยุดให้คนข้ามทางม้าลาย"),
	}
	local charge = CHARGE[reason] or L("Stopped at a police checkpoint", "ถูกเรียกตรวจที่ด่านตำรวจ")
	text(card, claim and L("What happened", "เหตุ") or L("Charge", "ข้อหา"), 48, 16, 12, Color3.fromRGB(120, 120, 128), Enum.Font.GothamMedium)
	text(card, charge, 64, 24, 18, Color3.fromRGB(30, 30, 36), Enum.Font.GothamBold)
	text(card, reason == "hit_ped" and L("Hospital bill", "ค่ารักษา") or (claim and L("Repair bill", "ค่าซ่อม") or L("Fine", "ค่าปรับ")), 96, 16, 12, Color3.fromRGB(120, 120, 128), Enum.Font.GothamMedium)
	if waived then
		text(card, L("฿0 · settled, no bill", "฿0 · ยอมความ ไม่ต้องจ่าย"), 110, 34, 24, Color3.fromRGB(28, 120, 60), Enum.Font.GothamBlack)
	elseif ins then
		text(card, L(("Insurer pays ฿%d · you pay ฿%d"):format(insured, amount), ("ประกันจ่าย ฿%d · คุณจ่าย ฿%d"):format(insured, amount)), 110, 34, 20, Color3.fromRGB(30, 100, 190), Enum.Font.GothamBlack)
	else
		text(card, amount > 0 and ("฿" .. amount) or L("No cash on you", "ไม่มีเงินสดติดตัว"), 110, 34, 30, Color3.fromRGB(190, 28, 36), Enum.Font.GothamBlack)
	end
	local TIP = {
		redlight = L("Stop at red. Turning left on red is allowed.", "ไฟแดงต้องหยุด (เลี้ยวซ้ายผ่านตลอดได้)"),
		sidewalk = L("Pavements are for feet. Officers patrol near the markets.", "ทางเท้ามีไว้เดิน แถวตลาดมีเทศกิจนะ"),
		nolicence = L("Take the test at the bus terminal (the queue is long).", "ไปสอบใบขับขี่ที่สถานีขนส่ง (คิวยาวหน่อย)"),
		nohelmet = L("Phone > Gear: the half helmet is free.", "มือถือ > อุปกรณ์ไรเดอร์ หมวกครึ่งใบใส่ได้ฟรี"),
		hit_ped = L("Slow down where people walk: markets, shops, crossings.", "ย่านตลาด หน้าร้าน ทางม้าลาย ขับช้าๆ นะ"),
		hit_car = L("Keep your distance and brake in time.", "เว้นระยะห่าง เบรกให้ทันนะ"),
		zebra = L("Someone on the crossing? Stop and let them cross.", "มีคนอยู่บนทางม้าลาย ต้องหยุดให้ข้ามก่อนนะ"),
	}
	local tip = TIP[reason] or L("Next time, go round the checkpoint.", "ครั้งหน้าลองขับหลบด่านดูนะ")
	text(card, tip, 146, 22, 12, Color3.fromRGB(90, 90, 98), Enum.Font.GothamMedium)
	-- (2026-11-19) the daily limit of server/FineService: how many of today's tickets this was
	if n and limit and not waived then
		text(card, claim and L(("Claim %d of %d today · after that they let it go"):format(n, limit), ("วันนี้ครั้งที่ %d/%d · เกินนี้คู่กรณีไม่เอาเรื่อง"):format(n, limit))
			or L(("Ticket %d of %d today · after that, warnings only"):format(n, limit), ("ใบสั่งวันนี้ %d/%d · ครบแล้วตำรวจแค่ตักเตือน"):format(n, limit)),
			168, 20, 12, Color3.fromRGB(28, 120, 60), Enum.Font.GothamBold)
	end
	-- the "paid" stamp lands a moment later
	local stamp = Instance.new("TextLabel")
	stamp.Name = "Stamp"
	stamp.BackgroundTransparency = 1
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.Position = UDim2.fromScale(0.78, 0.66)
	stamp.Size = UDim2.fromOffset(110, 40)
	stamp.Rotation = -14
	if ins then stamp.Position = UDim2.fromScale(0.8, 0.86) end -- (below the two amounts, not over them)
	stamp.Text = waived and L("SETTLED", "ยอมความ") or (ins and L("CLAIMED", "เคลมแล้ว")) or (amount > 0 and L("PAID", "ชำระแล้ว") or L("NOTED", "บันทึกแล้ว"))
	stamp.TextSize = 24
	stamp.Font = Enum.Font.GothamBlack
	stamp.TextColor3 = waived and Color3.fromRGB(28, 130, 60) or (ins and Color3.fromRGB(30, 100, 190)) or Color3.fromRGB(190, 28, 36)
	stamp.TextTransparency = 1
	stamp.ZIndex = 6
	local sk = Instance.new("UIStroke"); sk.Color = waived and Color3.fromRGB(28, 130, 60) or (ins and Color3.fromRGB(30, 100, 190)) or Color3.fromRGB(190, 28, 36); sk.Thickness = 2.5; sk.Transparency = 1
	sk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; sk.Parent = stamp
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 6); sc.Parent = stamp
	stamp.Parent = card
	card:SetAttribute("NoTranslate", true)
	return card
end

-- (2026-11-19) The police motorbike that pulls up behind you for a red light or the zebra crossing (owner:
-- "the other scenes too": the officer used to walk up from nowhere). A motorbike from the local traffic kit
-- with its rider in uniform, a POLICE box on the back and a light bar flashing red and blue.
local function policeBike(kind: string?): (Model?, Model?)
	local insurer = kind == "insurance" -- (2026-11-19) the insurance surveyor rides the same kind of bike
	local kit = ReplicatedStorage:FindFirstChild("GoDashTrafficKit")
	if not kit then return nil, nil end
	local bikes = {}
	for _, m in ipairs(kit:GetChildren()) do
		local d = m:IsA("Model") and Vehicles.ById[m.Name]
		if d and d.class == "bike" and not d.pedal and m:GetAttribute("HasRider") then table.insert(bikes, m) end
	end
	if #bikes == 0 then return nil, nil end
	local bike = bikes[math.random(1, #bikes)]:Clone()
	bike.Name = "GoDashPoliceBike"
	local rider
	for _, ch in ipairs(bike:GetChildren()) do
		if ch:IsA("Model") and (ch:FindFirstChildOfClass("Humanoid") or ch.Name == "Rider") then rider = ch end
	end
	if rider then
		if insurer then pcall(RiderPose.dress, rider, Color3.fromRGB(244, 246, 250), Color3.fromRGB(30, 40, 70)) else pcall(RiderPose.policeUniform, rider) end
	end
	for _, d in ipairs(bike:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
		elseif d:IsA("LuaSourceContainer") or d:IsA("Sound") then d:Destroy() end
	end
	local pv = bike:GetPivot()
	local size = bike:GetExtentsSize()
	local len = math.max(size.X, size.Z)
	local function part(sz: Vector3, cf: CFrame, col: Color3, mat: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		p.Size = sz
		p.CFrame = pv * cf
		p.Color = col
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Parent = bike
		return p
	end
	local box = part(Vector3.new(1.7, 1.3, 1.3), CFrame.new(0, 1.15, len * 0.36), Color3.fromRGB(244, 244, 240))
	part(Vector3.new(1.74, 0.28, 1.34), CFrame.new(0, 1.05, len * 0.36), insurer and Color3.fromRGB(30, 120, 210) or Color3.fromRGB(40, 70, 150))
	if insurer then
		bike:SetAttribute("Insurer", true)
		return bike, rider -- (no light bar for the surveyor)
	end
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(170, 130)
	sg.LightInfluence = 0.4
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 0.62)
	t.Text = insurer and "ประกันภัย\nINSURANCE" or "ตำรวจ\nPOLICE"
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(30, 50, 120)
	t.Parent = sg
	sg:SetAttribute("NoTranslate", true)
	sg.Parent = box
	part(Vector3.new(0.14, 0.9, 0.14), CFrame.new(0, 2.2, len * 0.36 + 0.4), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	local red = part(Vector3.new(0.55, 0.32, 0.36), CFrame.new(-0.32, 2.75, len * 0.36 + 0.4), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	local blue = part(Vector3.new(0.55, 0.32, 0.36), CFrame.new(0.32, 2.75, len * 0.36 + 0.4), Color3.fromRGB(40, 90, 255), Enum.Material.Neon)
	red.Name, blue.Name = "PoliceRed", "PoliceBlue"
	for _, p in ipairs({ red, blue }) do
		local l = Instance.new("PointLight")
		l.Range = 9 -- (16 / 3 washed the whole street pink)
		l.Brightness = 1.2
		l.Color = p.Color
		l.Parent = p
	end
	bike:SetAttribute("LightRed", true)
	return bike, rider
end

local function flashBar(bike: Model)
	local on = (os.clock() % 0.5) < 0.25
	for _, p in ipairs(bike:GetChildren()) do
		if p:IsA("BasePart") and (p.Name == "PoliceRed" or p.Name == "PoliceBlue") then
			local isRed = p.Name == "PoliceRed"
			local lit = (isRed and on) or (not isRed and not on)
			p.Transparency = lit and 0 or 0.75
			local l = p:FindFirstChildOfClass("PointLight")
			if l then l.Enabled = lit end
		end
	end
end

local function fineScene(info: any)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local vehicle = seat and seat.Parent
	local chassis = vehicle and (vehicle :: Model).PrimaryPart
	local store = ReplicatedStorage:FindFirstChild("GoDashModels")
	local cam = Workspace.CurrentCamera
	local Y = Vector3.yAxis
	-- an accident claim also finds you on foot (a hard crash threw you off): the claimant walks up to you
	local onFoot = false
	local footRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if (not seat or not chassis) and info and tostring(info.reason or ""):sub(1, 4) == "hit_" and footRoot and hum and hum.Health > 0 then
		onFoot, seat, chassis, vehicle = true, footRoot, footRoot, nil
	end
	if not seat or not chassis or not store or not cam then return end
	local peds = {}
	for _, m in ipairs(store:GetChildren()) do
		if m:IsA("Model") and m.Name:sub(1, 3) == "Ped" then table.insert(peds, m) end
	end
	if #peds == 0 then return end
	if not gui then buildGui() end
	playing = true
	State.cutscene = true -- Drive holds the vehicle: no throttle, handbrake on
	local sceneAt = os.clock()
	local reason = info and info.reason or "checkpoint"
	local amount = tonumber(info and info.amount) or 0
	local waived = info and info.waived == true
	local insured = tonumber(info and info.insured) or 0 -- (2026-11-19) what the insurer pays (server/InsuranceService)
	local surveyorBike: Model? = nil
	local claim = reason:sub(1, 4) == "hit_"
	local def = vehicle and Vehicles.ById[vehicle:GetAttribute("VehicleId") or ""]
	local car = def ~= nil and def.class == "car"
	-- the very person who was hit: borrowed from client/Peds right away, so they stay down where they fell
	local victim = reason == "hit_ped" and info.ped and Peds.borrow(info.ped) or nil
	local otherCar = claim and reason == "hit_car" and info.carModel and info.carModel.Parent and info.carModel or nil
	if otherCar and info.holdCar then pcall(info.holdCar, otherCar, 30) end
	local ignore: { Instance } = { char }
	if vehicle then table.insert(ignore, vehicle) end
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if onFoot and vehicles then table.insert(ignore, vehicles) end
	-- on foot: stand still for the talk (OnFoot would let the keys walk you away)
	local footWasAnchored = onFoot and footRoot and footRoot.Anchored
	if onFoot and footRoot then footRoot.AssemblyLinearVelocity = Vector3.zero; footRoot.Anchored = true end
	for _, n in ipairs({ "NPCs", "GoDashPedestrians", "GoDashLocalTraffic", "Traffic" }) do
		local f = Workspace:FindFirstChild(n)
		if f then table.insert(ignore, f) end
	end

	local huds = {}
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g ~= gui and g.Name:sub(1, 6) == "GoDash" then
			g.Enabled = false
			table.insert(huds, g)
		end
	end
	local oldType, oldFov = cam.CameraType, cam.FieldOfView
	local function frame(): (Vector3, Vector3, Vector3)
		local cf = chassis.CFrame
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		look = look.Magnitude > 0.1 and look.Unit or Vector3.zAxis
		return seat.Position, look, look:Cross(Y) -- seat, forward, right
	end
	local side = car and 1 or -1 -- +1 = right (a car's driver's window), -1 = left (the kerb)
	local camCf
	local fov = 55
	local function follow()
		local sp, fwd, right = frame()
		local focus = sp + Vector3.new(0, 1.2, 0)
		for _, s in ipairs({ side, -side }) do
			local eye = sp + fwd * 10 + right * s * 7 + Vector3.new(0, 3.6, 0)
			if clear(focus, eye, ignore) then return CFrame.lookAt(eye, focus) end
		end
		return CFrame.lookAt(sp + fwd * 9 + Vector3.new(0, 6, 0), focus)
	end
	-- a shot of `at` from the open side, `dist` away (the first side with a clear view)
	local function shotOf(at: Vector3, across: Vector3, dist: number, up: number): CFrame
		local a = Vector3.new(across.X, 0, across.Z)
		a = a.Magnitude > 0.1 and a.Unit or Vector3.xAxis
		local perp = a:Cross(Y)
		for _, s in ipairs({ 1, -1 }) do
			local eye = at + perp * s * dist + a * 2 + Y * up
			if clear(at + Y * 1.5, eye, ignore) then return CFrame.lookAt(eye, at + Y * 1.4) end
		end
		return CFrame.lookAt(at + Y * (up + 6) + a * dist * 0.6, at + Y * 1.4)
	end
	camCf = follow()
	local started = os.clock()
	local skip = false
	local skipConn = UserInputService.InputBegan:Connect(function(input)
		if os.clock() - started < 1.2 then return end
		local ty = input.UserInputType
		if ty == Enum.UserInputType.Keyboard or ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch or ty == Enum.UserInputType.Gamepad1 then skip = true end
	end)
	local tracking = true
	local bike: Model? = nil -- the police motorbike, while it is in the scene
	RunService:BindToRenderStep("GoDashCutscene", Enum.RenderPriority.Last.Value + 2, function()
		if tracking then camCf = cam.CFrame:Lerp(follow(), 0.18) end
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = camCf
		cam.FieldOfView = fov
		if bike then flashBar(bike) end
	end)
	local function setCaption()
		caption.Text = (reason == "hit_ped" and (waived and L("🤝 You hit someone... they say it's OK", "🤝 ชนคนเดินถนน... แต่เขาไม่เอาเรื่อง")
				or L("🚑 You hit someone! They want the hospital bill", "🚑 ชนคนเดินถนน! เขาเดินมาเรียกค่ารักษา")))
			or (reason == "hit_car" and (waived and L("🤝 Crash! The other driver lets it go", "🤝 ชนรถคันอื่น! แต่คู่กรณีไม่เอาเรื่อง")
				or L("💥 Crash! The other driver wants the repair bill", "💥 ชนรถคันอื่น! คู่กรณีลงมาเรียกค่าซ่อม")))
			or (reason == "redlight" and L("🚦 Pulled over: you ran a red light", "🚦 ตำรวจเรียกจอด: ฝ่าไฟแดง"))
			or (reason == "zebra" and L("🚸 Pulled over: you didn't stop at the crossing", "🚸 ตำรวจเรียกจอด: ไม่หยุดให้คนข้ามทางม้าลาย"))
			or (reason == "sidewalk" and L("📢 Municipal officer: no riding on the pavement!", "📢 เทศกิจเรียก: ห้ามขี่บนทางเท้า!"))
			or (reason == "nolicence" and L("🚨 Checkpoint: no driving licence!", "🚨 ด่านตรวจ: ไม่มีใบขับขี่!"))
			or (reason == "nohelmet" and L("🪖 Checkpoint: no helmet!", "🪖 ด่านตรวจ: ไม่สวมหมวกกันน็อก!"))
			or L("🚨 Pulled over at a police checkpoint", "🚨 ตำรวจเรียกจอดที่ด่านตรวจ")
	end
	setCaption()
	caption.TextTransparency = 1
	gui.Enabled = true
	fade.BackgroundTransparency = 1
	tween(barTop, 0.3, { Size = UDim2.fromScale(1, 0.1) })
	tween(barBottom, 0.3, { Size = UDim2.fromScale(1, 0.12) })
	tween(caption, 0.4, { TextTransparency = 0 })
	Feedback.bad()

	local function waitFor(seconds: number)
		local t0 = os.clock()
		while os.clock() - t0 < seconds and not skip do RunService.RenderStepped:Wait() end
	end
	-- a short cut to black and back (moving the story on without showing every step)
	local function cut(fn: () -> ())
		tween(fade, 0.18, { BackgroundTransparency = 0 })
		task.wait(0.2)
		fn()
		tween(fade, 0.25, { BackgroundTransparency = 1 })
	end

	local actor, card
	local ownActor = true -- false: the actor is the borrowed pedestrian (handed back, not destroyed)
	local riderHidden = {} -- the other bike's rider, hidden while they are "off" it
	local standAt: Vector3? = nil
	local ok, err = pcall(function()
		-- brake to a stop
		local t0 = os.clock()
		while os.clock() - t0 < 3 do
			local v = chassis.AssemblyLinearVelocity
			if Vector3.new(v.X, 0, v.Z).Magnitude < 1.2 then break end
			if victim then Peds.place(victim, "lie", victim.pos, victim.look) end
			RunService.RenderStepped:Wait()
		end
		tracking = false

		-- 1. the CCTV replay of what happened (client/Replay): accidents, red lights, the crossing
		if not onFoot and (claim or reason == "redlight" or reason == "zebra") then
			local hitAt = tonumber(info.hitAt) or (sceneAt - 0.5)
			Replay.keepEvent(hitAt, claim and "claim" or reason) -- for "keep this moment" (client/ClipMode)
			local samples = Replay.take(hitAt - 3.3, hitAt + 1.3)
			if #samples >= 8 and not skip then
				tween(caption, 0.2, { TextTransparency = 1 })
				cut(function() end)
				Replay.play({
					samples = samples, hitAt = hitAt, chassis = chassis, ped = victim, car = otherCar,
					setCam = function(cf, f) camCf = cf; fov = f end,
					skip = function() return skip end,
				})
				fov = 55
				cut(function() camCf = follow() end)
				setCaption()
				tween(caption, 0.3, { TextTransparency = 0 })
			end
		end
		if skip then return end

		local sp, fwd, right = frame()
		local stand = ground(sp + right * side * (car and 4.6 or 2.6) + fwd * 0.6, ignore)
		standAt = stand
		local root: BasePart?, ahum: Humanoid?, height
		local from: Vector3
		local walkSpeed = 6
		local limp = false
		local still = false

		if victim then
			-- 2a. the person you hit, where they fell: they get up, a bit dazed, and limp over
			ownActor = false
			actor, root, ahum, height = victim.model, victim.root, victim.hum, victim.height
			local lie = victim.pos
			from = lie
			camCf = shotOf(lie, (sp - lie), 10, 4)
			Peds.place(victim, "lie", lie, victim.look)
			waitFor(0.8)
			if skip then return end
			local face = Vector3.new(sp.X - lie.X, 0, sp.Z - lie.Z)
			face = face.Magnitude > 0.1 and face.Unit or -fwd
			local lieCf = (root :: BasePart).CFrame
			local standCf = CFrame.lookAt(lie + Y * height, lie + Y * height + face)
			local sitCf = CFrame.lookAt(lie + Y * (height * 0.42), lie + Y * (height * 0.42) + face) * CFrame.Angles(rad(-28), 0, 0)
			dust(lie)
			Feedback.play("bump", 0.35, 0.8, 0.2)
			local g = 0
			while g < 1.5 and not skip do
				g += RunService.RenderStepped:Wait()
				local cf
				if g < 0.65 then
					local k = math.sin(math.clamp(g / 0.65, 0, 1) * math.pi / 2)
					cf = lieCf:Lerp(sitCf, k)
				else
					local k = math.clamp((g - 0.65) / 0.85, 0, 1)
					k = 1 - (1 - k) * (1 - k)
					cf = sitCf:Lerp(standCf, k) * CFrame.Angles(0, 0, math.sin(g * 9) * 0.06 * (1 - k)) -- unsteady
				end
				Peds.place(victim, "none", lie, face, 0, cf)
			end
			dizzy(actor:FindFirstChild("Head") :: BasePart?, 2.5)
			limp, walkSpeed = true, 3.3
		elseif otherCar then
			-- 2b. the other driver gets out of their own car (the driver's door is on the right here) or
			-- climbs off their motorbike, hazard lights on
			local pv = otherCar:GetPivot()
			local size = otherCar:GetExtentsSize()
			local isBike = otherCar:GetAttribute("HasRider") == true
			local door = pv.Position + pv.RightVector * ((isBike and -1 or 1) * (math.min(size.X, size.Z) / 2 + 1.3))
			if (door - sp).Magnitude < 55 then
				from = ground(door, ignore)
				if isBike then
					for _, d in ipairs(otherCar:GetDescendants()) do
						if d:IsA("BasePart") and d:FindFirstAncestorWhichIsA("Model") ~= otherCar then
							table.insert(riderHidden, d)
							d.LocalTransparencyModifier = 1
						end
					end
				end
				camCf = shotOf(from, pv.LookVector, 11, 4.5)
			else
				otherCar = nil
			end
		elseif reason == "redlight" or reason == "zebra" then
			-- 2c. a police motorbike pulls up behind you, lights flashing
			local b, rider = policeBike()
			if b then
				bike = b
				local back = sp - fwd * 7 + right * (car and -3.2 or -2.2)
				local startP = sp - fwd * 40 + right * (car and -3.2 or -2.2)
				local yOff = (b:GetAttribute("Y") or 2.4) - 0.3
				local function put(p: Vector3)
					local gp = ground(p, ignore)
					b:PivotTo(CFrame.lookAt(gp + Y * yOff, gp + Y * yOff + fwd))
				end
				put(startP)
				b.Parent = Workspace
				table.insert(ignore, b)
				local camEye = sp + fwd * 9 + right * (car and 6 or -6) + Y * 3.6
				if not clear(sp + Y * 1.5, camEye, ignore) then camEye = sp + fwd * 9 - right * (car and 6 or -6) + Y * 3.6 end
				if not clear(sp + Y * 1.5, camEye, ignore) then camEye = sp + fwd * 7 + Y * 8 end
				local tt = 0
				while tt < 2.6 and not skip do
					tt += RunService.RenderStepped:Wait()
					local k = 1 - (1 - math.clamp(tt / 2.6, 0, 1)) ^ 2.4
					local p = startP:Lerp(back, k)
					put(p)
					camCf = CFrame.lookAt(camEye, (p + sp) / 2 + Y * 1.4)
				end
				waitFor(0.35)
				-- the officer gets off on the kerb side
				if rider then
					for _, d in ipairs(rider:GetDescendants()) do
						if d:IsA("BasePart") then d.Transparency = 1 elseif d:IsA("Decal") then d.Transparency = 1 end
					end
				end
				from = ground(back + right * (car and -1.6 or -1.4), ignore)
			end
		end
		if skip then return end

		if not actor then
			-- the officer / a stranger: a figure from the avatar models (the claimant's own look if known)
			local who = claim and info.claimant and store:FindFirstChild(info.claimant)
			actor = (who and who:IsA("Model") and who or peds[math.random(1, #peds)]):Clone()
			actor.Name = claim and "GoDashClaimant" or "GoDashOfficer"
			if not claim then RiderPose.policeUniform(actor) end
			RiderPose.relaxArms(actor)
			ahum = actor:FindFirstChildOfClass("Humanoid")
			root = actor:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not ahum or not root then return end
			for _, d in ipairs(actor:GetDescendants()) do
				if d:IsA("BasePart") then d.CanCollide = false; d.CanTouch = false; d.CanQuery = false
				elseif d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") then d:Destroy() end
			end
			ahum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			pcall(function() ahum.EvaluateStateMachine = false end)
			root.Anchored = true
			height = ahum.HipHeight + root.Size.Y / 2
			if not from then from = ground(stand + fwd * 9 + right * side * 1.5, ignore) end
		end
		table.insert(ignore, actor)
		local rp = root :: BasePart
		local pos = from
		local look = Vector3.new(stand.X - from.X, 0, stand.Z - from.Z)
		look = look.Magnitude > 0.1 and look.Unit or -fwd
		local function place(cf: CFrame?)
			if victim then
				-- ("none" once they stand and talk: no idle animation, so the arm can hold out the bill)
				Peds.place(victim, limp and "walk" or (still and "none" or "idle"), pos, look, walkSpeed, cf)
			else
				local at = pos + Vector3.new(0, height, 0)
				rp.CFrame = cf or CFrame.lookAt(at, at + look)
			end
		end
		if ownActor then
			if otherCar then
				-- stepping out: up from the seat, looking round at you
				local out = Vector3.new(from.X - otherCar:GetPivot().Position.X, 0, from.Z - otherCar:GetPivot().Position.Z)
				out = out.Magnitude > 0.1 and out.Unit or look
				local at0 = from + Y * (height - 1.5)
				rp.CFrame = CFrame.lookAt(at0, at0 + out)
				actor.Parent = Workspace
				local g = 0
				while g < 0.6 and not skip do
					g += RunService.RenderStepped:Wait()
					local k = math.clamp(g / 0.6, 0, 1)
					local at = from + Y * (height - 1.5 * (1 - k))
					local l = out:Lerp(look, k)
					rp.CFrame = CFrame.lookAt(at, at + (l.Magnitude > 0.05 and l.Unit or look))
				end
				Feedback.play("tick", 0.4, 0.6, 0.1) -- the door
			else
				place()
				actor.Parent = Workspace
			end
		end

		-- 3. walk (or limp) over; a long way is shortened with a cut
		local walk
		if ownActor then
			local animator = (ahum :: Humanoid):FindFirstChildOfClass("Animator") or Instance.new("Animator")
			animator.Parent = ahum
			pcall(function()
				local anim = Instance.new("Animation")
				anim.AnimationId = WALK_ANIM
				walk = animator:LoadAnimation(anim)
				walk.Looped = true
				walk:Play(0.15)
				walk:AdjustSpeed(walkRate(ahum :: Humanoid, walkSpeed))
			end)
		end
		-- frame the walker and the rider together, from the side with a clear view
		local function twoShot()
			local mid = (pos + sp) / 2 + Vector3.new(0, 2.2, 0)
			local span = (pos - sp).Magnitude
			local across = Vector3.new(sp.X - pos.X, 0, sp.Z - pos.Z)
			across = across.Magnitude > 0.1 and across.Unit or fwd
			local perp = across:Cross(Y)
			for _, s in ipairs({ side, -side }) do
				local eye = mid + perp * s * (7 + span * 0.45) + across * 1.5 + Y * 2.6
				if clear(mid, eye, ignore) then return CFrame.lookAt(eye, mid) end
			end
			return CFrame.lookAt(mid + fwd * 8 + Y * 5, mid)
		end
		if not victim and not otherCar and not bike then camCf = twoShot() end
		local dist = (stand - from).Magnitude
		local walked = 0
		local phase = 0
		local cutDone = false
		local shotT = 0
		while walked < dist and not skip do
			local dt = RunService.RenderStepped:Wait()
			walked = math.min(dist, walked + walkSpeed * dt)
			pos = from:Lerp(stand, dist > 0 and walked / dist or 1)
			shotT += dt
			-- a long walk: a few steps, then a cut to them arriving
			if not cutDone and dist - walked > 9 and shotT > (limp and 2.4 or 1.8) and dist > 18 then
				cutDone = true
				cut(function()
					walked = math.max(walked, dist - 8)
					pos = from:Lerp(stand, walked / dist)
					place()
					camCf = twoShot()
				end)
			elseif shotT > 1.2 and (victim or otherCar or bike) and not cutDone and dist <= 18 then
				camCf = camCf:Lerp(twoShot(), math.min(1, dt * 2))
			end
			if limp then
				-- favouring one leg: a dip and a lean on every other step
				phase += dt * walkSpeed * 1.15
				local dip = math.max(0, math.sin(phase)) * 0.22
				local at = pos + Vector3.new(0, height - dip, 0)
				place(CFrame.lookAt(at, at + look) * CFrame.Angles(0, 0, math.sin(phase) * 0.09))
			else
				place()
			end
		end
		if walk then walk:Stop(0.2) end
		pos = stand
		local toRider = Vector3.new(sp.X - stand.X, 0, sp.Z - stand.Z)
		if toRider.Magnitude > 0.1 then look = toRider.Unit end
		limp, still = false, true
		place()
		camCf = (function()
			local mid = (stand + sp) / 2 + Vector3.new(0, 2.2, 0)
			for _, s in ipairs({ side, -side }) do
				local eye = mid + fwd * 9 + right * s * 6 + Vector3.new(0, 2.5, 0)
				if clear(mid, eye, ignore) then return CFrame.lookAt(eye, mid) end
			end
			return CFrame.lookAt(mid + fwd * 8 + Vector3.new(0, 5, 0), mid)
		end)()
		if skip then return end

		-- 4. what they say
		if claim then
			local lines
			if insured > 0 and not waived then
				lines = reason == "hit_ped" and {
					L("Ow... you have insurance? Fine, let them sort it out.", "โอ๊ย... มีประกันใช่ไหม งั้นให้ประกันจัดการเลย"),
					L("Lucky you're insured!", "ดีนะที่มีประกัน!"),
				} or {
					L("You're insured? OK, call them.", "มีประกันใช่ไหม โอเค เรียกประกันมาเลย"),
					L("Fine, let the insurance handle my car.", "ได้ ให้ประกันจัดการรถฉันละกัน"),
				}
			elseif waived then
				lines = reason == "hit_ped" and {
					L("It's OK, it's OK. I won't make a fuss. Just ride carefully!", "ไม่เป็นไรๆ ไม่เอาเรื่องหรอก แต่คราวหน้าขับดีๆ นะ"),
					L("Only a scrape. Never mind, but watch out!", "เจ็บนิดหน่อยเอง ไม่เป็นไร ระวังด้วยล่ะ"),
					L("I'm in a good mood today. Slow down, OK?", "วันนี้ใจดี ไม่เอาเรื่อง ขับช้าๆ หน่อยนะ"),
				} or {
					L("Just a little scratch. Forget it.", "รอยนิดเดียว ไม่เป็นไรหรอก ไม่เอาเรื่อง"),
					L("No worries, the insurance will cover it. Careful now!", "ไม่เป็นไรครับ ประกันจ่าย ขับระวังด้วยนะ"),
					L("You riders work hard. I'll let it go this time.", "เห็นว่าขับไรเดอร์เหนื่อยๆ ครั้งนี้ไม่เอาเรื่องนะ"),
				}
			else
				lines = reason == "hit_ped" and {
					L("Ow, my leg! Can't you see where you're going?!", "โอ๊ย ขาฉัน! ขับยังไงไม่ดูทางเลย!"),
					L("Pay for the hospital, or we go to the police!", "จ่ายค่ารักษามา ไม่งั้นไปโรงพัก!"),
					L("I was on the pavement! On the PAVEMENT!", "ฉันเดินอยู่ดีๆ นะ! ดีๆ เลย!"),
					L("The CCTV saw everything. Pay up!", "กล้องวงจรปิดถ่ายไว้หมดแล้วนะ จ่ายมา!"),
				} or {
					L("Look at my car! Who pays for this?!", "ดูรถฉันสิ! ใครจะจ่ายเนี่ย!"),
					L("Pay for the repair, or I call my insurance!", "จ่ายค่าซ่อมมา ไม่งั้นเรียกประกัน!"),
					L("Brand new! Two weeks old!", "รถเพิ่งออกมาสองอาทิตย์เองนะ!"),
					L("The camera got it all. It was you!", "กล้องจับได้หมดแล้ว คุณผิดชัดๆ!"),
				}
			end
			local head = actor:FindFirstChild("Head") :: BasePart?
			Feedback.bubble((head and head.Position or (pos + Vector3.new(0, 5, 0))) + Vector3.new(0, 1.6, 0), reason == "hit_ped" and L("Pedestrian", "คนเดินถนน") or L("Other driver", "คู่กรณี"),
				lines[math.random(1, #lines)])
		end
		-- 4b. insured (2026-11-19): the insurer's surveyor rides up behind and takes it from here
		if claim and insured > 0 and not waived then
			local sb, srider = policeBike("insurance")
			if sb then
				surveyorBike = sb
				local yOff = (sb:GetAttribute("Y") or 2.4) - 0.3
				local stop = sp - fwd * 8 + right * -side * 2.4
				local startP = sp - fwd * 42 + right * -side * 2.4
				local function put(p: Vector3)
					local gp = ground(p, ignore)
					sb:PivotTo(CFrame.lookAt(gp + Y * yOff, gp + Y * yOff + fwd))
				end
				put(startP)
				sb.Parent = Workspace
				table.insert(ignore, sb)
				local tt = 0
				while tt < 2.2 and not skip do
					tt += RunService.RenderStepped:Wait()
					put(startP:Lerp(stop, 1 - (1 - math.clamp(tt / 2.2, 0, 1)) ^ 2.4))
				end
				local shead = srider and srider:FindFirstChild("Head") :: BasePart?
				Feedback.bubble((shead and shead.Position or (stop + Y * 5)) + Vector3.new(0, 1.6, 0), L("Insurance surveyor", "พนักงานเคลมประกัน"),
					L("Good afternoon! Isan Safe Insurance. We'll take care of the other side.", "สวัสดีครับ อีสานเซฟประกันภัย เดี๋ยวทางเราดูแลคู่กรณีให้เองครับ"))
				waitFor(1.6)
			end
		end
		-- 5. hold out the ticket / the bill, or wave it off
		local rs = joint(actor, "RightUpperArm", "RightShoulder")
		local re = joint(actor, "RightLowerArm", "RightElbow")
		local slip
		if not waived then
			slip = Instance.new("Part")
			slip.Anchored = true; slip.CanCollide = false; slip.CanQuery = false; slip.CanTouch = false; slip.CastShadow = false
			slip.Size = Vector3.new(0.7, 0.04, 1.0)
			slip.Color = Color3.fromRGB(250, 248, 240)
			slip.Name = "GoDashSlip"
			slip.Parent = actor
		end
		local hand = actor:FindFirstChild("RightHand") :: BasePart?
		local t = 0
		card = ticketCard(reason, amount, tonumber(info and info.n), tonumber(info and info.limit), waived, insured)
		card.Position = UDim2.fromScale(0.74, 1.4)
		card.Parent = gui
		local hold = (RunService:IsStudio() and Workspace:GetAttribute("QaSceneHold")) and 14 or 4.4 -- QaSceneHold: keep the ticket up for screenshots
		while t < hold and not skip do
			local dt = RunService.RenderStepped:Wait()
			t += dt
			local k = math.clamp(t / 0.45, 0, 1)
			if waived then
				-- "never mind": a hand up, waving
				if rs then rs.Transform = CFrame.Angles(rad(150 * k), 0, rad(-12 * k)) end
				if re then re.Transform = CFrame.Angles(rad((25 + 20 * math.sin(t * 9)) * k), 0, 0) end
			else
				if rs then rs.Transform = CFrame.Angles(rad(70 * k), 0, 0) end
				if re then re.Transform = CFrame.Angles(rad(20 * k), 0, 0) end
				if hand and slip then slip.CFrame = hand.CFrame * CFrame.new(0, -0.45, -0.1) end
			end
			if t > 0.5 and card.Position.Y.Scale > 1 then
				TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.74, 0.46) }):Play()
				Feedback.play("tick", 0.6, 0.8, 0.1)
			end
			local stamp = card:FindFirstChild("Stamp") :: TextLabel?
			if t > 1.5 and stamp and stamp.TextTransparency > 0.5 then
				TweenService:Create(stamp, TweenInfo.new(0.15), { TextTransparency = 0 }):Play()
				local sk = stamp:FindFirstChildOfClass("UIStroke")
				if sk then TweenService:Create(sk, TweenInfo.new(0.15), { Transparency = 0 }):Play() end
				if waived then Feedback.good() else Feedback.coins() end
			end
		end
		if rs then rs.Transform = CFrame.identity end
		if re then re.Transform = CFrame.identity end
		if slip then slip:Destroy() end
	end)
	if not ok then warn("[Cutscene] fine: " .. tostring(err)) end

	skipConn:Disconnect()
	tween(fade, 0.18, { BackgroundTransparency = 0 })
	task.wait(0.2)
	RunService:UnbindFromRenderStep("GoDashCutscene")
	if victim then
		-- back to their own life, from where they stand now (or where they fell, after a skip)
		local p = victim.pos
		local away = standAt and Vector3.new(p.X - (standAt.X + 0), 0, p.Z - standAt.Z) or Vector3.zero
		Peds.giveBack(victim, p, away.Magnitude > 0.1 and away or nil)
	elseif actor and ownActor then
		actor:Destroy()
	end
	for _, d in ipairs(riderHidden) do
		if d.Parent then d.LocalTransparencyModifier = 0 end
	end
	if bike then bike:Destroy() end
	if surveyorBike then surveyorBike:Destroy() end
	if card then card:Destroy() end
	if onFoot then
		if footRoot and footRoot.Parent then footRoot.Anchored = footWasAnchored == true end
		cam.CameraType = Enum.CameraType.Custom
	else
		cam.CameraType = oldType
	end
	cam.FieldOfView = oldFov
	for _, g in ipairs(huds) do
		if g.Parent then g.Enabled = true end
	end
	tween(barTop, 0.25, { Size = UDim2.fromScale(1, 0) })
	tween(barBottom, 0.25, { Size = UDim2.fromScale(1, 0) })
	tween(fade, 0.3, { BackgroundTransparency = 1 })
	playing = false
	State.cutscene = false
	task.delay(0.35, function()
		if not playing then gui.Enabled = false end
	end)
end

---------------------------------------------------------------------------------------------------
-- Treatment at the hospital (2026-11-18, owner: injuries that add up need a doctor, "and a cutscene of
-- the wound being treated, more realism"). server/HealthService via ShopService "heal" sends
-- { amount, injury, pos = the door }. The queue ticket of a public hospital (and its long wait), a
-- nurse in white walking over, the wound cleaned and bandaged, the receipt. The rider leaves with
-- the bandages on for a couple of minutes.
---------------------------------------------------------------------------------------------------
local BANDAGE_SECONDS = 150

local function bandage(char: Model)
	for _, old in ipairs(char:GetDescendants()) do
		if old.Name == "GoDashBandage" then old:Destroy() end
	end
	local made = {}
	local function wrap(partName: string, size: Vector3, offset: CFrame)
		local p = char:FindFirstChild(partName) :: BasePart?
		if not p then return end
		local b = Instance.new("Part")
		b.Name = "GoDashBandage"
		b.Size = size
		b.Color = Color3.fromRGB(250, 250, 247)
		b.Material = Enum.Material.SmoothPlastic -- (Fabric read as dark grey knitwear in the first test)
		b.CanCollide = false; b.CanQuery = false; b.CanTouch = false; b.Massless = true; b.CastShadow = false
		b.CFrame = p.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = p, b
		w.Parent = b
		b.Parent = char
		table.insert(made, b)
	end
	local head = char:FindFirstChild("Head") :: BasePart?
	if head then
		-- a band round the forehead
		wrap("Head", Vector3.new(head.Size.X * 1.04, head.Size.Y * 0.2, head.Size.Z * 1.06), CFrame.new(0, head.Size.Y * 0.18, 0))
	end
	local arm = char:FindFirstChild("RightLowerArm") :: BasePart?
	if arm then wrap("RightLowerArm", arm.Size * Vector3.new(1.18, 0.5, 1.18), CFrame.new(0, -arm.Size.Y * 0.1, 0)) end
	local knee = char:FindFirstChild("LeftLowerLeg") :: BasePart?
	if knee then wrap("LeftLowerLeg", knee.Size * Vector3.new(1.16, 0.32, 1.16), CFrame.new(0, knee.Size.Y * 0.28, 0)) end
	task.delay(BANDAGE_SECONDS, function()
		for _, b in ipairs(made) do if b.Parent then b:Destroy() end end
	end)
end

local hospitalTitle = nil :: string? -- the hospital the scene is at (Khon Kaen Hospital or Srinagarind)
local function hospitalCard(): (Frame, (string, number, number, Color3, Enum.Font, number?) -> TextLabel)
	local card = Instance.new("Frame")
	card.Name = "Hospital"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.75, 1.4)
	card.Size = UDim2.fromOffset(270, 190)
	card.BackgroundColor3 = Color3.fromRGB(250, 252, 252)
	card.Rotation = 2
	card.ZIndex = 4
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 10); corner.Parent = card
	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 40)
	band.BackgroundColor3 = Color3.fromRGB(0, 132, 128)
	band.ZIndex = 4
	band.Parent = card
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 10); bc.Parent = band
	local function text(s: string, y: number, h: number, color: Color3, font: Enum.Font, size: number?): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(14, y)
		t.Size = UDim2.new(1, -28, 0, h)
		t.Text = s
		t.TextSize = size or 14
		t.TextColor3 = color
		t.Font = font
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextWrapped = true
		t.ZIndex = 5
		t.Parent = card
		return t
	end
	local title = text(hospitalTitle or L("🏥 KHON KAEN HOSPITAL", "🏥 โรงพยาบาลศูนย์ขอนแก่น"), 0, 40, Color3.new(1, 1, 1), Enum.Font.GothamBlack, 17)
	title.Parent = band
	card:SetAttribute("NoTranslate", true)
	return card, text
end

local function treatScene(info: any)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local cam = Workspace.CurrentCamera
	local store = ReplicatedStorage:FindFirstChild("GoDashModels")
	if not char or not root or not hum or not cam or hum.SeatPart then return end
	if not gui then buildGui() end
	playing = true
	State.cutscene = true
	local amount = tonumber(info and info.amount) or 0
	local injury = tonumber(info and info.injury) or 0
	hospitalTitle = (info and info.name) and ("🏥 " .. L(string.upper(tostring(info.name)), tostring(info.thai or info.name))) or nil
	local wasAnchored = root.Anchored
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	local huds = {}
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g ~= gui and g.Name:sub(1, 6) == "GoDash" then
			g.Enabled = false
			table.insert(huds, g)
		end
	end
	local oldType, oldFov = cam.CameraType, cam.FieldOfView
	local ignore: { Instance } = { char }
	for _, n in ipairs({ "NPCs", "Vehicles", "GoDashPedestrians", "GoDashLocalTraffic" }) do
		local f = Workspace:FindFirstChild(n)
		if f then table.insert(ignore, f) end
	end
	-- face the door; the nurse comes out of it
	local door = (info and typeof(info.pos) == "Vector3") and info.pos or (root.Position + root.CFrame.LookVector * 10)
	local toDoor = Vector3.new(door.X - root.Position.X, 0, door.Z - root.Position.Z)
	local fwd = toDoor.Magnitude > 0.5 and toDoor.Unit or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local right = fwd:Cross(Vector3.yAxis)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + fwd)
	local mid = root.Position + fwd * 2.5 + Vector3.new(0, 0.6, 0)
	local camCf = CFrame.lookAt(mid + right * 9 - fwd * 2 + Vector3.new(0, 3.2, 0), mid)
	for _, s in ipairs({ 1, -1 }) do
		local eye = mid + right * s * 9 - fwd * 2 + Vector3.new(0, 3.2, 0)
		if clear(mid, eye, ignore) then camCf = CFrame.lookAt(eye, mid) break end
	end
	RunService:BindToRenderStep("GoDashCutscene", Enum.RenderPriority.Last.Value + 2, function()
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = camCf
		cam.FieldOfView = 55
	end)
	local started = os.clock()
	local skip = false
	local skipConn = UserInputService.InputBegan:Connect(function(input)
		if os.clock() - started < 1.5 then return end
		local ty = input.UserInputType
		if ty == Enum.UserInputType.Keyboard or ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch or ty == Enum.UserInputType.Gamepad1 then skip = true end
	end)
	local function wait(t: number)
		local t0 = os.clock()
		while os.clock() - t0 < t and not skip do RunService.RenderStepped:Wait() end
	end
	gui.Enabled = true
	fade.BackgroundTransparency = 1
	tween(barTop, 0.3, { Size = UDim2.fromScale(1, 0.1) })
	tween(barBottom, 0.3, { Size = UDim2.fromScale(1, 0.12) })
	caption.Text = L("🏥 " .. tostring(info and info.name or "Khon Kaen Hospital") .. ": take a queue ticket and wait…",
		"🏥 " .. tostring(info and info.thai or "โรงพยาบาลศูนย์ขอนแก่น") .. " · รับบัตรคิวแล้วรอเรียก…")
	caption.TextTransparency = 1
	tween(caption, 0.4, { TextTransparency = 0 })

	local nurse, card
	local ok, err = pcall(function()
		-- 1. the queue: a long wait at a public hospital, told in seconds
		local text
		card, text = hospitalCard()
		card.Parent = gui
		TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.75, 0.46) }):Play()
		local ticket = math.random(180, 420)
		local ahead = math.random(24, 46)
		text(L("Queue ticket", "บัตรคิว"), 48, 16, Color3.fromRGB(110, 120, 124), Enum.Font.GothamMedium, 12)
		text(("A-%03d"):format(ticket), 62, 40, Color3.fromRGB(0, 110, 106), Enum.Font.GothamBlack, 34)
		local aheadL = text("", 104, 20, Color3.fromRGB(40, 44, 48), Enum.Font.GothamBold, 15)
		local waitL = text("", 128, 18, Color3.fromRGB(110, 120, 124), Enum.Font.GothamMedium, 12)
		local minutes = 0
		local tq = os.clock()
		while ahead > 0 and not skip do
			local dt = RunService.RenderStepped:Wait()
			if os.clock() - tq > 0.06 then
				tq = os.clock()
				ahead -= 1
				minutes += math.random(1, 3)
			end
			aheadL.Text = ahead > 0 and L(("%d people ahead of you"):format(ahead), ("รออีก %d คิว"):format(ahead)) or L("Your turn!", "ถึงคิวแล้ว!")
			waitL.Text = L(("⏳ waited %d h %02d min"):format(minutes // 60, minutes % 60), ("⏳ รอมาแล้ว %d ชม. %02d นาที"):format(minutes // 60, minutes % 60))
			local _ = dt
		end
		aheadL.Text = L("Your turn! Room 3", "ถึงคิวแล้ว! เชิญห้องตรวจ 3")
		Feedback.play("tick", 0.6, 1.1, 0.1)
		wait(0.9)
		if skip then return end
		-- 2. the nurse comes out
		local peds = {}
		if store then
			for _, m in ipairs(store:GetChildren()) do
				if m:IsA("Model") and m.Name:sub(1, 3) == "Ped" then table.insert(peds, m) end
			end
		end
		if #peds > 0 then
			nurse = peds[math.random(1, #peds)]:Clone()
			nurse.Name = "GoDashNurse"
			RiderPose.dress(nurse, Color3.fromRGB(248, 248, 246), Color3.fromRGB(240, 240, 238), Color3.fromRGB(250, 250, 250))
			RiderPose.relaxArms(nurse)
			local nhum = nurse:FindFirstChildOfClass("Humanoid")
			local nroot = nurse:FindFirstChild("HumanoidRootPart") :: BasePart?
			if nhum and nroot then
				for _, d in ipairs(nurse:GetDescendants()) do
					if d:IsA("BasePart") then d.CanCollide = false; d.CanTouch = false; d.CanQuery = false
					elseif d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") then d:Destroy() end
				end
				nhum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				pcall(function() nhum.EvaluateStateMachine = false end)
				nroot.Anchored = true
				-- a nurse's cap
				local nhead = nurse:FindFirstChild("Head") :: BasePart?
				if nhead then
					local capPart = Instance.new("Part")
					capPart.Size = Vector3.new(nhead.Size.X * 0.7, nhead.Size.Y * 0.18, nhead.Size.Z * 0.55)
					capPart.Color = Color3.new(1, 1, 1)
					capPart.Material = Enum.Material.SmoothPlastic
					capPart.CanCollide = false; capPart.CanQuery = false; capPart.CanTouch = false; capPart.Massless = true
					capPart.CFrame = nhead.CFrame * CFrame.new(0, nhead.Size.Y * 0.55, -nhead.Size.Z * 0.05)
					local w = Instance.new("WeldConstraint"); w.Part0, w.Part1 = nhead, capPart; w.Parent = capPart
					capPart.Parent = nurse
				end
				local height = nhum.HipHeight + nroot.Size.Y / 2
				local stand = ground(root.Position + fwd * 2.6, ignore)
				local from = ground(root.Position + fwd * 10 + right * 1.5, ignore)
				local look = (stand - from); look = Vector3.new(look.X, 0, look.Z).Unit
				local pos = from
				local function place()
					local at = pos + Vector3.new(0, height, 0)
					nroot.CFrame = CFrame.lookAt(at, at + look)
				end
				place()
				nurse.Parent = Workspace
				table.insert(ignore, nurse)
				local animator = nhum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
				animator.Parent = nhum
				local walk
				pcall(function()
					local anim = Instance.new("Animation")
					anim.AnimationId = WALK_ANIM
					walk = animator:LoadAnimation(anim)
					walk.Looped = true
					walk:Play(0.15)
					walk:AdjustSpeed(walkRate(nhum, 5))
				end)
				caption.Text = L("👩‍⚕️ Nurse: \"This way please. Let's clean that wound.\"", "👩‍⚕️ พยาบาล: \"เชิญค่ะ เดี๋ยวล้างแผลให้นะคะ\"")
				local dist = (stand - from).Magnitude
				local walked = 0
				while walked < dist and not skip do
					local dt = RunService.RenderStepped:Wait()
					walked = math.min(dist, walked + 5 * dt)
					pos = from:Lerp(stand, dist > 0 and walked / dist or 1)
					place()
				end
				if walk then walk:Stop(0.2) end
				pos = stand
				look = Vector3.new(root.Position.X - stand.X, 0, root.Position.Z - stand.Z).Unit
				place()
				if skip then return end
				-- 3. clean, medicine, bandage: the nurse's hands at work
				caption.Text = injury >= 60 and L("💉 Cleaned, stitched, a tetanus shot and bandaged", "💉 ล้างแผล เย็บแผล ฉีดยากันบาดทะยัก แล้วพันผ้า")
					or L("🩹 Cleaned, some medicine and a fresh bandage", "🩹 ล้างแผล ทายา แล้วพันผ้าให้ใหม่")
				local rs = joint(nurse, "RightUpperArm", "RightShoulder")
				local ls = joint(nurse, "LeftUpperArm", "LeftShoulder")
				local t = 0
				local banded = false
				while t < 3.2 and not skip do
					local dt = RunService.RenderStepped:Wait()
					t += dt
					local k = math.clamp(t / 0.4, 0, 1)
					local wob = math.sin(t * 9) * 0.12
					if rs then rs.Transform = CFrame.Angles(rad(62 * k) + wob, 0, 0) end
					if ls then ls.Transform = CFrame.Angles(rad(55 * k) - wob, 0, 0) end
					if t > 1.6 and not banded then
						banded = true
						bandage(char)
						Feedback.play("tick", 0.5, 0.9, 0.1)
					end
				end
				if not banded then bandage(char) end
				if rs then rs.Transform = CFrame.identity end
				if ls then ls.Transform = CFrame.identity end
			end
		else
			bandage(char)
		end
		if skip then return end
		-- 4. the receipt
		card:Destroy()
		card, text = hospitalCard()
		card.Position = UDim2.fromScale(0.75, 0.46)
		card.Parent = gui
		local medicine = math.max(0, amount - 30)
		text(L("Receipt", "ใบเสร็จรับเงิน"), 46, 16, Color3.fromRGB(110, 120, 124), Enum.Font.GothamMedium, 12)
		text(L("Gold card visit", "บัตรทอง (ค่าบริการ)") .. "   ฿30", 64, 18, Color3.fromRGB(40, 44, 48), Enum.Font.GothamBold, 14)
		text(L("Dressing + medicine", "ทำแผล + ค่ายา") .. "   ฿" .. medicine, 84, 18, Color3.fromRGB(40, 44, 48), Enum.Font.GothamBold, 14)
		text(L("Total", "รวม") .. "  ฿" .. amount, 108, 34, Color3.fromRGB(0, 110, 106), Enum.Font.GothamBlack, 28)
		text(L("Injury healed: 0. Ride carefully!", "แผลหายแล้ว · ขับขี่ปลอดภัยนะ"), 150, 30, Color3.fromRGB(90, 96, 100), Enum.Font.GothamMedium, 12)
		Feedback.coins()
		caption.Text = L("✅ Patched up. Mind the speed bumps!", "✅ ทำแผลเรียบร้อย ระวังลูกระนาดด้วยนะ")
		wait(2.6)
	end)
	if not ok then warn("[Cutscene] treat: " .. tostring(err)) end
	skipConn:Disconnect()
	if not char:FindFirstChild("GoDashBandage") then pcall(bandage, char) end
	tween(fade, 0.18, { BackgroundTransparency = 0 })
	task.wait(0.2)
	RunService:UnbindFromRenderStep("GoDashCutscene")
	if nurse then nurse:Destroy() end
	if card then card:Destroy() end
	if root.Parent then root.Anchored = wasAnchored == true end
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = oldFov
	local _ = oldType
	for _, g in ipairs(huds) do
		if g.Parent then g.Enabled = true end
	end
	tween(barTop, 0.25, { Size = UDim2.fromScale(1, 0) })
	tween(barBottom, 0.25, { Size = UDim2.fromScale(1, 0) })
	tween(fade, 0.3, { BackgroundTransparency = 1 })
	playing = false
	State.cutscene = false
	task.delay(0.35, function()
		if not playing then gui.Enabled = false end
	end)
end

-- kind: "eat" | "drink" | "pickup" | "deliver" | "rest" | "sleep" | "board" | "alight" | "fine" | "crash" | "treat"
function Cutscene.play(kind: string, info: any)
	if playing then return end
	if kind == "crash" then
		local ok, err = pcall(crashScene, info)
		if not ok then
			warn("[Cutscene] " .. tostring(err))
			RunService:UnbindFromRenderStep("GoDashCutscene")
			playing = false
			State.cutscene = false
			if gui then gui.Enabled = false end
			local cam = Workspace.CurrentCamera
			if cam then cam.CameraType = Enum.CameraType.Custom end
		end
		return
	end
	if kind == "treat" then
		local ok, err = pcall(treatScene, info)
		if not ok then
			warn("[Cutscene] " .. tostring(err))
			RunService:UnbindFromRenderStep("GoDashCutscene")
			playing = false
			State.cutscene = false
			if gui then gui.Enabled = false end
			local cam = Workspace.CurrentCamera
			if cam then cam.CameraType = Enum.CameraType.Custom end
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and root.Anchored then root.Anchored = false end
		end
		return
	end
	if kind == "fine" then
		local ok, err = pcall(fineScene, info)
		if not ok then
			warn("[Cutscene] " .. tostring(err))
			RunService:UnbindFromRenderStep("GoDashCutscene")
			playing = false
			State.cutscene = false
			if gui then gui.Enabled = false end
			local cam = Workspace.CurrentCamera
			if cam then cam.CameraType = Enum.CameraType.Custom end
			-- an on-foot claim anchors the character for the talk: never leave it frozen
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and root.Anchored then root.Anchored = false end
		end
		return
	end
	if kind == "board" or kind == "alight" then
		local ok, err = pcall(passengerScene, kind, info)
		if not ok then
			warn("[Cutscene] " .. tostring(err))
			RunService:UnbindFromRenderStep("GoDashCutscene")
			playing = false
			State.cutscene = false
			if gui then gui.Enabled = false end
			local cam = Workspace.CurrentCamera
			if cam then cam.CameraType = Enum.CameraType.Custom end
		end
		return
	end
	if kind == "rest" or kind == "sleep" then
		local ok, err = pcall(restScene, kind, info)
		if not ok then
			warn("[Cutscene] " .. tostring(err))
			RunService:UnbindFromRenderStep("GoDashCutscene")
			playing = false
			State.cutscene = false
			if gui then gui.Enabled = false end
			local cam = Workspace.CurrentCamera
			if cam then cam.CameraType = Enum.CameraType.Custom end
		end
		return
	end
	local char = player.Character
	local realRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local realHum = char and char:FindFirstChildOfClass("Humanoid")
	local cam = Workspace.CurrentCamera
	if not char or not realRoot or not realHum or not cam then return end
	if not gui then buildGui() end
	playing = true
	State.cutscene = true

	local actor, root, hum, height = makeActor(char)
	if not actor or not root or not hum then
		playing = false
		State.cutscene = false
		return
	end
	local ignore: { Instance } = { char, actor }
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then table.insert(ignore, vehicles) end
	local peds = Workspace:FindFirstChild("GoDashPedestrians")
	if peds then table.insert(ignore, peds) end
	local npcs = Workspace:FindFirstChild("NPCs")
	if npcs then table.insert(ignore, npcs) end

	-- where the scene happens: from beside the bike to just short of the shop door / the customer
	local here = realRoot.Position
	local target = (info and typeof(info.pos) == "Vector3") and info.pos or (here + realRoot.CFrame.RightVector * -7)
	local flat = Vector3.new(target.X - here.X, 0, target.Z - here.Z)
	if flat.Magnitude < 3 then flat = realRoot.CFrame.RightVector * -6 end
	local dir = flat.Unit
	local total = flat.Magnitude
	local stopDist = math.max(2.5, total - ((kind == "deliver" or kind == "pickup") and 4.8 or 3.4))
	local startDist = math.max(1.8, stopDist - 13) -- a long walk is cut short: the scene starts closer
	if stopDist - startDist < 2 then startDist = math.max(0, stopDist - 4) end
	local start = ground(here + dir * startDist, ignore)
	local stop = ground(here + dir * stopDist, ignore)
	local side = dir:Cross(Vector3.yAxis)

	-- camera: a side shot of the walk, then a closer three-quarter shot of the action
	-- Each shot tries a few places (either side, low then higher, near then nearer) and takes the
	-- first one with a clear line to the actor, so a parked bike or a wall is not in the way.
	local mid = (start + stop) / 2 + Vector3.new(0, 3, 0)
	local function shot(at: Vector3, lookAt: Vector3, dists: { number }, ups: { number }, back: number): CFrame
		for _, up in ipairs(ups) do
			for _, dist in ipairs(dists) do
				for _, s in ipairs({ 1, -1 }) do
					local eye = at + side * s * dist + Vector3.new(0, up, 0) - dir * back
					if clear(at, eye, ignore) and clear(at - Vector3.new(0, 2, 0), eye, ignore) then return CFrame.lookAt(eye, lookAt) end
				end
			end
		end
		local eye = at + Vector3.new(0, 11, 0) - dir * (back + 5)
		return CFrame.lookAt(eye, lookAt)
	end
	local shotA = shot(mid, mid, { 13, 9, 6 }, { 2.5, 5.5, 8.5 }, 4)
	-- eating happens sitting on a plastic stool at a little street table (2026-11-17: standing in the
	-- road flapping a hand at the face looked broken): the hips drop by the thigh's length
	local thighPart = actor:FindFirstChild("RightUpperLeg") :: BasePart?
	local shinPart = actor:FindFirstChild("RightLowerLeg") :: BasePart?
	local footPart = actor:FindFirstChild("RightFoot") :: BasePart?
	local thigh = thighPart and thighPart.Size.Y or 1.1
	local shin = (shinPart and shinPart.Size.Y or 1.0) + (footPart and footPart.Size.Y or 0.35)
	local seated = kind == "eat" and thighPart ~= nil
	local focus = stop + Vector3.new(0, height + 0.6 - (seated and thigh or 0), 0)
	local shotB
	local faceEye: Vector3? = nil -- eating / drinking: the rider turns three-quarters toward this camera
	if kind == "eat" or kind == "drink" then
		-- the first clear spot around the rider (ahead and to the side first), far enough back for the
		-- whole upper body and the table; the rider then turns to it, so the face is always in shot
		for _, c in ipairs({ dir + side, dir - side, side, -side, dir, side - dir, -side - dir, -dir }) do
			local u = c.Unit
			for _, dist in ipairs({ 7.8, 6.2 }) do
				local eye = focus + u * dist + Vector3.new(0, 1.3, 0)
				if clear(focus, eye, ignore) and clear(focus - Vector3.new(0, 1.6, 0), eye - Vector3.new(0, 1.4, 0), ignore) then faceEye = eye break end
			end
			if faceEye then break end
		end
		if faceEye then shotB = CFrame.lookAt(faceEye, focus - Vector3.new(0, 0.6, 0)) end
	end
	shotB = shotB or shot(focus, focus + dir * 1.2, { 5.5, 4 }, { 1.4, 3.6, 6 }, 5.5)

	local oldType, oldFov = cam.CameraType, cam.FieldOfView
	local camCf = shotA
	local hidden = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then table.insert(hidden, d) end
	end
	-- the game's own HUD steps aside for the scene
	local huds = {}
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g ~= gui and g.Name:sub(1, 6) == "GoDash" then
			g.Enabled = false
			table.insert(huds, g)
		end
	end
	local skip = false
	local t0 = os.clock()
	local skipConn = UserInputService.InputBegan:Connect(function(input)
		if os.clock() - t0 < 0.6 then return end
		local ty = input.UserInputType
		if ty == Enum.UserInputType.Keyboard or ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch or ty == Enum.UserInputType.Gamepad1 then skip = true end
	end)
	RunService:BindToRenderStep("GoDashCutscene", Enum.RenderPriority.Last.Value + 2, function()
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = camCf
		cam.Focus = camCf * CFrame.new(0, 0, -12)
		for _, d in ipairs(hidden) do (d :: any).LocalTransparencyModifier = 1 end
	end)

	local pos = start
	local look = dir
	local sink = 0 -- how far the hips are lowered (sitting)
	local function place()
		local at = pos + Vector3.new(0, height - sink, 0)
		root.CFrame = CFrame.lookAt(at, at + look)
	end
	place()
	actor.Parent = Workspace

	local held: BasePart? = nil
	local extras: { Instance } = {} -- stool, table, bowl, spoon, counter: removed with the actor
	local hand = actor:FindFirstChild("RightHand") :: BasePart?
	local J = {
		rs = joint(actor, "RightUpperArm", "RightShoulder"), re = joint(actor, "RightLowerArm", "RightElbow"),
		ls = joint(actor, "LeftUpperArm", "LeftShoulder"), le = joint(actor, "LeftLowerArm", "LeftElbow"),
		rw = joint(actor, "RightHand", "RightWrist"),
		waist = joint(actor, "UpperTorso", "Waist"), neck = joint(actor, "Head", "Neck"),
		rh = joint(actor, "RightUpperLeg", "RightHip"), lh = joint(actor, "LeftUpperLeg", "LeftHip"),
		rk = joint(actor, "RightLowerLeg", "RightKnee"), lk = joint(actor, "LeftLowerLeg", "LeftKnee"),
	}
	local function pose(m: any, x: number, y: number?, z: number?)
		if m then m.Transform = CFrame.Angles(x, y or 0, z or 0) end
	end
	local function relax()
		for _, m in pairs(J) do m.Transform = CFrame.identity end
	end
	-- Key poses in degrees, { joint = { x, y, z } }; joints left out stand straight. setPose blends two.
	local ZERO = { 0, 0, 0 }
	local function setPose(a: any, b: any?, k: number?)
		local w = k or 0
		w = w * w * (3 - 2 * w) -- ease in and out
		for key, m in pairs(J) do
			local pa = a[key] or ZERO
			local pb = (b and b[key]) or pa
			m.Transform = CFrame.Angles(rad(pa[1] + (pb[1] - pa[1]) * w), rad((pa[2] or 0) + ((pb[2] or 0) - (pa[2] or 0)) * w), rad((pa[3] or 0) + ((pb[3] or 0) - (pa[3] or 0)) * w))
		end
	end
	local function with(base: any, more: any): any
		local out = table.clone(base)
		for k, v in pairs(more) do out[k] = v end
		return out
	end
	local function localPart(size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?, material: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then p.Shape = shape end
		p.Parent = actor
		table.insert(extras, p)
		return p
	end
	local heldKind = "bag"
	-- Props stay upright in the world whatever the wrist is doing: a cup sits in the hand, a bag hangs under it.
	local function holdProp()
		if not (held and hand) then return end
		if heldKind == "cup" then
			held.CFrame = CFrame.new(hand.Position + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, rad(90))
		else
			local at = hand.Position - Vector3.new(0, 0.9, 0)
			held.CFrame = CFrame.lookAt(at, at + look)
		end
	end

	local names = {
		eat = L("Stopping for a meal", "แวะกินข้าว"), drink = L("Stopping for a drink", "แวะดื่มน้ำ"),
		pickup = L("Collecting the order", "รับอาหารจากร้าน"), deliver = L("Delivering the order", "ส่งอาหารให้ลูกค้า"),
	}
	local text = names[kind] or ""
	if info and info.item then text ..= " · " .. Lang.t(info.item) end
	if info and info.name and kind ~= "eat" and kind ~= "drink" then text ..= " · " .. Lang.t(info.name) end
	caption.Text = text
	caption.TextTransparency = 1
	gui.Enabled = true
	tween(barTop, 0.3, { Size = UDim2.fromScale(1, 0.1) })
	tween(barBottom, 0.3, { Size = UDim2.fromScale(1, 0.12) })
	tween(caption, 0.4, { TextTransparency = 0 })

	local function finish()
		skipConn:Disconnect()
		fade.BackgroundTransparency = 1
		tween(fade, 0.18, { BackgroundTransparency = 0 })
		task.wait(0.2)
		RunService:UnbindFromRenderStep("GoDashCutscene")
		for _, d in ipairs(hidden) do
			if d.Parent then (d :: any).LocalTransparencyModifier = 0 end
		end
		if held then held:Destroy() end
		actor:Destroy()
		cam.CameraType = oldType
		cam.FieldOfView = oldFov
		for _, g in ipairs(huds) do
			if g.Parent then g.Enabled = true end
		end
		tween(barTop, 0.25, { Size = UDim2.fromScale(1, 0) })
		tween(barBottom, 0.25, { Size = UDim2.fromScale(1, 0) })
		tween(fade, 0.3, { BackgroundTransparency = 1 })
		task.delay(0.35, function()
			if not playing then gui.Enabled = false end
		end)
		playing = false
		State.cutscene = false
	end

	local ok, err = pcall(function()
		-- 1. walk over
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = hum
		for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do tr:Stop(0) end
		relax()
		local walk
		pcall(function()
			local a = Instance.new("Animation")
			a.AnimationId = WALK_ANIM
			walk = animator:LoadAnimation(a)
			walk.Looped = true
			walk:Play(0.1)
			walk:AdjustSpeed(walkRate(hum, WALK_SPEED))
		end)
		if kind == "deliver" then
			held = prop("bag")
			held.Parent = actor
		end
		local dist = (stop - start).Magnitude
		local walked = 0
		while walked < dist and not skip do
			local dt = RunService.RenderStepped:Wait()
			walked = math.min(dist, walked + WALK_SPEED * dt)
			pos = start:Lerp(stop, dist > 0 and walked / dist or 1)
			place()
			holdProp()
		end
		if walk then walk:Stop(0.15) end
		pos = stop
		place()
		if skip then return end

		-- 2. the action, in a closer shot
		-- (2026-11-17 rework, owner: "the eating and pick-up moves are buggy, not real": one hand does
		-- the work, the other stays natural, every move eases in and out at a human pace)
		if faceEye then
			-- turn three-quarters toward the camera
			local toCam = Vector3.new(faceEye.X - stop.X, 0, faceEye.Z - stop.Z)
			if toCam.Magnitude > 0.5 then
				look = CFrame.Angles(0, rad(38), 0):VectorToWorldSpace(toCam.Unit)
				place()
			end
		end
		local right = look:Cross(Vector3.yAxis)
		local up = Vector3.yAxis
		local floorY = stop.Y
		local SIT = { rh = { 88, 0, 7 }, lh = { 88, 0, -7 }, rk = { -86 }, lk = { -86 } }
		if seated then
			-- a red plastic stool under the hips and a little steel table in front, a bowl and a spoon
			local stoolTop = math.max(0.8, shin - 0.42)
			localPart(Vector3.new(stoolTop, 1.5, 1.5), CFrame.new(stop + up * (stoolTop / 2)) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(205, 52, 44), Enum.PartType.Cylinder)
			local tableTop = stoolTop + 1.05
			local tc = stop + look * 1.85 + up * tableTop
			localPart(Vector3.new(2.6, 0.14, 1.9), CFrame.lookAt(tc, tc + look), Color3.fromRGB(196, 200, 206), nil, Enum.Material.Metal)
			localPart(Vector3.new(0.2, tableTop, 0.2), CFrame.new(Vector3.new(tc.X, floorY + tableTop / 2, tc.Z)), Color3.fromRGB(120, 124, 130), nil, Enum.Material.Metal)
			local bowlAt = tc - look * 0.45 + up * 0.32
			localPart(Vector3.new(0.5, 1.15, 1.15), CFrame.new(bowlAt) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(244, 240, 230), Enum.PartType.Cylinder)
			localPart(Vector3.new(0.12, 0.95, 0.95), CFrame.new(bowlAt + up * 0.2) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(226, 160, 72), Enum.PartType.Cylinder) -- noodles
			-- sit down: the hips drop onto the stool
			local t0s = os.clock()
			while os.clock() - t0s < 0.45 and not skip do
				RunService.RenderStepped:Wait()
				local k = math.clamp((os.clock() - t0s) / 0.45, 0, 1)
				sink = thigh * k * k * (3 - 2 * k)
				place()
				setPose({}, SIT, k)
			end
			sink = thigh
			place()
		end
		camCf = shotB
		cam.FieldOfView = 55
		task.wait(0.12)
		local t = 0
		local length = (kind == "eat" and 4.2) or (kind == "drink" and 3.0) or (kind == "pickup" and 2.6) or 2.8
		local spoon: BasePart? = nil
		if kind == "eat" then
			spoon = localPart(Vector3.new(0.1, 0.06, 0.85), CFrame.new(), Color3.fromRGB(210, 214, 220), nil, Enum.Material.Metal)
		elseif kind == "drink" then
			held = prop("cup")
			heldKind = "cup"
			held.Parent = actor
			table.insert(extras, held)
		end
		-- pick-up: the order waits on a counter in front; the bag is not in the hand until it is taken
		local counterBag: BasePart? = nil
		if kind == "pickup" then
			local cc = stop + look * 2.1 + up * 1.45
			localPart(Vector3.new(3.4, 2.9, 1.3), CFrame.lookAt(cc, cc + look), Color3.fromRGB(150, 112, 76), nil, Enum.Material.Wood)
			counterBag = prop("bag")
			local bagAt = cc + up * (1.45 + 0.75) - look * 0.15 + right * 0.35
			counterBag.CFrame = CFrame.lookAt(bagAt, bagAt + look)
			counterBag.Parent = actor
			table.insert(extras, counterBag)
		end

		-- key poses
		local EAT_BOWL = with(SIT, { rs = { 30, 18, -6 }, re = { 58 }, ls = { 34, -22, 10 }, le = { 62 }, neck = { -12 }, waist = { -10 } })
		local EAT_MOUTH = with(SIT, { rs = { 55, 46, -12 }, re = { 128 }, rw = { -20 }, ls = { 34, -22, 10 }, le = { 62 }, neck = { -4 }, waist = { -6 } })
		local CUP_DOWN = { rs = { 22, 18, -6 }, re = { 78 }, neck = { -2 } }
		local CUP_UP = { rs = { 56, 44, -12 }, re = { 128 }, neck = { 16 } }
		local REACH = { rs = { 58, 12, -6 }, re = { 22 }, waist = { -12 }, neck = { -10 } }
		local CARRY = { rs = { 8, 0, 3 }, re = { 14 }, neck = { -12 } } -- bag at the side, a little nod of thanks
		local OFFER = { rs = { 56, 10, -6 }, re = { 20 }, ls = { 6, 0, 4 }, neck = { -6 } }
		local WAI = { rs = { 40, 0, -30 }, ls = { 40, 0, 30 }, re = { 112 }, le = { 112 }, waist = { -14 }, neck = { -12 } }
		local STAND = {}

		local given = false
		while t < length and not skip do
			local dt = RunService.RenderStepped:Wait()
			t += dt
			if kind == "eat" then
				-- scoop (0.4 s) - lift (0.55) - at the mouth, chewing (0.45) - back down (0.5)
				local c = t % 1.9
				if c < 0.4 then
					setPose(EAT_BOWL)
				elseif c < 0.95 then
					setPose(EAT_BOWL, EAT_MOUTH, (c - 0.4) / 0.55)
				elseif c < 1.4 then
					setPose(EAT_MOUTH)
					pose(J.neck, rad(-4 + 3 * math.sin((c - 0.95) * 18))) -- chewing
				else
					setPose(EAT_MOUTH, EAT_BOWL, (c - 1.4) / 0.5)
				end
				local rh = actor:FindFirstChild("RightHand") :: BasePart?
				if spoon and rh then
					-- the spoon sticks out of the thumb side of the fist, toward the mouth, tipped up
					spoon.CFrame = rh.CFrame * CFrame.new(0, -0.25, 0.32) * CFrame.Angles(rad(-25), 0, 0)
				end
			elseif kind == "drink" then
				-- lift (0.7 s), drink with the head back (1.2), lower (0.7)
				local k
				if t < 0.4 then k = 0
				elseif t < 1.1 then k = (t - 0.4) / 0.7
				elseif t < 2.3 then k = 1
				else k = 1 - math.clamp((t - 2.3) / 0.7, 0, 1) end
				setPose(CUP_DOWN, CUP_UP, k)
				local rh = actor:FindFirstChild("RightHand") :: BasePart?
				if held and rh then
					-- upright in the hand, tipped toward the mouth while drinking (a cylinder's axis is X)
					local tilt = rad(70) * k * k
					local axis = up * math.cos(tilt) - look * math.sin(tilt)
					local at = rh.Position + axis * 0.3
					held.CFrame = CFrame.fromMatrix(at, axis, right)
				end
			elseif kind == "pickup" then
				-- reach for the bag on the counter, take it, bring it to the side, nod thanks
				if t < 0.7 then
					setPose(STAND, REACH, t / 0.7)
				elseif t < 1.0 then
					setPose(REACH)
					if not held and counterBag then
						held = counterBag
						counterBag = nil
						Feedback.play("tick", 0.4, 1.2, 0.05)
					end
				elseif t < 1.7 then
					setPose(REACH, CARRY, (t - 1.0) / 0.7)
				else
					setPose(CARRY)
				end
				holdProp()
			else
				-- hold the bag out with one hand; once it is taken, a wai with a small bow
				if t < 0.6 then
					setPose(STAND, OFFER, t / 0.6)
					holdProp()
				elseif t < 1.0 then
					setPose(OFFER)
					holdProp()
				else
					if not given then
						given = true
						if held then
							local bag = held
							held = nil
							TweenService:Create(bag, TweenInfo.new(0.35), { CFrame = bag.CFrame + dir * 2.4, Transparency = 1 }):Play()
							task.delay(0.4, function() bag:Destroy() end)
						end
						Feedback.good()
					end
					if t < 1.5 then setPose(OFFER, WAI, (t - 1.0) / 0.5) else setPose(WAI) end
				end
			end
		end
	end)
	if not ok then warn("[Cutscene] " .. tostring(err)) end
	finish()
end

function Cutscene.start()
	Drive.onCrash = function(info) task.spawn(Cutscene.play, "crash", info) end
	Net.listen("Notify", function(kind, p)
		if kind == "scene" and type(p) == "table" and p.kind ~= "ghost" then -- (ghost scenes: client/Ghosts)
			task.spawn(Cutscene.play, p.kind, p)
		end
	end)
end

return Cutscene
