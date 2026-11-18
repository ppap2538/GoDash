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
local Crash = require(script.Parent.Crash)
local EngineSound = require(script.Parent.EngineSound)

local Drive = {}
local player = Players.LocalPlayer
local cur = nil -- the vehicle being driven
Drive.touch = { throttle = 0, steer = 0, handbrake = false } -- written by the HUD pedals
Drive.autoGas = false -- phones with "auto gas": cruising after a tap on GAS, until BRAKE (UI/HUD/TouchControls)
-- client/AutoDrive sets this: (c, ctx) -> throttle, steer, handbrake (or nil when it lets go)
Drive.autopilot = nil :: ((any, any) -> (number?, number?, boolean?))?
-- client/Cutscene sets this: called once when a hard crash throws the rider off (see the hard-hit check)
Drive.onCrash = nil :: ((any) -> ())?
Drive.onHorn = nil :: (() -> ())? -- client/StreetLife
Drive.fx = nil :: ((any, number, any) -> ())? -- client/DriveFx: per-step effects
Drive.onHit = nil :: ((any) -> ())? -- client/Accident: { instance, dv, at, model } for every hard hit
Drive.onExit = nil :: ((any) -> ())? -- client/DriveFx: clean up when you get off
-- client/LaneAssist sets this: (c, ctx) -> a small steering correction (-1..1) while the rider barely steers
Drive.laneAssist = nil :: ((any, any) -> number?)?
Drive.stallUntil = 0 -- client/StreetLife: the engine is dead until then (water in the exhaust)
Drive.info = { driving = false, speed = 0, fuel = 0, fuelCap = 0, condition = 100, lights = false, signal = 0, pedal = false, name = "" }

local GRAVITY = Workspace.Gravity
local SPRING = 70 -- per unit mass (per wheel)
local DAMP = 4.4

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

-- Steering lock at speed (2026-11-18, owner: "hard to control on PC and phone"). It used to shrink linearly from
-- the vehicle's lock to 6.5° at top speed, which still asked ~3 g of the tyres at 40 km/h and ~6 g at top speed:
-- a tap of A/D swerved the bike across the road. Now the lock is whatever keeps the sideways acceleration
-- (v² / turn radius) under the tyres' grip: full lock when slow, a calm, stable line when fast.
-- 1 stud = 0.28 m, so 35 studs/s² ≈ 1 g; LAT_G = 1.7 g for ordinary grip, more for grippy sports tyres.
local LAT_G = 1.7
local function maxSteer(c, speedF: number, gripMult: number?): number
	local aLat = 35 * LAT_G * (c.stats.grip / 10.5) * (gripMult or 1)
	local v = math.abs(speedF)
	return math.min(math.rad(c.def.steer), math.atan(c.wheelbase * aLat / math.max(v * v, 1)))
end
Drive.maxSteer = maxSteer

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

-- Get off: step down beside the vehicle on the seat's side (left on a motorbike, the way Thai
-- riders get off; the driver's door side in a car) instead of hopping into the air (2026-11-18).
local function leave()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum then return end
	local seat = hum.SeatPart
	local model = seat and seat.Parent
	local chassis = model and model:IsA("Model") and model.PrimaryPart
	hum.Sit = false
	if not (seat and chassis and root) then
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		return
	end
	local def = Vehicles.ById[model:GetAttribute("VehicleId")]
	local lx = chassis.CFrame:PointToObjectSpace(seat.Position).X
	local sideSign = (def and def.class == "car") and (lx >= 0 and 1 or -1) or -1
	local out = (def and def.class == "car") and ((def.wid or 6) / 2 + 1.6) or 2.3
	local look = Vector3.new(chassis.CFrame.LookVector.X, 0, chassis.CFrame.LookVector.Z)
	if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
	local spot = (chassis.CFrame * CFrame.new(sideSign * out, 0, 0)).Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model, char }
	local g = Workspace:Raycast(spot + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), params)
	local y = (g and g.Position.Y or spot.Y) + hum.HipHeight + root.Size.Y / 2
	task.defer(function()
		if root.Parent then
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = CFrame.lookAt(Vector3.new(spot.X, y, spot.Z), Vector3.new(spot.X, y, spot.Z) + look.Unit)
		end
	end)
