-- Police checkpoints (owner, 2026-11-16: "add police checkpoints: drive into one and you pay a fine,
-- so you have to try to drive around them").
--   * COUNT checkpoints stand across main streets: cones down the lane lines, a striped barrier on
--     each kerb, "ด่านตรวจ" signs for both directions, a tent with a flashing light, and officers
--     waving light batons.
--   * Driving a motor vehicle through the gate costs FINE (bicycles need no licence: free). Going
--     round it (another street, or over the pavement past the gate) is the way out.
--   * Every MOVE_EVERY seconds a few of them pack up and set up somewhere else.
--   * Clients learn where they are from ReplicatedStorage.GoDashCheckpoints (CFrameValues: the gate
--     centre facing along the road; attribute Width) for the minimap, the map and the warning.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Fines = require(script.Parent.FineService)
local Gear = require(game:GetService("ReplicatedStorage").Shared.Config.Gear)
local Kit = require(script.Parent.Parent.World.Kit)
local RiderPose = require(Shared.RiderPose)

local Police = {}
Police.FINE = 150
local COUNT = 24 -- (12 round the centre until 2026-11-18; the whole tambon now)
local MOVE_EVERY = 300 -- seconds
local MOVE_SHARE = 4 -- how many move each time
local GATE_HALF = 7 -- studs along the road either side of the gate line that count as "through"
local ROAD_Y = 0.24

local V3, CF = Vector3.new, CFrame.new
local rad = math.rad
local ORANGE = Color3.fromRGB(255, 110, 20)
local WHITE = Color3.fromRGB(245, 245, 240)
local RED = Color3.fromRGB(205, 30, 36)
local NAVY = Color3.fromRGB(28, 40, 74)
local KHAKI = Color3.fromRGB(138, 104, 64)
local M = Enum.Material

local rng = Random.new()

local function cone(parent: Instance, cf: CFrame)
	local o = { decor = true }
	Kit.part(parent, V3(1.25, 0.14, 1.25), cf * CF(0, 0.07, 0), Color3.fromRGB(40, 40, 42), M.SmoothPlastic, o)
	Kit.cyl(parent, 0.95, 0.75, cf * CF(0, 0.5, 0), ORANGE, M.SmoothPlastic, o)
	Kit.cyl(parent, 0.78, 0.3, cf * CF(0, 1.02, 0), WHITE, M.SmoothPlastic, { decor = true, reflectance = 0.25 })
	Kit.cyl(parent, 0.55, 0.7, cf * CF(0, 1.52, 0), ORANGE, M.SmoothPlastic, o)
end

-- red-and-white striped barrier on two legs, 6 long, its length along local X
local function barrier(parent: Instance, cf: CFrame)
	local o = { decor = true }
	for _, sx in ipairs({ -2.6, 2.6 }) do
		Kit.part(parent, V3(0.25, 2.2, 0.25), cf * CF(sx, 1.1, 0), Color3.fromRGB(60, 60, 64), M.Metal, o)
		Kit.part(parent, V3(0.25, 0.12, 1.4), cf * CF(sx, 0.06, 0), Color3.fromRGB(60, 60, 64), M.Metal, o)
	end
	for i = 0, 5 do
		Kit.part(parent, V3(1.0, 0.7, 0.18), cf * CF(-2.5 + i, 1.75, 0), i % 2 == 0 and RED or WHITE, M.SmoothPlastic, o)
	end
end

local function signBoard(parent: Instance, cf: CFrame)
	local o = { decor = true }
	for _, sx in ipairs({ -1.6, 1.6 }) do
		Kit.part(parent, V3(0.18, 3.6, 0.18), cf * CF(sx, 1.8, 0.05) * CFrame.Angles(rad(-8), 0, 0), Color3.fromRGB(70, 70, 74), M.Metal, o)
	end
	local board = Kit.part(parent, V3(4.2, 2.6, 0.15), cf * CF(0, 3.0, 0) * CFrame.Angles(rad(-8), 0, 0), NAVY, M.SmoothPlastic, o)
	board.CanQuery = true -- the fine scene's camera checks for clear views with rays: it must see the board and not park behind it
	Kit.sign(board, "ด่านตรวจ", { face = Enum.NormalId.Front, bg = NAVY, sub = "POLICE CHECKPOINT · ชะลอความเร็ว", light = true, pps = 40 })
	Kit.part(parent, V3(4.2, 0.25, 0.17), cf * CF(0, 1.62, 0.02) * CFrame.Angles(rad(-8), 0, 0), RED, M.SmoothPlastic, o)
end

local function tent(parent: Instance, cf: CFrame)
	local o = { decor = true }
	for _, p in ipairs({ { -3.2, -3.2 }, { 3.2, -3.2 }, { -3.2, 3.2 }, { 3.2, 3.2 } }) do
		Kit.part(parent, V3(0.22, 7, 0.22), cf * CF(p[1], 3.5, p[2]), Color3.fromRGB(200, 200, 205), M.Metal, o)
	end
	Kit.part(parent, V3(7, 0.3, 7), cf * CF(0, 7.1, 0), Color3.fromRGB(30, 70, 150), M.Fabric, o)
	Kit.wedge(parent, V3(7, 1.1, 3.5), cf * CF(0, 7.8, -1.75) * CFrame.Angles(0, rad(180), 0), Color3.fromRGB(235, 235, 240), M.Fabric, o)
	Kit.wedge(parent, V3(7, 1.1, 3.5), cf * CF(0, 7.8, 1.75), Color3.fromRGB(235, 235, 240), M.Fabric, o)
	local valance = Kit.part(parent, V3(7, 0.9, 0.08), cf * CF(0, 6.5, -3.5), Color3.fromRGB(30, 70, 150), M.Fabric, o)
	Kit.sign(valance, "ตำรวจ · POLICE", { face = Enum.NormalId.Front, bg = Color3.fromRGB(30, 70, 150), light = true, pps = 30 })
	-- table and two chairs
	Kit.part(parent, V3(4, 0.15, 1.8), cf * CF(0, 2.5, 0.6), WHITE, M.SmoothPlastic, o)
	for _, p in ipairs({ { -1.8, -0.2 }, { 1.8, -0.2 }, { -1.8, 1.4 }, { 1.8, 1.4 } }) do
		Kit.part(parent, V3(0.12, 2.5, 0.12), cf * CF(p[1], 1.25, p[2]), Color3.fromRGB(150, 150, 155), M.Metal, o)
	end
	for _, sx in ipairs({ -1, 1 }) do
		Kit.part(parent, V3(1.3, 0.15, 1.3), cf * CF(sx, 1.5, 2.2), Color3.fromRGB(40, 90, 170), M.SmoothPlastic, o)
		Kit.part(parent, V3(1.3, 1.4, 0.15), cf * CF(sx, 2.2, 2.85), Color3.fromRGB(40, 90, 170), M.SmoothPlastic, o)
	end
	-- the light bar on a pole by the kerb corner
	Kit.part(parent, V3(0.2, 8.2, 0.2), cf * CF(-3.2, 4.1, -3.4), Color3.fromRGB(60, 60, 64), M.Metal, o)
	Kit.part(parent, V3(2.4, 0.35, 0.5), cf * CF(-3.2, 8.3, -3.4), Color3.fromRGB(30, 30, 32), M.SmoothPlastic, o)
	local r = Kit.part(parent, V3(1.05, 0.38, 0.55), cf * CF(-3.75, 8.3, -3.4), RED, M.Neon, { decor = true, name = "FlashA" })
	local b = Kit.part(parent, V3(1.05, 0.38, 0.55), cf * CF(-2.65, 8.3, -3.4), Color3.fromRGB(40, 90, 255), M.Neon, { decor = true, name = "FlashB" })
	local la = Instance.new("PointLight"); la.Color = RED; la.Range = 22; la.Brightness = 2; la.Shadows = false; la.Parent = r
	local lb = Instance.new("PointLight"); lb.Color = Color3.fromRGB(40, 90, 255); lb.Range = 22; lb.Brightness = 2; lb.Shadows = false; lb.Parent = b
end

-- an officer: an avatar figure with a peaked cap, a reflective vest and (waving) a red light baton
local function officer(parent: Instance, npc, cf: CFrame, pose: string)
	local names = npc.pedNames()
	if #names == 0 then return end
	local fig = npc.figure(cf, names[rng:NextInteger(1, #names)], pose)
	if not fig then return end
	local m = fig.model
	m.Name = "Officer"
	local o = { decor = true }
	-- the khaki uniform (Thai police: khaki shirt and trousers, black shoes). The avatars are skinned
	-- meshes, so nothing is stuck on top of them (it floats off the real body): the clothes texture of
	-- those parts is taken off and the part itself is coloured.
	RiderPose.policeUniform(m)
	if pose == "hail" then
		local hand = m:FindFirstChild("RightHand") :: BasePart?
		if hand then
			Kit.cyl(m, 0.26, 0.5, hand.CFrame * CF(0, -0.25, 0), Color3.fromRGB(30, 30, 32), M.SmoothPlastic, o)
			local baton = Kit.cyl(m, 0.3, 1.9, hand.CFrame * CF(0, -1.4, 0), Color3.fromRGB(255, 50, 30), M.Neon, o)
			baton.Name = "Baton"
			local l = Instance.new("PointLight"); l.Color = Color3.fromRGB(255, 60, 40); l.Range = 9; l.Brightness = 1.5; l.Shadows = false; l.Parent = baton
		end
	end
	m.Parent = parent
end

local function build(folder: Instance, npc, id: string, cf: CFrame, width: number): Model
	local model = Instance.new("Model")
	model.Name = id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local half = width / 2
	-- (cf looks along the road; traffic heading that way keeps left = local -X and comes from +Z,
	-- traffic the other way keeps to +X and comes from -Z)
	-- cones down both kerb lines and the centre line, so the traffic runs through a gate
	for z = -12, 12, 4 do
		for _, x in ipairs({ -half + 0.7, 0, half - 0.7 }) do cone(model, cf * CF(x, 0, z)) end
	end
	-- striped barriers along the kerbs at the gate; a sign on the left of each approach, facing it
	barrier(model, cf * CF(-half - 1.6, 0, 0) * CFrame.Angles(0, rad(90), 0))
	barrier(model, cf * CF(half + 1.6, 0, 0) * CFrame.Angles(0, rad(90), 0))
	signBoard(model, cf * CF(-half - 1.2, 0, 38) * CFrame.Angles(0, rad(180), 0))
	signBoard(model, cf * CF(half + 1.2, 0, -38))
	-- the tent on the left pavement past the gate, open toward the road
	tent(model, cf * CF(-half - 5, 0, -13) * CFrame.Angles(0, rad(-90), 0))
	-- officers by the centre line waving the traffic that comes at them, one more at the tent
	officer(model, npc, cf * CF(-1.8, 0, 4) * CFrame.Angles(0, rad(180), 0), "hail")
	officer(model, npc, cf * CF(1.8, 0, -4), "hail")
	officer(model, npc, cf * CF(-half - 2.4, 0, -9) * CFrame.Angles(0, rad(-90), 0), "stand")
	model.Parent = folder
	return model
end

function Police.start(world, deps)
	local graph = world.graph
	local vehicles = deps.vehicles
	local npc = deps.npc
	local hub = world.pois.hub and world.pois.hub.door or Vector3.zero

	local folder = Instance.new("Folder")
	folder.Name = "PoliceCheckpoints"
	folder.Parent = Workspace
	local info = Instance.new("Folder")
	info.Name = "GoDashCheckpoints"
	info.Parent = ReplicatedStorage

	-- candidate spots: the middle of longer main streets inside the busy part of the city
	local spots = {}
	for _, e in ipairs(graph.edges) do
		if (e.type == "main" or e.type == "street") and not e.minor and e.len >= 90 then
			local mid = (e.a.pos + e.b.pos) / 2
			local d = (Vector3.new(mid.X, 0, mid.Z) - Vector3.new(hub.X, 0, hub.Z)).Magnitude
			if d > 320 and d < (world.radius or 3000) then table.insert(spots, e) end
		end
	end
	local live = {} -- [id] = { cf, width, model, value }
	local function taken(pos: Vector3): boolean
		for _, c in pairs(live) do
			if (c.cf.Position - pos).Magnitude < 420 then return true end
		end
		return false
	end
	local function place(id: string)
		for _ = 1, 40 do
			local e = spots[rng:NextInteger(1, #spots)]
			local a, b = e.a.pos, e.b.pos
			local mid = (a + b) / 2
			local pos = Vector3.new(mid.X, ROAD_Y, mid.Z)
			if not taken(pos) then
				local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
				local cf = CFrame.lookAt(pos, pos + dir)
				local width = e.def.width or 20
				local value = Instance.new("CFrameValue")
				value.Name = id
				value.Value = cf
				value:SetAttribute("Width", width)
				value.Parent = info
				live[id] = { cf = cf, width = width, value = value, model = build(folder, npc, id, cf, width) }
				return
			end
		end
	end
	local function remove(id: string)
		local c = live[id]
		if not c then return end
		live[id] = nil
		if c.model then c.model:Destroy() end
		if c.value then c.value:Destroy() end
	end
	if #spots == 0 then
		warn("[Police] no streets for checkpoints")
		return
	end
	for i = 1, COUNT do place("CP" .. i) end
	print(("[Police] %d checkpoints on %d candidate streets"):format(#info:GetChildren(), #spots))

	-- every few minutes some pack up and move
	task.spawn(function()
		while true do
			task.wait(MOVE_EVERY)
			local ids = {}
			for id in pairs(live) do table.insert(ids, id) end
			for _ = 1, math.min(MOVE_SHARE, #ids) do
				local id = table.remove(ids, rng:NextInteger(1, #ids))
				remove(id)
				place(id)
			end
		end
	end)

	-- the flashing lights
	task.spawn(function()
		local on = false
		while true do
			task.wait(0.45)
			on = not on
			for _, c in pairs(live) do
				local m = c.model
				local a, b = m and m:FindFirstChild("FlashA", true), m and m:FindFirstChild("FlashB", true)
				if a and b then
					(a :: BasePart).Transparency = on and 0 or 0.75;
					(b :: BasePart).Transparency = on and 0.75 or 0
					local la, lb = a:FindFirstChildOfClass("PointLight"), b:FindFirstChildOfClass("PointLight")
					if la then la.Enabled = on end
					if lb then lb.Enabled = not on end
				end
			end
		end
	end)

	-- the gate: who drives through it pays
	local fined = {} -- [player] = { [id] = clock }
	Players.PlayerRemoving:Connect(function(p) fined[p] = nil end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			for _, player in ipairs(Players:GetPlayers()) do
				local v = vehicles.driving(player)
				if v and v.chassis and not v.def.pedal then
					local pos = v.chassis.Position
					for id, c in pairs(live) do
						local rel = c.cf:PointToObjectSpace(Vector3.new(pos.X, ROAD_Y, pos.Z))
						if math.abs(rel.Z) < GATE_HALF and math.abs(rel.X) < c.width / 2 then
							fined[player] = fined[player] or {}
							local last = fined[player][id]
							if not last or os.clock() - last > 90 then
								fined[player][id] = os.clock()
								local d = Data.get(player)
								-- (2026-11-17) no licence for this kind of vehicle: twice the fine (server/LicenseService)
								local class = v.def.class == "car" and "car" or "bike"
								local noLicence = d ~= nil and d.licence ~= nil and d.licence[class] ~= true
								-- (2026-11-19) a motorbike without a helmet (Config/Gear): half a fine more
								-- (helmets were taken out of the game 2026-11-19: Gear.HELMETS = false, no surcharge then)
								local noHelmet = Gear.HELMETS and class == "bike" and d ~= nil and Gear.worn(d.gear, "helmet") == nil
								local fine = Police.FINE * ((noLicence and 2 or 1) + (noHelmet and 0.5 or 0))
								-- (2026-11-19) the daily limit: past it the officers only warn (server/FineService)
								local ok, amount, why, n, limit = Fines.charge(player, "ticket", fine, "checkpoint")
								if ok then
									local en, th = Fines.countText(n, limit)
									Net.fire(player, "Notify", "toast", { text = ("🚨 Police checkpoint! Fine %s"):format(amount > 0 and ("฿" .. amount) or "(no cash)") .. en,
										th = ("🚨 ด่านตรวจ! ปรับ %s"):format(amount > 0 and ("฿" .. amount) or "(ไม่มีเงินสด)") .. th, bad = true })
									Net.fire(player, "Notify", "scene", { kind = "fine", reason = noLicence and "nolicence" or (noHelmet and "nohelmet" or "checkpoint"), amount = amount, n = n, limit = limit }) -- client/Cutscene: pulled over, a ticket
									Net.fire(player, "Notify", "feed", { key = noLicence and "nolicence" or "fine_checkpoint", vars = { amount = amount, pos = pos } })
								else
									Fines.warn(player, "ticket", why, "🚨 Police checkpoint", "🚨 ด่านตรวจ")
								end
							end
						end
					end
				end
			end
		end
	end)
end

return Police
