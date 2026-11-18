-- Server-side NPCs: shop staff and landmark staff (static), plus a small pool of job NPCs
-- (customers, passengers). Also owns every world ProximityPrompt and routes it by kind.
-- Pedestrians are client-side (see client PedestrianController) so they cost the server nothing.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Rig = require(Shared.Rig)
local RiderPose = require(Shared.RiderPose)
local Dialogue = require(Shared.Config.Dialogue)
local Net = require(Shared.Net)
local Kit = require(script.Parent.Parent.World.Kit)
local Assets = require(script.Parent.Parent.World.Assets)
local Solid = require(script.Parent.Parent.World.Solid)

local NPC = {}
local handlers = {} -- [kind] = fn(player, id, promptPart)
local folder, interactions
local rng = Random.new()
local pool = {} -- spare job rigs

local OUTFIT = {
	restaurant = "staff", convenience = "shopkeeper", cafe = "staff", market = "shopkeeper", nightmarket = "staff",
	agri = "farmer", seedshop = "farmer", farm = "farmer", hub = "rider", police = "police", hospital = "nurse",
	gas = "shopkeeper", dealer = "shopkeeper", homestore = "shopkeeper", mall = "shopkeeper", bus = "shopkeeper",
	station = "shopkeeper", reststop = "shopkeeper",
	-- 2026-11-18 landmark batch (the front-desk person / guard)
	government = "staff", museum = "staff", school = "staff",
}

function NPC.handle(kind: string, fn)
	handlers[kind] = fn
end

-- World prompt. kind picks the handler, id identifies the thing.
function NPC.prompt(pos: Vector3, action: string, object: string, kind: string, id: string, hold: number?)
	local part, pp = Kit.prompt(interactions, pos, action, object, kind, id, hold)
	pp.Triggered:Connect(function(player)
		local fn = handlers[kind]
		if fn then
			local ok, err = pcall(fn, player, id, part)
			if not ok then warn("[NPC] prompt " .. kind .. " failed: " .. tostring(err)) end
		end
	end)
	return part, pp
end

-- Speech bubble for one player (the client draws it at the position).
function NPC.say(player: Player, pos: Vector3, name: string, text: string)
	Net.fire(player, "Dialogue", { pos = pos, name = name, text = text })
end

function NPC.line(key: string): string
	return Dialogue.line(key, rng)
end

-- A standing mesh person, when the models are loaded. Returns a handle shaped like a rig.
local function meshPerson(cf: CFrame, outfit: string?, name: string?, seed: number?)
	local n = seed or rng:NextInteger(1, 1000)
	local key = (outfit == "staff" or outfit == "nurse") and "npc_vendor" or (outfit == "student" and "npc_student" or (n % 2 == 0 and "npc_man" or "npc_vendor"))
	local t = Assets.template(key)
	if not t then return nil end
	local h = t:GetAttribute("Height") or 6
	local m = Assets.place(folder, key, cf, 6.1 / h * (0.95 + (n % 5) * 0.02))
	if not m then return nil end
	m.Name = name or "Person"
	m:AddTag("GoDashNPC")
	return { model = m, mesh = true, parts = {}, root = m:FindFirstChildWhichIsA("BasePart", true) }
end

function NPC.static(cf: CFrame, outfit: string?, name: string?, seed: number?)
	local person = meshPerson(cf, outfit, name, seed)
	if person then return person end
	local rig = Rig.build({ outfit = outfit, name = name or "Staff", seed = seed })
	Rig.place(rig, cf)
	rig.model:AddTag("GoDashNPC")
	pcall(Solid.body, rig.model, 0.5, 6.5) -- people on foot can't walk through staff
	rig.model.Parent = folder
	return rig
end

