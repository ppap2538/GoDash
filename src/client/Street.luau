-- Street life drawn on the client: traffic-light colours (a function of the shared server clock,
-- so everyone sees the same lights) and the AI vehicles.
--
-- Two kinds of AI vehicle share the road and see each other:
--   * route cars: models the server made, each driving there and back along a fixed route across
--     the centre of town. They start from the shared clock, so players see them in the same place.
--   * local traffic: a pool this client runs on the big streets around its own player, so there is
--     always traffic where you are: queues at red lights, rush hours in the morning and evening.
--     That is what makes a short cut through the sois worth finding (owner, 2026-11-16).
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Traffic = require(Shared.Traffic)
local Sounds = require(Shared.Config.Sounds)
local GPS = require(script.Parent.GPS)
local Feedback = require(script.Parent.Feedback)
local Perf = require(script.Parent.Perf)

local Street = {}
Street.onCrash = nil :: ((Model, number, Vector3?, Vector3?) -> ())? -- client/Accident (model, relative speed, its velocity, its position)

-- Keep a crashed AI car standing (hazards on) a while longer: its driver is out talking to you in the
-- claim scene (client/Cutscene). Defined below, once the car lists exist.
Street.hold = function(_model: Model, _seconds: number) end

local LAMP = {
	red = { Color3.fromRGB(255, 50, 40), 1 }, yellow = { Color3.fromRGB(255, 200, 40), 2 }, green = { Color3.fromRGB(60, 230, 110), 3 },
}
-- unlit lamps are nearly black so the lit one stands out (2026-11-18: the old unlit colours read as half-on)
local OFF = { Color3.fromRGB(40, 14, 12), Color3.fromRGB(44, 36, 12), Color3.fromRGB(12, 36, 18) }
local COUNT = { red = Color3.fromRGB(255, 60, 50), yellow = Color3.fromRGB(255, 200, 40), green = Color3.fromRGB(70, 240, 120) }
local lampCache = setmetatable({}, { __mode = "k" }) -- [model] = { lamps = { {part, index} }, count = TextLabel? }

local function paintSignal(model: Instance, t: number, camPos: Vector3?)
	local node, group = model:GetAttribute("Node"), model:GetAttribute("Group")
	if type(node) ~= "number" or type(group) ~= "number" then return end
	local col, _, left = Traffic.timing(node, group, t)
	if not col then return end
	local cache = lampCache[model]
	if not cache then
		cache = { lamps = {} }
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local i = tonumber(d.Name:match("^Lamp(%d)$"))
				if i then table.insert(cache.lamps, { d, i }) end
			elseif d:IsA("TextLabel") and d.Parent and d.Parent.Name == "Count" then
				cache.count = d
			end
		end
		lampCache[model] = cache
	end
	if model:GetAttribute("Shown") ~= col then
		model:SetAttribute("Shown", col)
		local on = LAMP[col]
		for _, li in ipairs(cache.lamps) do
			local lit = on[2] == li[2]
			li[1].Material = lit and Enum.Material.Neon or Enum.Material.SmoothPlastic
			li[1].Color = lit and on[1] or OFF[li[2]]
		end
	end
	-- the countdown, only on signals near the camera (the text is the expensive part)
	local label = cache.count
	if label and camPos then
		local box = label.Parent and label.Parent.Parent
		if box and box:IsA("BasePart") and (box.Position - camPos).Magnitude < 260 then
			local text = tostring(math.max(1, math.ceil(left)))
			if label.Text ~= text then label.Text = text end
			if label.TextColor3 ~= COUNT[col] then label.TextColor3 = COUNT[col] end
		elseif label.Text ~= "" then
			label.Text = ""
		end
	end
end

