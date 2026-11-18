-- Speed bumps (ลูกระนาด), 2026-11-18. Owner: "Thailand has to have them. Ride over one really fast and
-- the bike flies, or may even go down, with a cutscene: another gimmick."
--
-- Client only. The bumps are built in a ring around you from the road graph, at the same spots on
-- every device (they follow from the edge ids), and only your own vehicle reacts: you simulate it.
--   * where: sois and lanes, where real ones are; about one every SPACING studs, never close to a
--     junction, and about a third of the small streets have none. A gap at each kerb, as on real
--     streets, where motorbikes squeeze past.
--   * what happens, by speed across the bump (the speedometer shows studs/s as km/h):
--       under 15  a soft thump, the suspension takes it
--       15 - 35   a bounce; the camera jolts
--       35 - 70   both wheels leave the road for a moment; a two-wheeler may come down badly
--       over 70   a two-wheeler goes over the bars (client/Cutscene "crash" with its own caption);
--                 a car flies and lands hard (a little damage, like any hard knock)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Game = require(Shared.Config.Game)
local GPS = require(script.Parent.GPS)
local Drive = require(script.Parent.Drive)
local Feedback = require(script.Parent.Feedback)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)

local SpeedBumps = {}
local L = Lang.pick
local player = Players.LocalPlayer

local RING, DROP = 420, 540 -- build within, remove beyond (studs from you)
local SPACING, KEEP = 150, 28 -- studs between bumps; none this close to either end of a street
local HEIGHT, RADIUS = 0.42, 1.15 -- how far the hump rises above the road; the radius of its curve
local GAP = 2.2 -- open strip at each kerb
local STRIPE = 1.4 -- length of one yellow or black stripe
local YELLOW, BLACK = Color3.fromRGB(250, 196, 20), Color3.fromRGB(28, 28, 30)

local folder: Folder
local live = {} -- key -> bump { parts, center, along, across, half, sides = {wheel -> signed distance} }
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function noise(x: number): number
	local s = math.sin(x * 12.9898 + 78.233) * 43758.5453
	return s - math.floor(s)
end

-- the places along edge e that get a bump (distances from e.a), or nil
local function spots(e)
	if e.type ~= "soi" and e.type ~= "lane" then return nil end
	if e.len < KEEP * 2 + 30 then return nil end
	if noise(e.id) < 0.33 then return nil end
	local usable = e.len - KEEP * 2
	local n = math.max(1, math.floor(usable / SPACING + 0.5))
	local out = {}
	for i = 1, n do
		local jitter = (noise(e.id * 7 + i) - 0.5) * math.min(30, usable / n * 0.4)
		table.insert(out, KEEP + usable * (i - 0.5) / n + jitter)
	end
	return out
end

local function build(e, s: number)
	local along = Vector3.new(e.dx, 0, e.dz)
	local across = Vector3.new(-e.dz, 0, e.dx)
	local mid = Vector3.new(e.a.x + e.dx * s, 0, e.a.z + e.dz * s)
	-- sit on the real road surface (and wait while that part of town is not built yet)
	local hit = Workspace:Raycast(mid + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), params)
	if not hit or not hit.Instance:IsDescendantOf(Workspace:FindFirstChild("Map") or Workspace) then return nil end
	local y = hit.Position.Y
	local width = e.def.width - GAP * 2
	if width < 6 then return nil end
	local n = math.max(3, math.floor(width / STRIPE))
	local seg = width / n
	local center = Vector3.new(mid.X, y + HEIGHT - RADIUS, mid.Z)
	local base = CFrame.fromMatrix(center, across, Vector3.yAxis) -- the cylinders' axis (X) runs across the road
	local parts = {}
	for i = 1, n do
		local p = Instance.new("Part")
		p.Name = "SpeedBump"
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(seg + 0.02, RADIUS * 2, RADIUS * 2)
		p.CFrame = base * CFrame.new(-width / 2 + seg * (i - 0.5), 0, 0)
		p.Color = (i % 2 == 0) and BLACK or YELLOW
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanTouch = false
		-- (2026-11-18) not solid: a vehicle that stopped with a wheel on the hump could not drive off it,
		-- its suspension rays caught on the curve at walking pace (the long-delivery test sat there for
		-- minutes; measured: 0.4 studs in 2.5 s at 60% throttle, 36 studs once the hump was not solid).
		-- The bounce is the scripted kick below (LIFT_LOSS raised to make up for the springs).
		p.CanCollide = false
		p.CastShadow = false
		p.Parent = folder
		table.insert(parts, p)
	end
	return { parts = parts, center = Vector3.new(mid.X, y, mid.Z), along = along, across = across, half = width / 2, sides = {} }
