-- Places that sound like themselves (2026-11-18, owner: "market noise, the school bell, dogs barking:
-- the city should sound alive"). On top of the town-wide birds / traffic / night loops in client/Env:
--   * the fresh market at dawn and late afternoon, the night market and the walking street in the
--     evening, the school yard at the morning bell, lunch and home time (the bell rings at 8:00 and
--     15:30 game time), the university, the mall, the stadium on match evenings: each a 3-D sound at
--     the place, heard as you ride past
--   * water lapping at the lake shore near you, frogs by the lakes and in the fields at night
--   * crickets in the suburbs and the countryside at night, roosters and farm animals at dawn
-- Follows Phone > Settings > City ambience (settings.music) and stops in the rain. Only places within
-- 420 studs get a sound, so it costs a handful of Sound instances at any time.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Game = require(Shared.Config.Game)
local Map = require(Shared.Config.Maps[Game.MAP])
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)

local Ambience = {}
local REACH = 420

-- kind -> { sound, volume, { {from, to}, ... } }
local PLACES = {
	market = { Sounds.marketDay, 0.55, { { 5.2, 10 }, { 15, 18.6 } } },
	nightmarket = { Sounds.nightMarket, 0.6, { { 17, 23.8 } } },
	school = { Sounds.schoolYard, 0.5, { { 6.8, 8.3 }, { 11.5, 12.8 }, { 15.3, 16.6 } } },
	university = { Sounds.schoolYard, 0.22, { { 8, 18 } } },
	mall = { Sounds.cafeWalla, 0.3, { { 10, 21.5 } } },
	stadium = { Sounds.stadiumCrowd, 0.55, { { 16.5, 20.2 } } },
}

local function open(windows, h: number): boolean
	for _, w in ipairs(windows) do
		if h >= w[1] and h < w[2] then return true end
	end
	return false
end

local folder: Folder
local emitters = {} -- [key] = { part, sound, want }
local function emitter(key: string, pos: Vector3, id: string, minD: number, maxD: number)
	local e = emitters[key]
	if not e then
		local p = Instance.new("Part")
		p.Name = "Amb_" .. key
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Transparency = 1
		p.Size = Vector3.new(1, 1, 1)
		p.Parent = folder
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Looped = true
		s.Volume = 0
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = minD
		s.RollOffMaxDistance = maxD
		s.SoundGroup = Feedback.sfxGroup
		s.Parent = p
		s:Play()
		e = { part = p, sound = s, want = 0 }
		emitters[key] = e
	end
	e.part.Position = pos
	e.seen = true
	return e
end

local function global(name: string, id: string): Sound
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

local function rootPos(): Vector3?
	local char = Players.LocalPlayer.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return r and (r :: BasePart).Position or nil
end

local lakePts = nil
State.onWorld(function() lakePts = nil end)
local function nearestShore(pos: Vector3): (Vector3?, number)
	local w = State.world
	if not lakePts then
		if not w or not w.lakes then return nil, math.huge end
		lakePts = {}
		for _, l in ipairs(w.lakes) do
			for i = 1, #l.path - 1, 2 do table.insert(lakePts, Vector3.new(l.path[i], 1, l.path[i + 1])) end
		end
	end
	local best, bd = nil, math.huge
	for _, q in ipairs(lakePts) do
		local d = (q.X - pos.X) ^ 2 + (q.Z - pos.Z) ^ 2
		if d < bd then best, bd = q, d end
	end
	return best, math.sqrt(bd)
end

