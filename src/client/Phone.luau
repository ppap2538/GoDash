-- The GoDash smartphone: ten apps plus the shop / service screens that world prompts open.
-- Every button calls the server and shows its answer; nothing here changes state by itself.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Vehicles = require(Shared.Config.Vehicles)
local Items = require(Shared.Config.Items)
local Crops = require(Shared.Config.Crops)
local Housing = require(Shared.Config.Housing)
local Jobs = require(Shared.Config.Jobs)
local Missions = require(Shared.Config.Missions)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local UI = require(script.Parent.UI.Kit)
local Layout = require(script.Parent.UI.Core.Layout)
local Layers = require(script.Parent.UI.Core.Layers)
local UIState = require(script.Parent.UI.Core.UIState)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)
local HUD = require(script.Parent.HUD)
local GPS = require(script.Parent.GPS)
local Radio = require(script.Parent.Radio)
local Lang = require(script.Parent.Lang)

local Phone = {}
local C, F = UI.C, UI.F
local player = Players.LocalPlayer
local gui, shell, content, header, titleLabel, backBtn
local open = false
local current = { name = "home", arg = nil }
local stack = {}
local screens = {}
Phone.onBuild = nil :: (() -> ())? -- set by Build

-- The shell fills the RightPanel dock (see UI/Core/Layout); it slides in from past the edge.
local SHELL_OPEN = UDim2.new(0, 0, 0, 0)
local SHELL_CLOSED = UDim2.new(0, Layout.PHONE_W + 200, 0, 0)

local APPS = {
	{ id = "godash", name = "GoDash", icon = "🛵", color = C.green },
	{ id = "gps", name = "Maps", icon = "🗺", color = C.blue },
	{ id = "garage", name = "Garage", icon = "🚗", color = Color3.fromRGB(90, 100, 120) },
	{ id = "property", name = "Property", icon = "🏡", color = Color3.fromRGB(230, 130, 60) },
	{ id = "farming", name = "Farming", icon = "🌾", color = Color3.fromRGB(110, 170, 70) },
	{ id = "inventory", name = "Bag", icon = "🎒", color = Color3.fromRGB(170, 110, 70) },
	{ id = "bank", name = "Bank", icon = "🏦", color = Color3.fromRGB(60, 130, 200) },
	{ id = "profile", name = "Profile", icon = "👤", color = C.purple },
	{ id = "missions", name = "Missions", icon = "🎯", color = C.red },
	{ id = "radio", name = "Radio", icon = "📻", color = Color3.fromRGB(200, 80, 140) },
	{ id = "settings", name = "Settings", icon = "⚙️", color = Color3.fromRGB(110, 118, 130) },
}

---------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------
-- Where the server sends you when you are in the wrong place: the answer sets the route there
-- (owner, 2026-11-16: "KK Motors must show the way").
local GO_HINTS = {
	["Visit KK Motors to buy vehicles"] = { "dealer" }, ["Upgrades are fitted at KK Motors"] = { "dealer" },
	["Paint jobs are done at KK Motors"] = { "dealer" }, ["Repairs are done at KK Motors or a fuel station"] = { "gas", "dealer" },
	["Go to the hospital"] = { "hospital" }, ["Go to the stupa"] = { "stupa" }, ["Go to the police station"] = { "police" },
	["Go to your allotment at the Community Farm"] = "farm", ["Go to your plot to build"] = "plot",
}

-- Route to the nearest place of one of `kinds`; true when a route was set.
local function navTo(kinds: { string }): boolean
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local here = r and r.Position or Vector3.zero
	local best, bd
	for _, p in ipairs(GPS.places()) do
		if table.find(kinds, p.kind) then
			local d = (p.pos - here).Magnitude
			if not bd or d < bd then best, bd = p, d end
		end
	end
	if not best then return false end
	GPS.setTarget(best.pos, Lang.name(best))
	Feedback.toast(Lang.pick("📍 Route set: follow the arrows to ", "📍 นำทางให้แล้ว ขี่ตามลูกศรไป ") .. Lang.name(best) .. " · " .. Lang.t(Util.dist(bd)), "good")
	return true
end

local function call(remote: string, ...): boolean
	local ok, msg = Net.call(remote, ...)
	if msg and msg ~= "" then Feedback.toast(msg, ok and "good" or "bad") end
	if ok then Feedback.good() end
	local hint = (not ok) and msg and GO_HINTS[msg]
	if hint then
		local routed = false
		if hint == "farm" and State.farm then
			GPS.setTarget(State.farm.pos, "My Allotment"); routed = true
		elseif hint == "plot" and State.plot then
			GPS.setTarget(State.plot.base.Position, "My Home"); routed = true
		elseif type(hint) == "table" then
			routed = navTo(hint)
		end
		if routed then task.delay(0.9, function() Phone.setOpen(false) end) end -- show the road, not the phone
	end
	return ok == true
end

local function section(text: string, order: number?)
	return UI.label(content, text, 12, C.sub, F.bold, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order or 0 })
end

-- Card row: icon, title, subtitle and an optional button on the right.
local function row(icon: string, title: string, sub: string?, btnText: string?, onClick: (() -> ())?, opts: any?)
	local o = opts or {}
	local h = o.height or (sub and 58 or 46)
	local card = UI.card(content, { Size = UDim2.new(1, 0, 0, h), LayoutOrder = o.order or 0 })
	local x = 12
	if icon ~= "" then
		UI.label(card, icon, 24, C.text, F.med, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0, 36, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
		x = 48
	end
	local rightW = btnText and (o.btnWidth or 84) + 10 or 8
	if btnText and o.btn2 then rightW += (o.btn2.width or 60) + 6 end
	UI.label(card, title, 14, o.titleColor or C.text, F.bold, { Position = UDim2.fromOffset(x, sub and 9 or 0), Size = UDim2.new(1, -x - rightW, sub and 0 or 1, sub and 18 or 0) })
	if sub then
		UI.label(card, sub, 12, C.sub, F.med, { Position = UDim2.fromOffset(x, 28), Size = UDim2.new(1, -x - rightW, 0, 22), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	if btnText then
		local b = UI.button(card, btnText, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(o.btnWidth or 84, 32), TextSize = 13,
			BackgroundColor3 = o.btnColor or C.green, TextColor3 = o.btnTextColor or C.white }, onClick)
		if o.disabled then b.BackgroundColor3 = C.line; b.TextColor3 = C.sub; b.Active = false end
		-- optional second, quieter button to the left of the main one: { text, fn, width? }
		if o.btn2 then
			local b2 = UI.button(card, o.btn2.text, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8 - (o.btnWidth or 84) - 6, 0.5, 0),
				Size = UDim2.fromOffset(o.btn2.width or 60, 32), TextSize = 12, BackgroundColor3 = C.chip, TextColor3 = C.white }, o.btn2.fn)
			if o.disabled then b2.BackgroundColor3 = C.line; b2.TextColor3 = C.sub; b2.Active = false end
		end
	end
	return card
end

local function statBar(parent: Instance, label: string, value: number, max: number, text: string, color: Color3, y: number)
	UI.label(parent, label, 11, C.sub, F.med, { Position = UDim2.fromOffset(12, y), Size = UDim2.fromOffset(74, 14) })
	local track, set = UI.bar(parent, color, 6)
	track.Position = UDim2.fromOffset(88, y + 4); track.Size = UDim2.new(1, -150, 0, 6)
	track.BackgroundColor3 = C.black; track.BackgroundTransparency = 0.9
	set(value / max)
	UI.label(parent, text, 11, C.text, F.bold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, y), Size = UDim2.fromOffset(48, 14), TextXAlignment = Enum.TextXAlignment.Right })
end

local function bigCard(height: number, color: Color3?, order: number?): Frame
	return UI.card(content, { Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = color or C.card, LayoutOrder = order or 0 })
end

local function near(pos: Vector3?, range: number): boolean
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return pos ~= nil and r ~= nil and (r.Position - pos).Magnitude <= range
end

---------------------------------------------------------------------------------------------------
-- navigation
---------------------------------------------------------------------------------------------------
local function render()
	if not open then return end
	local fn = screens[current.name] or screens.home
	local keep = content.CanvasPosition
	UI.clear(content)
	local app
	for _, a in ipairs(APPS) do
		if a.id == current.name then app = a end
	end
	titleLabel.Text = app and app.name or (current.title or "GoDash Phone")
	header.BackgroundColor3 = app and app.color or (current.color or C.dark)
	backBtn.Visible = current.name ~= "home"
	local ok, err = pcall(fn, current.arg)
	if not ok then
		warn("[Phone] " .. current.name .. " failed: " .. tostring(err))
		UI.label(content, "This screen had a problem.", 13, C.red, F.med)
	end
	content.CanvasPosition = keep
end

local function go(name: string, arg: any?, title: string?, color: Color3?)
	table.insert(stack, current)
	current = { name = name, arg = arg, title = title, color = color }
	content.CanvasPosition = Vector2.zero
	render()
