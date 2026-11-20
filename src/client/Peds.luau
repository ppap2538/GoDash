-- Pedestrians: people walking slowly along the pavements and the edges of the sois around the
-- player. They stop now and then, pick another street at corners and chat when spoken to. They
-- live on the client only, so the count is set per device and they cost the server nothing.
--
-- They are moved along the street by this script (no physics): until 2026-11-16 they were
-- physical Humanoids that tripped over street furniture, ran, and cut across junctions, and they
-- only knew streets with a sidewalk, so the sois (most of the town) were empty.
--
-- 2026-11-18 (owner: "people should follow the time of day"): how many are out follows the hour (busy at
-- breakfast, lunch and after school, quiet late at night), and many of them gather where something is
-- going on at that hour: pupils in uniform at the school gates in the morning and after school, the
-- fresh market at dawn, offices and hospitals in the day, the night market and the walking street in
-- the evening. Joggers run round the lake promenades at dawn and dusk, and people cross at the zebra
-- crossings in front of schools and hospitals: drive over one while someone is on it and the police
-- fine you (server/TrafficService "ZebraRun"; AI traffic already stops for them).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rig = require(Shared.Rig)
local Net = require(Shared.Net)
local Dialogue = require(Shared.Config.Dialogue)
local RiderPose = require(Shared.RiderPose)
local GPS = require(script.Parent.GPS)
local Feedback = require(script.Parent.Feedback)
local Perf = require(script.Parent.Perf)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local L = Lang.pick

local Peds = {}
local player = Players.LocalPlayer
-- how many people this device shows (phones and tablets fewer). 2026-11-17 owner: "too few, and they
-- run; I want them walking normally": more people in a tighter ring around the player, and the walk
-- animation now plays at the pace they really move.
-- (2026-11-19, owner: "too many cars and people on the street, they walk all over, hard to get past"; "people
-- and cars suddenly warp") fewer people (60 -> 40, phones 30 -> 20), and nobody appears or vanishes where you
-- can see it: they start beyond SPAWN_MIN and off screen, and are only taken away once out of view
local COUNT = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and 20 or 40
local SPAWN_MIN, SPAWN_RADIUS, DESPAWN = 140, 320, 420
-- on screen and within `within` studs of the camera?
local function inView(pos: Vector3, within: number): boolean
	local cam = Workspace.CurrentCamera
	if not cam then return false end
	if (pos - cam.CFrame.Position).Magnitude > within then return false end
	local _, on = cam:WorldToViewportPoint(pos + Vector3.new(0, 2.5, 0))
	return on
end
-- Roblox's current R15 walk: its steps match about 6.4 studs/s at normal height. (The old 507777826
-- walk, sped up, made the legs go about twice as fast as the body moved, which read as jogging.)
local WALK_ANIM = "rbxassetid://913402848"
local WALK_NATURAL = 6.4
local IDLE_ANIM = "rbxassetid://507766666" -- Roblox's own R15 idle
local RUN_ANIM = "rbxassetid://913376220" -- Roblox's own R15 run (its stride fits 16 studs/s)
local folder
local rng = Random.new()
local all = {} -- every pedestrian state (client/Accident looks for one in front of your vehicle)
local animHook = nil :: ((any, string, number, boolean?) -> ())? -- set by startAvatars: plays a person's walk / run / idle

---------------------------------------------------------------------------------------------------
-- the hour of the day
---------------------------------------------------------------------------------------------------
local function hour(): number return Lighting.ClockTime end

-- share of this device's pool out on the streets at hour h
local function density(h: number): number
	if h < 5 then return 0.3 end
	if h < 6.5 then return 0.55 end
	if h < 9 then return 1 end -- school run, work, the morning market
	if h < 11 then return 0.8 end
	if h < 13.5 then return 1 end -- lunch
	if h < 16 then return 0.8 end
	if h < 19.5 then return 1 end -- after school, the evening market
	if h < 22 then return 0.75 end
	return 0.45
end

-- where people gather, by place kind: { from, to, weight }
local HOT = {
	school = { { 6.5, 8.3, 1.2 }, { 14.9, 16.9, 1.2 } },
	university = { { 7.5, 21, 0.7 } },
	market = { { 5.3, 9.5, 1.1 }, { 15.5, 18.5, 0.6 } },
	nightmarket = { { 17.3, 23.6, 1.2 } },
	hospital = { { 7, 16.5, 0.7 } },
	government = { { 8.3, 16.5, 0.6 } },
	mall = { { 10, 21.5, 0.9 } },
	station = { { 6, 21, 0.4 } },
	bus = { { 5.5, 21.5, 0.6 } },
	stadium = { { 16, 20, 0.6 } },
	museum = { { 9, 16, 0.35 } },
	restaurant = { { 11, 13.6, 0.5 }, { 17, 20.5, 0.5 } },
	cafe = { { 7, 10, 0.35 }, { 13, 16, 0.25 } },
}
local SCHOOLISH = { school = true, university = true }

local function hotNow(kind: string, h: number): number
	local list = HOT[kind]
	if not list then return 0 end
	for _, w in ipairs(list) do
		if h >= w[1] and h < w[2] then return w[3] end
	end
	return 0
end

-- active gathering places within reach of `around`: { { pos, kind, w } }
local function hotspots(around: Vector3, h: number, reach: number)
	local out, total = {}, 0
	local w = State.world
	if not w then return out, 0 end
	local function consider(kind, pos)
		if pos and kind then
			local k = hotNow(kind, h)
			if k > 0 and (Vector3.new(pos.X - around.X, 0, pos.Z - around.Z)).Magnitude < reach then
				table.insert(out, { pos = pos, kind = kind, w = k })
				total += k
			end
		end
	end
	for _, p in ipairs(w.pois or {}) do consider(p.kind, p.pos) end
	for _, s in ipairs(w.shops or {}) do consider(s.kind, s.pos) end
	return out, total
end

-- A vehicle ran into a pedestrian (client/Accident): the first person inside the vehicle's box
-- (a little margin) goes down for a few seconds, a step away from the vehicle, then gets up and
-- walks on slowly. Nobody is ever hurt for good. Returns that person's state or nil.
function Peds.hit(chassis: BasePart, halfLen: number, halfWid: number)
	local cf = chassis.CFrame
	local now = os.clock()
	for _, p in ipairs(all) do
		if p.active and p.pos and not p.scripted and not (p.downUntil and now < p.downUntil + 4) then
			local rel = cf:PointToObjectSpace(p.pos + Vector3.new(0, 2, 0))
			if math.abs(rel.X) < halfWid + 0.9 and math.abs(rel.Z) < halfLen + 0.9 and math.abs(rel.Y) < 6 then
				p.downUntil = now + 6.5
				local push = Vector3.new(p.pos.X - chassis.Position.X, 0, p.pos.Z - chassis.Position.Z)
				if push.Magnitude > 0.1 then p.pos += push.Unit * 1.6 end
				p.speed = math.max(2.2, (p.speed or 4) * 0.6) -- limping afterwards
				return p
			end
		end
	end
	return nil