end
Drive.leave = leave

local function exit()
	if not cur then return end
	local c = cur
	cur = nil
	Drive.info.driving = false
	Drive.info.auto = false
	Drive.autoGas = false
	if Drive.onExit then pcall(Drive.onExit, c) end
	if c.audio then c.audio:stop() end
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
	c.lastVel = nil
	-- paint colour for crash shards: the biggest visible body part
	local best, bv = nil, 0
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.5 then
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > bv then best, bv = p, v end
		end
	end
	c.paint = best and best.Color or nil
	c.lights = model:GetAttribute("Lights") == true
	rayParams.FilterDescendantsInstances = { model, player.Character }

	c.audio = EngineSound.new(def, chassis) -- revs, gears, load, wind, brakes, horn (client/EngineSound)
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
		elseif k == Enum.KeyCode.H then
			if cur.audio then cur.audio:horn() end
			if Drive.onHorn then Drive.onHorn() end -- client/StreetLife: the live-streamer steps back
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
	-- phones: "auto gas" holds the throttle while you only steer and brake (Phone > Settings)
	if Drive.autoGas and t.throttle == 0 and throttle == 0 and not handbrake and Drive.info.auto ~= true then throttle = 1 end
	-- keys are on/off: ramp the steering in (slower at speed) and let it centre quickly, so a tap is a nudge.
	-- Analogue input (thumb pad, gamepad stick) already says how hard, so it passes almost straight through.
	local analogue = steerIn ~= 0 and math.abs(steerIn) < 0.999
	local fracNow = math.clamp(math.abs(speedF) / math.max(c.stats.topSpeed, 1), 0, 1)
	c.steerCmd = c.steerCmd or 0
	local towardZero = steerIn == 0 or (c.steerCmd ~= 0 and math.sign(steerIn) ~= math.sign(c.steerCmd))
	local rate = analogue and 12 or (towardZero and 7 or (4.2 - 2.4 * fracNow))
	local dCmd = steerIn - c.steerCmd
	c.steerCmd += math.clamp(dCmd, -rate * dt, rate * dt)
	steerIn = c.steerCmd
	-- lane assist: a gentle pull to the middle of your lane while you barely steer (client/LaneAssist)
	if Drive.laneAssist and math.abs(steerIn) < 0.08 and not handbrake and not Drive.info.auto then
		local ok, corr = pcall(Drive.laneAssist, c, { cf = cf, fwd = fwd, right = right, speedF = speedF, dt = dt, maxAngle = maxSteer(c, speedF) })
		if ok and type(corr) == "number" then steerIn = math.clamp(steerIn + corr, -0.6, 0.6) end
	end
	local ap = Drive.autopilot
	if ap and Drive.info.auto then
		local aT, aS, aH = ap(c, {
			cf = cf, fwd = fwd, right = right, speedF = speedF, dt = dt, manualT = throttle, manualS = steerIn, manualH = handbrake,
			maxAngle = maxSteer(c, speedF),
		})
		if aT then throttle, steerIn, handbrake = aT, aS or 0, aH == true end
	end
	if State.cutscene then throttle, steerIn, handbrake = 0, 0, true end -- parked while the rider is off the bike in a scene
	local boost = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)

	-- hard hits: a big change of velocity within one step is a collision, not the brakes. Sparks,
	-- shards and sound at the contact point; a real smash throws the rider off (client/Cutscene "crash",
	-- owner 2026-11-17) and the vehicle stays where it stopped.
	if c.lastVel then
		local dv = Vector3.new(c.lastVel.X - vel.X, 0, c.lastVel.Z - vel.Z).Magnitude
		if dv > 11 and os.clock() - (c.hitAt or 0) > 0.4 then
			c.hitAt = os.clock()
			local dir = Vector3.new(c.lastVel.X, 0, c.lastVel.Z)
			dir = dir.Magnitude > 0.1 and dir.Unit or fwd
			local half = (c.def.len or 6) / 2
			local r = Workspace:Raycast(chassis.Position, dir * (half + 3), rayParams)
			local at = r and r.Position or (chassis.Position + dir * half)
			Crash.effect(at, math.clamp((dv - 11) / 34, 0.12, 1), { normal = r and r.Normal or -dir, mine = true, color = c.paint })
			if Drive.onHit then task.spawn(Drive.onHit, { instance = r and r.Instance, dv = dv, at = at, model = c.model, car = c.def.class == "car" }) end
			local hard = c.def.class == "car" and 38 or 24
			if dv > hard and not State.cutscene and Drive.onCrash and os.clock() - (c.thrownAt or 0) > 4 then
				c.thrownAt = os.clock()
				Drive.autoGas = false
				local hv = Vector3.new(c.lastVel.X, 0, c.lastVel.Z)
				Net.send("VehicleFall", hv.Magnitude) -- (the speed sets how badly the rider is hurt: server/HealthService)
				Drive.onCrash({ dir = dir, speed = hv.Magnitude, at = at, model = c.model, car = c.def.class == "car" })
			end
		end
	end
	c.lastVel = vel
	Crash.sweep(chassis, (c.def.len or 6) / 2)

	local fuel = attr(c.model, "Fuel", 0)
	local hasPower = (c.def.pedal or fuel > 0) and (c.def.pedal or os.clock() >= Drive.stallUntil) -- client/StreetLife floods stall small engines
	-- (the Guide card already shows low fuel with a route button, so these toasts stay rare)
	if not hasPower and throttle > 0 and os.clock() - (c.fuelWarn or 0) > 25 then
		c.fuelWarn = os.clock()
		Feedback.toast("⛽ Out of fuel! Open Garage on your phone for emergency fuel.", "bad")
	end
	if not c.def.pedal and c.def.fuelCap > 0 and fuel > 0 and fuel / c.def.fuelCap < 0.15 and not c.lowFuelWarn then
		c.lowFuelWarn = os.clock()
		Feedback.toast("⛽ Fuel is low. Phone > Maps > Nearest fuel station.", "bad")
	end
	local energy = State.data and State.data.energy or 100
	local pedalPower = c.def.pedal and (energy > 5 and 1 or 0.55) or 1

	-- steering: the lock the tyres can hold at this speed (maxSteer), smoothed by the handling upgrade and the
	-- sensitivity setting; the handbrake lets you swing the tail round anyway
	local top = stats.topSpeed
	local wet = Workspace:GetAttribute("Wet") or 0
	local gripMult = 1 + (stats.wetGrip - 1) * wet
	local maxAngle = maxSteer(c, speedF, gripMult)
	if handbrake then maxAngle = math.min(math.rad(c.def.steer), maxAngle * 1.8) end
	local sens = math.clamp(settings.steer or 1, 0.5, 2)
	local target = steerIn * maxAngle
	c.steer += (target - c.steer) * math.min(1, stats.steerRate * sens * dt * 2.2)
	local sinS, cosS = math.sin(c.steer), math.cos(c.steer)
	local assist = settings.assist ~= false

	local n = #c.wheels
	local share = mass / n
	local k = share * SPRING
	local damp = share * DAMP * stats.springDamp
	local com = chassis.AssemblyCenterOfMass
	local grounded = 0
	local slip = 0
	local braking = false

	c.contacts = c.contacts or {}
	for i = 1, n do
		local lp = c.wheels[i]
		local origin = cf:PointToWorldSpace(Vector3.new(lp.X, 0, lp.Z))
		local hit = Workspace:Raycast(origin, -up * (c.ride + 1.3), rayParams)
		local contact = c.contacts[i] or {}
		c.contacts[i] = contact
		contact.ok = hit ~= nil
		contact.front = lp.Z < 0
		if hit then
			contact.pos, contact.normal = hit.Position, hit.Normal
			contact.lat = chassis:GetVelocityAtPosition(origin):Dot(lp.Z < 0 and (right * cosS - fwd * sinS) or right)
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
	-- (2026-11-17, owner: "take out the physics where you fall over in a corner". Bikes and cars stay on
	-- their wheels however hard they turn; only a real crash throws the rider off.)
	local torque = fwd * ((roll * kr - angVel:Dot(fwd) * cr) * mass)
	if grounded == 0 then
		torque -= right * (angVel:Dot(right) * mass * 0.6) -- calm the tumbling while airborne
	end
	local _ = pitchA
	torque -= up * (angVel:Dot(up) * mass * (grounded > 0 and 0.6 or 0.2)) -- yaw damping
	chassis:ApplyAngularImpulse(torque * dt)

	-- driving assist: the vehicle turns the way its front wheel points and slides less sideways,
	-- so steering feels direct instead of scrubbing speed (Settings > Driving assist turns it off)
	if assist and grounded > 0 and math.abs(speedF) > 1.5 then
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
		-- pedal while pushing on; slow turns when barely moving (stuck against a wall)
		local cadence = throttle > 0.05 and math.clamp(1.2 + math.abs(speedF) * 0.4, 1.2, 11) or 0
		c.crank = (c.crank + cadence * dt) % (math.pi * 2)
	end
	c.steerNow = steerIn

	-- sound and camera
	local rev = math.clamp(math.abs(speedF) / math.max(top, 1), 0, 1.1)
	if c.audio then
		c.audio:update(dt, { speed = speedF, throttle = throttle, braking = braking, hasPower = hasPower, top = top, grounded = grounded, signal = c.signal })
		Drive.info.gear = c.audio:gearNow()
	end
	if c.skid then
		local want = (slip > mass * 2 and speed > 12) and math.clamp(slip / (mass * 40), 0.15, 0.6) or 0
		c.skid.Volume += (want - c.skid.Volume) * math.min(1, dt * 10)
	end
	local cam = Workspace.CurrentCamera
	if cam and not State.cutscene then cam.FieldOfView += ((70 + rev * 12) - cam.FieldOfView) * math.min(1, dt * 3) end
	-- skid marks, tyre smoke, exhaust, speed streaks, headlight beams (client/DriveFx)
	if Drive.fx then
		local ok, err = pcall(Drive.fx, c, dt, { speed = speed, speedF = speedF, top = top, throttle = throttle, braking = braking,
			handbrake = handbrake, slip = slip, mass = mass, grounded = grounded, wet = wet, hasPower = hasPower, boost = boost })
		if not ok and not c.fxWarned then c.fxWarned = true; warn("[DriveFx] " .. tostring(err)) end
	end

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

-- The vehicle this client is driving (nil on foot). Rider reads the crank and steering from it.
function Drive.current()
	return cur
end

-- V switches between third person and first person (works on foot and on a vehicle).
function Drive.toggleView()
	local first = player.CameraMode == Enum.CameraMode.LockFirstPerson
	player.CameraMode = first and Enum.CameraMode.Classic or Enum.CameraMode.LockFirstPerson
	if first then
		-- Leaving first person keeps the zoom at 0.5, so the view did not change at all (owner, 2026-11-16:
		-- "cannot go back to third person"). A minimum zoom pushes the camera back out; then free it again.
		player.CameraMaxZoomDistance = 60
		player.CameraMinZoomDistance = 16
		task.delay(0.3, function()
			if player.CameraMode == Enum.CameraMode.Classic then player.CameraMinZoomDistance = 0.5 end
		end)
	end
	Feedback.toast(first and "Third-person view" or "First-person view (V to switch back)")
end

function Drive.start()
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