end
Phone.go = go

local function back()
	local prev = table.remove(stack)
	current = prev or { name = "home" }
	content.CanvasPosition = Vector2.zero
	render()
end

function Phone.setOpen(v: boolean)
	if open == v then return end
	open = v
	-- UIState docks the phone: the HUD re-flows beside it (or declutters on small screens)
	UIState.set("phone", v)
	-- Roblox's player list sits on top of the phone's header: put it away while the phone is open
	pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, not v) end)
	if v then
		shell.Visible = true
		shell.Position = SHELL_CLOSED
		UI.tween(shell, 0.3, { Position = SHELL_OPEN }, Enum.EasingStyle.Back)
		render()
	else
		local t = UI.tween(shell, 0.2, { Position = SHELL_CLOSED }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		t.Completed:Once(function() if not open then shell.Visible = false end end)
	end
	Feedback.click()
end

function Phone.isOpen(): boolean return open end

-- Other modules add their own apps and screens (client/Feed, client/Finance, ...).
-- app = { id, name, icon, color, badge? }; fn(arg) draws the screen with Phone.ui helpers.
function Phone.addApp(app, fn)
	for _, a in ipairs(APPS) do
		if a.id == app.id then return end
	end
	table.insert(APPS, app)
	screens[app.id] = fn
end
function Phone.addScreen(name: string, fn) screens[name] = fn end
function Phone.current(): string return current.name end
function Phone.refresh() if open then render() end end
Phone.ui = {
	row = function(...) return row(...) end,
	section = function(...) return section(...) end,
	bigCard = function(...) return bigCard(...) end,
	call = function(...) return call(...) end,
	content = function() return content end,
}

---------------------------------------------------------------------------------------------------
-- home
---------------------------------------------------------------------------------------------------
screens.home = function()
	local d = State.data
	local hero = bigCard(74, C.dark)
	UI.label(hero, "Sawasdee, " .. player.DisplayName, 16, C.white, F.black, { Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 22) })
	UI.label(hero, d and ("Lv %d · %s · ★ %.2f"):format(d.level, Util.money(d.money), d.rating) or "Loading…", 13, Color3.fromRGB(190, 198, 208), F.med,
		{ Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 20) })
	local grid = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, math.ceil(#APPS / 4) * 96 + 10), Parent = content })
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.new(0.25, -8, 0, 84)
	g.CellPadding = UDim2.fromOffset(10, 12)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = grid
	for i, app in ipairs(APPS) do
		local cell = UI.new("Frame", { BackgroundTransparency = 1, LayoutOrder = i, Parent = grid })
		local b = UI.button(cell, app.icon, { Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = app.color, TextSize = 30 }, function() go(app.id) end)
		UI.corner(b, 18)
		UI.label(cell, app.name, 11, C.text, F.bold, { Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center })
		-- red dot: something new (apps added by other modules pass badge = function() -> boolean)
		if app.badge and app.badge() then
			local dot = UI.new("Frame", { BackgroundColor3 = C.red, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, -2), Size = UDim2.fromOffset(14, 14), ZIndex = 3, Parent = cell })
			UI.corner(dot, 7); UI.stroke(dot, C.white, 2)
		end
		-- red dot: something to claim
		if app.id == "missions" and d then
			local claimable = d.dailyReward.day ~= Util.dayNumber()
			for id, st in pairs(d.missions.career) do
				if not st.claimed and Missions.ById[id] and st.progress >= Missions.ById[id].goal then claimable = true end
			end
			for _, st in ipairs(d.missions.daily) do
				if not st.claimed and Missions.ById[st.id] and st.progress >= Missions.ById[st.id].goal then claimable = true end
			end
			if claimable then
				local dot = UI.new("Frame", { BackgroundColor3 = C.red, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, -2), Size = UDim2.fromOffset(14, 14), ZIndex = 3, Parent = cell })
				UI.corner(dot, 7); UI.stroke(dot, C.white, 2)
			end
		end
	end
	if State.world and State.world.mock then
		UI.label(content, "Test session: progress is kept in memory only.", 11, C.sub, F.med, { TextXAlignment = Enum.TextXAlignment.Center })
	end
end

---------------------------------------------------------------------------------------------------
-- GoDash driver app
---------------------------------------------------------------------------------------------------
screens.godash = function()
	local d, job = State.data, State.job
	if not d then return end
	local on = job.online
	local hero = bigCard(118, on and C.green or C.dark)
	UI.label(hero, on and "You're ONLINE" or "You're offline", 19, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) })
	UI.label(hero, on and (job.job and "On a job — follow the GPS" or job.offer and "New job offer!" or "Looking for jobs near you…") or "Go online to receive orders", 13, C.white, F.med,
		{ Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 18) })
	UI.button(hero, on and "Go Offline" or "GO ONLINE", { Position = UDim2.fromOffset(14, 66), Size = UDim2.new(1, -28, 0, 40), BackgroundColor3 = C.white, TextColor3 = on and C.red or C.greenDark, TextSize = 16 }, function()
		Net.send("JobSetOnline", not on, job.mode)
	end)
	section("JOB TYPE")
	local modes = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = content })
	UI.list(modes, 6, true)
	for _, m in ipairs({ { "food", "🍱 Food" }, { "ride", "🧍 Rides" }, { "both", "Both" } }) do
		local sel = job.mode == m[1]
		local locked = m[1] ~= "food" and d.level < Game.UNLOCKS.ride
		UI.button(modes, locked and ("🔒 Lv " .. Game.UNLOCKS.ride) or m[2], { Size = UDim2.new(1 / 3, -4, 1, 0), TextSize = 13, BackgroundColor3 = sel and C.green or C.card, TextColor3 = sel and C.white or C.text }, function()
			if locked then Feedback.toast("Ride-hailing unlocks at level " .. Game.UNLOCKS.ride, "bad") return end
			Net.send("JobSetOnline", on, m[1])
		end)
	end
	if job.job then
		local j = job.job
		section("CURRENT JOB")
		row(j.icon, j.name .. " · " .. Util.money(j.pay), (j.stage == "pickup" and "Go to " .. j.pickup.name or "Deliver to " .. j.dropoff.name) .. " · " .. j.item)
	end
	section("TODAY")
	local today = bigCard(64)
	local daily = d.daily.day == Util.dayNumber() and d.daily or { income = 0, jobs = 0 }
	for i, st in ipairs({ { Util.money(daily.income), "Income" }, { tostring(daily.jobs), "Jobs" }, { ("★ %.2f"):format(d.rating), "Rating" } }) do
		UI.label(today, st[1], 17, C.text, F.black, { Position = UDim2.new((i - 1) / 3, 0, 0, 12), Size = UDim2.new(1 / 3, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
		UI.label(today, st[2], 11, C.sub, F.med, { Position = UDim2.new((i - 1) / 3, 0, 0, 36), Size = UDim2.new(1 / 3, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center })
	end
	section("JOBS YOU CAN GET")
	local function list(tbl, mode)
		local arr = {}
		for _, def in pairs(tbl) do table.insert(arr, def) end
		table.sort(arr, function(a, b) return a.level < b.level end)
		for _, def in ipairs(arr) do
			local lock = d.level < def.level
			local need = def.cargo and def.cargo > 2 and (" · cargo " .. def.cargo .. "+") or (def.seats and def.seats > 1 and (" · " .. def.seats .. " seats") or "")
			-- landmark jobs only come at their hours (server/CivicJobs): show them
			local hrs = ""
			if def.hours then
				local parts = {}
				for _, w in ipairs(def.hours) do
					local function hm(x) return ("%d:%02d"):format(math.floor(x) % 24, math.floor((x % 1) * 60 + 0.5)) end
					table.insert(parts, hm(w[1]) .. "–" .. hm(w[2]))
				end
				hrs = " · 🕘 " .. table.concat(parts, ", ")
			end
			row(def.icon, def.name, lock and ("Unlocks at level " .. def.level) or ("฿" .. def.base .. " + distance · +" .. def.exp .. " EXP" .. need .. (def.rainOnly and " · rain only" or "") .. hrs),
				nil, nil, { titleColor = lock and C.sub or C.text })
		end
	end
	list(Jobs.FOOD, "food")
	list(Jobs.RIDE, "ride")
end

---------------------------------------------------------------------------------------------------
-- Maps
---------------------------------------------------------------------------------------------------
-- The places list: everything you can go to, nearest first, with a category filter.
local PLACE_FILTERS = {
	{ id = "all", label = "All" }, { id = "food", label = "🍜 Food" }, { id = "shop", label = "🛍 Shops" }, { id = "service", label = "🏥 Services" },
}
local PLACE_GROUP = {
	restaurant = "food", cafe = "food", market = "food", nightmarket = "food", reststop = "food",
	convenience = "shop", mall = "shop", homestore = "shop", seedshop = "shop", agri = "shop", dealer = "shop", gas = "shop",
}
local placeFilter = "all"

screens.gps = function()
	local w = State.world
	local mapCard = bigCard(300, Color3.fromRGB(36, 42, 50))
	mapCard.ClipsDescendants = true
	task.defer(function()
		if not mapCard.Parent then return end
		local canvas, toPoint = GPS.drawCity(mapCard)
		local char = player.Character
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if w then
			local shown = GPS.places()
			for _, cp in ipairs(GPS.checkpoints()) do table.insert(shown, cp) end
			for _, p in ipairs(shown) do
				local b = UI.new("TextButton", { Text = GPS.POI_ICON[p.kind] or "📍", TextSize = p.small and 11 or 14, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(p.small and 16 or 22, p.small and 16 or 22), Position = toPoint(p.pos), ZIndex = p.small and 8 or 9, Parent = canvas })
				b:SetAttribute("NoTranslate", true)
				b.MouseButton1Click:Connect(function()
					if p.kind == "checkpoint" then Feedback.toast(Lang.pick("🚨 Police checkpoint: drive round it, or pay a fine", "🚨 ด่านตรวจ: ขับหลบไป ไม่งั้นโดนปรับ"), "bad") return end
					GPS.setTarget(p.pos, Lang.name(p))
					Feedback.toast("📍 Route set to " .. Lang.name(p), "good")
				end)
			end
		end
		local t = GPS.target()
		if t then
			local dot = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(0, 220, 120), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), Position = toPoint(t.pos), ZIndex = 11, Parent = canvas })
			UI.corner(dot, 6); UI.stroke(dot, C.white, 2)
		end
		if r then
			UI.label(canvas, "▲", 14, C.green, F.black, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18), Position = toPoint(r.Position), TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 12, TextStrokeTransparency = 0, TextStrokeColor3 = C.white, Rotation = math.deg(math.atan2(r.CFrame.LookVector.X, -r.CFrame.LookVector.Z)) })
		end
	end)
	local t = GPS.target()
	if t then
		row("📍", "Navigating to " .. t.name, Util.dist(GPS.distance) .. " by road", (not t.job) and "Clear" or nil, function() GPS.setTarget(nil); render() end, { btnColor = C.red })
	end
	UI.label(content, "Map data © OpenStreetMap contributors", 10, C.sub, F.med, { TextXAlignment = Enum.TextXAlignment.Center })
	if w then
		-- one tap to the closest fuel station
		local char0 = player.Character
		local r0 = char0 and char0:FindFirstChild("HumanoidRootPart")
		local nearest, nd
		for _, p in ipairs(w.pois) do
			if p.kind == "gas" and r0 then
				local dd = (p.pos - r0.Position).Magnitude
				if not nearest or dd < nd then nearest, nd = p, dd end
			end
		end
		if nearest then
			row("⛽", "Nearest fuel station", Lang.name(nearest) .. " · " .. Util.dist(nd) .. " away", "Go", function()
				GPS.setTarget(nearest.pos, Lang.name(nearest))
				Feedback.toast("📍 Route set to " .. Lang.name(nearest), "good")
				render()
			end, { btnWidth = 56, btnColor = C.orange })
		end
	end
	section("PLACES")
	if not w then UI.label(content, "Loading places…", 13, C.sub) return end
	local chips = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = content })
	UI.list(chips, 6, true)
	for _, c in ipairs(PLACE_FILTERS) do
		local sel = placeFilter == c.id
		UI.button(chips, c.label, { Size = UDim2.new(0.25, -5, 1, 0), TextSize = 12, BackgroundColor3 = sel and C.green or C.card, TextColor3 = sel and C.white or C.text }, function()
			placeFilter = c.id
			render()
		end)
	end
	local list = {}
	for _, p in ipairs(GPS.places()) do
		if placeFilter == "all" or PLACE_GROUP[p.kind] == placeFilter or (placeFilter == "service" and not PLACE_GROUP[p.kind]) then table.insert(list, p) end
	end
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	local here = r and r.Position or Vector3.zero
	table.sort(list, function(a, b) return (a.pos - here).Magnitude < (b.pos - here).Magnitude end)
	for _, p in ipairs(list) do
		row(p.kind == "home" and "🏡" or (GPS.POI_ICON[p.kind] or "📍"), Lang.name(p), Util.dist((p.pos - here).Magnitude) .. " away", "Go", function()
			GPS.setTarget(p.pos, Lang.name(p))
			Feedback.toast("📍 Route set to " .. Lang.name(p), "good")
			render()
		end, { btnWidth = 56 })
	end
