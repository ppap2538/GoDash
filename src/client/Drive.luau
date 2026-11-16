-- Driving. The driver's client simulates their vehicle: four ray-cast wheels with spring and
-- damper, tyre grip that gives way in the wet, engine / brake forces from Config/Vehicles and the
-- owned upgrades. One model drives everything from the bicycle to the supercar.
-- Controls  PC: W/S throttle & brake-reverse, A/D steer, Space handbrake, Shift boost,
--               F lights, Z/C indicators, X hazards, H horn, E leave.   Mobile: on-screen pedals.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Vehicles = require(Shared.Config.Vehicles)
local Sounds = require(Shared.Config.Sounds)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)

local Drive = {}
local player = Players.LocalPlayer
local cur = nil -- the vehicle being driven
Drive.touch = { throttle = 0, steer = 0, handbrake = false } -- written by the HUD pedals
Drive.info = { driving = false, speed = 0, fuel = 0, fuelCap = 0, condition = 100, lights = false, signal = 0, pedal = false, name = "" }

local GRAVITY = Workspace.Gravity
local SPRING = 70 -- per unit mass (per wheel)
local DAMP = 4.4

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function attr(model: Instance, name: string, default: number): number
	local v = model:GetAttribute(name)
	return type(v) == "number" and v or default
end

local function readStats(c)
	local owned = { condition = attr(c.model, "Condition", 100) }
	for _, up in ipairs(Vehicles.UPGRADES) do owned[up.id] = attr(c.model, "Up_" .. up.id, 0) end
	c.stats = Vehicles.computeStats(c.def, owned)
end

local function sendState(force: boolean?)
	if not cur then return end
	local now = os.clock()
	local brake = cur.braking
	if force or (now - (cur.lastSend or 0) > 0.12 and (cur.sentLights ~= cur.lights or cur.sentBrake ~= brake or cur.sentSignal ~= cur.signal)) then
		cur.lastSend = now
		cur.sentLights, cur.sentBrake, cur.sentSignal = cur.lights, brake, cur.signal
		Net.send("VehicleState", cur.lights, brake, cur.signal)
	end
end

local function leave()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Sit = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end
Drive.leave = leave

local function exit()
	if not cur then return end
	local c = cur
	cur = nil
	Drive.info.driving = false
	if c.engine then c.engine:Destroy() end
	if c.skid then c.skid:Destroy() end
	if c.bodyWeld and c.bodyWeld.Parent then c.bodyWeld.C0 = c.bodyBase end
	for _, s in ipairs(c.spin or {}) do
		if s.weld.Parent then s.weld.C0 = s.base end
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
	ContextActionService:UnbindAction("GoDashDriveKeys")
	local cam = Workspace.CurrentCamera
	if cam then cam.FieldOfView = 70 end
end

