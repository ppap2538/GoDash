-- Loy Krathong at Bueng Kaen Nakhon (Config/Festival.LOY: 20-30 Nov 2026, the night itself 24 Nov).
-- (2026-11-18, owner: "ทำทั้งหมดที่เสนอมาได้เลย": content for TikTok clips; Bueng Kaen Nakhon holds Khon Kaen's real one.)
--   * Workspace "Festival" = "loykrathong" while it runs and "FestivalAt" = the pier end (clients: chip, GPS,
--     fireworks, krathong drift: client/Festival)
--   * along the promenade either side of the pier: lantern posts with strings of coloured bulbs, an arch over the
--     pier, a krathong stall; a prompt at the end of the pier
--   * City op "krathong" ("wish,style"): the first krathong each day is free (season XP + happiness), then ฿20.
--     It floats away from the pier with the rider's name and wish; clients move it from its attributes
--     (LaunchAt, DirX, DirZ, WaterY, Seed), the server only creates and removes it
--   * a few krathongs with no name drift out on their own, so the lake glows even when the server is quiet
-- Culture only: no monks, no rites. Studio: Workspace attribute QaFestival = true runs it now.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Festival = require(Shared.Config.Festival)
local Season = require(Shared.Config.Season)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Lifestyle = require(script.Parent.LifestyleService)
local SeasonService = require(script.Parent.SeasonService)
local City = require(script.Parent.CityRemote)
local World = script.Parent.Parent.World
local Kit = require(World.Kit)
local S = require(World.Scenery)

local Service = {}
local LOY = Festival.LOY
local V3, CF = Vector3.new, CFrame.new
local M = Kit.M

local folder: Folder? = nil
local floating: Folder? = nil
local launch: Vector3? = nil -- the end of the pier, on the water
local out: Vector3? = nil -- from the water toward the land
local waterY = 0.8
local lanes = {} :: { { dir: Vector3, run: number } } -- directions from the launch point that stay over water
local lastFloat = {} :: { [Player]: number }

function Service.active(): boolean
	return Workspace:GetAttribute("Festival") == LOY.id
end

local function inWindow(): boolean
	if RunService:IsStudio() and Workspace:GetAttribute("QaFestival") then return true end
	local day = Util.dayNumber()
	return day >= LOY.from and day <= LOY.to
end

-- a krathong: a round slice of banana trunk, folded leaves round it, flowers, a candle with a small flame
local function makeKrathong(style, owner: string?, wish: string?): Model
	local m = Instance.new("Model")
	m.Name = "Krathong"
	local base = Kit.part(m, V3(0.7, 2.8, 2.8), CF() * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(226, 214, 170), M.SmoothPlastic,
		{ decor = true, shape = Enum.PartType.Cylinder, name = "Base" })
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local cf = CF(math.cos(a) * 1.25, 0.5, math.sin(a) * 1.25) * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(math.rad(-20), 0, 0)
		Kit.wedge(m, V3(0.7, 1.1, 0.7), cf, style.leaf, M.SmoothPlastic, { decor = true })
	end
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2 + 0.3
		Kit.ball(m, 0.62, CF(math.cos(a) * 0.7, 0.75, math.sin(a) * 0.7), style.flower, M.SmoothPlastic, { decor = true })
	end
	Kit.cyl(m, 0.28, 1.2, CF(0, 1.05, 0), Color3.fromRGB(250, 248, 236), M.SmoothPlastic, { decor = true })
	local flame = Kit.ball(m, 0.32, CF(0, 1.78, 0), Color3.fromRGB(255, 170, 60), M.Neon, { decor = true, name = "Flame" })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 180, 90)
	light.Range = 9
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = flame
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false end
	end
	if owner then
		local g = Instance.new("BillboardGui")
		g.Size = UDim2.fromOffset(190, 40)
		g.StudsOffset = V3(0, 3.2, 0)
		g.MaxDistance = 110
		g.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(255, 236, 190)
		t.TextStrokeTransparency = 0.4
		t.Text = owner .. (wish and ("\n" .. wish) or "")
		t:SetAttribute("NoTranslate", true)
		t.Parent = g
		g.Parent = base
	end
	m.WorldPivot = CF() -- built round the origin, upright: PivotTo places it
	return m
