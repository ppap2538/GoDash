-- CCTV replay (2026-11-19, owner: "a replay so you can see what happened, as if there was a CCTV camera").
-- While you drive, the last few seconds are kept: your vehicle, the people around it (client/Peds) and the
-- AI cars near you (client/Street), 15 times a second. After an accident claim or a red-light / zebra
-- ticket, client/Cutscene's fineScene calls Replay.play: the moments before (and just after) it happened
-- play back from a camera high on a pole by the road, grey and grainy with scan lines and a REC stamp,
-- at CCTV's own choppy frame rate, slowing down round the moment itself.
--
-- The real actors are moved for the replay (only on this screen) and put back exactly where they were:
-- your vehicle is anchored here for it (nothing is sent to the server while it is anchored, so other
-- players see it standing still), the person who was hit is borrowed from client/Peds, and the AI car
-- is held with its "ReplayHold" attribute (client/Street leaves it alone).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Drive = require(script.Parent.Drive)
local Peds = require(script.Parent.Peds)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)

local Replay = {}
local L = Lang.pick
local player = Players.LocalPlayer
local HZ, KEEP = 15, 8 -- samples a second, seconds kept
local buf = {} -- ring of samples { t, cf, peds, cars }
local head = 0
local count = 0
local SIZE = HZ * KEEP
local acc = 0
local camNo = 0

local function sample(c)
	local cf = c.chassis.CFrame
	local pos = cf.Position
	local cars = {}
	local f = Workspace:FindFirstChild("GoDashLocalTraffic")
	if f then
		for _, m in ipairs(f:GetChildren()) do
			if m:IsA("Model") then
				local pv = m:GetPivot()
				if (pv.Position - pos).Magnitude < 60 then cars[m] = pv end
			end
		end
	end
	head = head % SIZE + 1
	buf[head] = { t = os.clock(), cf = cf, model = c.model, peds = Peds.near(pos, 40), cars = cars }
	count = math.min(count + 1, SIZE)
end

