-- Detailed Thai shophouse terraces (ตึกแถว) at real scale: 4 m units, ~3.2 m floors.
-- Each unit gets its own wall colour, a ground-floor shop (roller shutter, glass front or open
-- stall), a sign, an awning, and upper floors with framed windows or balconies, air-con units,
-- drain pipes, ledges, parapet and roof tanks. Local frame: front = -Z, base at ground level.
local Kit = require(script.Parent.Kit)
local Assets = require(script.Parent.Assets)
local M = Kit.M
local C = Kit.COLORS
local V3 = Vector3.new
local CF = CFrame.new
local rad = math.rad

local Shop = {}

-- Real Isan shophouse fronts (2026-11-16 realism pass): mostly cream, beige and bare grey concrete,
-- some faded ochre / salmon / mint paint; none of the cold blue-whites the old list had.
local WALLS = {
	Color3.fromRGB(230, 220, 198), Color3.fromRGB(218, 204, 178), Color3.fromRGB(206, 202, 192), Color3.fromRGB(226, 208, 188),
	Color3.fromRGB(196, 192, 184), Color3.fromRGB(234, 226, 210), Color3.fromRGB(222, 200, 166), Color3.fromRGB(212, 208, 198),
	Color3.fromRGB(232, 216, 178), Color3.fromRGB(196, 208, 194), Color3.fromRGB(224, 194, 176), Color3.fromRGB(186, 184, 178),
}
local SHUTTERS = {
	Color3.fromRGB(176, 176, 172), Color3.fromRGB(150, 152, 150), Color3.fromRGB(126, 142, 156), Color3.fromRGB(128, 150, 132),
	Color3.fromRGB(188, 178, 152), Color3.fromRGB(140, 140, 138),
}
local SIGN_BG = {
	Color3.fromRGB(196, 40, 40), Color3.fromRGB(28, 90, 170), Color3.fromRGB(240, 196, 40), Color3.fromRGB(30, 130, 80),
	Color3.fromRGB(236, 236, 232), Color3.fromRGB(230, 110, 30), Color3.fromRGB(110, 60, 150), Color3.fromRGB(30, 30, 34),
}
local AWN = {
	Color3.fromRGB(60, 110, 80), Color3.fromRGB(150, 60, 50), Color3.fromRGB(70, 100, 150), Color3.fromRGB(190, 190, 186),
	Color3.fromRGB(200, 150, 60), Color3.fromRGB(110, 110, 114),
}
local NAMES = {
	{ "ร้านทองเยาวราช", "GOLD SHOP" }, { "ตัดผมชาย", "BARBER" }, { "ซ่อมมือถือ", "PHONE REPAIR" }, { "ร้านขายยา", "PHARMACY" },
	{ "ซัก อบ รีด", "LAUNDRY" }, { "คลินิกทันตกรรม", "DENTAL CLINIC" }, { "เครื่องเขียน", "STATIONERY" }, { "อะไหล่ยนต์", "AUTO PARTS" },
	{ "ร้านดอกไม้", "FLORIST" }, { "ร้านแว่นตา", "OPTICIAN" }, { "เสื้อผ้าแฟชั่น", "FASHION" }, { "ร้านหนังสือ", "BOOKS" },
	{ "นวดแผนไทย", "THAI MASSAGE" }, { "วัสดุก่อสร้าง", "HARDWARE" }, { "ถ่ายเอกสาร", "COPY & PRINT" }, { "เบเกอรี่", "BAKERY" },
	{ "ผ้าไหมไทย", "THAI SILK" }, { "ร้านจักรยาน", "BICYCLES" }, { "ของชำ", "GROCERY" }, { "คอมพิวเตอร์", "COMPUTERS" },
	{ "ข้าวต้มโต้รุ่ง", "RICE SOUP" }, { "ก๋วยเตี๋ยวไก่", "CHICKEN NOODLES" }, { "อาหารตามสั่ง", "MADE TO ORDER" }, { "กาแฟโบราณ", "THAI COFFEE" },
	{ "ร้านสังฆภัณฑ์", "TEMPLE SUPPLIES" }, { "ร้านกาแฟสด", "FRESH COFFEE" }, { "ร้านอัดรูป", "PHOTO LAB" }, { "ยางรถยนต์", "TYRES" },
	{ "ร้านเฟอร์นิเจอร์", "FURNITURE" }, { "อุปกรณ์การเกษตร", "FARM SUPPLY" },
}
Shop.NAMES = NAMES

