-- Weekly "Top Riders" (2026-11-17 growth plan: a reason to come back and to beat friends).
-- Three boards that start again every Monday 00:00 Thai time: money earned from jobs, jobs done, and
-- five-star jobs. Each rider's week totals live in the profile (d.week); they are written to one
-- OrderedDataStore per board and week within 30 s of a change and on leaving, and the top ten are read
-- back every 90 seconds. The phone app (client/Board) and the board at the rider hub show them.
-- Studio play tests use their own stores (suffix "_Studio"), like the profiles.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Data = require(script.Parent.PlayerDataService)
local City = require(script.Parent.CityRemote)

local Board = {}
Board.STATS = { "earned", "jobs", "five" }
local SUFFIX = RunService:IsStudio() and "_Studio" or ""
local TOP = 10

local tops = { earned = {}, jobs = {}, five = {} } -- { { id, name, value } }
local dirty = {} :: { [Player]: boolean }
local names = {} :: { [number]: string }
local onChange = {} :: { () -> () }

-- Weeks since the Unix epoch, starting Monday 00:00 in Thailand (UTC+7); 1 Jan 1970 was a Thursday.
function Board.weekId(t: number?): number
	return math.floor(((t or os.time()) + 7 * 3600 + 3 * 86400) / (7 * 86400))
end

-- Seconds until the boards start again.
function Board.secondsLeft(): number
	local t = os.time() + 7 * 3600 + 3 * 86400
	return 7 * 86400 - t % (7 * 86400)
end

local function store(stat: string, week: number)
	return DataStoreService:GetOrderedDataStore(("GoDash_Week%d_%s%s"):format(week, stat, SUFFIX))
end

local function mine(d)
	local w = Board.weekId()
	if type(d.week) ~= "table" or d.week.id ~= w then d.week = { id = w, earned = 0, jobs = 0, five = 0 } end
	return d.week
end

-- A finished job: money paid (pay + tip) and its stars.
function Board.job(player: Player, money: number, stars: number)
	local d = Data.get(player)
	if not d then return end
	local wk = mine(d)
	wk.earned += math.max(0, math.floor(money))
	wk.jobs += 1
	if stars >= 4.8 then wk.five += 1 end
	Data.touch(player, "week")
	dirty[player] = true
end

local function nameOf(id: number): string
	if names[id] then return names[id] end
	local p = Players:GetPlayerByUserId(id)
	if p then names[id] = p.DisplayName return names[id] end
	local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(id) end)
	names[id] = ok and n or ("Rider " .. id)
	return names[id]
end

local function flush(player: Player)
	local d = Data.get(player)
	if not d or not dirty[player] then return end
	dirty[player] = nil
	local wk = mine(d)
	for _, stat in ipairs(Board.STATS) do
		local v = wk[stat] or 0
		if v > 0 then
			pcall(function() store(stat, wk.id):SetAsync(tostring(player.UserId), v) end)
		end
	end
end

local function refresh()
	local w = Board.weekId()
	for _, stat in ipairs(Board.STATS) do
		local ok, pages = pcall(function() return store(stat, w):GetSortedAsync(false, TOP) end)
		if ok and pages then
			local list = {}
			for _, e in ipairs(pages:GetCurrentPage()) do
				local id = tonumber(e.key)
				if id then table.insert(list, { id = id, name = nameOf(id), value = e.value }) end
			end
			tops[stat] = list
		end
	end
	-- riders in this server count at once, before their next write
	for _, p in ipairs(Players:GetPlayers()) do
		local d = Data.get(p)
		if d and type(d.week) == "table" and d.week.id == w then
			for _, stat in ipairs(Board.STATS) do
				local v = d.week[stat] or 0
				if v > 0 then
					local list = tops[stat]
					local found = false
					for _, e in ipairs(list) do
						if e.id == p.UserId then e.value = math.max(e.value, v); found = true end
					end
					if not found then table.insert(list, { id = p.UserId, name = p.DisplayName, value = v }) end
					table.sort(list, function(a, b) return a.value > b.value end)
					while #list > TOP do table.remove(list) end
				end
			end
		end
	end
	for _, fn in ipairs(onChange) do task.spawn(fn) end
end

function Board.top(stat: string) return tops[stat] or {} end
function Board.onChange(fn: () -> ()) table.insert(onChange, fn) end

