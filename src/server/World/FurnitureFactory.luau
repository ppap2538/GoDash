-- Furniture models from Config/Housing. Every model has an invisible "Base" box of the catalogue
-- size (PrimaryPart, bottom on the floor) so placement and collision checks use one footprint.
-- Local frame: front = -Z.
local Factory = {}

local V3, CF = Vector3.new, CFrame.new
local M = Enum.Material
local rad = math.rad

local WOOD = Color3.fromRGB(150, 108, 70)
local WOOD_D = Color3.fromRGB(98, 68, 44)
local WHITE = Color3.fromRGB(240, 240, 236)
local STEEL = Color3.fromRGB(170, 174, 180)
local DARK = Color3.fromRGB(44, 46, 50)
local FABRICS = { Color3.fromRGB(70, 110, 160), Color3.fromRGB(170, 70, 70), Color3.fromRGB(90, 140, 100), Color3.fromRGB(200, 170, 110), Color3.fromRGB(110, 90, 150) }

local SHAPES = {}

-- p(size, x, y, z, color, material, extra): y is the part's centre above the floor
SHAPES.sofa = function(p, s, rng)
	local c = FABRICS[rng:NextInteger(1, #FABRICS)]
	p(V3(s.X, 1.4, s.Z), 0, 0.9, 0, c, M.Fabric)
	p(V3(s.X, s.Y - 1.4, 0.9), 0, 1.6 + (s.Y - 1.4) / 2 - 0.2, s.Z / 2 - 0.45, c, M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do p(V3(0.7, 1.4, s.Z), sx * (s.X / 2 - 0.35), 1.7, 0, c, M.Fabric) end
	return { seat = CF(0, 1.7, -0.2) }
end
SHAPES.chair = function(p, s)
	p(V3(s.X, 0.3, s.Z), 0, 1.9, 0, WOOD, M.Wood)
	p(V3(s.X, 2, 0.3), 0, 3, s.Z / 2 - 0.15, WOOD, M.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do p(V3(0.25, 1.8, 0.25), sx * (s.X / 2 - 0.2), 0.9, sz * (s.Z / 2 - 0.2), WOOD_D, M.Wood) end
	end
	return { seat = CF(0, 2.1, 0) }
end
SHAPES.bench = function(p, s)
	p(V3(s.X, 0.35, s.Z - 0.6), 0, 1.7, -0.2, WOOD, M.WoodPlanks)
	p(V3(s.X, 1.3, 0.3), 0, 2.5, s.Z / 2 - 0.3, WOOD, M.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do p(V3(0.4, 1.6, s.Z - 0.6), sx * (s.X / 2 - 0.5), 0.8, -0.2, DARK, M.Metal) end
	return { seat = CF(0, 1.9, -0.2) }
end
SHAPES.table = function(p, s)
	p(V3(s.X, 0.3, s.Z), 0, s.Y - 0.15, 0, WOOD, M.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do p(V3(0.3, s.Y - 0.3, 0.3), sx * (s.X / 2 - 0.3), (s.Y - 0.3) / 2, sz * (s.Z / 2 - 0.3), WOOD_D, M.Wood) end
	end
end
SHAPES.tv = function(p, s)
	p(V3(s.X, 1.6, s.Z), 0, 0.8, 0, WOOD_D, M.Wood)
	p(V3(s.X * 0.8, 3.2, 0.25), 0, 3.6, 0.2, DARK, M.SmoothPlastic)
	local screen = p(V3(s.X * 0.76, 2.9, 0.06), 0, 3.6, 0.05, Color3.fromRGB(60, 120, 190), M.Neon)
	screen.Name = "Screen"
end
SHAPES.shelf = function(p, s)
	p(V3(s.X, s.Y, 0.2), 0, s.Y / 2, s.Z / 2 - 0.1, WOOD_D, M.Wood)
	for _, sx in ipairs({ -1, 1 }) do p(V3(0.2, s.Y, s.Z), sx * (s.X / 2 - 0.1), s.Y / 2, 0, WOOD, M.Wood) end
	local n = math.floor(s.Y / 1.8)
	for i = 0, n do
		p(V3(s.X - 0.3, 0.18, s.Z - 0.2), 0, 0.1 + i * (s.Y - 0.2) / n, 0, WOOD, M.Wood)
		if i < n then p(V3(s.X * 0.6, 1.1, s.Z * 0.6), -s.X * 0.1, 0.75 + i * (s.Y - 0.2) / n, 0, FABRICS[i % #FABRICS + 1], M.SmoothPlastic) end
	end
end
SHAPES.pc = function(p, s)
	p(V3(s.X, 0.3, s.Z), 0, 2.9, 0, WOOD, M.Wood)
	for _, sx in ipairs({ -1, 1 }) do p(V3(0.3, 2.8, s.Z - 0.4), sx * (s.X / 2 - 0.3), 1.4, 0, WOOD_D, M.Wood) end
	p(V3(2.6, 1.6, 0.15), -0.6, 4, 0.5, DARK, M.SmoothPlastic)
	p(V3(2.4, 1.4, 0.05), -0.6, 4, 0.42, Color3.fromRGB(80, 170, 120), M.Neon)
	p(V3(0.3, 0.5, 0.3), -0.6, 3.25, 0.5, DARK, M.SmoothPlastic)
	p(V3(1.8, 0.1, 0.7), -0.6, 3.1, -0.5, DARK, M.SmoothPlastic)
	p(V3(0.9, 2, 2), 1.9, 4, 0.2, DARK, M.SmoothPlastic)
end
SHAPES.bed = function(p, s, rng)
	local c = FABRICS[rng:NextInteger(1, #FABRICS)]
	p(V3(s.X, 1, s.Z), 0, 0.7, 0, WOOD_D, M.Wood)
	p(V3(s.X - 0.3, 0.8, s.Z - 0.4), 0, 1.5, 0, WHITE, M.Fabric)
	p(V3(s.X - 0.25, 0.5, s.Z * 0.6), 0, 1.8, -s.Z * 0.18, c, M.Fabric)
	p(V3(s.X, s.Y, 0.4), 0, s.Y / 2, s.Z / 2 - 0.2, WOOD, M.Wood)
	p(V3(s.X * 0.7, 0.5, 1.4), 0, 2.1, s.Z / 2 - 1.3, WHITE, M.Fabric)
end
SHAPES.wardrobe = function(p, s)
	p(V3(s.X, s.Y, s.Z), 0, s.Y / 2, 0, WOOD, M.Wood)
	p(V3(0.1, s.Y - 0.6, 0.06), 0, s.Y / 2, -s.Z / 2 - 0.03, WOOD_D, M.Wood)
	for _, sx in ipairs({ -1, 1 }) do p(V3(0.15, 0.9, 0.2), sx * 0.4, s.Y / 2, -s.Z / 2 - 0.1, STEEL, M.Metal) end
end
SHAPES.lamp_table = function(p, s)
	p(V3(s.X, 2, s.Z), 0, 1, 0, WOOD, M.Wood)
	p(V3(0.3, 1.4, 0.3), 0, 2.7, 0, STEEL, M.Metal)
	local shade = p(V3(1.5, 1.1, 1.5), 0, 3.9, 0, Color3.fromRGB(255, 232, 180), M.Fabric)
	return { light = shade }
end
SHAPES.floor_lamp = function(p, s)
	p(V3(1.3, 0.2, 1.3), 0, 0.1, 0, DARK, M.Metal)
	p(V3(0.2, s.Y - 1.6, 0.2), 0, (s.Y - 1.6) / 2 + 0.2, 0, STEEL, M.Metal)
	local shade = p(V3(1.6, 1.4, 1.6), 0, s.Y - 0.7, 0, Color3.fromRGB(255, 232, 180), M.Fabric)
	return { light = shade }
end
SHAPES.lamp_post = function(p, s)
	p(V3(0.4, s.Y - 1, 0.4), 0, (s.Y - 1) / 2, 0, DARK, M.Metal)
	local shade = p(V3(1.2, 1, 1.2), 0, s.Y - 0.5, 0, Color3.fromRGB(255, 240, 200), M.SmoothPlastic)
	return { light = shade }
end
SHAPES.fridge = function(p, s)
	p(V3(s.X, s.Y, s.Z), 0, s.Y / 2, 0, STEEL, M.Metal)
	p(V3(s.X - 0.2, 0.08, 0.06), 0, s.Y * 0.62, -s.Z / 2 - 0.03, DARK, M.SmoothPlastic)
	p(V3(0.15, 1.6, 0.2), s.X / 2 - 0.5, s.Y * 0.4, -s.Z / 2 - 0.1, DARK, M.Metal)
	p(V3(0.15, 1, 0.2), s.X / 2 - 0.5, s.Y * 0.8, -s.Z / 2 - 0.1, DARK, M.Metal)
end
SHAPES.stove = function(p, s)
	p(V3(s.X, s.Y - 0.2, s.Z), 0, (s.Y - 0.2) / 2, 0, WHITE, M.SmoothPlastic)
	p(V3(s.X, 0.2, s.Z), 0, s.Y - 0.1, 0, DARK, M.Marble)
	for _, sx in ipairs({ -1.2, 1.2 }) do p(V3(1.3, 0.12, 1.3), sx, s.Y + 0.05, 0, Color3.fromRGB(30, 30, 32), M.Metal) end
	p(V3(1.2, 0.7, 1.2), -1.2, s.Y + 0.45, 0, STEEL, M.Metal)
	p(V3(s.X * 0.5, 1.6, 0.1), 0, 1.6, -s.Z / 2 - 0.05, DARK, M.Glass)
end
SHAPES.counter = function(p, s)
	p(V3(s.X, s.Y - 0.2, s.Z), 0, (s.Y - 0.2) / 2, 0, WOOD, M.Wood)
	p(V3(s.X, 0.2, s.Z), 0, s.Y - 0.1, 0, Color3.fromRGB(220, 220, 214), M.Marble)
	p(V3(2, 0.1, 1.6), 1, s.Y + 0.01, 0, STEEL, M.Metal)
	p(V3(0.2, 1, 0.2), 1, s.Y + 0.5, 0.9, STEEL, M.Metal)
end
SHAPES.shower = function(p, s)
	p(V3(s.X, 0.3, s.Z), 0, 0.15, 0, Color3.fromRGB(220, 226, 230), M.Marble)
	p(V3(s.X, s.Y, 0.2), 0, s.Y / 2, s.Z / 2 - 0.1, Color3.fromRGB(200, 220, 230), M.Marble)
	local glass = p(V3(0.15, s.Y - 0.6, s.Z), -s.X / 2 + 0.08, s.Y / 2, 0, Color3.fromRGB(180, 210, 225), M.Glass)
	glass.Transparency = 0.6
	p(V3(0.2, s.Y - 2, 0.2), 0, (s.Y - 2) / 2 + 1, s.Z / 2 - 0.4, STEEL, M.Metal)
	p(V3(1.1, 0.2, 1.1), 0, s.Y - 0.9, s.Z / 2 - 1, STEEL, M.Metal)
end
SHAPES.toilet = function(p, s)
	p(V3(1.8, 1.5, 2.2), 0, 0.75, -0.4, WHITE, M.SmoothPlastic)
	p(V3(2.2, 2, 0.9), 0, 2.2, s.Z / 2 - 0.45, WHITE, M.SmoothPlastic)
	p(V3(1.9, 0.2, 2.2), 0, 1.6, -0.4, Color3.fromRGB(226, 226, 222), M.SmoothPlastic)
end
SHAPES.sink = function(p, s)
	p(V3(s.X, 3, s.Z - 0.4), 0, 1.5, 0.2, WHITE, M.SmoothPlastic)
	p(V3(s.X, 0.3, s.Z), 0, 3.15, 0, Color3.fromRGB(226, 226, 222), M.Marble)
	local mirror = p(V3(s.X - 0.6, 2.6, 0.1), 0, 5.2, s.Z / 2 - 0.05, Color3.fromRGB(190, 210, 220), M.Glass)
	mirror.Reflectance = 0.5
end
SHAPES.washer = function(p, s)
	p(V3(s.X, s.Y, s.Z), 0, s.Y / 2, 0, WHITE, M.SmoothPlastic)
	local door = p(V3(1.8, 1.8, 0.1), 0, s.Y * 0.5, -s.Z / 2 - 0.05, Color3.fromRGB(60, 80, 100), M.Glass)
	door.Shape = Enum.PartType.Cylinder
	door.Size = V3(0.1, 1.8, 1.8)
	door.CFrame = door.CFrame * CFrame.Angles(0, rad(90), 0)
end
SHAPES.garage = function(p, s)
	p(V3(s.X, 0.3, s.Z), 0, 0.15, 0, Color3.fromRGB(120, 122, 126), M.Concrete)
	for _, sx in ipairs({ -1, 1 }) do p(V3(0.4, 0.06, s.Z - 2), sx * (s.X / 2 - 0.8), 0.33, 0, Color3.fromRGB(240, 200, 60), M.SmoothPlastic) end
end
SHAPES.bench_tools = function(p, s)
	p(V3(s.X, 0.3, s.Z), 0, 3, 0, WOOD_D, M.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do p(V3(0.4, 2.9, s.Z - 0.3), sx * (s.X / 2 - 0.4), 1.45, 0, DARK, M.Metal) end
	p(V3(s.X, 1.4, 0.15), 0, 3.9, s.Z / 2 - 0.08, Color3.fromRGB(180, 60, 50), M.Metal)
	p(V3(1.4, 0.8, 1), -1.5, 3.55, 0, Color3.fromRGB(200, 50, 40), M.Metal)
	p(V3(0.3, 0.3, 1.4), 1.2, 3.3, -0.3, STEEL, M.Metal)
end
SHAPES.palm = function(p, s)
	p(V3(1.1, s.Y - 2, 1.1), 0, (s.Y - 2) / 2, 0, Color3.fromRGB(104, 78, 54), M.Wood)
	for i = 0, 4 do
		local leaf = p(V3(1.5, 0.25, 7), 0, s.Y - 2, 0, Color3.fromRGB(64, 132, 60), M.Grass)
		leaf.CFrame = leaf.CFrame * CFrame.Angles(0, rad(i * 72), 0) * CFrame.Angles(rad(-24), 0, 0) * CF(0, 0, -3.4)
	end
end
SHAPES.flowers = function(p, s, rng)
	p(V3(s.X, 0.9, s.Z), 0, 0.45, 0, Color3.fromRGB(110, 80, 54), M.WoodPlanks)
	p(V3(s.X - 0.4, 0.3, s.Z - 0.4), 0, 0.95, 0, Color3.fromRGB(90, 66, 48), M.Ground)
	local cols = { Color3.fromRGB(230, 80, 100), Color3.fromRGB(240, 200, 60), Color3.fromRGB(230, 130, 200), Color3.fromRGB(250, 250, 240) }
	for i = 1, 6 do
		local b = p(V3(0.8, 0.8, 0.8), rng:NextNumber(-s.X / 2 + 0.6, s.X / 2 - 0.6), 1.4, rng:NextNumber(-s.Z / 2 + 0.6, s.Z / 2 - 0.6), cols[rng:NextInteger(1, 4)], M.SmoothPlastic)
		b.Shape = Enum.PartType.Ball
	end
end
SHAPES.spirit = function(p, s)
	p(V3(0.8, 3.4, 0.8), 0, 1.7, 0, WHITE, M.Marble)
	p(V3(s.X, 0.3, s.Z), 0, 3.5, 0, WHITE, M.Marble)
	p(V3(1.8, 1.6, 1.8), 0, 4.45, 0, Color3.fromRGB(196, 60, 50), M.SmoothPlastic)
	p(V3(2.4, 0.3, 2.4), 0, 5.4, 0, Color3.fromRGB(226, 180, 60), M.Metal)
	p(V3(1.4, 0.9, 1.4), 0, 6, 0, Color3.fromRGB(226, 180, 60), M.Metal)
	p(V3(0.3, 0.9, 0.3), 0, 6.6, 0, Color3.fromRGB(226, 180, 60), M.Metal)
end
SHAPES.fence = function(p, s)
	for i = -1, 1 do p(V3(0.5, s.Y, 0.5), i * (s.X / 2 - 0.3), s.Y / 2, 0, WOOD_D, M.Wood) end
	p(V3(s.X, 0.4, 0.3), 0, s.Y * 0.75, 0, WOOD, M.WoodPlanks)
	p(V3(s.X, 0.4, 0.3), 0, s.Y * 0.35, 0, WOOD, M.WoodPlanks)
end
SHAPES.rug = function(p, s, rng)
	p(V3(s.X, 0.12, s.Z), 0, 0.06, 0, FABRICS[rng:NextInteger(1, #FABRICS)], M.Fabric)
	p(V3(s.X - 1.2, 0.13, s.Z - 1.2), 0, 0.07, 0, Color3.fromRGB(236, 226, 200), M.Fabric)
end
SHAPES.plant = function(p, s)
	p(V3(1.5, 1.4, 1.5), 0, 0.7, 0, Color3.fromRGB(190, 110, 70), M.Slate)
	p(V3(0.25, 1.6, 0.25), 0, 2.1, 0, Color3.fromRGB(80, 110, 60), M.Wood)
	local leaf = p(V3(2, 2, 2), 0, 3.4, 0, Color3.fromRGB(70, 150, 70), M.Grass)
	leaf.Shape = Enum.PartType.Ball
end
SHAPES.painting = function(p, s, rng)
	p(V3(s.X, s.Y, 0.2), 0, 5, 0, WOOD_D, M.Wood)
	p(V3(s.X - 0.5, s.Y - 0.5, 0.22), 0, 5, -0.02, FABRICS[rng:NextInteger(1, #FABRICS)], M.SmoothPlastic)
	p(V3(s.X * 0.4, s.Y * 0.3, 0.24), -0.4, 4.8, -0.03, Color3.fromRGB(240, 200, 90), M.SmoothPlastic)
end
SHAPES.fan = function(p, s)
	p(V3(1.4, 0.2, 1.4), 0, 0.1, 0, DARK, M.SmoothPlastic)
	p(V3(0.2, s.Y - 2, 0.2), 0, (s.Y - 2) / 2 + 0.2, 0, STEEL, M.Metal)
	local head = p(V3(0.4, 1.9, 1.9), 0, s.Y - 1, 0, Color3.fromRGB(200, 210, 220), M.SmoothPlastic)
	head.Shape = Enum.PartType.Cylinder
	head.CFrame = head.CFrame * CFrame.Angles(0, rad(90), 0)
	head.Transparency = 0.3
end

-- Returns Model (PrimaryPart = Base) and extras { seat = Seat?, light = BasePart? }.
function Factory.build(def, seed: number?)
	local model = Instance.new("Model")
	model.Name = def.id
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = def.size
	base.Transparency = 1
	base.Anchored = true
	base.CanCollide = false
	base.CanTouch = false
	base.CanQuery = true -- the build tool clicks on this
	base.CFrame = CF(0, def.size.Y / 2, 0)
	base.Parent = model
	model.PrimaryPart = base
	local floor = CF(0, 0, 0)
	local solid = def.size.Y >= 1 and def.shape ~= "garage"
	local function p(size, x, y, z, color, mat)
		local part = Instance.new("Part")
		part.Size = size
		part.Color = color
		part.Material = mat or M.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = true
		part.CanTouch = false
		part.CanCollide = solid
		part.CFrame = floor * CF(x, y, z)
		part.Parent = model
		return part
	end
	local fn = SHAPES[def.shape] or SHAPES.table
	local extra = fn(p, def.size, Random.new(seed or 1)) or {}
	if extra.seat then
		local seat = Instance.new("Seat")
		seat.Size = V3(math.min(def.size.X - 0.6, 6), 0.2, 1.4)
		seat.Transparency = 1
		seat.Anchored = true
		seat.CanCollide = false
		seat.CFrame = extra.seat * CF(0, -0.1, 0)
		seat.Parent = model
	end
	if extra.light then
		local l = Instance.new("PointLight")
		l.Range = 20; l.Brightness = 1.2; l.Color = Color3.fromRGB(255, 220, 170); l.Shadows = false
		l.Enabled = false
		l.Parent = extra.light
		extra.light:AddTag("NightLight")
		extra.light:SetAttribute("DayMaterial", extra.light.Material.Name)
		extra.light:AddTag("NightGlow")
	end
	return model
end

return Factory
