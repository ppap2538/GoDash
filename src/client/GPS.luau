-- GPS: shortest route on the real street network, drawn three ways — a ribbon on the road,
-- a beacon at the destination and a line on the minimap. Also draws the phone's city map.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Map = require(Shared.Config.Maps[Game.MAP])
local RoadGraph = require(Shared.RoadGraph)
local Util = require(Shared.Util)
local UI = require(script.Parent.UI.Kit)
local State = require(script.Parent.State)
local HUD = require(script.Parent.HUD)
local Lang = require(script.Parent.Lang)

local GPS = {}
local C, F = UI.C, UI.F
local player = Players.LocalPlayer
local graph
GPS.distance = 0
GPS.name = ""
GPS.path = nil :: { Vector3 }?

local ROAD_COL = {
	highway = Color3.fromRGB(250, 204, 96), main = Color3.fromRGB(244, 246, 248), street = Color3.fromRGB(196, 202, 212), soi = Color3.fromRGB(112, 120, 132),
}
local ROAD_PX = { highway = 4, main = 3, street = 2, soi = 1 }
local POI_ICON = {
	hub = "🏠", mall = "🛍", station = "🚉", hospital = "🏥", bus = "🚌", nightmarket = "🏮", police = "🚓", market = "🥬", dealer = "🚗",
	homestore = "🛋", stupa = "🛕", reststop = "⛱", agri = "🌾", seedshop = "🌱", farm = "🚜", gas = "⛽",
}
GPS.POI_ICON = POI_ICON

local folder, beacon, beaconLabel
local ribbonPool, ribbonUsed = {}, 0

local function rootPos(): Vector3?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return r and r.Position or nil
end

-- What the player is navigating to right now.
function GPS.target()
	local j = State.job and State.job.job
	if j then
		local t = j.stage == "pickup" and j.pickup or j.dropoff
		local name = (Lang.code == "th" and t.thai and t.thai ~= "") and t.thai or t.name
		local verb = j.stage == "pickup" and (j.mode == "ride" and Lang.pick("🧍 Pick up", "🧍 รับผู้โดยสาร") or Lang.pick("🍱 Collect food", "🍱 รับอาหาร"))
			or (j.mode == "ride" and Lang.pick("📍 Drop off", "📍 ส่งผู้โดยสาร") or Lang.pick("📍 Deliver here", "📍 ส่งอาหารที่นี่"))
		return { pos = t.pos, name = t.name, label = verb .. ": " .. Lang.t(name), job = true }
	end
	return State.target
end

function GPS.setTarget(pos: Vector3?, name: string?)
	State.target = pos and { pos = pos, name = name or "Waypoint" } or nil
	GPS.lastKey = nil
end

---------------------------------------------------------------------------------------------------
-- world: ribbon + beacon
---------------------------------------------------------------------------------------------------
local function ribbon(a: Vector3, b: Vector3)
	ribbonUsed += 1
	local p = ribbonPool[ribbonUsed]
	if not p then
		p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = Color3.fromRGB(0, 220, 120)
		p.Transparency = 0.25
		p.Parent = folder
		ribbonPool[ribbonUsed] = p
	end
	local len = (b - a).Magnitude
	p.Size = Vector3.new(1.4, 0.06, len)
	p.CFrame = CFrame.lookAt((a + b) / 2 + Vector3.new(0, 0.42, 0), b + Vector3.new(0, 0.42, 0))
	p.Parent = folder
end

local function drawRibbon(path: { Vector3 }?, from: Vector3)
	ribbonUsed = 0
	if path then
		for i = 1, #path - 1 do
			local a, b = path[i], path[i + 1]
			-- only what is near enough to be seen
			if (a - from).Magnitude < 1100 or (b - from).Magnitude < 1100 then
				local len = (b - a).Magnitude
				local pieces = math.max(1, math.ceil(len / 1800))
				for k = 0, pieces - 1 do
					ribbon(a:Lerp(b, k / pieces), a:Lerp(b, (k + 1) / pieces))
				end
			end
		end
	end
	for i = ribbonUsed + 1, #ribbonPool do ribbonPool[i].Parent = nil end
end

