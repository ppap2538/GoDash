-- Big loads strapped on a vehicle (2026-11-19, viral pack; Jobs.BIGLOADS, server/JobService "Cargo").
-- Every client draws every vehicle's load: the model attribute "Cargo" = the load id.
--   * on a delivery box (scooters, mopeds) it sits on the box lid; on a bag bike behind the seat; on a car, the roof
--   * it wobbles: a spring on the vehicle's own acceleration tips it back when you pull away, forward and a little
--     ahead when you brake, sideways in a turn, and hops on bumps; tall loads (the fridge, the palm) swing most
--   * "CargoDrop" (VehicleService, on a crash): a loose copy flies off with the vehicle's speed and tumbles down the
--     road ("💥 ของตก!"), then the load is strapped back on a few seconds later
-- Built from parts, base at the origin, the vehicle's forward = -Z (the load's face looks back, at the chase camera).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vehicles = require(ReplicatedStorage:WaitForChild("Shared").Config.Vehicles)
local Bricks = require(ReplicatedStorage:WaitForChild("Shared").Bricks)
local Lang = require(script.Parent.Lang)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)

local Cargo = {}
local L = Lang.pick
local SHOW = 260
local drawn = {} :: { [Model]: any }
local holder: Folder
local loose: Folder

---------------------------------------------------------------------------------------------------
-- the loads
---------------------------------------------------------------------------------------------------
local function newPart(m: Model, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then p.Shape = shape end
	p.Transparency = transparency or 0
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, false, true
	if Bricks.ON then Bricks.part(p) end -- (2026-11-20) toy-brick look
	p.Parent = m
	return p
end

-- a vertical cylinder (Roblox cylinders lie along X)
local function cyl(m: Model, dia: number, h: number, at: Vector3, color: Color3, material: Enum.Material?, transparency: number?): Part
	return newPart(m, Vector3.new(h, dia, dia), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), color, material, Enum.PartType.Cylinder, transparency)
end

local STRAP = Color3.fromRGB(34, 34, 38)
-- two straps over the top and down the front and back, along Z (alongX = across instead)
local function straps(m: Model, w: number, h: number, d: number, alongX: boolean?)
	for _, s in ipairs({ -1, 1 }) do
		if alongX then
			local z = s * d / 4
			newPart(m, Vector3.new(w + 0.08, 0.06, 0.2), CFrame.new(0, h + 0.03, z), STRAP, Enum.Material.Fabric)
			newPart(m, Vector3.new(0.06, h, 0.2), CFrame.new(-w / 2 - 0.03, h / 2, z), STRAP, Enum.Material.Fabric)
			newPart(m, Vector3.new(0.06, h, 0.2), CFrame.new(w / 2 + 0.03, h / 2, z), STRAP, Enum.Material.Fabric)
		else
			local x = s * w / 4
			newPart(m, Vector3.new(0.2, 0.06, d + 0.08), CFrame.new(x, h + 0.03, 0), STRAP, Enum.Material.Fabric)
			newPart(m, Vector3.new(0.2, h, 0.06), CFrame.new(x, h / 2, -d / 2 - 0.03), STRAP, Enum.Material.Fabric)
			newPart(m, Vector3.new(0.2, h, 0.06), CFrame.new(x, h / 2, d / 2 + 0.03), STRAP, Enum.Material.Fabric)
		end
	end
end

local BUILD = {}