local function enter(model: Model, seat: VehicleSeat)
	exit()
	local def = Vehicles.ById[model:GetAttribute("VehicleId")]
	local chassis = model.PrimaryPart
	if not def or not chassis then return end
	local c = {
		model = model, chassis = chassis, seat = seat, def = def,
		originY = attr(model, "OriginY", 0), ride = attr(model, "RideHeight", 2),
		wheels = {}, steer = 0, lights = false, signal = 0, braking = false, lastSpeed = 0, flipT = 0, airT = 0, pitch = 0, lean = 0,
	}
	for i = 1, 4 do
		local w = model:GetAttribute("Wheel" .. i)
		if typeof(w) == "Vector3" then table.insert(c.wheels, w) end
	end
	local zMin, zMax = math.huge, -math.huge
	for _, w in ipairs(c.wheels) do zMin = math.min(zMin, w.Z); zMax = math.max(zMax, w.Z) end
	c.wheelbase = math.max(2, (zMax > zMin) and (zMax - zMin) or 4)
	c.bodyWeld = chassis:FindFirstChild("BodyWeld")
	c.bodyBase = CFrame.new(0, -c.originY, 0)
	readStats(c)
	c.spin = {}
	local bodyPart = model:FindFirstChild("Body")
	if bodyPart then
		for _, key in ipairs({ "F", "R" }) do
			local weld = bodyPart:FindFirstChild("Spin" .. key)
			local wheelPart = model:FindFirstChild("Wheel" .. key)
			if weld and wheelPart then
				table.insert(c.spin, { weld = weld, base = weld.C0, r = math.max(0.3, wheelPart:GetAttribute("Radius") or 1), angle = 0 })
			end
		end
	end
	c.crank = 0
	c.joints = nil -- found lazily: the character may still be loading its limbs
	c.lights = model:GetAttribute("Lights") == true
	rayParams.FilterDescendantsInstances = { model, player.Character }

	local eng = Instance.new("Sound")
	eng.Name = "Engine"
	eng.Looped = true
	eng.SoundId = def.pedal and "" or (def.class == "bike" and Sounds.engineBike or Sounds.engineCar)
	eng.Volume = 0
	eng.RollOffMaxDistance = 200
	eng.SoundGroup = Feedback.sfxGroup
	eng.Parent = chassis
	if eng.SoundId ~= "" then eng:Play() end
	c.engine = eng
	local skid = Instance.new("Sound")
	skid.Looped = true
	skid.SoundId = Sounds.skid
	skid.Volume = 0
	skid.SoundGroup = Feedback.sfxGroup
	skid.Parent = chassis
	skid:Play()
	c.skid = skid

	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end -- Space is the handbrake

	ContextActionService:BindAction("GoDashDriveKeys", function(_, state, input)
		if state ~= Enum.UserInputState.Begin or not cur then return Enum.ContextActionResult.Pass end
		local k = input.KeyCode
		if k == Enum.KeyCode.E then leave()
		elseif k == Enum.KeyCode.F then Drive.toggleLights()
		elseif k == Enum.KeyCode.Z then Drive.setSignal(cur.signal == -1 and 0 or -1)
		elseif k == Enum.KeyCode.C then Drive.setSignal(cur.signal == 1 and 0 or 1)
		elseif k == Enum.KeyCode.X then Drive.setSignal(cur.signal == 2 and 0 or 2)
		elseif k == Enum.KeyCode.H then Feedback.play("tick", 0.9, 0.55, 0.3)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.F, Enum.KeyCode.Z, Enum.KeyCode.C, Enum.KeyCode.X, Enum.KeyCode.H)

	cur = c
	Drive.info.driving = true
	Drive.info.name = def.name
	Drive.info.pedal = def.pedal == true
	Drive.info.fuelCap = def.fuelCap
	Drive.info.class = def.class
end

function Drive.toggleLights()
	if not cur then return end
	cur.lights = not cur.lights
	Drive.info.lights = cur.lights
	Feedback.click()
	sendState(true)
end

function Drive.setSignal(s: number)
	if not cur then return end
	cur.signal = s
	Drive.info.signal = s
	Feedback.click()
	sendState(true)
end

