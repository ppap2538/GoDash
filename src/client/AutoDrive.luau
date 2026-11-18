-- Auto drive (owner, 2026-11-16: "add auto driving, for when it's far and I'm too tired to press").
-- Q, or the 🤖 button under the speedometer: the vehicle follows the GPS route by itself along the
-- left lane (GPS.lane), keeps its distance from traffic, people and dogs, stops at red lights (a left
-- turn on red goes on: "ซ้ายผ่านตลอด", as the fines in server/TrafficService allow), slows down for
-- corners, signals its turns and stops at the destination. Steering, the pedals or the handbrake give
-- control straight back. It never drives faster than CRUISE_MAX in town.
-- Hooked into the physics through Drive.autopilot (Drive must not require this module: HUD needs Drive).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Traffic = require(Shared.Traffic)
local Util = require(Shared.Util)
local Drive = require(script.Parent.Drive)
local GPS = require(script.Parent.GPS)
local Feedback = require(script.Parent.Feedback)
local Lang = require(script.Parent.Lang)
local Speedo = require(script.Parent.UI.HUD.Speedometer)
local Peds = require(script.Parent.Peds) -- people in the way step aside (Peds.makeWay)

local AutoDrive = {}
local player = Players.LocalPlayer

local CRUISE = 0.85 -- share of the vehicle's top speed on a clear straight road
local CRUISE_MAX = 75 -- studs/s (= km/h on the speedometer); 2026-11-17 vehicles got faster
local HORIZON = 170 -- studs of route looked at ahead
local ARRIVE = 20 -- studs from the door: close enough to press G
local BUMP_V = 20 -- studs/s (km/h on the speedometer) over a speed bump: a bounce, never a fall
local OBSTACLE_FOLDERS = { "Traffic", "GoDashLocalTraffic", "GoDashPedestrians", "GoDashDogs", "Vehicles", "NPCs" }

local Y = Vector3.yAxis
local function flat(v: Vector3): Vector3 return Vector3.new(v.X, 0, v.Z) end

-- distance from p to the segment a-b, and how far along it the nearest point is
local function segDist(p: Vector3, a: Vector3, b: Vector3): (number, number)
	local ab, ap = b - a, p - a
	local l2 = ab:Dot(ab)
	local k = l2 > 0.01 and math.clamp(ap:Dot(ab) / l2, 0, 1) or 0
	return (ap - ab * k).Magnitude, k * math.sqrt(l2)
end

---------------------------------------------------------------------------------------------------
-- traffic lights near a point (same table the server fines from)
---------------------------------------------------------------------------------------------------
local CELL = 512
local grid
local function signalNear(p: Vector3)
	if not grid then
		local graph = GPS.graph()
		if not graph then return nil end
		grid = {}
		for _, s in ipairs((Traffic.signals(graph))) do
			local k = math.floor(s.node.x / CELL) * 4096 + math.floor(s.node.z / CELL)
			grid[k] = grid[k] or {}
			table.insert(grid[k], s)
		end
	end
	local list = grid[math.floor(p.X / CELL) * 4096 + math.floor(p.Z / CELL)]
	if not list then return nil end
	for _, s in ipairs(list) do
		if (s.node.x - p.X) ^ 2 + (s.node.z - p.Z) ^ 2 < s.node.r ^ 2 then return s end
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------------------------------
local lane, hint = nil :: { Vector3 }?, 1
local smoothT = 0
local stuckFor = 0
local signalSet = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function setOn(on: boolean, why: string?, good: boolean?)
	if Drive.info.auto == on then return end
	Drive.info.auto = on
	smoothT, stuckFor, hint = 0, 0, 1
	if not on and signalSet ~= 0 then
		signalSet = 0
		if Drive.info.driving then Drive.setSignal(0) end
	end
	if why then Feedback.toast(why, good and "good" or (on and "good" or nil)) end
	Feedback.click()
end