function BUILD.fridge(m: Model)
	local w, h, d = 2.3, 4.4, 2.0
	local white, steel, dark = Color3.fromRGB(238, 240, 238), Color3.fromRGB(176, 182, 188), Color3.fromRGB(60, 64, 70)
	newPart(m, Vector3.new(w, h, d), CFrame.new(0, h / 2 + 0.12, 0), white)
	-- the doors face back, at the chase camera: freezer on top, the big door below, a seam between them
	newPart(m, Vector3.new(w - 0.1, 0.05, 0.03), CFrame.new(0, 3.25, d / 2 + 0.01), dark)
	newPart(m, Vector3.new(0.12, 0.7, 0.12), CFrame.new(w / 2 - 0.3, 3.75, d / 2 + 0.08), steel, Enum.Material.Metal)
	newPart(m, Vector3.new(0.12, 1.4, 0.12), CFrame.new(w / 2 - 0.3, 2.35, d / 2 + 0.08), steel, Enum.Material.Metal)
	newPart(m, Vector3.new(0.5, 0.36, 0.02), CFrame.new(-w / 2 + 0.45, 2.7, d / 2 + 0.01), Color3.fromRGB(255, 214, 64)) -- the energy label
	for _, x in ipairs({ -0.9, 0.9 }) do
		for _, z in ipairs({ -0.75, 0.75 }) do newPart(m, Vector3.new(0.2, 0.12, 0.2), CFrame.new(x, 0.06, z), dark) end
	end
	straps(m, w, h + 0.12, d, true)
	return { sway = 1.25, h = h }
end

function BUILD.mattress(m: Model)
	local w, h, d = 6.6, 0.9, 3.8
	local cloth, piping = Color3.fromRGB(248, 246, 240), Color3.fromRGB(120, 168, 230)
	newPart(m, Vector3.new(w, h, d), CFrame.new(0, h / 2, 0.4), cloth, Enum.Material.SmoothPlastic)
	for i = -2, 2 do -- quilted stripes on top
		newPart(m, Vector3.new(w - 0.3, 0.03, 0.1), CFrame.new(0, h + 0.01, 0.4 + i * 0.7), Color3.fromRGB(176, 204, 240), Enum.Material.SmoothPlastic)
	end
	-- blue piping round the top edge (four thin strips, so the white top shows)
	newPart(m, Vector3.new(w + 0.06, 0.1, 0.1), CFrame.new(0, h - 0.04, 0.4 - d / 2), piping)
	newPart(m, Vector3.new(w + 0.06, 0.1, 0.1), CFrame.new(0, h - 0.04, 0.4 + d / 2), piping)
	newPart(m, Vector3.new(0.1, 0.1, d + 0.06), CFrame.new(-w / 2, h - 0.04, 0.4), piping)
	newPart(m, Vector3.new(0.1, 0.1, d + 0.06), CFrame.new(w / 2, h - 0.04, 0.4), piping)
	straps(m, w, h, d, false)
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") and p.Color == STRAP then p.CFrame += Vector3.new(0, 0, 0.4) end
	end
	return { sway = 0.8, h = h }
end

function BUILD.durian(m: Model)
	local skin, stem = Color3.fromRGB(128, 142, 52), Color3.fromRGB(110, 84, 48)
	cyl(m, 2.7, 0.8, Vector3.new(0, 0.4, 0), Color3.fromRGB(196, 158, 96), Enum.Material.WoodPlanks) -- the woven basket
	cyl(m, 2.85, 0.14, Vector3.new(0, 0.82, 0), Color3.fromRGB(150, 112, 62), Enum.Material.WoodPlanks)
	local spots = { { 0, 1.35, 0 } }
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		table.insert(spots, { math.cos(a) * 0.82, 1.3, math.sin(a) * 0.82 })
	end
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + 0.5
		table.insert(spots, { math.cos(a) * 0.45, 2.1, math.sin(a) * 0.45 })
	end
	table.insert(spots, { 0, 2.85, 0 })
	for i, s in ipairs(spots) do
		local dia = 1.0 + ((i * 37) % 5) * 0.04
		local p = newPart(m, Vector3.new(dia, dia * 1.12, dia), CFrame.new(s[1], s[2], s[3]) * CFrame.Angles(0, i, 0.2), skin, Enum.Material.Pebble, Enum.PartType.Ball)
		p.Name = "Durian"
		if s[2] > 2 then cyl(m, 0.12, 0.32, Vector3.new(s[1], s[2] + dia * 0.6, s[3]), stem, Enum.Material.Wood) end
	end
	return { sway = 0.9, h = 3.3 }