local function ensureBeacon()
	if beacon then return end
	beacon = Instance.new("Part")
	beacon.Name = "Beacon"
	beacon.Anchored = true; beacon.CanCollide = false; beacon.CanQuery = false; beacon.CanTouch = false; beacon.CastShadow = false
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Material = Enum.Material.Neon
	beacon.Color = Color3.fromRGB(0, 220, 120)
	beacon.Transparency = 0.7
	beacon.Size = Vector3.new(110, 3, 3)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(250, 58)
	bb.StudsOffset = Vector3.new(0, 14, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 1e6
	bb.Parent = beacon
	local card = UI.new("Frame", { BackgroundColor3 = C.green, Size = UDim2.fromScale(1, 1), Parent = bb })
	UI.corner(card, 16)
	UI.stroke(card, C.white, 2)
	beaconLabel = UI.label(card, "", 15, C.white, F.bold, { Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
	-- a disc on the ground shows the interaction range
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CanTouch = false; ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = Color3.fromRGB(0, 220, 120)
	ring.Transparency = 0.82
	ring.Size = Vector3.new(0.12, Game.INTERACT_RANGE * 2, Game.INTERACT_RANGE * 2)
	ring.Parent = beacon
end

---------------------------------------------------------------------------------------------------
-- minimap
---------------------------------------------------------------------------------------------------
local MM_SCALE = 0.105 -- pixels per stud
local mm = { origin = Vector3.zero, lines = {}, route = {}, icons = {} }

local function lineFrame(parent: Instance, a: Vector3, b: Vector3, origin: Vector3, scale: number, px: number, color: Color3, z: number?)
	local dx, dz = b.X - a.X, b.Z - a.Z
	local len = math.sqrt(dx * dx + dz * dz)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(len * scale + px, px)
	f.Position = UDim2.new(0.5, ((a.X + b.X) / 2 - origin.X) * scale, 0.5, ((a.Z + b.Z) / 2 - origin.Z) * scale)
	f.Rotation = math.deg(math.atan2(dz, dx))
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function rebuildMinimap(pos: Vector3)
	local canvas = mm.canvas
	for _, f in ipairs(mm.lines) do f:Destroy() end
	mm.lines = {}
	mm.origin = pos
	for _, e in ipairs(graph:edgesNear(pos, 1500)) do
		table.insert(mm.lines, lineFrame(canvas, e.a.pos, e.b.pos, pos, MM_SCALE, ROAD_PX[e.type], ROAD_COL[e.type], 5 - e.def.id))
	end
	for _, f in ipairs(mm.icons) do f:Destroy() end
	mm.icons = {}
	if State.world then
		for _, p in ipairs(State.world.pois) do
			if (p.pos - pos).Magnitude < 1700 then
				local l = UI.label(canvas, POI_ICON[p.kind] or "📍", 13, C.white, F.med, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18),
					Position = UDim2.new(0.5, (p.pos.X - pos.X) * MM_SCALE, 0.5, (p.pos.Z - pos.Z) * MM_SCALE), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8 })
				table.insert(mm.icons, l)
			end
		end
	end
	mm.routeDirty = true
end

local function rebuildRoute()
	for _, f in ipairs(mm.route) do f:Destroy() end
	mm.route = {}
	local path = GPS.path
	if not path then return end
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		if (a - mm.origin).Magnitude < 2200 or (b - mm.origin).Magnitude < 2200 then
			table.insert(mm.route, lineFrame(mm.canvas, a, b, mm.origin, MM_SCALE, 4, Color3.fromRGB(0, 220, 120), 7))
		end
	end
end

local function buildMinimap()
	local holder = HUD.mapHolder
	if not holder then return end
	mm.canvas = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = holder })
	mm.arrow = UI.label(holder, "▲", 16, C.green, F.black, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 20, TextStrokeTransparency = 0, TextStrokeColor3 = C.white })
	mm.dot = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(0, 220, 120), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), ZIndex = 19, Visible = false, Parent = holder })
	UI.corner(mm.dot, 6)
	UI.stroke(mm.dot, C.white, 2)
	UI.label(holder, "N", 10, C.white, F.bold, { Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(14, 12), ZIndex = 21 })
end

