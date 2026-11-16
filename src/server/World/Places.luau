-- Hand-designed places (landmarks, services). Each builder works in the lot's local frame
-- (front = -Z, x across the front) and reports where its prompts and staff go through `out`:
--   out.door  = Vector3   main interaction point
--   out.npc   = CFrame    where the staff NPC stands (feet)
--   out.extra = { {kind=, pos=, action=, object=} }  additional prompts
local Kit = require(script.Parent.Kit)
local S = require(script.Parent.Scenery)
local M = Kit.M
local C = Kit.COLORS
local V3 = Vector3.new
local CF = CFrame.new
local rad = math.rad
local Angles = CFrame.Angles

local Places = {}

local function world(base: CFrame, x: number, y: number, z: number): Vector3
	return (base * CF(x, y, z)).Position
end

local function pad(m: Instance, base: CFrame, w: number, d: number, color: Color3?, mat: Enum.Material?)
	return Kit.part(m, V3(w, 0.5, d), base * CF(0, 0.05, 0), color or C.concrete, mat or M.Concrete, { name = "Pad" })
end

local function bigSign(m: Instance, cf: CFrame, w: number, h: number, color: Color3, text: string, sub: string?)
	local s = Kit.part(m, V3(w, h, 0.6), cf, color, M.SmoothPlastic, { decor = true })
	Kit.sign(s, text, { sub = sub, light = true, maxDistance = 520, pps = 16 })
	Kit.nightGlow(s)
	return s
end

---------------------------------------------------------------------------------------------------
function Places.hub(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(206, 206, 200))
	-- office at the back
	Kit.part(m, V3(w - 8, 16, 22), base * CF(0, 8, d / 2 - 13), C.white, M.Concrete)
	Kit.part(m, V3(w - 8, 3, 22.6), base * CF(0, 17.5, d / 2 - 13), C.godash, M.SmoothPlastic, { decor = true })
	local glass = Kit.part(m, V3(w - 16, 8, 0.4), base * CF(0, 5, d / 2 - 24.1), C.glassDark, M.Glass, { decor = true, reflectance = 0.15 })
	Kit.nightGlow(glass)
	bigSign(m, base * CF(0, 22, d / 2 - 24.4), 34, 6, C.godash, "GoDash", "RIDER HUB · ศูนย์ไรเดอร์")
	-- canopy with bike parking
	Kit.part(m, V3(w - 14, 0.6, 16), base * CF(0, 11, d / 2 - 33), C.godash, M.Metal, { decor = true, shadow = true })
	for _, sx in ipairs({ -1, 1 }) do
		Kit.cyl(m, 0.8, 11, base * CF(sx * (w / 2 - 9), 5.5, d / 2 - 40), C.metal, M.Metal)
	end
	S.parkedBikes(m, base * CF(-10, 0.3, d / 2 - 32), 4, rng)
	-- rest benches under the canopy
	S.bench(m, base * CF(14, 0.3, d / 2 - 29))
	S.bench(m, base * CF(22, 0.3, d / 2 - 29))
	local lightBar = Kit.part(m, V3(w - 20, 0.3, 1), base * CF(0, 10.6, d / 2 - 33), Color3.fromRGB(255, 240, 210), M.SmoothPlastic, { decor = true })
	Kit.nightLight(lightBar, 44, nil, 1.8); Kit.nightGlow(lightBar)
	S.tree(m, base * CF(-w / 2 + 5, 0, -d / 2 + 6), rng, "palm")
	S.tree(m, base * CF(w / 2 - 5, 0, -d / 2 + 6), rng, "palm")
	out.door = world(base, 0, 3, d / 2 - 27)
	out.npc = base * CF(6, 0.3, d / 2 - 25.5) * Angles(0, 0, 0)
	out.extra = {
		{ kind = "rest", pos = world(base, 18, 3, d / 2 - 30), action = "Rest", object = "Bench (free energy)" },
	}
	out.spawns = {}
	for i = -2, 2 do table.insert(out.spawns, base * CF(i * 7, 3, -d / 2 + 12)) end
end