end

function BUILD.plant(m: Model)
	local pot, leaf = Color3.fromRGB(196, 104, 62), Color3.fromRGB(70, 150, 66)
	cyl(m, 2.0, 1.7, Vector3.new(0, 0.85, 0), pot)
	cyl(m, 2.25, 0.25, Vector3.new(0, 1.62, 0), Color3.fromRGB(176, 92, 54))
	cyl(m, 1.9, 0.08, Vector3.new(0, 1.66, 0), Color3.fromRGB(70, 50, 34), Enum.Material.Ground)
	local trunk = Color3.fromRGB(130, 96, 60)
	newPart(m, Vector3.new(0.38, 1.7, 0.38), CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, 0.06), trunk, Enum.Material.Wood)
	newPart(m, Vector3.new(0.32, 1.6, 0.32), CFrame.new(0.1, 4.05, 0) * CFrame.Angles(0, 0, -0.08), trunk, Enum.Material.Wood)
	local top = Vector3.new(0.05, 4.85, 0)
	for i = 0, 8 do
		local a = i / 9 * math.pi * 2
		-- each frond reaches out and hangs down (a positive pitch tips the far end down), two pieces for a curve
		local base = CFrame.new(top) * CFrame.Angles(0, a, 0)
		local inner = base * CFrame.Angles(0.18, 0, 0) * CFrame.new(0, 0, -1.0)
		local f = newPart(m, Vector3.new(0.7, 0.06, 2.0), inner, leaf, Enum.Material.Grass)
		f.Name = "Frond"
		local outer = base * CFrame.Angles(0.18, 0, 0) * CFrame.new(0, 0, -1.95) * CFrame.Angles(0.55, 0, 0) * CFrame.new(0, 0, -0.85)
		local g = newPart(m, Vector3.new(0.55, 0.06, 1.8), outer, Color3.fromRGB(86, 164, 70), Enum.Material.Grass)
		g.Name = "Frond"
	end
	return { sway = 1.55, h = 5.2 }
end

function BUILD.water(m: Model)
	local glass, cap = Color3.fromRGB(168, 214, 244), Color3.fromRGB(70, 130, 210)
	local pw, ph, pd = 1.0, 0.95, 0.75
	for ix = -1, 1 do
		for iz = 0, 1 do
			for iy = 0, 1 do
				local at = Vector3.new(ix * (pw + 0.02), iy * (ph + 0.02) + ph / 2, (iz - 0.5) * (pd + 0.02))
				newPart(m, Vector3.new(pw, ph, pd), CFrame.new(at), glass, Enum.Material.Glass, nil, 0.25)
				newPart(m, Vector3.new(pw + 0.02, 0.18, pd + 0.02), CFrame.new(at + Vector3.new(0, 0.1, 0)), cap, Enum.Material.SmoothPlastic) -- the label band
			end
		end
	end
	straps(m, 3 * pw + 0.04, 2 * ph + 0.02, 2 * pd + 0.02, true)
	return { sway = 0.7, h = 2 }
end