function AutoDrive.toggle()
	if Drive.info.auto then
		setOn(false, Lang.pick("🤖 Auto drive off", "🤖 ปิดขับอัตโนมัติแล้ว"))
		return
	end
	if not Drive.info.driving then
		Feedback.toast(Lang.pick("🤖 Get on a vehicle first", "🤖 ขึ้นรถก่อนนะ แล้วค่อยเปิดขับอัตโนมัติ"), "bad")
		return
	end
	if not GPS.target() then
		Feedback.toast(Lang.pick("🤖 Pick a destination first: accept a job, or tap Go on a place in Maps",
			"🤖 เลือกที่หมายก่อน: รับงาน หรือกด \"ไป\" ที่สถานที่ในแอปแผนที่"), "bad")
		return
	end
	setOn(true, Lang.pick("🤖 Auto drive on: following the route. Steer or brake to take over",
		"🤖 เปิดขับอัตโนมัติ: รถขับตามเส้นทางเอง กดเลี้ยว/เบรกเมื่อไหร่ก็คุมเองได้ทันที"))
end

---------------------------------------------------------------------------------------------------
-- the route ahead: samples { pos, s } from the point nearest the vehicle
---------------------------------------------------------------------------------------------------
local function ahead(L: { Vector3 }, pos: Vector3)
	local n = #L
	local from, to = math.max(1, hint - 4), math.min(n - 1, hint + 60)
	local bi, bk, bd = from, 0, math.huge
	for i = from, to do
		local a, b = L[i], L[i + 1]
		local ab, ap = flat(b - a), flat(pos - a)
		local l2 = ab:Dot(ab)
		local k = l2 > 0.01 and math.clamp(ap:Dot(ab) / l2, 0, 1) or 0
		local d = (ap - ab * k).Magnitude
		if d < bd then bi, bk, bd = i, k, d end
	end
	hint = bi
	local first = L[bi]:Lerp(L[bi + 1], bk)
	local samples = { { pos = flat(first), s = 0 } }
	local s = 0
	local prev = flat(first)
	for i = bi + 1, n do
		local p = flat(L[i])
		s += (p - prev).Magnitude
		table.insert(samples, { pos = p, s = s })
		prev = p
		if s > HORIZON then break end
	end
	local reachesEnd = samples[#samples].s <= HORIZON
	return samples, bd, reachesEnd
end

local function at(samples, s: number): Vector3
	for i = 2, #samples do
		local a, b = samples[i - 1], samples[i]
		if b.s >= s then
			local k = (b.s > a.s) and (s - a.s) / (b.s - a.s) or 1
			return a.pos:Lerp(b.pos, k)
		end
	end
	return samples[#samples].pos
end

---------------------------------------------------------------------------------------------------
-- obstacles: rays along the way the route goes
---------------------------------------------------------------------------------------------------
local function isObstacle(inst: Instance): boolean
	for _, name in ipairs(OBSTACLE_FOLDERS) do
		local f = Workspace:FindFirstChild(name)
		if f and inst:IsDescendantOf(f) then return true end
	end
	local m = inst:FindFirstAncestorOfClass("Model")
	return m ~= nil and m:FindFirstChildOfClass("Humanoid") ~= nil
end

local function clearAhead(c, origin: Vector3, dir: Vector3, side: Vector3, length: number, halfW: number, groundY: number): (number, boolean)
	local best, person = math.huge, false
	local rows = {
		{ 0, groundY + 1.1 }, { 0, groundY + 2.6 }, { halfW, groundY + 2.2 }, { -halfW, groundY + 2.2 },
	}
	for _, r in ipairs(rows) do
		local o = Vector3.new(origin.X, r[2], origin.Z) + side * r[1]
		local hit = Workspace:Raycast(o, dir * length, rayParams)
		if hit then
			if isObstacle(hit.Instance) then
				if hit.Distance < best then
					best = hit.Distance
					local m = hit.Instance:FindFirstAncestorOfClass("Model")
					person = m ~= nil and m:FindFirstChildOfClass("Humanoid") ~= nil
				end
			elseif hit.Distance < 2.5 + c.apV * 0.12 and r[1] == 0 and r[2] > groundY + 2 then
				best = math.min(best, hit.Distance) -- a wall right in front: stop rather than hit it
			end
		end
	end
	return best, person
end

---------------------------------------------------------------------------------------------------
-- the driver
---------------------------------------------------------------------------------------------------
local function control(c, ctx): (number?, number?, boolean?)
	-- the player takes over
	if math.abs(ctx.manualS) > 0.3 or math.abs(ctx.manualT) > 0.3 or ctx.manualH then
		setOn(false, Lang.pick("🤖 Auto drive off: you're driving", "🤖 ปิดขับอัตโนมัติ: คุณคุมรถเองแล้ว"))
		return nil
	end
	local t = GPS.target()
	if not t then
		-- the destination was reached (a waypoint clears itself 40 studs out) or cleared: stop, then hand over
		if math.abs(ctx.speedF) > 1.2 then return (ctx.speedF > 0 and -0.55 or 0.55), 0, false end
		setOn(false, Lang.pick("📍 Arrived. Auto drive off", "📍 ถึงที่หมายแล้ว ปิดขับอัตโนมัติ"), true)
		return 0, 0, true
	end
	if not c.def.pedal and (c.model:GetAttribute("Fuel") or 0) <= 0 then
		setOn(false, Lang.pick("⛽ Out of fuel. Auto drive off", "⛽ น้ำมันหมด ปิดขับอัตโนมัติ"))
		return nil
	end
	local L = GPS.lane
	if L ~= lane then lane, hint = L, 1 end
	if not L or #L < 2 then return 0, 0, false end -- route being worked out: wait

	local pos = c.chassis.Position
	local v = ctx.speedF
	c.apV = math.abs(v)
	local stats = c.stats
	local top = math.min(stats.topSpeed * CRUISE, CRUISE_MAX)
	local decel = math.max(10, stats.brake * 0.55)
	local lat = math.max(6, stats.grip * 1.1)
	if not c.apSize then
		local size = c.model:GetExtentsSize()
		c.apSize = Vector2.new(math.max(size.X, 1.5), math.max(size.Z, 3))
	end
	local halfW, halfL = c.apSize.X / 2, c.apSize.Y / 2

	local samples, off, reachesEnd = ahead(L, pos)
	local vT = top

	-- arriving: follow the lane to its end (the road beside the door), then creep up to the door itself
	-- until it is near enough to pick up / deliver (the server allows Game.INTERACT_RANGE + 6 = 32)
	local toEnd = reachesEnd and samples[#samples].s or math.huge
	local toDoor = Util.flatDist(pos, t.pos)
	if toDoor <= ARRIVE and c.apV < 2.5 then
		setOn(false, Lang.pick("📍 Arrived. Auto drive off", "📍 ถึงที่หมายแล้ว ปิดขับอัตโนมัติ"), true)
		return 0, 0, true
	end
	local lastStretch = toEnd < 10 and toDoor > ARRIVE
	if lastStretch then
		vT = math.min(vT, 6, math.sqrt(2 * decel * math.max(0, toDoor - ARRIVE + 1)))
	elseif reachesEnd then
		vT = math.min(vT, math.sqrt(2 * decel * math.max(0, toEnd - 3)))
	end

	-- corners: slow enough at each bend to get round it, braking early enough to get there
	local turnSoon = 0
	for i = 2, #samples - 1 do
		local a, b, d = samples[i - 1], samples[i], samples[i + 1]
		local d1, d2 = b.pos - a.pos, d.pos - b.pos
		if d1.Magnitude > 0.5 and d2.Magnitude > 0.5 then
			local cosT = math.clamp(d1.Unit:Dot(d2.Unit), -1, 1)
			local theta = math.acos(cosT)
			if theta > math.rad(12) then
				local r = math.min(math.min(d1.Magnitude, d2.Magnitude) / 2, 16) / math.tan(theta / 2)
				local vc = math.clamp(math.sqrt(lat * math.max(r, 2)), 6, top)
				vT = math.min(vT, math.sqrt(vc * vc + 2 * decel * math.max(0, b.s - 4)))
				if turnSoon == 0 and theta > math.rad(40) and b.s < 30 + c.apV then
					turnSoon = (d1.Unit:Cross(d2.Unit).Y > 0) and -1 or 1 -- left / right (Y up: a positive cross turns left here)
				end
			end
		end
	end

	-- speed bumps on the route (client/SpeedBumps): ease down to a gentle bounce before each one
	-- (2026-11-18 long-delivery test: auto drive hit one at 59 km/h in a KKU lane and the rider came off)
	local bumps = Workspace:FindFirstChild("GoDashSpeedBumps")
	if bumps then
		local here = flat(pos)
		for _, p in ipairs(bumps:GetChildren()) do
			if p:IsA("BasePart") then
				local bp = flat(p.Position)
				if (bp - here).Magnitude < 90 then
					for i = 2, #samples do
						local a, b = samples[i - 1], samples[i]
						if a.s > 90 then break end
						local d, along = segDist(bp, a.pos, b.pos)
						if d < 4 then
							local sB = a.s + along
							vT = math.min(vT, math.sqrt(BUMP_V * BUMP_V + 2 * decel * math.max(0, sB - halfL - 3)))
							break
						end
					end
				end
			end
		end
	end

	-- police checkpoint on the route (server/PoliceService): stop well before it and hand over, so the
	-- player can choose a way round (the owner wants them avoided, not driven through for you)
	if not c.def.pedal then
		for _, cp in ipairs(GPS.checkpoints()) do
			local cpos = flat(cp.pos)
			if (cpos - flat(pos)).Magnitude < HORIZON then
				for i = 2, #samples do
					local a, b = samples[i - 1], samples[i]
					if a.s > 120 then break end
					local d, along = segDist(cpos, a.pos, b.pos)
					if d < cp.width / 2 + 4 then
						local sCp = a.s + along
						vT = math.min(vT, math.sqrt(2 * decel * math.max(0, sCp - 26)))
						if sCp < 34 and c.apV < 2 then
							setOn(false, Lang.pick("🚨 Police checkpoint ahead! Auto drive off: find a way round (another street, or over the pavement)",
								"🚨 ด่านตรวจข้างหน้า! ปิดขับอัตโนมัติ หาทางหลบเอง (ถนนอื่น หรือขึ้นทางเท้าอ้อม)"))
							return 0, 0, true
						end
						break
					end
				end
			end
		end
	end

	-- traffic lights on the way: stop unless it is green, or the turn there is a left one
	for i = 1, #samples do
		local sm = samples[i]
		local sig = signalNear(sm.pos)
		if sig then
			local node = sig.node
			local npos = Vector3.new(node.x, 0, node.z)
			local toNode = sm.s + (npos - sm.pos).Magnitude
			if Util.flatDist(pos, npos) > node.r + 1.5 then -- not inside it already (then: clear it)
				local before = i > 1 and samples[i - 1].pos or flat(pos)
				local inDir = flat(npos - before)
				if inDir.Magnitude < 0.5 then inDir = flat(ctx.fwd) end
				inDir = inDir.Unit
				local edge, bestDot = nil, -2
				for _, l in ipairs(node.links) do
					local dot = ((l.to.x - node.x) * -inDir.X + (l.to.z - node.z) * -inDir.Z) / l.len
					if dot > bestDot then edge, bestDot = l.edge, dot end
				end
				local exitPt = at(samples, toNode + node.r + 6)
				local outDir = flat(exitPt - npos)
				local left = outDir.Magnitude > 1 and outDir.Unit:Dot(inDir:Cross(Y)) < -0.45
				if edge and not edge.minor and not left and sig.groups[edge] ~= nil then -- (no light on pieces inside a junction)
					-- (2026-11-19) go on only when the junction (the r + 3 line server/TrafficService checks)
					-- is reached before the light turns red; it used to go on any yellow it could not stop
					-- for, and a long yellow-to-red approach got the rider a red-light ticket
					local col, _, leftT = Traffic.timing(node.id, sig.groups[edge], Workspace:GetServerTimeNow())
					local stopAt = toNode - node.r - 5
					local canStop = stopAt > c.apV * c.apV / (2 * decel * 1.4)
					local tLine = math.max(0, toNode - node.r - 3) / math.max(c.apV, 1)
					local untilRed = col == "green" and leftT + Traffic.YELLOW or (col == "yellow" and leftT or 0)
					if col == "red" or (canStop and tLine > untilRed - 0.6) then
						vT = math.min(vT, stopAt < 0.8 and 0 or math.sqrt(2 * decel * stopAt))
					end
				end
			end
			break
		end
	end

	-- steering: pure pursuit on a point ahead along the lane
	local look = math.clamp(6 + c.apV * 0.45, 7, 26)
	local aim = lastStretch and flat(t.pos) or at(samples, look)
	local rel = flat(aim - pos)
	local x, z = rel:Dot(ctx.right), rel:Dot(ctx.fwd)
	local alpha = math.atan2(x, z)
	local delta = math.atan(2 * c.wheelbase * math.sin(alpha) / math.max(rel.Magnitude, 4))
	local steer = math.clamp(delta / math.max(ctx.maxAngle, 0.05), -1, 1)
	if math.abs(alpha) > math.rad(75) then vT = math.min(vT, 6) end -- facing the wrong way: turn round slowly
	if off > 14 then vT = math.min(vT, 14) end -- well off the line: get back to it first

	-- keep the distance: traffic, people and dogs in the way the route goes
	local dir = rel.Magnitude > 0.5 and rel.Unit or flat(ctx.fwd).Unit
	local side = dir:Cross(Y)
	rayParams.FilterDescendantsInstances = { c.model, player.Character, Workspace:FindFirstChild("GoDashGPS") }
	local front = flat(pos) + flat(ctx.fwd).Unit * (halfL + 0.4)
	local groundY = ctx.cf.Position.Y - (c.ride or 2)
	local reach = c.apV * c.apV / (2 * decel) + 10
	local gap, person = clearAhead(c, front, dir, side, reach, math.max(halfW - 0.2, 0.4), groundY)
	-- someone walking in the way and not moving off: a short polite toot and they step aside
	if person and gap < 30 then
		c.apPersonFor = (c.apPersonFor or 0) + ctx.dt
		if c.apPersonFor > 1 and os.clock() - (c.apMadeWay or 0) > 2.5 then
			c.apMadeWay = os.clock()
			Peds.makeWay(front, dir, halfW, gap + 8)
			if c.audio and c.audio.horn and os.clock() - (c.apHonk or 0) > 6 then
				c.apHonk = os.clock()
				c.audio:horn()
			end
		end
	else
		c.apPersonFor = 0
	end
	if gap < math.huge then
		vT = math.min(vT, math.max(0, (gap - (person and 4.5 or 3.5)) * 1.3))
		if lastStretch and gap < 8 and c.apV < 1 then -- a wall or kerb before the door: this is as close as it gets
			setOn(false, Lang.pick("📍 Arrived. Auto drive off", "📍 ถึงที่หมายแล้ว ปิดขับอัตโนมัติ"), true)
			return 0, 0, true
		end
	end

	-- give up when truly stuck (wanting to go, not moving, nothing in the way)
	if vT > 4 and c.apV < 0.8 and gap == math.huge then
		stuckFor += ctx.dt
		if stuckFor > 7 then
			setOn(false, Lang.pick("🤖 Auto drive is stuck here, please take over", "🤖 รถติดอยู่ ขับออกเองก่อนนะ"))
			return nil
		end
	else
		stuckFor = 0
	end

	-- turn signals: on before a real turn, off after it
	if turnSoon ~= signalSet and Drive.info.signal ~= 2 then
		signalSet = turnSoon
		Drive.setSignal(turnSoon)
	end

	-- pedals: gentle, so passengers rate the ride as smooth
	local want
	if vT < 0.5 and c.apV < 1.2 then
		want = 0
	elseif c.apV > vT + 0.8 then
		want = -math.clamp((c.apV - vT) * 0.22, 0.15, 1)
	else
		want = math.clamp((vT - c.apV) * 0.28, 0, 1)
	end
	smoothT += (want - smoothT) * math.min(1, ctx.dt * 6)
	return smoothT, steer, vT < 0.5 and c.apV < 1.2
end

function AutoDrive.start()
	Drive.autopilot = control
	Speedo.onAuto = AutoDrive.toggle
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Q then AutoDrive.toggle() end
	end)
	-- a police checkpoint coming up ahead: say so in time to turn off (motor vehicles; bicycles go free)
	task.spawn(function()
		local warned = {}
		while true do
			task.wait(0.3)
			local char = player.Character
			local r = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r and Drive.info.driving and not Drive.info.pedal then
				local vel = flat(r.AssemblyLinearVelocity)
				if vel.Magnitude > 4 then
					for _, cp in ipairs(GPS.checkpoints()) do
						local rel = flat(cp.pos - r.Position)
						local d = rel.Magnitude
						if d < 140 and d > 12 and rel.Unit:Dot(vel.Unit) > 0.6 then
							local key = math.floor(cp.pos.X) .. ":" .. math.floor(cp.pos.Z)
							if not warned[key] or os.clock() - warned[key] > 40 then
								warned[key] = os.clock()
								Feedback.toast(Lang.pick("🚨 Police checkpoint ahead! Turn off, or go round on the pavement, or pay ฿150",
									"🚨 ด่านตรวจข้างหน้า! เลี้ยวหลบ หรือขึ้นทางเท้าอ้อม ไม่งั้นโดนปรับ ฿150"), "bad")
							end
						end
					end
				end
			end
		end
	end)
end

return AutoDrive
