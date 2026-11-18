-- What a crash looks and sounds like, on the client:
--   * Crash.effect(pos, intensity, opts): sparks, a dust puff, flying shards of plastic and glass,
--     a metal / glass / bump sound at the spot, and a camera shake when it is your own crash
--   * smoke from any vehicle whose Condition attribute is low (grey, then black)
--   * street props tagged "Knockable" (plastic chairs, pot plants, bins) get knocked over when a
--     vehicle drives into them, then quietly put back after a while
-- Everything here is local and temporary; nothing is sent to the server.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Feedback = require(script.Parent.Feedback)

local Crash = {}
local player = Players.LocalPlayer
local rng = Random.new()

local MAX_SHARDS = 48
local shards = 0

---------------------------------------------------------------------------------------------------
-- one-shot effect
---------------------------------------------------------------------------------------------------
local function sound(at: BasePart, id: string?, volume: number, speed: number?)
	if not id or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.RollOffMinDistance = 12
	s.RollOffMaxDistance = 260
	s.SoundGroup = Feedback.sfxGroup
	s.Parent = at
	s:Play()
end

local shake = { t = 0, amp = 0 }
RunService:BindToRenderStep("GoDashCrashShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shake.t <= 0 then return end
	shake.t -= dt
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local a = shake.amp * math.max(0, shake.t) / 0.45
	cam.CFrame *= CFrame.Angles(rng:NextNumber(-a, a) * 0.02, rng:NextNumber(-a, a) * 0.02, rng:NextNumber(-a, a) * 0.015)
		+ Vector3.new(rng:NextNumber(-a, a), rng:NextNumber(-a, a), 0) * 0.08
end)

