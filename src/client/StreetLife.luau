-- Thai street life drawn by this client (owner, 2026-11-17: "reflect Thai society, satire, funny"):
--   potholes     on streets and sois; ride over one and the vehicle jolts (bump, camera kick)
--   floods       (OFF since 2026-11-20, owner: FLOODS below) heavy rain filled the low spots of some streets;
--                riding through slowed you and could kill a small bike's engine for a few seconds
--   live-streamer someone on the road edge filming "hi everyone, like and share!"; honk and they step back
--   wrong-way rider a motorbike coming at you along the kerb on your side of the road
--   party truck  a pickup with a wall of speakers, lights and dancers, blasting mor lam through the soi
--   Songkran     during the event (server/StreetService) people at the kerbs soak passing riders
--   U-turn       turn round in the middle of a main road and the city has an opinion
--   the neighbour at home asks the questions every Thai relative asks; your answer changes happiness
-- All of it is local to this player (no network traffic) except the neighbour's answer (Social remote).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Sounds = require(Shared.Config.Sounds)
local Vehicles = require(Shared.Config.Vehicles)
local RiderPose = require(Shared.RiderPose)
local Util = require(Shared.Util)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)
local Drive = require(script.Parent.Drive)
local GPS = require(script.Parent.GPS)
local Feed = require(script.Parent.Feed)
local Choice = require(script.Parent.Choice)
local EngineSound = require(script.Parent.EngineSound)

local StreetLife = {}
local player = Players.LocalPlayer
local L = Lang.pick
local rng = Random.new()
local Y = Vector3.yAxis
local ROAD_TOP = 0.26
local folder: Folder

local function flat(v: Vector3): Vector3 return Vector3.new(v.X, 0, v.Z) end
local function hash(n: number): number
	local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
	return x - math.floor(x)
end
local function rootPos(): Vector3?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return r and r.Position or nil
end
local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = props.Parent or folder
	return p
end
local function oneShot(at: Instance?, id: string?, vol: number, speed: number?)
	EngineSound.oneShot(at, id, vol, speed)
end

