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
-- (2026-11-20) toy-brick look: a clear, bright Roblox day (default sky, light air, no film grade or far blur)
local BRICKS = require(Shared.Config.Look).BRICKS == true
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

local atmosphere, bloom, cc, rays, clouds, dof
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
	-- dark window glass would glow dark: at night a lit window is warm lamp light (signs keep their colours)
	local dc = part:GetAttribute("DayColor")
	if dc == nil then
		local c = part.Color
		if math.max(c.R, c.G, c.B) < 0.4 then
			dc = c
			part:SetAttribute("DayColor", c)
		else
			part:SetAttribute("DayColor", false)
		end
	end
	if typeof(dc) == "Color3" then
		if night then
			local k = 0.34 + ((part.Position.X * 7.3 + part.Position.Z * 3.1) % 1) * 0.18 -- not every room is equally bright
			part.Color = Color3.fromRGB(255 * k, 196 * k, 120 * k) -- warm lamp light, not a white glare
		else
			part.Color = dc
		end
	end
end
local function applyLight(part: Instance)
	for _, l in ipairs(part:GetChildren()) do
		if l:IsA("Light") then l.Enabled = night end
	end
	-- A lamp that streams in arrives before its light does, so the light is not there yet when the
	-- tag is seen (until 2026-11-16 every district that loaded after dark stayed unlit). Catch it
	-- when it arrives.
	if not part:GetAttribute("LightHook") then
		part:SetAttribute("LightHook", true)
		part.ChildAdded:Connect(function(l)
			if l:IsA("Light") then l.Enabled = night end
		end)
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
	dof = post("DepthOfFieldEffect", "GoDashFocus")
	-- 2026-11-16 realism pass: a hot, humid Isan city. Hard midday shadows, warm haze that eats the
	-- distance, colours a little less candy than Roblox defaults, highlights (sun glints, neon signs
	-- at night) blooming only above HDR white, and a soft far blur like a phone camera.
	-- 2026-11-16 (owner: "make the tone cozy, it is too bright, unreal and hard on the eyes"): the
	-- look is now a soft, warm afternoon all day. The sun is weaker and the shadows are filled with
	-- warm skylight, so nothing is glaring white or pitch black; colours are a little muted and
	-- creamy; contrast is low; bloom only touches real lights.
	-- 2026-11-17 (owner: "the colours look too gloomy, I want it brighter and more cheerful"): clear
	-- air instead of the brown haze, fresher and more saturated colours, a touch more exposure and
	-- brighter shadows. Still no glare: bloom only on real lights, no blown-out whites, nights stay
	-- lamp-lit and readable.
	bloom.Intensity = 0.25; bloom.Size = 24; bloom.Threshold = 2.0
	rays.Intensity = 0.03; rays.Spread = 0.55
	dof.NearIntensity = 0; dof.FarIntensity = 0.08; dof.FocusDistance = 40; dof.InFocusRadius = 200
	atmosphere.Offset = 0.12
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.85
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GeographicLatitude = 16.4 -- Khon Kaen
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Name = "GoDashSky"
		sky.Parent = Lighting
	end
	-- a clear humid-sky gradient (our own image, assets/textures/sky_*.png); the clouds in front of it
	-- are Roblox's live Terrain clouds, so there are no painted cartoon clouds any more
	local SIDE, UP, DOWN = "rbxassetid://102196248176522", "rbxassetid://122010862183021", "rbxassetid://112916264686066"
	if BRICKS then -- Roblox's own default sky
		SIDE, UP, DOWN = "rbxassetid://6444884337", "rbxassetid://6412503613", "rbxassetid://6444884785"
		Lighting.EnvironmentDiffuseScale = 1
		Lighting.EnvironmentSpecularScale = 1
		bloom.Intensity = 0.6; bloom.Size = 24; bloom.Threshold = 2
		dof.FarIntensity = 0
	end
	sky.SkyboxBk, sky.SkyboxFt, sky.SkyboxLf, sky.SkyboxRt = SIDE, SIDE, SIDE, SIDE
	sky.SkyboxUp, sky.SkyboxDn = UP, DOWN
	sky.SunAngularSize = BRICKS and 21 or 12
	sky.MoonAngularSize = 9
	sky.StarCount = 2200
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
	local flash = 0 -- lightning: added to the grade for a few frames
	local nextThunder = os.clock() + 10
	RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		if cam then rainPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 42, 0) + cam.CFrame.LookVector * Vector3.new(20, 0, 20)) end
		local ct = Lighting.ClockTime
		local weather = Workspace:GetAttribute("Weather") or "Sunny"
		local rainT = Workspace:GetAttribute("Rain") or 0
		rainNow += (rainT - rainNow) * math.min(1, dt * 0.5)
		local cloudT = weather == "Sunny" and 0.4 or (weather == "Cloudy" and 0.74 or 0.92)
		cloudNow += (cloudT - cloudNow) * math.min(1, dt * 0.25)

		-- day curve: 0 at night, 1 in full daylight; golden near sunrise and sunset
		local dayK = smooth(ct, 5.6, 7.4) * (1 - smooth(ct, 17.4, 19.2))
		local golden = math.max(smooth(ct, 5.4, 6.4) * (1 - smooth(ct, 7.2, 8.6)), smooth(ct, 15.8, 17.4) * (1 - smooth(ct, 18.6, 19.4)))
		local gloom = math.clamp(rainNow * 0.9 + (cloudNow - 0.45) * 0.6, 0, 1)

		-- sunlight: strong and slightly warm at midday, orange at the ends of the day; skylight fills
		-- the shadows neutral-to-cool (not blue), streets at night lit mostly by lamps and signs
		Lighting.Brightness = lerp(1.1, 2.5, dayK) * (1 - gloom * 0.35)
		-- (night ambient kept high enough that the road stays readable between street lamps)
		-- (owner, 2026-11-16: "and never so dark that it looks scary": shadows and nights stay readable)
		Lighting.Ambient = lerpC(Color3.fromRGB(112, 110, 130), Color3.fromRGB(150, 146, 140), dayK)
		Lighting.OutdoorAmbient = lerpC(Color3.fromRGB(122, 122, 146), lerpC(Color3.fromRGB(160, 162, 166), Color3.fromRGB(140, 142, 146), gloom), dayK)
		Lighting.ColorShift_Top = lerpC(lerpC(Color3.fromRGB(44, 50, 78), Color3.fromRGB(255, 240, 214), dayK), Color3.fromRGB(255, 176, 104), golden * (1 - gloom))
		Lighting.ColorShift_Bottom = lerpC(Color3.fromRGB(0, 0, 0), Color3.fromRGB(56, 54, 50), dayK) -- light bounce off sunlit concrete
		Lighting.ExposureCompensation = lerp(0.25, 0.06, dayK) + gloom * 0.15
		Lighting.ShadowSoftness = 0.35 + gloom * 0.4
		cc.TintColor = lerpC(lerpC(Color3.fromRGB(236, 238, 255), Color3.fromRGB(255, 249, 238), dayK), Color3.fromRGB(255, 226, 192), golden * (1 - gloom))
		cc.Saturation = lerp(0.14, -0.1, gloom) + golden * 0.05 - (1 - dayK) * 0.1 -- fresh by day, colours rest at night
		cc.Contrast = 0.06 + golden * 0.03 - gloom * 0.04
		cc.Brightness = 0.02 * dayK + flash
		-- air: clear and a little blue by day, amber at sunset, blue at night, grey in the rain
		atmosphere.Density = lerp(0.22, 0.46, gloom) + (1 - dayK) * 0.05
		atmosphere.Haze = lerp(0.9, 2.8, gloom) + golden * 0.8
		atmosphere.Color = lerpC(lerpC(lerpC(Color3.fromRGB(70, 80, 110), Color3.fromRGB(200, 218, 236), dayK), Color3.fromRGB(255, 200, 150), golden), Color3.fromRGB(160, 166, 174), gloom)
		atmosphere.Decay = lerpC(lerpC(Color3.fromRGB(46, 52, 80), Color3.fromRGB(156, 178, 204), dayK), Color3.fromRGB(104, 110, 120), gloom)
		atmosphere.Glare = (0.02 + golden * 0.14) * (1 - gloom)
		dof.FarIntensity = lerp(0.08, 0.18, gloom)
		if BRICKS then
			-- a bright toy-box day: neutral white sun, grey-white fill, crisp shadows, clean colours, light air;
			-- sunsets still go orange, rain still goes grey, nights stay lamp-lit and readable
			Lighting.Brightness = lerp(1.2, 2.4, dayK) * (1 - gloom * 0.3)
			Lighting.Ambient = lerpC(Color3.fromRGB(112, 110, 130), Color3.fromRGB(90, 90, 92), dayK)
			Lighting.OutdoorAmbient = lerpC(Color3.fromRGB(122, 122, 146), Color3.fromRGB(118, 120, 126), dayK)
			Lighting.ColorShift_Top = lerpC(lerpC(Color3.fromRGB(44, 50, 78), Color3.new(0, 0, 0), dayK), Color3.fromRGB(255, 170, 96), golden * (1 - gloom))
			Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
			Lighting.ExposureCompensation = lerp(0.25, -0.08, dayK) + gloom * 0.15
			Lighting.ShadowSoftness = 0.2 + gloom * 0.4
			cc.TintColor = lerpC(lerpC(Color3.fromRGB(236, 238, 255), Color3.new(1, 1, 1), dayK), Color3.fromRGB(255, 232, 205), golden * (1 - gloom))
			cc.Saturation = lerp(0.2, -0.05, gloom) - (1 - dayK) * 0.08
			cc.Contrast = 0.08
			atmosphere.Density = lerp(0.24, 0.45, gloom)
			atmosphere.Offset = 0.1
			atmosphere.Haze = lerp(0, 2.4, gloom) + golden * 0.5
			atmosphere.Color = lerpC(lerpC(lerpC(Color3.fromRGB(70, 80, 110), Color3.fromRGB(178, 204, 232), dayK), Color3.fromRGB(255, 200, 150), golden), Color3.fromRGB(160, 166, 174), gloom)
			atmosphere.Decay = lerpC(lerpC(Color3.fromRGB(46, 52, 80), Color3.fromRGB(100, 128, 170), dayK), Color3.fromRGB(104, 110, 120), gloom)
			atmosphere.Glare = 0
			dof.FarIntensity = 0
		end
		-- (2026-11-19) clip mode (client/ClipMode sets State.clipFocus = studs to the rider): a film-camera focus,
		-- the rider sharp and the street behind softly out of focus
		local focus = State.clipFocus
		if type(focus) == "number" then
			dof.FocusDistance = focus
			dof.InFocusRadius = math.max(8, focus * 0.55)
			dof.FarIntensity = 0.3
			dof.NearIntensity = 0.1
		else
			dof.FocusDistance = 40
			dof.InFocusRadius = 200
			dof.NearIntensity = 0
		end
		if clouds then
			clouds.Cover = cloudNow
			clouds.Density = lerp(0.4, 0.9, gloom)
			clouds.Color = lerpC(lerpC(Color3.fromRGB(100, 106, 132), Color3.fromRGB(255, 255, 255), dayK), Color3.fromRGB(128, 134, 144), gloom)
		end
		rays.Intensity = 0.03 * (1 - gloom) + golden * 0.14 -- (a little more of the low sun's rays: nice to watch, still no glare)
		bloom.Intensity = lerp(0.35, 0.25, dayK) -- signs and lamps glow a little more at night

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
				flash = 0.45
				task.wait(0.08)
				flash = 0
				task.wait(0.1)
				flash = 0.25
				task.wait(0.06)
				flash = 0
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
