-- Builds drivable vehicles from Config/Vehicles. Layout of every vehicle:
--   Chassis  (invisible box, the only collider and the only part with mass; physics root)
--   Body     (invisible pivot welded to Chassis by "BodyWeld"; the client tilts it for lean/pitch)
--   visuals, DriveSeat and passenger points are welded to Body
-- Local frame: forward = -Z, up = +Y, chassis centre = origin. Driving physics is in the client
-- VehicleController (the driver owns the assembly); this file is geometry only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Assets = require(script.Parent.Assets)
local Rig = require(ReplicatedStorage.Shared.Rig)
local RiderPose = require(ReplicatedStorage.Shared.RiderPose)
local Bricks = require(ReplicatedStorage.Shared.Bricks)

local Factory = {}

local V3 = Vector3.new
local CF = CFrame.new
local rad = math.rad
local M = Enum.Material

local BLACK = Color3.fromRGB(26, 26, 28)
local DARK = Color3.fromRGB(52, 54, 58)
local GLASS = Color3.fromRGB(40, 56, 70)
local CHROME = Color3.fromRGB(190, 194, 200)
local GODASH = Color3.fromRGB(28, 168, 84)

local function newBuilder(model: Model, body: BasePart)
	local function add(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = mat or M.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		if shape then p.Shape = shape end
		p.CFrame = body.CFrame * cf
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = p
		w.Parent = p
		p.Parent = model
		return p
	end
	local function wedge(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): WedgePart
		local p = Instance.new("WedgePart")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = mat or M.SmoothPlastic
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.CFrame = body.CFrame * cf
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = p
		w.Parent = p
		p.Parent = model
		return p
	end
	local function wheel(name: string, x: number, y: number, z: number, r: number, width: number)
		local tire = add(name, V3(width, r * 2, r * 2), CF(x, y, z), BLACK, M.SmoothPlastic, Enum.PartType.Cylinder)
		add(name .. "Hub", V3(width + 0.06, r * 1.1, r * 1.1), CF(x, y, z), CHROME, M.Metal, Enum.PartType.Cylinder)
		return tire
	end
	return add, wedge, wheel
end

local function logo(part: BasePart, face: Enum.NormalId)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0.4
	g.MaxDistance = 120
	g.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = "GoDash"
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Parent = g
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.1, 0); pad.PaddingRight = UDim.new(0.1, 0)
	pad.PaddingTop = UDim.new(0.28, 0); pad.PaddingBottom = UDim.new(0.28, 0)
	pad.Parent = t
end

local function lamp(part: BasePart, color: Color3, range: number, angle: number, brightness: number)
	local l = Instance.new("SpotLight")
	l.Name = "Beam"
	l.Face = Enum.NormalId.Front
	l.Color = color
	l.Range = range
	l.Angle = angle
	l.Brightness = brightness
	l.Enabled = false
	l.Shadows = false
	l.Parent = part
end