function Places.dealer(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(190, 192, 196))
	Kit.part(m, V3(w - 30, 18, 34), base * CF(-10, 9, d / 2 - 19), C.white, M.Concrete)
	local glass = Kit.part(m, V3(w - 40, 12, 0.5), base * CF(-10, 7, d / 2 - 36.2), C.glass, M.Glass, { decor = true, reflectance = 0.2, transparency = 0.25 })
	Kit.nightGlow(glass)
	Kit.part(m, V3(w - 26, 2, 38), base * CF(-10, 19, d / 2 - 20), Color3.fromRGB(200, 40, 40), M.Metal, { decor = true })
	bigSign(m, base * CF(-10, 24, d / 2 - 37), 46, 7, Color3.fromRGB(200, 40, 40), "KK MOTORS", "ศูนย์รถยนต์และมอเตอร์ไซค์")
	-- display podiums out front
	for i = -1, 1 do
		Kit.cyl(m, 16, 0.6, base * CF(i * 26 - 10, 0.6, -d / 2 + 16), Color3.fromRGB(60, 62, 68), M.Metal)
	end
	out.display = { base * CF(-36, 1, -d / 2 + 16), base * CF(-10, 1, -d / 2 + 16), base * CF(16, 1, -d / 2 + 16) }
	-- service bay
	Kit.part(m, V3(22, 13, 28), base * CF(w / 2 - 14, 6.5, d / 2 - 16), Color3.fromRGB(120, 124, 130), M.Metal)
	Kit.part(m, V3(16, 9, 0.5), base * CF(w / 2 - 14, 4.5, d / 2 - 30.2), Color3.fromRGB(40, 42, 46), M.Metal, { decor = true })
	local s2 = Kit.part(m, V3(18, 2.6, 0.5), base * CF(w / 2 - 14, 11, d / 2 - 30.4), Color3.fromRGB(240, 170, 40), M.SmoothPlastic, { decor = true })
	Kit.sign(s2, "SERVICE · ศูนย์ซ่อม", { color = Color3.fromRGB(30, 30, 30) })
	for _, sx in ipairs({ -w / 2 + 4, w / 2 - 4 }) do S.lamp(m, base * CF(sx, 0, -d / 2 + 4) * Angles(0, rad(180), 0)) end
	out.door = world(base, -10, 3, d / 2 - 40)
	out.npc = base * CF(-4, 0.3, d / 2 - 39)
	out.extra = { { kind = "service", pos = world(base, w / 2 - 14, 3, d / 2 - 34), action = "Service", object = "Repair · Refuel · Upgrades" } }
end

function Places.homestore(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d)
	Kit.part(m, V3(w - 12, 20, d - 30), base * CF(0, 10, 12), Color3.fromRGB(244, 236, 220), M.Concrete)
	local glass = Kit.part(m, V3(w - 30, 10, 0.5), base * CF(0, 6, -d / 2 + 26.8), C.glass, M.Glass, { decor = true, transparency = 0.2 })
	Kit.nightGlow(glass)
	Kit.part(m, V3(w - 8, 1.2, 12), base * CF(0, 13, -d / 2 + 21), Color3.fromRGB(230, 120, 40), M.Metal, { decor = true, shadow = true })
	bigSign(m, base * CF(0, 24, -d / 2 + 26.6), 50, 7, Color3.fromRGB(230, 120, 40), "BAAN SUAY HOME", "บ้านสวย โฮม · เฟอร์นิเจอร์")
	-- sample furniture out front
	Kit.part(m, V3(8, 3, 3.6), base * CF(-20, 1.8, -d / 2 + 14), Color3.fromRGB(70, 110, 160), M.Fabric)
	Kit.part(m, V3(5, 1.6, 3), base * CF(-20, 1.1, -d / 2 + 8), C.wood, M.Wood)
	Kit.part(m, V3(4.6, 2.6, 8.4), base * CF(22, 1.6, -d / 2 + 12), C.white, M.Fabric)
	S.tree(m, base * CF(-w / 2 + 6, 0, -d / 2 + 6), rng, "small")
	S.tree(m, base * CF(w / 2 - 6, 0, -d / 2 + 6), rng, "small")
	out.door = world(base, 0, 3, -d / 2 + 22)
	out.npc = base * CF(6, 0.3, -d / 2 + 24)
end

function Places.nightmarket(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(120, 118, 114), M.Cobblestone)
	local labels = { "หมูปิ้ง", "ส้มตำ", "ผัดไทย", "ชานม", "ลูกชิ้น", "ไก่ทอด", "ข้าวเหนียวมะม่วง", "น้ำปั่น", "ก๋วยเตี๋ยว", "โรตี" }
	local i = 0
	for row = -1, 1, 2 do
		for col = -2, 2 do
			i += 1
			S.stall(m, base * CF(col * 15, 0.3, row * 20) * Angles(0, row == 1 and rad(180) or 0, 0), rng, labels[i])
		end
	end
	-- string lights across the aisle
	for x = -30, 30, 15 do
		local bulbLine = Kit.part(m, V3(0.2, 0.2, 34), base * CF(x + 7, 10, 0), Color3.fromRGB(255, 220, 150), M.SmoothPlastic, { decor = true })
		Kit.nightGlow(bulbLine)
	end
	-- gate arch
	for _, sx in ipairs({ -12, 12 }) do Kit.part(m, V3(1.4, 14, 1.4), base * CF(sx, 7, -d / 2 + 3), Color3.fromRGB(170, 40, 40), M.Metal) end
	bigSign(m, base * CF(0, 14, -d / 2 + 3), 28, 4.6, Color3.fromRGB(170, 40, 40), "ตลาดโต้รุ่ง", "TON RUNG NIGHT MARKET")
	-- eating tables
	for x = -24, 24, 16 do
		Kit.part(m, V3(5, 0.4, 5), base * CF(x, 2.8, 0), C.metal, M.Metal)
		Kit.cyl(m, 0.6, 2.6, base * CF(x, 1.4, 0), C.metalDark, M.Metal, { decor = true })
	end
	out.door = world(base, 0, 3, -6)
	out.npc = base * CF(0, 0.3, -17.6) * Angles(0, rad(180), 0)
