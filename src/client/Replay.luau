-- Replays (2026-11-19).
--   * CCTV replay (owner: "a replay so you can see what happened, as if there was a CCTV camera"): after an
--     accident claim, a red light or the zebra fine, client/Cutscene's fineScene calls Replay.play: the moments
--     before (and just after) it happened, from a camera high on a pole by the road, grey and grainy with scan
--     lines and a REC stamp, at CCTV's own choppy frame rate, slowing down round the moment itself.
--   * Instant replay (owner: "เพิ่มตามแนะนำ": watch the last 10 seconds, for clips): L, or the ⏪ button in clip
--     mode. Six cameras (TV, chase, low, front, drone, roadside), pause, half speed; it loops until you close it.
--     Pull up first (below ~12 km/h): the vehicle is held still while you watch.
-- While you drive, the last few seconds are kept: your vehicle, the people around it (client/Peds) and the AI
-- cars near you (client/Street), 15 times a second. For a replay the real actors are moved (on this screen only)
-- and put back exactly where they were: your vehicle is anchored here for it (nothing is sent to the server
-- while it is anchored, so other players see it standing still), people are borrowed from client/Peds, AI cars
-- are held with their "ReplayHold" attribute (client/Street leaves them alone).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Drive = require(script.Parent.Drive)
local Peds = require(script.Parent.Peds)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI.Kit)

local Replay = {}
local L = Lang.pick
local player = Players.LocalPlayer
local HZ, KEEP = 15, 12 -- samples a second, seconds kept
local SIZE = HZ * KEEP
local buf = {} -- ring of samples { t, cf, model, peds, cars }
local head, count = 0, 0
local acc = 0
local camNo = 0
local busy = false

local function sample(c)
	local cf = c.chassis.CFrame
	local pos = cf.Position
	local cars = {}
	local f = Workspace:FindFirstChild("GoDashLocalTraffic")
	if f then
		for _, m in ipairs(f:GetChildren()) do
			if m:IsA("Model") then
				local pv = m:GetPivot()
				if (pv.Position - pos).Magnitude < 70 then cars[m] = pv end
			end
		end
	end
	head = head % SIZE + 1
	buf[head] = { t = os.clock(), cf = cf, model = c.model, peds = Peds.near(pos, 45), cars = cars }
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

-- between which samples is time t: i, k (0..1 toward sample i + 1)
local function at(samples, t: number): (number, number)
	local n = #samples
	if t <= samples[1].t then return 1, 0 end
	if t >= samples[n].t then return n, 0 end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if samples[mid].t <= t then lo = mid else hi = mid end
	end
	local a, b = samples[lo], samples[hi]
	return lo, (t - a.t) / math.max(b.t - a.t, 1e-3)
end

local function pedAt(s, p)
	for _, e in ipairs(s.peds) do
		if e.p == p then return e end
	end
	return nil
end

