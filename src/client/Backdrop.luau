-- The city past the streaming radius (2026-11-18, owner: "beyond 450-700 studs nothing is drawn").
-- The server sends a coarse outline once (World/Skyline: per 128-stud cell the height of the tallest
-- building, or a tree mass); this draws it as plain blocks and tree balls in a ring from just past the
-- real streamed city out to Perf.limit("backdrop") (2,600 studs on a computer, 1,700 on a phone,
-- 1,000 on low), plus flat ground out to the horizon so nothing ends in the sky colour. The haze of the
-- Atmosphere does the rest. Local parts only: no collisions, no shadows, no queries.
-- Tall blocks get a strip of lit windows at night. The ring is refreshed as the player moves.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local Perf = require(script.Parent.Perf)

local Backdrop = {}
local INNER = 760 -- cell centres closer than this are left to the real (streamed) city
local GROUND_TILE = 2048
local folder: Folder
local sky -- { cell, x0, z0, nx, nz, values = { [index] = value } }
local shown = {} -- [cell index] = { parts }
local nightParts = {} -- [part] = true: window strips
local isNight = false

local BUILD_COLS = {
	Color3.fromRGB(214, 208, 196), Color3.fromRGB(204, 200, 192), Color3.fromRGB(222, 214, 198), Color3.fromRGB(198, 202, 204),
	Color3.fromRGB(216, 204, 188), Color3.fromRGB(190, 192, 196),
}
local ROOF_COLS = { Color3.fromRGB(176, 96, 70), Color3.fromRGB(150, 110, 90), Color3.fromRGB(120, 128, 136), Color3.fromRGB(168, 84, 64) }
local TREE_COLS = { Color3.fromRGB(70, 106, 60), Color3.fromRGB(80, 116, 64), Color3.fromRGB(62, 98, 58) }

local function decode(s)
	local A = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
	local val = {}
	for i = 1, #A do val[string.sub(A, i, i)] = i - 1 end
	local values = {}
	local idx = 0
	local i = 1
	local n = #s
	while i <= n do
		local ch = string.sub(s, i, i)
		if ch == "~" then
			idx += val[string.sub(s, i + 1, i + 1)] or 0
			i += 2
		elseif ch == "." then
			idx += 1
			i += 1
		else
			idx += 1
			values[idx] = val[ch]
			i += 1
		end
	end
	return values
end