end

-- The lake is several water parts with strips of ground between them (a play test floated one krathong onto the
-- bank). So find real water: the launch point is the first water off the end of the pier, and the krathongs only
-- drift along lanes that stay over water (how far each lane goes rides along as MaxDist). The lake may not be
-- built yet when the festival starts (nobody near it): then it is searched again before a later krathong.
local pierShore: Vector3? = nil
local waterFound = false
local lastSearch = -1e9
local function findWater()
	if not (pierShore and out) then return end
	lastSearch = os.clock()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local function water(p: Vector3): (boolean, number?)
		local hit = Workspace:Raycast(V3(p.X, 40, p.Z), V3(0, -80, 0), params)
		if hit and hit.Instance.Name == "Water" then return true, hit.Position.Y end
		return false, nil
	end
	local shore = pierShore :: Vector3
	launch = shore - out * 33
	waterFound = false
	for dist = 8, 90, 2 do
		local p = shore - out * dist
		local ok, y = water(p)
		if ok and water(p - out * 10) then
			launch, waterY = p, y or waterY
			waterFound = true
			break
		end
	end
	lanes = {}
	if waterFound then
		for k = 0, 35 do
			local a = k / 36 * math.pi * 2
			local dir = V3(math.cos(a), 0, math.sin(a))
			local run = 0
			for s = 8, 420, 12 do
				if water(launch + dir * s) then run = s else break end
			end
			if run >= 60 then table.insert(lanes, { dir = dir, run = run }) end
		end
		table.sort(lanes, function(p, q) return p.run > q.run end)
	end
	if #lanes == 0 then
		waterFound = false
		lanes = { { dir = -out, run = 120 } }
	end
	Workspace:SetAttribute("FestivalAt", launch)
	-- where the fireworks go: over the water the krathongs drift out on, as seen from the pier (client/Festival)
	local sky = launch + lanes[1].dir * math.min(lanes[1].run, 260) * 0.8
	Workspace:SetAttribute("FestivalSky", sky)
end

