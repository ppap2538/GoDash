-- The small things that make a Thai street look lived-in: bins, utility cabinets, road-name and
-- traffic signs, potted plants, food carts, plastic tables and stools, manholes, drain grates,
-- road patches. Frames: `cf` stands on the pavement with -Z pointing at the road unless noted.
local Kit = require(script.Parent.Kit)
local Assets = require(script.Parent.Assets)
local M = Kit.M
local C = Kit.COLORS
local V3 = Vector3.new
local CF = CFrame.new
local rad = math.rad

local Life = {}
local D = { decor = true }

function Life.bin(parent: Instance, cf: CFrame, rng: Random)
	if rng:NextNumber() < 0.5 and Assets.place(parent, "trash", cf, 0.85) then return end
	local col = ({ Color3.fromRGB(40, 120, 70), Color3.fromRGB(40, 90, 160), Color3.fromRGB(220, 170, 40) })[rng:NextInteger(1, 3)]
	Kit.part(parent, V3(2.2, 3.3, 2.4), cf * CF(0, 1.75, 0), col, M.SmoothPlastic)
	Kit.part(parent, V3(2.4, 0.3, 2.7), cf * CF(0, 3.5, 0.05) * CFrame.Angles(rad(4), 0, 0), Color3.new(col.R * 0.8, col.G * 0.8, col.B * 0.8), M.SmoothPlastic, D)
end

function Life.cabinet(parent: Instance, cf: CFrame)
	if Assets.place(parent, "box", cf, 1.3) then return end
	Kit.part(parent, V3(3.4, 0.5, 1.8), cf * CF(0, 0.25, 0), Color3.fromRGB(170, 168, 162), M.Concrete, { variant = "GD_ConcreteWall" })
	Kit.part(parent, V3(3, 4.8, 1.4), cf * CF(0, 2.9, 0), Color3.fromRGB(172, 178, 172), M.Metal)
	Kit.part(parent, V3(0.06, 4.2, 0.06), cf * CF(0, 2.9, -0.72), Color3.fromRGB(110, 114, 110), M.Metal, D)
	local tag = Kit.part(parent, V3(1.1, 0.8, 0.05), cf * CF(-0.8, 4.3, -0.73), Color3.fromRGB(240, 200, 40), M.SmoothPlastic, D)
	Kit.sign(tag, "⚡", { color = Color3.fromRGB(30, 30, 30), maxDistance = 60 })
end

-- Thai road-name sign: blue blades with white text, Thai above English.
function Life.roadName(parent: Instance, cf: CFrame, thai: string, en: string, thai2: string?, en2: string?)
	Kit.cyl(parent, 0.45, 11, cf * CF(0, 5.5, 0), Color3.fromRGB(150, 156, 162), M.Metal, D)
	local blue = Color3.fromRGB(20, 70, 160)
	local a = Kit.part(parent, V3(7.5, 1.9, 0.2), cf * CF(0, 10.2, 0), blue, M.SmoothPlastic, D)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		Kit.sign(a, thai, { sub = en, face = face, bg = blue, maxDistance = 200, pps = 30 })
	end
	if thai2 then
		local b = Kit.part(parent, V3(0.2, 1.9, 7.5), cf * CF(0, 8.1, 0), blue, M.SmoothPlastic, D)
		for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
			Kit.sign(b, thai2, { sub = en2, face = face, bg = blue, maxDistance = 200, pps = 30 })
		end
	end
end

-- kind: "limit" (speed), "noparking", "school", "oneway"
function Life.trafficSign(parent: Instance, cf: CFrame, kind: string)
	Kit.cyl(parent, 0.4, 9.5, cf * CF(0, 4.75, 0), Color3.fromRGB(150, 156, 162), M.Metal, D)
	local face = Kit.cyl(parent, 3, 0.15, cf * CF(0, 8.6, -0.25) * CFrame.Angles(rad(90), 0, 0), kind == "noparking" and Color3.fromRGB(30, 80, 180) or Color3.fromRGB(240, 240, 240), M.SmoothPlastic, D)
	local board = Kit.part(parent, V3(2.5, 2.5, 0.05), cf * CF(0, 8.6, -0.36), Color3.fromRGB(240, 240, 240), M.SmoothPlastic, { decor = true, transparency = 1 })
	local text, col = "50", Color3.fromRGB(20, 20, 20)
	if kind == "noparking" then text, col = "ห้ามจอด", Color3.new(1, 1, 1) elseif kind == "school" then text = "โรงเรียน" elseif kind == "oneway" then text = "→" end
	Kit.sign(board, text, { color = col, maxDistance = 160, pps = 40 })
	if kind ~= "noparking" then
		-- red ring
		local ring = Kit.cyl(parent, 3.3, 0.1, cf * CF(0, 8.6, -0.2) * CFrame.Angles(rad(90), 0, 0), Color3.fromRGB(200, 30, 30), M.SmoothPlastic, D)
		ring.Name = "Ring"
	end
	local _ = face
