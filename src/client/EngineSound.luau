-- Engine, road and small vehicle sounds for the vehicle the player is driving (owner, 2026-11-17:
-- "realistic vehicle sounds when accelerating, braking or easing off").
--
-- An engine model turns road speed and the pedals into revs and a gear:
--   * geared motorbikes and cars shift up and down by themselves: the revs climb in each gear and drop
--     at every change (a click on a bike, a short dip on a car's automatic)
--   * scooters run a CVT: the revs jump up when you open the throttle and hold while the speed builds
--   * the bicycle has pedals and a freewheel that ticks when you coast
-- Three copies of one licensed engine loop play together and are mixed from the revs and the throttle:
--   idle (only near idle revs), "on load" (throttle open: louder, brighter, a little grit on sport
--   engines) and "off load" (throttle shut: quieter and muffled while the revs fall with the speed =
--   engine braking). Wind or tyre roar grows with speed, the brakes squeal at the end of a hard stop,
--   the indicators tick, a car door shuts when you get in and out, the engine catches with a blip when
--   started and winds down when switched off. Horn: H (a bell on the bicycle).
-- Sounds are local to the driver (the client creates them), in the SFX sound group (Settings > Sound).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local IS_STUDIO = game:GetService("RunService"):IsStudio()
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Feedback = require(script.Parent.Feedback)

local EngineSound = {}
EngineSound.__index = EngineSound

-- idle / red = revs; gears = share of the vehicle's top speed reached at the red line in each gear
local PROFILES = {
	oldbike = { kind = "gears", sample = "bike", idle = 1400, red = 8500, gears = { 0.34, 0.56, 0.78, 1.04 }, pitch = 1.1, vol = 0.85 },
	underbone = { kind = "gears", sample = "bike", idle = 1500, red = 9000, gears = { 0.32, 0.54, 0.76, 1.04 }, pitch = 1.06, vol = 0.85 },
	scooter = { kind = "cvt", sample = "bike", idle = 1600, red = 8500, engage = 5000, cruise = 7600, pitch = 1.16, vol = 0.8 },
	sport = { kind = "gears", sample = "bike", idle = 1500, red = 11500, gears = { 0.26, 0.4, 0.54, 0.68, 0.84, 1.03 }, pitch = 0.98, vol = 1, grit = 0.22 },
	bigbike = { kind = "gears", sample = "bike", idle = 1100, red = 9000, gears = { 0.26, 0.4, 0.54, 0.68, 0.84, 1.03 }, pitch = 0.76, vol = 1, grit = 0.14 },
	hatch = { kind = "auto", sample = "car", idle = 850, red = 6200, gears = { 0.24, 0.42, 0.6, 0.8, 1.03 }, pitch = 1.05, vol = 0.85 },
	sedan = { kind = "auto", sample = "car", idle = 800, red = 6200, gears = { 0.24, 0.42, 0.6, 0.8, 1.03 }, pitch = 1, vol = 0.85 },
	pickup = { kind = "auto", sample = "car", idle = 750, red = 4300, gears = { 0.22, 0.4, 0.58, 0.78, 1.03 }, pitch = 0.82, vol = 0.95, grit = 0.12 },
	suv = { kind = "auto", sample = "car", idle = 750, red = 5500, gears = { 0.22, 0.4, 0.58, 0.78, 1.03 }, pitch = 0.88, vol = 0.9 },
	luxury = { kind = "auto", sample = "car", idle = 700, red = 6500, gears = { 0.2, 0.36, 0.52, 0.68, 0.84, 1.03 }, pitch = 0.92, vol = 0.7 },
	super = { kind = "auto", sample = "car", idle = 1000, red = 8500, gears = { 0.18, 0.3, 0.42, 0.55, 0.69, 0.85, 1.03 }, pitch = 1.08, vol = 1, grit = 0.28 },
	bicycle = { kind = "pedal" },
}
local SAMPLES = {
	bike = { id = Sounds.engineBike, region = Sounds.engineBikeRegion },
	car = { id = Sounds.engineCar, region = Sounds.engineCarRegion },
}

local function clamp01(x: number): number return math.clamp(x, 0, 1) end
local function smooth(a: number, b: number, x: number): number
	local k = clamp01((x - a) / (b - a))
	return k * k * (3 - 2 * k)
end

local function newSound(parent: Instance, id: string, looped: boolean, region: NumberRange?): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = looped
	s.Volume = 0
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 220
	s.SoundGroup = Feedback.sfxGroup
	if region then
		s.PlaybackRegionsEnabled = true
		s.LoopRegion = region
		s.PlaybackRegion = region
	end
	s.Parent = parent
	return s
end

local function eq(s: Sound, low: number, mid: number, high: number): EqualizerSoundEffect
	local e = Instance.new("EqualizerSoundEffect")
	e.LowGain, e.MidGain, e.HighGain = low, mid, high
	e.Parent = s
	return e
end

-- one-shot on the vehicle (3D), or on SoundService when no part is given
local function oneShot(parent: Instance?, id: string?, volume: number, speed: number?)
	if not id or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 200
	s.SoundGroup = Feedback.sfxGroup
	s.Parent = parent or game:GetService("SoundService")
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
	task.delay(8, function() if s.Parent then s:Destroy() end end)
end
EngineSound.oneShot = oneShot

function EngineSound.new(def, chassis: BasePart)
	local p = PROFILES[def.style] or (def.class == "car" and PROFILES.sedan) or PROFILES.oldbike
	if def.pedal then p = PROFILES.bicycle end
	local self = setmetatable({ def = def, p = p, chassis = chassis, rpm = 0, load = 0, gear = 1, shiftT = 0, shiftLock = 0,
		startT = 0, alive = true, tickT = 0, tickOn = false, brakeArmed = false, peak = 0, freeT = 0, pool = {}, poolI = 0 }, EngineSound)
	if p.kind == "pedal" then
		self.pedal = newSound(chassis, Sounds.bikePedal, true)
		self.pedal:Play()
		for i = 1, 4 do self.pool[i] = newSound(chassis, Sounds.tick, false) end
	else
		local smp = SAMPLES[p.sample]
		self.idle = newSound(chassis, smp.id, true, smp.region)
		self.on = newSound(chassis, smp.id, true, smp.region)
		self.off = newSound(chassis, smp.id, true, smp.region)
		self.idleEq = eq(self.idle, 3, -2, -10)
		self.onEq = eq(self.on, 2, 0, -4)
		self.offEq = eq(self.off, 1, -6, -16)
		-- the exhaust the owner fitted (Styling app): 2 racing pipe = louder, deeper, rough; 3 quiet
		local ex = chassis.Parent and chassis.Parent:GetAttribute("Exhaust") or 1
		if ex == 2 then
			local q = table.clone(p)
			q.vol = (p.vol or 0.9) * 1.3
			q.pitch = p.pitch * 0.9
			q.grit = math.max(p.grit or 0, 0.3)
			p = q
			self.p = q
		elseif ex == 3 then
			local q = table.clone(p)
			q.vol = (p.vol or 0.9) * 0.6
			q.grit = nil
			p = q
			self.p = q
		end
		if p.grit then
			local d = Instance.new("DistortionSoundEffect")
			d.Level = 0
			d.Parent = self.on
			self.grit = d
		end
		-- start the three copies at different points of the loop so they don't phase against each other
		for i, s in ipairs({ self.idle, self.on, self.off }) do
			s:Play()
			local len = smp.region and (smp.region.Max - smp.region.Min) or 20
			s.TimePosition = (smp.region and smp.region.Min or 0) + len * (i - 1) / 3
		end
		self.startT = 1.0
		if def.class == "car" then oneShot(chassis, Sounds.carDoor, 0.55, 1) end
	end
	self.road = newSound(chassis, def.class == "car" and Sounds.roadCar or Sounds.wind, true)
	self.road:Play()
	return self
end

-- revs in gear g at speed v (studs/s)
function EngineSound:rpmIn(g: number, v: number, top: number): number
	local p = self.p
	return p.red * v / math.max(top * p.gears[g], 1)
end

-- s = { speed (forward, signed), throttle (-1..1), braking, hasPower, top, grounded, signal }
function EngineSound:update(dt: number, s)
	if not self.alive then return end
	local p = self.p
	local v = math.abs(s.speed)
	local top = math.max(s.top, 1)

	-- tick-tock while an indicator or the hazards are on
	if s.signal and s.signal ~= 0 then
		self.tickT -= dt
		if self.tickT <= 0 then
			self.tickT = 0.38
			self.tickOn = not self.tickOn
			oneShot(nil, Sounds.tick, 0.16, self.tickOn and 1.95 or 1.6)
		end
	else
		self.tickT = 0
	end

	-- wind (bikes) / tyre roar (cars)
	local frac = clamp01(v / top)
	self.road.Volume = (frac ^ 1.6) * (self.def.class == "car" and 0.3 or 0.42) * (s.grounded > 0 and 1 or 0.6)
	self.road.PlaybackSpeed = 0.8 + 0.45 * frac

	-- brakes: a squeal at the end of a hard stop
	if s.braking and v > 15 then self.brakeArmed = true end
	if not s.braking then self.brakeArmed = self.brakeArmed and v > 3 end
	if self.brakeArmed and s.braking and v < 9 and v > 1 then
		self.brakeArmed = false
		local car = self.def.class == "car"
		oneShot(self.chassis, Sounds.brakeSqueal, car and 0.2 or 0.32, (p.kind == "pedal" and 1.15) or (car and 0.72 or 0.95))
	end

	if p.kind == "pedal" then
		-- pedalling: chain and pedals; coasting: the freewheel ticks
		local pedalling = s.throttle > 0.05 and v > 0.8
		local want = pedalling and (0.12 + 0.3 * frac) or 0
		self.pedal.Volume += (want - self.pedal.Volume) * math.min(1, dt * 6)
		self.pedal.PlaybackSpeed = 0.8 + 0.5 * frac
		if not pedalling and v > 2 then
			self.freeT -= dt
			if self.freeT <= 0 then
				self.freeT = 1 / math.clamp(v * 0.9, 4, 12)
				self.poolI = self.poolI % #self.pool + 1
				local t = self.pool[self.poolI]
				t.Volume = 0.05
				t.PlaybackSpeed = 2.7
				t.TimePosition = 0
				t:Play()
			end
		end
		return
	end

	-- the engine comes back after a stall: it catches with a blip again
	if s.hasPower and self.hadPower == false then self.startT = 1.0 end
	self.hadPower = s.hasPower
	-- the throttle the engine sees
	local thr = 0
	if s.hasPower then
		if s.throttle > 0 and s.speed > -1.5 then thr = s.throttle
		elseif s.throttle < 0 and s.speed < 1.5 then thr = -s.throttle * 0.7 end -- reversing
	end
	self.load += (thr - self.load) * math.min(1, dt * (thr > self.load and 9 or 5))

	-- revs
	local rpmT
	if p.kind == "cvt" then
		if thr > 0.05 then
			rpmT = (p.engage + (p.cruise - p.engage) * frac) * (0.85 + 0.15 * thr)
		else
			rpmT = p.idle + frac * (p.engage - p.idle) * 0.75
		end
	else
		self.shiftLock -= dt
		local g = self.gear
		local rpm = self:rpmIn(g, v, top)
		local upAt = p.red * (0.6 + 0.32 * self.load)
		local downAt = math.max(p.idle * 1.5, p.red * (0.28 + 0.12 * self.load))
		if self.shiftLock <= 0 and s.speed > -1 then
			if rpm > upAt and g < #p.gears then
				self.gear = g + 1
				self.shiftLock = 0.45
				self.shiftT = p.kind == "gears" and 0.16 or 0.24
				if p.kind == "gears" then oneShot(self.chassis, Sounds.tick, 0.22, 0.42) end -- the gear lever
			elseif rpm < downAt and g > 1 then
				self.gear = g - 1
				self.shiftLock = 0.45
				if p.kind == "gears" and self.load < 0.2 then oneShot(self.chassis, Sounds.tick, 0.16, 0.38) end
			end
		end
		if s.speed < -1 then self.gear = 1 end
		rpmT = self:rpmIn(self.gear, v, top)
		if self.gear == 1 then
			-- the clutch slips while pulling away
			rpmT = math.max(rpmT, p.idle + thr * (p.red * 0.42 - p.idle))
		end
		if s.speed < -1 then rpmT = math.min(rpmT, p.red * 0.5) end -- reversing: low revs
	end
	if not s.hasPower then rpmT = 0 end
	rpmT = math.max(rpmT, s.hasPower and p.idle or 0)
	rpmT = math.min(rpmT, p.red * 1.02)
	-- a fresh start: the engine catches with a blip, then settles to idle
	if self.startT > 0 then
		self.startT -= dt
		local k = 1 - math.max(self.startT, 0) / 1.0
		rpmT = math.max(rpmT, p.idle * (0.35 + 1.25 * math.sin(math.pi * math.min(k * 1.3, 1)) + 0.65 * k))
	end
	local rate = rpmT > self.rpm and (self.shiftT > 0 and 30 or 8) or (self.shiftT > 0 and 30 or 4)
	self.rpm += (rpmT - self.rpm) * math.min(1, dt * rate)

	-- mix
	local dip = 1
	if self.shiftT > 0 then
		self.shiftT -= dt
		dip = 0.45
	end
	local r = clamp01((self.rpm - p.idle) / (p.red - p.idle))
	local alive = s.hasPower and 1 or clamp01(self.rpm / math.max(p.idle, 1))
	local load = self.load * dip
	local master = (p.vol or 0.9) * alive
	local idleV = (1 - smooth(0.02, 0.3, r)) * 0.3 * master
	local onV = (0.16 + 0.6 * r) * load * master
	local offV = (0.1 + 0.3 * r) * (1 - load) * master
	self.idle.Volume += (idleV - self.idle.Volume) * math.min(1, dt * 10)
	self.on.Volume += (onV - self.on.Volume) * math.min(1, dt * 14)
	self.off.Volume += (offV - self.off.Volume) * math.min(1, dt * 10)
	-- pitch: a perceptual curve from idle to the red line
	local pitch = p.pitch * (0.55 + 1.2 * (r ^ 0.85))
	if self.rpm < p.idle then pitch = p.pitch * 0.55 * math.max(self.rpm / p.idle, 0.4) end
	self.on.PlaybackSpeed = pitch
	self.off.PlaybackSpeed = pitch * 0.985
	self.idle.PlaybackSpeed = p.pitch * 0.55 * math.clamp(self.rpm / p.idle, 0.4, 1.4)
	-- tone: brighter and grittier under load
	self.onEq.HighGain = -6 + 9 * self.load
	self.onEq.LowGain = 2 + 2 * self.load
	if self.grit then self.grit.Level = p.grit * self.load * (0.4 + 0.6 * r) end
	if IS_STUDIO then -- readout for muted play tests
		self.chassis:SetAttribute("QaRpm", math.floor(self.rpm))
		self.chassis:SetAttribute("QaGear", self.gear)
		self.chassis:SetAttribute("QaLoad", math.floor(self.load * 100) / 100)
	end
end

-- the gear the engine is in (nil for a CVT or the bicycle)
function EngineSound:gearNow(): number?
	if self.p.kind == "gears" or self.p.kind == "auto" then return self.gear end
	return nil
end

function EngineSound:horn()
	local now = os.clock()
	if now - (self.hornAt or 0) < 0.35 then return end
	self.hornAt = now
	-- the horn the owner fitted (Styling app): 2 deep, 3 air horn, 4 beep-beep, 5 bell
	local style = self.chassis.Parent and self.chassis.Parent:GetAttribute("Horn") or 1
	local base = self.def.class == "car" and (self.p.pitch >= 1 and 1.05 or 0.92) or 1.38
	if style == 5 or self.p.kind == "pedal" then
		oneShot(self.chassis, Sounds.bell, 0.45, 1)
	elseif style == 2 then
		oneShot(self.chassis, Sounds.horn, 0.65, base * 0.72)
	elseif style == 3 then
		oneShot(self.chassis, Sounds.horn, 0.7, 0.82)
		task.delay(0.22, function() oneShot(self.chassis, Sounds.horn, 0.7, 0.78) end)
	elseif style == 4 then
		oneShot(self.chassis, Sounds.horn, 0.45, 1.6)
		task.delay(0.16, function() oneShot(self.chassis, Sounds.horn, 0.45, 1.6) end)
	elseif self.def.class == "car" then
		oneShot(self.chassis, Sounds.horn, 0.6, self.p.pitch >= 1 and 1.05 or 0.92)
	else
		oneShot(self.chassis, Sounds.horn, 0.5, 1.38) -- a small bike's horn is higher
	end
end

-- getting off: the engine winds down, a car door shuts, everything is removed
function EngineSound:stop()
	if not self.alive then return end
	self.alive = false
	local list = { self.idle, self.on, self.off, self.road, self.pedal }
	if self.def.class == "car" then oneShot(self.chassis, Sounds.carDoor, 0.55, 0.95) end
	task.spawn(function()
		local t = 0
		while t < 0.7 do
			local dt = task.wait()
			t += dt
			for _, s in ipairs(list) do
				if s and s.Parent then
					s.Volume *= 0.88
					s.PlaybackSpeed = math.max(0.3, s.PlaybackSpeed * 0.97)
				end
			end
		end
		for _, s in ipairs(list) do if s then s:Destroy() end end
		for _, s in ipairs(self.pool) do s:Destroy() end
	end)
end

return EngineSound
