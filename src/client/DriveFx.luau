-- What driving looks like up close (2026-11-18 realism pass). Called by Drive every physics step
-- (Drive.fx) for the vehicle this client drives:
--   * skid marks: dark strips laid where a tyre slides or locks under hard braking; they fade after
--     half a minute (a ring of at most MARKS pieces)
--   * tyre smoke while sliding on a dry road, a spray of water on a wet one
--   * exhaust: a thin haze at idle, puffs when the throttle opens, darker from old engines
--   * speed streaks flying past the camera near top speed
--   * headlight beams you can see in the air at night and in the rain
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Drive = require(script.Parent.Drive)
local Perf = require(script.Parent.Perf)

local DriveFx = {}
local MARKS = 220
local MARK_LIFE = 30

local folder: Folder
local marks = {} :: { { part: BasePart, born: number } }
local markI = 0
local lastMark = {} :: { [number]: Vector3 }
local rig: any = nil -- emitters for the vehicle being driven
local streakPart: BasePart? = nil
local streak: ParticleEmitter? = nil

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

local function seq(a: number, b: number) return NumberSequence.new(a, b) end

local function markAt(i: number, pos: Vector3, normal: Vector3, width: number, strength: number)
	local last = lastMark[i]
	lastMark[i] = pos
	if not last then return end
	local d = pos - last
	local len = d.Magnitude
	if len < 0.45 or len > 6 then return end
	markI = markI % MARKS + 1
	local slot = marks[markI]
	local p = slot and slot.part
	if not p then
		p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = Color3.fromRGB(18, 18, 20)
		p.Parent = folder
		slot = { part = p, born = 0 }
		marks[markI] = slot
	end
	local mid = (pos + last) / 2 + normal * 0.03
	p.Size = Vector3.new(width, 0.02, len + 0.05)
	p.CFrame = CFrame.lookAt(mid, mid + d, normal)
	p.Transparency = 0.55 - 0.3 * strength
	p:SetAttribute("Base", p.Transparency)
	slot.born = os.clock()
end

local function clearRig()
	if rig then
		for _, inst in ipairs(rig.made) do inst:Destroy() end
	end
	rig = nil
	table.clear(lastMark)
end

local function makeRig(c)
	clearRig()
	local chassis = c.chassis
	local def = c.def
	local made = {}
	rig = { model = c.model, made = made, wheels = {} }
	-- one attachment per rear wheel for smoke / spray
	for i, w in ipairs(c.wheels) do
		if w.Z > 0 then
			local a = Instance.new("Attachment")
			a.Name = "GoDashFxWheel"
			a.Position = Vector3.new(w.X, -c.ride + 0.4 - (c.originY or 0), w.Z)
			a.Parent = chassis
			table.insert(made, a)
			local smoke = emitter(a, {
				Color = ColorSequence.new(Color3.fromRGB(210, 210, 212)), LightInfluence = 1, LightEmission = 0,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 5.5) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(1.2, 2.2), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(60, 60),
				Acceleration = Vector3.new(0, 1.2, 0), Drag = 1.5, RotSpeed = NumberRange.new(-40, 40), Rotation = NumberRange.new(0, 360),
			})
			local spray = emitter(a, {
				Color = ColorSequence.new(Color3.fromRGB(200, 214, 226)), LightInfluence = 1,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1.6) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(0.35, 0.7), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(25, 25),
				EmissionDirection = Enum.NormalId.Back, Acceleration = Vector3.new(0, -30, 0), Drag = 2,
			})
			table.insert(rig.wheels, { index = i, smoke = smoke, spray = spray })
		end
	end
	-- exhaust at the back, low
	local len = def.len or 6
	local ex = Instance.new("Attachment")
	ex.Name = "GoDashFxExhaust"
	ex.Position = Vector3.new(def.class == "bike" and 0.45 or -(def.wid or 6) * 0.3, -c.ride + (def.class == "bike" and 1.0 or 0.9) - (c.originY or 0), len / 2 - 0.2)
	ex.Parent = chassis
	table.insert(made, ex)
	local old = def.id == "oldmoped" or def.style == "oldbike" or def.style == "pickup"
	rig.exhaust = emitter(ex, {
		Color = ColorSequence.new(old and Color3.fromRGB(120, 120, 122) or Color3.fromRGB(190, 190, 194)), LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1.6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, old and 0.55 or 0.75), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(1.5, 3), SpreadAngle = Vector2.new(15, 15),
		EmissionDirection = Enum.NormalId.Back, Acceleration = Vector3.new(0, 1.5, 0), Drag = 2,
	})
	rig.oldEngine = old
	rig.pedal = def.pedal == true
	-- headlight beams: soft cones in the air, only when it's dark or raining
	rig.beams = {}
	for _, p in ipairs(c.model:GetChildren()) do
		if p.Name == "Headlight" and p:IsA("BasePart") then
			local a0 = Instance.new("Attachment")
			a0.Parent = p
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -1.2, -22)
			a1.Parent = p
			local b = Instance.new("Beam")
			b.Attachment0, b.Attachment1 = a0, a1
			b.Width0, b.Width1 = 0.9, 9
			b.FaceCamera = true
			b.LightEmission = 1
			b.LightInfluence = 0
			b.Segments = 6
			b.Color = ColorSequence.new(Color3.fromRGB(255, 240, 210))
			b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1) })
			b.Enabled = false
			b.Parent = p
			table.insert(made, a0); table.insert(made, a1); table.insert(made, b)
			table.insert(rig.beams, b)
		end
	end