-- The big board at the rider hub, turned toward the spawn: top five on each board, both languages.
local function hubBoard(world)
	local hub = world and world.pois and world.pois.hub
	if not hub or not hub.base then return end
	local w, d = hub.w or 60, hub.d or 60
	-- front right of the lot, clear of the canopy and its pillars (they stand at d/2 - 40)
	local at = (hub.base * CFrame.new(w / 2 - 7, 0, -d / 2 + 17)).Position
	local face = (hub.base * CFrame.new(0, 0, -d / 2 + 12)).Position
	local look = Vector3.new(face.X - at.X, 0, face.Z - at.Z)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.zAxis
	local cf = CFrame.lookAt(Vector3.new(at.X, 0.3, at.Z), Vector3.new(at.X, 0.3, at.Z) + look)
	local m = Instance.new("Model")
	m.Name = "TopRidersBoard"
	local function part(size: Vector3, c: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = c
		p.Color = color
		p.Material = mat
		if shape then p.Shape = shape end
		p.CanQuery = false
		p.Parent = m
		return p
	end
	for _, sx in ipairs({ -7.2, 7.2 }) do
		part(Vector3.new(14, 0.7, 0.7), cf * CFrame.new(sx, 7, 0.4) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 64, 70), Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	part(Vector3.new(17, 11, 0.6), cf * CFrame.new(0, 9, 0.2), Color3.fromRGB(150, 110, 20), Enum.Material.Metal)
	local panel = part(Vector3.new(16.4, 10.4, 0.2), cf * CFrame.new(0, 9, -0.15), Color3.fromRGB(22, 26, 32), Enum.Material.SmoothPlastic)
	panel.CanCollide = false
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.MaxDistance = 240
	sg.Parent = panel
	local function label(parent: Instance, text: string, size: number, color: Color3, pos: UDim2, dim: UDim2, align: Enum.TextXAlignment?): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Text = text
		l.TextSize = size
		l.TextColor3 = color
		l.Font = Enum.Font.GothamBold
		l.Position = pos
		l.Size = dim
		l.TextXAlignment = align or Enum.TextXAlignment.Left
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.Parent = parent
		return l
	end
	local white, gold, dim = Color3.new(1, 1, 1), Color3.fromRGB(255, 200, 70), Color3.fromRGB(170, 176, 186)
	label(sg, "🏆 ไรเดอร์ยอดเยี่ยมประจำสัปดาห์ · TOP RIDERS", 34, gold, UDim2.fromOffset(20, 14), UDim2.new(1, -40, 0, 44), Enum.TextXAlignment.Center)
	local cols = {}
	local heads = { { "earned", "💰 รายได้ · Money" }, { "jobs", "📦 งาน · Jobs" }, { "five", "⭐ 5 ดาว · 5 stars" } }
	for i, h in ipairs(heads) do
		local col = Instance.new("Frame")
		col.BackgroundColor3 = Color3.fromRGB(34, 40, 48)
		col.Position = UDim2.new((i - 1) / 3, 10, 0, 70)
		col.Size = UDim2.new(1 / 3, -20, 1, -120)
		col.Parent = sg
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 14)
		corner.Parent = col
		label(col, h[2], 22, white, UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 30), Enum.TextXAlignment.Center)
		local rows = {}
		for r = 1, 5 do
			local y = 46 + (r - 1) * 42
			rows[r] = {
				name = label(col, "", 20, r == 1 and gold or white, UDim2.fromOffset(12, y), UDim2.new(0.62, -12, 0, 36)),
				value = label(col, "", 20, dim, UDim2.new(0.62, 0, 0, y), UDim2.new(0.38, -12, 0, 36), Enum.TextXAlignment.Right),
			}
		end
		cols[h[1]] = rows
	end
	local foot = label(sg, "", 18, dim, UDim2.new(0, 20, 1, -44), UDim2.new(1, -40, 0, 30), Enum.TextXAlignment.Center)
	local function draw()
		for stat, rows in pairs(cols) do
			local list = tops[stat] or {}
			for r = 1, 5 do
				local e = list[r]
				local medal = ({ "🥇", "🥈", "🥉" })[r] or (r .. ".")
				rows[r].name.Text = e and (medal .. " " .. e.name) or (r == 1 and "ยังว่าง · open" or "")
				rows[r].value.Text = e and (stat == "earned" and ("฿" .. tostring(math.floor(e.value))) or tostring(math.floor(e.value))) or ""
			end
		end
		local s = Board.secondsLeft()
		foot.Text = ("ดูทั้งหมดในมือถือ → อันดับไรเดอร์  ·  รีเซ็ตทุกวันจันทร์ (อีก %d วัน %d ชม.)"):format(math.floor(s / 86400), math.floor(s % 86400 / 3600))
	end
	draw()
	Board.onChange(draw)
	local folder = workspace:FindFirstChild("Interactions") or workspace
	m.Parent = folder
end

function Board.start(world)
	local okBoard, err = pcall(hubBoard, world)
	if not okBoard then warn("[Board] hub board: " .. tostring(err)) end
	City.register("board", function(player)
		local d = Data.get(player)
		local wk = d and mine(d) or { earned = 0, jobs = 0, five = 0 }
		return true, "", { tops = tops, me = { earned = wk.earned, jobs = wk.jobs, five = wk.five }, left = Board.secondsLeft() }
	end)
	Players.PlayerRemoving:Connect(function(p)
		flush(p)
		dirty[p] = nil
	end)
	Data.onRelease(function(p) flush(p) end)
	task.spawn(function()
		task.wait(8)
		refresh()
		local last = os.clock()
		while true do
			task.wait(30)
			for _, p in ipairs(Players:GetPlayers()) do
				if dirty[p] then flush(p) end
			end
			if os.clock() - last >= 90 then
				last = os.clock()
				refresh()
			end
		end
	end)
end

return Board