-- a posed local figure from the avatar models (stand / hail / sit), feet at cf
local function figure(cf: CFrame, pose: string): Model?
	local store = ReplicatedStorage:FindFirstChild("GoDashModels")
	if not store then return nil end
	local peds = {}
	for _, m in ipairs(store:GetChildren()) do
		if m:IsA("Model") and m.Name:sub(1, 3) == "Ped" then table.insert(peds, m) end
	end
	if #peds == 0 then return nil end
	local ok, m = pcall(RiderPose.build, peds[rng:NextInteger(1, #peds)], cf, nil, pose)
	if not ok or not m then return nil end
	m.Parent = folder
	return m
end

-- where the road is ahead of the player: { pos on the left lane edge, dir, edge }
local function roadAhead(dist: number)
	local graph = GPS.graph()
	local c = Drive.current()
	local r = c and c.chassis
	if not graph or not r then return nil end
	local fwd = flat(r.CFrame.LookVector)
	if fwd.Magnitude < 0.1 then return nil end
	fwd = fwd.Unit
	local probe = r.Position + fwd * dist
	local e, p = graph:nearest(probe)
	if not e then return nil end
	local dir = flat(e.b.pos - e.a.pos).Unit
	if dir:Dot(fwd) < 0 then dir = -dir end
	local left = Vector3.new(dir.Z, 0, -dir.X) -- +X east, +Z south: the left of travel
	return { p = Vector3.new(p.X, 0, p.Z), dir = dir, left = left, e = e }
end

---------------------------------------------------------------------------------------------------
-- potholes
---------------------------------------------------------------------------------------------------
local holes, holeGrid, holeParts = {}, {}, {}
local CELL = 200
local function cellKey(x: number, z: number): number return math.floor(x / CELL) * 4096 + math.floor(z / CELL) end

local function buildHoles(graph)
	for _, e in ipairs(graph.edges) do
		if (e.type == "street" or e.type == "soi") and e.len > 40 and hash(e.id) < 0.33 then
			local t = 0.2 + 0.6 * hash(e.id * 3.7)
			local p = e.a.pos:Lerp(e.b.pos, t)
			local dir = flat(e.b.pos - e.a.pos).Unit
			local side = Vector3.new(dir.Z, 0, -dir.X) * ((hash(e.id * 1.3) < 0.5) and 1 or -1)
			local pos = Vector3.new(p.X, 0, p.Z) + side * (e.def.width / 4)
			local h = { id = e.id, pos = pos, dir = dir, size = 2.2 + hash(e.id * 9.1) * 1.4 }
			table.insert(holes, h)
			local k = cellKey(pos.X, pos.Z)
			holeGrid[k] = holeGrid[k] or {}
			table.insert(holeGrid[k], h)
		end
	end
end

local function holesNear(pos: Vector3, r: number)
	local out = {}
	local cx, cz = math.floor(pos.X / CELL), math.floor(pos.Z / CELL)
	local n = math.ceil(r / CELL)
	for dx = -n, n do
		for dz = -n, n do
			for _, h in ipairs(holeGrid[(cx + dx) * 4096 + cz + dz] or {}) do
				if (h.pos - flat(pos)).Magnitude < r then table.insert(out, h) end
			end
		end
	end
	return out
end

local function showHoles(cam: Vector3)
	local want = {}
	for _, h in ipairs(holesNear(cam, 260)) do want[h] = true end
	for h, m in pairs(holeParts) do
		if not want[h] then m:Destroy(); holeParts[h] = nil end
	end
	for h in pairs(want) do
		if not holeParts[h] then
			local cf = CFrame.lookAt(h.pos + Vector3.new(0, ROAD_TOP, 0), h.pos + Vector3.new(0, ROAD_TOP, 0) + h.dir)
			local m = Instance.new("Model")
			m.Name = "Pothole"
			part({ Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, h.size + 0.7, h.size + 0.7), CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(92, 88, 82), Material = Enum.Material.Asphalt, Parent = m })
			part({ Name = "Hole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.07, h.size, h.size * 0.8), CFrame = cf * CFrame.new(0, 0.01, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(26, 24, 22), Material = Enum.Material.Slate, Parent = m })
			m.Parent = folder
			holeParts[h] = m
		end
	end
end

local holeHit = {}
local postedHole = false
local function checkHoles(c)
	local ch = c.chassis
	local v = ch.AssemblyLinearVelocity
	local speed = flat(v).Magnitude
	if speed < 5 then return end
	for _, h in ipairs(holesNear(ch.Position, 8)) do
		if (flat(ch.Position) - h.pos).Magnitude < h.size * 0.55 + 0.6 and os.clock() - (holeHit[h] or 0) > 2.5 then
			holeHit[h] = os.clock()
			local mass = ch.AssemblyMass
			ch:ApplyImpulse(Y * mass * math.min(speed * 0.22, 8))
			ch:ApplyAngularImpulse(flat(ch.CFrame.RightVector) * mass * (rng:NextNumber() - 0.5) * 6)
			oneShot(ch, Sounds.bump, 0.55, rng:NextNumber(0.85, 1.05))
			Feedback.fovKick(4, 0.25)
			if not postedHole and rng:NextNumber() < 0.35 then
				postedHole = true
				task.delay(3, function() Feed.post("pothole", { pos = h.pos }, true) end)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- floods after heavy rain
---------------------------------------------------------------------------------------------------
local floods = {}
local depth = 0
-- (2026-11-20, owner: "ขับๆไปรถหยุดเองก็มี เอาน้ำขังออกเลย") floods are off: no standing water, no drag, no dead engine
local FLOODS = false
local function buildFloods(graph)
	if not FLOODS then return end
	local hubPos = Vector3.zero
	for _, p in ipairs(State.world and State.world.pois or {}) do
		if p.kind == "hub" then hubPos = p.pos end
	end
	local list = {}
	for _, e in ipairs(graph.edges) do
		if (e.type == "street" or e.type == "soi" or e.type == "main") and e.len > 60 and hash(e.id * 5.3) < 0.08 then
			local mid = (e.a.pos + e.b.pos) / 2
			if (flat(mid) - flat(hubPos)).Magnitude < 2600 then table.insert(list, e) end
		end
	end
	for i = 1, math.min(40, #list) do
		local e = list[i]
		local mid = (e.a.pos + e.b.pos) / 2
		local dir = flat(e.b.pos - e.a.pos).Unit
		table.insert(floods, { cf = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(mid.X, 0, mid.Z) + dir), w = e.def.width + 6, l = math.min(34, e.len * 0.6), id = e.id })
	end
end

local floodIn = nil
local function updateFloods(dt: number, cam: Vector3)
	local wet = Workspace:GetAttribute("Wet") or 0
	local target = math.clamp((wet - 0.75) / 0.25, 0, 1)
	depth += (target - depth) * math.min(1, dt * (target > depth and 0.05 or 0.03))
	for _, f in ipairs(floods) do
		local near = (f.cf.Position - flat(cam)).Magnitude < 420
		if depth > 0.05 and near then
			if not f.part then
				f.part = part({ Name = "Flood", Size = Vector3.new(f.w, 0.1, f.l), Color = Color3.fromRGB(116, 100, 74), Transparency = 0.22, Reflectance = 0.12 })
			end
			local h = 0.1 + depth * 0.9
			f.part.Size = Vector3.new(f.w, h, f.l)
			f.part.CFrame = f.cf + Vector3.new(0, ROAD_TOP + h / 2 - 0.05, 0)
		elseif f.part then
			f.part:Destroy()
			f.part = nil
		end
	end
	-- riding through
	local c = Drive.current()
	if not c or depth < 0.3 then floodIn = nil return end
	local ch = c.chassis
	local inside = nil
	for _, f in ipairs(floods) do
		if f.part then
			local rel = f.cf:PointToObjectSpace(Vector3.new(ch.Position.X, 0, ch.Position.Z))
			if math.abs(rel.X) < f.w / 2 and math.abs(rel.Z) < f.l / 2 then inside = f break end
		end
	end
	if not inside then floodIn = nil return end
	local v = flat(ch.AssemblyLinearVelocity)
	ch:ApplyImpulse(-v * ch.AssemblyMass * math.min(1, dt * 1.6 * depth)) -- water drags
	if floodIn ~= inside then
		floodIn = inside
		oneShot(ch, Sounds.puddle, 0.7, 0.9)
		if v.Magnitude > 6 then
			-- spray
			local a = Instance.new("Attachment"); a.Parent = ch
			local pe = Instance.new("ParticleEmitter")
			pe.Color = ColorSequence.new(Color3.fromRGB(170, 160, 140)); pe.Size = NumberSequence.new(0.6, 0); pe.Lifetime = NumberRange.new(0.5, 0.9)
			pe.Speed = NumberRange.new(8, 14); pe.SpreadAngle = Vector2.new(70, 70); pe.Acceleration = Vector3.new(0, -40, 0); pe.Rate = 0
			pe.Transparency = NumberSequence.new(0.2, 1)
			pe.Parent = a
			pe:Emit(40)
			task.delay(1.5, function() a:Destroy() end)
		end
		local small = c.def.class == "bike" and not c.def.pedal and (c.def.style == "oldbike" or c.def.style == "underbone" or c.def.style == "scooter")
		if small and v.Magnitude > 3 and rng:NextNumber() < 0.45 then
			Drive.stallUntil = os.clock() + 4
			Feedback.toast(L("💦 The engine died! Water in the exhaust... wait for it to start again", "💦 เครื่องดับ! น้ำเข้าท่อ... รอสตาร์ทใหม่แป๊บ"), "bad")
			if rng:NextNumber() < 0.5 then task.delay(2, function() Feed.post("flood", { pos = ch.Position }, true) end) end
		elseif rng:NextNumber() < 0.15 then
			task.delay(2, function() Feed.post("flood", { pos = ch.Position }, false) end)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- live-streamer on the road edge
---------------------------------------------------------------------------------------------------
local streamer = nil
local function spawnStreamer()
	local ra = roadAhead(110)
	if not ra then return end
	local edge = ra.p + ra.left * (ra.e.def.width / 2 - 1.6)
	local m = figure(CFrame.lookAt(edge, edge - ra.left) , "hail")
	if not m then return end
	local hand = m:FindFirstChild("RightHand") :: BasePart?
	if hand then
		part({ Name = "Stick", Size = Vector3.new(0.08, 1.6, 0.08), CFrame = hand.CFrame * CFrame.new(0, 0.8, 0), Color = Color3.fromRGB(30, 30, 32), Parent = m })
		part({ Name = "Phone", Size = Vector3.new(0.5, 0.9, 0.08), CFrame = hand.CFrame * CFrame.new(0, 1.7, -0.1), Color = Color3.fromRGB(20, 20, 24), Material = Enum.Material.Glass, Parent = m })
		local ring = part({ Name = "RingLight", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 0.8, 0.8), CFrame = hand.CFrame * CFrame.new(0, 1.7, 0.05) * CFrame.Angles(0, math.rad(90), 0),
			Color = Color3.fromRGB(255, 250, 230), Material = Enum.Material.Neon, Parent = m })
		local l = Instance.new("PointLight"); l.Range = 8; l.Brightness = 1.2; l.Parent = ring
	end
	streamer = { model = m, pos = edge, out = -ra.left, born = os.clock(), said = false, stepped = false }
	Feedback.bubble(edge + Y * 6.5, L("Live streamer", "คนไลฟ์สด"), L("Hi everyone~ live from the road today! Like and share!", "สวัสดีค่ะทุกคน~ วันนี้ไลฟ์จากกลางถนนเลย กดไลก์กดแชร์ด้วยนะคะ!"))
end

local function updateStreamer(me: Vector3)
	local s = streamer
	if not s then return end
	local d = (flat(me) - flat(s.pos)).Magnitude
	if os.clock() - s.born > 70 or (d > 320 and os.clock() - s.born > 10) then
		s.model:Destroy()
		streamer = nil
		return
	end
	if not s.said and d < 6 then
		s.said = true
		Feedback.bubble(s.pos + Y * 6.5, L("Live streamer", "คนไลฟ์สด"), L("Eek! Rider, watch it! ...everyone saw that, right?", "ว้ายยย! ไรเดอร์ขับดีๆ สิ ...ทุกคนเห็นใช่ไหมคะ"))
		if rng:NextNumber() < 0.4 then Feed.post("livestream", { pos = s.pos }, false) end
	end
end

function StreetLife.honked()
	local s = streamer
	local me = rootPos()
	if s and me and not s.stepped and (flat(me) - flat(s.pos)).Magnitude < 30 then
		s.stepped = true
		Feedback.bubble(s.pos + Y * 6.5, L("Live streamer", "คนไลฟ์สด"), L("Oops, sorry! 🙏 (going on the pavement)", "อุ๊ย ขอโทษค่ะ 🙏 (ขึ้นทางเท้าแป๊บ)"))
		s.model:PivotTo(s.model:GetPivot() + s.out * 4)
		s.pos += s.out * 4
	end
end

---------------------------------------------------------------------------------------------------
-- wrong-way rider along the kerb on your side
---------------------------------------------------------------------------------------------------
local wrong = nil
local function kitModel(kind: string): Model?
	local kit = ReplicatedStorage:FindFirstChild("GoDashTrafficKit")
	if not kit then return nil end
	local list = {}
	for _, m in ipairs(kit:GetChildren()) do
		local def = Vehicles.ById[m.Name]
		if def and def.class == kind and not def.pedal then table.insert(list, m) end
	end
	if #list == 0 then return nil end
	local pick = list[rng:NextInteger(1, #list)]
	if kind == "car" then
		for _, m in ipairs(list) do if m.Name == "pickup_dmax" then pick = m end end
	end
	local m = pick:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
	end
	return m
end

local function spawnWrongWay()
	local ra = roadAhead(170)
	if not ra then return end
	local m = kitModel("bike")
	if not m then return end
	local start = ra.p + ra.left * (ra.e.def.width / 2 - 1.4)
	m.Parent = folder
	wrong = { model = m, pos = start, dir = -ra.dir, y = m:GetAttribute("Y") or 2.2, born = os.clock(), said = false, honk = false }
	m:PivotTo(CFrame.lookAt(start + Y * wrong.y, start + Y * wrong.y + wrong.dir))
end

local function updateWrongWay(dt: number, me: Vector3)
	local w = wrong
	if not w then return end
	w.pos += w.dir * 13 * dt
	w.model:PivotTo(CFrame.lookAt(w.pos + Y * w.y, w.pos + Y * w.y + w.dir))
	local rel = flat(me) - flat(w.pos)
	local d = rel.Magnitude
	if not w.honk and d < 45 then
		w.honk = true
		oneShot(w.model.PrimaryPart or w.model:FindFirstChildWhichIsA("BasePart"), Sounds.horn, 0.5, 1.45)
	end
	if not w.said and d < 22 then
		w.said = true
		Feedback.bubble(w.pos + Y * 6, L("Wrong-way rider", "คนขี่ย้อนศร"), L("Coming through! My house is right there!", "ขอทางหน่อยพี่ บ้านอยู่ตรงนี้เอง!"))
		if rng:NextNumber() < 0.35 then Feed.post("wrongway", { pos = w.pos }, false) end
	end
	if os.clock() - w.born > 40 or (rel:Dot(w.dir) < -90) then
		w.model:Destroy()
		wrong = nil
	end
end

---------------------------------------------------------------------------------------------------
-- the party truck (รถแห่)
---------------------------------------------------------------------------------------------------
local truck = nil
local function spawnTruck()
	local graph = GPS.graph()
	local me = rootPos()
	if not graph or not me then return end
	local a = me + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * 240
	local path = graph:path(a, me + (me - a).Unit * 260)
	if not path or #path < 3 then return end
	local m = kitModel("car")
	if not m then return end
	local y = m:GetAttribute("Y") or 2.5
	m:PivotTo(CFrame.new(0, y, 0))
	local pivot0 = m:GetPivot()
	local cf0, size = m:GetBoundingBox()
	local bed = cf0 * CFrame.new(0, size.Y * 0.15, size.Z * 0.24) -- truck faces -Z: the bed is at +Z
	-- speakers: a wall of black boxes facing back, cones in them
	local spk
	for row = 0, 2 do
		for col = -1, 1 do
			local box = part({ Size = Vector3.new(1.5, 1.4, 1.2), CFrame = bed * CFrame.new(col * 1.55, 0.7 + row * 1.42, size.Z * 0.2), Color = Color3.fromRGB(22, 22, 24), Parent = m })
			part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 1.05, 1.05), CFrame = box.CFrame * CFrame.new(0, 0, 0.62) * CFrame.Angles(0, math.rad(90), 0),
				Color = Color3.fromRGB(60, 60, 64), Material = Enum.Material.Metal, Parent = m })
			spk = spk or box
		end
	end
	-- light bar and banner over the cab
	local frameCf = cf0 * CFrame.new(0, size.Y * 0.5 + 2.6, -size.Z * 0.05)
	part({ Size = Vector3.new(size.X + 0.4, 0.2, 0.2), CFrame = frameCf, Color = Color3.fromRGB(40, 40, 44), Parent = m })
	local lights = {}
	for i = -3, 3 do
		table.insert(lights, part({ Size = Vector3.new(0.5, 0.4, 0.4), CFrame = frameCf * CFrame.new(i * 0.62, 0.3, 0), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 60, 200), Parent = m }))
	end
	local banner = part({ Size = Vector3.new(size.X + 0.6, 1.3, 0.1), CFrame = frameCf * CFrame.new(0, 1.2, 0), Color = Color3.fromRGB(255, 210, 40), Parent = m })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local g = Instance.new("SurfaceGui"); g.Face = face; g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; g.PixelsPerStud = 40; g.LightInfluence = 0; g.Parent = banner
		local t = Instance.new("TextLabel"); t.BackgroundTransparency = 1; t.Size = UDim2.fromScale(1, 1); t.TextScaled = true; t.Font = Enum.Font.GothamBlack
		t.Text = "🔊 รถแห่ เสียงสะเทือนอีสาน 🔊"; t.TextColor3 = Color3.fromRGB(200, 20, 30); t.Parent = g
	end
	m.Parent = folder
	-- dancers on the bed, moved with the truck
	local dancers = {}
	for i, sx in ipairs({ -0.9, 0.9 }) do
		local dcf = bed * CFrame.new(sx, 0.2, -size.Z * 0.05)
		local fig = figure(dcf * CFrame.Angles(0, math.rad(180), 0), i == 1 and "hail" or "stand")
		if fig then table.insert(dancers, { model = fig, rel = pivot0:ToObjectSpace(fig:GetPivot()), phase = i * 1.7 }) end
	end
	local music = Instance.new("Sound")
	music.SoundId = Sounds.molam
	music.Looped = true
	music.Volume = 0.9
	music.RollOffMinDistance = 18
	music.RollOffMaxDistance = 230
	music.SoundGroup = Feedback.sfxGroup
	music.Parent = spk
	local eq = Instance.new("EqualizerSoundEffect"); eq.LowGain = 8; eq.MidGain = 0; eq.HighGain = -3; eq.Parent = music -- all bass
	music:Play()
	truck = { model = m, path = path, i = 1, s = 0, y = y, cf0 = cf0, dancers = dancers, lights = lights, born = os.clock(), posted = false }
end

local function updateTruck(dt: number, me: Vector3)
	local t = truck
	if not t then return end
	local path = t.path
	t.s += 11 * dt
	while t.i < #path and t.s > (path[t.i + 1] - path[t.i]).Magnitude do
		t.s -= (path[t.i + 1] - path[t.i]).Magnitude
		t.i += 1
	end
	if t.i >= #path or os.clock() - t.born > 90 then
		t.model:Destroy()
		for _, d in ipairs(t.dancers) do d.model:Destroy() end
		truck = nil
		return
	end
	local a, b = path[t.i], path[t.i + 1]
	local dir = flat(b - a).Unit
	local left = Vector3.new(dir.Z, 0, -dir.X)
	local pos = flat(a + (b - a).Unit * t.s) + left * 5
	local cf = CFrame.lookAt(pos + Y * t.y, pos + Y * t.y + dir)
	t.model:PivotTo(cf)
	local beat = os.clock() * 2 * math.pi * 2.1 -- about 126 bpm
	for _, d in ipairs(t.dancers) do
		d.model:PivotTo(cf * d.rel * CFrame.new(0, math.abs(math.sin(beat * 0.5 + d.phase)) * 0.35, 0) * CFrame.Angles(0, math.sin(beat * 0.25 + d.phase) * 0.5, 0))
	end
	for i, l in ipairs(t.lights) do
		l.Color = Color3.fromHSV(((os.clock() * 0.8) + i * 0.13) % 1, 0.9, 1)
	end
	local dist = (flat(me) - pos).Magnitude
	if dist < 45 then
		local cam = Workspace.CurrentCamera
		if cam and math.sin(beat) > 0.92 then cam.CFrame *= CFrame.new(0, 0.04 * (1 - dist / 45), 0) end -- the bass thumps
		if not t.posted then
			t.posted = true
			Feed.post("molam", { pos = pos }, false)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Songkran water fights
---------------------------------------------------------------------------------------------------
local soakers = {}
local soakedThisEvent = false
local overlay
local function splashScreen()
	if not overlay then
		local gui = Instance.new("ScreenGui"); gui.Name = "GoDashSplash"; gui.IgnoreGuiInset = true; gui.DisplayOrder = 40; gui.ResetOnSpawn = false
		gui.Parent = player:WaitForChild("PlayerGui")
		overlay = gui
	end
	for _ = 1, 9 do
		local d = Instance.new("TextLabel")
		d.BackgroundTransparency = 1
		d.Text = "💧"
		d.TextScaled = true
		d.Size = UDim2.fromOffset(rng:NextInteger(40, 110), rng:NextInteger(40, 110))
		d.Position = UDim2.fromScale(rng:NextNumber(0.05, 0.9), rng:NextNumber(0.05, 0.8))
		d.Parent = overlay
		TweenService:Create(d, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1, Position = d.Position + UDim2.fromScale(0, 0.15),
		}):Play()
		task.delay(2.3, function() d:Destroy() end)
	end
