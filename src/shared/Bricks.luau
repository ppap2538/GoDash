-- Toy-brick look (Config/Look.BRICKS, 2026-11-20). Bricks.part(p) turns one part into a plastic toy brick:
--   * Material Plastic: the only material Roblox draws studs on (SmoothPlastic, Concrete and MaterialVariants
--     show none; tested in Studio 2026-11-20);
--   * studs on whichever face points up, the classic inlet on the face underneath;
--   * no photo-scanned MaterialVariant;
--   * the colour moved to the nearest classic brick colour after a little extra saturation, so the whole city
--     shares one toy palette. Roads, pavements and lawns get fixed toy colours.
-- Doing a part twice changes nothing (a colour that already is a brick colour is kept), so builders may call it
-- and a watcher may still pass over the same part later.
-- Figures are never touched: anything inside a model with a Humanoid, or a block figure (Head + Torso).
local RunService = game:GetService("RunService")
local Look = require(script.Parent.Config.Look)

local Bricks = {}
Bricks.ON = Look.BRICKS == true

local M = Enum.Material
local KEEP = { [M.Neon] = true, [M.Glass] = true, [M.ForceField] = true, [M.Water] = true }
local OPP = { Top = "Bottom", Bottom = "Top", Right = "Left", Left = "Right", Front = "Back", Back = "Front" }

-- The toy palette: classic brick colours. Our own list and our own distance, because BrickColor.new(Color3)
-- picks odd neighbours (a dark grey came out "Medium brown", a light grey "Sand violet metallic").
-- Greys, whites and creams only ever map to the neutral list, so a grey stays grey.
local NEUTRAL = {
	{ 242, 243, 243 }, { 229, 228, 223 }, { 205, 205, 205 }, { 163, 162, 165 }, { 128, 128, 132 }, { 99, 95, 98 },
	{ 66, 66, 70 }, { 27, 42, 53 }, { 215, 197, 154 }, { 234, 222, 190 },
}
local COLOURS = {
	{ 196, 40, 28 }, { 163, 75, 75 }, { 255, 148, 148 }, { 190, 104, 98 }, { 238, 196, 182 },
	{ 218, 133, 65 }, { 255, 176, 0 }, { 245, 205, 48 }, { 253, 234, 141 }, { 248, 217, 109 }, { 234, 184, 146 },
	{ 204, 142, 105 }, { 160, 95, 53 }, { 124, 92, 70 }, { 105, 64, 40 }, { 199, 172, 120 }, { 188, 155, 93 },
	{ 75, 151, 75 }, { 40, 127, 71 }, { 39, 70, 45 }, { 124, 156, 107 }, { 161, 196, 140 }, { 164, 189, 71 }, { 194, 218, 184 },
	{ 13, 105, 172 }, { 110, 153, 202 }, { 128, 187, 219 }, { 180, 210, 228 }, { 82, 124, 174 }, { 32, 58, 86 }, { 0, 143, 156 },
	{ 107, 50, 124 }, { 140, 91, 159 }, { 232, 186, 200 }, { 255, 152, 220 },
}
local function rgb(t): Color3 return Color3.fromRGB(t[1], t[2], t[3]) end
local IN = {} -- hex of every palette colour: already done
for _, list in ipairs({ NEUTRAL, COLOURS }) do
	for i, t in ipairs(list) do
		list[i] = rgb(t)
		IN[list[i]:ToHex()] = true
	end
end
local FIXED = {
	[M.Asphalt] = rgb({ 66, 66, 70 }), -- road
	[M.Pavement] = rgb({ 163, 162, 165 }), -- pavement
	[M.Grass] = rgb({ 75, 151, 75 }), -- lawn
}

