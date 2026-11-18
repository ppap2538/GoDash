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
local UIS = game:GetService("UserInputService")
local TOUCH = UIS.TouchEnabled and not UIS.KeyboardEnabled
local player = Players.LocalPlayer
local graph
GPS.distance = 0
GPS.name = ""
GPS.path = nil :: { Vector3 }?

local ROAD_COL = {
	highway = Color3.fromRGB(250, 204, 96), main = Color3.fromRGB(244, 246, 248), street = Color3.fromRGB(196, 202, 212), soi = Color3.fromRGB(112, 120, 132),
	lane = Color3.fromRGB(88, 96, 108),
}
local ROAD_PX = { highway = 4, main = 3, street = 2, soi = 1, lane = 1 }
local POI_ICON = {
	hub = "🏠", mall = "🛍", station = "🚉", hospital = "🏥", bus = "🚌", nightmarket = "🏮", police = "🚓", market = "🥬", dealer = "🚗",
	homestore = "🛋", stupa = "🛕", reststop = "⛱", agri = "🌾", seedshop = "🌱", farm = "🚜", gas = "⛽", university = "🎓",
	cafe = "☕", convenience = "🏪", restaurant = "🍜", home = "🏡", checkpoint = "🚨",
	-- 2026-11-18 landmark batch
	government = "🏛", museum = "🏺", citygate = "🚩", stadium = "🏟", school = "🏫",
}
GPS.POI_ICON = POI_ICON

-- Police checkpoints (server/PoliceService): { kind, name, pos, cf (gate centre, looking along the road), width }
function GPS.checkpoints(): { any }
	local out = {}
	local f = ReplicatedStorage:FindFirstChild("GoDashCheckpoints")
	if f then
		for _, v in ipairs(f:GetChildren()) do
			if v:IsA("CFrameValue") then
				table.insert(out, { kind = "checkpoint", name = "Police checkpoint", pos = v.Value.Position, cf = v.Value, width = v:GetAttribute("Width") or 20 })
			end
		end
	end
	return out
end

-- Every place a player can go (owner, 2026-11-16: "every place you can go must be on the map"):
-- the landmarks, every shop, café and restaurant, and the player's own home and allotment.
-- small = a shop, drawn a little smaller so the landmarks still stand out.
function GPS.places(): { any }
	local out = {}
	local w = State.world
	if w then
		for _, p in ipairs(w.pois) do table.insert(out, p) end
		for _, s in ipairs(w.shops or {}) do
			table.insert(out, { id = s.id, kind = s.kind, name = s.name, thai = s.thai, pos = s.pos, small = true })
		end
	end
	if State.plot and State.plot.base then table.insert(out, { kind = "home", name = "My Home", pos = State.plot.base.Position }) end
	if State.farm and State.farm.pos then table.insert(out, { kind = "farm", name = "My Allotment (" .. tostring(State.farm.id) .. ")", pos = State.farm.pos }) end
	return out
end

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
-- The route is a row of arrows flowing along the LEFT lane (Thailand drives on the left), not a
-- band down the middle of the road (owner, 2026-11-16). Each piece is a Beam lying flat on the
-- road with our arrow texture (assets/textures/route_chevron.png).
local ROUTE_TEX = "rbxassetid://77994894090203"
local routeHost: Part? = nil

local function ribbon(a: Vector3, b: Vector3, width: number)
	ribbonUsed += 1
	local it = ribbonPool[ribbonUsed]
	if not it then
		if not routeHost then
			local h = Instance.new("Part")
			h.Name = "Route"
			h.Anchored = true; h.CanCollide = false; h.CanQuery = false; h.CanTouch = false
			h.Transparency = 1
			h.Size = Vector3.new(1, 1, 1)
			h.Parent = folder
			routeHost = h
		end
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Parent = routeHost
		a1.Parent = routeHost
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.FaceCamera = false
		beam.Texture = ROUTE_TEX
		beam.TextureMode = Enum.TextureMode.Static
		beam.TextureLength = 7
		beam.TextureSpeed = -0.9 -- texture lengths per second; negative = toward Attachment0, the far end (measured in Studio 2026-11-16)
		beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		beam.Transparency = NumberSequence.new(0.04)
		beam.LightEmission = 0.2
		beam.LightInfluence = 0.3
		beam.Segments = 1
		beam.ZOffset = 0.05
		beam.Parent = routeHost
		it = { beam = beam, a0 = a0, a1 = a1 }
		ribbonPool[ribbonUsed] = it
	end
	local dir = (b - a).Unit
	-- flat on the road: the attachments' X runs along the route and their Y across it; the arrows in
	-- the texture point from Attachment1 to Attachment0, so Attachment0 is the far end
	local cf = CFrame.fromMatrix(Vector3.zero, dir, dir:Cross(Vector3.yAxis))
	it.a0.WorldCFrame = cf + b
	it.a1.WorldCFrame = cf + a
	it.beam.Width0, it.beam.Width1 = width, width
	it.beam.Enabled = true
