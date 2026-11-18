-- Generic street-front buildings and street furniture, all in a local frame:
-- base = lot centre at ground level, front = local -Z, x across the front, y up.
local Kit = require(script.Parent.Kit)
local Assets = require(script.Parent.Assets)
local Solid = require(script.Parent.Solid)
local M = Kit.M
local C = Kit.COLORS
local V3 = Vector3.new
local CF = CFrame.new
local rad = math.rad

local S = {}

S.SHOP_NAMES = {
	{ "ร้านทองเยาวราช", "Gold Shop" }, { "ร้านตัดผมชาย", "Barber" }, { "ซ่อมมือถือ", "Phone Repair" }, { "ร้านขายยา", "Pharmacy" },
	{ "ซักอบรีด", "Laundry" }, { "คลินิกทันตกรรม", "Dental Clinic" }, { "ร้านเครื่องเขียน", "Stationery" }, { "อะไหล่ยนต์", "Auto Parts" },
	{ "ร้านดอกไม้", "Florist" }, { "ร้านแว่นตา", "Optician" }, { "เสื้อผ้าแฟชั่น", "Fashion" }, { "ร้านหนังสือ", "Bookstore" },
	{ "นวดแผนไทย", "Thai Massage" }, { "ร้านวัสดุก่อสร้าง", "Hardware" }, { "ร้านถ่ายเอกสาร", "Copy Shop" }, { "ร้านเบเกอรี่", "Bakery" },
	{ "ร้านผ้าไหม", "Thai Silk" }, { "ร้านจักรยาน", "Bike Shop" }, { "ร้านของชำ", "Grocery" }, { "ร้านคอมพิวเตอร์", "Computers" },
}
S.DORM_NAMES = { "หอพักสุขใจ", "หอพักมอดินแดง", "หอพักศรีกังสดาล", "ร่มเย็น แมนชั่น", "หอพักบ้านเพื่อน", "KK Place", "U-Home", "หอพักนักศึกษา" }