end

function Places.mall(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(180, 182, 186))
	local bd = d - 60
	Kit.part(m, V3(w - 20, 44, bd), base * CF(0, 22, 26), Color3.fromRGB(236, 232, 226), M.Concrete)
	Kit.part(m, V3(w - 60, 44, 8), base * CF(0, 22, 26 - bd / 2 - 4), Color3.fromRGB(200, 60, 60), M.Concrete)
	local glass = Kit.part(m, V3(w - 90, 26, 0.6), base * CF(0, 14, 26 - bd / 2 - 8.3), C.glass, M.Glass, { decor = true, reflectance = 0.25, transparency = 0.15 })
	Kit.nightGlow(glass)
	bigSign(m, base * CF(0, 36, 26 - bd / 2 - 8.5), 70, 11, Color3.fromRGB(200, 60, 60), "KK PLAZA", "เคเค พลาซ่า · ศูนย์การค้า")
	for _, sx in ipairs({ -1, 1 }) do
		local g2 = Kit.part(m, V3(34, 12, 0.5), base * CF(sx * 62, 26, 26 - bd / 2 - 0.3), C.glass, M.Glass, { decor = true, reflectance = 0.2 })
		Kit.nightGlow(g2)
	end
	Kit.part(m, V3(60, 1, 14), base * CF(0, 12, 26 - bd / 2 - 14), Color3.fromRGB(240, 240, 240), M.Metal, { decor = true, shadow = true })
	for _, sx in ipairs({ -26, 26 }) do Kit.cyl(m, 1.6, 12, base * CF(sx, 6, 26 - bd / 2 - 19), C.white, M.Concrete) end
	-- car park lines + trees
	for x = -w / 2 + 14, w / 2 - 14, 12 do
		Kit.part(m, V3(0.5, 0.06, 18), base * CF(x, 0.34, -d / 2 + 14), C.line, M.SmoothPlastic, { decor = true })
	end
	for x = -w / 2 + 8, w / 2 - 8, 46 do S.tree(m, base * CF(x, 0, -d / 2 + 28), rng, "palm") end
	out.door = world(base, 0, 3, 26 - bd / 2 - 14)
	out.npc = base * CF(8, 0.3, 26 - bd / 2 - 12)
end

function Places.hospital(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(200, 204, 206))
	Kit.part(m, V3(w - 50, 50, d - 50), base * CF(0, 25, 16), C.white, M.Concrete)
	Kit.part(m, V3(50, 28, d - 60), base * CF(-(w / 2 - 30), 14, 16), Color3.fromRGB(226, 236, 240), M.Concrete)
	Kit.part(m, V3(50, 28, d - 60), base * CF(w / 2 - 30, 14, 16), Color3.fromRGB(226, 236, 240), M.Concrete)
	for f = 1, 4 do
		local g = Kit.part(m, V3(w - 60, 5, 0.4), base * CF(0, f * 10 + 3, 16 - (d - 50) / 2 - 0.2), C.glass, M.Glass, { decor = true })
		if f % 2 == 0 then Kit.nightGlow(g) end
	end
	Kit.part(m, V3(40, 1, 16), base * CF(0, 10, 16 - (d - 50) / 2 - 8), Color3.fromRGB(60, 150, 110), M.Metal, { decor = true, shadow = true })
	for _, sx in ipairs({ -18, 18 }) do Kit.cyl(m, 1.2, 10, base * CF(sx, 5, 16 - (d - 50) / 2 - 14), C.white, M.Concrete) end
	-- green cross
	local cz = 16 - (d - 50) / 2 - 0.5
	Kit.part(m, V3(3, 10, 0.6), base * CF(0, 44, cz), Color3.fromRGB(40, 170, 90), M.Neon, { decor = true })
	Kit.part(m, V3(10, 3, 0.6), base * CF(0, 44, cz), Color3.fromRGB(40, 170, 90), M.Neon, { decor = true })
	bigSign(m, base * CF(0, 14.6, 16 - (d - 50) / 2 - 15.6), 38, 4, Color3.fromRGB(60, 150, 110), "โรงพยาบาลขอนแก่น", "KHON KAEN HOSPITAL")
	for x = -w / 2 + 12, w / 2 - 12, 30 do S.tree(m, base * CF(x, 0, -d / 2 + 8), rng, "small") end
	out.door = world(base, 0, 3, 16 - (d - 50) / 2 - 10)
	out.npc = base * CF(7, 0.3, 16 - (d - 50) / 2 - 6)