end

local function step(c, dt: number, s)
	if not rig or rig.model ~= c.model then makeRig(c) end
	local bike = c.def.class == "bike"
	local dry = (s.wet or 0) < 0.3
	-- tyres: sliding sideways, or locked under hard braking at speed
	for _, w in ipairs(rig.wheels) do
		local ct = c.contacts and c.contacts[w.index]
		local sliding = 0
		if ct and ct.ok then
			local lat = math.abs(ct.lat or 0)
			if lat > 5 then sliding = math.clamp((lat - 5) / 14, 0, 1) end
			if (s.handbrake or (s.braking and s.speed > 18)) and s.speed > 9 then sliding = math.max(sliding, s.handbrake and 0.8 or 0.45) end
			if sliding > 0.05 then
				markAt(w.index, ct.pos, ct.normal, bike and 0.32 or 0.62, sliding)
			else
				lastMark[w.index] = nil
			end
		else
			lastMark[w.index] = nil
		end
		local fxk = Perf.limit("effects") -- fewer particles on phones and slow devices (client/Perf)
		w.smoke.Rate = ((dry and sliding > 0.15 and s.speed > 6) and (12 + 48 * sliding) or 0) * fxk
		w.spray.Rate = ((not dry and s.speed > 14 and ct and ct.ok) and math.clamp(s.speed * 0.9, 0, 70) or 0) * fxk
	end
	-- exhaust
	if rig.exhaust then
		local rate = 0
		if not rig.pedal and s.hasPower then
			rate = rig.oldEngine and 5 or 2
			if s.throttle > 0.5 and s.speed < s.top * 0.6 then rate += rig.oldEngine and 18 or 9 end
		end
		rig.exhaust.Rate = rate
	end
	-- headlight beams
	local dark = Workspace:GetAttribute("IsNight") == true or (Workspace:GetAttribute("Rain") or 0) > 0.2 or Lighting.ClockTime < 6.2 or Lighting.ClockTime > 18.4
	local on = c.lights == true and dark
	for _, b in ipairs(rig.beams) do
		if b.Enabled ~= on then b.Enabled = on end
	end
	-- speed streaks past the camera
	if streak then
		local rev = s.speed / math.max(s.top, 1)
		streak.Rate = (rev > 0.6 and (rev - 0.6) / 0.4 * 140 or 0) * Perf.limit("effects")
	end
end

function DriveFx.start()
	folder = Instance.new("Folder")
	folder.Name = "GoDashSkidMarks"
	folder.Parent = Workspace
	Drive.fx = step
	Drive.onExit = function(c)
		if rig and rig.model == c.model then clearRig() end
		if streak then streak.Rate = 0 end
	end
	-- the streaks: emitted from a sheet just in front of the camera, flying back past it
	streakPart = Instance.new("Part")
	streakPart.Name = "GoDashSpeedStreaks"
	streakPart.Anchored = true; streakPart.CanCollide = false; streakPart.CanQuery = false; streakPart.CanTouch = false
	streakPart.Transparency = 1
	streakPart.Size = Vector3.new(34, 20, 1)
	streakPart.Parent = Workspace
	streak = emitter(streakPart, {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)), LightEmission = 0.4, LightInfluence = 0.3,
		Size = seq(0.06, 0.02), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.18, 0.32), Speed = NumberRange.new(80, 120), EmissionDirection = Enum.NormalId.Back,
		Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = NumberSequence.new(4), Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		if cam and streakPart then streakPart.CFrame = cam.CFrame * CFrame.new(0, 0, -16) end
		-- old skid marks fade out
		local now = os.clock()
		for _, slot in ipairs(marks) do
			local age = now - slot.born
			if slot.born > 0 and age > MARK_LIFE - 5 then
				if age >= MARK_LIFE then
					slot.part.Transparency = 1
					slot.born = 0
				else
					local base = slot.part:GetAttribute("Base") or 0.4
					slot.part.Transparency = base + (1 - base) * (age - (MARK_LIFE - 5)) / 5
				end
			end
		end
	end)
end

return DriveFx
