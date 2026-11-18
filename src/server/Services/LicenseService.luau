-- The driving test (owner, 2026-11-17: Thai society satire: the queue at the transport office, the
-- famous test course). At the bus terminal ("ขนส่ง") take a queue ticket (no. 999, now serving 12:
-- three hours later...), then ride the course outside town on your own vehicle:
--   motorbike: the narrow plank (a wheel touching the ground = fail), the slalom (alternate sides,
--              touch no cone), stop inside the box
--   car:       a wider slalom, stop inside the box
-- Pass: a licence for that class (profile licence.bike / licence.car). A checkpoint fines a motor
-- vehicle without the licence ฿300 instead of ฿150 (server/PoliceService). Bicycles need none.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local RiderPose = require(Shared.RiderPose)
local Data = require(script.Parent.PlayerDataService)
local Kit = require(script.Parent.Parent.World.Kit)

local License = {}
local V3, CF = Vector3.new, CFrame.new
local rad = math.rad
local M = Enum.Material
local TOP = 0.24 -- the course surface, like the city's roads
local origin: CFrame
local tests = {} -- [player] = state
local coolUntil = {}

local BIKE = {
	plank = { z0 = 24, z1 = 40, x = 0, w = 1.3, h = 0.4 }, -- a low step up, like the real one (no ramp: the small engines could not climb a ramp from walking pace)
	cones = { { 0, 56 }, { 0, 69 }, { 0, 82 }, { 0, 95 } }, -- 13 apart: a weave of radius ~7, what a small bike can turn
	box = { x = 0, z0 = 106, z1 = 116, w = 6 },
	start = { x = 0, z = 4 },
}
local CAR = {
	cones = { { 26, 30 }, { 26, 52 }, { 26, 74 }, { 26, 96 } }, -- 22 apart: a car turns wide
	box = { x = 26, z0 = 112, z1 = 126, w = 9 },
	start = { x = 26, z = 6 },
}

local function toast(player: Player, en: string, th: string, bad: boolean?)
	Net.fire(player, "Notify", "toast", { text = en, th = th, bad = bad, good = not bad })
end

local function build(npc)
	local m = Instance.new("Model")
	m.Name = "DrivingTestCourse"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local o = origin
	Kit.part(m, V3(520, 1, 520), o * CF(13, TOP - 0.56, 60), Color3.fromRGB(96, 150, 70), M.Grass)
	Kit.part(m, V3(70, 1, 150), o * CF(13, TOP - 0.5, 60), Color3.fromRGB(62, 64, 68), M.Asphalt)
	local function line(x: number, z: number, w: number, l: number)
		Kit.part(m, V3(w, 0.04, l), o * CF(x, TOP + 0.02, z), Color3.fromRGB(240, 240, 235), M.SmoothPlastic, { decor = true })
	end
	-- bike lane: start box, the plank with ramps, the slalom, the stop box
	local b = BIKE
	line(b.start.x - 2.5, b.start.z, 0.2, 7); line(b.start.x + 2.5, b.start.z, 0.2, 7)
	local p = b.plank
	local stripes = 8
	for i = 0, stripes - 1 do
		local zl = (p.z1 - p.z0) / stripes
		Kit.part(m, V3(p.w, p.h, zl), o * CF(p.x, TOP + p.h / 2, p.z0 + zl * (i + 0.5)), i % 2 == 0 and Color3.fromRGB(250, 200, 30) or Color3.fromRGB(30, 30, 30), M.Wood)
	end
	local function cone(x: number, z: number)
		Kit.cyl(m, 0.9, 0.7, o * CF(x, TOP + 0.4, z), Color3.fromRGB(255, 110, 20), M.SmoothPlastic, { decor = true })
		Kit.cyl(m, 0.55, 0.7, o * CF(x, TOP + 1.1, z), Color3.fromRGB(255, 110, 20), M.SmoothPlastic, { decor = true })
		Kit.cyl(m, 0.7, 0.2, o * CF(x, TOP + 0.85, z), Color3.fromRGB(245, 245, 240), M.SmoothPlastic, { decor = true })
	end
	for _, c in ipairs(b.cones) do cone(c[1], c[2]) end
	local function box(bx)
		line(bx.x - bx.w / 2, (bx.z0 + bx.z1) / 2, 0.25, bx.z1 - bx.z0)
		line(bx.x + bx.w / 2, (bx.z0 + bx.z1) / 2, 0.25, bx.z1 - bx.z0)
		line(bx.x, bx.z0, bx.w, 0.25); line(bx.x, bx.z1, bx.w, 0.25)
		local t = Kit.part(m, V3(bx.w - 1, 0.03, 2), o * CF(bx.x, TOP + 0.03, (bx.z0 + bx.z1) / 2), Color3.fromRGB(250, 200, 30), M.SmoothPlastic, { decor = true })
		Kit.sign(t, "STOP", { face = Enum.NormalId.Top, bg = Color3.fromRGB(250, 200, 30), color = Color3.new(0, 0, 0), pps = 30 })
	end
	box(b.box)
	-- car lane
	for _, c in ipairs(CAR.cones) do cone(c[1], c[2]) end
	box(CAR.box)
	line(CAR.start.x - 4, CAR.start.z, 0.2, 9); line(CAR.start.x + 4, CAR.start.z, 0.2, 9)
	-- the office tent, the examiner and the board of rules
	local t = o * CF(-14, TOP, 8)
	for _, q in ipairs({ { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 } }) do Kit.part(m, V3(0.2, 6, 0.2), t * CF(q[1], 3, q[2]), Color3.fromRGB(200, 200, 205), M.Metal) end
	Kit.part(m, V3(7, 0.3, 7), t * CF(0, 6.1, 0), Color3.fromRGB(40, 110, 190), M.Fabric)
	local val = Kit.part(m, V3(7, 1, 0.1), t * CF(0, 5.4, -3.5), Color3.fromRGB(40, 110, 190), M.Fabric, { decor = true })
	Kit.sign(val, "สนามสอบใบขับขี่ (สมมติ)", { face = Enum.NormalId.Front, bg = Color3.fromRGB(40, 110, 190), light = true, pps = 30 })
	Kit.part(m, V3(4, 0.15, 1.6), t * CF(0, 2.5, 0), Color3.fromRGB(245, 245, 245), M.SmoothPlastic)
	local names = npc.pedNames()
	if #names > 0 then
		local fig = npc.figure(t * CF(0, 0, 1.6) * CFrame.Angles(0, rad(180), 0), names[1], "stand")
		if fig then RiderPose.dress(fig.model, Color3.fromRGB(150, 190, 230), Color3.fromRGB(40, 50, 80)); fig.model.Parent = m end
	end
	local rules = Kit.part(m, V3(6, 3.4, 0.15), o * CF(-8, TOP + 3, 22) * CFrame.Angles(0, rad(90), 0), Color3.fromRGB(255, 255, 255), M.SmoothPlastic, { decor = true })
	Kit.sign(rules, "กติกา: ทางแคบ ล้อห้ามแตะพื้น", { face = Enum.NormalId.Front, bg = Color3.fromRGB(255, 255, 255), sub = "ซิกแซกสลับข้าง ห้ามชนกรวย · จอดในกรอบ", color = Color3.fromRGB(200, 30, 30), light = true, pps = 30 })
	m.Parent = Workspace