end

---------------------------------------------------------------------------------------------------
-- Garage / dealer / service
---------------------------------------------------------------------------------------------------
screens.garage = function(arg)
	local d = State.data
	if not d then return end
	local mode = arg and arg.mode or "phone"
	if mode == "fuel" or mode == "service" then
		local def = Vehicles.ById[d.activeVehicle]
		local o = d.vehicles[d.activeVehicle]
		section(mode == "fuel" and "FUEL STATION" or "SERVICE BAY")
		if def and o then
			local card = bigCard(96)
			UI.label(card, def.name, 16, C.text, F.black, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 22) })
			statBar(card, "Fuel", o.fuel, math.max(def.fuelCap, 0.01), def.pedal and "—" or ("%.1f L"):format(o.fuel), C.green, 38)
			statBar(card, "Condition", o.condition, 100, math.floor(o.condition) .. "%", C.blue, 60)
			if not def.pedal then
				local need = def.fuelCap - o.fuel
				row("⛽", "Fill the tank", ("%.1f L · %s"):format(need, Util.money(math.ceil(need * Game.FUEL_PRICE))), "Refuel", function()
					call("Garage", "refuel", def.id); render()
				end, { disabled = need < 0.05 })
			end
			row("🔧", "Repair", o.condition >= 99 and "In perfect shape" or ("Restore to 100%" .. (arg.home and " · home workshop −50%" or "")), "Repair", function()
				call("Garage", "repair", def.id); render()
			end, { disabled = o.condition >= 99 })
		end
		if mode == "service" then
			row("⬆️", "Upgrades & paint", "Tune your " .. (def and def.name or "vehicle"), "Open", function() go("vehicle", { id = d.activeVehicle, dealer = true }, "Tuning") end)
		end
		return
	end
	local dealer = mode == "dealer"
	if dealer then
		local hero = bigCard(56, Color3.fromRGB(200, 40, 40))
		UI.label(hero, "KK MOTORS", 18, C.white, F.black, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 22) })
		UI.label(hero, "Buy, upgrade and paint here", 12, C.white, F.med, { Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -28, 0, 18) })
	end
	section("MY VEHICLES")
	for _, def in ipairs(Vehicles.List) do
		local o = d.vehicles[def.id]
		if o then
			local active = d.activeVehicle == def.id
			row(def.class == "bike" and (def.pedal and "🚲" or "🛵") or "🚗", def.name .. (active and "  ✓" or ""),
				def.pedal and ("Condition " .. math.floor(o.condition) .. "%") or ("Fuel %.1f/%g L · Condition %d%%"):format(o.fuel, def.fuelCap, math.floor(o.condition)),
				"Details", function() go("vehicle", { id = def.id, dealer = dealer }, def.name) end, { btnWidth = 70, btnColor = C.dark })
		end
	end
	section(dealer and "FOR SALE" or "SHOWROOM (buy at KK Motors)")
	if not dealer then
		row("🧭", "KK Motors", Lang.pick("Buy, upgrade and paint there", "ซื้อ อัปเกรด และทำสีรถที่นี่"), Lang.pick("Go", "ไป"), function()
			if navTo({ "dealer" }) then Phone.setOpen(false) end
		end, { btnWidth = 60, btnColor = C.blue })
	end
	for _, def in ipairs(Vehicles.List) do
		if not d.vehicles[def.id] then
			local lock = d.level < def.level
			row(def.class == "bike" and "🛵" or "🚗", def.name, (lock and ("🔒 Level " .. def.level .. " · ") or "") .. Util.money(def.price) .. " · " .. def.thai,
				"View", function() go("vehicle", { id = def.id, dealer = dealer }, def.name) end, { btnWidth = 60, btnColor = C.dark, titleColor = lock and C.sub or C.text })
		end
	end
	row("📦", "Store vehicle", "Put your current vehicle away", "Store", function() call("Garage", "despawn") end, { btnColor = Color3.fromRGB(110, 118, 130) })
end