function BUILD.fans(m: Model, st)
	local white, grey, blade = Color3.fromRGB(240, 242, 245), Color3.fromRGB(150, 154, 160), Color3.fromRGB(120, 190, 240)
	st.blades = {}
	local spots = { { -0.75, -0.55, 0.1 }, { 0.75, -0.55, -0.12 }, { -0.75, 0.6, -0.08 }, { 0.75, 0.6, 0.14 } }
	for _, s in ipairs(spots) do
		local base = CFrame.new(s[1], 0, s[2]) * CFrame.Angles(0, 0, s[3])
		local b = cyl(m, 1.15, 0.14, Vector3.zero, grey)
		b.CFrame = base * CFrame.new(0, 0.07, 0) * CFrame.Angles(0, 0, math.rad(90))
		local pole = cyl(m, 0.14, 2.3, Vector3.zero, white)
		pole.CFrame = base * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90))
		-- the head looks back: a see-through cage disc, a hub and three blades that spin in the wind
		local headCf = base * CFrame.new(0, 2.5, 0.1)
		newPart(m, Vector3.new(0.3, 1.5, 1.5), headCf * CFrame.Angles(0, math.rad(90), 0), white, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, 0.55)
		local hub = newPart(m, Vector3.new(0.34, 0.34, 0.34), headCf * CFrame.new(0, 0, 0.2), Color3.fromRGB(70, 140, 220), nil, Enum.PartType.Ball)
		for k = 0, 2 do
			local bl = newPart(m, Vector3.new(0.3, 0.62, 0.04), CFrame.new(), blade, Enum.Material.SmoothPlastic, nil, 0.1)
			table.insert(st.blades, { part = bl, hub = hub, a = k / 3 * math.pi * 2 })
		end
	end
	return { sway = 1.0, h = 3.3 }
end

-- (2026-11-19, owner: "พวก Asset ต่างๆขอสมจริงหน่อย") the real textured models, made with Studio's mesh generator and
-- kept in ReplicatedStorage.GoDashModels.Cargo.<id> (saved in the place). The part-built ones above stay as the
-- fallback while a model is missing. yaw turns the model so its face looks back; straps = tie-down straps over it.
local MESH = {
	fridge = { yaw = math.pi, sway = 1.25, straps = "x" },
	mattress = { yaw = 0, sway = 0.8, straps = "z", z = 0.4 },
	durian = { yaw = 0, sway = 0.9 },
	plant = { yaw = 0, sway = 1.55 },
	water = { yaw = 0, sway = 0.7, straps = "x" },
	fans = { yaw = math.pi, sway = 1.0 }, -- (the model is tied with its own rope; straps over it looked like a cage)
}

