-- Look and atmosphere on the client: lighting through the day, rain and storms, lights that come
-- on at night, wet roads, ambient sound, and hiding your own roof while you are indoors.
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)

local Env = {}
Env.forceRoofHidden = false -- Build mode sets this
local player = Players.LocalPlayer

local function lerp(a: number, b: number, t: number): number return a + (b - a) * t end
local function lerpC(a: Color3, b: Color3, t: number): Color3 return a:Lerp(b, math.clamp(t, 0, 1)) end
local function smooth(x: number, a: number, b: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local atmosphere, bloom, cc, rays, clouds
local rainPart, rainEmitter, rainSound
local ambient = {}
local night = false

local function post(class: string, name: string): any
	local e = Lighting:FindFirstChild(name)
	if not e then
		e = Instance.new(class)
		e.Name = name
		e.Parent = Lighting
	end
	return e
end

local function loop(name: string, id: string): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	s.SoundGroup = Feedback.sfxGroup
	s.Parent = SoundService
	if id ~= "" then s:Play() end
	return s
end

---------------------------------------------------------------------------------------------------
-- night lights (tags set by the server builders; instances stream in and out)
---------------------------------------------------------------------------------------------------
local function applyGlow(part: Instance)
	if not part:IsA("BasePart") then return end
	local day = part:GetAttribute("DayMaterial")
	if not day then
		day = part.Material.Name
		part:SetAttribute("DayMaterial", day)
	end
	part.Material = night and Enum.Material.Neon or (Enum.Material :: any)[day] or Enum.Material.SmoothPlastic
end
local function applyLight(part: Instance)
	for _, l in ipairs(part:GetChildren()) do
		if l:IsA("Light") then l.Enabled = night end
	end
end
local function setNight(v: boolean)
	night = v
	task.spawn(function()
		for i, p in ipairs(CollectionService:GetTagged("NightGlow")) do
			-- not every window lights up at the same moment
			applyGlow(p)
			if i % 400 == 0 then task.wait() end
		end
		for i, p in ipairs(CollectionService:GetTagged("NightLight")) do
			applyLight(p)
			if i % 400 == 0 then task.wait() end
		end
	end)
end

local function setWet(w: number)
	for i, p in ipairs(CollectionService:GetTagged("Road")) do
		if p:IsA("BasePart") then p.Reflectance = w * 0.2 end
	end
end

---------------------------------------------------------------------------------------------------
function Env.start()
	atmosphere = post("Atmosphere", "GoDashAtmosphere")
	bloom = post("BloomEffect", "GoDashBloom")
	cc = post("ColorCorrectionEffect", "GoDashColor")
	rays = post("SunRaysEffect", "GoDashRays")
	bloom.Intensity = 0.35; bloom.Size = 22; bloom.Threshold = 1.1
	rays.Intensity = 0.06; rays.Spread = 0.6
	atmosphere.Offset = 0.1
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.7
	Lighting.GeographicLatitude = 16.4 -- Khon Kaen
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		clouds.Parent = terrain
	end

	rainPart = Instance.new("Part")
	rainPart.Name = "RainEmitter"
	rainPart.Anchored = true; rainPart.CanCollide = false; rainPart.CanQuery = false; rainPart.CanTouch = false
	rainPart.Transparency = 1
	rainPart.Size = Vector3.new(110, 1, 110)
	rainPart.Parent = Workspace
	rainEmitter = Instance.new("ParticleEmitter")
	rainEmitter.EmissionDirection = Enum.NormalId.Bottom
	rainEmitter.Speed = NumberRange.new(110, 130)
	rainEmitter.Lifetime = NumberRange.new(0.5, 0.6)
	rainEmitter.Size = NumberSequence.new(0.22)
	rainEmitter.Squash = NumberSequence.new(-2.6)
	rainEmitter.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	rainEmitter.Color = ColorSequence.new(Color3.fromRGB(200, 215, 230))
	rainEmitter.Transparency = NumberSequence.new(0.45)
	rainEmitter.LightEmission = 0.15
	rainEmitter.LightInfluence = 0.8
	rainEmitter.Rate = 0
	rainEmitter.Acceleration = Vector3.new(6, 0, 3)
	rainEmitter.Parent = rainPart

	rainSound = loop("Rain", Sounds.rain)
	ambient.birds = loop("Birds", Sounds.birdsCity)
	ambient.traffic = loop("Traffic", Sounds.traffic)
	ambient.night = loop("NightCity", Sounds.trafficNight)

	for _, tag in ipairs({ "NightGlow", "NightLight" }) do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(p)
			if tag == "NightGlow" then applyGlow(p) else applyLight(p) end
		end)
	end
	CollectionService:GetInstanceAddedSignal("Road"):Connect(function(p)
		if p:IsA("BasePart") then p.Reflectance = (Workspace:GetAttribute("Wet") or 0) * 0.2 end
	end)
	setNight(Workspace:GetAttribute("IsNight") == true)
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(function() setNight(Workspace:GetAttribute("IsNight") == true) end)
	Workspace:GetAttributeChangedSignal("Wet"):Connect(function() setWet(Workspace:GetAttribute("Wet") or 0) end)

	local rainNow, cloudNow = 0, 0.45
	local nextThunder = os.clock() + 10
	RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		if cam then rainPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 42, 0) + cam.CFrame.LookVector * Vector3.new(20, 0, 20)) end
		local ct = Lighting.ClockTime
		local weather = Workspace:GetAttribute("Weather") or "Sunny"
		local rainT = Workspace:GetAttribute("Rain") or 0
		rainNow += (rainT - rainNow) * math.min(1, dt * 0.5)
		local cloudT = weather == "Sunny" and 0.45 or (weather == "Cloudy" and 0.74 or 0.92)
		cloudNow += (cloudT - cloudNow) * math.min(1, dt * 0.25)

		-- day curve: 0 at night, 1 in full daylight; golden near sunrise and sunset
		local dayK = smooth(ct, 5.6, 7.4) * (1 - smooth(ct, 17.4, 19.2))
		local golden = math.max(smooth(ct, 5.4, 6.4) * (1 - smooth(ct, 7.2, 8.6)), smooth(ct, 15.8, 17.4) * (1 - smooth(ct, 18.6, 19.4)))
		local gloom = math.clamp(rainNow * 0.9 + (cloudNow - 0.45) * 0.6, 0, 1)

		Lighting.Brightness = lerp(0.9, 2.9, dayK) * (1 - gloom * 0.45)
		Lighting.Ambient = lerpC(Color3.fromRGB(46, 52, 74), Color3.fromRGB(128, 128, 132), dayK)
		Lighting.OutdoorAmbient = lerpC(Color3.fromRGB(40, 46, 72), lerpC(Color3.fromRGB(132, 136, 142), Color3.fromRGB(120, 124, 130), gloom), dayK)
		Lighting.ColorShift_Top = lerpC(Color3.fromRGB(0, 0, 0), Color3.fromRGB(255, 170, 90), golden * (1 - gloom))
		Lighting.ExposureCompensation = lerp(0.25, 0.05, dayK)
		Lighting.ShadowSoftness = 0.25 + gloom * 0.5
		cc.TintColor = lerpC(lerpC(Color3.fromRGB(190, 205, 255), Color3.fromRGB(255, 255, 255), dayK), Color3.fromRGB(255, 226, 190), golden * (1 - gloom))
		cc.Saturation = lerp(0.12, -0.22, gloom) + golden * 0.08
		cc.Contrast = 0.06 + golden * 0.05
		atmosphere.Density = lerp(0.26, 0.5, gloom)
		atmosphere.Haze = lerp(1.2, 3.2, gloom) + golden * 0.8
		atmosphere.Color = lerpC(lerpC(Color3.fromRGB(190, 205, 225), Color3.fromRGB(255, 205, 160), golden), Color3.fromRGB(150, 156, 166), gloom)
		atmosphere.Decay = lerpC(Color3.fromRGB(106, 120, 150), Color3.fromRGB(90, 96, 106), gloom)
		atmosphere.Glare = golden * 0.6
		if clouds then
			clouds.Cover = cloudNow
			clouds.Density = lerp(0.45, 0.9, gloom)
			clouds.Color = lerpC(lerpC(Color3.fromRGB(90, 96, 120), Color3.fromRGB(255, 255, 255), dayK), Color3.fromRGB(120, 126, 136), gloom)
		end
		rays.Intensity = 0.07 * (1 - gloom) + golden * 0.1

		rainEmitter.Rate = rainNow * 1400
		local sfx = not (State.data and State.data.settings and State.data.settings.sfx == false)
		local amb = not (State.data and State.data.settings and State.data.settings.music == false)
		rainSound.Volume = sfx and rainNow * 0.55 or 0
		local dayVol = amb and dayK * (1 - rainNow) or 0
		ambient.birds.Volume += ((dayVol * 0.22) - ambient.birds.Volume) * math.min(1, dt)
		ambient.traffic.Volume += ((amb and dayK * 0.1 or 0) - ambient.traffic.Volume) * math.min(1, dt)
		ambient.night.Volume += ((amb and (1 - dayK) * 0.12 or 0) - ambient.night.Volume) * math.min(1, dt)

		if weather == "Storm" and os.clock() > nextThunder then
			nextThunder = os.clock() + math.random(7, 18)
			task.spawn(function()
				local base = cc.Brightness
				cc.Brightness = 0.45
				task.wait(0.08)
				cc.Brightness = base
				task.wait(0.1)
				cc.Brightness = 0.25
				task.wait(0.06)
				cc.Brightness = base
				task.wait(math.random(4, 14) / 10)
				Feedback.play("boom", 0.7, 0.45 + math.random() * 0.15, 2)
			end)
		end
	end)

	-- your own roof disappears while you are inside (or building), so the camera can see in
	task.spawn(function()
		local hidden = false
		while true do
			task.wait(0.3)
			local want = Env.forceRoofHidden
			local plot = State.plot
			local char = player.Character
			local r = char and char:FindFirstChild("HumanoidRootPart")
			if plot and r and not want then
				local lp = plot.base:PointToObjectSpace(r.Position)
				want = math.abs(lp.X) < plot.house.hx + 2 and math.abs(lp.Z - plot.house.cz) < plot.house.hz + 2
			end
			if want ~= hidden or want then
				hidden = want
				for _, p in ipairs(CollectionService:GetTagged("HouseRoof")) do
					if p:IsA("BasePart") then
						local mine = plot and p:FindFirstAncestor(plot.id) ~= nil
						p.LocalTransparencyModifier = (want and mine) and 1 or 0
					end
				end
			end
		end
	end)
end

return Env
