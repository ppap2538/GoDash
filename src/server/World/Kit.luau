-- Part helpers for the procedural world. Everything is anchored and never touch-sensitive.
local MaterialService = game:GetService("MaterialService")
local Materials = require(game:GetService("ReplicatedStorage").Shared.Config.Materials)

local Kit = {}

local M = Enum.Material
Kit.M = M
local VARIANT = Materials.DEFAULT

-- The PBR MaterialVariants are written into the place file by tools/build_place.py, because game
-- scripts are not allowed to create them. This only fills in missing ones when it is run with
-- plugin rights (the Studio command bar); in a running game it does nothing.
function Kit.setupMaterials()
	for name, v in pairs(Materials.VARIANTS) do
		if not MaterialService:FindFirstChild(name) then
			pcall(function()
				local mv = Instance.new("MaterialVariant")
				mv.Name = name
				mv.BaseMaterial = v.base
				mv.ColorMap = v.color
				mv.NormalMap = v.normal
				mv.RoughnessMap = v.rough
				if v.metal then mv.MetalnessMap = v.metal end
				mv.StudsPerTile = v.tile
				mv.MaterialPattern = Enum.MaterialPattern.Organic
				mv.Parent = MaterialService
			end)
		end
	end
end

Kit.COLORS = {
	asphalt = Color3.fromRGB(58, 60, 64),
	asphaltSoi = Color3.fromRGB(72, 74, 78),
	dirt = Color3.fromRGB(150, 116, 84),
	walk = Color3.fromRGB(214, 212, 206),
	curb = Color3.fromRGB(150, 148, 142),
	line = Color3.fromRGB(240, 240, 235),
	lineYellow = Color3.fromRGB(238, 196, 52),
	grass = Color3.fromRGB(98, 150, 74),
	grassDry = Color3.fromRGB(150, 160, 84),
	paddy = Color3.fromRGB(128, 176, 72),
	concrete = Color3.fromRGB(206, 204, 198),
	glass = Color3.fromRGB(70, 84, 98),
	glassDark = Color3.fromRGB(44, 50, 58),
	wood = Color3.fromRGB(128, 88, 56),
	woodDark = Color3.fromRGB(88, 60, 40),
	roofTile = Color3.fromRGB(176, 84, 56),
	roofBlue = Color3.fromRGB(70, 96, 130),
	roofGrey = Color3.fromRGB(110, 112, 118),
	metal = Color3.fromRGB(150, 154, 160),
	metalDark = Color3.fromRGB(70, 74, 80),
	white = Color3.fromRGB(240, 240, 238),
	gold = Color3.fromRGB(226, 180, 60),
	godash = Color3.fromRGB(28, 168, 84),
	leaf = Color3.fromRGB(64, 132, 60),
	leafLight = Color3.fromRGB(104, 164, 70),
	leafDark = Color3.fromRGB(44, 104, 54),
	trunk = Color3.fromRGB(104, 78, 54),
	water = Color3.fromRGB(58, 132, 170),
}

Kit.PASTEL = {
	Color3.fromRGB(238, 226, 196), Color3.fromRGB(226, 234, 214), Color3.fromRGB(240, 214, 204), Color3.fromRGB(210, 226, 238),
	Color3.fromRGB(244, 236, 220), Color3.fromRGB(232, 220, 236), Color3.fromRGB(216, 216, 212), Color3.fromRGB(246, 232, 188),
	Color3.fromRGB(200, 222, 214), Color3.fromRGB(236, 200, 180),
}
Kit.AWNING = {
	Color3.fromRGB(200, 60, 50), Color3.fromRGB(40, 120, 190), Color3.fromRGB(240, 170, 40), Color3.fromRGB(40, 150, 90),
	Color3.fromRGB(230, 120, 60), Color3.fromRGB(120, 80, 170), Color3.fromRGB(220, 90, 130),
}

local FACE = {
	N = Vector3.new(0, 0, -1), S = Vector3.new(0, 0, 1), E = Vector3.new(1, 0, 0), W = Vector3.new(-1, 0, 0),
}
Kit.FACE = FACE

-- Frame at ground level whose LookVector (-Z local) is the front direction.
function Kit.frame(x: number, z: number, face: string): CFrame
	local p = Vector3.new(x, 0, z)
	return CFrame.lookAt(p, p + FACE[face])
end

-- Solid block. opts: { name, transparency, reflectance, shadow=false, decor=true (no collide/query), shape }
function Kit.part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, opts: any?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	local variant = (opts and opts.variant) or VARIANT[p.Material]
	if variant then p.MaterialVariant = variant end
	if opts then
		if opts.name then p.Name = opts.name end
		if opts.transparency then p.Transparency = opts.transparency end
		if opts.reflectance then p.Reflectance = opts.reflectance end
		if opts.shadow == false then p.CastShadow = false end
		if opts.shape then p.Shape = opts.shape end
		if opts.decor then
			p.CanCollide = false
			p.CanQuery = false
			p.CastShadow = opts.shadow == true
		end
	end
	p.Parent = parent
	return p
