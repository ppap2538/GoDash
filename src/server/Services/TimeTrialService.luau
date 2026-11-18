-- A lap of Bueng Kaen Nakhon against the clock (2026-11-19, TikTok toys: "ใครวนบึงเร็วสุด").
-- Gates on the roads round the lake (worked out from the road graph at start-up: the nearest big road out
-- from the lake every 36 degrees, close ones merged; 6 at Bueng Kaen Nakhon); the first is the
-- start/finish, nearest the pier.
-- A rider on a vehicle near the start presses the chip (client/TimeTrial) -> City op "trial_arm"; the clock
-- starts when they pass the start gate, each gate must be passed in order, and the lap ends back at the
-- start. The server checks positions itself (10 times a second) and refuses impossible times.
-- Best laps: d.stats.bestLap and a weekly board (OrderedDataStore, centiseconds, lowest first), shown on
-- the sign at the start.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local Festival = require(ReplicatedStorage.Shared.Config.Festival)
local Data = require(script.Parent.PlayerDataService)
local City = require(script.Parent.CityRemote)
local Metrics = require(script.Parent.MetricsService)
local Board = require(script.Parent.LeaderboardService)
local World = script.Parent.Parent.World
local Kit = require(World.Kit)

local Service = {}
local V3, CF = Vector3.new, CFrame.new
local GATE_R = 26 -- studs: passing a gate
local ARM_R = 110 -- the chip shows this close to the start
local MAX_LAP = 600 -- seconds before a run is dropped
local SUFFIX = RunService:IsStudio() and "_Studio" or ""

local gates = {} :: { { pos: Vector3, dir: Vector3 } }
local runs = {} :: { [Player]: any }
local top = {} :: { { name: string, cs: number } }
local minLap = 30
local boardGui: SurfaceGui? = nil

local function store(week: number)
	return DataStoreService:GetOrderedDataStore(("GoDash_Week%d_lapBKN%s"):format(week, SUFFIX))
end