screens.vehicle = function(arg)
	local d = State.data
	local def = Vehicles.ById[arg.id]
	if not d or not def then return end
	local o = d.vehicles[def.id]
	local stats = Vehicles.computeStats(def, o or {})
	local card = bigCard(176)
	UI.label(card, def.name, 18, C.text, F.black, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 24) })
	UI.label(card, def.thai .. " · " .. def.desc, 12, C.sub, F.med, { Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 18) })
	statBar(card, "Top speed", stats.topSpeed, 180, math.floor(stats.topSpeed * Game.KMH) .. " km/h", C.red, 58)
	statBar(card, "Acceleration", stats.accel, 50, ("%.0f"):format(stats.accel), C.orange, 78)
	statBar(card, "Handling", stats.grip, 18, ("%.1f"):format(stats.grip), C.blue, 98)
	statBar(card, "Braking", stats.brake, 90, ("%.0f"):format(stats.brake), C.purple, 118)
	statBar(card, "Comfort", stats.comfort, 2.6, ("%.1f"):format(stats.comfort), Color3.fromRGB(240, 110, 160), 138)
	UI.label(card, ("📦 Cargo %d   🧍 Seats %d   ⛽ %s"):format(def.cargo, def.seats, def.pedal and "pedal power" or (def.fuelCap .. " L")), 11, C.text, F.bold,
		{ Position = UDim2.fromOffset(12, 156), Size = UDim2.new(1, -24, 0, 16) })
	if not o then
		local lock = d.level < def.level
		UI.button(content, lock and ("🔒 Reach level " .. def.level) or ("Buy for " .. Util.money(def.price)), { BackgroundColor3 = (lock or d.money < def.price) and C.line or C.green,
			TextColor3 = (lock or d.money < def.price) and C.sub or C.white }, function()
			if call("Garage", "buy", def.id) then render() end
		end)
		if not arg.dealer then
			UI.button(content, Lang.pick("🧭 Take me to KK Motors", "🧭 นำทางไป KK Motors"), { BackgroundColor3 = C.blue }, function()
				if navTo({ "dealer" }) then Phone.setOpen(false) end
			end)
		end
		return
	end
	UI.button(content, "🔑 Bring it to me", {}, function() call("Garage", "spawn", def.id) end)
	if not def.pedal then
		row("⛽", ("Fuel %.1f / %g L"):format(o.fuel, def.fuelCap), "Full price at stations · emergency delivery costs 2.5×", "Refuel", function() call("Garage", "refuel", def.id); render() end,
			{ disabled = def.fuelCap - o.fuel < 0.05 })
	end
	row("🔧", "Condition " .. math.floor(o.condition) .. "%", "A worn vehicle is slower. Repair at KK Motors or a station.", "Repair", function() call("Garage", "repair", def.id); render() end,
		{ disabled = o.condition >= 99 })
	section("UPGRADES (fitted at KK Motors)")
	for _, up in ipairs(Vehicles.UPGRADES) do
		if not (def.pedal and (up.id == "engine" or up.id == "eco")) then
			local lvl = o[up.id] or 0
			local maxed = lvl >= Vehicles.MAX_UPGRADE
			local price = Vehicles.upgradePrice(def, up.id, lvl + 1)
			row(up.icon, up.name .. "  " .. string.rep("●", lvl) .. string.rep("○", Vehicles.MAX_UPGRADE - lvl), up.desc, maxed and "MAX" or Util.money(price), function()
				if call("Garage", "upgrade", def.id, up.id) then render() end
			end, { disabled = maxed, btnWidth = 78 })
		end
	end
	section("PAINT · " .. Util.money(Vehicles.PAINT_PRICE))
	local paint = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = content })
	UI.list(paint, 6, true)
	for i, col in ipairs(Vehicles.COLORS) do
		local b = UI.button(paint, o.color == i and "✓" or "", { Size = UDim2.fromOffset(31, 36), BackgroundColor3 = col.color, TextColor3 = i == 2 and C.text or C.white }, function()
			if call("Garage", "paint", def.id, i) then render() end
		end)
		UI.stroke(b, C.line, 1)
	end
end

---------------------------------------------------------------------------------------------------
-- Property
---------------------------------------------------------------------------------------------------
screens.property = function()
	local d = State.data
	if not d then return end
	if d.plot then
		local t = Housing.TIERS[d.plot.tier]
		local hero = bigCard(86, Color3.fromRGB(230, 130, 60))
		UI.label(hero, "🏡 " .. t.name, 18, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) })
		UI.label(hero, ("%d / %d furniture · lot %d × %d"):format(#d.plot.furniture, t.limit, t.size.X, t.size.Y), 13, C.white, F.med, { Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 18) })
		UI.label(hero, State.plot and "Your home is in this server" or "Plots of this size are full here — home is safe", 11, C.white, F.med, { Position = UDim2.fromOffset(14, 58), Size = UDim2.new(1, -28, 0, 18) })
		if State.plot then
			row("🧭", "Navigate home", "Set the GPS to your front door", "Go", function() GPS.setTarget(State.plot.base.Position, "My Home"); Feedback.toast("📍 Route set to My Home", "good") end, { btnWidth = 56 })
			local atHome = near(State.plot.base.Position, 180)
			row("🛠", "Build Mode", atHome and "Place, move and remove furniture" or "Go to your plot to build", "Build", function()
				if not atHome then Feedback.toast("Go to your plot first", "bad") return end
				Phone.setOpen(false)
				if Phone.onBuild then Phone.onBuild() end
			end, { disabled = not atHome })
		end
		section("WHAT FURNITURE DOES")
		for _, tip in ipairs({ { "🛏", "Bed", "Sleep to refill Energy fast" }, { "🧊", "Refrigerator", "Stores up to 60 food items" }, { "🍳", "Kitchen Stove", "Cook crops into meals to eat or sell" },
			{ "🚿", "Shower / 📺 TV", "Restore Happiness (better tips)" }, { "🅿️", "Garage Pad", "Bring your vehicle home" }, { "🔧", "Tool Bench", "Half-price repairs and upgrades at home" } }) do
			row(tip[1], tip[2], tip[3])
		end
		section("DANGER ZONE")
		row("💸", "Sell land", "60% of the land price + 50% of furniture", "Sell", function()
			if current.confirmSell and os.clock() - current.confirmSell < 4 then
				if call("Housing", "sell") then render() end
			else
				current.confirmSell = os.clock()
				Feedback.toast("Tap Sell again to confirm")
			end
		end, { btnColor = C.red })
	else
		local hero = bigCard(64, Color3.fromRGB(230, 130, 60))
		UI.label(hero, "Buy land, build a home", 17, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 22) })
		UI.label(hero, "Visit a FOR SALE sign to buy that plot", 12, C.white, F.med, { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 18) })
		for _, id in ipairs(Housing.TIER_ORDER) do
			local t = Housing.TIERS[id]
			local free
			if State.world then
				for _, p in ipairs(State.world.plots) do
					if p.tier == id and not p.owned and (not free or near(p.pos, (free.pos - p.pos).Magnitude)) then free = free or p end
				end
			end
			row("🏡", t.name .. " · " .. Util.money(t.price), (d.level < t.level and ("🔒 Level " .. t.level .. " · ") or "") .. t.thai .. " · " .. t.size.X .. "×" .. t.size.Y .. " studs",
				free and "Find" or nil, function() GPS.setTarget(free.pos, t.name .. " for sale"); Feedback.toast("📍 Route set", "good") end, { btnWidth = 60 })
		end
	end
end

screens.plot = function(arg)
	local d = State.data
	local t = Housing.TIERS[arg.tier]
	if not d or not t then return end
	local hero = bigCard(92, Color3.fromRGB(28, 120, 70))
	UI.label(hero, t.name, 19, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) })
	UI.label(hero, t.thai .. " · " .. t.size.X .. " × " .. t.size.Y .. " studs · house included", 12, C.white, F.med, { Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 18) })
	UI.label(hero, Util.money(t.price), 22, C.white, F.black, { Position = UDim2.fromOffset(14, 58), Size = UDim2.new(1, -28, 0, 26) })
	if arg.owned then
		UI.label(content, "This plot already has an owner.", 13, C.sub, F.med)
	elseif d.plot then
		UI.label(content, "You already own land. Sell it in the Property app to move.", 13, C.sub, F.med, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 36) })
	else
		local can = d.level >= t.level and d.money >= t.price
		UI.button(content, d.level < t.level and ("🔒 Reach level " .. t.level) or (d.money < t.price and ("Need " .. Util.money(t.price - d.money) .. " more") or "Buy this plot"),
			{ BackgroundColor3 = can and C.green or C.line, TextColor3 = can and C.white or C.sub }, function()
			if call("Housing", "buy", arg.id) then back() end
		end)
	end
	row("📦", "Furniture limit", t.limit .. " pieces")
	row("🏠", "House", ("%d × %d studs, walls %d high"):format(t.house.X, t.house.Z, t.house.Y))
end