function Ambience.start()
	folder = Instance.new("Folder")
	folder.Name = "GoDashAmbience"
	folder.Parent = Workspace
	local crickets = global("Crickets", Sounds.crickets)
	local frogs = global("Frogs", Sounds.frogs)
	local farm = global("FarmMorning", Sounds.farmMorning)
	local lastHour = Lighting.ClockTime

	task.spawn(function()
		while true do
			task.wait(0.5)
			local pos = rootPos()
			local s = State.data and State.data.settings
			local on = not (s and s.music == false)
			local rain = (Workspace:GetAttribute("Rain") or 0) > 0.2
			local h = Lighting.ClockTime
			for _, e in pairs(emitters) do e.seen = false; e.want = 0 end
			local use = "urban"
			if pos then
				use = Map.landUse(pos.X, pos.Z)
				local w = State.world
				-- the places near you that are busy at this hour
				if w and on then
					for _, p in ipairs(w.pois or {}) do
						local cfg = PLACES[p.kind]
						if cfg and p.pos and cfg[1] ~= "" and (p.pos - pos).Magnitude < REACH and open(cfg[3], h) then
							local e = emitter(p.id or p.kind, p.pos + Vector3.new(0, 6, 0), cfg[1], 26, 240)
							e.want = cfg[2] * (rain and 0.4 or 1)
						end
					end
					-- the lake shore beside you
					local shore, d = nearestShore(pos)
					if shore and d < 260 then
						local e = emitter("lake", shore, Sounds.lakeWater, 18, 150)
						e.want = 0.45
						local night = h >= 18.8 or h < 5.6
						if night then
							local f = emitter("lakefrogs", shore + Vector3.new(0, 0, 0.5), Sounds.frogs, 30, 220)
							f.want = 0.4
						end
					end
				end
				-- the school bell: once as the game clock passes 8:00 and 15:30, at schools near you
				for _, t in ipairs({ 8, 15.5 }) do
					if lastHour < t and h >= t and w and on then
						for _, p in ipairs(w.pois or {}) do
							if p.kind == "school" and p.pos and (p.pos - pos).Magnitude < 360 then
								local bell = Instance.new("Sound")
								bell.SoundId = Sounds.schoolBell
								bell.Volume = 0.7
								bell.RollOffMode = Enum.RollOffMode.InverseTapered
								bell.RollOffMinDistance, bell.RollOffMaxDistance = 30, 320
								bell.SoundGroup = Feedback.sfxGroup
								local e = emitter("bell_" .. tostring(p.id), p.pos + Vector3.new(0, 8, 0), "", 30, 320)
								e.keepUntil = os.clock() + 16 -- the bell rings out before its part is dropped
								bell.Parent = e.part
								bell:Play()
								bell.Ended:Once(function() bell:Destroy() end)
							end
						end
					end
				end
			end
			lastHour = h
			-- fade every emitter toward what it should be; drop the ones nobody needs
			for key, e in pairs(emitters) do
				if not e.seen and e.sound.Volume < 0.01 and os.clock() > (e.keepUntil or 0) then
					e.part:Destroy()
					emitters[key] = nil
				end
			end
			-- the countryside and the suburbs at night and at dawn
			local night = h >= 18.9 or h < 5.4
			local dawn = h >= 5.2 and h < 7.6
			local quiet = on and not rain
			Ambience.target = {
				crickets = (quiet and night and (use == "suburb" or use == "rural")) and (use == "rural" and 0.32 or 0.2) or ((quiet and night) and 0.07 or 0),
				frogs = (quiet and night and use == "rural") and 0.28 or 0,
				farm = (quiet and dawn and use == "rural") and 0.3 or ((quiet and dawn and use == "suburb") and 0.12 or 0),
			}
		end
	end)

	Ambience.target = { crickets = 0, frogs = 0, farm = 0 }
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		local k = math.min(1, dt * 0.7)
		for _, e in pairs(emitters) do
			e.sound.Volume += (e.want - e.sound.Volume) * k
		end
		local t = Ambience.target
		crickets.Volume += (t.crickets - crickets.Volume) * k
		frogs.Volume += (t.frogs - frogs.Volume) * k
		farm.Volume += (t.farm - farm.Volume) * k
	end)
end

-- QA: what is playing
function Ambience.stats()
	local out = {}
	for key, e in pairs(emitters) do table.insert(out, ("%s=%.2f"):format(key, e.sound.Volume)) end
	table.sort(out)
	return out
end

return Ambience
