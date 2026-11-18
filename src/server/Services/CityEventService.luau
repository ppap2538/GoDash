-- Random things happening in town (2026-11-19, owner: "เพิ่มตามแนะนำได้เลย": random city events).
-- Every 5-9 minutes, on a street 250-650 studs from a rider who is out driving, one of:
--   * breakdown: a car stopped in the kerb lane with its hazards on, a warning triangle behind it and the
--     driver waving for help
--   * crash: two cars that bumped, debris, cones round them and a police officer waving the traffic past
--   * market (evenings, on a soi): a pop-up market closes the street: barriers at both ends, stalls, shoppers
-- Each stays 3-5 minutes and is then cleared away; at most two at a time. AI traffic stops for them (the
-- invisible "GoDashObstacle" boxes, client/Street), riders within 900 studs get a heads-up toast, and a ⚠️
-- marker floats over the spot. Everything is anchored props: nothing here costs or pays money.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local RiderPose = require(Shared.RiderPose)
local World = script.Parent.Parent:WaitForChild("World")
local Kit = require(World.Kit)
local Assets = require(World.Assets)
local S = require(World.Scenery)

local Service = {}
local V3, CF, rad = Vector3.new, CFrame.new, math.rad
local M = Enum.Material
local rng = Random.new()
local ROAD_Y = 0.24
local ORANGE, WHITE = Color3.fromRGB(240, 110, 30), Color3.fromRGB(240, 240, 236)
local AMBER = Color3.fromRGB(255, 170, 40)
local active = {} -- { { model, untilT, blink = { parts } } }
local folder

local function cone(parent: Instance, cf: CFrame)
	Kit.cyl(parent, 0.95, 0.75, cf * CF(0, 0.45, 0), ORANGE, M.SmoothPlastic)
	Kit.cyl(parent, 0.75, 0.3, cf * CF(0, 0.97, 0), WHITE, M.SmoothPlastic, { decor = true })
	Kit.cyl(parent, 0.5, 0.7, cf * CF(0, 1.45, 0), ORANGE, M.SmoothPlastic, { decor = true })
end

-- an invisible box AI traffic stops for (client/Street reads the tag)
local function blocker(parent: Instance, cf: CFrame, size: Vector3)
	local p = Kit.part(parent, size, cf * CF(0, size.Y / 2, 0), WHITE, M.SmoothPlastic, { decor = true, transparency = 1 })
	p.CanCollide = false
	p.CanQuery = false
	p.Name = "Obstacle"
	CollectionService:AddTag(p, "GoDashObstacle")
	return p
end

local function marker(parent: Instance, at: Vector3, text: string)
	local a = Kit.part(parent, V3(0.4, 0.4, 0.4), CF(at), WHITE, M.SmoothPlastic, { decor = true, transparency = 1 })
	a.CanCollide = false
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(170, 44)
	bb.StudsOffsetWorldSpace = V3(0, 14, 0)
	bb.MaxDistance = 420
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	t.BackgroundTransparency = 0.2
	t.TextColor3 = Color3.fromRGB(255, 210, 80)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = text
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = t
	t.Parent = bb
	bb:SetAttribute("NoTranslate", true)
	bb.Parent = a
end