---------------------------------------------------------------------------------------------------
-- Farming
---------------------------------------------------------------------------------------------------
local function bedStatus(bed)
	if not bed.unlocked then return "🔒 Locked", C.sub end
	if not bed.tilled then return "Needs tilling", C.sub end
	if not bed.crop then return "Ready to plant", C.greenDark end
	local def = Crops.ById[bed.crop]
	local copy = table.clone(bed)
	Crops.advance(copy, os.time(), (Workspace:GetAttribute("Rain") or 0) > 0)
	if copy.progress >= 1 then
		local g = Crops.quality(copy)
		return ("%s ready! Grade %s"):format(def.name, Crops.GRADES[g].name), C.greenDark, copy
	end
	local left = (1 - copy.progress) * def.grow / (0.85 + 0.3 * (copy.soil or 0.7))
	return ("%s %d%% · %s%s"):format(def.name, math.floor(copy.progress * 100), copy.water > 0.05 and ("~" .. Util.duration(left)) or "needs water", (copy.fert or 0) >= 1 and " · fertilized" or ""),
		copy.water > 0.05 and C.text or C.red, copy
end

screens.farming = function()
	local d = State.data
	if not d then return end
	local farm = State.farm
	local hero = bigCard(64, Color3.fromRGB(96, 150, 60))
	UI.label(hero, farm and ("Allotment " .. farm.id) or "No allotment in this server", 17, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -110, 0, 22) })
	UI.label(hero, "Till → plant → water → harvest → sell", 12, C.white, F.med, { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -110, 0, 18) })
	if farm then
		UI.button(hero, "Go", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(60, 34), BackgroundColor3 = C.white, TextColor3 = C.greenDark }, function()
			GPS.setTarget(farm.pos, "My Allotment"); Feedback.toast("📍 Route set to your allotment", "good")
		end)
	end
	local atFarm = farm and near(farm.pos, 110)
	section(atFarm and "MY BEDS" or "MY BEDS (go to the farm to work them)")
	local beds = d.farm.beds
	for i = 1, Crops.BEDS do
		local bed = beds[i] or { unlocked = i <= Crops.FREE_BEDS }
		local text, color, live = bedStatus(bed)
		local btn, op, argv
		if not bed.unlocked then btn, op = Util.money(Crops.BED_PRICE[i]), "unlock"
		elseif not bed.tilled then btn, op = "Till", "till"
		elseif not bed.crop then btn = "Plant"
		elseif live and live.progress >= 1 then btn, op = "Harvest", "harvest"
		elseif live and live.water <= 0.05 then btn, op = "Water", "water"
		else btn = "Tend" end
		row(bed.crop and (Items.ById[bed.crop] and Items.ById[bed.crop].icon or "🌱") or "🟫", "Bed " .. i, text, btn, function()
			if not atFarm then Feedback.toast("Go to your allotment first", "bad") return end
			if op then
				if call("Farm", op, i, argv) then render() end
			elseif btn == "Plant" then go("seeds", { bed = i }, "Plant bed " .. i, Color3.fromRGB(96, 150, 60))
			else go("bed", { bed = i }, "Bed " .. i, Color3.fromRGB(96, 150, 60)) end
		end, { btnWidth = 74, titleColor = color })
	end
	section("TODAY'S MARKET (Farmers' Market buys crops)")
	local day = Util.dayNumber()
	for _, c in ipairs(Crops.List) do
		local it = Items.ById[c.id]
		local mult = Crops.marketMult(c.id, day)
		local price = math.max(1, math.floor(it.sell * mult + 0.5))
		row(it.icon, it.name .. " · " .. Util.money(price) .. " each", ("%s%d%% vs normal · you have %d · seed %s · %ds to grow"):format(mult >= 1 and "▲ +" or "▼ ", math.floor((mult - 1) * 100), d.inventory[c.id] or 0,
			Util.money(Items.ById[c.seed].price), c.grow), nil, nil, { titleColor = mult >= 1.1 and C.greenDark or (mult <= 0.9 and C.red or C.text) })
	end
end

screens.seeds = function(arg)
	local d = State.data
	if not d then return end
	section("CHOOSE A SEED FOR BED " .. arg.bed)
	local any = false
	for _, c in ipairs(Crops.List) do
		local have = d.inventory[c.seed] or 0
		local seed = Items.ById[c.seed]
		local lock = d.level < c.level
		if have > 0 then any = true end
		row(Items.ById[c.id].icon, seed.name .. " × " .. have, lock and ("🔒 Level " .. c.level) or (("Grows in %ds · yields %d · sells ~%s each"):format(c.grow, c.yield, Util.money(Items.ById[c.id].sell))),
			"Plant", function()
				if call("Farm", "plant", arg.bed, c.seed) then back() end
			end, { disabled = have <= 0 or lock, btnWidth = 64 })
	end
	if not any then UI.label(content, "No seeds. Buy some at the Isan Seed Shop next to the farm.", 13, C.sub, F.med, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 36) }) end
end

screens.bed = function(arg)
	local d = State.data
	if not d then return end
	local bed = d.farm.beds[arg.bed]
	if not bed or not bed.crop then UI.label(content, "Nothing is growing here.", 13, C.sub) return end
	local _, _, live = bedStatus(bed)
	live = live or bed
	local def = Crops.ById[bed.crop]
	local card = bigCard(128)
	UI.label(card, Items.ById[def.id].icon .. " " .. def.name, 18, C.text, F.black, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 24) })
	statBar(card, "Growth", live.progress or 0, 1, math.floor((live.progress or 0) * 100) .. "%", C.green, 40)
	statBar(card, "Water", live.water or 0, 1, math.floor((live.water or 0) * 100) .. "%", C.blue, 60)
	statBar(card, "Fertilizer", live.fert or 0, 1, math.floor((live.fert or 0) * 100) .. "%", C.orange, 80)
	statBar(card, "Health", live.health or 1, 1, math.floor((live.health or 1) * 100) .. "%", C.red, 100)
	row("🟫", "Soil quality " .. math.floor((live.soil or 0.7) * 100) .. "%", "Each harvest tires the soil. Compost restores it.")
	row("💧", "Water", "Crops only grow while watered. Rain waters for free.", "Water", function() if call("Farm", "water", arg.bed) then render() end end)
	row("🧪", "Fertilizer × " .. (d.inventory.fertilizer or 0), "Better quality grade → bigger harvest", "Use", function() if call("Farm", "fertilize", arg.bed, "fertilizer") then render() end end,
		{ disabled = (d.inventory.fertilizer or 0) <= 0 })
	row("🍂", "Compost × " .. (d.inventory.compost or 0), "Improves the soil of this bed", "Use", function() if call("Farm", "fertilize", arg.bed, "compost") then render() end end,
		{ disabled = (d.inventory.compost or 0) <= 0 })
	if (live.progress or 0) >= 1 then
		UI.button(content, "🌾 Harvest", {}, function() if call("Farm", "harvest", arg.bed) then back() end end)
	end
	row("🗑", "Clear bed", "Remove the crop (nothing is refunded)", "Clear", function() if call("Farm", "clear", arg.bed) then back() end end, { btnColor = C.red })
end

---------------------------------------------------------------------------------------------------
-- Bag, fridge, cooking
---------------------------------------------------------------------------------------------------
local function itemSub(it): string
	if it.kind == "food" then
		local parts = {}
		if (it.hunger or 0) > 0 then table.insert(parts, "🍜 +" .. it.hunger) end
		if (it.energy or 0) > 0 then table.insert(parts, "⚡ +" .. it.energy) end
		if (it.happy or 0) > 0 then table.insert(parts, "😊 +" .. it.happy) end
		if it.buff then table.insert(parts, "✨ " .. it.buff.desc) end
		return table.concat(parts, "  ")
	elseif it.kind == "seed" then return "Plant at your allotment"
	elseif it.kind == "crop" then return "Sell at the Farmers' Market or cook at home"
	end
	return it.thai or ""
end

screens.inventory = function()
	local d = State.data
	if not d then return end
	local food = 0
	for id, n in pairs(d.inventory) do
		if Items.ById[id] and Items.ById[id].kind == "food" then food += n end
	end
	section(("FOOD & DRINK  %d / 16"):format(food))
	local shown = false
	for _, kind in ipairs({ "food", "crop", "seed", "supply" }) do
		local first = true
		for _, it in ipairs(Items.List) do
			local n = d.inventory[it.id]
			if n and n > 0 and it.kind == kind then
				if first and kind ~= "food" then section(kind == "crop" and "PRODUCE" or (kind == "seed" and "SEEDS" or "SUPPLIES")) end
				first = false
				shown = true
				row(it.icon, it.name .. " × " .. n, itemSub(it), kind == "food" and "Eat" or nil, function() if call("Inventory", "eat", it.id) then render() end end, { btnWidth = 60 })
			end
		end
	end
	if not shown then UI.label(content, "Your bag is empty. Buy food at any restaurant or GoMart 24.", 13, C.sub, F.med, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 36) }) end
end