local function fromMesh(m: Model, kind: string)
	if Bricks.ON then return nil end -- (toy-brick look: the part-built loads, not the realistic meshes)
	local store = ReplicatedStorage:FindFirstChild("GoDashModels")
	local folder = store and store:FindFirstChild("Cargo")
	local tpl = folder and folder:FindFirstChild(kind)
	local spec = MESH[kind]
	if not (tpl and spec) then return nil end
	local c = tpl:Clone()
	local cf, size = c:GetBoundingBox()
	local place = CFrame.new(0, size.Y / 2, spec.z or 0) * CFrame.Angles(0, spec.yaw, 0)
	for _, p in ipairs(c:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CFrame = place * cf:ToObjectSpace(p.CFrame)
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, false, true
			p.CastShadow = true
			p.Parent = m
		end
	end
	c:Destroy()
	if spec.straps then
		local before = #m:GetChildren()
		straps(m, size.X, size.Y, size.Z, spec.straps == "x")
		if spec.z then
			for i, p in ipairs(m:GetChildren()) do
				if i > before and p:IsA("BasePart") then p.CFrame += Vector3.new(0, 0, spec.z) end
			end
		end
	end
	return { sway = spec.sway, h = size.Y }
end

---------------------------------------------------------------------------------------------------
-- drawing
---------------------------------------------------------------------------------------------------
local function build(kind: string)
	local m = Instance.new("Model")
	m.Name = "Cargo_" .. kind
	local st = { kind = kind }
	local info = fromMesh(m, kind) or (BUILD[kind] or BUILD.fridge)(m, st)
	st.sway, st.h = info.sway, info.h
	-- one anchored root at the base; everything else welded to it, so one CFrame write moves the load
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored, root.CanCollide, root.CanQuery, root.CanTouch = true, false, false, false
	root.CFrame = CFrame.new()
	root.Parent = m
	m.PrimaryPart = root
	local blades = {}
	if st.blades then for _, b in ipairs(st.blades) do blades[b.part] = true end end
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") and p ~= root and not blades[p] then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = root, p
			w.Parent = p
		end
	end
	-- fan blades turn on a Weld whose C0 we spin
	if st.blades then
		for _, b in ipairs(st.blades) do
			local w = Instance.new("Weld")
			w.Part0, w.Part1 = b.hub, b.part
			w.C0 = CFrame.Angles(0, 0, b.a) * CFrame.new(0, 0.34, -0.05)
			w.Parent = b.part
			b.weld = w
		end
	end
	st.model, st.root = m, root
	return st
end

-- where the load sits, in the frame of the vehicle's Body (it leans with the bike)
local function mountOf(model: Model, frame: BasePart): Vector3
	local box = model:FindFirstChild("DeliveryBox", true) or model:FindFirstChild("Bag", true)
	if box and box:IsA("BasePart") then
		return frame.CFrame:PointToObjectSpace(box.Position + Vector3.new(0, box.Size.Y / 2, 0))
	end
	local def = Vehicles.ById[model:GetAttribute("VehicleId") or ""]
	if def and def.class == "car" then
		local cf, size = model:GetBoundingBox()
		return frame.CFrame:PointToObjectSpace(Vector3.new(cf.Position.X, cf.Position.Y + size.Y / 2, cf.Position.Z))
	end
	return Vector3.new(0, 1.3, 1.9)
end

local function fling(st, vehicle: Model, chassis: BasePart)
	local c = st.model:Clone()
	local root = c.PrimaryPart :: BasePart
	for _, p in ipairs(c:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = p ~= root and p.Size.Magnitude > 0.6
			p.Massless = p ~= root and not p.CanCollide
		end
	end
	root.CanCollide = false
	root.Massless = true
	root.Anchored = false
	c.Parent = loose
	local v = chassis.AssemblyLinearVelocity
	local side = chassis.CFrame.RightVector * (math.random() < 0.5 and -1 or 1)
	root.AssemblyLinearVelocity = v * 0.75 + Vector3.new(0, 20, 0) + side * 6
	root.AssemblyAngularVelocity = Vector3.new(math.random() * 6 - 3, math.random() * 4 - 2, math.random() * 6 - 3)
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(180, 42)
	tag.StudsOffsetWorldSpace = Vector3.new(0, st.h + 2, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 140
	tag.Adornee = root
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 236, 120)
	t.TextStrokeTransparency = 0.2
	t.Text = L("💥 It fell off!", "💥 ของตก!")
	t:SetAttribute("NoTranslate", true)
	t.Parent = tag
	tag.Parent = c
	task.delay(2.2, function() tag:Destroy() end)
	task.delay(8, function()
		for i = 1, 10 do
			for _, p in ipairs(c:GetDescendants()) do
				if p:IsA("BasePart") and p ~= root then p.LocalTransparencyModifier = i / 10 end
			end
			task.wait(0.05)
		end
		c:Destroy()
	end)
end

local function forget(vehicle: Model)
	local st = drawn[vehicle]
	if not st then return end
	if st.conn then st.conn:Disconnect() end
	st.model:Destroy()
	drawn[vehicle] = nil
end

local function step(dt: number)
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	local now = os.clock()
	local seen = {}
	for _, vehicle in ipairs(CollectionService:GetTagged("GoDashVehicle")) do
		local kind = vehicle:GetAttribute("Cargo")
		if type(kind) == "string" and vehicle:IsA("Model") and vehicle.Parent then
			local chassis = vehicle.PrimaryPart or vehicle:FindFirstChild("Chassis") :: BasePart?
			local frame = (vehicle:FindFirstChild("Body") or chassis) :: BasePart?
			if chassis and frame and (chassis.Position - camPos).Magnitude < SHOW then
				seen[vehicle] = true
				local st = drawn[vehicle]
				if st and st.kind ~= kind then forget(vehicle); st = nil end
				if not st then
					st = build(kind)
					st.mount = mountOf(vehicle, frame)
					st.pitch, st.roll, st.vp, st.vr, st.slide, st.vs, st.hop, st.vh = 0, 0, 0, 0, 0, 0, 0, 0
					st.lastVel = chassis.AssemblyLinearVelocity
					st.hiddenUntil = 0
					st.conn = vehicle:GetAttributeChangedSignal("CargoDrop"):Connect(function()
						local t = vehicle:GetAttribute("CargoDrop")
						if type(t) == "number" and Workspace:GetServerTimeNow() - t < 3 and os.clock() - (st.droppedAt or -1e9) > 1 then
							st.droppedAt = os.clock()
							fling(st, vehicle, chassis)
							st.hiddenUntil = os.clock() + 3.2
						end
					end)
					drawn[vehicle] = st
				end
				-- the spring: the load leans against the vehicle's acceleration, in the vehicle's own frame
				local vel = chassis.AssemblyLinearVelocity
				local acc = (vel - st.lastVel) / math.max(dt, 1 / 240)
				st.lastVel = vel
				local a = frame.CFrame:VectorToObjectSpace(acc)
				local k, c, s = 60, 7, st.sway
				-- pull away (a.Z < 0, forward is -Z): tips back; brake: tips forward and slides ahead
				st.vp += (-st.pitch * k - st.vp * c + math.clamp(a.Z, -80, 80) * 0.016 * s) * dt
				st.vr += (-st.roll * k - st.vr * c - math.clamp(a.X, -80, 80) * 0.014 * s) * dt
				st.vs += (-st.slide * 40 - st.vs * 8 + math.clamp(a.Z, -80, 0) * 0.006) * dt
				st.vh += (-st.hop * 90 - st.vh * 9 + math.clamp(a.Y, -60, 120) * 0.004) * dt
				st.pitch = math.clamp(st.pitch + st.vp * dt, -0.35, 0.35)
				st.roll = math.clamp(st.roll + st.vr * dt, -0.35, 0.35)
				st.slide = math.clamp(st.slide + st.vs * dt, -0.6, 0.1)
				st.hop = math.clamp(st.hop + st.vh * dt, -0.05, 0.35)
				-- and a little life of its own on the road
				local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
				local idle = math.sin(now * 7.3) * 0.012 * math.min(speed / 30, 1) * s
				local cf = frame.CFrame * CFrame.new(st.mount + Vector3.new(0, st.hop, st.slide))
					* CFrame.Angles(st.pitch, 0, st.roll + idle)
				if now < st.hiddenUntil then
					st.model.Parent = nil
				else
					st.model.Parent = holder
					st.root.CFrame = cf
				end
				if st.blades then
					local spin = now * (4 + speed * 0.6)
					for _, b in ipairs(st.blades) do b.weld.C0 = CFrame.Angles(0, 0, b.a + spin) * CFrame.new(0, 0.34, -0.05) end
				end
			end
		end
	end
	for vehicle in pairs(drawn) do
		if not seen[vehicle] then forget(vehicle) end
	end
end

function Cargo.start()
	holder = Instance.new("Folder")
	holder.Name = "GoDashCargo"
	holder.Parent = Workspace
	loose = Instance.new("Folder")
	loose.Name = "GoDashLooseCargo"
	loose.Parent = Workspace
	RunService.RenderStepped:Connect(step)
	-- a word when the load goes on
	local told = {}
	State.onJob(function(js)
		local j = js and js.job
		if j and j.cargo and j.stage == "dropoff" and not told[j.id] then
			told[j.id] = true
			Feedback.toast(L("📦 Strapped on! Ride gently: hard braking makes it slide, a crash throws it off",
				"📦 มัดของแน่นแล้ว! ขับนุ่มๆ นะ เบรกแรงของจะไถล ชนเมื่อไหร่ของตก"), "good")
		end
	end)
end

return Cargo