-- a parked car prop (mesh model when the place has it, else a part box), facing along cf's -Z
local CARS = { "v_sedan", "v_hatch", "v_pickup", "v_suv" }
local function car(parent: Instance, cf: CFrame): { BasePart }
	local name = CARS[rng:NextInteger(1, #CARS)]
	local m = Assets.place(parent, name, cf)
	local len, wid, h = 13, 5.6, 4.6
	if m then
		local size = m:GetExtentsSize()
		len, wid, h = math.max(size.X, size.Z), math.min(size.X, size.Z), size.Y
	else
		local col = ({ Color3.fromRGB(200, 200, 204), Color3.fromRGB(40, 40, 46), Color3.fromRGB(150, 30, 34), Color3.fromRGB(30, 60, 120) })[rng:NextInteger(1, 4)]
		Kit.part(parent, V3(wid, 2.4, len), cf * CF(0, 1.8, 0), col, M.SmoothPlastic)
		Kit.part(parent, V3(wid - 0.4, 1.6, len * 0.55), cf * CF(0, 3.6, 0.6), col, M.SmoothPlastic, { decor = true })
	end
	-- hazard lights at the four corners (blinked by the loop below)
	local lights = {}
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = Kit.part(parent, V3(0.5, 0.35, 0.3), cf * CF(sx * (wid / 2 - 0.4), h * 0.42, sz * (len / 2 + 0.05)), AMBER, M.Neon, { decor = true })
			table.insert(lights, p)
		end
	end
	return lights
end

local function figure(parent: Instance, npc, cf: CFrame, pose: string, police: boolean?)
	local names = npc.pedNames()
	if #names == 0 then return nil end
	local fig = npc.figure(cf, names[rng:NextInteger(1, #names)], pose)
	if not fig then return nil end
	if police then pcall(RiderPose.policeUniform, fig.model) end
	fig.model.Parent = parent
	return fig.model
end

local function roadName(e): string
	if e.thai and e.thai ~= "" then return e.thai end
	if e.name and e.name ~= "" then return e.name end
	return "a street nearby"
end

-- a spot on edge e at distance s: the road's centre line frame (local -Z along the edge, +X = right)
local function frameOn(e, s: number): CFrame
	local x, z = e.a.x + e.dx * s, e.a.z + e.dz * s
	local y = (e.def and e.def.y) or ROAD_Y
	return CFrame.lookAt(V3(x, y, z), V3(x + e.dx, y, z + e.dz))
end

---------------------------------------------------------------------------------------------------
local function breakdown(m: Model, npc, e, s: number)
	local half = e.def.width / 2
	local base = frameOn(e, s) * CF(-(half - 3.3), 0, 0) -- the kerb lane (Thai traffic keeps left)
	local lights = car(m, base)
	-- the warning triangle a car length behind, the driver on the kerb waving for help
	local tri = Kit.part(m, V3(1.6, 1.5, 0.12), base * CF(0, 0.8, 16) * CFrame.Angles(rad(-12), 0, 0), Color3.fromRGB(220, 40, 30), M.SmoothPlastic, { decor = true })
	Kit.sign(tri, "⚠", { face = Enum.NormalId.Back, bg = Color3.fromRGB(220, 40, 30), color = WHITE })
	figure(m, npc, base * CF(-3.8, 0, -1) * CFrame.Angles(0, rad(90), 0), "hail")
	blocker(m, base * CF(0, 0, 2), V3(6, 5, 18))
	marker(m, (base * CF(0, 0, 0)).Position, "⚠️ รถเสีย")
	return lights, ("⚠️ Broken-down car blocking a lane on %s"):format(roadName(e))
end

local function crash(m: Model, npc, e, s: number)
	local half = e.def.width / 2
	local lane = frameOn(e, s) * CF(-(half * 0.5), 0, 0)
	local lights = car(m, lane)
	for _, p in ipairs(car(m, lane * CF(1.2, 0, 13.5) * CFrame.Angles(0, rad(18), 0))) do table.insert(lights, p) end
	-- debris and glass
	for _ = 1, 9 do
		local p = Kit.part(m, V3(rng:NextNumber(0.3, 0.9), 0.12, rng:NextNumber(0.3, 0.9)), lane * CF(rng:NextNumber(-3, 3), 0.08, rng:NextNumber(5, 9)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			({ Color3.fromRGB(40, 40, 44), Color3.fromRGB(190, 210, 220), Color3.fromRGB(150, 30, 30) })[rng:NextInteger(1, 3)], M.SmoothPlastic, { decor = true })
		p.CanCollide = false
	end
	-- cones round them, the officer waving traffic past in the other lane
	for z = -6, 24, 5 do cone(m, lane * CF(half * 0.5 - 1.2, 0, z)) end
	for _, z in ipairs({ -8, 26 }) do cone(m, lane * CF(-2, 0, z)); cone(m, lane * CF(2, 0, z)) end
	figure(m, npc, lane * CF(half * 0.5 + 1.5, 0, 32) * CFrame.Angles(0, rad(180), 0), "hail", true)
	figure(m, npc, lane * CF(-half * 0.5 - 1, 0, 8) * CFrame.Angles(0, rad(70), 0), "stand")
	-- a flashing police lamp on a stand
	local lamp = Kit.part(m, V3(0.6, 0.6, 0.6), lane * CF(half * 0.5 - 1.2, 3.4, 30), Color3.fromRGB(40, 90, 255), M.Neon, { decor = true })
	Kit.part(m, V3(0.18, 3.2, 0.18), lane * CF(half * 0.5 - 1.2, 1.6, 30), Color3.fromRGB(60, 60, 64), M.Metal, { decor = true })
	table.insert(lights, lamp)
	blocker(m, lane * CF(0, 0, 9), V3(half, 5, 34))
	marker(m, lane.Position, "⚠️ อุบัติเหตุ")
	return lights, ("⚠️ Accident ahead on %s: slow down"):format(roadName(e))
end

local function market(m: Model, npc, e, s: number)
	local half = e.def.width / 2
	local base = frameOn(e, s)
	-- red and white barriers across both ends
	for _, z in ipairs({ -34, 34 }) do
		for x = -half + 1.5, half - 1.5, 3 do
			Kit.part(m, V3(2.6, 1.6, 1.2), base * CF(x, 0.8, z), (math.floor(x) % 2 == 0) and Color3.fromRGB(210, 40, 36) or WHITE, M.SmoothPlastic)
		end
	end
	local sign = Kit.part(m, V3(10, 2.4, 0.3), base * CF(0, 6.2, -35), Color3.fromRGB(240, 190, 40), M.SmoothPlastic, { decor = true })
	Kit.sign(sign, "ตลาดนัดปิดถนน", { sub = "POP-UP MARKET · ขออภัยในความไม่สะดวก", color = Color3.fromRGB(60, 30, 10), light = true })
	for _, sx in ipairs({ -5.4, 5.4 }) do
		Kit.part(m, V3(0.3, 5, 0.3), base * CF(sx, 2.5, -35), Color3.fromRGB(60, 60, 64), M.Metal, { decor = true })
	end
	-- stalls down both sides, shoppers in the middle
	local labels = { "ไก่ทอด", "ส้มตำ", "น้ำปั่น", "ลูกชิ้นปิ้ง", "เสื้อผ้ามือสอง", "ขนมครก" }
	local k = 0
	for _, side in ipairs({ -1, 1 }) do
		for z = -24, 24, 12 do
			k += 1
			S.stall(m, base * CF(side * (half - 3), 0, z) * CFrame.Angles(0, rad(side * 90), 0), rng, labels[(k - 1) % #labels + 1])
		end
	end
	-- (2026-11-19 phone pass: each avatar figure is a few hundred instances; 7 made the market ~3,500)
	for _ = 1, 4 do
		figure(m, npc, base * CF(rng:NextNumber(-half + 6, half - 6), 0, rng:NextNumber(-26, 26)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), "stand")
	end
	blocker(m, base * CF(0, 0, -34), V3(half * 2, 5, 3))
	blocker(m, base * CF(0, 0, 34), V3(half * 2, 5, 3))
	marker(m, base.Position, "🛍 ตลาดนัด")
	return {}, ("🛍 A pop-up market has closed %s"):format(roadName(e))
end

---------------------------------------------------------------------------------------------------
local function riders(): { Player }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then table.insert(out, p) end
	end
	return out
end

local function spawnOne(world, deps, force: string?)
	if #active >= 2 then return end
	local list = riders()
	if #list == 0 then return end
	local who = list[rng:NextInteger(1, #list)]
	local root = who.Character and who.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local here = root.Position
	local hour = deps.time and deps.time.clock and deps.time.clock() or 12
	local evening = hour >= 16.5 and hour <= 23
	local kind = force or ((evening and rng:NextNumber() < 0.4) and "market" or (rng:NextNumber() < 0.5 and "breakdown" or "crash"))
	-- a street 250-650 studs away, long enough, the right size for the kind
	local options = {}
	for _, e in ipairs(world.graph:edgesNear(here, 650)) do
		local mid = V3((e.a.x + e.b.x) / 2, 0, (e.a.z + e.b.z) / 2)
		local d = (mid - V3(here.X, 0, here.Z)).Magnitude
		local w = e.def and e.def.width or 0
		local fits = (kind == "market" and (e.type == "soi" or e.type == "lane") and e.len > 90 and w >= 16) -- (12 left one shoulder-width aisle)
			or (kind ~= "market" and e.type ~= "highway" and e.type ~= "soi" and e.type ~= "lane" and e.len > 110 and w >= 20)
		if fits and d > 250 and d < 650 then table.insert(options, e) end
	end
	if #options == 0 then return end
	local e = options[rng:NextInteger(1, #options)]
	local s = rng:NextNumber(45, e.len - 45)
	local m = Instance.new("Model")
	m.Name = "CityEvent_" .. kind
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local ok, lights, text = pcall(kind == "market" and market or (kind == "crash" and crash or breakdown), m, deps.npc, e, s)
	if not ok then
		warn("[CityEvents] " .. tostring(lights))
		m:Destroy()
		return
	end
	m.Parent = folder
	local life = kind == "market" and 300 or (kind == "crash" and 240 or 180)
	table.insert(active, { model = m, untilT = os.clock() + life, lights = lights or {}, at = frameOn(e, s).Position, kind = kind })
	-- heads-up for riders near it
	local at = frameOn(e, s).Position
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and (r.Position - at).Magnitude < 900 then
			Net.fire(p, "Notify", "toast", { text = text, bad = true })
		end
	end
	print(("[CityEvents] %s on %s (%d s)"):format(kind, roadName(e), life))
end

function Service.start(world, deps)
	folder = Instance.new("Folder")
	folder.Name = "CityEvents"
	folder.Parent = Workspace
	-- the first one a few minutes in, then every 5-9 minutes
	task.spawn(function()
		local nextAt = os.clock() + rng:NextNumber(150, 240)
		local blinkOn = false
		while true do
			task.wait(0.4)
			blinkOn = not blinkOn
			for i = #active, 1, -1 do
				local ev = active[i]
				if os.clock() > ev.untilT or not ev.model.Parent then
					ev.model:Destroy()
					table.remove(active, i)
				else
					for _, p in ipairs(ev.lights) do
						if p.Parent then p.Transparency = blinkOn and 0 or 0.85 end
					end
				end
			end
			if os.clock() > nextAt then
				nextAt = os.clock() + rng:NextNumber(300, 540)
				local ok, err = pcall(spawnOne, world, deps)
				if not ok then warn("[CityEvents] " .. tostring(err)) end
			end
		end
	end)
	-- Studio QA: Workspace QaCityEvent = "breakdown" | "crash" | "market" -> one now, near the first rider
	if game:GetService("RunService"):IsStudio() then
		Workspace:GetAttributeChangedSignal("QaCityEvent"):Connect(function()
			local want = Workspace:GetAttribute("QaCityEvent")
			if want then
				Workspace:SetAttribute("QaCityEvent", nil)
				local ok, err = pcall(spawnOne, world, deps, type(want) == "string" and want or nil)
				if not ok then warn("[CityEvents] " .. tostring(err)) end
			end
		end)
	end
end

return Service