local function darker(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

---------------------------------------------------------------------------------------------------
-- buildings
---------------------------------------------------------------------------------------------------
-- info: { floors?, name?, thai?, signColor?, kind? }
function S.shophouse(parent: Instance, base: CFrame, w: number, d: number, rng: Random, info: any)
	local floors = info.floors or rng:NextInteger(2, 4)
	local fh = 10
	local h = floors * fh
	local col = Kit.PASTEL[rng:NextInteger(1, #Kit.PASTEL)]
	local m = Kit.model(parent, info.kind or "Shop")
	local fz = -d / 2 + 2
	Kit.part(m, V3(w - 0.5, h, d - 3), base * CF(0, h / 2, 1.5), col, M.Concrete)
	local front = Kit.part(m, V3(w - 4, 7, 0.4), base * CF(0, 3.9, fz - 0.05), C.glassDark, M.Glass, { decor = true, reflectance = 0.15 })
	Kit.nightGlow(front)
	local awn = info.signColor or Kit.AWNING[rng:NextInteger(1, #Kit.AWNING)]
	Kit.part(m, V3(w - 1, 0.35, 5.2), base * CF(0, 8.3, fz - 2.5) * CFrame.Angles(rad(-9), 0, 0), awn, M.Fabric, { decor = true, shadow = true })
	if info.name or rng:NextNumber() < 0.7 then
		local pair = S.SHOP_NAMES[rng:NextInteger(1, #S.SHOP_NAMES)]
		local thai, en = info.thai or pair[1], info.name or pair[2]
		local sign = Kit.part(m, V3(w - 3, 2.8, 0.5), base * CF(0, 10.6, fz - 0.4), info.signColor or darker(awn, 0.8), M.SmoothPlastic, { decor = true })
		Kit.sign(sign, thai, { sub = en, light = info.name ~= nil })
		if info.name then Kit.nightGlow(sign) end
	end
	for f = 2, floors do
		local win = Kit.part(m, V3(w - 5, 4.2, 0.3), base * CF(0, (f - 1) * fh + 5.4, fz - 0.05), C.glass, M.Glass, { decor = true, reflectance = 0.1 })
		if rng:NextNumber() < 0.55 then Kit.nightGlow(win) end
	end
	Kit.part(m, V3(w - 0.1, 0.9, d - 2.6), base * CF(0, h + 0.45, 1.5), darker(col, 0.72), M.Concrete, { decor = true })
	if rng:NextNumber() < 0.5 then
		Kit.cyl(m, 3, 3.4, base * CF(rng:NextNumber(-w / 4, w / 4), h + 2.6, 4), Color3.fromRGB(70, 110, 170), M.SmoothPlastic, { decor = true })
	end
	return m
end

-- A terrace of shophouses (ตึกแถว) as one building: far fewer parts than separate units.
-- info.shops = { { name, thai, color } } puts named shops in the first slots (slot 1 = left end).
function S.row(parent: Instance, base: CFrame, w: number, d: number, rng: Random, info: any)
	local m = Kit.model(parent, "Row")
	local floors = info.floors or rng:NextInteger(2, 4)
	local fh = 10
	local h = floors * fh
	local col = Kit.PASTEL[rng:NextInteger(1, #Kit.PASTEL)]
	local fz = -d / 2 + 2
	Kit.part(m, V3(w - 0.6, h, d - 3), base * CF(0, h / 2, 1.5), col, M.Concrete)
	Kit.part(m, V3(w, 0.9, d - 2.4), base * CF(0, h + 0.45, 1.5), darker(col, 0.72), M.Concrete, { decor = true })
	local front = Kit.part(m, V3(w - 3, 7, 0.4), base * CF(0, 3.9, fz - 0.05), C.glassDark, M.Glass, { decor = true, reflectance = 0.15 })
	Kit.nightGlow(front)
	local halves = w >= 60 and 2 or 1
	local hw = w / halves
	for i = 1, halves do
		local x = -w / 2 + hw * (i - 0.5)
		local shop = info.shops and info.shops[i]
		local awn = shop and shop.color or Kit.AWNING[rng:NextInteger(1, #Kit.AWNING)]
		Kit.part(m, V3(hw - 1, 0.35, 5.2), base * CF(x, 8.3, fz - 2.5) * CFrame.Angles(rad(-9), 0, 0), awn, M.Fabric, { decor = true, shadow = true })
		if shop or rng:NextNumber() < 0.75 then
			local pair = S.SHOP_NAMES[rng:NextInteger(1, #S.SHOP_NAMES)]
			local sw = math.min(hw - 4, 30)
			local sign = Kit.part(m, V3(sw, 2.8, 0.5), base * CF(x, 10.6, fz - 0.4), shop and shop.color or darker(awn, 0.8), M.SmoothPlastic, { decor = true })
			Kit.sign(sign, shop and shop.thai or pair[1], { sub = shop and shop.name or pair[2], light = shop ~= nil })
			if shop then Kit.nightGlow(sign) end
		end
	end
	local units = math.max(1, math.floor(w / 15.5 + 0.5))
	for f = 2, floors do
		Kit.facade(m, base * CF(0, (f - 1) * fh + fh / 2, fz - 0.1), w - 0.6, fh, Kit.FACADE.town, units, 1, col, rng:NextNumber() < 0.6)
	end
	if rng:NextNumber() < 0.4 then
		Kit.cyl(m, 3, 3.4, base * CF(rng:NextNumber(-w / 3, w / 3), h + 2.6, 4), Color3.fromRGB(70, 110, 170), M.SmoothPlastic, { decor = true })
	end
	return m
end

-- Roadside showroom / big-box store for the highway strip.
function S.bigbox(parent: Instance, base: CFrame, w: number, d: number, rng: Random)
	local m = Kit.model(parent, "BigBox")
	local h = rng:NextInteger(16, 24)
	local col = ({ C.white, Color3.fromRGB(226, 228, 232), Color3.fromRGB(236, 226, 206) })[rng:NextInteger(1, 3)]
	local accent = Kit.AWNING[rng:NextInteger(1, #Kit.AWNING)]
	Kit.part(m, V3(w - 6, h, d - 16), base * CF(0, h / 2, 7), col, M.Concrete)
	local g = Kit.part(m, V3(w - 20, h * 0.5, 0.4), base * CF(0, h * 0.3, 7 - (d - 16) / 2 - 0.2), C.glass, M.Glass, { decor = true, reflectance = 0.2 })
	Kit.nightGlow(g)
	Kit.part(m, V3(w - 5, 2.4, d - 15), base * CF(0, h + 1.2, 7), accent, M.Metal, { decor = true })
	local pair = S.SHOP_NAMES[rng:NextInteger(1, #S.SHOP_NAMES)]
	local sign = Kit.part(m, V3(w * 0.5, 4, 0.5), base * CF(0, h - 3, 7 - (d - 16) / 2 - 0.5), accent, M.SmoothPlastic, { decor = true })
	Kit.sign(sign, pair[1], { sub = pair[2], light = true, maxDistance = 420 })
	Kit.nightGlow(sign)
	Kit.part(m, V3(w, 0.3, d), base * CF(0, 0.15, 0), Color3.fromRGB(150, 152, 156), M.Concrete, { name = "LotPad" })
	return m
end

function S.house(parent: Instance, base: CFrame, w: number, d: number, rng: Random)
	local m = Kit.model(parent, "House")
	local bw, bd = w - 12, d - 12
	local col = Kit.PASTEL[rng:NextInteger(1, #Kit.PASTEL)]
	local roof = ({ C.roofTile, C.roofBlue, C.roofGrey, Color3.fromRGB(150, 70, 60) })[rng:NextInteger(1, 4)]
	local two = rng:NextNumber() < 0.4
	local h = two and 17 or 9.5
	local fz = -bd / 2 + 2
	Kit.part(m, V3(bw, h, bd), base * CF(0, h / 2, 2), col, M.Concrete)
	Kit.gable(m, base * CF(0, 0, 2), bw + 3, bd + 3, 5, h, roof, M.Slate)
	Kit.part(m, V3(3.2, 6.4, 0.3), base * CF(-bw / 4, 3.2, fz - 0.05), C.woodDark, M.Wood, { decor = true })
	local win = Kit.part(m, V3(5.5, 3.6, 0.3), base * CF(bw / 4, 5, fz - 0.05), C.glass, M.Glass, { decor = true })
	if rng:NextNumber() < 0.6 then Kit.nightGlow(win) end
	if two then
		local w2 = Kit.part(m, V3(bw - 6, 3.4, 0.3), base * CF(0, 13, fz - 0.05), C.glass, M.Glass, { decor = true })
		if rng:NextNumber() < 0.5 then Kit.nightGlow(w2) end
	end
	-- porch roof and low front wall with a gate gap
	Kit.part(m, V3(bw * 0.6, 0.4, 4), base * CF(-bw / 6, 7.4, fz - 2), darker(roof, 0.9), M.Slate, { decor = true, shadow = true })
	local wallCol = Color3.fromRGB(226, 224, 216)
	Kit.part(m, V3(w * 0.5, 2.6, 0.7), base * CF(w * 0.22, 1.3, -d / 2 + 1), wallCol, M.Concrete)
	Kit.part(m, V3(w * 0.2, 2.6, 0.7), base * CF(-w * 0.38, 1.3, -d / 2 + 1), wallCol, M.Concrete)
	if rng:NextNumber() < 0.7 then
		S.tree(m, base * CF(w / 2 - 5, 0, -d / 2 + 6), rng, rng:NextNumber() < 0.4 and "banana" or "small")
	end
	return m
end

function S.dorm(parent: Instance, base: CFrame, w: number, d: number, rng: Random)
	local m = Kit.model(parent, "Dorm")
	local floors = rng:NextInteger(3, 5)
	local fh = 9
	local h = floors * fh
	local col = Kit.PASTEL[rng:NextInteger(1, #Kit.PASTEL)]
	local fz = -d / 2 + 3
	Kit.part(m, V3(w - 1, h, d - 5), base * CF(0, h / 2, 2.5), col, M.Concrete)
	local lobby = Kit.part(m, V3(w - 6, 6.4, 0.4), base * CF(0, 3.4, fz - 0.05), C.glassDark, M.Glass, { decor = true })
	Kit.nightGlow(lobby)
	for f = 2, floors do
		local y = (f - 1) * fh
		Kit.part(m, V3(w - 1, 0.4, 2.6), base * CF(0, y, fz - 1.3), darker(col, 0.8), M.Concrete, { decor = true })
		Kit.part(m, V3(w - 1.4, 2.6, 0.25), base * CF(0, y + 1.5, fz - 2.5), C.metalDark, M.Metal, { decor = true, transparency = 0.35 })
		local win = Kit.part(m, V3(w - 5, 4, 0.3), base * CF(0, y + 5, fz - 0.05), C.glass, M.Glass, { decor = true })
		if rng:NextNumber() < 0.6 then Kit.nightGlow(win) end
	end
	local sign = Kit.part(m, V3(w * 0.6, 2.6, 0.5), base * CF(0, 8.2, fz - 0.5), Color3.fromRGB(60, 90, 150), M.SmoothPlastic, { decor = true })
	Kit.sign(sign, S.DORM_NAMES[rng:NextInteger(1, #S.DORM_NAMES)], { sub = "Dormitory" })
	Kit.part(m, V3(w - 0.6, 0.9, d - 4.4), base * CF(0, h + 0.45, 2.5), darker(col, 0.7), M.Concrete, { decor = true })
	return m
end

-- Isan wooden house on stilts.
function S.farmhouse(parent: Instance, base: CFrame, w: number, d: number, rng: Random)
	local m = Kit.model(parent, "FarmHouse")
	local bw, bd = 20, 16
	local wood = rng:NextNumber() < 0.5 and C.wood or C.woodDark
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			Kit.part(m, V3(1, 7, 1), base * CF(sx * (bw / 2 - 1), 3.5, sz * (bd / 2 - 1)), C.woodDark, M.Wood)
		end
	end
	Kit.part(m, V3(bw + 2, 0.8, bd + 2), base * CF(0, 7.2, 0), C.woodDark, M.WoodPlanks)
	Kit.part(m, V3(bw, 8, bd), base * CF(0, 11.6, 0), wood, M.WoodPlanks)
	Kit.gable(m, base, bw + 4, bd + 4, 5, 15.6, rng:NextNumber() < 0.5 and Color3.fromRGB(150, 64, 54) or C.roofGrey, M.CorrodedMetal)
	local win = Kit.part(m, V3(4, 3, 0.3), base * CF(4, 12, -bd / 2 - 0.05), C.glassDark, M.Glass, { decor = true })
	if rng:NextNumber() < 0.5 then Kit.nightGlow(win) end
	-- stair
	Kit.wedge(m, V3(3.4, 7.2, 8), base * CF(-5, 3.6, -bd / 2 - 5) , C.wood, M.WoodPlanks)
	if rng:NextNumber() < 0.8 then S.tree(m, base * CF(w / 2 - 8, 0, 4), rng, "banana") end
	if rng:NextNumber() < 0.6 then S.tree(m, base * CF(-w / 2 + 8, 0, 6), rng, "rain") end
	return m
end

-- Taller block for the inside of city blocks (skyline, no entrance).
function S.tower(parent: Instance, base: CFrame, w: number, d: number, rng: Random, floors: number?)
	local m = Kit.model(parent, "Tower")
	local n = floors or rng:NextInteger(4, 9)
	local h = n * 10
	local col = Kit.PASTEL[rng:NextInteger(1, #Kit.PASTEL)]
	Kit.part(m, V3(w, h, d), base * CF(0, h / 2, 0), col, M.Concrete)
	for _, side in ipairs({ -1, 1 }) do
		local g = Kit.part(m, V3(w - 4, h - 12, 0.3), base * CF(0, h / 2 + 3, side * (d / 2 + 0.05)), C.glass, M.Glass, { decor = true, reflectance = 0.2 })
		if rng:NextNumber() < 0.7 then Kit.nightGlow(g) end
	end
	Kit.part(m, V3(w + 0.6, 1, d + 0.6), base * CF(0, h + 0.5, 0), darker(col, 0.7), M.Concrete, { decor = true })
	return m
end

---------------------------------------------------------------------------------------------------
-- street furniture and plants
---------------------------------------------------------------------------------------------------
-- What S.tree(kind) plants: species (Config/Plants kinds) with weights, size range, trunk collider width.
S.PLANTS = {
	rain = { { "rain", 1 }, scale = { 0.6, 0.82 }, trunk = 3.6 },
	small = { { "shade", 3 }, { "mango", 2 }, { "koon", 3 }, { "frangipani", 1 }, scale = { 0.6, 0.85 }, trunk = 2.4 },
	street = { { "koon", 4 }, { "shade", 3 }, { "mango", 2 }, { "rain", 1 }, scale = { 0.62, 0.8 }, trunk = 2.6 },
	koon = { { "koon", 1 }, scale = { 0.65, 0.9 }, trunk = 2.2 },
	mango = { { "mango", 1 }, scale = { 0.6, 0.85 }, trunk = 2.6 },
	frangipani = { { "frangipani", 1 }, scale = { 0.8, 1.1 }, trunk = 1.6 },
	palm = { { "coconut", 7 }, { "royal", 3 }, scale = { 0.8, 1.05 }, trunk = 1.6 },
	royal = { { "royal", 1 }, scale = { 0.85, 1.05 }, trunk = 1.8 },
	banana = { { "banana", 1 }, scale = { 0.8, 1.2 }, trunk = 0.9 },
	bush = { { "hedge", 3 }, { "bougainvillea", 2 }, scale = { 0.55, 0.9 } },
	flower = { { "bougainvillea", 1 }, scale = { 0.6, 0.95 } },
	grass = { { "grass", 1 }, scale = { 0.8, 1.5 } },
}
for _, plan in pairs(S.PLANTS) do
	local total = 0
	for _, it in ipairs(plan) do total += it[2] end
	plan.total = total
end
-- Sugar palm (ต้นตาล), the tree of the Isan rice fields (2026-11-18): a tall straight dark trunk and a
-- round crown of stiff fan leaves, a few dead brown fans hanging below. Part-built (no mesh yet).
function S.sugarPalm(parent: Instance, base: CFrame, rng: Random)
	local m = Kit.model(parent, "SugarPalm")
	local h = rng:NextNumber(40, 54)
	local bark = Color3.fromRGB(84, 74, 66)
	local flat = CFrame.new(base.Position) * CFrame.Angles(0, rad(rng:NextNumber(0, 360)), 0)
	local lean = CFrame.Angles(rad(rng:NextNumber(-2.5, 2.5)), 0, rad(rng:NextNumber(-2.5, 2.5)))
	local trunk = flat * lean
	Kit.cyl(m, 1.9, h * 0.5, trunk * CF(0, h * 0.25, 0), bark, M.Wood, { name = "Trunk" })
	Kit.cyl(m, 1.6, h * 0.52, trunk * CF(0, h * 0.74, 0), Color3.fromRGB(92, 82, 72), M.Wood, { decor = true })
	local top = trunk * CF(0, h, 0)
	Kit.ball(m, 3.8, top * CF(0, 0.8, 0), Color3.fromRGB(58, 92, 48), M.LeafyGrass, { decor = true })
	local greens = { Color3.fromRGB(78, 122, 62), Color3.fromRGB(92, 134, 66), Color3.fromRGB(68, 110, 56), Color3.fromRGB(104, 140, 72) }
	-- the fans stand edge-on to the trunk (each one's flat face turned sideways), so the crown is a
	-- spiky ball from every side instead of a stack of plates
	local fans = rng:NextInteger(20, 24)
	for i = 0, fans - 1 do
		local az = i / fans * 360 * 2.618 + rng:NextNumber(-12, 12) -- golden-angle spread round the crown
		local el = -15 + (i / fans) * 95 + rng:NextNumber(-8, 8) -- from a little below level to almost straight up
		local dir = CFrame.Angles(0, rad(az), 0) * CFrame.Angles(rad(el), 0, 0)
		local d = rng:NextNumber(4.4, 5.6)
		local fan = top * CF(0, 0.8, 0) * dir * CF(0, 0, -(1.6 + d * 0.5)) * CFrame.Angles(0, 0, rad(90 + rng:NextNumber(-30, 30)))
		Kit.cyl(m, d, 0.14, fan, greens[rng:NextInteger(1, #greens)], M.LeafyGrass, { decor = true })
	end
	-- a skirt of dead brown fans hanging under the crown
	for i = 1, rng:NextInteger(3, 5) do
		local dir = CFrame.Angles(0, rad(i * 97 + rng:NextNumber(-20, 20)), 0) * CFrame.Angles(rad(-rng:NextNumber(62, 80)), 0, 0)
		local d = rng:NextNumber(3.8, 4.8)
		Kit.cyl(m, d, 0.12, top * CF(0, -0.2, 0) * dir * CF(0, 0, -(1.2 + d * 0.5)) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(146, 118, 76), M.Wood, { decor = true })
	end
	return m
end

function S.tree(parent: Instance, base: CFrame, rng: Random, kind: string?)
	local k = kind or "small"
	if k == "sugarpalm" then
		S.sugarPalm(parent, base, rng)
		return
	end
	local d = { decor = true, shadow = true }
	local bark = ({ Color3.fromRGB(104, 84, 64), Color3.fromRGB(92, 76, 60), Color3.fromRGB(116, 96, 76) })[rng:NextInteger(1, 3)]
	local greens = { Color3.fromRGB(58, 104, 50), Color3.fromRGB(72, 120, 54), Color3.fromRGB(50, 92, 48), Color3.fromRGB(86, 130, 60) }
	local function leaf(): Color3 return greens[rng:NextInteger(1, #greens)] end
	base = base * CFrame.Angles(0, rad(rng:NextNumber(0, 360)), 0)
	-- the vegetation library (Config/Plants): several species, each with its own models; an invisible
	-- trunk keeps the big ones solid. Falls back to the part-built trees below when it is not in the place.
	local plan = S.PLANTS[k] or S.PLANTS.small
	local roll = rng:NextNumber() * plan.total
	local pickKind = plan[1][1]
	for _, it in ipairs(plan) do
		roll -= it[2]
		if roll <= 0 then pickKind = it[1] break end
	end
	local names = Assets.plants(pickKind)
	if #names > 0 then
		local name = names[rng:NextInteger(1, #names)]
		local scale = rng:NextNumber(plan.scale[1], plan.scale[2])
		local flat = CFrame.new(base.Position) * CFrame.Angles(0, rad(rng:NextNumber(0, 360)), 0)
		local tree = Assets.place(parent, name, flat * CF(0, -0.2, 0), scale)
		if tree then
			if plan.trunk then
				local h = (tree:GetAttribute("Height") or 20) * scale
				local trunk = Kit.cyl(parent, plan.trunk * scale + 0.5, h * 0.45, flat * CF(0, h * 0.225, 0), bark, M.Wood, { name = "Trunk", transparency = 1 })
				trunk.CastShadow = false
			elseif k == "bush" or k == "flower" then
				Solid.body(tree, 0.7, 4) -- hedges: a walker goes round them (World/Solid)
			end
			return
		end
	end
	if k == "palm" then
		-- coconut palm: a gently curving trunk in segments, a crown of long drooping fronds
		local h = rng:NextNumber(26, 36)
		local segs = 4
		local cf = base
		local lean = rad(rng:NextNumber(2, 7))
		for i = 1, segs do
			local len = h / segs
			cf = cf * CFrame.Angles(lean * (i == 1 and 1 or 0.6), 0, 0)
			Kit.cyl(parent, 1.7 - i * 0.2, len + 0.3, cf * CF(0, len / 2, 0), bark, M.Wood, { decor = i > 1 })
			cf = cf * CF(0, len, 0)
		end
		Kit.ball(parent, 2.4, cf, Color3.fromRGB(96, 110, 60), M.LeafyGrass, d)
		local n = rng:NextInteger(8, 10)
		for i = 0, n - 1 do
			local a = cf * CFrame.Angles(0, rad(i * 360 / n + rng:NextNumber(-10, 10)), 0)
			local droop = rad(rng:NextNumber(8, 30))
			local c = leaf()
			local inner = a * CFrame.Angles(-rad(22) + droop * 0.3, 0, 0)
			Kit.part(parent, V3(2.6, 0.18, 7), inner * CF(0, 0, -3.5), c, M.LeafyGrass, d)
			local outer = inner * CF(0, 0, -7) * CFrame.Angles(-droop - rad(26), 0, 0)
			Kit.part(parent, V3(2, 0.14, 6.5), outer * CF(0, 0, -3.2), c, M.LeafyGrass, d)
		end
	elseif k == "banana" then
		Kit.cyl(parent, 1.2, 7, base * CF(0, 3.5, 0), Color3.fromRGB(120, 140, 80), M.SmoothPlastic, { decor = true })
		for i = 0, 5 do
			local a = base * CF(0, 6.6, 0) * CFrame.Angles(0, rad(i * 60 + 20), 0)
			Kit.part(parent, V3(2.8, 0.2, 5), a * CFrame.Angles(rad(38), 0, 0) * CF(0, 0, -2.5), leaf(), M.LeafyGrass, d)
			Kit.part(parent, V3(2.4, 0.16, 4), a * CFrame.Angles(rad(38), 0, 0) * CF(0, 0, -5) * CFrame.Angles(rad(-58), 0, 0) * CF(0, 0, -2), leaf(), M.LeafyGrass, d)
		end
	elseif k == "bush" then
		for i = 1, 3 do
			Kit.ball(parent, 4, base * CF(rng:NextNumber(-1.4, 1.4), 1.4 + i * 0.4, rng:NextNumber(-1.4, 1.4)), leaf(), M.LeafyGrass, d).Size = V3(rng:NextNumber(3.4, 5), rng:NextNumber(2.4, 3.4), rng:NextNumber(3.4, 5))
		end
	else
		-- broadleaf street / rain tree: forked trunk and a layered, irregular canopy
		local wide = k == "rain"
		local h = wide and rng:NextNumber(16, 22) or rng:NextNumber(11, 16)
		local spread = wide and rng:NextNumber(15, 21) or rng:NextNumber(8, 11)
		Kit.cyl(parent, wide and 2.6 or 1.6, h * 0.62, base * CF(0, h * 0.31, 0), bark, M.Wood, { decor = false })
		local fork = base * CF(0, h * 0.58, 0)
		local limbs = wide and 4 or 3
		for i = 0, limbs - 1 do
			local a = fork * CFrame.Angles(0, rad(i * 360 / limbs + rng:NextNumber(-20, 20)), 0) * CFrame.Angles(rad(rng:NextNumber(32, 50)), 0, 0)
			local len = h * 0.5
			Kit.cyl(parent, wide and 1.3 or 0.8, len, a * CF(0, len / 2, 0), bark, M.Wood, { decor = true })
			local tip = (a * CF(0, len, 0)).Position
			local sz = spread * rng:NextNumber(0.5, 0.75)
			Kit.ball(parent, sz, CF(tip), leaf(), M.LeafyGrass, d).Size = V3(sz * 1.25, sz * 0.72, sz * 1.25)
		end
		local top = base * CF(0, h + spread * 0.12, 0)
		Kit.ball(parent, spread, top, leaf(), M.LeafyGrass, d).Size = V3(spread * 1.2, spread * 0.6, spread * 1.2)
		Kit.ball(parent, spread * 0.6, top * CF(rng:NextNumber(-2, 2), spread * 0.28, rng:NextNumber(-2, 2)), leaf(), M.LeafyGrass, d).Size = V3(spread * 0.8, spread * 0.45, spread * 0.8)
	end
end

function S.lamp(parent: Instance, base: CFrame)
	-- base: at the kerb, local -Z points at the road
	Kit.cyl(parent, 0.7, 20, base * CF(0, 10, 0), C.metalDark, M.Metal, { decor = true })
	Kit.part(parent, V3(0.5, 0.5, 7), base * CF(0, 19.8, -3.2), C.metalDark, M.Metal, { decor = true })
	local head = Kit.part(parent, V3(1.6, 0.5, 3), base * CF(0, 19.5, -6), Color3.fromRGB(250, 240, 210), M.SmoothPlastic, { decor = true })
	Kit.nightLight(head, 56, Color3.fromRGB(255, 214, 160), 1.15)
	Kit.nightGlow(head)
end

-- Power pole; returns the wire attach point so the builder can string wires.
function S.pole(parent: Instance, base: CFrame): Vector3
	Kit.cyl(parent, 1, 26, base * CF(0, 13, 0), Color3.fromRGB(150, 146, 138), M.Concrete, { decor = true })
	Kit.part(parent, V3(7, 0.5, 0.5), base * CF(0, 24.5, 0), C.woodDark, M.Wood, { decor = true })
	return (base * CF(0, 24.9, 0)).Position
end

function S.wire(parent: Instance, a: Vector3, b: Vector3)
	local mid = (a + b) / 2 - Vector3.new(0, 0.8, 0)
	local len = (a - b).Magnitude
	local cf = CFrame.lookAt(mid, b - Vector3.new(0, 0.8, 0))
	for _, off in ipairs({ -3, 3 }) do
		Kit.part(parent, V3(0.14, 0.14, len), cf * CF(off, 0, 0), Color3.fromRGB(30, 30, 32), M.SmoothPlastic, { decor = true })
	end
end

function S.busStop(parent: Instance, base: CFrame)
	local m = Kit.model(parent, "BusStop")
	Kit.part(m, V3(12, 0.4, 4.4), base * CF(0, 8.4, 0), Color3.fromRGB(40, 110, 170), M.Metal, { decor = true, shadow = true })
	for _, sx in ipairs({ -5.5, 5.5 }) do Kit.part(m, V3(0.4, 8.4, 0.4), base * CF(sx, 4.2, 1.8), C.metalDark, M.Metal, { decor = true }) end
	Kit.part(m, V3(11, 5, 0.25), base * CF(0, 4.6, 2), C.glass, M.Glass, { decor = true, transparency = 0.4 })
	Kit.part(m, V3(9, 0.5, 1.6), base * CF(0, 1.9, 1.1), C.wood, M.WoodPlanks)
	local sign = Kit.part(m, V3(3.4, 2.4, 0.3), base * CF(7.4, 7, 0), Color3.fromRGB(40, 110, 170), M.SmoothPlastic, { decor = true })
	Kit.part(m, V3(0.4, 8, 0.4), base * CF(7.4, 4, 0), C.metalDark, M.Metal, { decor = true })
	Kit.sign(sign, "ป้ายรถเมล์", { sub = "BUS STOP" })
	return m
end

function S.bench(parent: Instance, base: CFrame)
	Kit.part(parent, V3(6, 0.5, 1.8), base * CF(0, 1.7, 0), C.wood, M.WoodPlanks)
	Kit.part(parent, V3(6, 1.8, 0.4), base * CF(0, 2.9, 0.9), C.wood, M.WoodPlanks, { decor = true })
	for _, sx in ipairs({ -2.5, 2.5 }) do Kit.part(parent, V3(0.5, 1.6, 1.6), base * CF(sx, 0.8, 0), C.metalDark, M.Metal, { decor = true }) end
	-- a real seat (the back rest is at +Z, so the sitter faces -Z). Nobody is sat by bumping into it:
	-- the server seats a player who chooses to rest here.
	local seat = Instance.new("Seat")
	seat.Name = "RestSeat"
	seat.Anchored = true
	seat.Size = V3(5.4, 0.3, 1.5)
	seat.CFrame = base * CF(0, 2.05, -0.05)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.CanQuery = false
	seat:AddTag("RestSeat")
	seat.Parent = parent
end

function S.trafficLight(parent: Instance, base: CFrame)
	Kit.cyl(parent, 0.8, 16, base * CF(0, 8, 0), C.metalDark, M.Metal, { decor = true })
	Kit.part(parent, V3(0.5, 0.5, 9), base * CF(0, 15.6, -4.4), C.metalDark, M.Metal, { decor = true })
	-- (2026-11-19, owner: the lights were hard to read) a bigger head on a black backboard with a yellow
	-- rim, and a hood over each lamp, as on real Thai signals. The lamps face local -X (the drivers).
	Kit.part(parent, V3(0.2, 7.6, 3.2), base * CF(0.55, 14.4, -8.6), Color3.fromRGB(240, 190, 40), M.SmoothPlastic, { decor = true })
	Kit.part(parent, V3(0.3, 7.0, 2.6), base * CF(0.45, 14.4, -8.6), Color3.fromRGB(16, 16, 18), M.SmoothPlastic, { decor = true })
	Kit.part(parent, V3(1.2, 6.2, 2.0), base * CF(-0.3, 14.4, -8.6), Color3.fromRGB(28, 28, 30), M.SmoothPlastic, { decor = true })
	local cols = { Color3.fromRGB(220, 50, 40), Color3.fromRGB(240, 190, 40), Color3.fromRGB(60, 200, 90) }
	for i, c in ipairs(cols) do
		local y = 14.4 + (2 - i) * 1.95
		local l = Kit.ball(parent, 1.55, base * CF(-0.9, y, -8.6), c, i == 3 and M.Neon or M.SmoothPlastic, { decor = true })
		l.Name = "Lamp" .. i
		Kit.part(parent, V3(1.0, 0.12, 1.75), base * CF(-1.3, y + 0.86, -8.6), Color3.fromRGB(28, 28, 30), M.SmoothPlastic, { decor = true })
	end
end

-- Sign gantry over a big road where one district ends and the next begins. cf looks along the
-- road; `front` is the district drivers enter when they see the front face, `back` the other way.
function S.gateway(parent: Instance, cf: CFrame, span: number, front: any, back: any)
	local m = Kit.model(parent, "Gateway")
	local green = Color3.fromRGB(22, 104, 64)
	for _, sx in ipairs({ -1, 1 }) do
		Kit.cyl(m, 1.6, 31, cf * CF(sx * span / 2, 15.5, 0), C.metalDark, M.Metal, { decor = true })
	end
	for _, y in ipairs({ 22.6, 30.4 }) do
		Kit.part(m, V3(span + 1.6, 1, 1), cf * CF(0, y, 0), C.metalDark, M.Metal, { decor = true })
	end
	local bw = math.min(span - 6, 36)
	local board = Kit.part(m, V3(bw, 6.6, 0.6), cf * CF(0, 26.5, 0), green, M.SmoothPlastic, { decor = true, shadow = true })
	Kit.part(m, V3(bw + 0.6, 7.2, 0.3), cf * CF(0, 26.5, 0), C.white, M.SmoothPlastic, { decor = true })
	Kit.sign(board, front.thai, { sub = front.name, face = Enum.NormalId.Front, bg = green, maxDistance = 700, pps = 14 })
	Kit.sign(board, back.thai, { sub = back.name, face = Enum.NormalId.Back, bg = green, maxDistance = 700, pps = 14 })
	return m
end

function S.billboard(parent: Instance, base: CFrame, text: string, sub: string, color: Color3)
	for _, sx in ipairs({ -8, 8 }) do Kit.cyl(parent, 1.2, 26, base * CF(sx, 13, 0), C.metalDark, M.Metal, { decor = true }) end
	local board = Kit.part(parent, V3(30, 13, 0.8), base * CF(0, 26, 0), color, M.SmoothPlastic, { decor = true, shadow = true })
	Kit.sign(board, text, { sub = sub, light = true, maxDistance = 600, pps = 14 })
	Kit.nightGlow(board)
end

-- Row of parked motorbikes made of a few parts each (Thai shopfront staple).
function S.parkedBikes(parent: Instance, base: CFrame, n: number, rng: Random)
	for i = 1, n do
		local b = base * CF((i - (n + 1) / 2) * 3, 0, 0) * CFrame.Angles(0, rad(rng:NextNumber(-12, 12)), 0)
		-- real scooter / moped meshes when they are loaded
		local key = rng:NextNumber() < 0.5 and "v_scooter" or "v_moped"
		local t = Assets.template(key)
		if t then
			local size = t:GetAttribute("Size")
			if Assets.place(parent, key, b, 7 / size.Z) then continue end
		end
		local col = Kit.AWNING[rng:NextInteger(1, #Kit.AWNING)]
		Kit.part(parent, V3(1.1, 1.4, 4.4), b * CF(0, 1.9, 0), col, M.SmoothPlastic, { decor = true })
		Kit.part(parent, V3(1.2, 0.5, 2.4), b * CF(0, 2.8, 0.8), Color3.fromRGB(30, 30, 34), M.SmoothPlastic, { decor = true })
		Kit.cyl(parent, 1.9, 0.5, b * CF(0, 0.95, -2.3) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(24, 24, 26), M.SmoothPlastic, { decor = true })
		Kit.cyl(parent, 1.9, 0.5, b * CF(0, 0.95, 2.3) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(24, 24, 26), M.SmoothPlastic, { decor = true })
	end
end

function S.stall(parent: Instance, base: CFrame, rng: Random, label: string?)
	local col = Kit.AWNING[rng:NextInteger(1, #Kit.AWNING)]
	Kit.part(parent, V3(8, 3, 3.4), base * CF(0, 1.5, 0), C.metal, M.Metal)
	for _, sx in ipairs({ -3.8, 3.8 }) do
		Kit.part(parent, V3(0.3, 8.6, 0.3), base * CF(sx, 4.3, -1.6), C.metalDark, M.Metal, { decor = true })
		Kit.part(parent, V3(0.3, 7.4, 0.3), base * CF(sx, 3.7, 1.6), C.metalDark, M.Metal, { decor = true })
	end
	Kit.part(parent, V3(9.6, 0.3, 5.6), base * CF(0, 8.2, 0) * CFrame.Angles(rad(-11), 0, 0), col, M.Fabric, { decor = true, shadow = true })
	-- food trays
	for i = -1, 1 do
		Kit.part(parent, V3(2, 0.4, 2), base * CF(i * 2.5, 3.2, 0), ({ Color3.fromRGB(230, 140, 60), Color3.fromRGB(200, 60, 50), Color3.fromRGB(120, 180, 80) })[i + 2], M.SmoothPlastic, { decor = true })
	end
	local bulb = Kit.ball(parent, 0.8, base * CF(0, 7.2, -1), Color3.fromRGB(255, 230, 170), M.SmoothPlastic, { decor = true })
	Kit.nightLight(bulb, 20, Color3.fromRGB(255, 200, 130), 1.5)
	Kit.nightGlow(bulb)
	if label then
		local s = Kit.part(parent, V3(7, 1.6, 0.3), base * CF(0, 6.6, -2.2), col, M.SmoothPlastic, { decor = true })
		Kit.sign(s, label, { maxDistance = 160 })
	end
end

S.darker = darker
return S
