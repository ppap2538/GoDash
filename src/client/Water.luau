-- Lakes after dark (2026-11-19, owner: "น้ำในบึงมีคลื่นเคลื่อนไหว และสะท้อนแสงไฟตอนกลางคืน").
--
-- The lakes are Roblox terrain water now (server/World/WaterSurface): waves and the sky in them, but
-- lamps barely show. So every light near a lake gets a soft, shimmering streak on the water where its
-- reflection would be seen from the camera: at the mirror point between the camera and the light,
-- stretched toward the camera the way ripples stretch a reflection. Lamps on the stone rim, the
-- festival lanterns and the krathong candles all get one; the nearest ones win when there are too many.
-- The water colour also turns from daytime teal to a deep night blue.
--
-- Cost: one pass over the candidate lights ten times a second, one downward ray per streak shown,
-- a pool of at most MAX[tier] flat parts with a SurfaceGui each. Low tier phones show a few.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Map = require(Shared.Config.Maps[Game.MAP])
local Perf = require(script.Parent.Perf)

local Water = {}

local WATER_Y = Game.WATER_Y
local MAX = { 6, 14, 24 } -- streaks by Perf tier
local REACH = 380 -- lights farther from the camera than this get none
local CELL = 32 -- the "near a lake" grid
local DAY_COL, NIGHT_COL = Color3.fromRGB(30, 88, 84), Color3.fromRGB(16, 38, 52)

-- cells within ~2 cells of water, from the map outlines (the lights are tested once, when they appear)
local near = {} :: { [number]: boolean }
local function key(cx: number, cz: number): number return cx * 65536 + cz end
local function buildNear()
	for _, w in ipairs(Map.features.water or {}) do
		local pts = w.pts
		local n = #pts // 2
		local minZ, maxZ = math.huge, -math.huge
		for i = 1, n do minZ = math.min(minZ, pts[i * 2]); maxZ = math.max(maxZ, pts[i * 2]) end
		local z = minZ + CELL / 2
		while z < maxZ do
			local xs = {}
			for i = 1, n do
				local j = i % n + 1
				local x1, z1, x2, z2 = pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2]
				if (z1 <= z and z2 > z) or (z2 <= z and z1 > z) then table.insert(xs, x1 + (z - z1) / (z2 - z1) * (x2 - x1)) end
			end
			table.sort(xs)
			for k = 1, #xs - 1, 2 do
				local cz = math.floor(z / CELL)
				for cx = math.floor(xs[k] / CELL), math.floor(xs[k + 1] / CELL) do
					for dx = -2, 2 do
						for dz = -2, 2 do near[key(cx + dx, cz + dz)] = true end
					end
				end
			end
			z += CELL
		end
	end
end
local function nearWater(p: Vector3): boolean
	return near[key(math.floor(p.X / CELL), math.floor(p.Z / CELL))] == true
end

-- candidate lights: [part] = true (lamps, lanterns, big signs by a lake; krathong candles)
local lights = {} :: { [BasePart]: boolean }
local function consider(p: Instance)
	if not p:IsA("BasePart") then return end
	local s = p.Size
	if math.max(s.X, s.Y, s.Z) < 0.9 then return end -- strings of tiny bulbs: too many, too small
	if nearWater(p.Position) then lights[p] = true end
end
local function considerKrathong(m: Instance)
	local flame = m:FindFirstChild("Flame") or m:WaitForChild("Flame", 5)
	if flame and flame:IsA("BasePart") then lights[flame] = true end
end

-- the streak pool
local pool = {} :: { any }
local folder: Folder? = nil
local function newStreak()
	local p = Instance.new("Part")
	p.Name = "LightOnWater"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(2, 0.05, 20)
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Top
	g.LightInfluence = 0
	g.Brightness = 2.2
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 6
	g.Parent = p
	local bars = {}
	-- a bright core and two broken side bars, each fading in and out along its length
	for k = 1, 3 do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.Size = UDim2.fromScale(k == 2 and 0.5 or 0.26, k == 2 and 1 or 0.72)
		f.Position = UDim2.fromScale(k == 1 and 0.02 or (k == 2 and 0.25 or 0.72), k == 2 and 0 or 0.14)
		f.Parent = g
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
		local gr = Instance.new("UIGradient")
		gr.Rotation = 90
		gr.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, k == 2 and 0.25 or 0.55),
			NumberSequenceKeypoint.new(0.65, k == 2 and 0.4 or 0.7), NumberSequenceKeypoint.new(1, 1),
		})
		gr.Parent = f
		table.insert(bars, { frame = f, grad = gr })
	end
	local s = { part = p, bars = bars, seed = math.random() * 100, on = false }
	p.Parent = folder
	return s
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { Workspace.Terrain }
rayParams.IgnoreWater = false