---------------------------------------------------------------------------------------------------
-- physics step
---------------------------------------------------------------------------------------------------
local function step(dt: number)
	local c = cur
	if not c then return end
	if not c.model.Parent or not c.chassis.Parent or c.seat.Occupant == nil then exit(); return end
	dt = math.min(dt, 1 / 30)
	local chassis = c.chassis
	local cf = chassis.CFrame * CFrame.new(0, -c.originY, 0)
	local up, fwd, right = cf.UpVector, cf.LookVector, cf.RightVector
	local mass = chassis.AssemblyMass
	local vel = chassis.AssemblyLinearVelocity
	local speedF = vel:Dot(fwd)
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local stats = c.stats
	local settings = State.data and State.data.settings or {}

	-- inputs: keyboard / gamepad / thumbstick arrive through the VehicleSeat, pedals through Drive.touch
	local throttle = c.seat.ThrottleFloat
	local steerIn = c.seat.SteerFloat
	local t = Drive.touch
	if t.throttle ~= 0 then throttle = t.throttle end
	if t.steer ~= 0 then steerIn = t.steer end
	local qaT, qaS = c.model:GetAttribute("QaThrottle"), c.model:GetAttribute("QaSteer")
	if type(qaT) == "number" then throttle = qaT end
	if type(qaS) == "number" then steerIn = qaS end
	local handbrake = t.handbrake or UserInputService:IsKeyDown(Enum.KeyCode.Space)
	local boost = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)

	local fuel = attr(c.model, "Fuel", 0)
	local hasPower = c.def.pedal or fuel > 0
	if not hasPower and throttle > 0 and os.clock() - (c.fuelWarn or 0) > 8 then
		c.fuelWarn = os.clock()
		Feedback.toast("⛽ Out of fuel! Open Garage on your phone for emergency fuel.", "bad")
	end
	if not c.def.pedal and c.def.fuelCap > 0 and fuel > 0 and fuel / c.def.fuelCap < 0.15 and os.clock() - (c.lowFuelWarn or 0) > 45 then
		c.lowFuelWarn = os.clock()
		Feedback.toast("⛽ Fuel is low. Phone > Maps > Nearest fuel station.", "bad")
	end
	local energy = State.data and State.data.energy or 100
	local pedalPower = c.def.pedal and (energy > 5 and 1 or 0.55) or 1

	-- steering: less lock at speed, smoothed by the handling upgrade and the sensitivity setting
	local top = stats.topSpeed
	local frac = math.clamp(math.abs(speedF) / math.max(top, 1), 0, 1)
	local maxAngle = math.rad(c.def.steer + (6.5 - c.def.steer) * frac ^ 0.65)
	local sens = math.clamp(settings.steer or 1, 0.5, 2)
	local target = steerIn * maxAngle
	c.steer += (target - c.steer) * math.min(1, stats.steerRate * sens * dt * 2.2)
	local sinS, cosS = math.sin(c.steer), math.cos(c.steer)

	local wet = Workspace:GetAttribute("Wet") or 0
	local gripMult = 1 + (stats.wetGrip - 1) * wet
	local assist = settings.assist ~= false

	local n = #c.wheels
	local share = mass / n
	local k = share * SPRING
	local damp = share * DAMP * stats.springDamp
	local com = chassis.AssemblyCenterOfMass
	local grounded = 0
	local slip = 0
	local braking = false

	for i = 1, n do
		local lp = c.wheels[i]
		local origin = cf:PointToWorldSpace(Vector3.new(lp.X, 0, lp.Z))
		local hit = Workspace:Raycast(origin, -up * (c.ride + 1.3), rayParams)
		if hit then
			grounded += 1
			local comp = c.ride - hit.Distance
			local pv = chassis:GetVelocityAtPosition(origin)
			local f = share * GRAVITY + k * comp - damp * pv:Dot(up)
			f = math.clamp(f, 0, share * GRAVITY * 4)
			-- push along the ground normal, not the chassis: a rider's weight tilting the body must not shove it backwards
			chassis:ApplyImpulseAtPosition(hit.Normal * (f * dt), origin)

			local front = lp.Z < 0
			local wf, wr = fwd, right
			if front then
				wf = fwd * cosS + right * sinS
				wr = right * cosS - fwd * sinS
			end
			-- sideways grip, limited like a real tyre so it can slide
			local lat = pv:Dot(wr)
			local gripRate = stats.grip * gripMult
			if handbrake and not front then gripRate *= 0.3 end
			local latF = -lat * share * gripRate
			local limit = share * GRAVITY * (assist and 1.9 or 1.5) * gripMult
			if math.abs(latF) > limit then
				slip += math.abs(latF) - limit
				latF = math.sign(latF) * limit
			end
			-- along the wheel: engine, brakes, drag
			local lon = 0
			local ws = pv:Dot(wf)
			if throttle > 0.02 then
				if ws < -1.5 then
					lon = stats.brake * share * throttle; braking = true
				elseif hasPower and ws < top then
					local curve = math.clamp(1 - (ws / top) ^ 3, 0.04, 1)
					lon = throttle * stats.accel * share * curve * pedalPower * (boost and 1.18 or 1) * (0.55 + 0.45 * gripMult)
				end
			elseif throttle < -0.02 then
				if ws > 1.5 then
					lon = -stats.brake * share * -throttle * gripMult; braking = true
				elseif hasPower and ws > -top * 0.28 then
					lon = throttle * stats.accel * 0.7 * share
				end
			end
			if handbrake and not front then
				lon -= math.sign(ws) * stats.brake * 1.2 * share * math.min(1, math.abs(ws) / 2)
				braking = true
			end
			lon -= ws * share * (throttle == 0 and 0.32 or 0.1) -- rolling resistance and engine braking
			lon -= ws * math.abs(ws) * share * 0.0009 -- air
			if math.abs(throttle) < 0.02 and math.abs(ws) < 2 then lon -= ws * share * 6 end -- hold still
			local at = origin + up * (com - origin):Dot(up) -- push at the height of the centre of mass: no flip-over
			chassis:ApplyImpulseAtPosition((wr * latF + wf * lon) * dt, at)
		end
	end

	-- keep it upright: strong for two wheels, gentle for four
	local angVel = chassis.AssemblyAngularVelocity
	local roll = math.asin(math.clamp(right.Y, -1, 1))
	local pitchA = math.asin(math.clamp(fwd.Y, -1, 1))
	local bike = c.def.class == "bike"
	local kr, cr = bike and 110 or 26, bike and 16 or 5
	-- a positive turn about the forward axis lowers the right side, so a raised right side (roll > 0) needs positive torque
	-- cornering too hard for the speed: a bike goes down, a car rolls (driving assist gives more margin)
	local aLat = angVel:Dot(up) * speedF
	-- (studs/s²; full lock near top speed on a motorbike goes over, a bicycle never does)
	local overLimit = (bike and 52 * gripMult or 80) * (assist and 1.15 or 1)
	if grounded > 0 and math.abs(aLat) > overLimit and speed > (bike and 16 or 34) then
		c.overT = (c.overT or 0) + dt
	else
		c.overT = math.max(0, (c.overT or 0) - dt * 2)
	end
	if (c.overT or 0) > (bike and 0.3 or 0.45) and not c.fallen then
		c.fallen = os.clock()
		c.fallDir = aLat >= 0 and 1 or -1
		c.overT = 0
		Net.send("VehicleFall")
		Feedback.toast(bike and "💥 Too fast into the corner: you went down!" or "💥 Rolled it! Slow down for corners.", "bad")
	end
	local torque
	if c.fallen then
		torque = fwd * (c.fallDir * (bike and 60 or 42) * mass)
		if os.clock() - c.fallen > 2.4 then c.fallen = nil end
	else
		torque = fwd * ((roll * kr - angVel:Dot(fwd) * cr) * mass)
	end
	if grounded == 0 then
		torque -= right * (angVel:Dot(right) * mass * 0.6) -- calm the tumbling while airborne
	end
	local _ = pitchA
	torque -= up * (angVel:Dot(up) * mass * (grounded > 0 and 0.6 or 0.2)) -- yaw damping
	chassis:ApplyAngularImpulse(torque * dt)

	-- driving assist: the vehicle turns the way its front wheel points and slides less sideways,
	-- so steering feels direct instead of scrubbing speed (Settings > Driving assist turns it off)
	if assist and grounded > 0 and not c.fallen and math.abs(speedF) > 1.5 then
		local wantYaw = -speedF * math.tan(c.steer) / c.wheelbase
		local av = chassis.AssemblyAngularVelocity
		local yawNow = av:Dot(up)
		chassis.AssemblyAngularVelocity = av + up * ((wantYaw - yawNow) * math.min(1, dt * 6))
		if not handbrake then
			local lv = chassis.AssemblyLinearVelocity
			chassis.AssemblyLinearVelocity = lv - right * (lv:Dot(right) * math.min(1, dt * 4))
		end
	end

	-- flipped over? set it back on its wheels
	if up.Y < 0.25 then
		c.flipT += dt
		if c.flipT > 1.6 then
			c.flipT = 0
			local look = Vector3.new(fwd.X, 0, fwd.Z)
			if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
			local p = chassis.Position + Vector3.new(0, 3, 0)
			chassis.CFrame = CFrame.lookAt(p, p + look) * CFrame.new(0, c.originY, 0)
			chassis.AssemblyLinearVelocity = Vector3.zero
			chassis.AssemblyAngularVelocity = Vector3.zero
		end
	else
		c.flipT = 0
	end

	-- body motion: bikes lean into corners, cars roll out and pitch under power
	local yawRate = angVel:Dot(up)
	local accel = (speedF - c.lastSpeed) / dt
	c.lastSpeed = speedF
	local leanTarget = bike and math.clamp(-yawRate * speedF * 0.011, -0.6, 0.6) or math.clamp(yawRate * speedF * 0.0016, -0.07, 0.07)
	local pitchTarget = math.clamp(accel * (bike and 0.0015 or 0.0022), -0.07, 0.07)
	c.lean += (leanTarget - c.lean) * math.min(1, dt * 7)
	c.pitch += (pitchTarget - c.pitch) * math.min(1, dt * 6)
	if c.bodyWeld then
		c.bodyWeld.C0 = c.bodyBase * CFrame.new(0, -c.ride + 0.2, 0) * CFrame.Angles(c.pitch, 0, c.lean) * CFrame.new(0, c.ride - 0.2, 0)
	end

	-- wheels roll with the road speed; the crank follows on a bicycle
	for _, s in ipairs(c.spin) do
		s.angle = (s.angle + speedF * dt / s.r) % (math.pi * 2)
		s.weld.C0 = s.base * CFrame.Angles(-s.angle, 0, 0)
	end
	if c.def.pedal then
		local cadence = throttle > 0.05 and math.clamp(3 + math.abs(speedF) * 0.35, 3, 11) or 0
		c.crank = (c.crank + cadence * dt) % (math.pi * 2)
	end
	c.steerNow = steerIn

	-- sound and camera
	local rev = math.clamp(math.abs(speedF) / math.max(top, 1), 0, 1.1)
	if c.engine then
		c.engine.PlaybackSpeed = 0.75 + rev * 1.1 + math.abs(throttle) * 0.12
		c.engine.Volume = hasPower and (0.18 + rev * 0.3 + math.abs(throttle) * 0.12) or 0
	end
	if c.skid then
		local want = (slip > mass * 2 and speed > 12) and math.clamp(slip / (mass * 40), 0.15, 0.6) or 0
		c.skid.Volume += (want - c.skid.Volume) * math.min(1, dt * 10)
	end
	local cam = Workspace.CurrentCamera
	if cam then cam.FieldOfView += ((70 + rev * 12) - cam.FieldOfView) * math.min(1, dt * 3) end

	c.braking = braking
	Drive.info.speed = speed
	Drive.info.fuel = fuel
	Drive.info.condition = attr(c.model, "Condition", 100)
	Drive.info.grounded = grounded
	Drive.info.wet = wet
	c.statT = (c.statT or 0) + dt
	if c.statT > 1 then
		c.statT = 0
		readStats(c) -- upgrades, repairs and wear change the numbers while driving
	end
	sendState(false)
