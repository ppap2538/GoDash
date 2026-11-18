-- Swan pedal boats you can ride (2026-11-19, owner list: "ปั่นเรือเป็ดในบึงได้จริง"). Free, for everyone.
-- Two swans wait at each lakeside pier (World/Lakeside: the pier's first two slots; the other two stay tied
-- up as scenery). Hold E on one ("Pedal a swan boat") and you sit in it; W/S or the thumbstick pedals, A/D
-- steers, jump to get off. The boat is a physics assembly owned by its rider: client/Boats drives it with a
-- LinearVelocity (speed, and holding it at the water surface Game.WATER_Y) and an AlignOrientation (heading).
-- The stone rim and the pier stop it. Left empty for IDLE seconds it goes back to its slot.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local World = script.Parent.Parent.World
local Kit = require(World.Kit)

local Service = {}
local V3, CF = Vector3.new, CFrame.new
local rad = math.rad
local M = Kit.M
local IDLE = 90

local folder: Folder? = nil
local boats = {} :: { any }

local function build(slot: CFrame, n: number)
	local m = Instance.new("Model")
	m.Name = "SwanBoat" .. n
	local white = Color3.fromRGB(246, 246, 242)
	-- the hull that floats and collides; everything else rides on it
	local hull = Instance.new("Part")
	hull.Name = "Hull"
	hull.Size = V3(4.4, 1.2, 7.6)
	hull.CFrame = slot * CF(0, 0.4, 0)
	hull.Transparency = 1
	hull.CanCollide = true
	hull.CanTouch = false
	hull.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.3, 0.1)
	hull.Parent = m
	m.PrimaryPart = hull
	local parts = {}
	local function add(p: BasePart)
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.Massless = true
		table.insert(parts, p)
	end
	add(Kit.part(m, V3(8, 4.6, 4.6), slot * CF(0, 0.3, 0) * CFrame.Angles(rad(90), 0, 0) * CFrame.Angles(0, 0, rad(90)), white, M.SmoothPlastic,
		{ shape = Enum.PartType.Cylinder, name = "Tube" }))
	add(Kit.wedge(m, V3(4.4, 2.6, 2.6), slot * CF(0, 2.6, 3.4) * CFrame.Angles(0, rad(180), 0), white, M.SmoothPlastic))
	add(Kit.part(m, V3(5, 0.9, 0.9), slot * CF(0, 3, -3.4) * CFrame.Angles(rad(-18), 0, 0) * CFrame.Angles(0, 0, rad(90)), white, M.SmoothPlastic,
		{ shape = Enum.PartType.Cylinder }))
	add(Kit.ball(m, 1.8, slot * CF(0, 5.4, -4.4), white, M.SmoothPlastic))
	add(Kit.part(m, V3(0.5, 0.5, 1.2), slot * CF(0, 5.3, -5.6), Color3.fromRGB(240, 150, 40), M.SmoothPlastic))
	-- the red seat is the VehicleSeat: its Throttle / Steer come from the rider's keys or thumbstick
	local seat = Instance.new("VehicleSeat")
	seat.Name = "SwanSeat"
	seat.Size = V3(3.8, 1.4, 3.4)
	seat.CFrame = slot * CF(0, 2.6, 0.6)
	seat.Color = Color3.fromRGB(220, 80, 70)
	seat.Material = M.SmoothPlastic
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.Parent = m
	add(seat)
	seat.CanCollide = true -- sat on, not walked through
	for _, p in ipairs(parts) do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = hull, p
		w.Parent = p
	end
	-- the drive: speed + height (LinearVelocity) and heading (AlignOrientation), set by the rider's client
	local att = Instance.new("Attachment")
	att.Name = "Drive"
	att.Parent = hull
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 60000
	lv.VectorVelocity = Vector3.zero
	lv.Parent = hull
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 400000
	ao.Responsiveness = 12
	ao.CFrame = CFrame.fromMatrix(Vector3.zero, slot.RightVector, Vector3.yAxis)
	ao.Parent = hull
	-- the prompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Pedal a swan boat"
	pp.ObjectText = "Swan boat"
	pp.HoldDuration = 0.3
	pp.MaxActivationDistance = 14
	pp.RequiresLineOfSight = false
	pp.Parent = seat
	m:SetAttribute("WaterY", GameConfig.WATER_Y)
	m:AddTag("SwanBoat")
	hull.Anchored = true
	m.Parent = folder
	local b = { model = m, hull = hull, seat = seat, slot = slot, prompt = pp, idleSince = os.clock() }
	pp.Triggered:Connect(function(player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.SeatPart or seat.Occupant then return end
		seat:Sit(hum)
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = seat.Occupant
		local player = hum and Players:GetPlayerFromCharacter(hum.Parent)
		if player then
			pp.Enabled = false
			hull.Anchored = false
			pcall(function() hull:SetNetworkOwner(player) end)
		else
			pp.Enabled = true
			b.idleSince = os.clock()
			lv.VectorVelocity = Vector3.zero
			task.delay(0.6, function()
				if not seat.Occupant and m.Parent then
					pcall(function() hull:SetNetworkOwner(nil) end)
					hull.Anchored = true
				end
			end)
		end
	end)
	table.insert(boats, b)
end

function Service.start(world)
	local f = Instance.new("Folder")
	f.Name = "SwanBoats"
	f.Parent = Workspace
	folder = f
	local n = 0
	for _, lake in ipairs(world.lakes or {}) do
		local pier = lake.pier
		if pier then
			local shore = V3(pier.x, 0, pier.z)
			local out = V3(pier.ox or 0, 0, pier.oz or 1)
			out = out.Magnitude > 0.1 and out.Unit or V3(0, 0, 1)
			local cf = CFrame.lookAt(shore, shore - out) -- -Z out over the water (as World/Lakeside.drawPier)
			-- beside the deck (7 wide, 34 long), halfway out: clear of the stone rim at the shore, which jammed
			-- the first test boat (it was moored 8 studs out and spawned overlapping the rim and the pier)
			for b = 0, 1 do
				local side = b % 2 == 0 and -1 or 1
				n += 1
				build(cf * CF(side * 9.5, 0.6, -21), n)
			end
		end
	end
	-- an empty boat drifts home to its slot after a while
	task.spawn(function()
		while true do
			task.wait(5)
			for _, b in ipairs(boats) do
				if not b.seat.Occupant and os.clock() - b.idleSince > IDLE and (b.hull.Position - (b.slot * CF(0, 0.4, 0)).Position).Magnitude > 3 then
					b.hull.Anchored = true
					b.model:PivotTo(b.slot * CF(0, 0.4, 0))
					b.idleSince = os.clock()
				end
			end
		end
	end)
	print(("[Boats] %d swan boats at the piers"):format(n))
end

return Service