local function float(style, owner: string?, wish: string?)
	if not waterFound and os.clock() - lastSearch > 20 then findWater() end
	if not (floating and launch and out) or #lanes == 0 then return end
	local list = floating:GetChildren()
	if #list >= LOY.maxOnWater then
		table.sort(list, function(a, b) return (a:GetAttribute("LaunchAt") or 0) < (b:GetAttribute("LaunchAt") or 0) end)
		list[1]:Destroy()
	end
	local m = makeKrathong(style, owner, wish)
	-- out along one of the longest water lanes, so they fan out and never reach the bank
	local lane = lanes[math.random(1, math.min(6, #lanes))]
	local dir = lane.dir
	m:PivotTo(CF(launch + V3(0, waterY + 0.35, 0)))
	m:SetAttribute("LaunchAt", Workspace:GetServerTimeNow())
	m:SetAttribute("DirX", dir.X)
	m:SetAttribute("DirZ", dir.Z)
	m:SetAttribute("MaxDist", math.max(20, lane.run - 10))
	m:SetAttribute("WaterY", waterY)
	m:SetAttribute("Seed", math.random(1, 1000))
	m:AddTag("Krathong")
	m.Parent = floating
	task.delay(LOY.lifetime + 4, function()
		if m.Parent then m:Destroy() end
	end)
end

-- lantern posts along the promenade, an arch over the pier, the krathong stall and the prompt
local function decorate(lake)
	local pier = lake.pier
	if not pier then return end
	out = V3(pier.ox or 0, 0, pier.oz or 1)
	if out.Magnitude < 0.1 then out = V3(0, 0, 1) end
	out = out.Unit
	local shore = V3(pier.x, 0, pier.z)
	pierShore = shore
	findWater()

	local deco = Kit.model(folder, "Decor")
	local bulbs = { Color3.fromRGB(255, 80, 70), Color3.fromRGB(255, 200, 60), Color3.fromRGB(80, 220, 120), Color3.fromRGB(90, 160, 255), Color3.fromRGB(240, 120, 220) }
	-- the promenade path round the lake: walk ~700 studs either way from the vertex nearest the pier
	local path = lake.path
	local n = #path // 2
	local best, bestD = 1, math.huge
	for i = 1, n do
		local d = (path[i * 2 - 1] - pier.x) ^ 2 + (path[i * 2] - pier.z) ^ 2
		if d < bestD then best, bestD = i, d end
	end
	local centre = V3(lake.x, 0, lake.z)
	for _, dirStep in ipairs({ 1, -1 }) do
		local walked, acc, prevTop = 0, 26, nil
		local i = best
		for _ = 1, n do
			local j = ((i - 1 + dirStep) % n) + 1
			local a = V3(path[i * 2 - 1], 0, path[i * 2])
			local b = V3(path[j * 2 - 1], 0, path[j * 2])
			local seg = (b - a).Magnitude
			if seg > 0.5 then
				local u = (b - a) / seg
				local side = V3(-u.Z, 0, u.X)
				if (a + side - centre).Magnitude < (a - centre).Magnitude then side = -side end -- the land side
				local s = 0
				while s < seg do
					local step = math.min(28 - acc, seg - s)
					s += step
					acc += step
					if acc >= 28 then
						acc = 0
						local p = a + u * s + side * 5.6
						Kit.cyl(deco, 0.4, 9, CF(p.X, 4.7, p.Z), Color3.fromRGB(150, 40, 40), M.Metal, { decor = true })
						local top = V3(p.X, 9.4, p.Z)
						local lantern = Kit.cyl(deco, 1.4, 1.6, CF(p.X, 8.6, p.Z), Color3.fromRGB(255, 140, 50), M.SmoothPlastic, { decor = true })
						Kit.nightGlow(lantern)
						if prevTop then
							for k = 1, 5 do
								local t = k / 6
								local q = prevTop:Lerp(top, t) - V3(0, math.sin(t * math.pi) * 1.6, 0)
								local bulb = Kit.ball(deco, 0.45, CF(q), bulbs[(k + (walked // 28)) % #bulbs + 1], M.SmoothPlastic, { decor = true })
								Kit.nightGlow(bulb)
							end
						end
						prevTop = top
						walked += 28
					end
				end
			end
			i = j
			if walked > 700 then break end
		end
	end
	-- the arch at the land end of the pier
	local cf = CFrame.lookAt(shore, shore - out) -- -Z over the water
	local red, gold = Color3.fromRGB(190, 40, 40), Color3.fromRGB(240, 190, 60)
	-- (a play test clipped the text on a 13-stud board: wider board, posts further apart)
	for _, sx in ipairs({ -10.5, 10.5 }) do Kit.cyl(deco, 0.9, 14, cf * CF(sx, 7, 2), red, M.SmoothPlastic, { decor = true }) end
	local board = Kit.part(deco, V3(22, 4.4, 0.5), cf * CF(0, 13.8, 2), red, M.SmoothPlastic, { decor = true })
	Kit.sign(board, "ลอยกระทง บึงแก่นนคร", { sub = "LOY KRATHONG 2026", bg = red, color = gold, face = Enum.NormalId.Front, maxDistance = 400, pps = 16, light = true })
	Kit.sign(board, "ลอยกระทง บึงแก่นนคร", { sub = "LOY KRATHONG 2026", bg = red, color = gold, face = Enum.NormalId.Back, maxDistance = 400, pps = 16, light = true })
	for k = -4, 4 do
		local l = Kit.ball(deco, 0.7, cf * CF(k * 2.4, 11.2, 2), bulbs[(k + 5) % #bulbs + 1], M.SmoothPlastic, { decor = true })
		Kit.nightGlow(l)
	end
	-- the krathong stall beside the pier's land end
	local stallAt = shore + out * 7 + V3(-out.Z, 0, out.X) * 9
	S.stall(deco, CFrame.lookAt(stallAt, stallAt - out), Random.new(24), "กระทง")
	-- the prompt at the end of the pier
	local spot = Instance.new("Part")
	spot.Name = "KrathongSpot"
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanQuery = false
	spot.Transparency = 1
	spot.Size = V3(4, 2, 4)
	spot.CFrame = CF(shore - out * 30 + V3(0, 3, 0))
	spot.Parent = deco
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Float a krathong"
	prompt.ObjectText = "Loy Krathong"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = spot
	prompt.Triggered:Connect(function(player)
		Net.fire(player, "Notify", "krathong_choose", { price = LOY.price })
	end)
	for _, p in ipairs(deco:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "KrathongSpot" then p.CanCollide = false; p.CanQuery = false; p.CanTouch = false end
	end
end

local function setOn(on: boolean, world)
	if on == Service.active() then return end
	if on then
		local lake
		for _, l in ipairs(world.lakes or {}) do
			if l.name == LOY.lake then lake = l break end
		end
		if not lake then warn("[Festival] lake not found: " .. LOY.lake) return end
		folder = Instance.new("Folder")
		folder.Name = "Festival"
		folder.Parent = Workspace
		floating = Kit.folder(folder, "Krathongs")
		decorate(lake)
		Workspace:SetAttribute("Festival", LOY.id)
		print("[Festival] Loy Krathong on at " .. tostring(launch))
	else
		Workspace:SetAttribute("Festival", nil)
		Workspace:SetAttribute("FestivalAt", nil)
		Workspace:SetAttribute("FestivalSky", nil)
		if folder then folder:Destroy() end
		folder, floating = nil, nil
	end
end

function Service.start(world)
	Players.PlayerRemoving:Connect(function(p) lastFloat[p] = nil end)
	City.register("krathong", function(player, arg)
		if not Service.active() or not launch then return false, "No festival now" end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or Util.flatDist(root.Position, launch) > 45 then return false, "Go to the end of the pier at Bueng Kaen Nakhon" end
		if os.clock() - (lastFloat[player] or 0) < 15 then return false, "Wait a moment before the next one" end
		local wi, si = string.match(tostring(arg or ""), "^(%d+),(%d+)$")
		local wish = LOY.wishes[tonumber(wi) or 0]
		local style = LOY.styles[tonumber(si) or 0]
		if not wish or not style then return false, "Pick a wish" end
		local d = Data.get(player)
		if not d then return false, "Not ready" end
		local th = not (d.settings and d.settings.lang == "en")
		Economy.rollDay(d)
		local first = (d.daily.krathong or 0) == 0
		if not first and not Economy.spend(player, LOY.price, "krathong") then
			return false, th and ("กระทงอันละ ฿%d เงินสดไม่พอ"):format(LOY.price) or ("A krathong costs ฿%d"):format(LOY.price)
		end
		d.daily.krathong = (d.daily.krathong or 0) + 1
		Data.touch(player, "daily")
		lastFloat[player] = os.clock()
		float(style, player.DisplayName, wish.th)
		if first then
			SeasonService.addXp(player, LOY.xp)
			Lifestyle.add(player, nil, nil, LOY.happy)
		end
		local _ = Season
		if th then return true, first and "อันแรกของวันฟรี (+XP ซีซั่น)" or "" end
		return true, first and "First krathong today is free (+season XP)" or ""
	end)
	task.spawn(function()
		while true do
			setOn(inWindow(), world)
			task.wait(RunService:IsStudio() and 3 or 30)
		end
	end)
	-- quiet krathongs with no name, so the lake is never dark during the festival
	task.spawn(function()
		while true do
			task.wait(18)
			if Service.active() and floating and #floating:GetChildren() < 14 then
				float(LOY.styles[math.random(1, #LOY.styles)], nil, nil)
			end
		end
	end)
end

return Service