local function overWater(x: number, z: number): boolean
	local hit = Workspace:Raycast(Vector3.new(x, WATER_Y + 6, z), Vector3.new(0, -10, 0), rayParams)
	return hit ~= nil and hit.Material == Enum.Material.Water
end

local function darkness(): number -- 0 by day, 1 at night, eased over dusk and dawn
	local t = Lighting.ClockTime
	if t >= 17.4 and t < 19.4 then return (t - 17.4) / 2 end
	if t >= 19.4 or t < 5 then return 1 end
	if t >= 5 and t < 6.6 then return 1 - (t - 5) / 1.6 end
	return 0
end

local function update()
	local cam = Workspace.CurrentCamera
	local dark = darkness()
	local terrain = Workspace.Terrain
	local want = DAY_COL:Lerp(NIGHT_COL, dark)
	if (terrain.WaterColor.R - want.R) ^ 2 + (terrain.WaterColor.G - want.G) ^ 2 > 1e-5 then terrain.WaterColor = want end
	local limit = MAX[Perf.tier] or 14
	local chosen = {}
	if cam and dark > 0.35 then
		local C = cam.CFrame.Position
		local hC = C.Y - WATER_Y
		if hC > 0.5 then
			local list = {}
			for p in pairs(lights) do
				if p.Parent == nil then
					lights[p] = nil
				else
					local d = (p.Position - C).Magnitude
					if d < REACH and (p.Material == Enum.Material.Neon or p.Name == "Flame") then
						table.insert(list, { p = p, d = d })
					end
				end
			end
			table.sort(list, function(a, b) return a.d < b.d end)
			for _, it in ipairs(list) do
				if #chosen >= limit then break end
				local L = it.p.Position
				local hL = L.Y - WATER_Y
				if hL > 0.3 then
					local t = hC / (hC + hL)
					local rx, rz = C.X + (L.X - C.X) * t, C.Z + (L.Z - C.Z) * t
					if overWater(rx, rz) then
						table.insert(chosen, { p = it.p, rx = rx, rz = rz, hL = hL })
					end
				end
			end
		end
	end
	for i = 1, math.max(#chosen, #pool) do
		local c = chosen[i]
		local s = pool[i]
		if c then
			if not s then
				s = newStreak()
				pool[i] = s
			end
			local C = cam.CFrame.Position
			local R = Vector3.new(c.rx, WATER_Y + 0.15, c.rz)
			local toCam = Vector3.new(C.X - R.X, 0, C.Z - R.Z)
			local dist = math.max(toCam.Magnitude, 1)
			local size = c.p.Size
			local tall = math.clamp(c.hL / 9, 0.25, 1) -- a candle just above the water makes a short one
			local len = (6 + dist * 0.75) * tall
			local width = math.clamp(math.max(size.X, size.Z) * 1.1, 0.8, 7) + dist * 0.01
			s.part.Size = Vector3.new(width, 0.05, len)
			s.part.CFrame = CFrame.lookAt(R, R + toCam / dist)
			local col = c.p.Color
			if col ~= s.color then
				s.color = col
				for _, b in ipairs(s.bars) do b.frame.BackgroundColor3 = col end
			end
			if not s.on then
				s.on = true
				s.part.Parent = folder
			end
		elseif s and s.on then
			s.on = false
			s.part.Parent = nil
		end
	end
end

-- the ripple shimmer: each bar's gradient slides and its brightness wobbles
local function shimmer(now: number)
	for _, s in ipairs(pool) do
		if s.on then
			for k, b in ipairs(s.bars) do
				local ph = now * (2.1 + k * 0.7) + s.seed * k
				b.grad.Offset = Vector2.new(0, math.sin(ph) * 0.09)
				b.frame.BackgroundTransparency = 0.12 + 0.18 * (0.5 + 0.5 * math.sin(ph * 1.7 + k))
			end
		end
	end
end

function Water.start()
	buildNear()
	local f = Instance.new("Folder")
	f.Name = "WaterLights"
	f.Parent = Workspace
	folder = f
	for _, tag in ipairs({ "NightGlow", "NightLight" }) do
		for _, p in ipairs(CollectionService:GetTagged(tag)) do consider(p) end
		CollectionService:GetInstanceAddedSignal(tag):Connect(consider)
	end
	for _, m in ipairs(CollectionService:GetTagged("Krathong")) do task.spawn(considerKrathong, m) end
	CollectionService:GetInstanceAddedSignal("Krathong"):Connect(function(m) task.spawn(considerKrathong, m) end)
	task.spawn(function()
		while true do
			local ok, err = pcall(update)
			if not ok then warn("[Water] " .. tostring(err)) end
			task.wait(0.1)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if #pool > 0 then shimmer(os.clock()) end
	end)
end

return Water