local function nearest(c: Color3, list): Color3
	local r, g, b = c.R * 255, c.G * 255, c.B * 255
	local best, bestD = list[1], math.huge
	for _, p in ipairs(list) do
		local pr, pg, pb = p.R * 255, p.G * 255, p.B * 255
		local rm = (r + pr) / 2 -- "redmean": a cheap distance close to what the eye sees
		local dr, dg, db = r - pr, g - pg, b - pb
		local d = (2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db
		if d < bestD then best, bestD = p, d end
	end
	return best
end

-- the builders' dusty paint, made bolder and moved to the toy palette
function Bricks.color(c: Color3): Color3
	if IN[c:ToHex()] then return c end
	local h, s, v = c:ToHSV()
	if s < 0.12 or v < 0.16 then return nearest(c, NEUTRAL) end
	return nearest(Color3.fromHSV(h, math.min(1, s * 1.5 + 0.08), v), COLOURS)
end

-- which face of a block points up (within ~14 degrees), or nil
local function upFace(cf: CFrame): string?
	local u, r, l = cf.UpVector.Y, cf.RightVector.Y, cf.LookVector.Y
	local best, dot = nil, 0.97
	if u > dot then best, dot = "Top", u end
	if -u > dot then best, dot = "Bottom", -u end
	if r > dot then best, dot = "Right", r end
	if -r > dot then best, dot = "Left", -r end
	if l > dot then best, dot = "Front", l end -- the Front face looks along LookVector
	if -l > dot then best, dot = "Back", -l end
	return best
end

local TOY_GLASS = Color3.fromRGB(128, 187, 219)
-- Roblox draws no studs on a cylinder, so the round junction pads (and other flat discs: roundabouts, plazas) were
-- smooth grey circles in the studded road (owner 2026-11-20, screenshot). A tiled stud picture on the face that points
-- up fills them in (assets/textures/facade/toy_stud.png, one stud per stud like the surface studs).
local STUD_TEX = "rbxassetid://93821885681967"

local function discStuds(p: Part)
	local r = p.CFrame.RightVector.Y -- a cylinder's axis is its local X
	if math.abs(r) < 0.97 or p.Size.Y < 4 or p.Size.X > p.Size.Y * 0.5 then return end
	if p.Transparency >= 1 or STUD_TEX == "rbxassetid://0" or p:FindFirstChild("BrickStuds") then return end
	local t = Instance.new("Texture")
	t.Name = "BrickStuds"
	t.Texture = STUD_TEX
	t.Face = r > 0 and Enum.NormalId.Right or Enum.NormalId.Left
	t.StudsPerTileU, t.StudsPerTileV = 1, 1
	t.Parent = p
end

function Bricks.part(p: BasePart, keepColor: boolean?)
	if p:IsA("MeshPart") then return end
	local mat = p.Material
	if mat == M.Glass then
		-- toy windows: light see-through blue (vehicle cabins showed a dark navy block)
		p.Color = TOY_GLASS
		if p.Transparency < 0.25 then p.Transparency = 0.25 end
		p.Reflectance = 0.05
		return
	end
	if KEEP[mat] then return end
	if p.Reflectance > 0 then p.Reflectance = 0 end -- matte toy plastic (client/Env still wets the roads)
	if p.MaterialVariant ~= "" then p.MaterialVariant = "" end
	if mat ~= M.Plastic then
		p.Material = M.Plastic
		if p:GetAttribute("DayMaterial") then p:SetAttribute("DayMaterial", "Plastic") end -- client/Env night glow
	end
	if not keepColor and p.Transparency < 1 then p.Color = FIXED[mat] or Bricks.color(p.Color) end
	if p:IsA("Part") and p.Shape == Enum.PartType.Cylinder then discStuds(p) end
	if p:IsA("Part") and p.Shape == Enum.PartType.Block then
		local f = upFace(p.CFrame)
		if f then
			local q: any = p
			q[f .. "Surface"] = Enum.SurfaceType.Studs
			q[OPP[f] .. "Surface"] = Enum.SurfaceType.Inlet
		end
	end
end

local function isFigure(p: Instance): boolean
	local m = p:FindFirstAncestorWhichIsA("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") or (m:FindFirstChild("Head") and m:FindFirstChild("Torso")) then return true end
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return false
end
Bricks.isFigure = isFigure

-- Every part under root, now (root not yet in the world: no replication cost).
function Bricks.tree(root: Instance, keepColor: boolean?)
	if not Bricks.ON then return end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and not isFigure(d) then Bricks.part(d, keepColor) end
	end
end

-- Everything under root now and whatever is added later, a little each frame (2 ms) so a chunk of city
-- streaming in never causes a hitch.
function Bricks.watch(root: Instance, keepColor: boolean?)
	if not Bricks.ON then return end
	local queue, head = {}, 1
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(queue, d) end
	end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then table.insert(queue, d) end
	end)
	RunService.Heartbeat:Connect(function()
		local n = #queue
		if head > n then
			if head > 1 then table.clear(queue); head = 1 end
			return
		end
		local t0 = os.clock()
		while head <= n and os.clock() - t0 < 0.002 do
			local p = queue[head]
			head += 1
			if p.Parent and not isFigure(p) then Bricks.part(p, keepColor) end
		end
	end)
end

return Bricks