-- AI vehicles ------------------------------------------------------------------------------------
-- Every AI vehicle keeps left of the centre line (Thailand drives on the left) and:
--   * stops at red and yellow lights (the same lights that fine the player)
--   * slows and stops for anything in its lane: your vehicle, other players, people, other cars
--   * honks if a player blocks it for a while
--   * after a crash it stalls with its hazard lights on, honks, then drives on
local cars = {} -- route cars: [model] = state
local locals = {} -- local traffic: list of states
Street.hold = function(model: Model, seconds: number)
	local until_ = Workspace:GetServerTimeNow() + seconds
	local c = cars[model]
	if not c then
		for _, l in ipairs(locals) do
			if l.model == model then c = l break end
		end
	end
	if c then
		c.stallUntil = math.max(c.stallUntil or 0, until_)
		c.v = 0
	end
end
local signalsById = nil :: any
local ACCEL, BRAKE = 9, 34 -- studs/s²
local player = Players.LocalPlayer
local rng = Random.new()
-- (2026-11-19, owner: "too many cars and people on the street, hard to get past"; "cars suddenly warp") fewer
-- local cars (22 -> 14, phones 12 -> 8) and a milder rush hour; a car starts beyond LOCAL_NEAR and off screen,
-- and is only taken away (too many, stuck) once out of view
local LOCAL_COUNT = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) and 8 or 14
local LOCAL_NEAR, LOCAL_FAR, LOCAL_DROP = 230, 560, 660
local localFolder
local function inView(pos: Vector3, within: number): boolean
	local cam = Workspace.CurrentCamera
	if not cam then return false end
	if (pos - cam.CFrame.Position).Magnitude > within then return false end
	local _, on = cam:WorldToViewportPoint(pos + Vector3.new(0, 2, 0))
	return on
end

local function lamps(model: Model)
	local brakes, signals = {}, {}
	local sigL, sigR = {}, {} -- (2026-11-19) indicators by side for AI turn signals (VehicleFactory: SignalL / SignalFL / SignalR / SignalFR)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if CollectionService:HasTag(d, "BrakeLight") then table.insert(brakes, { part = d, mat = d.Material, color = d.Color }) end
			if d.Name:sub(1, 6) == "Signal" then
				local rec = { part = d, mat = d.Material, color = d.Color }
				table.insert(signals, rec)
				if d.Name == "SignalL" or d.Name == "SignalFL" then table.insert(sigL, rec) end
				if d.Name == "SignalR" or d.Name == "SignalFR" then table.insert(sigR, rec) end
			end
		end
	end
	return brakes, signals, sigL, sigR
end

local function prepare(model: Instance)
	if not model:IsA("Model") then return end
	if cars[model] then return end -- shown again after being hidden far away (see moveCars): same state
	local graph = GPS.graph()
	local path = model:GetAttribute("Path")
	if not graph or type(path) ~= "string" then return end
	if not signalsById then
		local _, byId = Traffic.signals(graph)
		signalsById = byId
	end
	local ids, pts, cum, total = {}, {}, { 0 }, 0
	for id in path:gmatch("%d+") do
		local n = graph.nodes[tonumber(id) :: number]
		if n then table.insert(pts, Vector3.new(n.x, 0, n.z)); table.insert(ids, n.id) end
	end
	if #pts < 2 then return end
	for i = 2, #pts do
		total += (pts[i] - pts[i - 1]).Magnitude
		cum[i] = total
	end
	local speed = model:GetAttribute("Speed") or 40
	local size = model:GetExtentsSize()
	local brakes, signals = lamps(model)
	local t = Workspace:GetServerTimeNow()
	cars[model] = {
		model = model, graph = graph, ids = ids, pts = pts, cum = cum, total = total, base = speed, v = speed,
		s = (speed * t + (model:GetAttribute("Offset") or 0)) % (total * 2),
		y = model:GetAttribute("Y") or 2.5, seg = 1, len = math.max(size.Z, size.X), wid = math.min(size.X, size.Z),
		brakes = brakes, signals = signals, stallUntil = 0, blockedFor = 0, honkAt = 0,
		home = model.Parent, shown = true,
	}
	model.Destroying:Connect(function() cars[model] = nil end)