end

function Places.police(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d)
	Kit.part(m, V3(w - 24, 20, d - 26), base * CF(0, 10, 9), Color3.fromRGB(232, 226, 210), M.Concrete)
	Kit.gable(m, base * CF(0, 0, 9), w - 20, d - 22, 7, 20, Color3.fromRGB(120, 60, 50), M.Slate)
	local g = Kit.part(m, V3(w - 40, 7, 0.4), base * CF(0, 5, 9 - (d - 26) / 2 - 0.2), C.glassDark, M.Glass, { decor = true })
	Kit.nightGlow(g)
	bigSign(m, base * CF(0, 13, 9 - (d - 26) / 2 - 0.5), 40, 4.4, Color3.fromRGB(110, 40, 40), "สถานีตำรวจภูธรเมืองขอนแก่น", "POLICE STATION")
	Kit.cyl(m, 0.6, 26, base * CF(-w / 2 + 10, 13, -d / 2 + 8), C.metal, M.Metal, { decor = true })
	Kit.part(m, V3(5, 3.2, 0.2), base * CF(-w / 2 + 12.6, 24, -d / 2 + 8), Color3.fromRGB(200, 40, 50), M.Fabric, { decor = true })
	out.door = world(base, 0, 3, 9 - (d - 26) / 2 - 5)
	out.npc = base * CF(6, 0.3, 9 - (d - 26) / 2 - 3)
end

function Places.bus(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(150, 152, 156))
	-- terminal hall
	Kit.part(m, V3(w - 40, 18, 40), base * CF(0, 9, d / 2 - 24), Color3.fromRGB(230, 226, 214), M.Concrete)
	local g = Kit.part(m, V3(w - 60, 10, 0.5), base * CF(0, 6, d / 2 - 44.2), C.glass, M.Glass, { decor = true, transparency = 0.2 })
	Kit.nightGlow(g)
	bigSign(m, base * CF(0, 22, d / 2 - 44.4), 60, 6.5, Color3.fromRGB(40, 90, 170), "สถานีขนส่งผู้โดยสารขอนแก่น", "KHON KAEN BUS TERMINAL")
	-- platform canopy
	Kit.part(m, V3(w - 30, 0.8, 22), base * CF(0, 14, -4), Color3.fromRGB(40, 90, 170), M.Metal, { decor = true, shadow = true })
	for x = -w / 2 + 22, w / 2 - 22, 34 do
		Kit.cyl(m, 1.2, 14, base * CF(x, 7, -4), C.metal, M.Metal)
	end
	-- two parked buses
	for i, x in ipairs({ -40, 30 }) do
		local col = i == 1 and Color3.fromRGB(240, 130, 40) or Color3.fromRGB(60, 130, 210)
		Kit.part(m, V3(9, 9, 30), base * CF(x, 6, -4), col, M.SmoothPlastic)
		Kit.part(m, V3(9.2, 3.2, 26), base * CF(x, 7.6, -4), C.glassDark, M.Glass, { decor = true })
		for _, wz in ipairs({ -10, 10 }) do
			Kit.cyl(m, 3.4, 9.6, base * CF(x, 1.9, -4 + wz) * Angles(0, 0, rad(90)), Color3.fromRGB(26, 26, 28), M.SmoothPlastic, { decor = true })
		end
	end
	S.bench(m, base * CF(-6, 0.3, 8)); S.bench(m, base * CF(6, 0.3, 8))
	out.door = world(base, 0, 3, d / 2 - 49)
	out.npc = base * CF(8, 0.3, d / 2 - 46)
end