end

-- People in a vehicle's way step to the side and wait a moment (2026-11-18: in the long-delivery test
-- auto drive sat behind someone walking down the middle of a narrow lane). Called by client/AutoDrive
-- when a person blocks it, and when the rider sounds the horn (H). origin = the vehicle's nose,
-- dir = where it is going (flat, unit), halfW = half its width, reach = how far ahead to look.
function Peds.makeWay(origin: Vector3, dir: Vector3, halfW: number, reach: number)
	local now = os.clock()
	local side = Vector3.new(-dir.Z, 0, dir.X)
	for _, p in ipairs(all) do
		if p.active and p.pos and p.role ~= "cross" and not p.scripted and not (p.downUntil and now < p.downUntil) then
			local rel = Vector3.new(p.pos.X - origin.X, 0, p.pos.Z - origin.Z)
			local along, lat = rel:Dot(dir), rel:Dot(side)
			if along > -3 and along < reach and math.abs(lat) < halfW + 1.8 then
				local sgn = lat >= 0 and 1 or -1 -- the side they are already on
				p.goal = p.pos + side * sgn * (halfW + 2.6 - math.abs(lat)) + dir * 0.6
				p.idleUntil = 0
				p.stepAside = now + 5
				p.avoidUntil = nil
			end
		end
	end
end

-- Take a pedestrian off the street now (the claim cutscene brings the same person over).
function Peds.vanish(p)
	if not p then return end
	p.downUntil = nil
	p.active = false
	p.scripted = nil
	if p.model then p.model.Parent = nil end
	if p.rig then p.rig.model.Parent = nil end
end

local function lying(p, root: BasePart)
	local at = p.pos + Vector3.new(0, 0.55, 0)
	local look = (p.look and p.look.Magnitude > 0.1) and p.look or Vector3.zAxis
	root.CFrame = CFrame.lookAt(at, at + Vector3.yAxis, look) -- face up, head toward where they were walking
end

local function rootPos(): Vector3?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return r and r.Position or nil
end

local function walkable(e): boolean
	return e.len > 36 and e.type ~= "highway"
end

-- Where people walk beside edge e: the middle of the sidewalk, or the edge of the road in a soi.
local function linePoint(e, s: number, side: number): Vector3
	local nx, nz = -e.dz * side, e.dx * side
	local off, y
	if e.def.walk > 0 then
		off, y = e.def.width / 2 + e.def.walk * 0.5, 0.5
	else
		off, y = e.def.width / 2 - 1.7, e.def.y
	end
	return Vector3.new(e.a.x + e.dx * s + nx * off, y, e.a.z + e.dz * s + nz * off)
end