end

local function refresh()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local graph = GPS.graph()
	if not root or not graph then return end
	local me = root.Position
	params.FilterDescendantsInstances = { folder, char, Workspace:FindFirstChild("Vehicles"), Workspace:FindFirstChild("GoDashPedestrians"),
		Workspace:FindFirstChild("GoDashLocalTraffic"), Workspace:FindFirstChild("NPCs") }
	local want = {}
	local made = 0
	for _, e in ipairs(graph:edgesNear(me, RING)) do
		local list = spots(e)
		if list then
			for i, s in ipairs(list) do
				local key = e.id .. ":" .. i
				local x, z = e.a.x + e.dx * s, e.a.z + e.dz * s
				local d = math.sqrt((x - me.X) ^ 2 + (z - me.Z) ^ 2)
				if d < RING then
					want[key] = true
					if not live[key] and made < 8 then -- a few per tick: no hitch while riding into new streets
						local b = build(e, s)
						if b then live[key] = b; made += 1 end
					end
				elseif d < DROP and live[key] then
					want[key] = true
				end
			end
		end
	end
	for key, b in pairs(live) do
		local qa = key:sub(1, 3) == "qa:" and (b.center - me).Magnitude < DROP -- Studio test bumps stay while you are near
		if not want[key] and not qa then
			for _, p in ipairs(b.parts) do p:Destroy() end
			live[key] = nil
		end
	end
end

-- how high the vehicle is thrown (studs) at this speed (km/h). Measured in Studio 2026-11-18: the
-- springs added a little on top while the hump was solid (x1.55 threw a moped 2.5 studs at 46 km/h);
-- the hump is not solid any more (see build), so the kick alone carries it: LIFT_LOSS 1
local LIFT_LOSS = 1.0
local function rise(kmh: number): number
	if kmh < 15 then return 0.08 end
	if kmh < 35 then return 0.08 + (kmh - 15) / 20 * 0.37 end
	if kmh < 70 then return 0.45 + (kmh - 35) / 35 * 1.15 end
	return math.min(2.4, 1.6 + (kmh - 70) / 40 * 0.8)
end

local fallBusy = 0