---------------------------------------------------------------------------------------------------
-- phone: whole-city map. Returns a function that places a marker at a world position.
---------------------------------------------------------------------------------------------------
function GPS.drawCity(parent: Frame)
	local b = Map.bounds
	local w, h = b.maxX - b.minX, b.maxZ - b.minZ
	local size = parent.AbsoluteSize
	local guiScale = parent:FindFirstAncestorOfClass("ScreenGui")
	local sc = guiScale and guiScale:FindFirstChildOfClass("UIScale")
	local div = sc and sc.Scale or 1
	local pw, ph = size.X / div, size.Y / div
	local scale = math.min(pw / w, ph / h)
	local origin = Vector3.new((b.minX + b.maxX) / 2, 0, (b.minZ + b.maxZ) / 2)
	local canvas = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	-- water first
	for _, wt in ipairs(Map.features.water) do
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for i = 1, #wt.pts, 2 do
			minX = math.min(minX, wt.pts[i]); maxX = math.max(maxX, wt.pts[i]); minZ = math.min(minZ, wt.pts[i + 1]); maxZ = math.max(maxZ, wt.pts[i + 1])
		end
		local f = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(70, 150, 200), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset((maxX - minX) * scale * 0.8, (maxZ - minZ) * scale * 0.9),
			Position = UDim2.new(0.5, ((minX + maxX) / 2 - origin.X) * scale, 0.5, ((minZ + maxZ) / 2 - origin.Z) * scale), Parent = canvas })
		UI.corner(f, 12)
	end
	for _, e in ipairs(graph.edges) do
		if e.type ~= "soi" then
			lineFrame(canvas, e.a.pos, e.b.pos, origin, scale, e.type == "highway" and 3 or (e.type == "main" and 2 or 1), ROAD_COL[e.type], 5 - e.def.id)
		end
	end
	local function toPoint(pos: Vector3): UDim2
		return UDim2.new(0.5, (pos.X - origin.X) * scale, 0.5, (pos.Z - origin.Z) * scale)
	end
	return canvas, toPoint, scale, origin
end

function GPS.graph() return graph end

function GPS.start()
	graph = RoadGraph.new(Map)
	folder = Instance.new("Folder")
	folder.Name = "GoDashGPS"
	folder.Parent = Workspace
	buildMinimap()
	HUD.gps = GPS
	State.onWorld(function() mm.origin = Vector3.new(1e9, 0, 0) end) -- redraw icons

	local lastPathPos, lastPathT = Vector3.zero, 0
	task.spawn(function()
		while true do
			task.wait(0.4)
			local pos = rootPos()
			if pos then
				local t = GPS.target()
				local key = t and (math.floor(t.pos.X) .. ":" .. math.floor(t.pos.Z)) or "none"
				if t then
					local now = os.clock()
					if key ~= GPS.lastKey or (pos - lastPathPos).Magnitude > 70 or now - lastPathT > 4 then
						GPS.lastKey = key
						lastPathPos, lastPathT = pos, now
						local path, len = graph:path(pos, t.pos)
						GPS.path = path
						GPS.distance = len + Util.flatDist(path[#path], t.pos)
						GPS.name = t.name
						drawRibbon(path, pos)
						mm.routeDirty = true
					end
					ensureBeacon()
					beacon.CFrame = CFrame.new(t.pos.X, 80, t.pos.Z) * CFrame.Angles(0, 0, math.rad(90))
					beacon.Ring.CFrame = CFrame.new(t.pos.X, 0.5, t.pos.Z) * CFrame.Angles(0, 0, math.rad(90))
					beaconLabel.Text = (t.label or Lang.t(t.name)) .. "\n" .. Lang.t(Util.dist(Util.flatDist(pos, t.pos)))
					beacon.Parent = folder
					-- arriving at a waypoint (not a job) clears it
					if not t.job and Util.flatDist(pos, t.pos) < 40 then
						GPS.setTarget(nil)
					end
				else
					if GPS.path then
						GPS.path = nil
						GPS.lastKey = nil
						drawRibbon(nil, pos)
						mm.routeDirty = true
					end
					GPS.distance = 0
					if beacon then beacon.Parent = nil end
				end
				if (pos - mm.origin).Magnitude > 320 then rebuildMinimap(pos) end
				if mm.routeDirty then mm.routeDirty = false; rebuildRoute() end
				local e = graph:nearest(pos)
				local road = e and Lang.name(e) or ""
				HUD.setRoad((road ~= "" and (road .. " · ") or "") .. Lang.name(Map.zoneAt(pos.X, pos.Z)))
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local char = player.Character
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if not r or not mm.canvas then return end
		local pos = r.Position
		mm.canvas.Position = UDim2.fromOffset((mm.origin.X - pos.X) * MM_SCALE, (mm.origin.Z - pos.Z) * MM_SCALE)
		local look = r.CFrame.LookVector
		mm.arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
		local t = GPS.target()
		if t then
			local dx, dz = (t.pos.X - pos.X) * MM_SCALE, (t.pos.Z - pos.Z) * MM_SCALE
			-- keep the target dot inside the minimap, whatever size the layout gave it
			local ms = HUD.mapSize
			local hx, hz = ms.X / 2 - 7, ms.Y / 2 - 7
			local k = math.max(math.abs(dx) / hx, math.abs(dz) / hz, 1)
			mm.dot.Position = UDim2.new(0.5, dx / k, 0.5, dz / k)
			mm.dot.Visible = true
		else
			mm.dot.Visible = false
		end
	end)
end

return GPS
