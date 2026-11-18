-- What stands on a property: every building here comes with its land (pad, walls, gate, yard), so
-- a block is filled edge to edge and nobody can cut across private ground.
-- Local frame for all of them: base = centre of the property at ground level, street front = -Z,
-- w = width along the street, dp = depth of the property.
-- o.prev = -1 | 1 : which local X side the previous lot of the same street side is on (that wall is
--                   always drawn); o.endWall = true also draws the wall on the other side.
local Kit = require(script.Parent.Kit)
local S = require(script.Parent.Scenery)
local Shophouse = require(script.Parent.Shophouse)
local M = Kit.M
local C = Kit.COLORS
local V3 = Vector3.new
local CF = CFrame.new

local B = {}

local WALLS = {
	Color3.fromRGB(214, 208, 196), Color3.fromRGB(198, 192, 180), Color3.fromRGB(226, 220, 206), Color3.fromRGB(188, 186, 180),
	Color3.fromRGB(206, 196, 176),
}
local ROOFS = { C.roofTile, C.roofBlue, C.roofGrey, Color3.fromRGB(150, 70, 60), Color3.fromRGB(122, 86, 66), Color3.fromRGB(96, 100, 104) }
local GATES = { Color3.fromRGB(70, 74, 80), Color3.fromRGB(110, 60, 48), Color3.fromRGB(60, 86, 70), Color3.fromRGB(150, 150, 146) }
local GRASS = Color3.fromRGB(112, 128, 78)
local DIRT = Color3.fromRGB(150, 126, 98)
local WALL_H = 8 -- a character jumps about 7 studs: property walls are not a shortcut
local darker = S.darker

local FACADE = Kit.FACADE
local facade = Kit.facade

local function shade(c: Color3, k: number): Color3
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

-- Ground pad, back wall, side walls and (optionally) a front wall with a gate opening.
-- o: { wall, height, prev, endWall, front = true, frontHeight, gate, gateX, gateColor,
--      ground = false | Color3, groundMat, groundVariant, back = false }
function B.compound(m: Instance, base: CFrame, w: number, dp: number, o: any)
	local hgt = o.height or WALL_H
	local col = o.wall or WALLS[1]
	local wo = { name = "Wall", variant = "GD_Plaster" }
	if o.ground ~= false then
		Kit.part(m, V3(w, 0.3, dp), base * CF(0, 0.15, 0), o.ground or C.concrete, o.groundMat or M.Concrete, { name = "LotPad", variant = o.groundVariant })
	end
	if o.back ~= false then
		Kit.part(m, V3(w, hgt, 0.8), base * CF(0, hgt / 2, dp / 2 - 0.4), col, M.Concrete, wo)
	end
	local prev = o.prev or -1
	Kit.part(m, V3(0.8, hgt, dp - 0.8), base * CF(prev * (w / 2 - 0.4), hgt / 2, -0.4), col, M.Concrete, wo)
	if o.endWall then
		Kit.part(m, V3(0.8, hgt, dp - 0.8), base * CF(-prev * (w / 2 - 0.4), hgt / 2, -0.4), col, M.Concrete, wo)
	end
	if o.front then
		local gx, gw = o.gateX or 0, o.gate or 12
		local fh = o.frontHeight or 5.5
		local lw = (gx - gw / 2) + w / 2
		local rw = w / 2 - (gx + gw / 2)
		if lw > 1.5 then Kit.part(m, V3(lw, fh, 0.7), base * CF(-w / 2 + lw / 2, fh / 2, -dp / 2 + 0.4), col, M.Concrete, wo) end
		if rw > 1.5 then Kit.part(m, V3(rw, fh, 0.7), base * CF(w / 2 - rw / 2, fh / 2, -dp / 2 + 0.4), col, M.Concrete, wo) end
		if o.gateColor then
			-- sliding steel gate, left half open
			Kit.part(m, V3(gw * 0.6, fh - 0.8, 0.3), base * CF(gx + gw * 0.2, fh / 2, -dp / 2 + 1), o.gateColor, M.Metal, { decor = true, transparency = 0.25 })
		end
	end
end