-- pos: where it happened. intensity: 0 (tap) .. 1 (head-on at speed).
-- opts: { normal = Vector3 (away from the surface hit), color = Color3 (paint for the shards),
--         mine = boolean (shake my camera), glass = boolean?, quiet = boolean? (props) }
function Crash.effect(pos: Vector3, intensity: number, opts: any?)
	local o = opts or {}
	local k = math.clamp(intensity, 0, 1)
	local normal = (o.normal and o.normal.Magnitude > 0.01) and o.normal.Unit or Vector3.yAxis
	local holder = Instance.new("Part")
	holder.Name = "CrashFx"
	holder.Anchored = true; holder.CanCollide = false; holder.CanQuery = false; holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.lookAt(pos, pos + normal)
	holder.Parent = Workspace
	Debris:AddItem(holder, 5)
	local att = Instance.new("Attachment")
	att.Parent = holder

	if not o.quiet then
		-- sparks: metal on metal
		local sp = Instance.new("ParticleEmitter")
		sp.Color = ColorSequence.new(Color3.fromRGB(255, 236, 170), Color3.fromRGB(255, 140, 40))
		sp.LightEmission = 1
		sp.LightInfluence = 0
		sp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.24), NumberSequenceKeypoint.new(1, 0) })
		sp.Squash = NumberSequence.new(2.2)
		sp.Lifetime = NumberRange.new(0.3, 0.85)
		sp.Speed = NumberRange.new(16, 28 + 30 * k)
		sp.SpreadAngle = Vector2.new(70, 70)
		sp.Acceleration = Vector3.new(0, -70, 0)
		sp.Drag = 2
		sp.EmissionDirection = Enum.NormalId.Front
		sp.Rate = 0
		sp.Parent = att
		sp:Emit(math.floor(20 + 70 * k))
	end
	-- dust / smoke puff, lingering a moment after a real smash
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(Color3.fromRGB(150, 144, 136), Color3.fromRGB(120, 116, 112))
	dust.LightInfluence = 1
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 4.5 + 4 * k) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.6, 0.6), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(1.2, 2.4)
	dust.Speed = NumberRange.new(2, 7)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Acceleration = Vector3.new(0, 1.5, 0)
	dust.RotSpeed = NumberRange.new(-40, 40)
	dust.Rate = 0
	dust.Parent = att
	dust:Emit(math.floor(5 + 14 * k))

	-- shards: bits of trim, lamp lens and glass
	local n = math.floor((o.quiet and 0 or 3) + 12 * k)
	for _ = 1, n do
		if shards >= MAX_SHARDS then break end
		shards += 1
		local glassy = rng:NextNumber() < 0.4
		local p = Instance.new("Part")
		p.Name = "Shard"
		p.Size = Vector3.new(rng:NextNumber(0.18, 0.7), rng:NextNumber(0.06, 0.16), rng:NextNumber(0.18, 0.75))
		p.Material = glassy and Enum.Material.Glass or Enum.Material.SmoothPlastic
		p.Color = glassy and Color3.fromRGB(196, 210, 214) or (rng:NextNumber() < 0.5 and (o.color or Color3.fromRGB(60, 62, 66)) or Color3.fromRGB(34, 34, 36))
		p.Transparency = glassy and 0.35 or 0
		p.CanQuery = false; p.CanTouch = false
		p.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.5, 0.2)
		p.CFrame = CFrame.new(pos + normal * 0.4) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0)
		p.Parent = Workspace
		local dir = (normal + Vector3.new(rng:NextNumber(-0.9, 0.9), rng:NextNumber(0.2, 1.1), rng:NextNumber(-0.9, 0.9))).Unit
		p.AssemblyLinearVelocity = dir * rng:NextNumber(10, 18 + 26 * k)
		p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-20, 20), rng:NextNumber(-20, 20), rng:NextNumber(-20, 20))
		task.delay(7, function() shards -= 1 end)
		Debris:AddItem(p, 7)
	end

	-- sound
	if o.quiet then
		sound(holder, Sounds.bump, 0.35, rng:NextNumber(1.3, 1.6))
	elseif k > 0.45 then
		sound(holder, rng:NextNumber() < 0.5 and Sounds.crashMetal or Sounds.crashMetal2, 0.35 + 0.45 * k, rng:NextNumber(0.92, 1.08))
	else
		sound(holder, Sounds.bump, 0.4 + 0.5 * k, rng:NextNumber(0.85, 1.05))
	end
	if (o.glass or k > 0.5) and rng:NextNumber() < 0.7 then sound(holder, Sounds.glass, 0.25 + 0.3 * k) end

	if o.mine then
		shake.amp = math.max(shake.t > 0 and shake.amp or 0, 0.6 + 2.4 * k)
		shake.t = 0.45
		Feedback.fovKick(4 + 8 * k, 0.4)
	end
end

---------------------------------------------------------------------------------------------------
-- smoke from damaged vehicles
---------------------------------------------------------------------------------------------------
local function smokeFor(model: Instance)
	if not model:IsA("Model") then return end
	local function apply()
		local cond = model:GetAttribute("Condition")
		local chassis = model.PrimaryPart
		if type(cond) ~= "number" or not chassis then return end
		local att = chassis:FindFirstChild("DamageSmoke")
		if cond >= 45 then
			if att then att:Destroy() end
			return
		end
		if not att then
			att = Instance.new("Attachment")
			att.Name = "DamageSmoke"
			local len = chassis.Size.Z
			att.Position = Vector3.new(0, chassis.Size.Y * 0.5 + 0.4, -len * 0.3)
			local e = Instance.new("ParticleEmitter")
			e.Name = "Smoke"
			e.LightInfluence = 1
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 4) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(1.4, 2.6)
			e.Speed = NumberRange.new(1.5, 3.5)
			e.SpreadAngle = Vector2.new(18, 18)
			e.Acceleration = Vector3.new(0, 3, 0)
			e.RotSpeed = NumberRange.new(-30, 30)
			e.EmissionDirection = Enum.NormalId.Top
			e.Parent = att
			att.Parent = chassis
		end
		local e = att:FindFirstChild("Smoke") :: ParticleEmitter
		local k = math.clamp((45 - cond) / 40, 0, 1)
		e.Rate = 3 + 14 * k
		local shade = math.floor(150 - 120 * k)
		e.Color = ColorSequence.new(Color3.fromRGB(shade, shade, shade))
	end
	apply()
	model:GetAttributeChangedSignal("Condition"):Connect(apply)