local function part(size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = folder
	return p
end

local function hash(i: number, k: number): number -- 0..1, stable per cell
	local h = (i * 73856093 + k * 19349663) % 1000003
	return (h % 1000) / 1000
end

local function drawCell(i: number, v: number): { Part }
	local cell = sky.cell
	local cx = (i - 1) % sky.nx
	local cz = (i - 1) // sky.nx
	local x = sky.x0 + (cx + 0.5) * cell + (hash(i, 1) - 0.5) * cell * 0.3
	local z = sky.z0 + (cz + 0.5) * cell + (hash(i, 2) - 0.5) * cell * 0.3
	local out = {}
	if v >= 1 and v <= 31 then
		local h = v * 4
		local yaw = CFrame.Angles(0, hash(i, 3) * math.pi / 2, 0)
		local base = CFrame.new(x, 0, z) * yaw
		local w = cell * (0.48 + hash(i, 4) * 0.22)
		local d = cell * (0.42 + hash(i, 5) * 0.22)
		local col = BUILD_COLS[math.floor(hash(i, 6) * #BUILD_COLS) + 1]
		if h <= 26 then
			-- low town: two or three roofs of different heights
			table.insert(out, part(Vector3.new(w, h, d * 0.55), base * CFrame.new(0, h / 2, -d * 0.22), col))
			table.insert(out, part(Vector3.new(w * 0.8, h * 0.75, d * 0.5), base * CFrame.new(w * 0.08, h * 0.375, d * 0.27), BUILD_COLS[math.floor(hash(i, 7) * #BUILD_COLS) + 1]))
			table.insert(out, part(Vector3.new(w * 1.02, 1.6, d * 0.57), base * CFrame.new(0, h + 0.8, -d * 0.22), ROOF_COLS[math.floor(hash(i, 8) * #ROOF_COLS) + 1]))
		else
			-- a block with a set-back top storey
			table.insert(out, part(Vector3.new(w, h * 0.82, d), base * CFrame.new(0, h * 0.41, 0), col))
			table.insert(out, part(Vector3.new(w * 0.7, h * 0.18 + 1, d * 0.7), base * CFrame.new(0, h * 0.82 + h * 0.09, 0), col:Lerp(Color3.new(1, 1, 1), 0.15)))
			if h >= 40 then
				-- lit windows at night: a band across two faces
				local band = part(Vector3.new(w + 0.2, h * 0.5, 0.4), base * CFrame.new(0, h * 0.42, -d / 2 - 0.1), Color3.fromRGB(255, 214, 150))
				band.Material = Enum.Material.Neon
				band.Transparency = isNight and 0.55 or 1
				nightParts[band] = true
				table.insert(out, band)
				local band2 = part(Vector3.new(0.4, h * 0.36, d + 0.2), base * CFrame.new(w / 2 + 0.1, h * 0.36, 0), Color3.fromRGB(255, 220, 160))
				band2.Material = Enum.Material.Neon
				band2.Transparency = isNight and 0.6 or 1
				nightParts[band2] = true
				table.insert(out, band2)
			end
		end
	elseif v >= 32 then
		-- a clump of trees: two or three crowns of different sizes, sunk so they read as trees, not hills
		local h = 12 + (v - 32) * 2
		local n = hash(i, 11) < 0.5 and 3 or 2
		for k = 1, n do
			local r = cell * (0.13 + hash(i, 10 + k) * 0.08)
			local ox = (hash(i, 20 + k) - 0.5) * cell * 0.5
			local oz = (hash(i, 30 + k) - 0.5) * cell * 0.5
			local top = h * (0.75 + hash(i, 40 + k) * 0.35)
			table.insert(out, part(Vector3.new(r * 2, r * 2, r * 2), CFrame.new(x + ox, top - r, z + oz), TREE_COLS[math.floor(hash(i, 9 + k) * #TREE_COLS) + 1], Enum.PartType.Ball))
		end
	end
	return out
end

local ground = {}
local function focus(): Vector3?
	local char = Players.LocalPlayer.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return r and (r :: BasePart).Position or nil
end

local function refresh()
	local pos = focus()
	if not pos or not sky then return end
	local outer = Perf.limit("backdrop")
	local cell = sky.cell
	local want = {}
	local r = math.ceil(outer / cell) + 1
	local cx0 = math.floor((pos.X - sky.x0) / cell)
	local cz0 = math.floor((pos.Z - sky.z0) / cell)
	local in2, out2 = INNER * INNER, outer * outer
	for cx = math.max(0, cx0 - r), math.min(sky.nx - 1, cx0 + r) do
		for cz = math.max(0, cz0 - r), math.min(sky.nz - 1, cz0 + r) do
			local i = cz * sky.nx + cx + 1
			local v = sky.values[i]
			if v then
				local x = sky.x0 + (cx + 0.5) * cell
				local z = sky.z0 + (cz + 0.5) * cell
				local d2 = (x - pos.X) ^ 2 + (z - pos.Z) ^ 2
				if d2 >= in2 and d2 <= out2 then want[i] = v end
			end
		end
	end
	for i, parts in pairs(shown) do
		if not want[i] then
			for _, p in ipairs(parts) do
				nightParts[p] = nil
				p:Destroy()
			end
			shown[i] = nil
		end
	end
	local made = 0
	for i, v in pairs(want) do
		if not shown[i] then
			shown[i] = drawCell(i, v)
			made += 1
			if made % 60 == 0 then task.wait() end -- spread a big first draw over a few frames
		end
	end
	-- ground to the horizon, 2 studs under the real ground (hidden wherever the real ground has streamed in)
	local gx = math.floor(pos.X / 512) * 512
	local gz = math.floor(pos.Z / 512) * 512
	local k = 0
	for ix = -1, 1 do
		for iz = -1, 1 do
			k += 1
			local g = ground[k]
			if not g then
				g = part(Vector3.new(GROUND_TILE, 2, GROUND_TILE), CFrame.new(), Color3.fromRGB(146, 150, 112))
				g.Material = Enum.Material.Grass
				g.Name = "FarGround"
				ground[k] = g
			end
			g.CFrame = CFrame.new(gx + ix * GROUND_TILE, -3, gz + iz * GROUND_TILE)
		end
	end
end

local function setNight(on: boolean)
	isNight = on
	for p in pairs(nightParts) do
		if p.Parent then p.Transparency = on and 0.58 or 1 end
	end
end

function Backdrop.start()
	folder = Instance.new("Folder")
	folder.Name = "GoDashBackdrop"
	folder.Parent = Workspace
	isNight = Workspace:GetAttribute("IsNight") == true
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(function() setNight(Workspace:GetAttribute("IsNight") == true) end)
	task.spawn(function()
		for _ = 1, 20 do
			local ok, _, s = Net.call("GetSkyline")
			if ok and s then
				sky = { cell = s.cell, x0 = s.x0, z0 = s.z0, nx = s.nx, nz = s.nz, values = decode(s.data) }
				break
			end
			task.wait(3)
		end
		if not sky then return end
		local last: Vector3? = nil
		local lastTier = Perf.tier
		while true do
			local pos = focus()
			if pos and (not last or (pos - last).Magnitude > 48 or Perf.tier ~= lastTier) then
				last, lastTier = pos, Perf.tier
				local ok, err = pcall(refresh)
				if not ok then warn("[Backdrop] " .. tostring(err)) end
			end
			task.wait(0.5)
		end
	end)
end

-- QA: how much is drawn
function Backdrop.stats()
	local cells, parts = 0, 0
	for _, list in pairs(shown) do
		cells += 1
		parts += #list
	end
	return { cells = cells, parts = parts, outer = Perf.limit("backdrop"), loaded = sky ~= nil }
end

return Backdrop