-- Give ped p somewhere to walk to next. p.edge / p.s / p.dir / p.side describe where it is.
local function nextGoal(p)
	local e = p.edge
	local margin = 10
	local endS = p.dir > 0 and e.len - margin or margin
	if (p.dir > 0 and p.s < endS - 1) or (p.dir < 0 and p.s > endS + 1) then
		-- carry on along this street
		p.s = p.dir > 0 and math.min(p.s + 34, endS) or math.max(p.s - 34, endS)
		p.goal = linePoint(e, p.s, p.side)
		return
	end
	-- at the corner: another street (not back the way we came unless it is a dead end)
	local node = p.dir > 0 and e.b or e.a
	local options = {}
	for _, l in ipairs(node.links) do
		if l.edge ~= e and walkable(l.edge) then table.insert(options, l.edge) end
	end
	if #options == 0 then
		p.dir = -p.dir
		p.s = p.dir > 0 and margin or e.len - margin
		p.goal = linePoint(e, p.s, p.side)
		return
	end
	local ne = options[rng:NextInteger(1, #options)]
	local dir = ne.a == node and 1 or -1
	local s = dir > 0 and math.min(node.r + 12, ne.len - 4) or math.max(ne.len - node.r - 12, 4)
	-- stay on the side of the new street that is nearer, so people rarely cross the road
	local a, b = linePoint(ne, s, 1), linePoint(ne, s, -1)
	local side = (a - p.pos).Magnitude <= (b - p.pos).Magnitude and 1 or -1
	p.lookFirst = nil
	if rng:NextNumber() < 0.12 then
		side = -side -- but sometimes they do cross: looking out for traffic first (advance)
		p.lookFirst = true
	end
	p.edge, p.dir, p.s, p.side = ne, dir, s, side
	p.goal = side > 0 and a or b
end

-- A street near a gathering place that is busy now (or nil): most people out at that hour are there.
local function hotEdge(p, around: Vector3, graph)
	local h = hour()
	local spots, total = hotspots(around, h, SPAWN_RADIUS + 60)
	if total <= 0 then return nil end
	if p.student then
		-- pupils and students only gather at schools and the university
		local keep, t2 = {}, 0
		for _, s in ipairs(spots) do
			if SCHOOLISH[s.kind] then table.insert(keep, s); t2 += s.w end
		end
		spots, total = keep, t2
		if total <= 0 then return nil end
	end
	local r = rng:NextNumber() * total
	local pick = spots[1]
	for _, s in ipairs(spots) do
		r -= s.w
		if r <= 0 then pick = s break end
	end
	local options = {}
	local here = Vector3.new(around.X, 0, around.Z)
	for _, e in ipairs(graph:edgesNear(pick.pos, 80)) do
		if walkable(e) then
			local mid = Vector3.new((e.a.x + e.b.x) / 2, 0, (e.a.z + e.b.z) / 2)
			local d = (mid - here).Magnitude
			if d > SPAWN_MIN and d < DESPAWN - 50 then table.insert(options, e) end
		end
	end
	if #options == 0 then return nil end
	local e = options[rng:NextInteger(1, #options)]
	local s = (pick.pos.X - e.a.x) * e.dx + (pick.pos.Z - e.a.z) * e.dz -- along the street, near the door
	return e, math.clamp(s + rng:NextNumber(-26, 26), 8, math.max(8, e.len - 8)), pick.kind
end

local function spawnAt(p, around: Vector3): boolean
	local graph = GPS.graph()
	local hot, hotS, hotKind = nil, nil, nil
	if rng:NextNumber() < (p.student and 0.85 or 0.55) then hot, hotS, hotKind = hotEdge(p, around, graph) end
	if p.student and not hot then
		local h = hour()
		if h < 6.4 or h > 19 then return false end -- no pupils in uniform about at night
	end
	local options = {}
	if not hot then
		for _, e in ipairs(graph:edgesNear(around, SPAWN_RADIUS)) do
			if walkable(e) then
				local mid = Vector3.new((e.a.x + e.b.x) / 2, 0, (e.a.z + e.b.z) / 2)
				local d = (mid - Vector3.new(around.X, 0, around.Z)).Magnitude
				if d > SPAWN_MIN and d < SPAWN_RADIUS then table.insert(options, e) end
			end
		end
		if #options == 0 then return false end
	end
	p.role = "walk"
	p.hotKind = hotKind
	p.edge = hot or options[rng:NextInteger(1, #options)]
	p.s = hotS or rng:NextNumber(8, p.edge.len - 8)
	p.dir = rng:NextNumber() < 0.5 and 1 or -1
	p.side = rng:NextNumber() < 0.5 and 1 or -1
	p.speed = rng:NextNumber(3.6, 4.8) -- an unhurried walk (about 1 - 1.35 m/s)
	p.pos = linePoint(p.edge, p.s, p.side)
	p.look = Vector3.new(p.edge.dx, 0, p.edge.dz) * p.dir
	p.idleUntil = 0
	p.goal = nil
	nextGoal(p)
	return true
end

-- Stepping aside (2026-11-18, owner: people walked through lamp posts; "everything should be real,
-- like stepping out of the way"). Every ~0.2 s a walker looks AVOID_LOOK studs ahead along its way with a
-- body-sized sphere against everything solid (posts, stalls, tables, trees, parked bikes, players):
-- something there -> it veers to the open side (the shop side first: posts stand at the kerb) until
-- the straight way is clear again, then drifts back to its line. Someone coming the other way: both
-- keep left, as people do here. Boxed in: wait a moment, then turn back.
local AVOID_LOOK, AVOID_R, AVOID_NEAR = 4.5, 0.95, 180
local avoidParams = RaycastParams.new()
avoidParams.FilterType = Enum.RaycastFilterType.Exclude
avoidParams.RespectCanCollide = true
local avoidFilterAt = 0

local function blockedFrom(from: Vector3, dir: Vector3, len: number): boolean
	return Workspace:Spherecast(from, AVOID_R, dir * len, avoidParams) ~= nil
end

local function turnBack(p)
	local e = p.edge
	if not e then return end
	local s = (p.pos.X - e.a.x) * e.dx + (p.pos.Z - e.a.z) * e.dz
	p.dir = -p.dir
	p.s = math.clamp(s, 0, e.len)
	p.avoidUntil = nil
	nextGoal(p)
end

local function steer(p, dir: Vector3, now: number)
	if now > avoidFilterAt then
		avoidFilterAt = now + 2
		avoidParams.FilterDescendantsInstances = { folder }
	end
	local right = dir:Cross(Vector3.yAxis)
	-- another walker (or one standing, or lying after a knock) in the way
	for _, q in ipairs(all) do
		if q ~= p and q.active and q.pos then
			local d = q.pos - p.pos
			local ahead = d.X * dir.X + d.Z * dir.Z
			if ahead > 0.3 and ahead < 3.4 then
				local lat = d.X * right.X + d.Z * right.Z
				if math.abs(lat) < 1.6 then
					-- keep left; but when they are already off to our left, pass them on the right
					p.avoid = lat < -0.4 and 0.9 or -0.9
					p.avoidUntil = now + 0.5
					return
				end
			end
		end
	end
	local from = p.pos + Vector3.new(0, 2, 0)
	if not blockedFrom(from, dir, AVOID_LOOK) then
		p.stuck = 0
		return
	end
	-- the shop side of the street first, unless we are already passing on a side that is still open
	local first = 1
	local e = p.edge
	if e then
		local house = Vector3.new(-e.dz * p.side, 0, e.dx * p.side)
		first = house:Dot(right) > 0 and 1 or -1
	end
	if p.avoidUntil and now < p.avoidUntil + 0.3 and p.avoid and p.avoid ~= 0 then first = p.avoid > 0 and 1 or -1 end
	for _, sg in ipairs({ first, -first }) do
		for _, off in ipairs({ 1.9, 3.1 }) do
			local side = right * sg * off
			if not blockedFrom(from, right * sg, off) and not blockedFrom(from + side - dir * 0.5, dir, AVOID_LOOK) then
				p.avoid = sg * (off > 2 and 1.5 or 1.05)
				p.avoidUntil = now + 0.6
				p.stuck = 0
				return
			end
		end
	end
	-- boxed in: wait a moment (someone may move), then go back the way we came
	p.stuck = (p.stuck or 0) + 1
	if p.stuck >= 2 then
		p.stuck = 0
		turnBack(p)
	else
		p.idleUntil = now + rng:NextNumber(0.8, 1.6)
	end
end

---------------------------------------------------------------------------------------------------
-- Watching the traffic (2026-11-19, owner: "people walk as if the cars were not there; they should get
-- out of the way a little"). Every ~0.12 s the vehicles near the camera are listed with their speed (a
-- physics vehicle's own velocity, or how far a scripted AI car moved since the last look). Someone
-- standing in the strip a vehicle will cover in the next DODGE_AHEAD seconds steps out of it to the open
-- side (hurrying, or jumping when it is already close, with a start), turns to watch it go by, then
-- carries on. Someone about to cross a street looks both ways first and waits while something comes.
---------------------------------------------------------------------------------------------------
local DODGE_AHEAD, DODGE_MARGIN, WATCH_R = 2.3, 1.15, 160
local VEHICLE_FOLDERS = { "Vehicles", "Traffic", "GoDashLocalTraffic" }
local movers = {} -- this look's moving vehicles: { model, pos, dir, speed, hw, hl, mine }
local lastSeen = setmetatable({}, { __mode = "k" }) :: { [Model]: { pos: Vector3, t: number } }
local extents = setmetatable({}, { __mode = "k" }) :: { [Model]: Vector3 }
local moverAt = 0
local shoutAt = 0

local function scanMovers(now: number, camPos: Vector3)
	table.clear(movers)
	local myModel
	do
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		myModel = seat and seat:FindFirstAncestorWhichIsA("Model")
	end
	for _, fname in ipairs(VEHICLE_FOLDERS) do
		local f = Workspace:FindFirstChild(fname)
		if not f then continue end
		for _, m in ipairs(f:GetChildren()) do
			if not m:IsA("Model") then continue end
			local pos = m:GetPivot().Position
			if (pos - camPos).Magnitude > WATCH_R then continue end
			local seen = lastSeen[m]
			local vel
			local pp = m.PrimaryPart
			if pp and not pp.Anchored then vel = pp.AssemblyLinearVelocity end
			if (not vel or vel.Magnitude < 0.5) and seen and now - seen.t > 0.03 and now - seen.t < 0.6 then
				vel = (pos - seen.pos) / (now - seen.t)
			end
			if seen then seen.pos, seen.t = pos, now else lastSeen[m] = { pos = pos, t = now } end
			local flat = vel and Vector3.new(vel.X, 0, vel.Z) or Vector3.zero
			local speed = flat.Magnitude
			if speed > 3.5 then
				local ext = extents[m]
				if not ext then
					local _, size = m:GetBoundingBox()
					ext = size
					extents[m] = ext
				end
				table.insert(movers, { model = m, pos = pos, dir = flat / speed, speed = math.min(speed, 120),
					hw = math.min(ext.X, ext.Z) / 2, hl = math.max(ext.X, ext.Z) / 2, mine = m == myModel })
			end
		end
	end
end

-- the vehicle whose path p stands in, when it gets there, and how far p is off its middle line
local function threat(p)
	local best, bestT, bestLat
	for _, v in ipairs(movers) do
		local rx, rz = p.pos.X - v.pos.X, p.pos.Z - v.pos.Z
		local along = rx * v.dir.X + rz * v.dir.Z
		if along > -v.hl * 0.5 and along < v.hl + v.speed * DODGE_AHEAD + 2 and math.abs(p.pos.Y - v.pos.Y) < 8 then
			local lat = rx * -v.dir.Z + rz * v.dir.X
			if math.abs(lat) < v.hw + DODGE_MARGIN then
				local t = math.max(0, along - v.hl) / v.speed
				if not bestT or t < bestT then best, bestT, bestLat = v, t, lat end
			end
		end
	end
	return best, bestT, bestLat
end

local function startDodge(p, v, t: number, lat: number, now: number)
	local side = Vector3.new(-v.dir.Z, 0, v.dir.X)
	local sg = lat >= 0 and 1 or -1
	if math.abs(lat) < 0.35 and p.edge and p.side then
		-- right in the middle of its path: the kerb / house side of the street
		local e = p.edge
		local house = Vector3.new(-e.dz * p.side, 0, e.dx * p.side)
		sg = house:Dot(side) >= 0 and 1 or -1
	end
	local from = p.pos + Vector3.new(0, 2, 0)
	local to
	for _, s in ipairs({ sg, -sg }) do
		local need = math.max(0.3, v.hw + DODGE_MARGIN + 1 - lat * s)
		if need < 7.5 and not blockedFrom(from, side * s, need + 0.3) then
			to = p.pos + side * s * need
			break
		end
	end
	-- (boxed in against a wall: press flat where they are and watch it squeeze past)
	local dist = to and (to - p.pos).Magnitude or 0
	local speed = math.clamp(dist / math.max(t - 0.1, 0.22), 5.5, 10) -- (a sprint at most: a person, not a cat)
	p.dodge = { to = to or p.pos, speed = speed, untilT = now + t + (2 * v.hl) / v.speed + 0.7, model = v.model }
	p.idleUntil = 0
	if t < 0.75 then
		p.hopAt = now -- a start: a little jump back
		if v.mine and now - shoutAt > 7 then
			shoutAt = now
			local lines = {
				L("Hey! Watch it!", "เฮ้ย! ระวังหน่อย!"),
				L("Whoa! Slow down!", "โอ๊ย! ขับช้าๆ หน่อย!"),
				L("Careful!", "ระวังสิ!"),
			}
			Feedback.bubble(p.pos + Vector3.new(0, 6.2, 0), L("Pedestrian", "คนเดินถนน"), lines[rng:NextInteger(1, #lines)])
		end
	end
end

-- Is something coming toward pos (or right there)? People about to cross wait for it.
local function vehicleComing(pos: Vector3): (boolean, Vector3?)
	for _, v in ipairs(movers) do
		local rel = Vector3.new(pos.X - v.pos.X, 0, pos.Z - v.pos.Z)
		local d = rel.Magnitude
		if d < 13 then return true, v.pos end
		local closing = rel:Dot(v.dir) / d * v.speed
		if closing > 3 and d / closing < 3.6 then return true, v.pos end
	end
	return false, nil
end

local function watchTraffic(list, now: number, camPos: Vector3)
	if now < moverAt then return end
	moverAt = now + 0.12
	scanMovers(now, camPos)
	if #movers == 0 then return end
	for _, p in ipairs(list) do
		if p.active and p.pos and not p.dodge and not p.scripted and not (p.downUntil and now < p.downUntil)
			and not (p.noDodgeUntil and now < p.noDodgeUntil) and (p.pos - camPos).Magnitude < WATCH_R then
			local v, t, lat = threat(p)
			if not v then
				p.noticeAt = nil
			elseif not p.noticeAt then
				-- people need a moment to notice: longer when it comes from behind (they hear it first) or
				-- while they stand looking at something; a vehicle that turns up close can still catch them
				local toV = Vector3.new(v.pos.X - p.pos.X, 0, v.pos.Z - p.pos.Z)
				local behind = toV.Magnitude > 0.1 and p.look and p.look:Dot(toV.Unit) < 0
				p.noticeAt = now + rng:NextNumber(0.18, 0.45) + (behind and 0.3 or 0) + (now < (p.idleUntil or 0) and 0.2 or 0)
			elseif now >= p.noticeAt then
				p.noticeAt = nil
				startDodge(p, v, t, lat, now)
			end
		end
	end
end

-- One step of stepping out of the way (instead of the person's own walk). Returns true while moving.
local function advanceDodge(p, dt: number, now: number): boolean
	local d = p.dodge
	local to = d.to - p.pos
	local flat = Vector3.new(to.X, 0, to.Z)
	local dist = flat.Magnitude
	local moving = dist > 0.12
	if moving then
		local step = math.min(dist, d.speed * dt)
		p.pos += flat / dist * step
		local look = p.look:Lerp(flat / dist, math.min(1, dt * 10))
		p.look = look.Magnitude > 0.01 and look.Unit or p.look
	else
		-- out of the way: turn and watch it go by
		local m = d.model
		local vp = m and m.Parent and m:GetPivot().Position
		if vp then
			local w = Vector3.new(vp.X - p.pos.X, 0, vp.Z - p.pos.Z)
			if w.Magnitude > 0.5 then
				local look = p.look:Lerp(w.Unit, math.min(1, dt * 6))
				p.look = look.Magnitude > 0.01 and look.Unit or p.look
			end
		end
		if now > d.untilT then
			p.dodge = nil
			p.idleUntil = now + rng:NextNumber(0.3, 0.9)
		end
	end
	return moving
end

-- One step of walking. Returns true while the ped is moving.
local function advance(p, dt: number, now: number, raining: boolean): boolean
	if now < p.idleUntil then return false end
	-- about to cross the street: look both ways, wait while something is coming
	if p.lookFirst then
		local coming, at = vehicleComing(p.pos)
		if coming then
			p.idleUntil = now + 0.5
			if at then
				local w = Vector3.new(at.X - p.pos.X, 0, at.Z - p.pos.Z)
				if w.Magnitude > 0.5 then p.look = w.Unit end
			end
			return false
		end
		p.lookFirst = nil
	end
	local to = p.goal - p.pos
	local flat = Vector3.new(to.X, 0, to.Z)
	local dist = flat.Magnitude
	if dist < 1.2 then
		if p.stepAside then
			-- stepped out of a vehicle's way: let it pass, then carry on
			local wait = math.max(1.5, p.stepAside - now - 2)
			p.stepAside = nil
			p.idleUntil = now + wait
			return false
		end
		if rng:NextNumber() < 0.09 then
			p.idleUntil = now + rng:NextNumber(3, 8) -- stop for a moment: look around, wait, check the phone
			return false
		end
		nextGoal(p)
		return true
	end
	local step = math.min(dist, p.speed * (raining and 1.2 or 1) * dt)
	local dir = flat / dist
	if now >= (p.probeAt or 0) then
		p.probeAt = now + 0.17 + rng:NextNumber() * 0.08
		local cam = Workspace.CurrentCamera
		if cam and (cam.CFrame.Position - p.pos).Magnitude < AVOID_NEAR then
			steer(p, dir, now)
			if now < p.idleUntil then return false end
		end
	end
	if p.avoidUntil and now < p.avoidUntil and p.avoid then
		local veer = dir + dir:Cross(Vector3.yAxis) * p.avoid
		dir = veer.Unit
	end
	p.pos = Vector3.new(p.pos.X + dir.X * step, p.pos.Y + (p.goal.Y - p.pos.Y) * math.min(1, dt * 6), p.pos.Z + dir.Z * step)
	local look = p.look:Lerp(dir, math.min(1, dt * 5))
	p.look = look.Magnitude > 0.01 and look.Unit or dir
	return true
end

local function talk(p, at: Vector3)
	local raining = (Workspace:GetAttribute("Rain") or 0) > 0
	Feedback.bubble(at + Vector3.new(0, 3, 0), "Local", Dialogue.line(raining and rng:NextNumber() < 0.6 and "pedestrian_rain" or "pedestrian", rng))
	p.idleUntil = os.clock() + 4
	local me = rootPos()
	if me then
		local d = Vector3.new(me.X - at.X, 0, me.Z - at.Z)
		if d.Magnitude > 0.5 then p.look = d.Unit end
	end
end

local function addPrompt(p, part: BasePart)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Talk"
	pp.ObjectText = "Local"
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.T
	pp.Parent = part
	pp.Triggered:Connect(function() talk(p, part.Position) end)
end

---------------------------------------------------------------------------------------------------
-- joggers on the lake promenades (World/Lakeside paths, GetWorld.lakes)
---------------------------------------------------------------------------------------------------
local lakePaths = nil
local zebraList = nil
local crossing = {} -- [zebra index] = people using that crossing now
State.onWorld(function() lakePaths = nil; zebraList = nil end)

local function lakes()
	if lakePaths then return lakePaths end
	local w = State.world
	if not w or not w.lakes then return nil end
	lakePaths = {}
	for _, l in ipairs(w.lakes) do
		local pts = {}
		for i = 1, #l.path - 1, 2 do table.insert(pts, Vector3.new(l.path[i], 0.35, l.path[i + 1])) end
		if #pts >= 3 then table.insert(lakePaths, { pts = pts, open = l.open }) end
	end
	return lakePaths
end

local function jogHours(h: number): boolean return (h >= 5.3 and h < 8.2) or (h >= 16.3 and h < 19.7) end
local function jogMax(): number return ({ 3, 5, 8 })[Perf.tier] end

local function spawnJogger(p, around: Vector3): boolean
	local L = lakes()
	if not L then return false end
	local best, bi, bd
	for _, l in ipairs(L) do
		for i, q in ipairs(l.pts) do
			local d = Vector3.new(q.X - around.X, 0, q.Z - around.Z).Magnitude
			if not bd or d < bd then best, bi, bd = l, i, d end
		end
	end
	if not best or bd > 360 then return false end
	local n = #best.pts
	local i = ((bi - 1 + rng:NextInteger(-6, 6)) % n) + 1
	local q = best.pts[i]
	if Vector3.new(q.X - around.X, 0, q.Z - around.Z).Magnitude < 40 then return false end -- never pop up beside you
	p.role, p.lake, p.vi = "jog", best, i
	p.jdir = rng:NextNumber() < 0.5 and 1 or -1
	p.lane = rng:NextNumber(-2.2, 2.2)
	p.speed = rng:NextNumber(8.5, 12)
	p.pos, p.goal, p.idleUntil = q, nil, 0
	p.look = Vector3.zAxis
	p.edge = nil
	return true
end

local function jogNext(p)
	local l = p.lake
	local n = #l.pts
	local ni = p.vi + p.jdir
	if l.open and (ni < 1 or ni > n) then
		p.jdir = -p.jdir
		ni = p.vi + p.jdir
	end
	ni = ((ni - 1) % n) + 1
	p.vi = ni
	local a = l.pts[ni]
	local nb = l.pts[((ni - 1 + p.jdir) % n) + 1]
	local d = nb - a
	local side = d.Magnitude > 0.1 and Vector3.new(-d.Z, 0, d.X).Unit or Vector3.zero
	p.goal = a + side * p.lane -- each runner keeps to a lane of the path
end

local function advanceJog(p, dt: number): boolean
	if not p.goal then jogNext(p) end
	local to = p.goal - p.pos
	local flat = Vector3.new(to.X, 0, to.Z)
	local dist = flat.Magnitude
	if dist < 1.5 then
		jogNext(p)
		return true
	end
	local dir = flat / dist
	local step = math.min(dist, p.speed * dt)
	p.pos = Vector3.new(p.pos.X + dir.X * step, 0.35, p.pos.Z + dir.Z * step)
	local look = p.look:Lerp(dir, math.min(1, dt * 6))
	p.look = look.Magnitude > 0.01 and look.Unit or dir
	return true
end

---------------------------------------------------------------------------------------------------
-- people crossing at the zebra crossings (World/RoadMarks, GetWorld.zebras)
---------------------------------------------------------------------------------------------------
local function zebras()
	if zebraList then return zebraList end
	local w = State.world
	if not w or not w.zebras then return nil end
	zebraList = w.zebras
	return zebraList
end

local function kerbPoint(z, side: number, jitter: number): Vector3
	local nx, nz = -z.dz * side, z.dx * side
	local off = z.w / 2 + (z.walk > 0 and math.min(z.walk * 0.5, 2.5) or 1.2)
	local y = z.walk > 0 and 0.5 or z.y
	return Vector3.new(z.x + nx * off + z.dx * jitter, y, z.z + nz * off + z.dz * jitter)
end

local function schoolRun(h: number): boolean return (h >= 6.5 and h < 8.4) or (h >= 14.9 and h < 17) end

local function spawnCrosser(p, around: Vector3): boolean
	local Z = zebras()
	if not Z then return false end
	local h = hour()
	if h < 6 or h > 21.5 then return false end
	for i, z in ipairs(Z) do
		local d = Vector3.new(z.x - around.X, 0, z.z - around.Z).Magnitude
		local cap = (z.school and schoolRun(h)) and 3 or 1
		if d > 55 and d < 240 and (crossing[i] or 0) < cap then
			crossing[i] = (crossing[i] or 0) + 1
			p.role, p.zi = "cross", i
			p.zside = rng:NextNumber() < 0.5 and 1 or -1
			p.zj = rng:NextNumber(-2, 2)
			p.pos = kerbPoint(z, p.zside, p.zj)
			p.goal, p.phase = nil, "wait"
			p.idleUntil = os.clock() + rng:NextNumber(1, 6)
			p.speed = rng:NextNumber(3.8, 4.8)
			p.look = Vector3.new(z.dz * p.zside, 0, -z.dx * p.zside) -- facing the road
			p.edge = nil
			return true
		end
	end
	return false
end

-- Wait at the kerb while a vehicle would reach the crossing within ~4.5 s (or is right there): people
-- step out when there is a gap, so a driver always has time to stop for them.
local function trafficComing(z): boolean
	local c = Vector3.new(z.x, 0, z.z)
	local f = Workspace:FindFirstChild("Vehicles")
	if f then
		for _, m in ipairs(f:GetChildren()) do
			local pp = m:IsA("Model") and m.PrimaryPart
			if pp then
				local rel = Vector3.new(pp.Position.X, 0, pp.Position.Z) - c
				local d = rel.Magnitude
				if d < 26 then return true end
				local v = pp.AssemblyLinearVelocity
				local closing = d > 0.1 and -(rel / d):Dot(Vector3.new(v.X, 0, v.Z)) or 0
				if closing > 3 and d / closing < 4.5 then return true end
			end
		end
	end
	for _, name in ipairs({ "Traffic", "GoDashLocalTraffic" }) do
		local t = Workspace:FindFirstChild(name)
		if t then
			for _, m in ipairs(t:GetChildren()) do
				if m:IsA("Model") then
					local pv = m:GetPivot().Position
					if (Vector3.new(pv.X, 0, pv.Z) - c).Magnitude < 34 then return true end
				end
			end
		end
	end
	return false
end

local function advanceCross(p, dt: number, now: number): boolean
	local Z = zebras()
	local z = Z and Z[p.zi]
	if not z then return false end
	if p.phase ~= "walk" then
		if now < p.idleUntil then return false end
		if trafficComing(z) then
			p.idleUntil = now + 0.5
			return false
		end
		p.phase = "walk"
		p.zside = -p.zside
		p.goal = kerbPoint(z, p.zside, p.zj + rng:NextNumber(-0.6, 0.6))
	end
	local to = p.goal - p.pos
	local flat = Vector3.new(to.X, 0, to.Z)
	local dist = flat.Magnitude
	if dist < 0.8 then
		p.phase = "rest"
		p.idleUntil = now + rng:NextNumber(6, 16)
		p.look = Vector3.new(z.dz * p.zside, 0, -z.dx * p.zside)
		return false
	end
	local dir = flat / dist
	local step = math.min(dist, p.speed * dt)
	local across = math.abs((p.pos.X - z.x) * -z.dz + (p.pos.Z - z.z) * z.dx)
	local y = across < z.w / 2 and z.y or p.goal.Y
	p.pos = Vector3.new(p.pos.X + dir.X * step, p.pos.Y + (y - p.pos.Y) * math.min(1, dt * 8), p.pos.Z + dir.Z * step)
	local look = p.look:Lerp(dir, math.min(1, dt * 6))
	p.look = look.Magnitude > 0.01 and look.Unit or dir
	return true
end

-- Did this player just drive over a crossing while someone is on the road part of it?
local zebraReported = 0
local function checkZebra(now: number)
	if now - zebraReported < 60 then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat then return end
	if seat.AssemblyLinearVelocity.Magnitude < 8 then return end
	local Z = zebras()
	if not Z then return end
	for _, p in ipairs(all) do
		if p.active and p.role == "cross" and p.phase == "walk" then
			local z = Z[p.zi]
			if z then
				local rx, rz = seat.Position.X - z.x, seat.Position.Z - z.z
				local along, across = rx * z.dx + rz * z.dz, rx * -z.dz + rz * z.dx
				if math.abs(along) < 4 and math.abs(across) < z.w / 2 + 1 then
					-- (2026-11-19) only someone on the road and near your path counts: a person still on the
					-- far side of a wide road is not one you failed to stop for
					local pa = (p.pos.X - z.x) * -z.dz + (p.pos.Z - z.z) * z.dx
					if math.abs(pa) < z.w / 2 + 0.3 and math.abs(pa - across) < 9 then
						zebraReported = now
						Net.send("ZebraRun", p.zi)
						return
					end
				end
			end
		end
	end
end

-- leave whatever job this person had (crossing / jogging) before they are put somewhere else
local function release(p)
	if p.role == "cross" and p.zi then crossing[p.zi] = math.max(0, (crossing[p.zi] or 1) - 1) end
	p.role, p.zi, p.lake, p.phase = nil, nil, nil, nil
end

-- pick what this person does next: jog by the lake, use a crossing, or walk the streets
local function spawnAny(p, me: Vector3, list): boolean
	release(p)
	local h = hour()
	if p.sporty and jogHours(h) then
		local n = 0
		for _, q in ipairs(list) do if q.active and q.role == "jog" then n += 1 end end
		if n < jogMax() and spawnJogger(p, me) then return true end
	end
	-- (2026-11-19: fewer people out on the road itself: at most 2 crossing at a time, was 5)
	if not p.sporty and rng:NextNumber() < 0.2 then
		local n = 0
		for _, q in ipairs(list) do if q.active and q.role == "cross" then n += 1 end end
		if n < 2 and spawnCrosser(p, me) then return true end
	end
	return spawnAt(p, me)
end

-- still the right thing to be doing at this hour? (a runner after dusk goes home once out of view)
local function retired(p, h: number, camPos: Vector3?): boolean
	local far = not camPos or not inView(p.pos, 300) -- (out of view, not just 90 studs away)
	if p.role == "jog" then return far and not jogHours(h) end
	if p.role == "cross" then return far and (h < 6 or h > 21.5) end
	return false
end

---------------------------------------------------------------------------------------------------
-- Avatar pedestrians: generated R15 characters stored in ReplicatedStorage.GoDashModels ("Ped1"...).
---------------------------------------------------------------------------------------------------
-- The generated avatars rest with their arms about 43 degrees out from the body (an A-pose), and
-- Roblox's walk animation is made for arms that hang straight down, so every walk looked like
-- flailing. Turn each shoulder joint so the arm hangs down at rest.
local relaxArms = require(Shared.RiderPose).relaxArms

local function startAvatars(templates: { Model })
	local list = {}
	local walk, idle = Instance.new("Animation"), Instance.new("Animation")
	walk.AnimationId = WALK_ANIM
	idle.AnimationId = IDLE_ANIM
	for i = 1, COUNT do
		local template = templates[(i - 1) % #templates + 1]
		local model = template:Clone()
		model.Name = "Pedestrian"
		local hum = model:FindFirstChildOfClass("Humanoid")
		local rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum and rootPart then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			hum.BreakJointsOnDeath = false
			hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
			pcall(function() hum.EvaluateStateMachine = false end) -- this script moves them; no physics
			pcall(function() model:ScaleTo(0.92 + (i % 6) * 0.03) end) -- people are not all one height
			rootPart.Anchored = true
			relaxArms(model)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then d.CanCollide = false; d.CanTouch = false; d.CanQuery = d == rootPart end
			end
			local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
			animator.Parent = hum
			local p = { model = model, hum = hum, root = rootPart, animator = animator, active = false, idleUntil = 0, moving = false,
				height = hum.HipHeight + rootPart.Size.Y / 2, hScale = math.max(0.6, hum.HipHeight / 2), template = template.Name }
			-- one in six in sports kit (they are the ones who go jogging), one in six in school uniform
			if i % 6 == 1 then
				p.sporty = true
				RiderPose.dress(model, ({ Color3.fromRGB(240, 90, 70), Color3.fromRGB(60, 150, 230), Color3.fromRGB(250, 200, 60), Color3.fromRGB(90, 200, 140) })[(i // 6) % 4 + 1],
					Color3.fromRGB(34, 34, 40), Color3.fromRGB(236, 236, 236))
			elseif i % 6 == 4 then
				p.student = true
				RiderPose.dress(model, Color3.fromRGB(246, 246, 242), (i // 6) % 2 == 0 and Color3.fromRGB(30, 40, 78) or Color3.fromRGB(28, 28, 32), Color3.fromRGB(22, 22, 24))
			end
			addPrompt(p, rootPart)
			table.insert(list, p)
			table.insert(all, p)
		end
	end

	local run = Instance.new("Animation")
	run.AnimationId = RUN_ANIM
	local function tracks(p)
		if p.walk or not p.model.Parent then return end
		local ok1, w = pcall(function() return p.animator:LoadAnimation(walk) end)
		local ok2, s = pcall(function() return p.animator:LoadAnimation(idle) end)
		if ok1 and w then w.Looped = true; p.walk = w end
		if ok2 and s then s.Looped = true; p.idle = s end
		-- (everyone can run now: joggers, and anyone hurrying out of a vehicle's way)
		local ok3, r = pcall(function() return p.animator:LoadAnimation(run) end)
		if ok3 and r then r.Looped = true; p.run = r end
	end
	-- anim = "walk" | "run" | "idle" | "none" (lying down); speed = how fast the body moves (studs/s)
	local function setAnim(p, anim: string, speed: number, raining: boolean?)
		tracks(p)
		if anim == "run" and not p.run then anim = "walk" end
		if anim ~= p.anim or not p.started then
			p.anim, p.started = anim, true
			p.moving = anim == "walk" or anim == "run"
			local quick = anim == "none" and 0.05 or 0.3
			if p.walk then if anim == "walk" then p.walk:Play(0.25) else p.walk:Stop(quick) end end
			if p.run then if anim == "run" then p.run:Play(0.2) else p.run:Stop(quick) end end
			if p.idle then if anim == "idle" then p.idle:Play(0.4) else p.idle:Stop(quick) end end
		end
		if anim == "run" then
			p.run:AdjustSpeed(speed / (16 * p.hScale) * 1.3)
		elseif anim == "walk" and p.walk then
			p.walk:AdjustSpeed(speed * (raining and 1.2 or 1) / (WALK_NATURAL * p.hScale))
		end
	end
	animHook = setAnim

	RunService.Heartbeat:Connect(function(dt)
		local me = rootPos()
		if not me then return end
		local now = os.clock()
		local raining = (Workspace:GetAttribute("Rain") or 0) > 0
		local h = hour()
		local cam = Workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position
		local want = math.floor(#list * density(h) * Perf.scale * Perf.limit("peds"))
		checkZebra(now)
		if camPos then watchTraffic(list, now, camPos) end
		for i, p in ipairs(list) do
			if p.scripted then
				-- a cutscene has this person now (client/Cutscene, client/Replay): it moves them
				continue
			elseif i > want and (not p.active or not inView(p.pos, 300)) then
				-- fewer wanted (night, a slow frame rate): taken away only once out of view
				if p.active then p.active = false; release(p); p.dodge = nil; p.model.Parent = nil end
			elseif not p.active or (p.pos - me).Magnitude > DESPAWN or retired(p, h, camPos) then
				p.dodge, p.lookFirst = nil, nil
				-- (someone far behind you is moved; someone you can see stays where they are)
				local ok = spawnAny(p, me, list)
				if ok and inView(p.pos, 260) then
					release(p)
					ok = false -- that spot is in view: try again next frame
				end
				if ok then
					p.active = true
					p.root.CFrame = CFrame.lookAt(p.pos + Vector3.new(0, p.height, 0), p.pos + Vector3.new(0, p.height, 0) + p.look)
					p.model.Parent = folder
				elseif p.active then
					p.active = false
					p.model.Parent = nil
				end
			elseif p.downUntil and now < p.downUntil then
				-- knocked down by a vehicle (Peds.hit): lie still, then get up
				if not p.downPosed then
					p.downPosed = true
					p.dodge = nil
					setAnim(p, "none", 0)
				end
				lying(p, p.root)
			else
				if p.downPosed then
					p.downPosed, p.downUntil, p.started = nil, nil, nil -- back on their feet; the tracks restart below
				end
				local moving
				local speed = p.speed
				if p.dodge then
					speed = p.dodge.speed
					moving = advanceDodge(p, dt, now)
				elseif p.role == "jog" then moving = advanceJog(p, dt)
				elseif p.role == "cross" then moving = advanceCross(p, dt, now)
				else moving = advance(p, dt, now, raining) end
				-- a start (startDodge): a quick little jump
				local hop = 0
				if p.hopAt then
					local k = (now - p.hopAt) / 0.42
					if k >= 1 then p.hopAt = nil else hop = math.sin(k * math.pi) * 0.9 end
				end
				local at = p.pos + Vector3.new(0, p.height + hop, 0)
				p.root.CFrame = CFrame.lookAt(at, at + p.look)
				local fast = p.role == "jog" or speed > 7.5
				setAnim(p, moving and (fast and "run" or "walk") or "idle", speed, raining)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Part-built pedestrians (places without the avatar models, e.g. the local file built from src/).
---------------------------------------------------------------------------------------------------
local function startRigs()
	local list = {}
	for i = 1, COUNT do
		local rig = Rig.build({ jointed = true, seed = i * 131, name = "Pedestrian", outfit = (i % 5 == 0) and "student" or nil })
		local p = { rig = rig, active = false, phase = rng:NextNumber(0, 6), idleUntil = 0 }
		addPrompt(p, rig.root)
		list[i] = p
		table.insert(all, p)
	end
	RunService.Heartbeat:Connect(function(dt)
		local me = rootPos()
		if not me then return end
		local now = os.clock()
		local raining = (Workspace:GetAttribute("Rain") or 0) > 0
		local night = Workspace:GetAttribute("IsNight") == true
		local want = math.floor((night and COUNT * 0.55 or COUNT) * Perf.scale)
		for i, p in ipairs(list) do
			if i > want then
				if p.active then p.active = false; p.rig.model.Parent = nil end
			elseif not p.active or (p.pos - me).Magnitude > DESPAWN then
				if spawnAt(p, me) then
					p.active = true
					p.rig.model.Parent = folder
				elseif p.active then
					p.active = false
					p.rig.model.Parent = nil
				end
			elseif p.downUntil and now < p.downUntil then
				Rig.walkPose(p.rig, 0, 0)
				lying(p, p.rig.root)
			else
				p.downUntil = nil
				local moving = advance(p, dt, now, raining)
				local at = p.pos + Vector3.new(0, Rig.FEET, 0)
				p.rig.root.CFrame = CFrame.lookAt(at, at + p.look)
				if moving then
					p.phase += dt * p.speed * 1.25
					Rig.walkPose(p.rig, p.phase, 1)
				else
					Rig.walkPose(p.rig, 0, 0)
				end
			end
		end
	end)
end

-- For the accident scenes (2026-11-19, owner: "the person who was hit should get up and come over to
-- claim, not warp in"; "a CCTV replay"). A scene borrows the very person who was hit; while borrowed
-- this script leaves them alone and the scene poses them with Peds.place, then hands them back where
-- they ended up, and they walk on from there (slowly: they were hurt).

-- People near pos (client/Replay's recording): { { p, pos, look, down } }
function Peds.near(pos: Vector3, r: number)
	local out = {}
	local now = os.clock()
	for _, p in ipairs(all) do
		-- (a scammer, client/Accident, is borrowed but still recorded: the CCTV replay must show them jumping in)
		if p.active and p.pos and p.model and (not p.scripted or p.scam) then
			local dx, dz = p.pos.X - pos.X, p.pos.Z - pos.Z
			if dx * dx + dz * dz < r * r then
				table.insert(out, { p = p, pos = p.pos, look = p.look, down = p.downUntil ~= nil and now < p.downUntil })
			end
		end
	end
	return out
end

-- Take this person over (nil when they are not on the street any more, or are part-built).
function Peds.borrow(p)
	if not (p and p.active and p.model and p.model.Parent and p.root and p.hum) then return nil end
	p.scripted = true
	p.dodge, p.hopAt = nil, nil
	return p
end

-- Pose a borrowed person. mode "lie" | "walk" | "run" | "idle" | "none" (no animation: the scene sets the
-- joints); pos / look = where they are; speed = how fast they move (for the steps); cf = the root's exact
-- frame (a scene's own body motion), else standing at pos facing look.
function Peds.place(p, mode: string, pos: Vector3, look: Vector3, speed: number?, cf: CFrame?)
	if not (p and p.root) then return end
	p.pos = pos
	if look.Magnitude > 0.01 then p.look = Vector3.new(look.X, 0, look.Z).Unit end
	if mode == "lie" then
		if animHook then animHook(p, "none", 0) end
		lying(p, p.root)
		return
	end
	if animHook then animHook(p, mode, speed or 0) end
	if cf then
		p.root.CFrame = cf
	else
		local at = pos + Vector3.new(0, p.height, 0)
		p.root.CFrame = CFrame.lookAt(at, at + p.look)
	end
end

-- Hand a borrowed person back just as they were (client/Replay put them back where they really are).
function Peds.release(p)
	if not p then return end
	p.scripted = nil
	p.started, p.anim, p.downPosed = nil, nil, nil
end

-- Hand a borrowed person back, standing at pos: they carry on from there, slowly (they were hurt).
function Peds.giveBack(p, pos: Vector3?, look: Vector3?)
	if not p then return end
	p.scripted = nil
	p.downUntil, p.downPosed, p.started, p.anim, p.dodge = nil, nil, nil, nil, nil
	if pos then p.pos = pos end
	if look and look.Magnitude > 0.01 then p.look = Vector3.new(look.X, 0, look.Z).Unit end
	p.speed = math.min(p.speed or 3, 2.8)
	p.idleUntil = os.clock() + 1.2
	if p.role == "walk" and p.edge then pcall(nextGoal, p) end
end

function Peds.start()
	folder = Instance.new("Folder")
	folder.Name = "GoDashPedestrians"
	folder.Parent = Workspace
	-- (2026-11-20: block figures with the toy-brick look for a few hours; the owner wanted the realistic people back)
	local store = ReplicatedStorage:WaitForChild("GoDashModels", 6)
	local templates = {}
	if store then
		for _, m in ipairs(store:GetChildren()) do
			if m:IsA("Model") and m.Name:sub(1, 3) == "Ped" and m:FindFirstChildOfClass("Humanoid") then table.insert(templates, m) end
		end
	end
	if #templates > 0 then startAvatars(templates) else startRigs() end
	-- the horn (H) asks the people in front of your vehicle to step aside
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.H then return end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		if seat then
			local lv = seat.CFrame.LookVector
			local d = Vector3.new(lv.X, 0, lv.Z)
			if d.Magnitude > 0.1 then
				d = d.Unit
				Peds.makeWay(seat.Position + d * 3, d, 2.2, 32)
			end
		end
	end)
	-- Studio QA (client/Accident tests): Workspace QaPedAhead = studs -> the nearest pedestrian stands
	-- still that far in front of the vehicle you are driving, so a hit can be repeated on purpose
	if RunService:IsStudio() then
		Workspace:GetAttributeChangedSignal("QaPedAhead"):Connect(function()
			local dist = Workspace:GetAttribute("QaPedAhead")
			if type(dist) ~= "number" then return end
			Workspace:SetAttribute("QaPedAhead", nil)
			-- (a negative distance: a target that DOES step out of the way, for recording the dodge)
			local dodgeTest = dist < 0
			dist = math.abs(dist)
			local char = Players.LocalPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local seat = hum and hum.SeatPart
			if not seat then return end
			local look = Vector3.new(seat.CFrame.LookVector.X, 0, seat.CFrame.LookVector.Z).Unit
			local best, bd
			for _, p in ipairs(all) do
				if p.active and p.pos then
					local d = (p.pos - seat.Position).Magnitude
					if not bd or d < bd then best, bd = p, d end
				end
			end
			if not best then return end
			best.downUntil = nil
			local at = Vector3.new(seat.Position.X, 0, seat.Position.Z) + look * dist
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { char, seat:FindFirstAncestorWhichIsA("Model") or seat, folder }
			local g = Workspace:Raycast(at + Vector3.new(0, seat.Position.Y + 20, 0), Vector3.new(0, -80, 0), params)
			best.pos = Vector3.new(at.X, g and g.Position.Y or best.pos.Y, at.Z)
			best.look = -look
			best.idleUntil = os.clock() + 12
			best.dodge, best.noticeAt = nil, nil
			best.noDodgeUntil = not dodgeTest and os.clock() + 12 or nil -- (a test target stays put: it would step out of the way)
		end)
	end
end

return Peds
