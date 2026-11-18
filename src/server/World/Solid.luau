-- Nothing in the city is a ghost (owner, 2026-11-17: "ห้ามทะลุ มันจะได้สมจริง").
--
-- Most street dressing is drawn with Kit's `decor` flag (no collision, no queries) so it costs
-- nothing, and the mesh props are loaded without collision. That let people walk through posts,
-- stalls, chairs, parked bikes and other people. This pass gives what a person would bump into a
-- body again:
--   * decor parts standing in a walker's way (they start below knee height and reach above the
--     waist): CanCollide on. CanQuery stays off, so the camera and the wheel rays still ignore them.
--   * mesh props and posed people: one invisible box each (a mesh's collision can't be made a box
--     at run time, and a box is cheap and smooth to walk along)
-- Everything made solid here is in the collision group "Props", which blocks people on foot but not
-- vehicles: driving is unchanged, and riding into a chair still knocks it over (client/Crash).
-- Vehicles and the people riding them are in the group "Vehicles".
--
-- Solid.area(container) runs on every chunk the Streamer finishes and on the hand-built places.
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Solid = {}
Solid.PROPS = "Props"
Solid.VEHICLES = "Vehicles"

local LOW = 3.2 -- a part is in the way when it starts below this height ...
local HIGH = 1.6 -- ... and reaches above this one (the city's ground is at about 0.2 - 0.6)
local BODY_NAME = "GoDashBody"

local R15 = {
	Head = true, UpperTorso = true, LowerTorso = true, Torso = true, HumanoidRootPart = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
	["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
}

local registered = false
function Solid.init()
	if registered then return end
	registered = true
	for _, g in ipairs({ Solid.PROPS, Solid.VEHICLES }) do
		if not PhysicsService:IsCollisionGroupRegistered(g) then PhysicsService:RegisterCollisionGroup(g) end
	end
	PhysicsService:CollisionGroupSetCollidable(Solid.PROPS, Solid.VEHICLES, false)
end

-- An invisible box in the Props group. cf = its centre.
function Solid.box(parent: Instance, cf: CFrame, size: Vector3): Part
	local b = Instance.new("Part")
	b.Name = BODY_NAME
	b.Anchored = true
	b.Transparency = 1
	b.CanCollide = true
	b.CanQuery = false
	b.CanTouch = false
	b.CastShadow = false
	b.Massless = true
	b.Size = size
	b.CFrame = cf
	b.CollisionGroup = Solid.PROPS
	b.Parent = parent
	return b
end

-- A body for a placed model (a mesh prop or person). k shrinks the footprint (a chair's legs splay
-- wider than its seat), maxH caps the height. Nothing for models already solid or up off the ground.
function Solid.body(m: Model, k: number, maxH: number?)
	if m:FindFirstChild(BODY_NAME) then return end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then return end
	end
	local cf, size = m:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	if bottom > LOW then return end
	local h = math.min(size.Y, maxH or 6.5)
	local s = Vector3.new(math.max(size.X * k, 0.6), h, math.max(size.Z * k, 0.6))
	Solid.box(m, cf * CFrame.new(0, (h - size.Y) / 2, 0), s)
end

-- Take the body away again (a waiting customer who gets on a vehicle).
function Solid.unbody(m: Instance)
	for _, d in ipairs(m:GetDescendants()) do
		if d.Name == BODY_NAME and d:IsA("BasePart") then d:Destroy() end
	end
end

local function inTheWay(p: BasePart): boolean
	if p.CanCollide or not p.Anchored or p.Transparency >= 0.5 then return false end
	if p:IsA("MeshPart") or p:IsA("Seat") or p:IsA("VehicleSeat") or R15[p.Name] then return false end
	if p.Name:sub(1, 9) == "Interact_" then return false end
	local cf, s = p.CFrame, p.Size
	local ext = (cf.RightVector * s.X):Abs() + (cf.UpVector * s.Y):Abs() + (cf.LookVector * s.Z):Abs()
	local y = cf.Position.Y
	if y - ext.Y / 2 > LOW or y + ext.Y / 2 < HIGH then return false end
	local wide = math.max(ext.X, ext.Z)
	return wide >= 0.2 and wide <= 80
end

-- Posed people (avatar figures, part-built rigs): one box per person, around the parts near each torso.
local function people(torsos: { BasePart })
	for _, torso in ipairs(torsos) do
		local parent = torso.Parent
		if parent and not parent:FindFirstChild(BODY_NAME) then
			local c = torso.Position
			local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
			for _, p in ipairs(parent:GetChildren()) do
				if p:IsA("BasePart") and R15[p.Name] then
					local q = p.Position
					if Vector3.new(q.X - c.X, 0, q.Z - c.Z).Magnitude < 3.5 then
						local e = p.Size / 2
						lo = lo:Min(q - e)
						hi = hi:Max(q + e)
					end
				end
			end
			if lo.Y < LOW and hi.Y > lo.Y then
				local mid = (lo + hi) / 2
				local size = hi - lo
				local w = math.clamp(math.max(size.X, size.Z) * 0.6, 1.2, 2.4)
				Solid.box(parent, CFrame.new(mid), Vector3.new(w, math.min(size.Y, 6.5), w))
			end
		end
	end
end

-- Make everything a person would bump into in this container solid for people on foot.
-- soft = true: spread the work over frames (about 1.5 ms per frame), for chunks built while playing.
-- (Mesh props, people's limbs and anything already solid are left out by inTheWay, so the tagged
-- models inside - knockable chairs, posed figures - need no special case.)
function Solid.area(container: Instance, soft: boolean?): number
	Solid.init()
	local list = container:GetDescendants()
	local torsos = {}
	local n = 0
	local t0 = os.clock()
	for i, d in ipairs(list) do
		if soft and i % 150 == 0 and os.clock() - t0 > 0.0015 then
			task.wait()
			if not container.Parent then return n end
			t0 = os.clock()
		end
		if d:IsA("BasePart") then
			local name = d.Name
			if name == "LowerTorso" or name == "Torso" then
				table.insert(torsos, d)
			elseif inTheWay(d) then
				d.CanCollide = true
				d.CollisionGroup = Solid.PROPS
				n += 1
			end
		end
	end
	people(torsos)
	return n
end

-- Vehicles (and their riders) go in the Vehicles group, so Props never stop them.
local function setGroup(model: Instance, g: string)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= BODY_NAME then d.CollisionGroup = g end
	end
end

local function vehicleModel(m: Instance)
	setGroup(m, Solid.VEHICLES)
	m.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and d.Name ~= BODY_NAME then d.CollisionGroup = Solid.VEHICLES end
	end)
end

local function inVehicle(seat: Instance?): boolean
	if not seat then return false end
	if seat:IsA("VehicleSeat") then return true end
	local m = seat:FindFirstAncestorWhichIsA("Model")
	while m do
		if m:HasTag("GoDashVehicle") then return true end
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return false
end

local function character(char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then return end
	hum.Seated:Connect(function(active, seat)
		setGroup(char, (active and inVehicle(seat)) and Solid.VEHICLES or "Default")
	end)
end

function Solid.start()
	Solid.init()
	for _, tag in ipairs({ "GoDashVehicle", "TrafficCar" }) do
		for _, m in ipairs(CollectionService:GetTagged(tag)) do vehicleModel(m) end
		CollectionService:GetInstanceAddedSignal(tag):Connect(vehicleModel)
	end
	local function player(p: Player)
		if p.Character then task.spawn(character, p.Character) end
		p.CharacterAdded:Connect(character)
	end
	for _, p in ipairs(Players:GetPlayers()) do player(p) end
	Players.PlayerAdded:Connect(player)
end

return Solid