end

function Life.pot(parent: Instance, cf: CFrame, rng: Random)
	local s = rng:NextNumber(0.85, 1.3)
	if rng:NextNumber() < 0.6 and Assets.place(parent, "plant", cf * CFrame.Angles(0, rad(rng:NextNumber(0, 360)), 0), 4.4 * s) then return end
	Kit.cyl(parent, 1.9 * s, 1.6 * s, cf * CF(0, 0.8 * s, 0), ({ Color3.fromRGB(170, 96, 66), Color3.fromRGB(96, 100, 106), Color3.fromRGB(226, 220, 206) })[rng:NextInteger(1, 3)], M.Concrete, { variant = "GD_ConcreteWall" })
	local green = ({ C.leaf, C.leafLight, C.leafDark })[rng:NextInteger(1, 3)]
	if rng:NextNumber() < 0.5 then
		Kit.ball(parent, 2.6 * s, cf * CF(0, 2.6 * s, 0), green, M.LeafyGrass, D)
		Kit.ball(parent, 1.8 * s, cf * CF(0.5 * s, 3.6 * s, 0.2), Color3.new(green.R * 1.1, green.G * 1.1, green.B), M.LeafyGrass, D)
	else
		-- tall fronds
		for i = 0, 4 do
			Kit.part(parent, V3(0.5 * s, 0.1, 3.4 * s), cf * CF(0, 1.7 * s, 0) * CFrame.Angles(0, rad(i * 72 + 10), 0) * CFrame.Angles(rad(52), 0, 0) * CF(0, 0, -1.6 * s), green, M.LeafyGrass, D)
		end
	end
end

function Life.stool(parent: Instance, cf: CFrame, col: Color3)
	Kit.cyl(parent, 1.2, 1.6, cf * CF(0, 0.8, 0), col, M.SmoothPlastic)
end