end

---------------------------------------------------------------------------------------------------
-- knockable street props
---------------------------------------------------------------------------------------------------
local CELL = 24
local grid = {} :: { [number]: { Model } }
local knocked = {} :: { [Model]: boolean }

local function key(x: number, z: number): number
	return math.floor(x / CELL) * 65536 + math.floor(z / CELL)
end

local function addProp(m: Instance)
	if not m:IsA("Model") then return end
	local p = m:GetPivot().Position
	local k = key(p.X, p.Z)
	local list = grid[k]
	if not list then list = {}; grid[k] = list end
	table.insert(list, m)
end

local function knock(m: Model, vel: Vector3)
	knocked[m] = true
	local parts, orig = {}, {}
	local root, best = nil, -1
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			orig[d] = { cf = d.CFrame, collide = d.CanCollide }
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > best then root, best = d, v end
		end
	end
	if not root then knocked[m] = nil; return end
	local welds = {}
	for _, p in ipairs(parts) do
		if p ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root; w.Part1 = p; w.Parent = root
			table.insert(welds, w)
		end
		p.CanCollide = true
		p.CustomPhysicalProperties = PhysicalProperties.new(0.35, 0.5, 0.25)
		p.Anchored = false
	end
	local speed = vel.Magnitude
	root.AssemblyLinearVelocity = vel * rng:NextNumber(0.7, 1.0) + Vector3.new(rng:NextNumber(-6, 6), 8 + speed * 0.18, rng:NextNumber(-6, 6))
	root.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
	Crash.effect(root.Position, 0.2, { quiet = true, normal = vel.Magnitude > 0.1 and vel.Unit or Vector3.yAxis })
	-- put it back once nobody is looking at the mess any more
	task.delay(22, function()
		for _ = 1, 30 do
			local char = player.Character
			local r = char and char:FindFirstChild("HumanoidRootPart")
			if not r or (r.Position - root.Position).Magnitude > 60 then break end
			task.wait(2)
		end
		for _, w in ipairs(welds) do w:Destroy() end
		for _, p in ipairs(parts) do
			if p.Parent then
				p.Anchored = true
				p.AssemblyLinearVelocity = Vector3.zero
				p.AssemblyAngularVelocity = Vector3.zero
				p.CFrame = orig[p].cf
				p.CanCollide = orig[p].collide
				p.CustomPhysicalProperties = nil
			end
		end
		knocked[m] = nil
	end)
end

-- Called by Drive every physics step with the vehicle's chassis.
function Crash.sweep(chassis: BasePart, halfLen: number)
	local vel = chassis.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	if speed < 5 then return end
	local pos = chassis.Position
	local reach = halfLen + 1.6
	local cx, cz = math.floor(pos.X / CELL), math.floor(pos.Z / CELL)
	for dx = -1, 1 do
		for dz = -1, 1 do
			local list = grid[(cx + dx) * 65536 + cz + dz]
			if list then
				for i = #list, 1, -1 do
					local m = list[i]
					if not m.Parent then
						table.remove(list, i)
					elseif not knocked[m] then
						local p = m:GetPivot().Position
						local rel = Vector3.new(p.X - pos.X, 0, p.Z - pos.Z)
						-- inside the vehicle's footprint (a capsule along its heading)
						local fwd = chassis.CFrame.LookVector
						local along = rel:Dot(fwd)
						local side = math.abs(rel:Dot(chassis.CFrame.RightVector))
						if math.abs(along) < reach and side < 1.9 and math.abs(p.Y - pos.Y) < 8 then knock(m, vel) end
					end
				end
			end
		end
	end
end

function Crash.start()
	for _, m in ipairs(CollectionService:GetTagged("GoDashVehicle")) do smokeFor(m) end
	CollectionService:GetInstanceAddedSignal("GoDashVehicle"):Connect(smokeFor)
	for _, m in ipairs(CollectionService:GetTagged("Knockable")) do addProp(m) end
	CollectionService:GetInstanceAddedSignal("Knockable"):Connect(addProp)
end

return Crash
