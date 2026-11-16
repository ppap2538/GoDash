-- Pedestrians: a small pool of jointed NPCs that walk the sidewalks around the player, stop for
-- a rest, pick a new street at corners and chat when spoken to. They live on the client only,
-- so the count is capped per device and they cost the server nothing.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rig = require(Shared.Rig)
local Dialogue = require(Shared.Config.Dialogue)
local GPS = require(script.Parent.GPS)
local RoadGraphProject = require(Shared.RoadGraph).project
local Feedback = require(script.Parent.Feedback)

local Peds = {}
local player = Players.LocalPlayer
local MAX = 14
local SPAWN_RADIUS, DESPAWN = 520, 760
local peds = {}
local folder
local rng = Random.new()

local function rootPos(): Vector3?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return r and r.Position or nil
end

local function walkable(e): boolean
	return e.def.walk > 0 and e.len > 50
end

local function place(p)
	local e = p.edge
	local nx, nz = -e.dz * p.side, e.dx * p.side
	local off = e.def.width / 2 + e.def.walk * 0.5
	local x = e.a.x + e.dx * p.s + nx * off
	local z = e.a.z + e.dz * p.s + nz * off
	local pos = Vector3.new(x, 0.5 + Rig.FEET, z)
	local dir = Vector3.new(e.dx, 0, e.dz) * p.dir
	if p.face then dir = p.face end
	p.pos = pos
	p.rig.root.CFrame = CFrame.lookAt(pos, pos + dir)
end