end

function Kit.wedge(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, opts: any?): WedgePart
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.CanTouch = false
	local variant = (opts and opts.variant) or VARIANT[p.Material]
	if variant then p.MaterialVariant = variant end
	if opts and opts.decor then p.CanCollide = false; p.CanQuery = false end
	p.Parent = parent
	return p
end

-- Upright cylinder (axis = local Y of cf).
function Kit.cyl(parent: Instance, diameter: number, height: number, cf: CFrame, color: Color3, material: Enum.Material?, opts: any?): Part
	local o = opts and table.clone(opts) or {}
	o.shape = Enum.PartType.Cylinder
	return Kit.part(parent, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, o)
end

function Kit.ball(parent: Instance, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, opts: any?): Part
	local o = opts and table.clone(opts) or {}
	o.shape = Enum.PartType.Ball
	return Kit.part(parent, Vector3.new(diameter, diameter, diameter), cf, color, material, o)
end

-- Gable roof over a w x d footprint: two wedges meeting on a ridge that runs along local X.
function Kit.gable(parent: Instance, base: CFrame, w: number, d: number, rise: number, y: number, color: Color3, material: Enum.Material?)
	local half = d / 2
	-- WedgePart slopes down toward its local -Z... the high edge is at +Z, so face the high edges together.
	Kit.wedge(parent, Vector3.new(w, rise, half), base * CFrame.new(0, y + rise / 2, -half / 2), color, material or M.Slate)
	Kit.wedge(parent, Vector3.new(w, rise, half), base * CFrame.new(0, y + rise / 2, half / 2) * CFrame.Angles(0, math.rad(180), 0), color, material or M.Slate)
end

-- Text on a part face. opts: { face, color, bg, sub (second line), font, maxDistance, light }
function Kit.sign(part: BasePart, text: string, opts: any?)
	local o = opts or {}
	local g = Instance.new("SurfaceGui")
	g.Face = o.face or Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = o.pps or 22
	g.LightInfluence = o.light and 0 or 0.6
	g.MaxDistance = o.maxDistance or 320
	g.Parent = part
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = o.bg or part.Color
	bg.BackgroundTransparency = o.bg and 0 or 1
	bg.BorderSizePixel = 0
	bg.Parent = g
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = o.sub and UDim2.fromScale(0.94, 0.58) or UDim2.fromScale(0.94, 0.9)
	t.Position = o.sub and UDim2.fromScale(0.03, 0.04) or UDim2.fromScale(0.03, 0.05)
	t.Text = text
	t.TextScaled = true
	t.Font = o.font or Enum.Font.GothamBold
	t.TextColor3 = o.color or Color3.new(1, 1, 1)
	t.Parent = bg
	if o.sub then
		local s = Instance.new("TextLabel")
		s.BackgroundTransparency = 1
		s.Size = UDim2.fromScale(0.94, 0.34)
		s.Position = UDim2.fromScale(0.03, 0.62)
		s.Text = o.sub
		s.TextScaled = true
		s.Font = Enum.Font.GothamMedium
		s.TextColor3 = o.color or Color3.new(1, 1, 1)
		s.TextTransparency = 0.1
		s.Parent = bg
	end
	return g
end

-- Light that the client switches on at night (tag "NightLight"); the part glows too.
function Kit.nightLight(part: BasePart, range: number?, color: Color3?, brightness: number?)
	local l = Instance.new("PointLight")
	l.Range = range or 28
	l.Brightness = brightness or 1.4
	l.Color = color or Color3.fromRGB(255, 220, 170)
	l.Shadows = false
	l.Enabled = false
	l.Parent = part
	part:AddTag("NightLight")
	return l
end

-- Neon that only glows at night (signs, shop strips).
function Kit.nightGlow(part: BasePart)
	part:SetAttribute("DayMaterial", part.Material.Name)
	part:AddTag("NightGlow")
end

function Kit.model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Kit.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- World-space prompt holder (invisible).
function Kit.prompt(parent: Instance, pos: Vector3, action: string, object: string, kind: string, id: string, hold: number?)
	local p = Instance.new("Part")
	p.Name = "Interact_" .. id
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(2, 2, 2)
	p.CFrame = CFrame.new(pos)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = hold or 0
	pp.MaxActivationDistance = 16
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Parent = p
	p:SetAttribute("Kind", kind)
	p:SetAttribute("Id", id)
	p:AddTag("GoDashPrompt")
	p.Parent = parent
	return p, pp
end

return Kit
