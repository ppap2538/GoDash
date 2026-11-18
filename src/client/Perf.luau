-- Keeps the game smooth on slow devices.
--
-- Perf.scale (0.3 .. 1) is how much of their full count the crowd systems show (pedestrians, local
-- traffic): it goes down in steps when the frame rate stays low and creeps back up with headroom.
--
-- Perf.tier (2026-11-18, the whole tambon is the map now) is the detail level for everything else:
--   3 = high   (computers)          far city backdrop to 2,600 studs, all crowds
--   2 = medium (phones, tablets)    backdrop to 1,700, fewer route cars drawn far away
--   1 = low    (struggling devices) backdrop to 1,000, crowds and effects trimmed
-- The player can pin it in Phone > Settings > Graphics (settings.quality = "auto" | "low" | "medium" |
-- "high"); on "auto" a phone starts at medium and any device steps down a tier after ~10 s under
-- 24 fps, and back up after ~30 s above 50 fps. Smoothness first, but it never drops below low.
-- Studio test hooks: workspace attribute QaPerf = number pins the scale, QaTier = 1/2/3 pins the tier.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Perf = {}
Perf.scale = 1 -- 1 = everything, 0.3 = the bare minimum
Perf.fps = 60
Perf.touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
Perf.tier = Perf.touch and 2 or 3
Perf.auto = true
Perf.changed = Instance.new("BindableEvent") -- fires (tier) when the tier changes

local LOW, HIGH = 27, 48 -- crowd scale: shed below LOW fps, restore above HIGH
local MIN = 0.3
local TIER_DOWN, TIER_UP = 24, 50
local NAMES = { "low", "medium", "high" }

-- What each tier allows (read by Backdrop, Street, Peds, Dogs, DriveFx, Ambience).
-- routeCars = how far away a server route car is still drawn (beyond the streaming radius of 700 its
-- road is not there, so a car farther out would float on nothing)
Perf.LIMITS = {
	{ backdrop = 1000, routeCars = 560, peds = 0.55, locals = 0.6, effects = 0.4 },
	{ backdrop = 1700, routeCars = 720, peds = 0.8, locals = 0.85, effects = 0.7 },
	{ backdrop = 2300, routeCars = 860, peds = 1, locals = 1, effects = 1 },
}

function Perf.limit(key: string): number
	return Perf.LIMITS[Perf.tier][key]
end

function Perf.name(): string
	return NAMES[Perf.tier]
end

local function setTier(t: number)
	t = math.clamp(t, 1, 3)
	if t == Perf.tier then return end
	Perf.tier = t
	Perf.changed:Fire(t)
end

-- settings.quality from the profile (Phone > Settings), or "auto"
function Perf.setQuality(q: string?)
	if q == "low" then Perf.auto = false; setTier(1)
	elseif q == "medium" then Perf.auto = false; setTier(2)
	elseif q == "high" then Perf.auto = false; setTier(3)
	else
		if not Perf.auto then setTier(Perf.touch and 2 or 3) end
		Perf.auto = true
	end
end

function Perf.start()
	local frames, elapsed = 0, 0
	local lowFor, highFor = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		frames += 1
		elapsed += dt
		if elapsed < 2.5 then return end
		Perf.fps = frames / elapsed
		local span = elapsed
		frames, elapsed = 0, 0
		local studio = RunService:IsStudio()
		local forced = studio and Workspace:GetAttribute("QaPerf") or nil
		if type(forced) == "number" then
			Perf.scale = math.clamp(forced, MIN, 1)
		elseif Perf.fps < LOW then
			Perf.scale = math.max(MIN, Perf.scale - 0.15)
		elseif Perf.fps > HIGH then
			Perf.scale = math.min(1, Perf.scale + 0.05)
		end
		local qt = studio and Workspace:GetAttribute("QaTier") or nil
		if type(qt) == "number" then
			setTier(math.floor(qt))
			return
		end
		if not Perf.auto then return end
		-- the tier moves slowly: a loading hitch or one busy junction must not change it
		if Perf.fps < TIER_DOWN then lowFor += span else lowFor = 0 end
		if Perf.fps > TIER_UP then highFor += span else highFor = 0 end
		if lowFor >= 10 then
			lowFor = 0
			setTier(Perf.tier - 1)
		elseif highFor >= 30 then
			highFor = 0
			-- a phone on auto never climbs above medium: memory, not frame rate, is what runs out first
			if Perf.tier < (Perf.touch and 2 or 3) then setTier(Perf.tier + 1) end
		end
	end)
	-- follow the saved setting (State is required lazily: Perf starts first)
	task.spawn(function()
		local State = require(script.Parent:WaitForChild("State"))
		local function follow()
			local s = State.data and State.data.settings
			Perf.setQuality(s and s.quality or "auto")
		end
		follow()
		State.onData(function(keys) if keys.settings then follow() end end)
	end)
end

return Perf