end

-- where s puts a route car: centre-line point, travel direction, segment, and the junction ahead
local function locate(c, s: number)
	local forward = s <= c.total
	local d = forward and s or c.total * 2 - s
	local i = c.seg
	if i > #c.pts - 1 then i = #c.pts - 1 end
	while i > 1 and c.cum[i] > d do i -= 1 end
	while i < #c.pts - 1 and c.cum[i + 1] < d do i += 1 end
	c.seg = i
	local a, b = c.pts[i], c.pts[i + 1]
	local len = c.cum[i + 1] - c.cum[i]
	local k = len > 0 and (d - c.cum[i]) / len or 0
	local dir = (b - a).Magnitude > 0.01 and (b - a).Unit * (forward and 1 or -1) or Vector3.zAxis
	-- the next node in the direction of travel, how far it is, and the node we come from
	local nextI, prevI, toNext
	if forward then nextI, prevI, toNext = i + 1, i, c.cum[i + 1] - d
	else nextI, prevI, toNext = i, i + 1, d - c.cum[i] end
	return a:Lerp(b, k), dir, nextI, prevI, toNext
end

-- must a vehicle doing v stop for the light at `node`, arriving on `edge` with `toNext` studs to go?
local function mustStop(node, edge, toNext: number, v: number, t: number): boolean
	local sig = signalsById and signalsById[node.id]
	if not sig or not edge or edge.minor or sig.groups[edge] == nil then return false end -- no light on this road (or inside the junction)
	local stopLine = node.r + 5
	if toNext < node.r + 1.5 then return false end -- already in the junction: clear it
	if toNext - stopLine > v * v / (2 * BRAKE) + 6 then return false end -- not near yet
	local col = Traffic.colour(node.id, sig.groups[edge], t)
	if col == "green" then return false end
	-- on yellow, a car too close to stop goes through
	return col == "red" or toNext - stopLine > v * v / (2 * BRAKE)
end

local function redAhead(c, nextI: number, prevI: number, toNext: number, t: number): boolean
	local sig = signalsById and signalsById[c.ids[nextI]]
	if not sig then return false end
	local edge
	for _, l in ipairs(sig.node.links) do
		if l.to.id == c.ids[prevI] then edge = l.edge break end
	end
	return mustStop(sig.node, edge, toNext, c.v, t)
end

local function setLamps(list, on: boolean, color: Color3)
	for _, l in ipairs(list) do
		if l.part.Parent then
			l.part.Material = on and Enum.Material.Neon or l.mat
			l.part.Color = on and color or l.color
		end
	end
end

local function honk(model: Model)
	local root = model.PrimaryPart
	if not root or Sounds.horn == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = Sounds.horn
	s.Volume = 0.55
	s.PlaybackSpeed = 0.9 + math.random() * 0.25
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 180
	s.SoundGroup = Feedback.sfxGroup
	s.Parent = root
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
end