local function wheelOver(c, b, lp, wp: Vector3, vel: Vector3, grounded: boolean)
	local v = math.abs(vel:Dot(b.along))
	if v < 3 then return end
	-- one kick per axle (a car or a twin-wheel model has two wheels on each)
	local front = lp.Z < 0
	local axle = front and "f" or "r"
	b.kicked = b.kicked or {}
	if b.kicked[axle] and os.clock() - b.kicked[axle] < 0.8 then return end
	b.kicked[axle] = os.clock()
	local kmh = v * Game.KMH
	local bike = c.def.class == "bike"
	local g = Workspace.Gravity
	local chassis = c.chassis
	local mass = chassis.AssemblyMass
	local right = chassis.CFrame.RightVector
	local h = rise(kmh) * (bike and 1 or 0.75)
	local u = math.sqrt(2 * g * h) -- launch speed for that height
	local t = 2 * u / g -- time in the air
	local len = c.def.len or 6
	local pitchI = mass * len * len / 12
	if front then
		-- the front wheel hits it: the whole vehicle is thrown up and the nose lifts
		chassis:ApplyImpulse(Vector3.yAxis * mass * u * LIFT_LOSS)
		-- (x1.5 at 74 km/h stood a moped on its tail, 85°, in the first test: keep the nose lift small)
		chassis:ApplyAngularImpulse(right * pitchI * math.clamp(kmh / 45, 0.1, 1.5) * 0.22)
		Feedback.play("bump", math.clamp(0.25 + kmh / 80, 0.25, 0.9), 1.15 - math.min(0.35, kmh / 200), 0.05)
		if h > 0.3 then Feedback.fovKick(3 + h * 4, 0.25) end
		return
	end
	-- the back wheel: the tail kicks up, the nose drops (only if it is still on the road to be kicked)
	if grounded then chassis:ApplyAngularImpulse(-right * pitchI * math.clamp(kmh / 60, 0.1, 1.1) * 0.18) end
	if os.clock() < fallBusy then return end
	-- the back wheel is over: did a two-wheeler stay up?
	local fall = 0
	if bike then
		if kmh > 70 then fall = math.min(0.95, 0.75 + (kmh - 70) / 120)
		elseif kmh > 40 then fall = (kmh - 40) / 30 * 0.5 end
	end
	if fall > 0 and math.random() < fall then
		fallBusy = os.clock() + 6
		local dir = vel.Magnitude > 0.1 and Vector3.new(vel.X, 0, vel.Z).Unit or b.along
		task.delay(math.max(0.12, t * 0.8), function()
			local now = Drive.current()
			if not now or now ~= c or State.cutscene or not Drive.onCrash then return end
			Net.send("VehicleFall", v)
			Drive.onCrash({
				dir = dir, speed = v, model = c.model, car = false, feed = "speedbump",
				caption = L("🚧 Speed bump at full throttle! Over the handlebars", "🚧 ลูกระนาด! ซิ่งมาเต็มสปีด ปลิวข้ามแฮนด์"),
			})
		end)
	elseif not bike and kmh > 75 and os.clock() > fallBusy then
		fallBusy = os.clock() + 3
		task.delay(t + 0.1, function() Net.send("VehicleFall", v * 0.5) end) -- the landing knocks the suspension (and your neck)
	end
end

function SpeedBumps.start()
	folder = Instance.new("Folder")
	folder.Name = "GoDashSpeedBumps"
	folder.Parent = Workspace
	task.spawn(function()
		while true do
			pcall(refresh)
			task.wait(1)
		end
	end)
	-- each wheel crossing a bump's centre line gets its kick
	RunService.Heartbeat:Connect(function()
		local c = Drive.current()
		if not c or State.cutscene or not c.wheels or not c.contacts then return end
		local chassis = c.chassis
		local cf = chassis.CFrame
		local pos = chassis.Position
		local vel = chassis.AssemblyLinearVelocity
		for _, b in pairs(live) do
			local rel = pos - b.center
			if math.abs(rel.X) < 40 and math.abs(rel.Z) < 40 then
				for i, lp in ipairs(c.wheels) do
					local wp = cf:PointToWorldSpace(Vector3.new(lp.X, 0, lp.Z))
					local off = wp - b.center
					local d = off:Dot(b.along)
					local prev = b.sides[i]
					b.sides[i] = d
					local contact = c.contacts[i]
					-- the front must be on the road to be kicked; the back counts even in the air (it decides the fall)
					if prev and (prev > 0) ~= (d > 0) and math.abs(prev - d) < 8 and math.abs(off:Dot(b.across)) <= b.half + 0.4
						and (lp.Z >= 0 or (contact and contact.ok)) then
						wheelOver(c, b, lp, wp, vel, contact ~= nil and contact.ok == true)
					end
				end
			else
				if next(b.sides) then b.sides = {} end
			end
		end
	end)
	-- Studio QA: Workspace QaBumpAhead = studs -> a bump appears that far in front of your vehicle
	if RunService:IsStudio() then
		Workspace:GetAttributeChangedSignal("QaBumpAhead"):Connect(function()
			local dist = Workspace:GetAttribute("QaBumpAhead")
			if type(dist) ~= "number" then return end
			Workspace:SetAttribute("QaBumpAhead", nil)
			local c = Drive.current()
			if not c then return end
			local look = Vector3.new(c.chassis.CFrame.LookVector.X, 0, c.chassis.CFrame.LookVector.Z).Unit
			local at = c.chassis.Position + look * dist
			-- a one-point "street" running the way you face: the hump lies across it
			local b = build({ id = -1, type = "lane", len = 1, dx = look.X, dz = look.Z, a = { x = at.X, z = at.Z }, def = { width = 16 } }, 0)
			if b then live["qa:" .. os.clock()] = b end
		end)
	end
end

return SpeedBumps