end

local function leftOf(d: Vector3): Vector3
	return Vector3.new(d.Z, 0, -d.X) -- +X east, +Z south
end

GPS.lane = nil :: { Vector3 }? -- the route shifted into the left lane (client/AutoDrive follows it)

local function drawRibbon(path: { Vector3 }?, from: Vector3)
	ribbonUsed = 0
	GPS.lane = nil
	if path and #path >= 2 then
		-- how far left of the centre line each piece runs: the middle of the left half of that street
		local n = #path
		local off = table.create(n - 1, 5)
		for i = 1, n - 1 do
			local mid = (path[i] + path[i + 1]) / 2
			if (mid - from).Magnitude < 520 then
				local e = graph:nearest(mid)
				if e then off[i] = math.max(2.6, e.def.width / 4) end
			end
		end
		local pts = table.create(n)
		for i = 1, n do
			local dp = i > 1 and (path[i] - path[i - 1]) or nil
			local dn = i < n and (path[i + 1] - path[i]) or nil
			local lp = dp and dp.Magnitude > 0.1 and leftOf(dp.Unit) or nil
			local ln = dn and dn.Magnitude > 0.1 and leftOf(dn.Unit) or nil
			local o = (off[math.max(1, i - 1)] + off[math.min(n - 1, i)]) / 2
			local shift
			if lp and ln then
				local m = lp + ln
				if m.Magnitude < 0.3 then
					shift = ln * o -- doubling back
				else
					m = m.Unit
					shift = m * (o / math.max(0.5, m:Dot(ln))) -- mitre, so the row of arrows turns the corner in its lane
				end
			else
				shift = (lp or ln or Vector3.zero) * o
			end
			pts[i] = Vector3.new(path[i].X + shift.X, 0.52, path[i].Z + shift.Z)
		end
		GPS.lane = pts
		for i = 1, n - 1 do
			local a, b = pts[i], pts[i + 1]
			-- only what is near enough to be seen
			if ((a - from).Magnitude < 700 or (b - from).Magnitude < 700) and (b - a).Magnitude > 1.5 then
				ribbon(a, b, off[i] < 4 and 3.2 or 4.2)
			end
		end
	end
	for i = ribbonUsed + 1, #ribbonPool do ribbonPool[i].beam.Enabled = false end
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
	-- the name card over the pin (2026-11-18, owner: on a phone it covered the road ahead): smaller on
	-- touch screens, a little see-through, and only shown when you are close (BEACON_LABEL_NEAR); from
	-- far away the light pillar, the route arrows and the minimap show the way
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = TOUCH and UDim2.fromOffset(168, 38) or UDim2.fromOffset(240, 54)
	bb.StudsOffset = Vector3.new(0, 14, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 1e6
	bb.Parent = beacon
	local card = UI.new("Frame", { BackgroundColor3 = C.green, BackgroundTransparency = 0.12, Size = UDim2.fromScale(1, 1), Parent = bb })
	UI.corner(card, TOUCH and 12 or 16)
	UI.stroke(card, C.white, TOUCH and 1.5 or 2)
	beaconLabel = UI.label(card, "", TOUCH and 12 or 15, C.white, F.bold, { Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(6, 0), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
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
	local shown = GPS.places()
	for _, cp in ipairs(GPS.checkpoints()) do table.insert(shown, cp) end
	for _, p in ipairs(shown) do
		if (p.pos - pos).Magnitude < 1700 then
			local px = p.small and 14 or 18
			local l = UI.label(canvas, POI_ICON[p.kind] or "📍", p.small and 10 or 13, C.white, F.med, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(px, px),
				Position = UDim2.new(0.5, (p.pos.X - pos.X) * MM_SCALE, 0.5, (p.pos.Z - pos.Z) * MM_SCALE), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = p.small and 7 or 8 })
			l:SetAttribute("NoTranslate", true)
			table.insert(mm.icons, l)
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
	-- The map turns with you: what is ahead is at the top (owner, 2026-11-16). A rotated frame is not
	-- clipped by ClipsDescendants, so the turning part lives in a CanvasGroup, which clips anything.
	local clip = UI.new("CanvasGroup", { Name = "Clip", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = holder })
	UI.corner(clip, UI.R.lg)
	mm.rotor = UI.new("Frame", { Name = "Rotor", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Parent = clip })
	mm.canvas = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = mm.rotor })
	mm.arrow = UI.label(holder, "▲", 16, C.green, F.black, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 20, TextStrokeTransparency = 0, TextStrokeColor3 = C.white })
	mm.dot = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(0, 220, 120), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), ZIndex = 19, Visible = false, Parent = holder })
	UI.corner(mm.dot, 6)
	UI.stroke(mm.dot, C.white, 2)
	mm.north = UI.label(holder, "N", 11, Color3.fromRGB(255, 120, 110), F.black, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), ZIndex = 21,
		TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3 })
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
		if not e.minor then
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
	task.spawn(function() -- checkpoints move: redraw the icons when they do
		local f = ReplicatedStorage:WaitForChild("GoDashCheckpoints", 60)
		if not f then return end
		local function dirty() mm.origin = Vector3.new(1e9, 0, 0) end
		f.ChildAdded:Connect(dirty)
		f.ChildRemoved:Connect(dirty)
		dirty()
	end)

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
					local away = Util.flatDist(pos, t.pos)
					beaconLabel.Text = (t.label or Lang.t(t.name)) .. "\n" .. Lang.t(Util.dist(away))
					beacon.Label.Enabled = away < (TOUCH and 260 or 520)
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

	local heading = 0
	RunService.RenderStepped:Connect(function(dt)
		local char = player.Character
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if not r or not mm.canvas then return end
		local pos = r.Position
		mm.canvas.Position = UDim2.fromOffset((mm.origin.X - pos.X) * MM_SCALE, (mm.origin.Z - pos.Z) * MM_SCALE)
		-- heading = where the view is pointing (on a vehicle the camera sits behind it); the map turns
		-- the other way so that direction is always up, and the arrow in the middle stays pointing up
		local cam = Workspace.CurrentCamera
		local look = cam and cam.CFrame.LookVector or r.CFrame.LookVector
		if look.X * look.X + look.Z * look.Z < 0.05 then look = r.CFrame.LookVector end -- looking straight down
		local want = math.atan2(look.X, -look.Z)
		local diff = (want - heading + math.pi) % (2 * math.pi) - math.pi
		heading += diff * math.min(1, dt * 10)
		local deg = math.deg(heading)
		mm.rotor.Rotation = -deg
		mm.arrow.Rotation = 0
		for _, l in ipairs(mm.icons) do l.Rotation = deg end -- place icons stay upright
		local ms = HUD.mapSize
		local c, sn = math.cos(-heading), math.sin(-heading)
		do
			-- N rides the edge of the map toward north
			local nx, ny = sn, -c
			local k = math.min((ms.X / 2 - 10) / math.max(math.abs(nx), 0.001), (ms.Y / 2 - 10) / math.max(math.abs(ny), 0.001))
			mm.north.Position = UDim2.new(0.5, nx * k, 0.5, ny * k)
		end
		local t = GPS.target()
		if t then
			local wx, wz = (t.pos.X - pos.X) * MM_SCALE, (t.pos.Z - pos.Z) * MM_SCALE
			local dx, dz = wx * c - wz * sn, wx * sn + wz * c
			-- keep the target dot inside the minimap, whatever size the layout gave it
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