local WHITE = Color3.fromRGB(236, 238, 240)
local ALU = Color3.fromRGB(170, 176, 182)
local DARKGLASS = Color3.fromRGB(40, 44, 42) -- tinted grey-green, as Thai shophouse glass is
local PANE = Enum.Material.SmoothPlastic -- dark, slightly glossy: real windows look dark by day

local acCount = 0
-- Wall-mounted condenser: back against the wall at local +Z, fans toward the street.
local function aircon(parent: Instance, cf: CFrame, deco)
	acCount += 1 -- the detailed mesh on every third unit keeps the triangle count sensible
	if acCount % 3 == 0 and Assets.place(parent, "aircon", cf * CF(0, -0.95, 0), 0.45) then return end
	Kit.part(parent, V3(2.8, 1.9, 1.3), cf, Color3.fromRGB(236, 238, 240), M.SmoothPlastic, deco)
end

local function shade(c: Color3, k: number): Color3
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

local function signText(part: BasePart, thai: string, en: string, bg: Color3, glow: boolean)
	local dark = (bg.R * 0.3 + bg.G * 0.59 + bg.B * 0.11) > 0.62
	Kit.sign(part, thai, { sub = en, bg = bg, color = dark and Color3.fromRGB(30, 30, 34) or Color3.new(1, 1, 1), light = glow, maxDistance = glow and 420 or 260 })
	if glow then Kit.nightGlow(part) end
end