end

---------------------------------------------------------------------------------------------------
-- lights for every vehicle in view (driven by replicated attributes)
---------------------------------------------------------------------------------------------------
local RED_OFF, RED_ON = Color3.fromRGB(150, 20, 20), Color3.fromRGB(255, 40, 40)
local AMBER_OFF, AMBER_ON = Color3.fromRGB(180, 110, 20), Color3.fromRGB(255, 180, 30)
local blinkers = {}

local function paintLights(model: Model)
	local lights = model:GetAttribute("Lights") == true
	local brake = model:GetAttribute("Brake") == true
	for _, p in ipairs(model:GetChildren()) do
		if p.Name == "Headlight" then
			p.Material = lights and Enum.Material.Neon or Enum.Material.SmoothPlastic
			local beam = p:FindFirstChild("Beam")
			if beam then beam.Enabled = lights end
		elseif p.Name == "TailLight" then
			p.Material = (brake or lights) and Enum.Material.Neon or Enum.Material.SmoothPlastic
			p.Color = brake and RED_ON or RED_OFF
		end
	end
	blinkers[model] = (model:GetAttribute("Signal") or 0) ~= 0 and true or nil
	if not blinkers[model] then
		for _, p in ipairs(model:GetChildren()) do
			if p.Name:sub(1, 6) == "Signal" then p.Material = Enum.Material.SmoothPlastic; p.Color = AMBER_OFF end
		end
	end