-- Put the actors on stage: opts = { chassis, drive (Drive's state, to spin the wheels), ped (a person the caller
-- already borrowed: they lie down from hitAt on), hitAt, allPeds, car, allCars }. Returns apply(t) and restore().
local function stage(samples, opts)
	local chassis = opts.chassis :: BasePart
	local liveCf, wasAnchored = chassis.CFrame, chassis.Anchored
	local people = {}
	if opts.ped then table.insert(people, { p = opts.ped, live = { pos = opts.ped.pos, look = opts.ped.look }, own = false }) end
	if opts.allPeds then
		local seenP = {}
		if opts.ped then seenP[opts.ped] = true end
		for _, s in ipairs(samples) do
			for _, e in ipairs(s.peds) do
				if not seenP[e.p] then
					seenP[e.p] = true
					local live = { pos = e.p.pos, look = e.p.look }
					if Peds.borrow(e.p) then table.insert(people, { p = e.p, live = live, own = true }) end
				end
			end
		end
	end
	local cars = {}
	local function addCar(m: Model)
		if m and m.Parent then
			m:SetAttribute("ReplayHold", true)
			table.insert(cars, { m = m, live = m:GetPivot() })
		end
	end
	if opts.allCars then
		local seenC = {}
		for _, s in ipairs(samples) do
			for m in pairs(s.cars) do
				if not seenC[m] then seenC[m] = true; addCar(m) end
			end
		end
	elseif opts.car then
		addCar(opts.car)
	end
	chassis.Anchored = true
	local lastPos: Vector3? = nil

	local function apply(t: number, dt: number?)
		local i, k = at(samples, t)
		local a, b = samples[i], samples[math.min(i + 1, #samples)]
		local cf = a.cf:Lerp(b.cf, k)
		chassis.CFrame = cf
		chassis.AssemblyLinearVelocity = Vector3.zero
		-- the wheels roll with the replayed speed (Drive keeps the angles; it keeps writing them)
		local c = opts.drive
		if c and c.spin and dt and lastPos then
			local along = (cf.Position - lastPos):Dot(cf.LookVector)
			for _, sp in ipairs(c.spin) do sp.angle = (sp.angle + along / math.max(sp.r, 0.2)) % (math.pi * 2) end
		end
		lastPos = cf.Position
		for _, who in ipairs(people) do
			local ea, eb = pedAt(a, who.p), pedAt(b, who.p)
			local e = ea or eb
			if e then
				local pos = (ea and eb) and ea.pos:Lerp(eb.pos, k) or e.pos
				if e.down or (who.p == opts.ped and opts.hitAt and t >= opts.hitAt) then
					Peds.place(who.p, "lie", pos, e.look)
				else
					local moved = (ea and eb) and (eb.pos - ea.pos).Magnitude or 0
					local spd = moved / math.max(b.t - a.t, 1e-3)
					Peds.place(who.p, spd > 0.6 and (spd > 7.5 and "run" or "walk") or "idle", pos, e.look, spd)
				end
			end
		end
		for _, car in ipairs(cars) do
			if car.m.Parent then
				local ca, cb = a.cars[car.m], b.cars[car.m]
				if ca or cb then car.m:PivotTo((ca and cb) and ca:Lerp(cb, k) or (ca or cb)) end
			end
		end
		return cf
	end

	local function restore()
		chassis.CFrame = liveCf
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
		chassis.Anchored = wasAnchored
		for _, who in ipairs(people) do
			if who.own then
				Peds.place(who.p, "idle", who.live.pos, who.live.look)
				Peds.release(who.p)
			else
				Peds.place(who.p, "lie", who.live.pos, who.live.look)
			end
		end
		for _, car in ipairs(cars) do
			if car.m.Parent then car.m:PivotTo(car.live) end
			car.m:SetAttribute("ReplayHold", nil)
		end
	end
	return apply, restore
end

local function ignoreList(chassis: BasePart): { Instance }
	local ignore = { chassis:FindFirstAncestorWhichIsA("Model") or chassis, player.Character }
	for _, n in ipairs({ "Vehicles", "Traffic", "GoDashLocalTraffic", "GoDashPedestrians", "NPCs", "GoDashDogs" }) do
		local f = Workspace:FindFirstChild(n)
		if f then table.insert(ignore, f) end
	end
	return ignore
end

---------------------------------------------------------------------------------------------------
-- CCTV replay
---------------------------------------------------------------------------------------------------
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
--   setCam = function(cf, fov), skip = function(): boolean
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

	local eye = spot(hitPos, dir, ignoreList(chassis))
	local apply, restore = stage(samples, { chassis = chassis, ped = opts.ped, hitAt = hitAt, car = opts.car })
	local ov = overlay()
	local clock0 = math.floor(Lighting.ClockTime * 3600) - math.floor(os.clock() - t0)
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
				local cf = apply(t0 + frameNo * step)
				-- the camera turns to keep it in the picture (a PTZ camera) and zooms in a little at the hit
				look = look:Lerp(cf.Position, 0.35)
				fov = fov + ((near < 0.8 and 44 or 58) - fov) * 0.25
				opts.setCam(CFrame.lookAt(eye, look + Vector3.new(0, 1.2, 0)), fov)
			end
		end
	end)
	if not ok then warn("[Replay] " .. tostring(err)) end
	restore()
	ov.destroy()
	return true
end

---------------------------------------------------------------------------------------------------
-- Instant replay: the last 10 seconds
---------------------------------------------------------------------------------------------------
local CAMS = {
	{ id = "tv", en = "TV", th = "มุมทีวี" },
	{ id = "chase", en = "Chase", th = "ตามหลัง" },
	{ id = "low", en = "Low", th = "มุมต่ำ" },
	{ id = "front", en = "Front", th = "ด้านหน้า" },
	{ id = "drone", en = "Drone", th = "โดรน" },
	{ id = "road", en = "Roadside", th = "ข้างทาง" },
}

function Replay.instant()
	if busy or State.cutscene then return end
	local c = Drive.current()
	if not c or not c.chassis or not c.chassis.Parent then
		Feedback.toast(L("⏪ Replays are for riding: get on your vehicle", "⏪ ดูรีเพลย์ได้ตอนขี่รถอยู่นะ"), "bad")
		return
	end
	local v = c.chassis.AssemblyLinearVelocity
	if Vector3.new(v.X, 0, v.Z).Magnitude > 12 then
		Feedback.toast(L("⏪ Slow down and pull up first, then L", "⏪ ชะลอจอดก่อน แล้วกด L ดูรีเพลย์"), "bad")
		return
	end
	local now = os.clock()
	local samples = Replay.take(now - 10, now)
	if #samples < 15 then
		Feedback.toast(L("⏪ Nothing to replay yet: ride a little first", "⏪ ยังไม่มีภาพ ขี่ต่ออีกนิดนะ"), "bad")
		return
	end
	busy = true
	State.cutscene = true -- Drive holds the vehicle (handbrake) while we watch
	local cam = Workspace.CurrentCamera
	local oldFov = cam.FieldOfView
	local clipGui = player.PlayerGui:FindFirstChild("GoDashClip")
	local clipOn = clipGui and clipGui.Enabled
	local huds = {}
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g.Name:sub(1, 6) == "GoDash" and g ~= clipGui then
			g.Enabled = false
			table.insert(huds, g)
		end
	end
	local apply, restore = stage(samples, { chassis = c.chassis, drive = c, allPeds = true, allCars = true })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList(c.chassis)
	local function clear(from: Vector3, to: Vector3): Vector3
		local d = to - from
		local hit = Workspace:Raycast(from, d, params)
		if hit then return hit.Position - d.Unit * 1.2 end
		return to
	end

	-- the overlay: a REPLAY tag in the picture, the controls outside it in clip mode (on the left bar)
	local gui = Instance.new("ScreenGui")
	gui.Name = "GoDashReplay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 86
	gui:SetAttribute("NoTranslate", true)
	gui.Parent = player.PlayerGui
	local tag = UI.label(gui, L("⏪ REPLAY", "⏪ รีเพลย์"), 22, Color3.new(1, 1, 1), UI.F.black,
		{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromOffset(200, 34), TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0.15, BackgroundColor3 = Color3.fromRGB(200, 30, 40) })
	UI.corner(tag, 8)
	local vs = cam.ViewportSize
	local bar = clipOn and math.max(0, (vs.X - vs.Y * 9 / 16) / 2) or 0
	local panel = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(16, 18, 24), BackgroundTransparency = 0.2, Parent = gui })
	UI.corner(panel, 12)
	if bar >= 230 then
		panel.Position = UDim2.fromOffset(12, 190)
		panel.Size = UDim2.fromOffset(bar - 24, 150)
	else
		panel.AnchorPoint = Vector2.new(0.5, 1)
		panel.Position = UDim2.new(0.5, 0, 1, -16)
		panel.Size = UDim2.fromOffset(math.min(520, vs.X - 32), 92)
	end
	local timeline = UI.new("Frame", { Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 8), BackgroundColor3 = Color3.fromRGB(70, 74, 84), Parent = panel })
	UI.corner(timeline, 4)
	local prog = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(230, 50, 60), Parent = timeline })
	UI.corner(prog, 4)
	local info = UI.label(panel, "", 14, Color3.fromRGB(255, 220, 120), UI.F.bold, { Position = UDim2.fromOffset(12, 22), Size = UDim2.new(1, -24, 0, 20) })
	local row = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 0, 36), Parent = panel })
	UI.list(row, 6, true)
	if bar >= 230 then
		row.Size = UDim2.new(1, -24, 0, 80)
		local grid = row:FindFirstChildOfClass("UIListLayout")
		if grid then grid:Destroy() end
		local g = Instance.new("UIGridLayout")
		g.CellSize = UDim2.fromOffset(math.floor((bar - 24 - 24 - 12) / 3), 34)
		g.CellPadding = UDim2.fromOffset(6, 6)
		g.Parent = row
	end

	local camI, paused, slow = 1, false, false
	local pt = samples[1].t
	local t0, t1 = samples[1].t, samples[#samples].t
	local camPos: Vector3? = nil
	local roadCam: Vector3? = nil
	local orbit = 0
	local ended = false
	local holdT = 0
	local function camName() return L(CAMS[camI].en, CAMS[camI].th) end
	local function setCam(i: number)
		camI = (i - 1) % #CAMS + 1
		camPos, roadCam = nil, nil
	end
	local function btn(text: string, w: number, cb, color: Color3?)
		local b = UI.button(row, text, { Size = UDim2.fromOffset(w, 34), TextSize = 14, BackgroundColor3 = color or UI.C.dark }, cb)
		b:SetAttribute("NoTranslate", true)
		return b
	end
	btn("◀ " .. L("Cam", "มุม"), 76, function() setCam(camI - 1) end)
	btn(L("Cam", "มุม") .. " ▶", 76, function() setCam(camI + 1) end)
	local pauseB = btn("⏸", 54, function() paused = not paused end)
	local slowB = btn("🐢 0.5x", 76, function() slow = not slow end)
	btn("✖ " .. L("Close", "ออก"), 76, function() ended = true end, UI.C.red)

	local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.N then setCam(camI + 1)
		elseif input.KeyCode == Enum.KeyCode.Space then paused = not paused
		elseif input.KeyCode == Enum.KeyCode.L or input.KeyCode == Enum.KeyCode.Escape then ended = true end
	end)
	Feedback.play("tick", 0.5, 0.7, 0.1)

	RunService:BindToRenderStep("GoDashReplay", Enum.RenderPriority.Last.Value + 3, function(rdt)
		local dt = math.min(rdt, 1 / 20)
		if not paused then
			if pt >= t1 then
				-- hold the last frame a moment, then go round again
				holdT += dt
				if holdT > 0.8 then pt, holdT, camPos, roadCam = t0, 0, nil, nil end
			else
				pt = math.min(t1, pt + dt * (slow and 0.5 or 1))
			end
		end
		local cf = apply(pt, dt)
		local s = cf.Position + Vector3.new(0, 1.6, 0)
		local fwd = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		fwd = fwd.Magnitude > 0.05 and fwd.Unit or Vector3.zAxis
		local right = Vector3.new(-fwd.Z, 0, fwd.X)
		local id = CAMS[camI].id
		local want, look, fov, k
		if id == "tv" then
			want = s + right * 18 + fwd * 8 + Vector3.new(0, 4.5, 0)
			look, fov, k = s, 40, 3
		elseif id == "chase" then
			want = s - fwd * 15 + Vector3.new(0, 5.5, 0)
			look, fov, k = s + fwd * 8, 66, 6
		elseif id == "low" then
			want = s - fwd * 10.5 + right * 1.9 + Vector3.new(0, 0.3, 0) -- (7 back: the delivery box filled the picture)
			look, fov, k = s + fwd * 10, 62, 7
		elseif id == "front" then
			want = s + fwd * 10 + right * 1.5 + Vector3.new(0, 1.2, 0)
			look, fov, k = s + Vector3.new(0, 0.4, 0), 50, 6
		elseif id == "drone" then
			orbit += dt * 0.2
			want = s + Vector3.new(math.cos(orbit) * 34, 24, math.sin(orbit) * 34)
			look, fov, k = s, 60, 3
		else
			if not roadCam or (roadCam - s).Magnitude > 120 then
				roadCam = clear(s, s + fwd * 70 + right * 10 + Vector3.new(0, 2.8, 0))
				camPos = roadCam
			end
			want, look, fov, k = roadCam :: Vector3, s, 38, 60
		end
		if id ~= "drone" and id ~= "road" then want = clear(s, want) end
		local a = 1 - math.exp(-dt * k)
		camPos = camPos and camPos:Lerp(want, a) or want
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(camPos :: Vector3, look)
		cam.FieldOfView = fov
		prog.Size = UDim2.fromScale(math.clamp((pt - t0) / math.max(t1 - t0, 0.1), 0, 1), 1)
		info.Text = ("🎥 %s   ·   -%.1f %s%s"):format(camName(), math.max(0, t1 - pt), L("s", "วิ"), UserInputService.KeyboardEnabled and L("   ·   N cam · Space pause · L close", "   ·   N มุม · Space หยุด · L ออก") or "")
		pauseB.Text = paused and "▶" or "⏸"
		slowB.Text = slow and "🐢 0.5x ✓" or "🐢 0.5x"
		tag.TextTransparency = (os.clock() % 1.2) < 0.9 and 0 or 0.4
	end)

	task.spawn(function()
		while not ended and gui.Parent and Drive.current() == c do task.wait(0.1) end
		inputConn:Disconnect()
		RunService:UnbindFromRenderStep("GoDashReplay")
		pcall(restore)
		gui:Destroy()
		for _, g in ipairs(huds) do if g.Parent then g.Enabled = true end end
		cam.FieldOfView = oldFov
		cam.CameraType = Enum.CameraType.Custom
		State.cutscene = false
		busy = false
	end)
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
	-- L = the last ten seconds again
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or busy then return end
		if input.KeyCode == Enum.KeyCode.L then Replay.instant() end
	end)
end

return Replay