local function buildBicycle(def, add, color: Color3)
	local wb = def.len * 0.62
	local r = def.wheelR
	local wy = -0.9
	local STEEL = Color3.fromRGB(70, 74, 80)
	for _, z in ipairs({ -wb / 2, wb / 2 }) do
		add("Tyre", V3(0.22, r * 2, r * 2), CF(0, wy, z), BLACK, M.SmoothPlastic, Enum.PartType.Cylinder)
		add("Rim", V3(0.26, r * 1.6, r * 1.6), CF(0, wy, z), CHROME, M.Metal, Enum.PartType.Cylinder).Transparency = 0.5
	end
	local function tube(name, a: Vector3, b: Vector3, thick: number?, col: Color3?)
		local mid = (a + b) / 2
		add(name, V3(thick or 0.22, thick or 0.22, (b - a).Magnitude), CFrame.lookAt(mid, b), col or color, M.Metal)
	end
	local bb = V3(0, wy + 0.1, 0.3) -- bottom bracket
	local seatTop = V3(0, 1.0, 0.9)
	local headTop = V3(0, 1.25, -wb / 2 + 0.9)
	local headLow = V3(0, 0.5, -wb / 2 + 0.75)
	tube("SeatTube", bb, seatTop)
	tube("TopTube", seatTop + V3(0, -0.25, 0), headTop + V3(0, -0.2, 0))
	tube("DownTube", bb, headLow)
	tube("HeadTube", headLow, headTop + V3(0, 0.5, 0), 0.26)
	tube("Fork", headLow, V3(0, wy, -wb / 2), 0.2, STEEL)
	tube("ChainStay", bb, V3(0, wy, wb / 2), 0.18)
	tube("SeatStay", seatTop + V3(0, -0.2, 0), V3(0, wy, wb / 2), 0.18)
	add("Bars", V3(2.1, 0.18, 0.18), CF(0, 1.75, -wb / 2 + 0.95), STEEL, M.Metal)
	add("Saddle", V3(0.7, 0.25, 1.3), CF(0, 1.2, 1.0), Color3.fromRGB(70, 44, 30), M.Fabric)
	add("Crank", V3(1.1, 0.16, 0.16), CF(0, bb.Y, bb.Z), STEEL, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do add("Pedal", V3(0.45, 0.14, 0.7), CF(sx * 0.6, bb.Y + sx * 0.35, bb.Z), BLACK) end
	-- front basket + rear rack with a small GoDash bag
	add("Basket", V3(1.5, 0.9, 1.1), CF(0, 1.3, -wb / 2 + 0.1), Color3.fromRGB(150, 120, 80), M.WoodPlanks)
	add("Rack", V3(0.9, 0.12, 1.7), CF(0, 0.5, wb / 2 + 0.2), STEEL, M.Metal)
	local bag = add("Bag", V3(1.3, 1.2, 1.3), CF(0, 1.16, wb / 2 + 0.25), GODASH)
	logo(bag, Enum.NormalId.Back)
	local head = add("Headlight", V3(0.35, 0.35, 0.3), CF(0, 0.95, -wb / 2 + 0.55), Color3.fromRGB(250, 246, 220))
	lamp(head, Color3.fromRGB(255, 244, 214), 40, 50, 1.4)
	local tail = add("TailLight", V3(0.3, 0.3, 0.15), CF(0, 0.3, wb / 2 + 1.1), Color3.fromRGB(150, 20, 20))
	tail:AddTag("BrakeLight")
	return {
		seat = CF(0, 1.5, 0.95),
		pax = {},
		wheels = { V3(-0.5, 0, -wb / 2), V3(0.5, 0, -wb / 2), V3(-0.5, 0, wb / 2), V3(0.5, 0, wb / 2) },
		chassis = V3(1.1, 1.0, def.len * 0.7),
		rideHeight = r + 0.9,
	}
end

local function buildBike(def, add, wedge, wheel, color: Color3)
	if def.style == "bicycle" then return buildBicycle(def, add, color) end
	if def.style == "oldbike" then color = Color3.new(color.R * 0.6 + 0.12, color.G * 0.5 + 0.12, color.B * 0.45 + 0.12) end
	local wb = def.len * 0.62
	local r = def.wheelR
	local wy = -0.9
	wheel("WheelF", 0, wy, -wb / 2, r, 0.5)
	wheel("WheelR", 0, wy, wb / 2, r, 0.6)
	local sport = def.style == "sport" or def.style == "bigbike"
	local big = def.style == "bigbike"
	-- fork and bars
	add("Fork", V3(0.3, r * 2.4, 0.3), CF(0, wy + r * 1.1, -wb / 2 + 0.45) * CFrame.Angles(rad(-22), 0, 0), CHROME, M.Metal)
	add("Bars", V3(2.3, 0.2, 0.25), CF(0, wy + r * 2.25, -wb / 2 + 1.0), BLACK)
	local head = add("Headlight", V3(0.8, 0.6, 0.4), CF(0, wy + r * 1.8, -wb / 2 + 0.55), Color3.fromRGB(250, 246, 220))
	lamp(head, Color3.fromRGB(255, 244, 214), 70, 60, 2.2)
	add("FenderF", V3(0.6, 0.2, r * 1.6), CF(0, wy + r + 0.2, -wb / 2), color)
	add("Engine", V3(0.9, 0.9, 1.5), CF(0, wy + 0.3, 0.1), DARK, M.Metal)
	if sport then
		wedge("Fairing", V3(1.3, 1.5, 2.0), CF(0, wy + r * 1.5, -wb / 2 + 1.3) * CFrame.Angles(0, rad(180), 0), color)
		add("Tank", V3(1.2, 0.9, 1.9), CF(0, 1.0, -0.5), color)
		add("Seat", V3(1.0, 0.35, 1.7), CF(0, 1.05, 1.1), BLACK, M.Fabric)
		wedge("Tail", V3(0.9, 0.7, 1.6), CF(0, 1.1, 2.3), color)
		add("Exhaust", V3(big and 2.6 or 2.0, 0.5, 0.5), CF(0.65, wy + 0.5, wb / 2 - 0.4) * CFrame.Angles(0, rad(90), 0), CHROME, M.Metal, Enum.PartType.Cylinder)
		if big then
			for _, sx in ipairs({ -1, 1 }) do add("Pannier", V3(0.7, 1.2, 1.6), CF(sx * 1.0, 0.3, wb / 2 - 0.2), DARK) end
		else
			local bag = add("Bag", V3(1.5, 1.3, 1.4), CF(0, 1.9, 2.2), GODASH)
			logo(bag, Enum.NormalId.Back)
		end
	else
		local scooter = def.style == "scooter"
		add("LegShield", V3(1.3, 1.9, 0.4), CF(0, 0.5, -wb / 2 + 1.5) * CFrame.Angles(rad(-12), 0, 0), color)
		add("Floor", V3(1.1, 0.25, 1.6), CF(0, -0.45, -0.4), scooter and DARK or color)
		add("RearBody", V3(1.15, 0.9, wb * 0.55), CF(0, 0.45, wb * 0.24), color)
		add("Seat", V3(1.05, 0.4, wb * 0.5), CF(0, 1.1, wb * 0.16), BLACK, M.Fabric)
		add("Exhaust", V3(2.0, 0.42, 0.42), CF(0.62, wy + 0.4, wb / 2 - 0.5) * CFrame.Angles(0, rad(90), 0), CHROME, M.Metal, Enum.PartType.Cylinder)
		local old = def.style == "oldbike"
		local bw, bh = scooter and 2.2 or 1.9, scooter and 2.1 or 1.8
		local by = scooter and 2.4 or 2.2
		local box = add("DeliveryBox", V3(bw, bh, 1.9), CF(0, by, wb / 2 + 0.15), old and Color3.fromRGB(34, 120, 70) or GODASH, old and M.Fabric or M.SmoothPlastic)
		logo(box, Enum.NormalId.Back); logo(box, Enum.NormalId.Left); logo(box, Enum.NormalId.Right)
		add("BoxLid", V3(bw + 0.1, 0.2, 2.0), CF(0, by + bh / 2 + 0.1, wb / 2 + 0.15), BLACK)
		if old then
			-- rust patches and a taped-up seat
			add("Rust1", V3(0.5, 0.5, 0.06), CF(0.3, 0.7, -wb / 2 + 1.28) * CFrame.Angles(rad(-12), 0, 0), Color3.fromRGB(120, 70, 40), M.CorrodedMetal)
			add("Rust2", V3(0.06, 0.4, 0.9), CF(0.59, 0.5, wb * 0.3), Color3.fromRGB(120, 70, 40), M.CorrodedMetal)
			add("Tape", V3(1.08, 0.42, 0.4), CF(0, 1.1, wb * 0.25), Color3.fromRGB(150, 150, 150), M.Fabric)
		end
	end
	local tail = add("TailLight", V3(0.7, 0.3, 0.2), CF(0, 0.9, wb / 2 + (sport and 0.9 or 0.35)), Color3.fromRGB(150, 20, 20))
	tail:AddTag("BrakeLight")
	for _, sx in ipairs({ -1, 1 }) do
		add(sx < 0 and "SignalL" or "SignalR", V3(0.3, 0.25, 0.25), CF(sx * 0.75, 0.9, wb / 2 + 0.2), Color3.fromRGB(180, 110, 20))
		add(sx < 0 and "SignalFL" or "SignalFR", V3(0.3, 0.25, 0.25), CF(sx * 0.85, wy + r * 1.8, -wb / 2 + 0.7), Color3.fromRGB(180, 110, 20))
	end
	return {
		seat = CF(0, 1.35, sport and 0.9 or wb * 0.08),
		pax = { CF(0, 1.4, (sport and 0.9 or wb * 0.08) + 1.5) },
		wheels = { V3(-0.55, 0, -wb / 2), V3(0.55, 0, -wb / 2), V3(-0.55, 0, wb / 2), V3(0.55, 0, wb / 2) },
		chassis = V3(1.3, 1.2, def.len * 0.72),
		rideHeight = r + 0.9,
	}
end

local SHAPES = {
	hatch = { bodyH = 2.0, cabH = 1.9, cabLen = 0.56, cabZ = 0.1 },
	sedan = { bodyH = 1.9, cabH = 1.75, cabLen = 0.46, cabZ = 0.03 },
	suv = { bodyH = 2.6, cabH = 2.3, cabLen = 0.62, cabZ = 0.1 },
	pickup = { bodyH = 2.5, cabH = 2.2, cabLen = 0.34, cabZ = -0.1 },
	luxury = { bodyH = 1.85, cabH = 1.65, cabLen = 0.46, cabZ = 0.04 },
	super = { bodyH = 1.35, cabH = 1.25, cabLen = 0.36, cabZ = 0.04 },
}

local function buildCar(def, add, wedge, wheel, color: Color3)
	local sh = SHAPES[def.style] or SHAPES.sedan
	local L, W, r = def.len, def.wid, def.wheelR
	local wy = -0.9
	local by = wy + r * 0.55 + sh.bodyH / 2 -- body centre
	local top = by + sh.bodyH / 2
	local wx, wz = W / 2 - 0.45, L * 0.31
	wheel("WheelFL", -wx, wy, -wz, r, 0.9); wheel("WheelFR", wx, wy, -wz, r, 0.9)
	wheel("WheelRL", -wx, wy, wz, r, 0.9); wheel("WheelRR", wx, wy, wz, r, 0.9)
	add("BodyLower", V3(W, sh.bodyH, L), CF(0, by, 0), color, M.SmoothPlastic).Reflectance = 0.12
	if def.style == "super" then
		wedge("Nose", V3(W, sh.bodyH * 0.7, L * 0.2), CF(0, by + sh.bodyH * 0.15, -L / 2 - L * 0.1 + 0.2) * CFrame.Angles(0, rad(180), 0), color)
		add("Spoiler", V3(W * 0.9, 0.2, 1.4), CF(0, top + 0.9, L / 2 - 0.9), DARK)
		for _, sx in ipairs({ -1, 1 }) do add("SpoilerLeg", V3(0.2, 0.9, 0.5), CF(sx * W * 0.3, top + 0.45, L / 2 - 0.9), DARK) end
	end
	local cabLen = L * sh.cabLen
	local cz = L * sh.cabZ
	local cab = add("Cabin", V3(W - 0.5, sh.cabH, cabLen), CF(0, top + sh.cabH / 2, cz), GLASS, M.Glass)
	cab.Reflectance = 0.2
	add("Roof", V3(W - 0.7, 0.25, cabLen - 0.6), CF(0, top + sh.cabH + 0.1, cz), color)
	-- windscreen and rear glass slopes
	wedge("Windscreen", V3(W - 0.5, sh.cabH, sh.cabH * 1.1), CF(0, top + sh.cabH / 2, cz - cabLen / 2 - sh.cabH * 0.55) , GLASS, M.Glass)
	if def.style ~= "pickup" then
		wedge("RearGlass", V3(W - 0.5, sh.cabH, sh.cabH * (def.style == "sedan" and 1.1 or 0.5)),
			CF(0, top + sh.cabH / 2, cz + cabLen / 2 + sh.cabH * (def.style == "sedan" and 0.55 or 0.25)) * CFrame.Angles(0, rad(180), 0), GLASS, M.Glass)
	else
		-- open bed
		local bedLen = L / 2 - (cz + cabLen / 2) - 0.3
		local bz = cz + cabLen / 2 + bedLen / 2 + 0.1
		for _, sx in ipairs({ -1, 1 }) do add("BedSide", V3(0.3, 1.3, bedLen), CF(sx * (W / 2 - 0.15), top + 0.65, bz), color) end
		add("Tailgate", V3(W, 1.3, 0.3), CF(0, top + 0.65, L / 2 - 0.15), color)
	end
	add("BumperF", V3(W + 0.2, 0.8, 0.6), CF(0, by - sh.bodyH / 2 + 0.5, -L / 2 - 0.1), DARK)
	add("BumperR", V3(W + 0.2, 0.8, 0.6), CF(0, by - sh.bodyH / 2 + 0.5, L / 2 + 0.1), DARK)
	add("Grille", V3(W * 0.5, sh.bodyH * 0.35, 0.2), CF(0, by + 0.1, -L / 2 - 0.06), BLACK)
	for _, sx in ipairs({ -1, 1 }) do
		local head = add("Headlight", V3(1.1, 0.5, 0.25), CF(sx * (W / 2 - 0.85), by + sh.bodyH * 0.2, -L / 2 - 0.05), Color3.fromRGB(250, 246, 220))
		lamp(head, Color3.fromRGB(255, 244, 214), 90, 55, 2)
		local tail = add("TailLight", V3(1.1, 0.45, 0.25), CF(sx * (W / 2 - 0.85), by + sh.bodyH * 0.2, L / 2 + 0.05), Color3.fromRGB(150, 20, 20))
		tail:AddTag("BrakeLight")
		add(sx < 0 and "SignalL" or "SignalR", V3(0.4, 0.45, 0.27), CF(sx * (W / 2 - 0.2), by + sh.bodyH * 0.2, L / 2 + 0.05), Color3.fromRGB(180, 110, 20))
		add(sx < 0 and "SignalFL" or "SignalFR", V3(0.4, 0.5, 0.27), CF(sx * (W / 2 - 0.2), by + sh.bodyH * 0.2, -L / 2 - 0.05), Color3.fromRGB(180, 110, 20))
		add("Mirror", V3(0.5, 0.35, 0.3), CF(sx * (W / 2 + 0.2), top + 0.3, cz - cabLen / 2 + 0.2), color)
	end
	local sign = add("TaxiSign", V3(2.2, 0.6, 0.7), CF(0, top + sh.cabH + 0.5, cz), GODASH)
	logo(sign, Enum.NormalId.Front); logo(sign, Enum.NormalId.Back)
	local seatY = top - 0.4
	local pax = {}
	local frontZ = cz - cabLen * 0.18
	table.insert(pax, CF(-W * 0.22, seatY, frontZ))
	if def.seats >= 3 then
		table.insert(pax, CF(-W * 0.22, seatY, cz + cabLen * 0.22))
		table.insert(pax, CF(W * 0.22, seatY, cz + cabLen * 0.22))
	end
	if def.seats >= 5 then
		table.insert(pax, CF(0, seatY, cz + cabLen * 0.22))
		table.insert(pax, CF(0, seatY, cz + cabLen * 0.4))
	end
	return {
		seat = CF(W * 0.22, seatY, frontZ),
		pax = pax,
		wheels = { V3(-wx, 0, -wz), V3(wx, 0, -wz), V3(-wx, 0, wz), V3(wx, 0, wz) },
		chassis = V3(W - 0.4, sh.bodyH, L - 0.6),
		chassisY = by,
		rideHeight = r + 0.9,
	}
end

-- Which mesh model (Config/Models) each vehicle uses; anything missing falls back to the part-built body.
local MESH = {
	bicycle = "v_bicycle", oldmoped = "v_moped", sabai110 = "v_scooter", zoomer125 = "v_scooter", raptor300 = "v_sport", titan650 = "v_bigbike",
	eco_city = "v_hatch", sedan_vios = "v_sedan", pickup_dmax = "v_pickup", suv_fortune = "v_suv", lux_e300 = "v_lux", super_gt = "v_super",
}
-- saddle height as a fraction of the model's height
local SADDLE = { bicycle = 0.8, oldmoped = 0.66, sabai110 = 0.62, zoomer125 = 0.62, raptor300 = 0.7, titan650 = 0.66 }

-- Real mesh body. Bikes come with separate wheels, which get "SpinF"/"SpinR" welds the driver's
-- client turns. Returns the same layout table as the part builders, or nil without the mesh.
local function buildMesh(def, model: Model, body: BasePart, add, owned)
	local template = Assets.template(MESH[def.id] or "")
	if not template then return nil end
	local m = template:Clone()
	local size: Vector3 = m:GetAttribute("Size")
	local scale = def.len / size.Z
	m:ScaleTo(scale)
	local bike = def.class == "bike"
	local ride = def.wheelR + 0.9
	m:PivotTo(body.CFrame * CF(0, -ride, 0)) -- the template's pivot is its bottom centre: tyres on the ground
	local W, H, L = size.X * scale, size.Y * scale, def.len
	local tint = (not bike and owned and (owned.color or 1) > 1) and Vehicles.COLORS[owned.color] or nil
	local wheelZ = {}
	local list = {}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then table.insert(list, p) end
	end
	for _, p in ipairs(list) do
		p.Anchored = false
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		local n = p.Name:lower()
		local key = bike and (n:find("front") and "F" or (n:find("rear") and "R" or nil)) or nil
		p.Parent = model
		if key then
			p.Name = "Wheel" .. key
			local w = Instance.new("Weld")
			w.Name = "Spin" .. key
			w.Part0 = body
			w.Part1 = p
			w.C0 = body.CFrame:ToObjectSpace(p.CFrame)
			w.Parent = body
			p:SetAttribute("Radius", p.Size.Y / 2)
			wheelZ[key] = w.C0.Z
		else
			p.Name = "MeshBody"
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = p
			w.Parent = p
			if tint then
				local sa = p:FindFirstChildWhichIsA("SurfaceAppearance")
				if sa then pcall(function() sa.Color = tint.color end) end
			end
		end
	end
	m:Destroy()

	local function light(x: number, y: number)
		local head = add("Headlight", V3(0.5, 0.35, 0.2), CF(x, y - ride, -L / 2 - 0.05), Color3.fromRGB(250, 246, 220))
		head.Transparency = 1
		lamp(head, Color3.fromRGB(255, 244, 214), bike and 70 or 90, 58, 2.1)
	end
	if bike then
		light(0, H * 0.62)
		local tail = add("TailLight", V3(0.45, 0.2, 0.1), CF(0, H * 0.5 - ride, L / 2 + 0.02), Color3.fromRGB(150, 20, 20))
		tail:AddTag("BrakeLight")
		-- the GoDash bag rides on the back
		local bag = add("Bag", V3(1.5, 1.3, 1.4), CF(0, H * (def.pedal and 0.52 or 0.6) - ride + 0.7, L * 0.38), GODASH)
		logo(bag, Enum.NormalId.Back)
		local zf, zr = wheelZ.F or -L * 0.31, wheelZ.R or L * 0.31
		local saddle = H * (SADDLE[def.id] or 0.66)
		local seatZ = L * 0.1
		return {
			seat = CF(0, saddle - ride + 1.2, seatZ),
			pax = def.seats > 0 and { CF(0, saddle - ride + 1.25, seatZ + 1.5) } or {},
			wheels = { V3(-0.5, 0, zf), V3(0.5, 0, zf), V3(-0.5, 0, zr), V3(0.5, 0, zr) },
			chassis = V3(1.1, 1.0, L * 0.7),
			rideHeight = ride,
			mesh = true,
		}
	end
	for _, sx in ipairs({ -1, 1 }) do
		light(sx * W * 0.32, H * 0.42)
		local tail = add("TailLight", V3(W * 0.16, 0.18, 0.1), CF(sx * W * 0.34, H * 0.52 - ride, L / 2 + 0.02), Color3.fromRGB(150, 20, 20))
		tail:AddTag("BrakeLight")
	end
	local hip = H * 0.3 - ride + 1.2
	local z0 = -L * 0.04
	local pax = { CF(-W * 0.2, hip, z0) }
	if def.seats >= 3 then
		table.insert(pax, CF(-W * 0.2, hip, z0 + L * 0.2))
		table.insert(pax, CF(W * 0.2, hip, z0 + L * 0.2))
	end
	if def.seats >= 5 then
		table.insert(pax, CF(0, hip, z0 + L * 0.2))
		table.insert(pax, CF(0, hip, z0 + L * 0.34))
	end
	local wx, wz = W / 2 - 0.5, L * 0.31
	return {
		seat = CF(W * 0.2, hip, z0),
		pax = pax,
		wheels = { V3(-wx, 0, -wz), V3(wx, 0, -wz), V3(-wx, 0, wz), V3(wx, 0, wz) },
		chassis = V3(W - 0.5, H * 0.5, L - 0.8),
		chassisY = -ride + 0.9 + H * 0.25,
		rideHeight = ride,
		mesh = true,
	}
end

-- Styling (แต่งซิ่ง, 2026-11-17): underglow, number plate, bag / plate sticker, horn. Looks only. Parts
-- are named "Style_*" and rebuilt whenever the owner changes something (also on a moving vehicle:
-- welds keep the offsets from the body as it is now). plateText = the filtered custom plate or nil.
function Factory.style(model: Model, def, owned, ownerId: number?)
	local body = model:FindFirstChild("Body") :: BasePart?
	if not body then return end
	for _, c in ipairs(model:GetChildren()) do
		if c.Name:sub(1, 6) == "Style_" then c:Destroy() end
	end
	local st = (owned and type(owned.style) == "table") and owned.style or {}
	model:SetAttribute("Horn", st.horn or 1)
	model:SetAttribute("Exhaust", st.exhaust or 1)
	local ownerPlayer = ownerId and ownerId > 0 and game:GetService("Players"):GetPlayerByUserId(ownerId) or nil
	local vip = ownerPlayer ~= nil and ownerPlayer:GetAttribute("VIP") == true
	if def.pedal then return end -- a bicycle has no plate or wiring
	local L, W, H = def.len, def.wid, def.height
	local ride = model:GetAttribute("RideHeight") or (def.wheelR + 0.9)
	local bike = def.class == "bike"
	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = mat or M.SmoothPlastic
		p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
		p.Massless = true
		p.CastShadow = false
		p.CFrame = body.CFrame * cf
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = p
		w.Parent = p
		p.Parent = model
		return p
	end
	local function gui(p: BasePart, face: Enum.NormalId, ppsv: number): SurfaceGui
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = ppsv
		g.LightInfluence = 0.3
		g.MaxDistance = 90
		g.Parent = p
		return g
	end
	local function text(parent: Instance, s: string, color: Color3, pos: UDim2, size: UDim2, font: Enum.Font?)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Text = s
		t.TextScaled = true
		t.Font = font or Enum.Font.GothamBlack
		t.TextColor3 = color
		t.Position = pos
		t.Size = size
		t.Parent = parent
		return t
	end

	-- underglow: a neon strip under the body and a light on the road
	local glow = Vehicles.GLOWS[st.glow or 0]
	if glow then
		local strip = part("Style_Glow", V3(bike and 0.45 or W * 0.78, 0.08, L * (bike and 0.5 or 0.78)), CF(0, -ride + (bike and 0.75 or 0.55), 0), glow.color, M.Neon)
		if glow.rainbow then strip:SetAttribute("Rainbow", true) end -- client/Styling cycles the colour
		local sl = Instance.new("SurfaceLight")
		sl.Face = Enum.NormalId.Bottom
		sl.Color = glow.color
		sl.Range = bike and 7 or 11
		sl.Angle = 150
		sl.Brightness = 3
		sl.Shadows = false
		sl.Parent = strip
	end

	-- number plate at the back (Thai style: white, black letters, the province underneath)
	local plateText = model:GetAttribute("PlateText")
	if type(plateText) ~= "string" or plateText == "" then plateText = Vehicles.defaultPlate(ownerId or 0) end
	local pw, ph = bike and 1.15 or 2.0, bike and 0.78 or 0.62
	local plate = part("Style_Plate", V3(pw, ph, 0.05), CF(0, (bike and H * 0.36 or H * 0.3) - ride, L / 2 + 0.04), Color3.fromRGB(246, 246, 240))
	local pg = gui(plate, Enum.NormalId.Back, 60)
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = pg
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = vip and 6 or 3
	stroke.Color = vip and Color3.fromRGB(230, 180, 40) or Color3.fromRGB(30, 30, 30) -- VIPs get a gold frame
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	text(frame, plateText, Color3.fromRGB(20, 20, 22), UDim2.fromScale(0.05, 0.06), UDim2.fromScale(0.9, 0.58))
	text(frame, "ขอนแก่น", Color3.fromRGB(20, 20, 22), UDim2.fromScale(0.15, 0.64), UDim2.fromScale(0.7, 0.3), Enum.Font.GothamBold)

	-- sticker: both sides of the delivery bag on two wheels, a strip above the plate on cars
	local sticker = Vehicles.STICKERS[st.sticker or 0]
	if sticker then
		local bag = model:FindFirstChild("Bag") :: BasePart?
		local function decorate(g: SurfaceGui)
			local f = Instance.new("Frame")
			f.BackgroundColor3 = sticker.color
			f.Size = UDim2.fromScale(0.86, 0.5)
			f.Position = UDim2.fromScale(0.07, 0.25)
			f.Parent = g
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.25, 0)
			c.Parent = f
			text(f, sticker.icon .. " " .. sticker.text, Color3.new(1, 1, 1), UDim2.fromScale(0.06, 0.12), UDim2.fromScale(0.88, 0.76))
		end
		if bike and bag then
			-- a thin card on each side face of the bag, so the bag's own logo stays
			for _, sx in ipairs({ -1, 1 }) do
				local card = part("Style_Sticker", V3(0.04, bag.Size.Y * 0.9, bag.Size.Z * 0.95), body.CFrame:ToObjectSpace(bag.CFrame) * CF(sx * (bag.Size.X / 2 + 0.03), 0, 0), bag.Color)
				card.Transparency = 1
				decorate(gui(card, sx < 0 and Enum.NormalId.Left or Enum.NormalId.Right, 50))
			end
		elseif not bike then
			local strip = part("Style_Sticker", V3(2.4, 0.5, 0.04), CF(0, H * 0.3 - ride + ph / 2 + 0.32, L / 2 + 0.03), Color3.new(1, 1, 1))
			strip.Transparency = 1
			decorate(gui(strip, Enum.NormalId.Back, 50))
		end
	end

	-- delivery-box skin (2026-11-19, viral pack; Config/Vehicles.BOXES): the box (or bag) and lid take the skin's
	-- colours, plus its own touches: watermelon stripes, cat ears and a face, a pha khao ma plaid, a shark fin and teeth
	local box = model:FindFirstChild("DeliveryBox") or model:FindFirstChild("Bag")
	local lid = model:FindFirstChild("BoxLid")
	if bike and box and box:IsA("BasePart") then
		if box:GetAttribute("BaseColor") == nil then box:SetAttribute("BaseColor", box.Color) end
		if lid and lid:IsA("BasePart") and lid:GetAttribute("BaseColor") == nil then lid:SetAttribute("BaseColor", lid.Color) end
		local skin = Vehicles.BOXES[st.box or 0]
		box.Color = skin and skin.color or box:GetAttribute("BaseColor")
		if lid and lid:IsA("BasePart") then lid.Color = skin and skin.lid or lid:GetAttribute("BaseColor") end
		if skin then
			local bcf = body.CFrame:ToObjectSpace(box.CFrame)
			local s = box.Size
			local top = s.Y / 2 + ((lid and lid:IsA("BasePart")) and lid.Size.Y or 0)
			local function band(size: Vector3, at: Vector3, color: Color3)
				part("Style_Box", size, bcf * CF(at.X, at.Y, at.Z), color)
			end
			local function wedge(size: Vector3, cf: CFrame, color: Color3)
				local w = Instance.new("WedgePart")
				w.Name = "Style_Box"
				w.Size = size
				w.Color = color
				w.Material = M.SmoothPlastic
				w.CanCollide, w.CanTouch, w.CanQuery, w.Massless, w.CastShadow = false, false, false, true, false
				w.CFrame = body.CFrame * bcf * cf
				local wc = Instance.new("WeldConstraint")
				wc.Part0, wc.Part1 = body, w
				wc.Parent = w
				w.Parent = model
			end
			local function ball(d: number, at: Vector3, color: Color3)
				local b = part("Style_Box", V3(d, d, d), bcf * CF(at.X, at.Y, at.Z), color)
				b.Shape = Enum.PartType.Ball
			end
			if skin.stripes then
				for _, i in ipairs({ -1, 0, 1 }) do
					band(V3(0.14, s.Y + 0.02, s.Z + 0.04), V3(i * s.X / 3.2, 0, 0), skin.stripes)
					band(V3(s.X + 0.04, s.Y + 0.02, 0.14), V3(0, 0, i * s.Z / 3.2), skin.stripes)
				end
			elseif skin.plaid then
				-- red cloth with yellow and green checks and white bands, like the everyday Thai pha khao ma
				for _, i in ipairs({ -1, 1 }) do
					band(V3(0.12, s.Y + 0.02, s.Z + 0.04), V3(i * s.X / 4, 0, 0), Color3.fromRGB(240, 220, 110))
					band(V3(s.X + 0.04, s.Y + 0.02, 0.12), V3(0, 0, i * s.Z / 4), Color3.fromRGB(46, 128, 76))
					band(V3(s.X + 0.04, 0.1, s.Z + 0.04), V3(0, i * s.Y / 4, 0), Color3.fromRGB(246, 244, 236))
				end
				band(V3(s.X + 0.05, 0.06, s.Z + 0.05), V3(0, 0, 0), Color3.fromRGB(40, 80, 170))
			elseif skin.cat then
				-- ears on the top, a face on the back (the chase camera's view)
				for _, sx in ipairs({ -1, 1 }) do
					wedge(V3(0.18, 0.62, 0.62), CF(sx * s.X * 0.28, top + 0.3, 0) * CFrame.Angles(0, sx * math.rad(90), 0), skin.color)
					ball(0.3, V3(sx * s.X * 0.2, s.Y * 0.12, s.Z / 2 + 0.06), Color3.fromRGB(30, 30, 34))
					for k = -1, 1, 2 do -- whiskers
						band(V3(s.X * 0.22, 0.04, 0.04), V3(sx * s.X * 0.33, -s.Y * 0.08 + k * 0.1, s.Z / 2 + 0.04), Color3.fromRGB(60, 50, 44))
					end
				end
				ball(0.2, V3(0, -s.Y * 0.04, s.Z / 2 + 0.06), Color3.fromRGB(240, 120, 140))
			elseif skin.shark then
				wedge(V3(0.16, 0.9, 1.0), CF(0, top + 0.45, s.Z * 0.1) * CFrame.Angles(0, math.rad(180), 0), skin.color) -- the fin
				band(V3(s.X + 0.04, s.Y * 0.38, s.Z + 0.04), V3(0, -s.Y * 0.31, 0), Color3.fromRGB(238, 240, 242)) -- white belly
				band(V3(s.X * 0.7, 0.3, 0.04), V3(0, -s.Y * 0.06, s.Z / 2 + 0.04), Color3.fromRGB(70, 20, 30)) -- the mouth
				for k = -2, 2 do
					wedge(V3(0.04, 0.16, 0.16), CF(k * s.X * 0.13, 0.03, s.Z / 2 + 0.06) * CFrame.Angles(math.rad(180), math.rad(90), 0), Color3.new(1, 1, 1))
				end
				for _, sx in ipairs({ -1, 1 }) do ball(0.24, V3(sx * s.X * 0.26, s.Y * 0.2, s.Z / 2 + 0.06), Color3.fromRGB(20, 20, 24)) end
			end
		end
	end
end

-- cf = where the chassis centre goes. owned = the player's saved state for this vehicle.
function Factory.build(def, owned, cf: CFrame, ownerId: number?): Model
	local model = Instance.new("Model")
	model.Name = def.name
	local color = (Vehicles.COLORS[owned and owned.color or 1] or Vehicles.COLORS[1]).color

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Transparency = 1
	chassis.CanTouch = false
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.CFrame = cf
	chassis.Size = V3(2, 1, 4)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Transparency = 1
	body.Size = V3(0.5, 0.5, 0.5)
	body.CanCollide = false; body.CanTouch = false; body.CanQuery = false; body.Massless = true
	body.CFrame = cf
	body.Parent = model
	local bw = Instance.new("Weld")
	bw.Name = "BodyWeld"
	bw.Part0 = chassis
	bw.Part1 = body
	bw.Parent = chassis

	local add, wedge, wheel = newBuilder(model, body)
	local info = buildMesh(def, model, body, add, owned)
		or (def.class == "bike" and buildBike(def, add, wedge, wheel, color) or buildCar(def, add, wedge, wheel, color))
	model:SetAttribute("Mesh", info.mesh == true)

	chassis.Size = info.chassis
	if info.chassisY then
		-- keep the collider around the lower body while the physics origin stays put
		chassis.CFrame = cf * CF(0, info.chassisY, 0)
		bw.C0 = CF(0, -info.chassisY, 0)
		model:SetAttribute("OriginY", info.chassisY)
	else
		model:SetAttribute("OriginY", 0)
	end
	local vol = info.chassis.X * info.chassis.Y * info.chassis.Z
	chassis.CustomPhysicalProperties = PhysicalProperties.new(math.clamp(def.mass / vol, 0.4, 100), 0.25, 0.1, 1, 1)

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = V3(1.6, 0.3, 1.6)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false -- nobody sits by bumping into it; the server seats the owner
	seat.Massless = true
	seat.MaxSpeed = 0; seat.Torque = 0; seat.TurnSpeed = 0
	seat.HeadsUpDisplay = false
	seat.CFrame = body.CFrame * info.seat * CF(0, -1.2, 0)
	local sw = Instance.new("WeldConstraint"); sw.Part0 = body; sw.Part1 = seat; sw.Parent = seat
	seat.Parent = model

	for i, p in ipairs(info.pax) do
		local a = Instance.new("Attachment")
		a.Name = "Pax" .. i
		a.CFrame = p * CF(0, -1.2, 0)
		a.Parent = body
	end
	for i, w in ipairs(info.wheels) do
		model:SetAttribute("Wheel" .. i, w)
	end
	model:SetAttribute("VehicleId", def.id)
	model:SetAttribute("Class", def.class)
	model:SetAttribute("RideHeight", info.rideHeight)
	model:SetAttribute("Owner", ownerId or 0)
	model:SetAttribute("Seats", #info.pax)
	if owned then
		for _, up in ipairs(Vehicles.UPGRADES) do model:SetAttribute("Up_" .. up.id, owned[up.id] or 0) end
		model:SetAttribute("Fuel", owned.fuel)
		model:SetAttribute("Condition", owned.condition)
		model:SetAttribute("Tread", math.floor(owned.tread or 100))
		model:SetAttribute("OilDue", not def.pedal and (owned.oil or 0) > Vehicles.OIL_INTERVAL or nil)
	end
	model:SetAttribute("Lights", false)
	model:SetAttribute("Brake", false)
	model:SetAttribute("Signal", 0)
	if owned and type(owned.style) == "table" and type(owned.style.plate) == "string" then model:SetAttribute("PlateText", owned.style.plate) end
	pcall(Factory.style, model, def, owned, ownerId)
	-- (2026-11-20) toy-brick look: plastic with studs, but the paint the owner picked stays exactly as picked
	Bricks.tree(model, true)
	model:AddTag("GoDashVehicle")
	return model
end

-- Anchored showroom copy (no seat, no physics).
function Factory.display(def, cf: CFrame, colorIndex: number?): Model
	local m = Factory.build(def, { color = colorIndex or 1, fuel = 0, condition = 100 }, cf, 0)
	m:RemoveTag("GoDashVehicle")
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	local seat = m:FindFirstChild("DriveSeat")
	if seat then seat:Destroy() end
	return m
end

local HELMETS = {
	Color3.fromRGB(30, 30, 34), Color3.fromRGB(236, 236, 232), Color3.fromRGB(200, 50, 44), Color3.fromRGB(40, 90, 170),
	Color3.fromRGB(240, 190, 40), Color3.fromRGB(240, 120, 150), Color3.fromRGB(28, 168, 84),
}

-- AI traffic copy: like display(), and every two-wheeler carries a rider. (Until 2026-11-16 traffic
-- used display(), the parked-showroom copy, so AI motorbikes drove around with nobody on them.)
-- The rider's parts are anchored inside the vehicle model; the client moves the whole model, so the
-- rider cannot be left behind, float or drop off.
function Factory.traffic(def, cf: CFrame, colorIndex: number?, seed: number?): Model
	local m = Factory.build(def, { color = colorIndex or 1, fuel = 0, condition = 100 }, cf, 0)
	m:RemoveTag("GoDashVehicle")
	pcall(Factory.style, m, def, nil, (seed or 1) * 7919) -- every car its own plate
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	local seat = m:FindFirstChild("DriveSeat")
	if seat and def.class == "bike" then
		local rng = Random.new(seed or 1)
		local saddle = (seat :: BasePart).CFrame * CF(0, 0.15, 0)
		local helmet = HELMETS[rng:NextInteger(1, #HELMETS)]
		-- a real figure (one of the avatar models) when the place has them, else the block figure
		local rider: Model? = nil
		local store = ReplicatedStorage:FindFirstChild("GoDashModels")
		local peds = {}
		if store and not Bricks.ON then -- (toy-brick look: the block figure, not the realistic avatars)
			for _, p in ipairs(store:GetChildren()) do
				if p:IsA("Model") and p.Name:sub(1, 3) == "Ped" then table.insert(peds, p) end
			end
			table.sort(peds, function(a, b) return a.Name < b.Name end)
		end
		if #peds > 0 then
			local ok, res = pcall(RiderPose.build, peds[rng:NextInteger(1, #peds)], saddle, helmet)
			if ok then rider = res end
		end
		if not rider then
			local rig = Rig.build({ name = "Rider", seed = rng:NextInteger(1, 1e6), outfit = rng:NextNumber() < 0.3 and "rider" or nil })
			Rig.ride(rig, saddle, helmet)
			rider = rig.model
		end
		(rider :: Model).Parent = m
		m:SetAttribute("HasRider", true)
	end
	if seat then seat:Destroy() end
	return m
end

return Factory