end

local function watch(model: Instance)
	if not model:IsA("Model") then return end
	paintLights(model)
	for _, a in ipairs({ "Lights", "Brake", "Signal" }) do
		model:GetAttributeChangedSignal(a):Connect(function() paintLights(model) end)
	end
	model.Destroying:Connect(function() blinkers[model] = nil end)
end

-- Rider pose on two wheels: lean in, hands on the bars, legs pedalling on a bicycle.
-- Added on top of the sit animation every frame (R15 avatars; others keep the plain sit).
local function findJoints(char: Model)
	local function j(partName: string, jointName: string)
		local p = char:FindFirstChild(partName)
		local m = p and p:FindFirstChild(jointName)
		return (m and m:IsA("Motor6D")) and m or nil
	end
	local t = {
		waist = j("UpperTorso", "Waist"),
		rs = j("RightUpperArm", "RightShoulder"), ls = j("LeftUpperArm", "LeftShoulder"),
		re = j("RightLowerArm", "RightElbow"), le = j("LeftLowerArm", "LeftElbow"),
		rh = j("RightUpperLeg", "RightHip"), lh = j("LeftUpperLeg", "LeftHip"),
		rk = j("RightLowerLeg", "RightKnee"), lk = j("LeftLowerLeg", "LeftKnee"),
	}
	return (t.waist and t.rs and t.ls) and t or false