end

local function spawnSoakers()
	local ra = roadAhead(rng:NextNumber(60, 110))
	if not ra then return end
	local side = rng:NextNumber() < 0.75 and ra.left or -ra.left
	local base = ra.p + side * (ra.e.def.width / 2 + 1.2)
	local group = { pos = base, born = os.clock(), done = false, models = {} }
	for i = 1, 2 do
		local at = base + ra.dir * (i - 1.5) * 2.4
		local m = figure(CFrame.lookAt(at, at - side), i == 1 and "hail" or "stand")
		if m then
			local hand = m:FindFirstChild(i == 1 and "RightHand" or "LeftHand") :: BasePart?
			if hand then
				part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = hand.CFrame * CFrame.new(0, -0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
					Color = i == 1 and Color3.fromRGB(40, 140, 230) or Color3.fromRGB(240, 90, 160), Parent = m })
			end
			table.insert(group.models, m)
		end
	end
	table.insert(soakers, group)
end

local function updateSoakers(me: Vector3)
	for i = #soakers, 1, -1 do
		local g = soakers[i]
		local d = (flat(me) - flat(g.pos)).Magnitude
		if not g.done and d < 16 then -- they stand on the kerb; the rider passes in the lane
			g.done = true
			local a = Instance.new("Attachment"); a.WorldPosition = g.pos + Y * 3; a.Parent = Workspace.Terrain
			local pe = Instance.new("ParticleEmitter")
			pe.Color = ColorSequence.new(Color3.fromRGB(150, 210, 255)); pe.Size = NumberSequence.new(0.5, 0.1); pe.Lifetime = NumberRange.new(0.5, 0.8)
			pe.Speed = NumberRange.new(14, 22); pe.SpreadAngle = Vector2.new(25, 25); pe.Acceleration = Vector3.new(0, -50, 0); pe.Rate = 0
			pe.EmissionDirection = Enum.NormalId.Top
			pe.Parent = a
			a.WorldCFrame = CFrame.lookAt(g.pos + Y * 3, me + Y * 2) * CFrame.Angles(math.rad(-90), 0, 0)
			pe:Emit(60)
			task.delay(1.5, function() a:Destroy() end)
			oneShot(nil, Sounds.puddle, 0.8, 1.1)
			splashScreen()
			Feedback.bubble(g.pos + Y * 6, L("Songkran", "สงกรานต์"), L("Happy Songkran!! 💦", "สุขสันต์วันสงกรานต์!! 💦"))
			if not soakedThisEvent then
				soakedThisEvent = true
				Feedback.toast(L("💦 Soaked! Happy Songkran", "💦 โดนสาด! เปียกโชกเลย สุขสันต์วันสงกรานต์"), "good")
				task.delay(2.5, function() Feed.post("songkran", { pos = g.pos }, true) end)
			end
		end
		if os.clock() - g.born > 35 or d > 300 then
			for _, m in ipairs(g.models) do m:Destroy() end
			table.remove(soakers, i)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- the neighbour's questions