end

local function local3(pos: Vector3): Vector3
	return origin:PointToObjectSpace(pos)
end

local function placeAndSeat(player: Player, vehicles, id: string, cf: CFrame)
	local v = vehicles.spawnAt(player, id, cf)
	if not v then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if char and hum then
		hum.Sit = false
		char:PivotTo(v.seat.CFrame * CF(0, 3, 0))
		task.wait(0.3)
		v.seat:Sit(hum)
	end
	return true
end

function License.has(player: Player, class: string): boolean
	local d = Data.get(player)
	return d ~= nil and d.licence ~= nil and d.licence[class] == true
end

function License.start(world, deps)
	local vehicles, npc = deps.vehicles, deps.npc
	-- the course: off the edge of town
	local maxZ, midX = -math.huge, 0
	for _, n in ipairs(world.graph.nodes) do
		if n.z > maxZ then maxZ, midX = n.z, n.x end
	end
	origin = CF(midX, 0, maxZ + 900)
	build(npc)
	local terminal = world.pois.bus
	if not terminal then warn("[Licence] no bus terminal: no test") return end
	npc.prompt(terminal.door + V3(4, 0, 0), "Driving licence test", "Transport Office", "licence", "licence")
	print("[Licence] test course at " .. tostring(origin.Position))

	local function finish(player: Player, st, passed: boolean, whyEn: string?, whyTh: string?)
		tests[player] = nil
		local d = Data.get(player)
		if passed and d then
			d.licence[st.class] = true
			Data.touch(player, "licence")
			require(script.Parent.StoreService).badge(player, "licence")
			Net.fire(player, "Notify", "licence", { stage = "pass", class = st.class })
			Net.fire(player, "Notify", "feed", { key = "licence_pass" })
		else
			coolUntil[player] = os.clock() + 25
			Net.fire(player, "Notify", "licence", { stage = "fail", class = st.class, why = { en = whyEn, th = whyTh } })
			Net.fire(player, "Notify", "feed", { key = "licence_fail" })
		end
		task.delay(4.5, function()
			if player.Parent and st.vehicleId then
				-- back to the bus terminal, on the road beside it
				local e, p = world.graph:nearest(terminal.door)
				if e then
					local dir = V3(e.b.pos.X - e.a.pos.X, 0, e.b.pos.Z - e.a.pos.Z).Unit
					local side = dir:Cross(Vector3.yAxis)
					local at = V3(p.X, 0.3, p.Z) + side * (e.def.width / 2 - 4)
					placeAndSeat(player, vehicles, st.vehicleId, CFrame.lookAt(at, at + dir))
				end
			end
		end)
	end

	npc.handle("licence", function(player)
		if tests[player] then return end
		local d = Data.get(player)
		local v = vehicles.get(player)
		if not d then return end
		if not v then return toast(player, "Bring out the vehicle you want a licence for first (Garage app)", "เรียกรถที่จะสอบออกมาก่อนนะ (แอปโรงรถ)", true) end
		if v.def.pedal then return toast(player, "A bicycle needs no licence. Come back on a motorbike or a car", "จักรยานไม่ต้องมีใบขับขี่ ขี่มอไซค์หรือรถยนต์มาสอบนะ", true) end
		local class = v.def.class == "car" and "car" or "bike"
		if d.licence[class] then return toast(player, "You already have this licence", "มีใบขับขี่ประเภทนี้แล้ว") end
		if os.clock() < (coolUntil[player] or 0) then return toast(player, "Practise a little first. Come back in a moment", "ไปซ้อมก่อนนะ แล้วค่อยกลับมาสอบใหม่", true) end
		local st = { class = class, vehicleId = v.id, started = 0, step = 1, lastZ = nil, lastSide = 0, coneI = 1, offPlank = 0 }
		tests[player] = st
		Net.fire(player, "Notify", "licence", { stage = "queue" })
		task.delay(4.6, function()
			if tests[player] ~= st or not player.Parent then return end
			local course = class == "car" and CAR or BIKE
			local at = origin * CF(course.start.x, 0.3, course.start.z)
			if not placeAndSeat(player, vehicles, st.vehicleId, CFrame.lookAt(at.Position, at.Position + origin.LookVector * -1)) then
				tests[player] = nil
				return
			end
			st.started = os.clock()
			Net.fire(player, "Notify", "licence", { stage = "start", class = class })
		end)
	end)

	-- the examiner's eye: ten times a second
	Players.PlayerRemoving:Connect(function(p) tests[p] = nil; coolUntil[p] = nil end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			for player, st in pairs(tests) do
				if st.started > 0 then
					local v = vehicles.driving(player)
					if not v then
						if os.clock() - st.started > 2 then finish(player, st, false, "You got off the vehicle", "ลงจากรถระหว่างสอบ") end
					else
						local course = st.class == "car" and CAR or BIKE
						local p = local3(v.chassis.Position)
						local x, z = p.X, p.Z -- the course runs along +Z from the origin
						local speed = vehicles.speed(player)
						if os.clock() - st.started > 150 then finish(player, st, false, "Out of time", "หมดเวลา")
						elseif math.abs(x - 13) > 60 or z < -20 or z > 140 then finish(player, st, false, "You left the course", "ออกนอกสนามสอบ")
						else
							-- 1 (bike): the plank
							if st.class == "bike" and st.step == 1 then
								local pl = course.plank
								if z > pl.z0 + 3 and z < pl.z1 - 3 then
									-- (the suspension bounces after the ramp: only a real drop counts)
									local high = v.chassis.Position.Y > (st.baseY or v.chassis.Position.Y) + pl.h * 0.35
									if math.abs(x - pl.x) > pl.w / 2 + 0.6 or not high then
										st.offPlank += 0.1
										if st.offPlank > 0.35 then finish(player, st, false, "A wheel touched the ground on the narrow plank", "ล้อแตะพื้นตอนขึ้นทางแคบ") end
									else
										st.offPlank = math.max(0, st.offPlank - 0.05)
									end
								elseif z <= pl.z0 - 4 then
									st.baseY = v.chassis.Position.Y -- the height on flat ground, before the ramp
								elseif z >= pl.z1 + 3 then
									st.step = 2
									Net.fire(player, "Notify", "licence", { stage = "step", n = 1 })
								end
							end
							-- the slalom
							local slalomStep = st.class == "bike" and 2 or 1
							if tests[player] == st and st.step == slalomStep then
								for _, c in ipairs(course.cones) do
									if (V3(x, 0, z) - V3(c[1], 0, c[2])).Magnitude < 1.25 then
										finish(player, st, false, "You hit a cone", "ชนกรวย")
										break
									end
								end
								local c = course.cones[st.coneI]
								if tests[player] == st and c and st.lastZ and st.lastZ < c[2] and z >= c[2] then
									local side = (x >= c[1]) and 1 or -1
									if side == st.lastSide then
										finish(player, st, false, "Not a slalom: you passed two cones on the same side", "ซิกแซกไม่ถูก: ผ่านกรวยข้างเดียวกันสองครั้ง")
									else
										st.lastSide = side
										st.coneI += 1
										if st.coneI > #course.cones then
											st.step = slalomStep + 1
											Net.fire(player, "Notify", "licence", { stage = "step", n = slalomStep })
										end
									end
								end
							end
							-- stop in the box
							if tests[player] == st and st.step == (st.class == "bike" and 3 or 2) then
								local bx = course.box
								local inside = math.abs(x - bx.x) < bx.w / 2 - 0.4 and z > bx.z0 + 0.6 and z < bx.z1 - 0.6
								if inside and speed < 0.8 then
									finish(player, st, true)
								elseif z > bx.z1 + 4 then
									finish(player, st, false, "You didn't stop inside the box", "จอดไม่อยู่ในกรอบ")
								end
							end
						end
						st.lastZ = z
					end
				end
			end
		end
	end)
	local _ = Util
end

return License