local function fmt(cs: number): string
	local s = cs / 100
	return ("%d:%05.2f"):format(s // 60, s % 60)
end

-- the gates: from the lake's centre, the nearest big road out past the shore every 36 degrees
local function planGates(world): boolean
	local lake
	for _, l in ipairs(world.lakes or {}) do
		if l.name == Festival.LOY.lake and l.pier then lake = l break end
	end
	if not lake or not world.graph then return false end
	local centre = V3(lake.x, 0, lake.z)
	local path = lake.path
	local found = {}
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		local dir = V3(math.cos(a), 0, math.sin(a))
		-- how far the shore reaches in this direction
		local reach = 0
		for i = 1, #path, 2 do
			local p = V3(path[i] - centre.X, 0, path[i + 1] - centre.Z)
			if p.Magnitude > 1 and p.Unit:Dot(dir) > 0.94 then reach = math.max(reach, p.Magnitude) end
		end
		if reach > 0 then
			local probe = centre + dir * (reach + 60)
			local e, p, _, dist = world.graph:nearest(probe, function(edge) return not edge.minor end)
			if e and dist < 160 then
				table.insert(found, { pos = p, dir = V3(e.dx, 0, e.dz), a = a })
			end
		end
	end
	-- no two gates on top of each other
	local out = {}
	for _, g in ipairs(found) do
		local ok = true
		for _, h in ipairs(out) do
			if (h.pos - g.pos).Magnitude < 90 then ok = false break end
		end
		if ok then table.insert(out, g) end
	end
	if #out < 5 then return false end
	-- start / finish: the gate nearest the pier; then round the lake in bearing order
	local pier = V3(lake.pier.x, 0, lake.pier.z)
	local si, sd = 1, math.huge
	for i, g in ipairs(out) do
		local d = (g.pos - pier).Magnitude
		if d < sd then si, sd = i, d end
	end
	for i = 1, #out do gates[i] = out[(si + i - 2) % #out + 1] end
	-- the fastest believable lap: the gates' ring at 1.4x a superbike's top speed (studs/s ~ km/h here)
	local ring = 0
	for i = 1, #gates do ring += (gates[i % #gates + 1].pos - gates[i].pos).Magnitude end
	minLap = ring / 140
	return true
end

-- published for the clients: ReplicatedStorage.GoDashTrial / Gate1..N (Pos, Dir)
local function publish()
	local f = Instance.new("Folder")
	f.Name = "GoDashTrial"
	for i, g in ipairs(gates) do
		local c = Instance.new("Configuration")
		c.Name = "Gate" .. i
		c:SetAttribute("Index", i)
		c:SetAttribute("Pos", g.pos)
		c:SetAttribute("Dir", g.dir)
		c.Parent = f
	end
	f:SetAttribute("Count", #gates)
	f:SetAttribute("ArmRadius", ARM_R)
	f.Parent = ReplicatedStorage
end

-- the sign beside the start: what it is, and this week's five fastest
local function drawSign()
	local g = gates[1]
	local side = V3(-g.dir.Z, 0, g.dir.X)
	local base = g.pos + side * 16
	local m = Kit.model(Workspace, "LapBoard")
	local cf = CFrame.lookAt(base, base - side) -- facing the road
	Kit.cyl(m, 0.6, 12, cf * CF(-6, 6, 0.4), Kit.COLORS.metalDark, Kit.M.Metal, {})
	Kit.cyl(m, 0.6, 12, cf * CF(6, 6, 0.4), Kit.COLORS.metalDark, Kit.M.Metal, {})
	local board = Kit.part(m, V3(14, 9, 0.5), cf * CF(0, 11, 0), Color3.fromRGB(20, 24, 32), Kit.M.SmoothPlastic, {})
	Kit.nightGlow(board)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.MaxDistance = 300
	gui.Parent = board
	boardGui = gui
	local function label(text: string, y: number, h: number, color: Color3, font: Enum.Font, name: string?)
		local t = Instance.new("TextLabel")
		t.Name = name or "L"
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0.04, y)
		t.Size = UDim2.fromScale(0.92, h)
		t.Font = font
		t.TextScaled = true
		t.TextColor3 = color
		t.Text = text
		t.TextXAlignment = Enum.TextXAlignment.Left
		t:SetAttribute("NoTranslate", true)
		t.Parent = gui
		return t
	end
	label("⏱ แข่งรอบบึงแก่นนคร · LAKE LAP", 0.03, 0.14, Color3.fromRGB(255, 200, 60), Enum.Font.GothamBlack)
	label(("ขี่ผ่านด่านครบ %d ด่าน ใครเร็วสุดประจำสัปดาห์"):format(#gates), 0.18, 0.08, Color3.fromRGB(210, 220, 230), Enum.Font.GothamMedium)
	for i = 1, 5 do
		label(("%d. —"):format(i), 0.28 + (i - 1) * 0.13, 0.11, Color3.new(1, 1, 1), Enum.Font.GothamBold, "Row" .. i)
	end
	-- the start line across the road
	Kit.part(m, V3(1.2, 0.06, 26), CFrame.lookAt(g.pos + V3(0, 0.36, 0), g.pos + V3(0, 0.36, 0) + side), Color3.fromRGB(245, 245, 245), Kit.M.SmoothPlastic,
		{ decor = true, name = "StartLine" })
end

local function refreshBoard()
	local ok, pages = pcall(function() return store(Board.weekId()):GetSortedAsync(true, 5) end)
	if ok and pages then
		local list = {}
		for _, e in ipairs(pages:GetCurrentPage()) do
			local id = tonumber(e.key)
			if id then
				local p = Players:GetPlayerByUserId(id)
				local name = p and p.DisplayName
				if not name then
					local ok2, n = pcall(function() return Players:GetNameFromUserIdAsync(id) end)
					name = ok2 and n or ("Rider " .. id)
				end
				table.insert(list, { name = name, cs = e.value })
			end
		end
		top = list
	end
	if boardGui then
		for i = 1, 5 do
			local row = boardGui:FindFirstChild("Row" .. i) :: TextLabel?
			local e = top[i]
			if row then row.Text = e and ("%d. %s  %s"):format(i, fmt(e.cs), e.name) or ("%d. —"):format(i) end
		end
	end
end

local function vehicleOf(player: Player, vehicles): any
	return vehicles and vehicles.driving(player)
end

function Service.start(world, deps)
	if not planGates(world) then
		warn("[TimeTrial] could not lay out the lake lap")
		return
	end
	publish()
	drawSign()
	task.spawn(function()
		while true do
			refreshBoard()
			task.wait(90)
		end
	end)
	local vehicles = deps and deps.vehicles
	Players.PlayerRemoving:Connect(function(p) runs[p] = nil end)

	City.register("trial_arm", function(player)
		local d = Data.get(player)
		if not d then return false, "" end
		local th = not (d.settings and d.settings.lang == "en")
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not vehicleOf(player, vehicles) then return false, th and "ขึ้นรถก่อน แล้วค่อยเริ่ม" or "Get on a vehicle first" end
		if (root.Position - gates[1].pos).Magnitude > ARM_R + 30 then return false, th and "ไปที่จุดสตาร์ทริมบึงก่อน" or "Go to the start by the lake" end
		runs[player] = { next = 1, t0 = nil, armedAt = os.clock() }
		return true, th and "⏱ พร้อม! ขี่ผ่านเส้นสตาร์ทแล้วนาฬิกาเริ่มเดิน" or "⏱ Ready! The clock starts at the start line"
	end)
	City.register("trial_cancel", function(player)
		runs[player] = nil
		return true, ""
	end)

	-- positions, ten times a second
	task.spawn(function()
		while true do
			task.wait(0.1)
			local now = os.clock()
			for player, run in pairs(runs) do
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local onVehicle = vehicleOf(player, vehicles) ~= nil
				if not player.Parent or not root or not onVehicle or (run.t0 and now - run.t0 > MAX_LAP) or (not run.t0 and now - run.armedAt > 120) then
					runs[player] = nil
					if player.Parent then Net.fire(player, "Notify", "trial", { event = "off" }) end
				else
					local pos = Vector3.new(root.Position.X, 0, root.Position.Z)
					if not run.t0 then
						if (pos - gates[1].pos).Magnitude < GATE_R then
							run.t0 = now
							run.next = 2
							Net.fire(player, "Notify", "trial", { event = "go", next = 2 })
						end
					elseif run.next <= #gates then
						if (pos - gates[run.next].pos).Magnitude < GATE_R then
							run.next += 1
							Net.fire(player, "Notify", "trial", { event = "gate", next = run.next <= #gates and run.next or 1, passed = run.next - 1 })
						end
					elseif (pos - gates[1].pos).Magnitude < GATE_R then
						-- the lap is done
						runs[player] = nil
						local secs = now - run.t0
						local d = Data.get(player)
						if secs < minLap or not d then
							Net.fire(player, "Notify", "trial", { event = "void" })
						else
							local cs = math.floor(secs * 100 + 0.5)
							local best = d.stats.bestLap
							local record = (not best) or best == 0 or cs < best
							if record then
								d.stats.bestLap = cs
								Data.touch(player, "stats")
							end
							-- this week's best goes on the board (it starts again every Monday)
							local wk = Board.weekId()
							if type(d.lapWeek) ~= "table" or d.lapWeek.id ~= wk or cs < (d.lapWeek.cs or math.huge) then
								d.lapWeek = { id = wk, cs = cs }
								Data.touch(player, "lapWeek")
								task.spawn(function()
									pcall(function()
										store(Board.weekId()):UpdateAsync(tostring(player.UserId), function(old)
											if old and old <= cs then return nil end
											return cs
										end)
									end)
									refreshBoard()
								end)
							end
							Metrics.event(player, "Lake lap", secs)
							Net.fire(player, "Notify", "trial", { event = "finish", cs = cs, best = d.stats.bestLap, record = record })
						end
					end
				end
			end
		end
	end)
	print(("[TimeTrial] %d gates round %s, fastest believable lap %.0f s"):format(#gates, Festival.LOY.lake, minLap))
end

return Service