---------------------------------------------------------------------------------------------------
local QUESTIONS = {
	{ L("When are you getting married? My grandson has married twice already!", "เมื่อไหร่จะแต่งงานล่ะ หลานป้าแต่งไปสองรอบแล้วนะ"),
		{ L("No girlfriend or boyfriend yet, auntie 😅", "ยังไม่มีแฟนเลยป้า 😅"), L("I'm married to my job (deliveries)", "แต่งกับงานไปแล้ว (ส่งอาหาร)"), L("That's my business, auntie", "เรื่องส่วนตัวนะป้า") } },
	{ L("How much does a rider make a month? My son is a civil servant, you know.", "ทำไรเดอร์ได้เดือนละเท่าไหร่ ลูกป้าเป็นข้าราชการนะ"),
		{ L("Enough to get by", "พอกินพอใช้ป้า"), L("A million (in my dreams)", "เป็นล้าน (ในฝัน)"), L("More than your son", "มากกว่าลูกป้าอีก") } },
	{ L("You've put on weight! Eating all the food you deliver?", "อ้วนขึ้นนะเนี่ย กินแต่ข้าวที่ไปส่งเหรอ"),
		{ L("I have been eating a lot lately", "ช่วงนี้กินเยอะจริง"), L("Chubby but kind-hearted", "อ้วนแต่ใจดีนะป้า"), L("So have you, auntie", "ป้าก็เหมือนกันนะ") } },
	{ L("How much is that bike a month? It's on instalments, isn't it?", "รถคันนี้ผ่อนเดือนละเท่าไหร่ ผ่อนใช่ไหม"),
		{ L("Paid cash! (lie)", "ซื้อสด! (โกหก)"), L("Paying until the end of time", "ผ่อนจนกว่าชาติจะหาไม่"), L("Not telling", "ไม่บอกหรอก") } },
	{ L("Why don't you take the civil service exam? So secure!", "ทำไมไม่ไปสอบเป็นข้าราชการ มั่นคงนะ"),
		{ L("I'm studying for it", "กำลังอ่านหนังสืออยู่"), L("Civil servants get up too early", "ข้าราชการต้องตื่นเช้า ไม่ไหว"), L("Will you sit it for me?", "ป้าไปสอบแทนไหมล่ะ") } },
}
local auntieAt = os.clock() - 200
local auntieBusy = false
local function checkAuntie(me: Vector3)
	if auntieBusy or State.cutscene or Drive.info.driving then return end
	local plot = State.plot
	if not plot or not plot.base then return end
	local basePos = typeof(plot.base) == "CFrame" and plot.base.Position or plot.base.Position
	if (flat(me) - flat(basePos)).Magnitude > 38 or os.clock() - auntieAt < 360 then return end
	auntieAt = os.clock()
	auntieBusy = true
	task.spawn(function()
		local ok, err = pcall(function()
		local baseCf = typeof(plot.base) == "CFrame" and plot.base or plot.base.CFrame -- State.plot.base is a CFrame
		local size = typeof(plot.size) == "Vector3" and plot.size or Vector3.new(44, 0, 44)
		local corner = baseCf * CFrame.new(size.X / 2 + 2, 0, -size.Z / 2 + 4)
		local at = Vector3.new(corner.Position.X, baseCf.Position.Y + 0.6, corner.Position.Z)
		local m = figure(CFrame.lookAt(at, Vector3.new(me.X, at.Y, me.Z)), "hail")
		if m then RiderPose.dress(m, Color3.fromRGB(220, 110, 160), Color3.fromRGB(70, 50, 90)) end
		local q = QUESTIONS[rng:NextInteger(1, #QUESTIONS)]
		Feedback.bubble(at + Y * 6.5, L("Auntie next door", "ป้าข้างบ้าน"), q[1])
		local n = Choice.ask({ icon = "👵", title = L("Auntie next door", "ป้าข้างบ้าน"), text = q[1], answers = { { q[2][1] }, { q[2][2] }, { q[2][3], Color3.fromRGB(200, 70, 70) } }, seconds = 25 })
		if n then
			Net.send("Social", "auntie", n)
			local reply = n == 1 and L("Hmm, good child. Off you go then.", "อืม เด็กดี ไปเถอะ") or (n == 2 and L("Hahaha! You're so funny!", "ฮ่าๆๆ ตลกจริงเชียว!") or L("Hmph! I'm telling the whole soi!", "ชิ! เดี๋ยวป้าเล่าให้คนทั้งซอยฟัง!"))
			Feedback.bubble(at + Y * 6.5, L("Auntie next door", "ป้าข้างบ้าน"), reply)
		end
		task.wait(5)
		if m then m:Destroy() end
		end)
		if not ok then warn("[StreetLife] neighbour: " .. tostring(err)) end
		auntieBusy = false
	end)
end

---------------------------------------------------------------------------------------------------
-- U-turn in the middle of a main road
---------------------------------------------------------------------------------------------------
local headings = {}
local uturnAt = 0
local function checkUturn(c)
	local ch = c.chassis
	local v = flat(ch.AssemblyLinearVelocity)
	local now = os.clock()
	if v.Magnitude < 6 then return end
	local h = v.Unit
	table.insert(headings, { t = now, h = h })
	while headings[1] and now - headings[1].t > 3.5 do table.remove(headings, 1) end
	if now - uturnAt < 90 then return end
	for _, e in ipairs(headings) do
		if e.h:Dot(h) < -0.85 then
			local graph = GPS.graph()
			local edge = graph and graph:nearest(ch.Position)
			if edge and edge.type == "main" then
				uturnAt = now
				headings = {}
				Feedback.toast(L("🙃 A U-turn right here? The sign said the next one is 3 km away", "🙃 กลับรถตรงนี้เลย? ป้ายบอกยูเทิร์นอีก 3 กิโลนะ"), nil)
				if rng:NextNumber() < 0.4 then task.delay(2, function() Feed.post("uturn", nil, true) end) end
			end
			return
		end
	end
end

---------------------------------------------------------------------------------------------------
function StreetLife.start()
	folder = Instance.new("Folder")
	folder.Name = "GoDashStreetLife"
	folder.Parent = Workspace
	task.spawn(function()
		local t0 = os.clock()
		while not GPS.graph() and os.clock() - t0 < 30 do task.wait(0.5) end
		local graph = GPS.graph()
		if not graph then return end
		buildHoles(graph)
		while not State.world and os.clock() - t0 < 60 do task.wait(0.5) end
		buildFloods(graph)
	end)
	-- what shows near the camera: every half second
	task.spawn(function()
		while true do
			task.wait(0.5)
			local cam = Workspace.CurrentCamera
			if cam and #holes > 0 then showHoles(cam.CFrame.Position) end
		end
	end)
	-- who turns up on the road: now and then while riding
	task.spawn(function()
		local nextStream, nextWrong, nextTruck, nextSoak = os.clock() + rng:NextNumber(90, 160), os.clock() + rng:NextNumber(120, 220), os.clock() + rng:NextNumber(150, 300), 0
		while true do
			task.wait(1)
			local now = os.clock()
			local riding = Drive.info.driving and not State.cutscene
			if riding then
				if now > nextStream and not streamer then nextStream = now + rng:NextNumber(150, 260); spawnStreamer() end
				if now > nextWrong and not wrong then nextWrong = now + rng:NextNumber(170, 300); spawnWrongWay() end
				local songkran = (Workspace:GetAttribute("Songkran") or 0) > os.time()
				if songkran and now > nextSoak and #soakers < 3 then nextSoak = now + rng:NextNumber(5, 9); spawnSoakers() end
			end
			if not ((Workspace:GetAttribute("Songkran") or 0) > os.time()) then soakedThisEvent = false end
			if now > nextTruck and not truck and not State.cutscene then
				local hour = game:GetService("Lighting").ClockTime
				nextTruck = now + ((hour >= 16 or hour < 1) and rng:NextNumber(240, 420) or rng:NextNumber(420, 700))
				spawnTruck()
			end
			local me = rootPos()
			if me then checkAuntie(me) end
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local me = rootPos()
		if not me then return end
		local cam = Workspace.CurrentCamera
		updateFloods(dt, cam and cam.CFrame.Position or me)
		local c = Drive.current()
		if c and c.chassis and not State.cutscene then
			checkHoles(c)
			checkUturn(c)
		end
		updateStreamer(me)
		updateWrongWay(dt, me)
		updateTruck(dt, me)
		updateSoakers(me)
	end)
	-- Studio test hook: Workspace attribute QaStreet = "stream" | "wrong" | "truck" | "soak" | "auntie" spawns one now
	if RunService:IsStudio() then
		Workspace:GetAttributeChangedSignal("QaStreet"):Connect(function()
			local v = Workspace:GetAttribute("QaStreet")
			if v == nil then return end
			Workspace:SetAttribute("QaStreet", nil)
			if v == "stream" then spawnStreamer() elseif v == "wrong" then spawnWrongWay() elseif v == "truck" then spawnTruck()
			elseif v == "soak" then spawnSoakers() elseif v == "auntie" then auntieAt = -1e9; local me = rootPos(); if me then checkAuntie(me) end end
		end)
	end
	Drive.onHorn = StreetLife.honked
	-- the municipal officer's whistle with the pavement ticket; Songkran music while the water flies
	Net.listen("Notify", function(kind, p)
		if kind == "scene" and type(p) == "table" and p.kind == "fine" and p.reason == "sidewalk" then oneShot(nil, Sounds.whistle, 0.7, 1) end
	end)
	local song = Instance.new("Sound")
	song.SoundId = Sounds.songkranMusic
	song.Looped = true
	song.Volume = 0
	song.SoundGroup = Feedback.sfxGroup
	song.Parent = game:GetService("SoundService")
	task.spawn(function()
		while true do
			task.wait(0.5)
			local on = (Workspace:GetAttribute("Songkran") or 0) > os.time()
			if on and not song.IsPlaying then song:Play() end
			song.Volume += ((on and 0.28 or 0) - song.Volume) * 0.3
			if not on and song.IsPlaying and song.Volume < 0.01 then song:Stop() end
		end
	end)
	local _ = Util
end

return StreetLife