function Places.gas(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(170, 172, 176))
	local col = Color3.fromRGB(30, 120, 200)
	Kit.part(m, V3(w - 12, 1.6, 30), base * CF(0, 15, -6), col, M.Metal, { decor = true, shadow = true })
	Kit.part(m, V3(w - 12.4, 0.5, 30.4), base * CF(0, 14, -6), C.white, M.SmoothPlastic, { decor = true })
	local strip = Kit.part(m, V3(w - 20, 0.3, 2), base * CF(0, 13.7, -6), Color3.fromRGB(255, 250, 230), M.SmoothPlastic, { decor = true })
	Kit.nightLight(strip, 50, Color3.fromRGB(255, 250, 235), 2); Kit.nightGlow(strip)
	out.extra = {}
	for i, sx in ipairs({ -w / 4, w / 4 }) do
		Kit.cyl(m, 1.4, 14, base * CF(sx, 7, -6), C.white, M.Metal)
		Kit.part(m, V3(3, 6, 2), base * CF(sx, 3.3, -12), col, M.SmoothPlastic)
		Kit.part(m, V3(3, 6, 2), base * CF(sx, 3.3, 0), col, M.SmoothPlastic)
		Kit.part(m, V3(6, 0.7, 20), base * CF(sx, 0.6, -6), C.curb, M.Concrete)
	end
	-- shop
	Kit.part(m, V3(w - 20, 12, 16), base * CF(0, 6, d / 2 - 10), C.white, M.Concrete)
	local g = Kit.part(m, V3(w - 28, 7, 0.4), base * CF(0, 4.6, d / 2 - 18.2), C.glassDark, M.Glass, { decor = true })
	Kit.nightGlow(g)
	bigSign(m, base * CF(0, 10.4, d / 2 - 18.4), w - 26, 2.8, col, poi.name, poi.thai)
	-- price pylon
	Kit.part(m, V3(5, 18, 1.4), base * CF(-w / 2 + 5, 9, -d / 2 + 4), col, M.SmoothPlastic)
	local price = Kit.part(m, V3(4.4, 7, 0.3), base * CF(-w / 2 + 5, 11, -d / 2 + 3.2), C.white, M.SmoothPlastic, { decor = true })
	Kit.sign(price, "⛽ 91", { sub = "฿4 / L", color = Color3.fromRGB(30, 30, 30) })
	out.door = world(base, 0, 3, -6)
	out.npc = base * CF(0, 0.3, d / 2 - 20)
end