-- Detached house in its own walled compound (บ้านเดี่ยว).
function B.home(parent: Instance, base: CFrame, w: number, dp: number, rng: Random, o: any)
	local m = Kit.model(parent, "Home")
	local side = rng:NextNumber() < 0.5 and -1 or 1 -- which side the driveway is on
	local gateX = side * math.max(0, w / 2 - 9)
	local yard = rng:NextNumber()
	local ground, gmat, gvar = C.concrete, M.Concrete, "GD_ConcreteFloor"
	if yard < 0.45 then ground, gmat, gvar = GRASS, M.Grass, "GD_Grass" elseif yard > 0.82 then ground, gmat, gvar = DIRT, M.Ground, nil end
	B.compound(m, base, w, dp, {
		wall = WALLS[rng:NextInteger(1, #WALLS)], prev = o.prev, endWall = o.endWall, front = true, gate = 12, gateX = gateX,
		gateColor = GATES[rng:NextInteger(1, #GATES)], ground = ground, groundMat = gmat, groundVariant = gvar,
	})
	local bw = math.min(w - 9, rng:NextNumber(26, 38))
	local bd = math.clamp(dp - rng:NextNumber(15, 20), 16, 32)
	local two = rng:NextNumber() < (o.two or 0.45)
	local h = two and 19 or 10.5
	local bx = -side * math.max(0, (w - 6 - bw) / 2 - 1)
	local hb = base * CF(bx, 0.3, dp / 2 - 3.5 - bd / 2)
	local col = Kit.PASTEL[rng:NextInteger(1, #Kit.PASTEL)]
	local roof = ROOFS[rng:NextInteger(1, #ROOFS)]
	Kit.part(m, V3(bw, h, bd), hb * CF(0, h / 2, 0), col, M.Concrete, { variant = "GD_PaintedWall" })
	Kit.gable(m, hb, bw + 3, bd + 3, two and 5.5 or 4.5, h, roof, M.Slate)
	local fz = -bd / 2
	-- front: door under a canopy and a wide window; a second storey has its own row of windows
	facade(m, hb * CF(0, 5.25, fz - 0.16), bw, 10.5, FACADE.home, 1, 1, col, rng:NextNumber() < 0.6)
	if two then
		facade(m, hb * CF(0, 10.5 + (h - 10.5) / 2, fz - 0.16), bw, h - 10.5, FACADE.town, math.max(1, math.floor(bw / 17 + 0.5)), 1, col, rng:NextNumber() < 0.5)
		Kit.part(m, V3(bw + 1, 0.4, 3.2), hb * CF(0, 10.3, fz - 1.4), shade(col, 0.86), M.Concrete, { decor = true, shadow = true, variant = "GD_ConcreteWall" })
	end
	-- carport over the driveway
	local cw = math.min(11, w - bw - 4)
	if cw >= 8 and dp >= 34 then
		local cz = -dp / 2 + 9
		Kit.part(m, V3(cw, 0.35, 14), base * CF(gateX, 8.4, cz), darker(roof, 0.85), M.CorrodedMetal, { decor = true, shadow = true })
		for _, sx in ipairs({ -1, 1 }) do
			Kit.part(m, V3(0.4, 8.2, 0.4), base * CF(gateX + sx * (cw / 2 - 0.5), 4.3, cz - 6), C.metalDark, M.Metal, { decor = true })
		end
	end
	if rng:NextNumber() < 0.42 and dp >= 34 then
		local k = rng:NextNumber()
		S.tree(m, base * CF(-gateX * 0.55, 0.3, -dp / 2 + 7), rng, k < 0.3 and "banana" or (k < 0.5 and "palm" or "small"))
	end
	return m
end

-- A terrace of narrow homes with a shared roof and a small front yard each (ทาวน์เฮาส์).
function B.townhouses(parent: Instance, base: CFrame, w: number, dp: number, rng: Random, o: any)
	local m = Kit.model(parent, "Townhouses")
	local n = math.max(1, math.floor(w / 17 + 0.5))
	local uw = w / n
	local floors = rng:NextInteger(2, 3)
	local fh = 10.5
	local h = floors * fh
	local front = math.clamp(dp - 30, 4, 10)
	local bd = math.max(16, dp - front - 3)
	local hb = base * CF(0, 0.3, -dp / 2 + front + bd / 2)
	local col = Kit.PASTEL[rng:NextInteger(1, #Kit.PASTEL)]
	local roof = ROOFS[rng:NextInteger(1, #ROOFS)]
	Kit.part(m, V3(w, 0.3, dp), base * CF(0, 0.15, 0), C.concrete, M.Concrete, { name = "LotPad", variant = "GD_ConcreteFloor" })
	Kit.part(m, V3(w - 0.3, h, bd), hb * CF(0, h / 2, 0), col, M.Concrete, { variant = "GD_PaintedWall" })
	if rng:NextNumber() < 0.6 then
		Kit.gable(m, hb, w + 0.6, bd + 2.4, 4.6, h, roof, M.Slate)
	else
		Kit.part(m, V3(w, 1.2, bd + 0.6), hb * CF(0, h + 0.6, 0), shade(col, 0.78), M.Concrete, { decor = true, variant = "GD_ConcreteWall" })
	end
	local fz = -bd / 2
	-- each home: a folding gate over the car space and a front door below, louvred windows above
	facade(m, hb * CF(0, fh / 2, fz - 0.16), w, fh, FACADE.ground, n, 1, col, rng:NextNumber() < 0.5)
	for f = 2, floors do
		facade(m, hb * CF(0, (f - 1) * fh + fh / 2, fz - 0.16), w, fh, FACADE.town, n, 1, col, rng:NextNumber() < 0.6)
	end
	-- party walls, and a painted panel per home so each one reads as its own
	for i = 0, n do
		Kit.part(m, V3(1.1, h, 1.1), hb * CF(-w / 2 + uw * i + (i == 0 and 0.55 or (i == n and -0.55 or 0)), h / 2, fz - 0.4), shade(col, 0.9), M.Concrete, { decor = true, variant = "GD_ConcreteWall" })
	end
	for i = 1, n do
		local x = -w / 2 + uw * (i - 0.5)
		-- low front fence with a gate gap
		if front >= 6 then
			Kit.part(m, V3(uw - 7, 4, 0.6), base * CF(x - 3.2, 2.3, -dp / 2 + 0.4), WALLS[1], M.Concrete, { name = "Wall", variant = "GD_Plaster" })
		end
	end
	if front >= 6 then
		Kit.part(m, V3(w - 1, 0.3, front - 0.6), base * CF(0, 8.3, -dp / 2 + front / 2 + 0.3), darker(roof, 0.8), M.CorrodedMetal, { decor = true, shadow = true })
	end
	-- the terrace itself closes the back; end walls stop people walking round it
	Kit.part(m, V3(0.8, WALL_H, front + 1), base * CF((o.prev or -1) * (w / 2 - 0.4), WALL_H / 2, -dp / 2 + front / 2 + 0.5), WALLS[1], M.Concrete, { name = "Wall", variant = "GD_Plaster" })
	return m
end

local APT_NAMES = { "หอพักสุขใจ", "ร่มเย็น แมนชั่น", "KK Place", "U-Home", "หอพักบ้านเพื่อน", "ศรีจันทร์ เรสซิเดนซ์", "อพาร์ตเมนต์ ดีดี", "หอพักแก่นนคร" }

-- Walk-up apartment block with parking in front (อพาร์ตเมนต์ / หอพัก).
function B.apartment(parent: Instance, base: CFrame, w: number, dp: number, rng: Random, o: any)
	local m = Kit.model(parent, "Apartment")
	B.compound(m, base, w, dp, { wall = WALLS[rng:NextInteger(1, #WALLS)], prev = o.prev, endWall = o.endWall, ground = Color3.fromRGB(150, 150, 152), groundVariant = "GD_ConcreteFloor" })
	local bd = math.clamp(dp - 20, 22, 40)
	local bw = w - 6
	local floors = rng:NextInteger(3, o.tall and 7 or 5)
	local fh = 9.5
	local h = floors * fh
	local hb = base * CF(0, 0.3, dp / 2 - 2 - bd / 2)
	local col = Kit.PASTEL[rng:NextInteger(1, #Kit.PASTEL)]
	local fz = -bd / 2
	Kit.part(m, V3(bw, h, bd), hb * CF(0, h / 2, 0), col, M.Concrete, { variant = "GD_PaintedWall" })
	local lobby = Kit.part(m, V3(bw * 0.4, 6.6, 0.4), hb * CF(0, 3.5, fz - 0.1), C.glassDark, M.SmoothPlastic, { decor = true, reflectance = 0.1 })
	Kit.nightGlow(lobby)
	-- every room: balcony door and window behind a steel railing, an air-con; one tile per room
	local rooms = math.max(2, math.floor(bw / 10.5 + 0.5))
	for f = 2, floors do
		facade(m, hb * CF(0, (f - 1) * fh + fh / 2, fz - 0.16), bw, fh, FACADE.apartment, rooms, 1, col, rng:NextNumber() < 0.7)
	end
	-- ground floor rooms either side of the lobby
	local wing = (bw - bw * 0.4) / 2 - 1
	if wing >= 9 then
		for _, sx in ipairs({ -1, 1 }) do
			facade(m, hb * CF(sx * (bw * 0.2 + 1 + wing / 2), fh / 2, fz - 0.16), wing, fh, FACADE.apartment, math.max(1, math.floor(wing / 10.5 + 0.5)), 1, col, rng:NextNumber() < 0.5)
		end
	end
	Kit.part(m, V3(bw + 0.6, 1, bd + 0.6), hb * CF(0, h + 0.5, 0), shade(col, 0.72), M.Concrete, { decor = true, variant = "GD_ConcreteWall" })
	local sign = Kit.part(m, V3(math.min(bw * 0.6, 30), 2.8, 0.5), hb * CF(0, 8.4, fz - 0.5), Color3.fromRGB(52, 84, 140), M.SmoothPlastic, { decor = true })
	Kit.sign(sign, APT_NAMES[rng:NextInteger(1, #APT_NAMES)], { sub = "APARTMENT", maxDistance = 260 })
	-- parking bays
	local bays = math.floor((w - 8) / 9)
	for i = 0, bays do
		Kit.part(m, V3(0.4, 0.05, 12), base * CF(-(bays * 9) / 2 + i * 9, 0.33, -dp / 2 + 7.5), C.line, M.SmoothPlastic, { decor = true })
	end
	return m
end

local TOWER_KINDS = {
	{ "โรงแรม", "HOTEL", Color3.fromRGB(150, 40, 46) }, { "คอนโดมิเนียม", "CONDOMINIUM", Color3.fromRGB(40, 70, 120) },
	{ "อาคารสำนักงาน", "OFFICE TOWER", Color3.fromRGB(50, 56, 64) }, { "ธนาคาร", "BANK", Color3.fromRGB(30, 110, 70) },
	{ "ศูนย์การแพทย์", "MEDICAL CENTRE", Color3.fromRGB(40, 120, 150) }, { "โรงแรม แกรนด์", "GRAND HOTEL", Color3.fromRGB(120, 86, 30) },
}

-- Mid-rise on a podium for the main streets of the centre: hotel, condominium, office, bank.
function B.tower(parent: Instance, base: CFrame, w: number, dp: number, rng: Random, o: any)
	local m = Kit.model(parent, "Tower")
	local kind = TOWER_KINDS[rng:NextInteger(1, #TOWER_KINDS)]
	B.compound(m, base, w, dp, { wall = WALLS[4], prev = o.prev, endWall = o.endWall, ground = Color3.fromRGB(176, 174, 168), groundVariant = "GD_ConcreteFloor" })
	local floors = rng:NextInteger(o.minFloors or 7, o.maxFloors or 14)
	local pw, pd = w - 5, dp - 14
	local ph = 15
	local pb = base * CF(0, 0.3, dp / 2 - 2 - pd / 2)
	local col = ({ Color3.fromRGB(226, 224, 218), Color3.fromRGB(206, 208, 212), Color3.fromRGB(222, 212, 196), Color3.fromRGB(190, 196, 204) })[rng:NextInteger(1, 4)]
	Kit.part(m, V3(pw, ph, pd), pb * CF(0, ph / 2, 0), shade(col, 0.92), M.Concrete, { variant = "GD_ConcreteWall" })
	local lobby = Kit.part(m, V3(pw * 0.7, 9, 0.4), pb * CF(0, 5, -pd / 2 - 0.1), C.glassDark, M.SmoothPlastic, { decor = true, reflectance = 0.2 })
	Kit.nightGlow(lobby)
	Kit.part(m, V3(pw * 0.5, 0.6, 7), pb * CF(0, 10.4, -pd / 2 - 3.4), kind[3], M.Metal, { decor = true, shadow = true })
	local tw, td = pw - 10, pd - 8
	local th = floors * 10
	local tb = pb * CF(0, ph, 2)
	Kit.part(m, V3(tw, th, td), tb * CF(0, th / 2, 0), col, M.Concrete, { variant = "GD_PaintedWall" })
	-- curtain wall on all four sides: glass between mullions, a band at every floor
	local across, deep = math.max(2, math.floor(tw / 10 + 0.5)), math.max(2, math.floor(td / 10 + 0.5))
	facade(m, tb * CF(0, th / 2, -(td / 2 + 0.16)), tw, th, FACADE.tower, across, floors, col, rng:NextNumber() < 0.8)
	facade(m, tb * CF(0, th / 2, td / 2 + 0.16) * CFrame.Angles(0, math.pi, 0), tw, th, FACADE.tower, across, floors, col, rng:NextNumber() < 0.6)
	facade(m, tb * CF(tw / 2 + 0.16, th / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0), td, th, FACADE.tower, deep, floors, col, rng:NextNumber() < 0.6)
	facade(m, tb * CF(-(tw / 2 + 0.16), th / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), td, th, FACADE.tower, deep, floors, col, rng:NextNumber() < 0.6)
	Kit.part(m, V3(tw + 1, 1.4, td + 1), tb * CF(0, th + 0.7, 0), shade(col, 0.7), M.Concrete, { decor = true, variant = "GD_ConcreteWall" })
	local sign = Kit.part(m, V3(math.min(tw, 34), 5, 0.6), tb * CF(0, th - 5, -td / 2 - 0.5), kind[3], M.SmoothPlastic, { decor = true })
	Kit.sign(sign, kind[1], { sub = kind[2], light = true, maxDistance = 700, pps = 12 })
	Kit.nightGlow(sign)
	return m
end

-- Showroom / big-box store with its car park (the highway strip).
function B.bigbox(parent: Instance, base: CFrame, w: number, dp: number, rng: Random, o: any)
	local m = S.bigbox(parent, base, w, dp, rng)
	Kit.part(m, V3(w, WALL_H, 0.8), base * CF(0, WALL_H / 2, dp / 2 - 0.4), WALLS[4], M.Concrete, { name = "Wall", variant = "GD_Plaster" })
	return m
end

-- Land with no building: a small car park, a garden, a fenced empty lot.
function B.yard(parent: Instance, base: CFrame, w: number, dp: number, rng: Random, o: any)
	local m = Kit.model(parent, "Yard")
	local r = rng:NextNumber()
	local wall = WALLS[rng:NextInteger(1, #WALLS)]
	if o.use == "rural" or (o.use == "suburb" and r < 0.5) then
		-- orchard / kitchen garden behind a low wooden fence
		Kit.part(m, V3(w, 0.3, dp), base * CF(0, 0.15, 0), GRASS, M.Grass, { name = "LotPad", variant = "GD_Grass" })
		Kit.part(m, V3(w, 3.4, 0.5), base * CF(0, 1.7, -dp / 2 + 0.4), C.wood, M.WoodPlanks, { name = "Wall" })
		local n = math.clamp(math.floor(w * dp / 900), 1, 4)
		for _ = 1, n do
			S.tree(m, base * CF(rng:NextNumber(-w / 2 + 6, w / 2 - 6), 0.3, rng:NextNumber(-dp / 2 + 6, dp / 2 - 6)), rng, ({ "banana", "small", "palm", "bush" })[rng:NextInteger(1, 4)])
		end
	elseif r < 0.55 and w >= 22 and dp >= 22 then
		-- pay car park
		B.compound(m, base, w, dp, { wall = wall, prev = o.prev, endWall = o.endWall, ground = Color3.fromRGB(104, 106, 110), groundMat = M.Asphalt, groundVariant = "GD_AsphaltWorn" })
		local bays = math.floor((w - 4) / 9)
		for i = 0, bays do
			Kit.part(m, V3(0.4, 0.05, math.min(14, dp - 8)), base * CF(-(bays * 9) / 2 + i * 9, 0.33, dp / 2 - 9), C.line, M.SmoothPlastic, { decor = true })
		end
		local sign = Kit.part(m, V3(6, 3, 0.4), base * CF(-(o.prev or -1) * (w / 2 - 4), 9, -dp / 2 + 1), Color3.fromRGB(30, 90, 170), M.SmoothPlastic, { decor = true })
		Kit.part(m, V3(0.5, 9, 0.5), base * CF(-(o.prev or -1) * (w / 2 - 4), 4.5, -dp / 2 + 1), C.metalDark, M.Metal, { decor = true })
		Kit.sign(sign, "ที่จอดรถ", { sub = "PARKING", maxDistance = 200 })
	else
		-- fenced lot waiting for a building: bare ground, a wall, weeds
		B.compound(m, base, w, dp, { wall = wall, prev = o.prev, endWall = o.endWall, front = w >= 20, gate = 10, gateX = 0, ground = DIRT, groundMat = M.Ground })
		if w >= 16 and dp >= 16 and rng:NextNumber() < 0.6 then
			S.tree(m, base * CF(rng:NextNumber(-w / 4, w / 4), 0.3, rng:NextNumber(-dp / 4, dp / 4)), rng, rng:NextNumber() < 0.5 and "bush" or "banana")
		end
	end
	return m
end

local CROPS = {
	{ Color3.fromRGB(128, 170, 76), Color3.fromRGB(108, 150, 66), M.Grass }, -- rice
	{ Color3.fromRGB(96, 132, 62), Color3.fromRGB(132, 104, 78), M.Grass }, -- cassava rows on red soil
	{ Color3.fromRGB(150, 168, 84), Color3.fromRGB(124, 146, 70), M.Grass }, -- sugar cane
	{ Color3.fromRGB(146, 118, 90), Color3.fromRGB(122, 96, 72), M.Ground }, -- ploughed, waiting for rain
}

-- Farmland: a field with crop rows and an earth bund along the road. Rice paddies (2026-11-18) are
-- ringed with bunds (คันนา) on every side and often have a sugar palm or two standing on a bund, the
-- picture of the Isan countryside; other fields sometimes have a dirt track down one side.
local BUND = Color3.fromRGB(132, 110, 84)
function B.field(parent: Instance, base: CFrame, w: number, dp: number, rng: Random, o: any)
	local m = Kit.model(parent, "Field")
	local ci = rng:NextInteger(1, #CROPS)
	local crop = CROPS[ci]
	Kit.part(m, V3(w, 0.3, dp), base * CF(0, 0.15, 0), crop[1], crop[3], { name = "Field", decor = true, variant = crop[3] == M.Grass and "GD_Grass" or nil })
	local rows = math.clamp(math.floor(dp / 9), 2, 9)
	for i = 1, rows do
		Kit.part(m, V3(w - 3, 0.5, 2.2), base * CF(0, 0.4, -dp / 2 + dp * (i - 0.5) / rows), crop[2], crop[3], { decor = true })
	end
	Kit.part(m, V3(w, 1.1, 1.8), base * CF(0, 0.55, -dp / 2 + 0.9), BUND, M.Ground, { name = "Bund" })
	if ci == 1 then
		-- paddy: bunds on the other three sides, and a sugar palm on one of them now and then
		Kit.part(m, V3(w, 0.9, 1.4), base * CF(0, 0.45, dp / 2 - 0.7), BUND, M.Ground, { decor = true })
		for _, sx in ipairs({ -1, 1 }) do
			Kit.part(m, V3(1.4, 0.9, dp - 2), base * CF(sx * (w / 2 - 0.7), 0.45, 0), BUND, M.Ground, { decor = true })
		end
		if dp > 40 then -- a cross bund splits a big paddy in two
			Kit.part(m, V3(w - 2, 0.8, 1.2), base * CF(0, 0.4, 0), BUND, M.Ground, { decor = true })
		end
		local pr = rng:NextNumber()
		if pr < 0.42 then
			S.tree(m, base * CF(rng:NextNumber(-w / 2 + 2, w / 2 - 2), 0.9, dp / 2 - 0.7), rng, "sugarpalm")
			if pr < 0.14 then S.tree(m, base * CF((rng:NextNumber() < 0.5 and -1 or 1) * (w / 2 - 0.7), 0.9, rng:NextNumber(-dp / 3, dp / 3)), rng, "sugarpalm") end
		end
	elseif rng:NextNumber() < 0.3 and w > 30 then
		-- a dirt track along one side, the way the tractor goes
		local sx = rng:NextNumber() < 0.5 and -1 or 1
		Kit.part(m, V3(5, 0.36, dp - 2), base * CF(sx * (w / 2 - 2.5), 0.18, 1), Color3.fromRGB(164, 128, 92), M.Ground, { decor = true, name = "Track" })
	end
	if rng:NextNumber() < 0.12 and w > 40 and dp > 40 then
		-- field shelter
		local hb = base * CF(w / 4, 0.3, 0)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do Kit.part(m, V3(0.6, 8, 0.6), hb * CF(sx * 4, 4, sz * 3.4), C.woodDark, M.Wood, { decor = true }) end
		end
		Kit.part(m, V3(9.4, 0.5, 8), hb * CF(0, 3.2, 0), C.wood, M.WoodPlanks)
		Kit.gable(m, hb, 11, 9.6, 2.6, 8, Color3.fromRGB(150, 130, 90), M.CorrodedMetal)
	end
	return m
end

-- Isan farmhouse on stilts in a dirt yard with a wooden fence.
function B.farmstead(parent: Instance, base: CFrame, w: number, dp: number, rng: Random, o: any)
	local m = Kit.model(parent, "Farmstead")
	Kit.part(m, V3(w, 0.3, dp), base * CF(0, 0.15, 0), DIRT, M.Ground, { name = "LotPad" })
	local gap = 12
	local lw = (w - gap) / 2
	for _, sx in ipairs({ -1, 1 }) do
		Kit.part(m, V3(lw, 3.6, 0.5), base * CF(sx * (gap / 2 + lw / 2), 1.8, -dp / 2 + 0.4), C.wood, M.WoodPlanks, { name = "Wall" })
	end
	Kit.part(m, V3(0.5, 3.6, dp - 0.6), base * CF((o.prev or -1) * (w / 2 - 0.3), 1.8, 0), C.wood, M.WoodPlanks, { name = "Wall" })
	Kit.part(m, V3(w, 3.6, 0.5), base * CF(0, 1.8, dp / 2 - 0.3), C.wood, M.WoodPlanks, { name = "Wall" })
	S.farmhouse(m, base * CF(0, 0.3, dp / 2 - 18), w, 30, rng)
	return m
end

-- Shophouse terrace. detail: 2 = full facades, 1 = lighter facades, 0 = simple terrace.
-- Returns the building frame (the terrace is 34 deep and stands at the street front of the property).
function B.shophouses(parent: Instance, base: CFrame, w: number, dp: number, rng: Random, o: any): CFrame
	local bd = math.min(34, dp)
	local bb = base * CF(0, 0, -dp / 2 + bd / 2)
	Kit.part(parent, V3(w, 0.3, dp), base * CF(0, 0.15, 0), C.concrete, M.Concrete, { name = "LotPad", variant = "GD_ConcreteFloor" })
	local info = { shops = o.shop and { o.shop } or nil, lite = o.detail == 1, floors = o.floors }
	if o.detail > 0 then
		Shophouse.row(parent, bb * CF(0, 0.3, 0), w, bd, rng, info)
	else
		S.row(parent, bb * CF(0, 0.3, 0), w, bd, rng, info)
	end
	if dp - bd > 5 then
		-- service yard behind the terrace
		Kit.part(parent, V3(w, WALL_H, 0.8), base * CF(0, WALL_H / 2, dp / 2 - 0.4), WALLS[2], M.Concrete, { name = "Wall", variant = "GD_Plaster" })
		Kit.part(parent, V3(0.8, WALL_H, dp - bd), base * CF((o.prev or -1) * (w / 2 - 0.4), WALL_H / 2, dp / 2 - (dp - bd) / 2), WALLS[2], M.Concrete, { name = "Wall", variant = "GD_Plaster" })
	end
	return bb
end

return B