screens.fridge = function()
	local d = State.data
	if not d or not d.plot then return end
	local total = 0
	for _, n in pairs(d.plot.fridge) do total += n end
	section(("IN THE FRIDGE  %d / 60"):format(total))
	for _, it in ipairs(Items.List) do
		local n = d.plot.fridge[it.id]
		if n and n > 0 then row(it.icon, it.name .. " × " .. n, itemSub(it), "Take", function() if call("Housing", "fridge_take", it.id, 1) then render() end end, { btnWidth = 60 }) end
	end
	section("IN YOUR BAG")
	for _, it in ipairs(Items.List) do
		local n = d.inventory[it.id]
		if n and n > 0 and (it.kind == "food" or it.kind == "crop") then
			row(it.icon, it.name .. " × " .. n, "", "Store", function() if call("Housing", "fridge_put", it.id, 1) then render() end end, { btnWidth = 60, btnColor = C.blue, height = 46 })
		end
	end
end

screens.cook = function()
	local d = State.data
	if not d or not d.plot then return end
	section("RECIPES (uses your bag and fridge)")
	for _, r in ipairs(Items.RECIPES) do
		local it = Items.ById[r.id]
		local parts, can = {}, true
		for id, need in pairs(r.needs) do
			local have = (d.inventory[id] or 0) + (d.plot.fridge[id] or 0)
			if have < need then can = false end
			table.insert(parts, ("%s %d/%d"):format(Items.ById[id].name, math.min(have, need), need))
		end
		row(it.icon, it.name .. (r.makes and (" ×" .. r.makes) or ""), table.concat(parts, " · ") .. " → sells " .. Util.money(it.sell), "Cook", function()
			if call("Housing", "cook", r.id) then render() end
		end, { disabled = not can, btnWidth = 60 })
	end
	UI.label(content, "Cooked meals restore more than street food, and the Fresh Market buys them.", 12, C.sub, F.med, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 34) })
end

---------------------------------------------------------------------------------------------------
-- Shop (opened by world prompts)
---------------------------------------------------------------------------------------------------
screens.shop = function(arg)
	local d = State.data
	if not d then return end
	local hero = bigCard(56, C.dark)
	UI.label(hero, arg.name, 16, C.white, F.black, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 22) })
	UI.label(hero, (arg.thai or "") .. " · You have " .. Util.money(d.money), 12, Color3.fromRGB(190, 198, 208), F.med, { Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -28, 0, 18) })
	if #arg.stock > 0 then section("BUY") end
	for _, id in ipairs(arg.stock) do
		local it = Items.ById[id]
		if it and it.kind == "food" then
			-- food: eat it here in one tap; "+ Bag" keeps one for later
			row(it.icon, it.name .. " · " .. Util.money(it.price), (it.thai and (it.thai .. "  ") or "") .. itemSub(it), "Eat now", function()
				if call("Shop", "eatnow", arg.id, id) then render() end
			end, { btnWidth = 70, disabled = d.money < it.price, btn2 = { text = "+ Bag", width = 64, fn = function()
				if call("Shop", "buy", arg.id, id, 1) then render() end
			end } })
		elseif it then
			row(it.icon, it.name .. " · " .. Util.money(it.price), (it.thai and (it.thai .. "  ") or "") .. itemSub(it), "Buy", function()
				if call("Shop", "buy", arg.id, id, 1) then render() end
			end, { btnWidth = 60, disabled = d.money < it.price })
		end
	end
	if #arg.sells > 0 then
		section("SELL")
		local any = false
		for _, s in ipairs(arg.sells) do
			local it = Items.ById[s.id]
			local have = d.inventory[s.id] or 0
			if it and have > 0 then
				any = true
				row(it.icon, it.name .. " × " .. have, Util.money(s.price) .. " each · total " .. Util.money(s.price * have), "Sell all", function()
					if call("Shop", "sell", arg.id, s.id, have) then render() end
				end, { btnWidth = 70, btnColor = C.orange })
			end
		end
		if not any then UI.label(content, "Nothing to sell yet.", 13, C.sub, F.med) end
		for _, s in ipairs(arg.sells) do
			local it = Items.ById[s.id]
			if it and (d.inventory[s.id] or 0) == 0 then row(it.icon, it.name, "Buying at " .. Util.money(s.price) .. " each today", nil, nil, { titleColor = C.sub, height = 46 }) end
		end
	end
end

screens.bus = function(arg)
	section("WHERE TO?  ฿30 per ride")
	for _, s in ipairs(arg.stops) do
		if s.id ~= arg.from then
			row("🚌", s.name, s.thai, "Go", function()
				if call("Shop", "bus", arg.from, s.id) then Phone.setOpen(false) end
			end, { btnWidth = 60 })
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Bank, profile, missions, settings
---------------------------------------------------------------------------------------------------
screens.bank = function()
	local d = State.data
	if not d then return end
	local hero = bigCard(92, Color3.fromRGB(40, 100, 170))
	UI.label(hero, "Savings", 12, C.white, F.med, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 16) })
	UI.label(hero, Util.money(d.bank), 28, C.white, F.black, { Position = UDim2.fromOffset(14, 26), Size = UDim2.new(1, -28, 0, 34) })
	UI.label(hero, "Cash " .. Util.money(d.money) .. " · 1% interest per day (max ฿2,500)", 11, C.white, F.med, { Position = UDim2.fromOffset(14, 64), Size = UDim2.new(1, -28, 0, 18) })
	for _, op in ipairs({ { "deposit", "DEPOSIT", d.money, C.green }, { "withdraw", "WITHDRAW", d.bank, C.orange } }) do
		section(op[2])
		local r = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), Parent = content })
		UI.list(r, 6, true)
		for _, amt in ipairs({ 100, 1000, 10000, -1 }) do
			local n = amt == -1 and op[3] or amt
			local okay = n > 0 and n <= op[3]
			UI.button(r, amt == -1 and "All" or Util.num(amt), { Size = UDim2.new(0.25, -5, 1, 0), TextSize = 13, BackgroundColor3 = okay and op[4] or C.line, TextColor3 = okay and C.white or C.sub }, function()
				if okay and call("Bank", op[1], n) then render() end
			end)
		end
	end
end