function Places.university(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	Kit.part(m, V3(w, 0.5, d), base * CF(0, 0.05, 0), Color3.fromRGB(110, 160, 84), M.Grass, { name = "Pad" })
	-- gate (two brick pylons + beam) at the front centre
	local brick = Color3.fromRGB(170, 86, 64)
	for _, sx in ipairs({ -24, 24 }) do
		Kit.part(m, V3(8, 26, 8), base * CF(sx, 13, -d / 2 + 8), brick, M.Brick)
		Kit.part(m, V3(10, 2, 10), base * CF(sx, 27, -d / 2 + 8), C.gold, M.SmoothPlastic, { decor = true })
	end
	Kit.part(m, V3(56, 5, 5), base * CF(0, 22, -d / 2 + 8), brick, M.Brick)
	bigSign(m, base * CF(0, 22, -d / 2 + 5.2), 44, 4, brick, "มหาวิทยาลัยขอนแก่น", "KHON KAEN UNIVERSITY")
	-- avenue + main hall with clock tower
	Kit.part(m, V3(26, 0.3, d - 50), base * CF(0, 0.4, -10), C.asphaltSoi, M.Asphalt, { decor = true })
	Kit.part(m, V3(150, 30, 34), base * CF(0, 15, d / 2 - 24), Color3.fromRGB(232, 222, 200), M.Concrete)
	Kit.gable(m, base * CF(0, 0, d / 2 - 24), 156, 40, 12, 30, brick, M.Slate)
	for f = 0, 2 do
		local g = Kit.part(m, V3(136, 4.6, 0.4), base * CF(0, 6 + f * 9, d / 2 - 41.2), C.glass, M.Glass, { decor = true })
		if f > 0 then Kit.nightGlow(g) end
	end
	Kit.part(m, V3(16, 62, 16), base * CF(0, 31, d / 2 - 44), Color3.fromRGB(232, 222, 200), M.Concrete)
	Kit.part(m, V3(18, 3, 18), base * CF(0, 63, d / 2 - 44), brick, M.Slate, { decor = true })
	local clock = Kit.cyl(m, 10, 0.6, base * CF(0, 52, d / 2 - 52.2) * Angles(rad(90), 0, 0), C.white, M.SmoothPlastic, { decor = true })
	Kit.nightGlow(clock)
	-- faculty blocks either side
	for _, sx in ipairs({ -1, 1 }) do
		for k = 1, 2 do
			local x = sx * (60 + k * 86)
			if math.abs(x) < w / 2 - 40 then
				Kit.part(m, V3(70, 24 + k * 6, 40), base * CF(x, 12 + k * 3, 10), Kit.PASTEL[rng:NextInteger(1, #Kit.PASTEL)], M.Concrete)
				local g = Kit.part(m, V3(60, 14 + k * 6, 0.4), base * CF(x, 13 + k * 3, -10.2), C.glass, M.Glass, { decor = true })
				Kit.nightGlow(g)
			end
		end
		for z = -d / 2 + 24, 0, 22 do
			S.tree(m, base * CF(sx * 20, 0, z), rng, "rain")
		end
	end
	out.door = world(base, 34, 3, -d / 2 + 2)
	out.npc = base * CF(30, 0.5, -d / 2 + 3) * Angles(0, 0, 0)
end

-- Nine-tier stupa in the style of the lakeside landmark (architecture only).
function Places.stupa(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(226, 220, 204), M.Marble)
	local wall = Color3.fromRGB(244, 240, 228)
	local size, y = 50, 0.3
	for tier = 1, 9 do
		local h = tier == 1 and 9 or 6.5
		Kit.part(m, V3(size, h, size), base * CF(0, y + h / 2, 0), wall, M.Concrete, { decor = tier > 2 })
		Kit.part(m, V3(size + 2.4, 0.9, size + 2.4), base * CF(0, y + h + 0.45, 0), Color3.fromRGB(176, 60, 44), M.Slate, { decor = true })
		y += h + 0.9
		size -= 4.6
	end
	local spire = Kit.part(m, V3(5, 5, 5), base * CF(0, y + 2.5, 0), C.gold, M.Metal, { decor = true, reflectance = 0.3 })
	Kit.nightGlow(spire)
	Kit.part(m, V3(3, 12, 3), base * CF(0, y + 11, 0), C.gold, M.Metal, { decor = true, reflectance = 0.3 })
	Kit.part(m, V3(1.6, 10, 1.6), base * CF(0, y + 22, 0), C.gold, M.Metal, { decor = true, reflectance = 0.3 })
	Kit.part(m, V3(0.6, 8, 0.6), base * CF(0, y + 31, 0), C.gold, M.Metal, { decor = true })
	-- corner lamps and trees
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local lamp = Kit.ball(m, 1.6, base * CF(sx * (w / 2 - 6), 9, sz * (d / 2 - 6)), Color3.fromRGB(255, 236, 190), M.SmoothPlastic, { decor = true })
			Kit.cyl(m, 0.6, 8.4, base * CF(sx * (w / 2 - 6), 4.2, sz * (d / 2 - 6)), C.gold, M.Metal, { decor = true })
			Kit.nightLight(lamp, 40, Color3.fromRGB(255, 220, 160), 2); Kit.nightGlow(lamp)
		end
	end
	bigSign(m, base * CF(0, 5, -d / 2 + 1), 30, 3, Color3.fromRGB(120, 40, 36), "พระธาตุแก่นนคร", "KAEN NAKHON STUPA")
	out.door = world(base, 0, 3, -d / 2 + 6)
end

local function openHall(m, base, w, d, roofCol, rng, labels)
	Kit.part(m, V3(w - 8, 1, d - 16), base * CF(0, 16, 4), roofCol, M.CorrodedMetal, { decor = true, shadow = true })
	Kit.gable(m, base * CF(0, 0, 4), w - 4, d - 12, 6, 16.5, roofCol, M.CorrodedMetal)
	for _, sx in ipairs({ -1, 0, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			Kit.part(m, V3(1.4, 16, 1.4), base * CF(sx * (w / 2 - 8), 8, 4 + sz * (d / 2 - 12)), C.metalDark, M.Metal)
		end
	end
	local i = 0
	for x = -w / 2 + 16, w / 2 - 16, 15 do
		i += 1
		S.stall(m, base * CF(x, 0.3, 16), rng, labels[(i - 1) % #labels + 1])
		-- produce crates
		for k = -1, 1 do
			Kit.part(m, V3(3, 2, 3), base * CF(x + k * 3.6, 1.3, -6), C.wood, M.WoodPlanks)
			Kit.part(m, V3(2.6, 0.8, 2.6), base * CF(x + k * 3.6, 2.6, -6),
				({ Color3.fromRGB(210, 50, 40), Color3.fromRGB(120, 190, 80), Color3.fromRGB(240, 200, 60) })[k + 2], M.SmoothPlastic, { decor = true })
		end
	end
	local light = Kit.part(m, V3(w - 20, 0.3, 1), base * CF(0, 15, 4), Color3.fromRGB(255, 240, 210), M.SmoothPlastic, { decor = true })
	Kit.nightLight(light, 56, nil, 1.6); Kit.nightGlow(light)
end

function Places.market(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(176, 172, 164))
	openHall(m, base, w, d, Color3.fromRGB(60, 120, 90), rng, { "ผักสด", "หมูปิ้ง", "ส้มตำ", "ผลไม้", "ไก่ย่าง", "ขนมไทย" })
	bigSign(m, base * CF(0, 13, -d / 2 + 9.4), 44, 4.2, Color3.fromRGB(60, 120, 90), poi.thai, "FRESH MARKET")
	S.parkedBikes(m, base * CF(-w / 2 + 14, 0.3, -d / 2 + 5), 5, rng)
	out.door = world(base, 0, 3, 2)
	out.npc = base * CF(0, 0.3, 12.4) * Angles(0, 0, 0)
end

function Places.agri(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(170, 150, 120), M.Ground)
	openHall(m, base, w, d, Color3.fromRGB(150, 70, 50), rng, { "รับซื้อพริก", "รับซื้อข้าว", "ข้าวโพด", "แตงโม", "ผักกาด", "มะเขือเทศ" })
	bigSign(m, base * CF(0, 13, -d / 2 + 9.4), 44, 4.2, Color3.fromRGB(150, 70, 50), poi.thai, "FARMERS' MARKET · SELL CROPS")
	-- weighing scale + pickup
	Kit.part(m, V3(6, 1, 6), base * CF(w / 2 - 12, 0.8, -d / 2 + 10), C.metal, M.DiamondPlate)
	Kit.part(m, V3(1, 7, 1), base * CF(w / 2 - 9, 3.5, -d / 2 + 7), C.metalDark, M.Metal, { decor = true })
	out.door = world(base, 0, 3, 2)
	out.npc = base * CF(0, 0.3, 12.4)
end

function Places.seedshop(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(176, 160, 130), M.Ground)
	Kit.part(m, V3(w - 8, 11, d - 20), base * CF(0, 5.5, 8), Color3.fromRGB(196, 170, 120), M.WoodPlanks)
	Kit.gable(m, base * CF(0, 0, 8), w - 4, d - 14, 5, 11, Color3.fromRGB(60, 120, 70), M.CorrodedMetal)
	Kit.part(m, V3(w - 6, 0.4, 8), base * CF(0, 9, -d / 2 + 12) * Angles(rad(-8), 0, 0), Color3.fromRGB(60, 120, 70), M.Fabric, { decor = true, shadow = true })
	bigSign(m, base * CF(0, 12.4, -d / 2 + 17.6), w - 12, 3, Color3.fromRGB(60, 120, 70), poi.thai, "SEEDS · FERTILIZER")
	-- seed sacks and seedling trays
	for i = -1, 1 do
		Kit.part(m, V3(3, 2.6, 2), base * CF(i * 5, 1.6, -d / 2 + 10), ({ Color3.fromRGB(220, 200, 150), Color3.fromRGB(200, 180, 130), Color3.fromRGB(230, 210, 170) })[i + 2], M.Fabric)
		Kit.part(m, V3(3, 0.6, 2.4), base * CF(i * 5, 0.7, -d / 2 + 5), Color3.fromRGB(90, 170, 80), M.Grass, { decor = true })
	end
	out.door = world(base, 0, 3, -d / 2 + 8)
	out.npc = base * CF(5, 0.3, -d / 2 + 12.5)
end

function Places.station(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(186, 180, 168))
	local cream = Color3.fromRGB(240, 226, 190)
	Kit.part(m, V3(w - 30, 20, 30), base * CF(0, 10, d / 2 - 20), cream, M.Concrete)
	Kit.gable(m, base * CF(0, 0, d / 2 - 20), w - 24, 36, 9, 20, Color3.fromRGB(150, 60, 50), M.Slate)
	local g = Kit.part(m, V3(w - 60, 9, 0.5), base * CF(0, 6, d / 2 - 35.2), C.glassDark, M.Glass, { decor = true })
	Kit.nightGlow(g)
	Kit.part(m, V3(60, 1, 14), base * CF(0, 13, d / 2 - 42), Color3.fromRGB(150, 60, 50), M.Metal, { decor = true, shadow = true })
	for _, sx in ipairs({ -26, 26 }) do Kit.cyl(m, 1.4, 13, base * CF(sx, 6.5, d / 2 - 47), cream, M.Concrete) end
	bigSign(m, base * CF(0, 17, d / 2 - 35.6), 62, 5, Color3.fromRGB(40, 60, 120), "สถานีรถไฟขอนแก่น", "KHON KAEN RAILWAY STATION")
	-- clock tower
	Kit.part(m, V3(10, 40, 10), base * CF(-(w / 2 - 22), 20, d / 2 - 30), cream, M.Concrete)
	Kit.part(m, V3(12, 2, 12), base * CF(-(w / 2 - 22), 41, d / 2 - 30), Color3.fromRGB(150, 60, 50), M.Slate, { decor = true })
	local clock = Kit.cyl(m, 7, 0.5, base * CF(-(w / 2 - 22), 33, d / 2 - 35.2) * Angles(rad(90), 0, 0), C.white, M.SmoothPlastic, { decor = true })
	Kit.nightGlow(clock)
	S.bench(m, base * CF(-12, 0.3, d / 2 - 40)); S.bench(m, base * CF(12, 0.3, d / 2 - 40))
	S.parkedBikes(m, base * CF(w / 2 - 22, 0.3, -d / 2 + 8), 5, rng)
	S.tree(m, base * CF(-w / 2 + 6, 0, -d / 2 + 6), rng, "rain")
	out.door = world(base, 0, 3, d / 2 - 46)
	out.npc = base * CF(8, 0.3, d / 2 - 44)
end

-- Community farm: fenced compound with a hut and water tank; the allotments are built by FarmingService.
function Places.farm(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	Kit.part(m, V3(w, 0.4, d), base * CF(0, 0, 0), Color3.fromRGB(120, 150, 80), M.Grass, { name = "Pad" })
	local fence = Color3.fromRGB(150, 110, 70)
	Kit.part(m, V3(w, 2.6, 0.5), base * CF(0, 1.5, d / 2 - 0.4), fence, M.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do Kit.part(m, V3(0.5, 2.6, d), base * CF(sx * (w / 2 - 0.4), 1.5, 0), fence, M.WoodPlanks) end
	for _, sx in ipairs({ -1, 1 }) do Kit.part(m, V3(w / 2 - 14, 2.6, 0.5), base * CF(sx * (w / 4 + 7), 1.5, -d / 2 + 0.4), fence, M.WoodPlanks) end
	-- gate
	for _, sx in ipairs({ -13, 13 }) do Kit.part(m, V3(1.2, 11, 1.2), base * CF(sx, 5.5, -d / 2 + 0.6), C.woodDark, M.Wood) end
	bigSign(m, base * CF(0, 11, -d / 2 + 0.6), 30, 3.4, Color3.fromRGB(60, 120, 70), poi.thai, "COMMUNITY FARM")
	-- hut and water tank in the middle aisle
	Kit.part(m, V3(16, 9, 12), base * CF(0, 4.7, d / 2 - 12), Color3.fromRGB(196, 170, 120), M.WoodPlanks)
	Kit.gable(m, base * CF(0, 0, d / 2 - 12), 20, 16, 5, 9.2, Color3.fromRGB(150, 64, 54), M.CorrodedMetal)
	Kit.cyl(m, 7, 8, base * CF(16, 8, d / 2 - 10), Color3.fromRGB(70, 110, 170), M.SmoothPlastic)
	for _, o in ipairs({ { 13.5, -12.5 }, { 18.5, -12.5 }, { 13.5, -7.5 }, { 18.5, -7.5 } }) do
		Kit.part(m, V3(0.6, 4, 0.6), base * CF(o[1], 2, d / 2 + o[2]), C.metalDark, M.Metal, { decor = true })
	end
	local cols, rows = 6, 2
	out.allotments = {}
	local n = 0
	for r = 1, rows do
		for c = 1, cols do
			n += 1
			local x = (c - (cols + 1) / 2) * 72
			x += x > 0 and 14 or -14 -- leave the centre aisle free
			local z = (r - 1.5) * 54 - 6
			table.insert(out.allotments, { id = "F" .. n, base = base * CF(x, 0.2, z) })
		end
	end
	out.door = world(base, 0, 3, -d / 2 + 8)
	out.npc = base * CF(-6, 0.4, d / 2 - 19)
end

function Places.reststop(m, base, poi, rng, out)
	local w, d = poi.w, poi.d
	pad(m, base, w, d, Color3.fromRGB(170, 164, 150), M.Ground)
	-- sala (open pavilion)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			Kit.part(m, V3(1.2, 11, 1.2), base * CF(-10 + sx * 9, 5.5, sz * 7), C.woodDark, M.Wood)
		end
	end
	Kit.part(m, V3(20, 0.8, 16), base * CF(-10, 1, 0), C.wood, M.WoodPlanks)
	Kit.gable(m, base * CF(-10, 0, 0), 24, 20, 6, 11, Color3.fromRGB(150, 64, 54), M.Slate)
	S.bench(m, base * CF(-10, 1.4, 4))
	-- kiosk
	Kit.part(m, V3(18, 10, 12), base * CF(14, 5, d / 2 - 10), Color3.fromRGB(236, 226, 200), M.Concrete)
	Kit.part(m, V3(20, 0.4, 6), base * CF(14, 8.4, d / 2 - 18) * Angles(rad(-8), 0, 0), Color3.fromRGB(240, 170, 40), M.Fabric, { decor = true, shadow = true })
	bigSign(m, base * CF(14, 11.4, d / 2 - 16.2), 18, 2.6, Color3.fromRGB(200, 90, 40), poi.thai, "REST STOP")
	S.tree(m, base * CF(-w / 2 + 6, 0, -d / 2 + 6), rng, "rain")
	S.tree(m, base * CF(w / 2 - 6, 0, -d / 2 + 6), rng, "banana")
	out.door = world(base, 14, 3, d / 2 - 19)
	out.npc = base * CF(18, 0.3, d / 2 - 17)
	out.extra = { { kind = "rest", pos = world(base, -10, 3, 2), action = "Rest", object = "Sala (free energy)" } }
end

return Places