function Life.tableSet(parent: Instance, cf: CFrame, rng: Random)
	local col = ({ Color3.fromRGB(200, 50, 50), Color3.fromRGB(50, 100, 190), Color3.fromRGB(240, 240, 236) })[rng:NextInteger(1, 3)]
	Kit.part(parent, V3(3.4, 0.2, 3.4), cf * CF(0, 2.6, 0), Color3.fromRGB(196, 200, 204), M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			Kit.part(parent, V3(0.2, 2.5, 0.2), cf * CF(sx * 1.4, 1.25, sz * 1.4), Color3.fromRGB(120, 124, 130), M.Metal, D)
		end
	end
	for i = 0, 3 do
		local seat = cf * CFrame.Angles(0, rad(i * 90 + rng:NextNumber(-15, 15)), 0) * CF(0, 0, -3)
		-- monobloc chairs face the table; fall back to stools without the mesh
		if not Assets.place(parent, "chair", seat * CFrame.Angles(0, rad(180), 0), 1) then Life.stool(parent, seat, col) end
	end
	-- condiment caddy
	Kit.part(parent, V3(1, 0.7, 0.6), cf * CF(0.3, 3.05, 0.2), Color3.fromRGB(200, 60, 40), M.SmoothPlastic, D)
end

function Life.foodCart(parent: Instance, cf: CFrame, rng: Random, label: string?)
	local steel = Color3.fromRGB(196, 200, 206)
	if Assets.place(parent, "cart", cf, 1) then
		-- the real cart: add only the umbrella, a light and the seats
		local col = ({ Color3.fromRGB(200, 50, 50), Color3.fromRGB(40, 110, 180), Color3.fromRGB(240, 190, 50), Color3.fromRGB(40, 140, 90) })[rng:NextInteger(1, 4)]
		Kit.cyl(parent, 0.25, 11, cf * CF(4.6, 5.5, 1.2), Color3.fromRGB(180, 184, 190), M.Metal, D)
		Kit.cyl(parent, 11, 0.25, cf * CF(4.6, 10.9, 1.2), col, M.Fabric, { decor = true, shadow = true })
		Kit.cyl(parent, 5.5, 0.9, cf * CF(4.6, 11.4, 1.2), col, M.Fabric, D)
		local bulb = Kit.ball(parent, 0.7, cf * CF(4.6, 10.2, 0.2), Color3.fromRGB(255, 240, 210), M.SmoothPlastic, D)
		Kit.nightGlow(bulb); Kit.nightLight(bulb, 20, Color3.fromRGB(255, 226, 180), 1.5)
		for i, x in ipairs({ -2.2, 1.4 }) do
			if not Assets.place(parent, "chair", cf * CF(x, 0, 4.2) * CFrame.Angles(0, rad(i == 1 and 20 or -15), 0), 1) then Life.stool(parent, cf * CF(x, 0, 4), col) end
		end
		return
	end
	Kit.part(parent, V3(6, 2.4, 2.8), cf * CF(0, 2.4, 0), steel, M.Metal)
	Kit.part(parent, V3(6.2, 0.2, 3), cf * CF(0, 3.7, 0), steel, M.Metal, D)
	Kit.part(parent, V3(5.4, 2.2, 0.12), cf * CF(0, 4.9, -1.3), Color3.fromRGB(190, 220, 235), M.Glass, { decor = true, transparency = 0.55 })
	for _, sx in ipairs({ -1, 1 }) do
		Kit.part(parent, V3(0.15, 2.2, 2.6), cf * CF(sx * 2.7, 4.9, 0), Color3.fromRGB(190, 220, 235), M.Glass, { decor = true, transparency = 0.55 })
		Kit.cyl(parent, 1.6, 0.3, cf * CF(sx * 2.2, 0.8, 0.9) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(30, 30, 32), M.SmoothPlastic, D)
	end
	Kit.part(parent, V3(5.6, 0.15, 2.8), cf * CF(0, 6.05, 0), steel, M.Metal, D)
	-- food in the case
	for i = -1, 1 do
		Kit.part(parent, V3(1.4, 0.5, 1.6), cf * CF(i * 1.7, 4, 0), ({ Color3.fromRGB(226, 150, 70), Color3.fromRGB(190, 70, 50), Color3.fromRGB(240, 220, 150) })[i + 2], M.SmoothPlastic, D)
	end
	-- umbrella
	local col = ({ Color3.fromRGB(200, 50, 50), Color3.fromRGB(40, 110, 180), Color3.fromRGB(240, 190, 50), Color3.fromRGB(40, 140, 90) })[rng:NextInteger(1, 4)]
	Kit.cyl(parent, 0.25, 10, cf * CF(3.6, 5, 1.6), Color3.fromRGB(180, 184, 190), M.Metal, D)
	Kit.cyl(parent, 10, 0.25, cf * CF(3.6, 9.9, 1.6), col, M.Fabric, { decor = true, shadow = true })
	Kit.cyl(parent, 5, 0.9, cf * CF(3.6, 10.4, 1.6), col, M.Fabric, D)
	local tube = Kit.part(parent, V3(4.6, 0.2, 0.2), cf * CF(0, 5.85, -1.1), Color3.fromRGB(246, 250, 255), M.SmoothPlastic, D)
	Kit.nightGlow(tube); Kit.nightLight(tube, 18, Color3.fromRGB(255, 236, 200), 1.4)
	if label then
		local s = Kit.part(parent, V3(5.4, 1.2, 0.1), cf * CF(0, 6.8, -1.3), Color3.fromRGB(236, 60, 50), M.SmoothPlastic, D)
		Kit.sign(s, label, { bg = Color3.fromRGB(236, 60, 50), maxDistance = 140 })
	end
	Life.stool(parent, cf * CF(-1.5, 0, 3.4), col)
	Life.stool(parent, cf * CF(1.2, 0, 3.6), col)
end

-- on the carriageway (cf = spot on the road surface, y = road top)
function Life.manhole(parent: Instance, pos: Vector3)
	if Assets.place(parent, "manhole", CF(pos - V3(0, 0.16, 0)), 1.25) then return end
	Kit.cyl(parent, 3.2, 0.08, CF(pos + V3(0, 0.02, 0)), Color3.fromRGB(70, 72, 76), M.DiamondPlate, D)
end

function Life.grate(parent: Instance, cf: CFrame)
	Kit.part(parent, V3(3.2, 0.08, 1.3), cf * CF(0, 0.02, 0), Color3.fromRGB(56, 58, 62), M.DiamondPlate, D)
end

function Life.patch(parent: Instance, cf: CFrame, rng: Random)
	local k = rng:NextNumber(0.72, 0.9)
	Kit.part(parent, V3(rng:NextNumber(6, 14), 0.05, rng:NextNumber(8, 26)), cf * CF(0, 0.015, 0), Color3.new(k, k, k), M.Asphalt, { decor = true, variant = "GD_AsphaltWorn" })
end

Life.CART_LABELS = { "ลูกชิ้นปิ้ง", "ส้มตำ", "น้ำปั่น", "หมูปิ้ง", "ข้าวเหนียวไก่ทอด", "ผลไม้สด", "ชาไทย", "โรตี" }

return Life