local function respawn(p, around: Vector3)
	local graph = GPS.graph()
	local list = {}
	for _, e in ipairs(graph:edgesNear(around, SPAWN_RADIUS)) do
		if walkable(e) then table.insert(list, e) end
	end
	if #list == 0 then
		p.rig.model.Parent = nil
		p.active = false
		return
	end
	p.edge = list[rng:NextInteger(1, #list)]
	p.s = rng:NextNumber(4, p.edge.len - 4)
	p.dir = rng:NextNumber() < 0.5 and 1 or -1
	p.side = rng:NextNumber() < 0.5 and 1 or -1
	p.speed = rng:NextNumber(5.5, 8.5)
	p.idleUntil = 0
	p.face = nil
	p.active = true
	p.rig.model.Parent = folder
	place(p)
end

local function turn(p)
	-- reached a corner: carry on along another street that has a sidewalk
	local e = p.edge
	local node = p.dir > 0 and e.b or e.a
	local options = {}
	for _, l in ipairs(node.links) do
		if l.edge ~= e and walkable(l.edge) then table.insert(options, l.edge) end
	end
	if #options == 0 then
		p.dir = -p.dir
		p.s = math.clamp(p.s, 1, e.len - 1)
		return
	end
	local nextEdge = options[rng:NextInteger(1, #options)]
	p.edge = nextEdge
	if nextEdge.a == node then p.dir = 1; p.s = math.min(node.r + 8, nextEdge.len - 1) else p.dir = -1; p.s = math.max(nextEdge.len - node.r - 8, 1) end
end

---------------------------------------------------------------------------------------------------
-- Avatar pedestrians: generated R15 characters stored in ReplicatedStorage.GoDashModels ("Ped1"...).
-- Each one is a local Humanoid that really walks (MoveTo) with a walk animation.
---------------------------------------------------------------------------------------------------
local WALK_ANIM = "rbxassetid://507777826" -- Roblox's own R15 walk
local AVATARS = 12

local function sidewalkPoint(e, s: number, side: number): Vector3
	local nx, nz = -e.dz * side, e.dx * side
	local off = e.def.width / 2 + e.def.walk * 0.5
	return Vector3.new(e.a.x + e.dx * s + nx * off, 0.6, e.a.z + e.dz * s + nz * off)
end

local function startAvatars(templates: { Model })
	folder = Instance.new("Folder")
	folder.Name = "GoDashPedestrians"
	folder.Parent = Workspace
	local list = {}
	local anim = Instance.new("Animation")
	anim.AnimationId = WALK_ANIM
	for i = 1, AVATARS do
		local model = templates[(i - 1) % #templates + 1]:Clone()
		model.Name = "Pedestrian"
		local hum = model:FindFirstChildOfClass("Humanoid")
		local rootPart = model:FindFirstChild("HumanoidRootPart")
		if hum and rootPart then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			hum.BreakJointsOnDeath = false
			hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
			-- a little variety from two or three templates
			pcall(function() model:ScaleTo(0.94 + (i % 5) * 0.03) end)
			local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
			animator.Parent = hum
			-- the walk track can only be loaded once the model is in the world, so it is loaded on first use
			local p = { model = model, hum = hum, root = rootPart, animator = animator, track = nil, active = false, idleUntil = 0, nextMove = 0 }
			local pp = Instance.new("ProximityPrompt")
			pp.ActionText = "Talk"
			pp.ObjectText = "Local"
			pp.MaxActivationDistance = 9
			pp.RequiresLineOfSight = false
			pp.KeyboardKeyCode = Enum.KeyCode.T
			pp.Parent = rootPart
			pp.Triggered:Connect(function()
				local raining = (Workspace:GetAttribute("Rain") or 0) > 0
				Feedback.bubble(rootPart.Position + Vector3.new(0, 3, 0), "Local", Dialogue.line(raining and rng:NextNumber() < 0.6 and "pedestrian_rain" or "pedestrian", rng))
				p.idleUntil = os.clock() + 4
				hum:MoveTo(rootPart.Position)
			end)
			table.insert(list, p)
		end
	end

	local function respawn(p, around: Vector3)
		local graph = GPS.graph()
		local options = {}
		for _, e in ipairs(graph:edgesNear(around, SPAWN_RADIUS)) do
			if walkable(e) then table.insert(options, e) end
		end
		if #options == 0 then
			p.model.Parent = nil
			p.active = false
			return
		end
		p.edge = options[rng:NextInteger(1, #options)]
		p.s = rng:NextNumber(6, p.edge.len - 6)
		p.dir = rng:NextNumber() < 0.5 and 1 or -1
		p.side = rng:NextNumber() < 0.5 and 1 or -1
		p.speed = rng:NextNumber(6, 8.5)
		p.idleUntil = 0
		p.nextMove = 0
		p.active = true
		local at = sidewalkPoint(p.edge, p.s, p.side)
		p.model:PivotTo(CFrame.new(at + Vector3.new(0, p.hum.HipHeight + 1.2, 0)))
		p.root.AssemblyLinearVelocity = Vector3.zero
		p.model.Parent = folder
	end

	task.spawn(function()
		while true do
			task.wait(0.5)
			local me = rootPos()
			if me then
				local now = os.clock()
				local raining = (Workspace:GetAttribute("Rain") or 0) > 0
				local night = Workspace:GetAttribute("IsNight") == true
				local want = night and math.floor(#list * 0.5) or #list
				for i, p in ipairs(list) do
					if i > want then
						if p.active then p.active = false; p.model.Parent = nil end
					elseif not p.active or (p.root.Position - me).Magnitude > DESPAWN or p.root.Position.Y < -20 then
						respawn(p, me)
					elseif now < p.idleUntil then
						if p.track and p.track.IsPlaying then p.track:Stop(0.3) end
					else
						-- how far along the pavement are we? walk on, and pick a new street at the corner
						local _, _, t = RoadGraphProject(p.edge, p.root.Position.X, p.root.Position.Z)
						p.s = t * p.edge.len
						if (p.dir > 0 and p.s > p.edge.len - 8) or (p.dir < 0 and p.s < 8) then
							local node = p.dir > 0 and p.edge.b or p.edge.a
							local nexts = {}
							for _, l in ipairs(node.links) do
								if l.edge ~= p.edge and walkable(l.edge) then table.insert(nexts, l.edge) end
							end
							if #nexts > 0 then
								local ne = nexts[rng:NextInteger(1, #nexts)]
								p.edge = ne
								if ne.a == node then p.dir = 1; p.s = math.min(node.r + 10, ne.len - 2) else p.dir = -1; p.s = math.max(ne.len - node.r - 10, 2) end
							else
								p.dir = -p.dir
							end
							p.nextMove = 0
						end
						if now >= p.nextMove then
							p.nextMove = now + 2.5
							p.hum.WalkSpeed = p.speed * (raining and 1.6 or 1)
							local ahead = math.clamp(p.s + p.dir * 36, 2, p.edge.len - 2)
							p.hum:MoveTo(sidewalkPoint(p.edge, ahead, p.side))
							if not p.track and p.model.Parent then
								local ok, track = pcall(function() return p.animator:LoadAnimation(anim) end)
								if ok and track then
									track.Looped = true
									p.track = track
								end
							end
							if p.track then
								if not p.track.IsPlaying then p.track:Play(0.3) end
								p.track:AdjustSpeed(p.hum.WalkSpeed / 8)
							end
						end
						if rng:NextNumber() < 0.012 then
							p.idleUntil = now + rng:NextNumber(3, 7)
							p.hum:MoveTo(p.root.Position)
						end
					end
				end
			end
		end
	end)
end

local function startRigs()
	folder = Instance.new("Folder")
	folder.Name = "GoDashPedestrians"
	folder.Parent = Workspace
	for i = 1, MAX do
		local rig = Rig.build({ jointed = true, seed = i * 131, name = "Pedestrian", outfit = (i % 5 == 0) and "student" or nil })
		local p = { rig = rig, active = false, phase = rng:NextNumber(0, 6) }
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = "Talk"
		pp.ObjectText = "Local"
		pp.MaxActivationDistance = 9
		pp.RequiresLineOfSight = false
		pp.KeyboardKeyCode = Enum.KeyCode.T
		pp.Parent = rig.root
		pp.Triggered:Connect(function()
			local raining = (Workspace:GetAttribute("Rain") or 0) > 0
			Feedback.bubble(rig.root.Position + Vector3.new(0, 2, 0), "Local", Dialogue.line(raining and rng:NextNumber() < 0.6 and "pedestrian_rain" or "pedestrian", rng))
			p.idleUntil = os.clock() + 4
			local me = rootPos()
			if me then
				local d = Vector3.new(me.X - rig.root.Position.X, 0, me.Z - rig.root.Position.Z)
				if d.Magnitude > 0.5 then p.face = d.Unit; place(p) end
			end
		end)
		peds[i] = p
	end

	RunService.Heartbeat:Connect(function(dt)
		local me = rootPos()
		if not me then return end
		local now = os.clock()
		local raining = (Workspace:GetAttribute("Rain") or 0) > 0
		local night = Workspace:GetAttribute("IsNight") == true
		local want = night and math.floor(MAX * 0.5) or MAX
		for i, p in ipairs(peds) do
			if i > want then
				if p.active then p.active = false; p.rig.model.Parent = nil end
			elseif not p.active or not p.pos or (p.pos - me).Magnitude > DESPAWN then
				respawn(p, me)
			elseif now >= p.idleUntil then
				if p.face then p.face = nil end
				p.s += p.dir * p.speed * (raining and 1.5 or 1) * dt
				if p.s <= 0 or p.s >= p.edge.len then turn(p) end
				place(p)
				local dist = (p.pos - me).Magnitude
				if dist < 280 then
					p.phase += dt * p.speed * 1.25
					Rig.walkPose(p.rig, p.phase, 1)
				end
				-- now and then stop for a rest
				if rng:NextNumber() < dt * 0.03 then
					p.idleUntil = now + rng:NextNumber(2.5, 6)
					Rig.walkPose(p.rig, 0, 0)
				end
			end
		end
	end)
end

function Peds.start()
	local store = ReplicatedStorage:WaitForChild("GoDashModels", 6)
	local templates = {}
	if store then
		for _, m in ipairs(store:GetChildren()) do
			if m:IsA("Model") and m.Name:sub(1, 3) == "Ped" and m:FindFirstChildOfClass("Humanoid") then table.insert(templates, m) end
		end
	end
	if #templates > 0 then startAvatars(templates) else startRigs() end
end

return Peds