screens.profile = function()
	local d = State.data
	if not d then return end
	local hero = bigCard(86, C.purple)
	UI.label(hero, player.DisplayName, 19, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) })
	UI.label(hero, ("Level %d GoDash Rider · ★ %.2f (%d ratings)"):format(d.level, d.rating, d.ratingCount), 13, C.white, F.med, { Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 18) })
	UI.label(hero, ("%d / %d EXP to level %d"):format(d.exp, Game.expForLevel(d.level), d.level + 1), 12, C.white, F.med, { Position = UDim2.fromOffset(14, 58), Size = UDim2.new(1, -28, 0, 18) })
	section("CAREER")
	local s = d.stats
	for _, st in ipairs({
		{ "🍱", "Food deliveries", Util.num(s.deliveries) }, { "🧍", "Passenger rides", Util.num(s.rides) }, { "🛣", "Distance driven", ("%.1f km"):format(s.distance / 1000) },
		{ "💰", "Lifetime earnings", Util.money(s.earned) }, { "⭐", "Five-star jobs", Util.num(s.fiveStars) }, { "🌾", "Harvests", Util.num(s.harvests) },
		{ "🚗", "Vehicles owned", tostring(Util.count(d.vehicles)) }, { "🏡", "Home", d.plot and Housing.TIERS[d.plot.tier].name or "None yet" }, { "⏱", "Time played", Util.duration(s.playSeconds) },
	}) do
		local card = row(st[1], st[2], nil)
		UI.label(card, st[3], 14, C.text, F.black, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0, 130, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	end
end
screens.computer = screens.profile

screens.missions = function()
	local d = State.data
	if not d then return end
	local day = Util.dayNumber()
	local claimed = d.dailyReward.day == day
	local nextStreak = (d.dailyReward.day == day - 1 or claimed) and (claimed and d.dailyReward.streak or d.dailyReward.streak % #Game.DAILY_REWARDS + 1) or 1
	local hero = bigCard(108, C.red)
	UI.label(hero, "🎁 Daily Reward", 17, C.white, F.black, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 22) })
	local strip = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -24, 0, 30), Parent = hero })
	UI.list(strip, 4, true)
	for i, r in ipairs(Game.DAILY_REWARDS) do
		local done = i < nextStreak or (claimed and i == nextStreak)
		local cell = UI.new("Frame", { BackgroundColor3 = done and C.white or Color3.fromRGB(255, 255, 255), BackgroundTransparency = done and 0 or 0.75, Size = UDim2.new(1 / 7, -4, 1, 0), Parent = strip })
		UI.corner(cell, 8)
		UI.label(cell, done and "✓" or tostring(i), 13, done and C.red or C.white, F.black, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		local _ = r
	end
	local rw = Game.DAILY_REWARDS[nextStreak]
	UI.button(hero, claimed and "Come back tomorrow" or ("Claim day " .. nextStreak .. " · " .. Util.money(rw.money) .. (rw.item and " + item" or "")),
		{ Position = UDim2.fromOffset(12, 70), Size = UDim2.new(1, -24, 0, 30), TextSize = 13, BackgroundColor3 = C.white, TextColor3 = claimed and C.sub or C.red }, function()
		if not claimed and call("Mission", "daily") then render() end
	end)
	local function mission(def, st)
		local prog = st and st.progress or 0
		local done = prog >= def.goal
		local got = st and st.claimed
		local reward = Util.money(def.money or 0) .. " · " .. (def.exp or 0) .. " EXP" .. (def.item and (" · " .. Items.ById[def.item].name .. " ×" .. (def.qty or 1)) or "")
		local unit = def.event == "distance" and ("%.1f / %.0f km"):format(prog / 1000, def.goal / 1000) or (Util.num(prog) .. " / " .. Util.num(def.goal))
		local card = row(got and "✅" or (done and "🎁" or "🎯"), def.name, def.desc .. " · " .. unit, got and "Done" or (done and "Claim" or nil), function()
			if done and not got and call("Mission", "claim", def.id) then render() end
		end, { disabled = got, btnWidth = 62, height = 76, titleColor = got and C.sub or C.text })
		UI.label(card, "Reward: " .. reward, 11, C.greenDark, F.bold, { Position = UDim2.fromOffset(48, 50), Size = UDim2.new(1, -60, 0, 14) })
		local track, set = UI.bar(card, done and C.green or C.blue, 4)
		track.Position = UDim2.new(0, 48, 1, -9); track.Size = UDim2.new(1, -60, 0, 4)
		track.BackgroundColor3 = C.black; track.BackgroundTransparency = 0.9
		set(prog / def.goal)
	end
	section("DAILY MISSIONS")
	for _, st in ipairs(d.missions.daily) do
		if Missions.ById[st.id] then mission(Missions.ById[st.id], st) end
	end
	section("CAREER")
	for _, def in ipairs(Missions.CAREER) do mission(def, d.missions.career[def.id]) end
end

screens.radio = function()
	local on = Radio.station ~= nil
	local hero = bigCard(82, Color3.fromRGB(200, 80, 140))
	UI.label(hero, on and "Now playing" or "Radio is off", 12, C.white, F.med, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 16) })
	UI.label(hero, on and Radio.track or "Pick a station to ride with music", 17, C.white, F.black, { Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -28, 0, 24) })
	UI.label(hero, "Licensed music from the Roblox library", 11, C.white, F.med, { Position = UDim2.fromOffset(14, 56), Size = UDim2.new(1, -28, 0, 16) })
	section("STATIONS")
	for _, s in ipairs(Radio.stations) do
		local playing = Radio.station == s.id
		row(s.icon, s.name .. (playing and "  ♪" or ""), s.thai .. " · " .. #s.tracks .. " tracks", playing and "Stop" or "Play", function()
			Radio.play(not playing and s.id or nil)
			Radio.remember(not playing)
			render()
		end, { btnWidth = 62, btnColor = playing and C.red or C.green })
	end
	if on then
		row("⏭", "Next track", "Skip to another song on this station", "Next", function() Radio.next() end, { btnWidth = 62, btnColor = C.dark })
	end
	section("VOLUME")
	local vol = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), Parent = content })
	UI.list(vol, 6, true)
	for _, v in ipairs({ 0.1, 0.25, 0.4, 0.6, 0.85 }) do
		local sel = math.abs(Radio.volume - v) < 0.07
		UI.button(vol, math.floor(v * 100) .. "%", { Size = UDim2.new(0.2, -5, 1, 0), TextSize = 13, BackgroundColor3 = sel and C.green or C.card, TextColor3 = sel and C.white or C.text }, function()
			Radio.setVolume(v)
			render()
		end)
	end
	UI.label(content, "Links from YouTube or other sites cannot be played inside Roblox.", 11, C.sub, F.med, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 30) })
end