end

local function riderPose()
	local c = cur
	if not c or c.def.class ~= "bike" then return end
	local char = player.Character
	if not char then return end
	if c.joints == nil then c.joints = findJoints(char) end
	local J = c.joints
	if not J then return end
	local A = CFrame.Angles
	local steer = (c.steerNow or 0) * 0.16
	local sport = c.def.style == "sport" or c.def.style == "bigbike"
	J.waist.Transform *= A(math.rad(sport and -24 or -11), 0, 0)
	local reach = math.rad(sport and 78 or 66)
	J.rs.Transform *= A(reach + steer, 0, math.rad(-7))
	J.ls.Transform *= A(reach - steer, 0, math.rad(7))
	if J.re then J.re.Transform *= A(math.rad(16), 0, 0) end
	if J.le then J.le.Transform *= A(math.rad(16), 0, 0) end
	if c.def.pedal and J.rh and J.lh then
		local s = math.sin(c.crank)
		J.rh.Transform *= A(math.rad(-22) + math.rad(24) * s, 0, 0)
		J.lh.Transform *= A(math.rad(-22) - math.rad(24) * s, 0, 0)
		if J.rk then J.rk.Transform *= A(math.rad(-26) - math.rad(26) * s, 0, 0) end
		if J.lk then J.lk.Transform *= A(math.rad(-26) + math.rad(26) * s, 0, 0) end
	elseif J.rh and J.lh then
		-- feet down on the pegs instead of straight out
		J.rh.Transform *= A(math.rad(-14), 0, 0)
		J.lh.Transform *= A(math.rad(-14), 0, 0)
		if J.rk then J.rk.Transform *= A(math.rad(-18), 0, 0) end
		if J.lk then J.lk.Transform *= A(math.rad(-18), 0, 0) end
	end
end

-- V switches between third person and first person (works on foot and on a vehicle).
function Drive.toggleView()
	local first = player.CameraMode == Enum.CameraMode.LockFirstPerson
	player.CameraMode = first and Enum.CameraMode.Classic or Enum.CameraMode.LockFirstPerson
	if first then
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 60
	end
	Feedback.toast(first and "Third-person view" or "First-person view (V to switch back)")
end

function Drive.start()
	RunService.Stepped:Connect(riderPose)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.V then Drive.toggleView() end
	end)
	local function hookCharacter(char: Model)
		local hum = char:WaitForChild("Humanoid", 10)
		if not hum then return end
		hum.Seated:Connect(function(active, seatPart)
			if active and seatPart and seatPart:IsA("VehicleSeat") and seatPart.Parent and seatPart.Parent:HasTag("GoDashVehicle") then
				enter(seatPart.Parent, seatPart)
			else
				exit()
			end
		end)
	end
	if player.Character then task.spawn(hookCharacter, player.Character) end
	player.CharacterAdded:Connect(hookCharacter)

	RunService.PreSimulation:Connect(step)

	for _, m in ipairs(CollectionService:GetTagged("GoDashVehicle")) do watch(m) end
	CollectionService:GetInstanceAddedSignal("GoDashVehicle"):Connect(watch)
	task.spawn(function()
		local on = false
		while true do
			task.wait(0.38)
			on = not on
			for model in pairs(blinkers) do
				local s = model:GetAttribute("Signal") or 0
				for _, p in ipairs(model:GetChildren()) do
					local nm = p.Name
					if nm:sub(1, 6) == "Signal" then
						local left = nm:sub(-1) == "L"
						local lit = on and (s == 2 or (s == -1 and left) or (s == 1 and not left))
						p.Material = lit and Enum.Material.Neon or Enum.Material.SmoothPlastic
						p.Color = lit and AMBER_ON or AMBER_OFF
					end
				end
			end
		end
	end)
end

return Drive