-- What vehicle c (at `here`, heading `dir`) may do given everything in its lane ahead. Returns the
-- speed it should aim for, whether a player is what blocks it, and notes a crash with your vehicle.
--
-- (2026-11-16, the owner found cars stuck crossways in the middle of a junction.) Two cars meeting
-- at a junction each saw the other "in its lane" and both waited for ever. Now:
--   * another AI vehicle only blocks when it is going roughly the same way (a queue); crossing and
--     oncoming traffic is kept apart by the junction lock below instead
--   * a person blocks only when they are really in front of the car, not walking along the kerb
--   * a car held up by AI traffic for 8 s stops looking at AI traffic for 3 s (deadlock breaker)
local function lookAhead(c, here: Vector3, dir: Vector3, left: Vector3, target: number, obstacles, t: number): (number, boolean, boolean)
	local byPlayer, byAI = false, false
	local ghost = t < (c.ghostUntil or 0)
	for _, o in ipairs(obstacles) do
		local skip = o.owner == c
		if not skip and o.owner then
			local ol = o.owner.look
			skip = ghost or (ol ~= nil and ol:Dot(dir) < 0.4)
		end
		if not skip then
			local rel = Vector3.new(o.pos.X - here.X, 0, o.pos.Z - here.Z)
			local along, side = rel:Dot(dir), math.abs(rel:Dot(left))
			local gap = c.len / 2 + o.half + 3 + c.v * 0.55
			local reach = c.wid / 2 + (o.half <= 1 and 0.8 or 1.8)
			-- (2026-11-19) a motorbike filters past cars and pickups on the kerb side, the Thai way
			if c.bike and o.owner and not o.owner.bike then reach = c.wid / 2 + 0.4 end
			if along > 0 and along < gap and side < reach then
				if o.person then byPlayer = true end
				if o.owner then byAI = true end
				target = math.min(target, math.max(0, (along - c.len / 2 - o.half - 2.5) * 1.4))
			end
			-- your vehicle inside this car's box at speed: that was a crash
			if o.mine and o.part and math.abs(along) < c.len / 2 + 1.2 and side < c.wid / 2 + 1.2 then
				local rv = (o.part.AssemblyLinearVelocity - dir * c.v).Magnitude
				if rv > 14 and t > c.stallUntil then
					c.stallUntil = t + 10
					c.v = 0
					c.crashHonkAt = t + 1.1
					target = 0
					-- client/Accident: the damage claim (with this car's own velocity and position, to tell who hit whom)
					if Street.onCrash then task.spawn(Street.onCrash, c.model, rv, dir * c.v, here) end
				end
			end
		end
	end
	return target, byPlayer, byAI
end

-- Junction lock: one vehicle at a time crosses a junction of three or more streets (this client's
-- traffic only; lights still decide who may go at signalled ones). Returns true when c must wait.
local locks = {} -- [node id] = { owner = state, t = time claimed }
local function junctionWait(c, node, toNext: number, t: number): boolean
	if #node.links < 3 or toNext > node.r + 16 then return false end
	local l = locks[node.id]
	if l and l.owner ~= c then
		local o = l.owner
		local near = o.at ~= nil and o.active ~= false and ((o.at.X - node.x) ^ 2 + (o.at.Z - node.z) ^ 2) < (node.r + 17) ^ 2
		if near and t - l.t < 6 then return true end
	end
	if not l or l.owner ~= c then locks[node.id] = { owner = c, t = t } end
	return false
end

-- After the look-ahead: count how long AI traffic has held c up and break a deadlock.
local function unjam(c, target: number, byAI: boolean, dt: number, t: number)
	if byAI and target < 1 then
		c.stuckFor = (c.stuckFor or 0) + dt
		if c.stuckFor > 8 then
			c.ghostUntil = t + 3
			c.stuckFor = 0
		end
	else
		c.stuckFor = 0
	end
	if target < 1 then c.stillFor = (c.stillFor or 0) + dt else c.stillFor = 0 end
end

-- Speed, lights and horn after the target speed is known; then move the model.
local function drive(c, target: number, byPlayer: boolean, here: Vector3, dir: Vector3, t: number, dt: number, blink: boolean)
	local stalled = t < c.stallUntil
	if stalled then target = 0 end
	c.blockedFor = (byPlayer and target < 2) and c.blockedFor + dt or 0
	if c.blockedFor > 3.5 and t > c.honkAt then
		c.honkAt = t + 7
		honk(c.model)
	end
	if c.crashHonkAt and t >= c.crashHonkAt then
		c.crashHonkAt = nil
		honk(c.model)
	end
	local dv = target - c.v
	c.v = math.clamp(c.v + math.clamp(dv, -BRAKE * dt, ACCEL * dt), 0, c.base)
	-- ease the heading through corners instead of snapping
	local look = c.look and c.look:Lerp(dir, math.min(1, dt * 10)) or dir
	if look.Magnitude < 0.01 then look = dir end
	c.look = look.Unit
	local p = here + Vector3.new(0, c.y, 0)
	c.vis = c.smooth and c.vis and c.vis:Lerp(p, math.min(1, dt * 12)) or p
	c.at = p
	-- (client/Replay moves a car itself while it shows the CCTV replay of a crash)
	if not c.model:GetAttribute("ReplayHold") then c.model:PivotTo(CFrame.lookAt(c.vis, c.vis + c.look)) end
	local braking = c.v < c.base - 1 and (dv < -0.5 or c.v < 1)
	if braking ~= c.braking then c.braking = braking; setLamps(c.brakes, braking, Color3.fromRGB(255, 40, 30)) end
	-- hazards when stalled; otherwise the indicator of the side it is about to turn to (c.turn, local traffic)
	local amber = Color3.fromRGB(255, 170, 40)
	if c.sigL and c.sigR and (#c.sigL > 0 or #c.sigR > 0) then
		local wantL = blink and (stalled or c.turn == "L")
		local wantR = blink and (stalled or c.turn == "R")
		if wantL ~= c.litL then c.litL = wantL; setLamps(c.sigL, wantL, amber) end
		if wantR ~= c.litR then c.litR = wantR; setLamps(c.sigR, wantR, amber) end
	else
		local hazard = stalled and blink
		if hazard ~= c.hazard then c.hazard = hazard; setLamps(c.signals, hazard, amber) end
	end
end

---------------------------------------------------------------------------------------------------
-- local traffic
---------------------------------------------------------------------------------------------------
local function busy(): number -- how full the streets are right now (rush hours, quiet nights)
	local ct = Lighting.ClockTime
	-- (2026-11-19, owner: "รถติดชั่วโมงเร่งด่วน") morning and evening rush: many more cars, crawling (see moveCars)
	if (ct >= 7 and ct < 9.5) or (ct >= 16.5 and ct < 19.5) then return 1.35 end -- (was 1.7: too crowded to ride through)
	if ct >= 22.5 or ct < 5 then return 0.45 end
	return 1
end

local function laneOf(c): (Vector3, Vector3, Vector3)
	local e = c.e
	local sa = c.sign > 0 and c.s or e.len - c.s
	local dir = Vector3.new(e.dx, 0, e.dz) * c.sign
	local left = Vector3.new(dir.Z, 0, -dir.X)
	local off = math.clamp(e.def.width / 4, 3.2, 9)
	if c.bike then off = math.min(off + 2, e.def.width / 2 - 1.6) end -- (2026-11-19) motorbikes keep to the kerb side of the lane
	return Vector3.new(e.a.x + e.dx * sa, 0, e.a.z + e.dz * sa) + left * off, dir, left
end

local function spawnLocal(c, around: Vector3, obstacles): boolean
	local graph = GPS.graph()
	if not graph then return false end
	local options = {}
	for _, e in ipairs(graph:edgesNear(around, LOCAL_FAR)) do
		if not e.minor and e.len > 40 then
			local d = (Vector3.new((e.a.x + e.b.x) / 2, 0, (e.a.z + e.b.z) / 2) - Vector3.new(around.X, 0, around.Z)).Magnitude
			if d > LOCAL_NEAR and d < LOCAL_FAR then table.insert(options, e) end
		end
	end
	if #options == 0 then return false end
	for _ = 1, 4 do
		c.e = options[rng:NextInteger(1, #options)]
		c.sign = rng:NextNumber() < 0.5 and 1 or -1
		local margin = math.min(c.e.len * 0.35, 24) -- never inside a junction
		c.s = rng:NextNumber(margin, c.e.len - margin)
		local here = laneOf(c)
		local free = not inView(here, LOCAL_FAR) -- never pop up where the rider can see it
		for _, o in ipairs(obstacles) do
			if not free then break end
			if o.owner ~= c and (Vector3.new(o.pos.X, 0, o.pos.Z) - here).Magnitude < 34 then free = false break end
		end
		if free then
			c.v = c.base * 0.7
			c.vis, c.look, c.at = nil, nil, nil
			c.stallUntil, c.blockedFor, c.stuckFor, c.stillFor, c.ghostUntil = 0, 0, 0, 0, 0
			c.planned, c.turn = nil, nil
			return true
		end
	end
	return false
end

-- At the end of its street a local car picks the next one: mostly straight on, sometimes a turn,
-- rarely into a soi, never into a lane; a dead end turns it round.
local function chooseNext(c)
	local e = c.e
	local node = c.sign > 0 and e.b or e.a
	local dx, dz = e.dx * c.sign, e.dz * c.sign
	local options, total = {}, 0
	for _, l in ipairs(node.links) do
		local o = l.edge
		if o ~= e and o.type ~= "lane" then
			local sgn = o.a == node and 1 or -1
			local w = 0.4 + 2.4 * math.max(0, dx * o.dx * sgn + dz * o.dz * sgn)
			if o.type == "soi" then w *= 0.2 end
			total += w
			table.insert(options, { o, sgn, w })
		end
	end
	if #options == 0 then return nil end
	local r = rng:NextNumber() * total
	local pick = options[1]
	for _, it in ipairs(options) do
		r -= it[3]
		if r <= 0 then pick = it break end
	end
	return pick
end

-- (2026-11-19, owner: AI vehicles signal before they turn) the next street is chosen ~45 studs before the
-- junction, so the indicator of that side can blink on the way in; c.turn = "L" / "R" / nil
local function planTurn(c)
	local pick = chooseNext(c)
	c.planned = pick or false
	c.turn = nil
	if pick then
		local e = c.e
		local dx, dz = e.dx * c.sign, e.dz * c.sign
		local o, sgn = pick[1], pick[2]
		local cross = dx * (o.dz * sgn) - dz * (o.dx * sgn) -- > 0 = to the right (Roblox: X right, Z toward the viewer)
		if cross > 0.45 then c.turn = "R" elseif cross < -0.45 then c.turn = "L" end
	end
end

local function nextStreet(c)
	local pick = c.planned
	if pick == nil then pick = chooseNext(c) end
	c.planned = nil
	c.turnOffAt = os.clock() + 1.2 -- keep blinking round the corner a moment
	if not pick then
		c.sign = -c.sign
		c.s = 0
		return
	end
	c.e, c.sign, c.s = pick[1], pick[2], 0
end

-- The traffic kit's vehicles come without indicator lamps: four small ones at the corners (local -Z is the way
-- it drives, -X its left), picked up by lamps() as SignalL / SignalFL / SignalR / SignalFR (2026-11-19)
local function addIndicators(model: Model)
	local pv = model:GetPivot()
	local bcf, size = model:GetBoundingBox()
	local rel = pv:ToObjectSpace(bcf).Position
	local ext = model:GetExtentsSize()
	local hl, hw = math.max(ext.X, ext.Z) / 2, math.min(ext.X, ext.Z) / 2
	local bike = model:GetAttribute("HasRider") == true
	local y = rel.Y - size.Y / 2 + size.Y * (bike and 0.45 or 0.38)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = Instance.new("Part")
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
			p.Size = bike and Vector3.new(0.22, 0.18, 0.18) or Vector3.new(0.34, 0.24, 0.12)
			p.Color = Color3.fromRGB(170, 105, 25)
			p.Material = Enum.Material.SmoothPlastic
			p.Name = "Signal" .. (sz < 0 and "F" or "") .. (sx < 0 and "L" or "R")
			p.CFrame = pv * CFrame.new(rel.X + sx * (hw - (bike and 0.45 or 0.12)), y, rel.Z + sz * (hl + 0.04))
			p.Parent = model
		end
	end
end

local function startLocals()
	-- (2026-11-19: a fresh server can take 30 s and more to build the city; with a 20 s wait the first rider
	-- on it gave up and saw no local traffic at all for the whole session)
	local kit = ReplicatedStorage:WaitForChild("GoDashTrafficKit", 300)
	if not kit then return end
	-- A folder arrives before what is inside it. Cloning at once copied half-arrived models: bikes
	-- whose rider was only a helmet (2026-11-16). Wait until everything the server made is here.
	local want = kit:GetAttribute("Size")
	local t0 = os.clock()
	while type(want) == "number" and #kit:GetDescendants() < want and os.clock() - t0 < 40 do task.wait(0.25) end
	local templates = kit:GetChildren()
	if #templates == 0 then return end
	localFolder = Instance.new("Folder")
	localFolder.Name = "GoDashLocalTraffic"
	localFolder.Parent = Workspace
	local n = math.ceil(LOCAL_COUNT * 1.7)
	for i = 1, n do
		local model = templates[(i - 1) % #templates + 1]:Clone()
		model.Name = "LocalCar"
		pcall(addIndicators, model)
		local size = model:GetExtentsSize()
		local brakes, signals, sigL, sigR = lamps(model)
		local base = (model:GetAttribute("Speed") or 40) * rng:NextNumber(0.85, 1.15)
		table.insert(locals, {
			model = model, base = base, v = base, y = model:GetAttribute("Y") or 2.5, smooth = true,
			len = math.max(size.Z, size.X), wid = math.min(size.X, size.Z), brakes = brakes, signals = signals, sigL = sigL, sigR = sigR,
			bike = model:GetAttribute("HasRider") == true,
			stallUntil = 0, blockedFor = 0, honkAt = 0, active = false,
		})
	end
end

---------------------------------------------------------------------------------------------------
local function moveCars(t: number, dt: number, camPos: Vector3)
	-- everything a car has to look out for this frame
	local obstacles = {}
	local folder = Workspace:FindFirstChild("Vehicles")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			local p = m:IsA("Model") and m.PrimaryPart
			if p then table.insert(obstacles, { pos = p.Position, half = 3, mine = m:GetAttribute("Owner") == player.UserId, part = p, person = true }) end
		end
	end
	local me: Vector3? = nil
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		if r and plr == player then me = r.Position end
		if r and hum and not hum.SeatPart then table.insert(obstacles, { pos = r.Position, half = 1, person = true }) end
	end
	for _, c in pairs(cars) do
		if c.at then table.insert(obstacles, { pos = c.at, half = c.len / 2, owner = c }) end
	end
	for _, c in ipairs(locals) do
		if c.active and c.at then table.insert(obstacles, { pos = c.at, half = c.len / 2, owner = c }) end
	end
	-- (2026-11-19) a broken-down car, a crash or a pop-up market (server/CityEventService) blocks the lane
	for _, b in ipairs(CollectionService:GetTagged("GoDashObstacle")) do
		if b:IsA("BasePart") then table.insert(obstacles, { pos = b.Position, half = math.max(b.Size.X, b.Size.Z) / 2 }) end
	end
	-- people on foot: a car waits for someone crossing in front of it
	local walkers = Workspace:FindFirstChild("GoDashPedestrians")
	if walkers then
		for _, m in ipairs(walkers:GetChildren()) do
			local p = m:IsA("Model") and m.PrimaryPart
			if p then table.insert(obstacles, { pos = p.Position, half = 1 }) end
		end
	end

	local blink = (t % 0.76) < 0.38
	-- route cars: drawn only within the tier's distance (client/Perf; 2026-11-18, with 70 of them across
	-- the whole tambon a phone was drawing cars it could not see), simulated a little beyond it
	local showR = Perf.limit("routeCars")
	local simR = showR + 220
	for _, c in pairs(cars) do
		local pos, dir, nextI, prevI, toNext = locate(c, c.s)
		local left = Vector3.new(dir.Z, 0, -dir.X)
		local here = pos + left * 7
		local dist = (here - camPos).Magnitude
		local show = dist < showR
		if show ~= c.shown and c.home and c.home.Parent then
			c.shown = show
			c.model.Parent = show and c.home or nil
			if not show then c.at = nil end
		end
		if dist < simR then
			local target = c.base
			if redAhead(c, nextI, prevI, toNext, t) then
				target = 0
			else
				local node = c.graph.nodes[c.ids[nextI]]
				if node and junctionWait(c, node, toNext, t) then
					target = math.min(target, math.max(0, (toNext - node.r - 7) * 1.4))
				end
			end
			local byPlayer, byAI
			target, byPlayer, byAI = lookAhead(c, here, dir, left, target, obstacles, t)
			unjam(c, target, byAI, dt, t)
			drive(c, target, byPlayer, here, dir, t, dt, blink)
		else
			-- out of sight: keep to the timetable
			c.v = c.base
			c.at = nil
		end
		c.s = (c.s + c.v * dt) % (c.total * 2)
	end
	-- local traffic
	if me and #locals > 0 then
		local want = math.floor(LOCAL_COUNT * busy() * Perf.scale * Perf.limit("locals") + 0.5)
		local slow = busy() > 1.2 and 0.66 or 1
		for i, c in ipairs(locals) do
			if i > want and (not c.active or not c.at or not inView(c.at, 600)) then
				-- fewer wanted: taken away only once out of view
				if c.active then c.active = false; c.at = nil; c.model.Parent = nil end
			elseif not c.active or (c.at and (c.at - me).Magnitude > LOCAL_DROP)
				or ((c.stillFor or 0) > 20 and c.at and not inView(c.at, 600)) then -- hopelessly stuck, out of view: start again elsewhere
				if spawnLocal(c, me, obstacles) then
					c.active = true
					c.model.Parent = localFolder
				elseif c.active then
					c.active = false
					c.at = nil
					c.model.Parent = nil
				end
			end
			if c.active then
				local e = c.e
				local toNext = e.len - c.s
				local node = c.sign > 0 and e.b or e.a
				local here, dir, left = laneOf(c)
				local target = c.base * slow
				if toNext < 45 and c.planned == nil then planTurn(c) end
				if c.turnOffAt and os.clock() > c.turnOffAt and c.s > 10 then c.turn, c.turnOffAt = nil, nil end
				if toNext < 30 and #node.links >= 3 then target = math.min(target, c.base * 0.55) end -- ease into junctions
				if mustStop(node, e, toNext, c.v, t) then
					target = 0
				elseif junctionWait(c, node, toNext, t) then
					target = math.min(target, math.max(0, (toNext - node.r - 7) * 1.4))
				end
				local byPlayer, byAI
				target, byPlayer, byAI = lookAhead(c, here, dir, left, target, obstacles, t)
				unjam(c, target, byAI, dt, t)
				drive(c, target, byPlayer, here, dir, t, dt, blink)
				c.s += c.v * dt
				if c.s >= e.len then nextStreet(c) end
			end
		end
	end
end

function Street.start()
	for _, m in ipairs(CollectionService:GetTagged("TrafficCar")) do prepare(m) end
	CollectionService:GetInstanceAddedSignal("TrafficCar"):Connect(function(m) task.defer(prepare, m) end)
	CollectionService:GetInstanceAddedSignal("TrafficSignal"):Connect(function(m) m:SetAttribute("Shown", nil) end)
	task.spawn(function()
		if not signalsById then
			local graph = GPS.graph()
			while not graph do task.wait(0.5); graph = GPS.graph() end
			local _, byId = Traffic.signals(graph)
			signalsById = byId
		end
		startLocals()
	end)

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		local t = Workspace:GetServerTimeNow()
		local cam = Workspace.CurrentCamera
		if cam then moveCars(t, math.min(dt, 0.1), cam.CFrame.Position) end
		acc += dt
		if acc > 0.25 then
			acc = 0
			local camPos = cam and cam.CFrame.Position
			for _, m in ipairs(CollectionService:GetTagged("TrafficSignal")) do paintSignal(m, t, camPos) end
		end
	end)
end

return Street