-- info: { floors?, shops = { [slot] = { name, thai, color } }?, lite = boolean? }
-- Returns the x offset of each unit's door (slot order, left to right).
function Shop.row(parent: Instance, base: CFrame, w: number, d: number, rng: Random, info: any)
	local m = Kit.model(parent, "Shophouses")
	local n = math.max(1, math.floor(w / 15.5 + 0.5))
	local uw = w / n
	local floors = info.floors or rng:NextInteger(2, 4)
	local gh, fh = 12.5, 11.5
	local h = gh + (floors - 1) * fh
	local depth = d - 3
	local fz = -d / 2 + 2 -- facade plane
	local lite = info.lite == true
	local deco = { decor = true }
	local rowWall = WALLS[rng:NextInteger(1, #WALLS)]
	local doors = {}

	for i = 1, n do
		local x = -w / 2 + uw * (i - 0.5)
		doors[i] = x
		local wall = rng:NextNumber() < 0.55 and rowWall or WALLS[rng:NextInteger(1, #WALLS)]
		local uh = h + ((not lite and rng:NextNumber() < 0.18) and 3 or 0) -- a few units stand a little taller
		Kit.part(m, V3(uw - 0.06, uh, depth), base * CF(x, uh / 2, 1.5), wall, M.Concrete, { variant = "GD_PaintedWall" })
		-- pilaster + drain pipe on the unit's left edge
		Kit.part(m, V3(1, uh, 0.9), base * CF(x - uw / 2 + 0.5, uh / 2, fz - 0.35), shade(wall, 0.93), M.Concrete, { decor = true, variant = "GD_ConcreteWall" })
		if not lite then
			Kit.part(m, V3(0.36, uh - 2, 0.36), base * CF(x - uw / 2 + 1.4, uh / 2, fz - 0.3), Color3.fromRGB(150, 156, 164), M.Metal, deco)
		end

		-- ground floor ------------------------------------------------------------------------
		local shop = info.shops and info.shops[i]
		local roll = rng:NextNumber()
		local kind = shop and (roll < 0.55 and "glass" or "open") or (roll < 0.42 and "shutter" or (roll < 0.78 and "glass" or "open"))
		local sw = uw - 2
		if kind == "shutter" then
			Kit.part(m, V3(sw, 9.4, 0.3), base * CF(x, 4.9, fz - 0.12), SHUTTERS[rng:NextInteger(1, #SHUTTERS)], M.Metal, { decor = true, variant = "GD_Shutter" })
			Kit.part(m, V3(sw + 0.4, 1, 0.9), base * CF(x, 10, fz - 0.35), ALU, M.Metal, deco)
		elseif kind == "glass" then
			local g = Kit.part(m, V3(sw, 9, 0.2), base * CF(x, 4.7, fz - 0.1), DARKGLASS, PANE, { decor = true, reflectance = 0.1 })
			if rng:NextNumber() < 0.7 then Kit.nightGlow(g) end
			Kit.part(m, V3(sw + 0.3, 0.5, 0.4), base * CF(x, 9.45, fz - 0.2), ALU, M.Metal, deco)
			if not lite then
				Kit.part(m, V3(0.3, 9, 0.4), base * CF(x - sw * 0.18, 4.7, fz - 0.2), ALU, M.Metal, deco)
				Kit.part(m, V3(0.3, 9, 0.4), base * CF(x + sw * 0.5, 4.7, fz - 0.2), ALU, M.Metal, deco)
				Kit.part(m, V3(sw * 0.6, 0.9, 0.25), base * CF(x + sw * 0.16, 0.65, fz - 0.16), shade(wall, 0.8), M.Concrete, deco)
			end
		else
			-- open-front shop: you can see into a lit interior
			Kit.part(m, V3(sw, 9.4, 0.2), base * CF(x, 4.9, fz + 0.5), Color3.fromRGB(46, 42, 38), M.SmoothPlastic, deco)
			if not lite then
				Kit.part(m, V3(sw * 0.55, 3.3, 1.6), base * CF(x - sw * 0.16, 1.9, fz - 0.2), Color3.fromRGB(186, 190, 196), M.Metal)
				Kit.part(m, V3(sw * 0.5, 4.4, 1.2), base * CF(x + sw * 0.2, 2.5, fz + 0.2), ({ Color3.fromRGB(150, 110, 70), Color3.fromRGB(190, 60, 50), Color3.fromRGB(60, 110, 160) })[rng:NextInteger(1, 3)], M.SmoothPlastic, deco)
			end
			local tube = Kit.part(m, V3(sw * 0.7, 0.25, 0.25), base * CF(x, 9.2, fz), Color3.fromRGB(244, 248, 255), M.SmoothPlastic, deco)
			Kit.nightGlow(tube)
			if not lite then Kit.nightLight(tube, 22, Color3.fromRGB(235, 242, 255), 1.3) end
		end
		-- fascia sign
		local hasSign = shop ~= nil or rng:NextNumber() < 0.8
		if hasSign then
			local pair = NAMES[rng:NextInteger(1, #NAMES)]
			local bg = shop and shop.color or SIGN_BG[rng:NextInteger(1, #SIGN_BG)]
			local board = Kit.part(m, V3(uw - 1.4, 2.6, 0.45), base * CF(x, 11.25, fz - 0.6), bg, M.SmoothPlastic, deco)
			signText(board, shop and shop.thai or pair[1], shop and shop.name or pair[2], bg, shop ~= nil or rng:NextNumber() < 0.35)
			-- some shops also hang a vertical blade sign over the pavement
			if not lite and (shop or rng:NextNumber() < 0.22) and floors >= 2 then
				local blade = Kit.part(m, V3(0.4, 7.5, 2.6), base * CF(x + uw / 2 - 1.2, gh + 5.5, fz - 2), bg, M.SmoothPlastic, deco)
				local dark = (bg.R * 0.3 + bg.G * 0.59 + bg.B * 0.11) > 0.62
				for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
					Kit.sign(blade, shop and shop.name or pair[2], { face = face, bg = bg, color = dark and Color3.fromRGB(30, 30, 34) or Color3.new(1, 1, 1), maxDistance = 220 })
				end
			end
		end
		-- awning over the pavement
		if rng:NextNumber() < (shop and 0.9 or 0.6) then
			local col = AWN[rng:NextInteger(1, #AWN)]
			local metal = rng:NextNumber() < 0.6
			Kit.part(m, V3(uw - 0.5, 0.2, 5.6), base * CF(x, 9.55, fz - 3) * CFrame.Angles(rad(-10), 0, 0), col, metal and M.CorrodedMetal or M.Fabric, { decor = true, shadow = true })
			if not lite then
				for _, sx in ipairs({ -1, 1 }) do
					Kit.part(m, V3(0.15, 0.15, 5.2), base * CF(x + sx * (uw / 2 - 0.9), 8.7, fz - 2.7) * CFrame.Angles(rad(12), 0, 0), Color3.fromRGB(90, 94, 100), M.Metal, deco)
				end
			end
		end

		-- upper floors -----------------------------------------------------------------------
		local balcony = rng:NextNumber() < 0.45
		for f = 2, floors do
			local y0 = gh + (f - 2) * fh
			if lite then
				Kit.facade(m, base * CF(x, y0 + fh / 2 + 0.2, fz - 0.1), uw - 1.1, fh - 0.5, Kit.FACADE.town, 1, 1, wall, rng:NextNumber() < 0.5)
			elseif balcony then
				local door = Kit.part(m, V3(uw - 4.5, 7.4, 0.2), base * CF(x, y0 + 4.2, fz - 0.06), DARKGLASS, PANE, { decor = true, reflectance = 0.1 })
				if rng:NextNumber() < 0.5 then Kit.nightGlow(door) end
				Kit.part(m, V3(uw - 4.2, 0.4, 0.3), base * CF(x, y0 + 8.1, fz - 0.12), WHITE, M.Metal, deco)
				Kit.part(m, V3(uw - 1.2, 0.45, 3.4), base * CF(x, y0 + 0.25, fz - 1.7), shade(wall, 0.88), M.Concrete, { decor = true, variant = "GD_ConcreteWall" })
				Kit.part(m, V3(uw - 1.3, 2.9, 0.12), base * CF(x, y0 + 1.9, fz - 3.3), Color3.fromRGB(60, 64, 70), M.Metal, { decor = true, transparency = 0.45 })
				Kit.part(m, V3(uw - 1.1, 0.25, 0.35), base * CF(x, y0 + 3.4, fz - 3.3), Color3.fromRGB(70, 74, 80), M.Metal, deco)
				if rng:NextNumber() < 0.55 then
					aircon(m, base * CF(x + uw / 2 - 2.6, y0 + 1.45, fz - 1), deco)
				end
				if rng:NextNumber() < 0.3 then
					-- potted plant on the balcony
					Kit.cyl(m, 1.1, 1, base * CF(x - uw / 2 + 2.4, y0 + 0.95, fz - 2.5), Color3.fromRGB(170, 96, 66), M.Slate, { decor = true, variant = "GD_ConcreteWall" })
					Kit.ball(m, 1.9, base * CF(x - uw / 2 + 2.4, y0 + 2.3, fz - 2.5), C.leafLight, M.LeafyGrass, deco)
				end
			else
				for _, sx in ipairs({ -1, 1 }) do
					local wx = x + sx * uw * 0.23
					Kit.part(m, V3(4.4, 5.6, 0.3), base * CF(wx, y0 + 6.1, fz - 0.1), WHITE, M.Metal, deco)
					local g = Kit.part(m, V3(3.8, 5, 0.2), base * CF(wx, y0 + 6.1, fz - 0.24), DARKGLASS, PANE, { decor = true, reflectance = 0.1 })
					if rng:NextNumber() < 0.45 then Kit.nightGlow(g) end
				end
				Kit.part(m, V3(uw - 1.6, 0.3, 0.9), base * CF(x, y0 + 3.1, fz - 0.4), shade(wall, 0.9), M.Concrete, { decor = true, variant = "GD_ConcreteWall" })
				if rng:NextNumber() < 0.6 then
					local ax = x + (rng:NextNumber() < 0.5 and 1 or -1) * uw * 0.23
					aircon(m, base * CF(ax, y0 + 1.7, fz - 0.9), deco)
					Kit.part(m, V3(3, 0.2, 1.5), base * CF(ax, y0 + 0.65, fz - 0.9), Color3.fromRGB(90, 94, 100), M.Metal, deco)
				end
			end
		end
		-- roof: parapet, tanks
		Kit.part(m, V3(uw - 0.06, 1.3, 0.6), base * CF(x, uh + 0.65, fz + 0.3), shade(wall, 0.85), M.Concrete, { decor = true, variant = "GD_ConcreteWall" })
		if not lite and rng:NextNumber() < 0.4 then
			local tx = x + rng:NextNumber(-uw / 4, uw / 4)
			Kit.cyl(m, 3.4, 4.6, base * CF(tx, uh + 3.4, 5), Color3.fromRGB(196, 202, 208), M.Metal, { decor = true, reflectance = 0.25 })
			Kit.part(m, V3(3.6, 1.1, 3.6), base * CF(tx, uh + 0.55, 5), Color3.fromRGB(110, 114, 120), M.Metal, deco)
		end
	end
	-- closing pilaster and floor ledges for the whole terrace
	Kit.part(m, V3(1, h, 0.9), base * CF(w / 2 - 0.5, h / 2, fz - 0.35), shade(rowWall, 0.93), M.Concrete, { decor = true, variant = "GD_ConcreteWall" })
	for f = 2, floors do
		Kit.part(m, V3(w, 0.5, 0.8), base * CF(0, gh + (f - 2) * fh - 0.1, fz - 0.35), shade(rowWall, 0.82), M.Concrete, { decor = true, variant = "GD_ConcreteWall" })
	end
	Kit.part(m, V3(w, 0.5, depth), base * CF(0, h + 0.2, 1.5), Color3.fromRGB(150, 150, 150), M.Concrete, { decor = true, variant = "GD_ConcreteFloor" })
	return doors
end

return Shop