-- Job NPC (customer / passenger): reused from a pool.
-- standing = true: someone who only waits on the pavement (a customer) can be a mesh person.
function NPC.spawnTemp(cf: CFrame, outfit: string?, standing: boolean?)
	if standing then
		local person = meshPerson(cf, outfit, "Customer", nil)
		if person then return person end
	end
	local rig = table.remove(pool)
	if not rig then
		rig = Rig.build({ outfit = outfit, name = "Customer" })
		rig.model:AddTag("GoDashNPC")
	end
	for _, p in pairs(rig.parts) do
		p.Anchored = true
		for _, w in ipairs(p:GetChildren()) do
			if w:IsA("WeldConstraint") then w:Destroy() end
		end
	end
	rig.root.Anchored = true
	Rig.place(rig, cf)
	rig.model.Parent = folder
	return rig
end

function NPC.despawn(rig)
	if not rig then return end
	if rig.mesh then
		rig.model:Destroy()
		return
	end
	rig.model.Parent = nil
	for _, p in pairs(rig.parts) do
		for _, w in ipairs(p:GetChildren()) do
			if w:IsA("WeldConstraint") then w:Destroy() end
		end
	end
	if #pool < 12 then table.insert(pool, rig) else rig.model:Destroy() end
end

-- Seat a job NPC on a vehicle: pose it at the seat frame and weld every part to the chassis.
function NPC.board(rig, chassis: BasePart, seatCf: CFrame)
	Solid.unbody(rig.model)
	Rig.sit(rig, seatCf)
	for _, p in ipairs(rig.model:GetChildren()) do
		if p:IsA("BasePart") then
			local w = Instance.new("WeldConstraint")
			w.Part0 = chassis
			w.Part1 = p
			w.Parent = p
			p.Anchored = false
		end
	end
end

-- The avatar models (ReplicatedStorage.GoDashModels "Ped1"...) by name; empty in a place without them.
local peds: { string }? = nil
function NPC.pedNames(): { string }
	if not peds then
		peds = {}
		local store = ReplicatedStorage:FindFirstChild("GoDashModels")
		if store then
			for _, m in ipairs(store:GetChildren()) do
				if m:IsA("Model") and m.Name:sub(1, 3) == "Ped" then table.insert(peds :: { string }, m.Name) end
			end
			table.sort(peds :: { string })
		end
	end
	return peds :: { string }
end

-- A posed avatar figure (RiderPose): "stand", "hail", "pillion" or "sit". Anchored, in the NPC folder.
-- Returns a person record ({ model, mesh = true }, so NPC.despawn works) or nil.
function NPC.figure(cf: CFrame, pedName: string?, pose: string, helmet: Color3?)
	local store = ReplicatedStorage:FindFirstChild("GoDashModels")
	local t = store and pedName and store:FindFirstChild(pedName)
	if not t then return nil end
	local ok, m = pcall(RiderPose.build, t, cf, helmet, pose)
	if not ok or not m then return nil end
	m.Name = "Passenger"
	m:AddTag("GoDashNPC")
	if pose == "stand" or pose == "hail" then pcall(Solid.body, m, 0.45, 6.5) end -- solid while waiting (removed in weldTo)
	m.Parent = folder
	return { model = m, mesh = true, parts = {} }
end

-- Fix a posed figure onto a moving vehicle: weld every part to the chassis. The joints and the
-- Humanoid are removed first, so nothing in the figure pulls on the vehicle's physics.
function NPC.weldTo(person, chassis: BasePart)
	local m = person.model
	Solid.unbody(m)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Humanoid") or d:IsA("AnimationConstraint") or d:IsA("Motor6D") or d:IsA("Weld") then d:Destroy() end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = chassis
			w.Part1 = d
			w.Parent = d
			d.Anchored = false
		end
	end
end

function NPC.start(world)
	folder = Workspace:FindFirstChild("NPCs") or Kit.folder(Workspace, "NPCs")
	interactions = Workspace:FindFirstChild("Interactions") or Kit.folder(Workspace, "Interactions")
	local n = 0
	for _, shop in ipairs(world.shops) do
		n += 1
		if shop.npc then NPC.static(shop.npc, OUTFIT[shop.kind], shop.name, n) end
	end
	for id, poi in pairs(world.pois) do
		n += 1
		if poi.npc then NPC.static(poi.npc, OUTFIT[poi.kind], poi.name, n * 7) end
	end
	print(("[NPC] %d staff placed"):format(n))
end

return NPC