-- The samples from t0 to t1 (oldest first), all of the same vehicle.
function Replay.take(t0: number, t1: number)
	local out = {}
	for i = count - 1, 0, -1 do
		local s = buf[(head - 1 - i) % SIZE + 1]
		if s and s.t >= t0 and s.t <= t1 then table.insert(out, s) end
	end
	-- a vehicle swap inside the window: keep only the last vehicle's part
	local last = out[#out]
	if last then
		local keep = {}
		for _, s in ipairs(out) do
			if s.model == last.model then table.insert(keep, s) end
		end
		out = keep
	end
	return out
end

-- interpolate the samples at time t: returns i, k (between samples i and i + 1)
local function at(samples, t: number): (number, number)
	local n = #samples
	if t <= samples[1].t then return 1, 0 end
	if t >= samples[n].t then return n, 0 end
	for i = 1, n - 1 do
		local a, b = samples[i], samples[i + 1]
		if t >= a.t and t <= b.t then return i, (t - a.t) / math.max(b.t - a.t, 1e-3) end
	end
	return n, 0
end

local function pedAt(s, p)
	for _, e in ipairs(s.peds) do
		if e.p == p then return e end
	end
	return nil
end

-- the CCTV look: grey, a little green, scan lines, dark corners, REC, camera number, the clock
local function overlay()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GoDashCCTV"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 84
	gui:SetAttribute("NoTranslate", true)
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	-- scan lines
	for i = 0, 89 do
		local l = Instance.new("Frame")
		l.BorderSizePixel = 0
		l.BackgroundColor3 = Color3.new(0, 0, 0)
		l.BackgroundTransparency = 0.82
		l.Position = UDim2.fromScale(0, i / 90)
		l.Size = UDim2.new(1, 0, 0, 2)
		l.Parent = root
	end
	-- dark edges: { anchor x, anchor y, width, height, gradient rotation (dark end first) }
	for _, e in ipairs({ { 0, 0, 1, 0.24, 90 }, { 0, 1, 1, 0.24, 270 }, { 0, 0, 0.18, 1, 0 }, { 1, 0, 0.18, 1, 180 } }) do
		local v = Instance.new("Frame")
		v.BorderSizePixel = 0
		v.BackgroundColor3 = Color3.new(0, 0, 0)
		v.AnchorPoint = Vector2.new(e[1], e[2])
		v.Position = UDim2.fromScale(e[1], e[2])
		v.Size = UDim2.fromScale(e[3], e[4])
		local g = Instance.new("UIGradient")
		g.Rotation = e[5]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = v
		v.Parent = root
	end
	local function label(text: string, x: number, y: number, ax: number, size: number, color: Color3?)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(ax, 0)
		t.Position = UDim2.new(x, ax == 0 and 24 or -24, y, 18)
		t.Size = UDim2.fromOffset(420, size + 6)
		t.Font = Enum.Font.Code
		t.TextSize = size
		t.TextColor3 = color or Color3.fromRGB(236, 236, 228)
		t.TextStrokeTransparency = 0.5
		t.TextXAlignment = ax == 0 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
		t.Text = text
		t.Parent = root
		return t
	end
	camNo = (camNo % 17) + 3
	local rec = label("●", 0, 0, 0, 22, Color3.fromRGB(240, 40, 40))
	label(("   REC   CAM %02d"):format(camNo), 0, 0, 0, 22)
	local clock = label("", 1, 0, 1, 20)
	local mode = label("", 0, 1, 0, 18)
	mode.Position = UDim2.new(0, 24, 1, -58)
	local tag = label(L("CCTV · REPLAY", "กล้องวงจรปิด · ภาพย้อนหลัง"), 1, 1, 1, 18)
	tag.Position = UDim2.new(1, -24, 1, -58)
	local flash = Instance.new("Frame")
	flash.BorderSizePixel = 0
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 3
	flash.Parent = root
	gui.Parent = player:WaitForChild("PlayerGui")
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "GoDashCCTV"
	cc.Saturation = -0.82
	cc.Contrast = 0.22
	cc.Brightness = 0.02
	cc.TintColor = Color3.fromRGB(214, 236, 220)
	cc.Parent = Lighting
	return {
		gui = gui, cc = cc, rec = rec, clock = clock, mode = mode, flash = flash,
		destroy = function() gui:Destroy(); cc:Destroy() end,
	}
end

-- A camera spot on a pole by the road, looking at the place it happened, with a clear view.
local function spot(hit: Vector3, dir: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local target = hit + Vector3.new(0, 2, 0)
	for _, c in ipairs({ { 16, 1 }, { 16, -1 }, { -12, 1 }, { -12, -1 }, { 26, 1 }, { 26, -1 } }) do
		for _, up in ipairs({ 17, 24 }) do
			local eye = hit + dir * c[1] + side * c[2] * 14 + Vector3.new(0, up, 0)
			if not Workspace:Raycast(eye, target - eye, params) then return eye end
		end
	end
	return hit + dir * 6 + Vector3.new(0, 30, 0)
end

-- Play it. opts = {
--   samples (Replay.take), hitAt = the moment (os.clock()), chassis = your vehicle's chassis now,
--   ped = the borrowed Peds state of the person who was hit (or nil), car = the AI car that was hit (or nil),
--   setCam = function(cf, fov), skip = function(): boolean, label = text for the bottom-left
-- }
function Replay.play(opts)
	local samples = opts.samples
	if not samples or #samples < 6 or not opts.chassis then return false end
	local chassis = opts.chassis :: BasePart
	local hitAt = opts.hitAt or samples[#samples].t
	local t0, t1 = samples[1].t, samples[#samples].t
	local hitIdx = at(samples, hitAt)
	local hitPos = samples[hitIdx].cf.Position
	local before = samples[math.max(1, hitIdx - 8)].cf.Position
	local dir = Vector3.new(hitPos.X - before.X, 0, hitPos.Z - before.Z)
	if dir.Magnitude < 0.5 then dir = Vector3.new(samples[hitIdx].cf.LookVector.X, 0, samples[hitIdx].cf.LookVector.Z) end
	dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.zAxis

	-- keep what is real now, to put it all back
	local liveCf, wasAnchored = chassis.CFrame, chassis.Anchored
	local ped = opts.ped
	local pedLive = ped and { pos = ped.pos, look = ped.look }
	local car = opts.car
	local carLive = car and car.Parent and car:GetPivot()
	if car then car:SetAttribute("ReplayHold", true) end
	local ignore = { chassis:FindFirstAncestorWhichIsA("Model") or chassis, player.Character }
	for _, n in ipairs({ "Vehicles", "Traffic", "GoDashLocalTraffic", "GoDashPedestrians", "NPCs", "GoDashDogs" }) do
		local f = Workspace:FindFirstChild(n)
		if f then table.insert(ignore, f) end
	end
	local eye = spot(hitPos, dir, ignore)
	local ov = overlay()
	local clock0 = math.floor(Lighting.ClockTime * 3600) - math.floor(os.clock() - t0)
	chassis.Anchored = true
	Feedback.play("tick", 0.5, 1.4, 0.1)

	local ok, err = pcall(function()
		local pt = t0
		local step = 1 / HZ
		local shown = -1
		local look = hitPos
		local flashed = false
		local fov = 58
		while pt < t1 and not (opts.skip and opts.skip()) do
			local rdt = RunService.RenderStepped:Wait()
			-- slow motion round the moment itself
			local near = math.abs(pt - hitAt)
			local rate = near < 0.55 and 0.32 or 1
			pt += math.min(rdt, 1 / 20) * rate
			ov.mode.Text = rate < 1 and "▶ 0.3x  ◀◀" or "▶ 1.0x"
			ov.rec.TextTransparency = (os.clock() % 1) < 0.5 and 0 or 1
			-- the camera's own clock: the town time when it happened, ticking in real seconds
			local tsec = math.floor(clock0 + (pt - t0))
			ov.clock.Text = ("%s  %02d:%02d:%02d"):format(os.date("%d/%m/%Y"), (tsec // 3600) % 24, (tsec // 60) % 60, tsec % 60)
			if not flashed and pt >= hitAt then
				flashed = true
				ov.flash.BackgroundTransparency = 0.55
				TweenService:Create(ov.flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
				Feedback.play("bump", 0.55, 0.9, 0.2)
			end
			-- CCTV frame rate: the picture only changes 15 times a second
			local frameNo = math.floor((pt - t0) / step)
			if frameNo ~= shown then
				shown = frameNo
				local tq = t0 + frameNo * step
				local i, k = at(samples, tq)
				local a, b = samples[i], samples[math.min(i + 1, #samples)]
				local cf = a.cf:Lerp(b.cf, k)
				chassis.CFrame = cf
				chassis.AssemblyLinearVelocity = Vector3.zero
				if ped then
					local ea, eb = pedAt(a, ped), pedAt(b, ped)
					local e = ea or eb
					if e then
						local pos = (ea and eb) and ea.pos:Lerp(eb.pos, k) or e.pos
						if e.down or tq >= hitAt then
							Peds.place(ped, "lie", pos, e.look)
						else
							Peds.place(ped, "walk", pos, e.look, 4)
						end
					end
				end
				if car and car.Parent then
					local ca, cb = a.cars[car], b.cars[car]
					if ca or cb then car:PivotTo((ca and cb) and ca:Lerp(cb, k) or (ca or cb)) end
				end
				-- the camera turns to keep it in the picture (a PTZ camera) and zooms in a little at the hit
				look = look:Lerp(cf.Position, 0.35)
				fov = fov + ((near < 0.8 and 44 or 58) - fov) * 0.25
				opts.setCam(CFrame.lookAt(eye, look + Vector3.new(0, 1.2, 0)), fov)
			end
		end
	end)
	if not ok then warn("[Replay] " .. tostring(err)) end

	-- everything back where it really is
	chassis.CFrame = liveCf
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	chassis.Anchored = wasAnchored
	if ped and pedLive then Peds.place(ped, "lie", pedLive.pos, pedLive.look) end
	if car then
		if car.Parent and carLive then car:PivotTo(carLive) end
		car:SetAttribute("ReplayHold", nil)
	end
	ov.destroy()
	return true
end

function Replay.start()
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / HZ then return end
		acc = 0
		local c = Drive.current()
		if c and c.chassis and c.chassis.Parent and not c.chassis.Anchored then
			pcall(sample, c)
		end
	end)
end

return Replay