screens.settings = function()
	local d = State.data
	if not d then return end
	local s = d.settings
	local function set(key, value) if call("Settings", key, value) then render() end end
	section("DRIVING")
	local card = bigCard(58)
	UI.label(card, "Steering sensitivity", 14, C.text, F.bold, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -150, 0, 20) })
	UI.label(card, ("%.1f×"):format(s.steer), 12, C.sub, F.med, { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -150, 0, 18) })
	UI.button(card, "−", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -56, 0.5, 0), Size = UDim2.fromOffset(40, 34), TextSize = 20, BackgroundColor3 = C.dark }, function() set("steer", math.max(0.5, s.steer - 0.1)) end)
	UI.button(card, "+", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(40, 34), TextSize = 20, BackgroundColor3 = C.dark }, function() set("steer", math.min(2, s.steer + 0.1)) end)
	local function toggle(icon, title, sub, key)
		row(icon, title, sub, s[key] and "ON" or "OFF", function() set(key, not s[key]) end, { btnWidth = 60, btnColor = s[key] and C.green or Color3.fromRGB(150, 158, 170) })
	end
	toggle("🛟", "Driving assist", "Extra grip so the vehicle is easier to control", "assist")
	-- who may hop on as your passenger (server/VehicleService "Ride along")
	local L = Lang.pick
	local rideCard = bigCard(76)
	local rl = UI.label(rideCard, L("👫 Who can ride with you", "👫 ใครขึ้นรถเราได้บ้าง"), 14, C.text, F.bold, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 20) })
	rl:SetAttribute("NoTranslate", true)
	local rideRow = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 32), Size = UDim2.new(1, -20, 0, 36), Parent = rideCard })
	UI.list(rideRow, 6, true)
	for _, o in ipairs({ { "friends", L("Friends", "เพื่อน") }, { "all", L("Anyone", "ทุกคน") }, { "off", L("Nobody", "ไม่รับ") } }) do
		local sel = (s.rideAlong or "friends") == o[1]
		local b = UI.button(rideRow, o[2], { Size = UDim2.new(1 / 3, -4, 1, 0), TextSize = 13, BackgroundColor3 = sel and C.green or C.bg, TextColor3 = sel and C.white or C.text }, function() set("rideAlong", o[1]) end)
		b:SetAttribute("NoTranslate", true)
	end
	-- 2026-11-18 easier driving: camera distance, lane assist, auto gas (phones)
	local camCard = bigCard(76)
	local cl = UI.label(camCard, L("🎥 Camera distance", "🎥 ระยะกล้องตอนขับ"), 14, C.text, F.bold, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 20) })
	cl:SetAttribute("NoTranslate", true)
	local camRow = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 32), Size = UDim2.new(1, -20, 0, 36), Parent = camCard })
	UI.list(camRow, 6, true)
	for _, o in ipairs({ { "near", L("Near", "ใกล้") }, { "normal", L("Normal", "ปกติ") }, { "far", L("Far", "ไกล") } }) do
		local sel = (s.camera or "normal") == o[1]
		local b = UI.button(camRow, o[2], { Size = UDim2.new(1 / 3, -4, 1, 0), TextSize = 13, BackgroundColor3 = sel and C.green or C.bg, TextColor3 = sel and C.white or C.text }, function() set("camera", o[1]) end)
		b:SetAttribute("NoTranslate", true)
	end
	local LaneAssist = require(script.Parent.LaneAssist)
	local laneOn = LaneAssist.enabled()
	row("🛣️", L("Lane assist", "ช่วยประคองเลน"), L("Keeps you in your lane while you barely steer", "ไม่ได้บังคับ รถจะค่อย ๆ อยู่กลางเลนซ้ายเอง"),
		laneOn and "ON" or "OFF", function() set("lane", not laneOn) end, { btnWidth = 60, btnColor = laneOn and C.green or Color3.fromRGB(150, 158, 170) })
	local ghostsOn = s.ghosts ~= false
	row("👻", L("Ghost scenes at night", "ฉากผีตอนดึก"), L("Late deliveries to lonely places may get... spooky", "ส่งของดึก ๆ ในที่เปลี่ยว อาจเจอดี"),
		ghostsOn and "ON" or "OFF", function() set("ghosts", not ghostsOn) end, { btnWidth = 60, btnColor = ghostsOn and C.green or Color3.fromRGB(150, 158, 170) })
	-- 2026-11-19 adopted soi dog (server/PetService): take it along or leave it at home
	if type(d.pet) == "table" then
		local PetNames = require(game:GetService("ReplicatedStorage").Shared.Config.Pets).NAMES
		local n = PetNames[d.pet.name] or PetNames[1]
		local petOut = d.pet.out ~= false
		row("🐶", L("Take " .. n.en .. " along", "พา" .. n.th .. "ไปด้วย"), L("Your dog follows you and rides in front of you", "น้องหมาเดินตาม และนั่งหน้ารถไปกับคุณ"),
			petOut and "ON" or "OFF", function() if call("City", "pet_out") then render() end end, { btnWidth = 60, btnColor = petOut and C.green or Color3.fromRGB(150, 158, 170) })
	end
	if UserInputService.TouchEnabled then
		row("🚀", L("Auto gas", "เร่งอัตโนมัติ"), L("Tap GAS once to cruise; BRAKE stops it", "แตะ GAS ครั้งเดียววิ่งเอง กด BRAKE เพื่อหยุด"),
			s.autoGas and "ON" or "OFF", function() set("autoGas", not s.autoGas) end, { btnWidth = 60, btnColor = s.autoGas and C.green or Color3.fromRGB(150, 158, 170) })
	end
	-- graphics detail (client/Perf): auto follows the frame rate; phones start at medium
	section("GRAPHICS")
	local Perf = require(script.Parent.Perf)
	local qCard = bigCard(96)
	local ql = UI.label(qCard, L("🖼 Graphics detail", "🖼 ระดับกราฟิก"), 14, C.text, F.bold, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 20) })
	ql:SetAttribute("NoTranslate", true)
	local nowTier = ({ L("low", "ต่ำ"), L("medium", "กลาง"), L("high", "สูง") })[Perf.tier]
	local qs = UI.label(qCard, L("Lower it if the game stutters · now: ", "ถ้าเกมกระตุกให้ลดลง · ตอนนี้: ") .. nowTier, 11, C.sub, F.med, { Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -24, 0, 16) })
	qs:SetAttribute("NoTranslate", true)
	local qRow = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 50), Size = UDim2.new(1, -20, 0, 36), Parent = qCard })
	UI.list(qRow, 5, true)
	for _, o in ipairs({ { "auto", L("Auto", "อัตโนมัติ") }, { "low", L("Low", "ต่ำ") }, { "medium", L("Medium", "กลาง") }, { "high", L("High", "สูง") } }) do
		local sel = (s.quality or "auto") == o[1]
		local b = UI.button(qRow, o[2], { Size = UDim2.new(0.25, -4, 1, 0), TextSize = 12, BackgroundColor3 = sel and C.green or C.bg, TextColor3 = sel and C.white or C.text }, function()
			Perf.setQuality(o[1])
			set("quality", o[1])
		end)
		b:SetAttribute("NoTranslate", true)
	end
	section("SOUND")
	toggle("🔊", "Sound effects", "Engines, rain, UI", "sfx")
	row("🎶", "Background music", "Upbeat songs while you ride (Radio app: station, volume)", s.bgm ~= false and "ON" or "OFF", function()
		local on = s.bgm == false
		Radio.play(on and (Radio.station or Radio.DEFAULT) or nil)
		Radio.remember(on)
		render()
	end, { btnWidth = 60, btnColor = s.bgm ~= false and C.green or Color3.fromRGB(150, 158, 170) })
	toggle("🎵", "City ambience", "Birds, traffic and night sounds", "music")
	section("LANGUAGE")
	local langRow = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 42), Parent = content })
	UI.list(langRow, 8, true)
	for _, l in ipairs({ { "th", "🇹🇭 ภาษาไทย" }, { "en", "🇬🇧 English" } }) do
		local sel = Lang.code == l[1]
		local b = UI.button(langRow, l[2], { Size = UDim2.new(0.5, -4, 1, 0), TextSize = 15, BackgroundColor3 = sel and C.green or C.card, TextColor3 = sel and C.white or C.text }, function()
			Lang.set(l[1])
			task.spawn(function() Net.call("Settings", "lang", l[1]) end)
			render()
		end)
		b:SetAttribute("NoTranslate", true)
	end
	section("CONTROLS")
	for _, t in ipairs({ { "W / S", "Accelerate · brake / reverse" }, { "A / D", "Steer" }, { "Space", "Handbrake" }, { "Shift", "Boost" }, { "Q", "Auto drive (follows the GPS route)" }, { "F", "Headlights (get in: F)" },
		{ "Z / C / X", "Indicators / hazards" }, { "E", "Interact · leave vehicle" }, { "G", "Pick up / deliver while driving" }, { "Y", "Accept a job offer" }, { "M", "Phone" },
		{ "P", "Photo mode" } }) do
		local card2 = row("", t[2], nil, nil, nil, { height = 34 })
		UI.label(card2, t[1], 12, C.greenDark, F.black, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0, 90, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	end
	UI.label(content, "GoDash: Thai Driver Life · " .. "Map data © OpenStreetMap contributors", 10, C.sub, F.med, { TextXAlignment = Enum.TextXAlignment.Center })
end

---------------------------------------------------------------------------------------------------
-- shell
---------------------------------------------------------------------------------------------------
function Phone.start()
	gui = UI.screen("GoDashPhone", Layers.Navigation)
	-- right-edge dock: 340 wide, as tall as the screen allows (max 620), kept inside the safe margin
	local dock = Layout.rightPanel(gui)
	shell = UI.new("Frame", { Name = "Phone", BackgroundColor3 = Color3.fromRGB(14, 16, 20), Position = SHELL_CLOSED, Size = UDim2.fromScale(1, 1), Visible = false, Parent = dock })
	UI.corner(shell, 34)
	UI.stroke(shell, Color3.fromRGB(60, 66, 76), 2)
	local screen = UI.new("Frame", { BackgroundColor3 = C.bg, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), ClipsDescendants = true, Parent = shell })
	UI.corner(screen, 28)
	header = UI.new("Frame", { BackgroundColor3 = C.dark, Size = UDim2.new(1, 0, 0, 58), Parent = screen })
	UI.corner(header, 28)
	UI.new("Frame", { BackgroundColor3 = C.dark, Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 24), Name = "Fill", Parent = header })
	header:GetPropertyChangedSignal("BackgroundColor3"):Connect(function() header.Fill.BackgroundColor3 = header.BackgroundColor3 end)
	backBtn = UI.button(header, "<", { Position = UDim2.fromOffset(8, 12), Size = UDim2.fromOffset(34, 34), TextSize = 18, BackgroundColor3 = C.white, BackgroundTransparency = 0.82, ZIndex = 3 }, back)
	titleLabel = UI.label(header, "GoDash Phone", 17, C.white, F.black, { Position = UDim2.fromOffset(50, 0), Size = UDim2.new(1, -100, 1, 0), ZIndex = 3 })
	UI.button(header, "X", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 12), Size = UDim2.fromOffset(34, 34), TextSize = 15, BackgroundColor3 = C.white, BackgroundTransparency = 0.82, ZIndex = 3 }, function()
		Phone.setOpen(false)
	end)
	content = UI.scroll(screen, { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 1, -100) })
	UI.pad(content, 12, 10, 12, 16)
	UI.list(content, 8)
	-- home bar
	local bar = UI.new("Frame", { BackgroundColor3 = C.card, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 42), Parent = screen })
	UI.button(bar, "⌂  Home", { Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -24, 0, 32), BackgroundColor3 = C.bg, TextColor3 = C.text, TextSize = 13 }, function()
		stack = {}
		current = { name = "home" }
		content.CanvasPosition = Vector2.zero
		render()
	end)

	HUD.onPhone = function() Phone.setOpen(not open) end

	-- redraw the open screen when its data changes (never more than a few times a second)
	local pending = false
	local function schedule(keys)
		if not open or pending then return end
		if keys and current.name ~= "home" and not (keys.money or keys.inventory or keys.vehicles or keys.plot or keys.farm or keys.missions or keys.dailyReward or keys.settings or keys.level
			or keys.bank or keys.stats or keys.daily or keys.rating or keys.activeVehicle or keys.season or keys.company or keys.unlocks or keys.title) then return end
		pending = true
		task.delay(0.25, function()
			pending = false
			render()
		end)
	end
	State.onData(schedule)
	State.onJob(function() if open and (current.name == "godash" or current.name == "gps") then schedule(nil) end end)
	State.onWorld(function() if open and (current.name == "gps" or current.name == "property" or current.name == "farming" or current.name == "home") then schedule(nil) end end)

	-- world prompts open the matching screen
	Net.listen("OpenUI", function(kind, arg)
		arg = arg or {}
		stack = {}
		current = { name = "home" }
		local titles = { shop = arg.name or "Shop", bus = "Bus Stop", plot = "Land for sale", seeds = "Plant", bed = "Crop care", fridge = "Refrigerator", cook = "Kitchen", computer = "My Career",
			garage = arg.mode == "dealer" and "KK Motors" or (arg.mode == "fuel" and "Fuel Station" or "Service") }
		local colors = { shop = C.dark, bus = Color3.fromRGB(40, 110, 170), plot = Color3.fromRGB(28, 120, 70), seeds = Color3.fromRGB(96, 150, 60), bed = Color3.fromRGB(96, 150, 60),
			fridge = Color3.fromRGB(60, 130, 200), cook = Color3.fromRGB(230, 130, 60), computer = C.purple }
		if not screens[kind] then return end
		go(kind, arg, titles[kind], colors[kind])
		stack = { { name = "home" } }
		Phone.setOpen(true)
		render()
	end)
end

return Phone
