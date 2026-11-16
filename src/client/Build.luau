-- Build mode: pick furniture, see a ghost on your plot, rotate, snap to a grid or place freely,
-- move or sell what is already there. The ghost is only a preview: the server checks ownership,
-- money, bounds, walls and overlaps before anything is really placed.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Housing = require(Shared.Config.Housing)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local UI = require(script.Parent.UI.Kit)
local Layout = require(script.Parent.UI.Core.Layout)
local Layers = require(script.Parent.UI.Core.Layers)
local UIState = require(script.Parent.UI.Core.UIState)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)
local Env = require(script.Parent.Env)
local Phone = require(script.Parent.Phone)

local Build = {}
local C, F = UI.C, UI.F
local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local gui, panel, itemRow, info, placeBtn, gridBtn
local active = false
local category = Housing.CATEGORIES[1]
local sel = nil -- { def, rot, x, z, ok, why, moveUid }
local picked = nil -- { uid, def, model }
local grid = true
local ghost, pickBox
local conns = {}

local function plot() return State.plot end

local function localPoint(screen: Vector2): Vector3?
	local p = plot()
	local cam = Workspace.CurrentCamera
	if not p or not cam then return nil end
	local ray = cam:ViewportPointToRay(screen.X, screen.Y)
	local y = p.base.Position.Y + p.house.ground
	if math.abs(ray.Direction.Y) < 1e-4 then return nil end
	local t = (y - ray.Origin.Y) / ray.Direction.Y
	if t < 0 or t > 2000 then return nil end
	return p.base:PointToObjectSpace(ray.Origin + ray.Direction * t)
end

-- The same rules the server applies, so the ghost colour is honest (overlaps are server-only).
local function check(def, x: number, z: number, rot: number): (boolean, string?)
	local p = plot()
	local fx, fz = Housing.footprint(def, rot)
	if math.abs(x) + fx / 2 > p.size.X / 2 - 0.5 or math.abs(z) + fz / 2 > p.size.Y / 2 - 0.5 then return false, "Outside your plot" end
	local h = p.house
	local inside = math.abs(x) < h.hx - h.wall and math.abs(z - h.cz) < h.hz - h.wall
	if inside then
		if (math.abs(x) + fx / 2 > h.hx - h.wall or math.abs(z - h.cz) + fz / 2 > h.hz - h.wall) and def.shape ~= "painting" then return false, "Too close to a wall" end
		if def.use == "garage" then return false, "The garage pad goes outside" end
	elseif math.abs(x) - fx / 2 < h.hx + 0.3 and math.abs(z - h.cz) - fz / 2 < h.hz + 0.3 then
		return false, "Blocked by the house"
	end
	return true
end

local function ghostCf(def, x: number, z: number, rot: number): CFrame
	local p = plot()
	local h = p.house
	local inside = math.abs(x) < h.hx - h.wall and math.abs(z - h.cz) < h.hz - h.wall
	return p.base * CFrame.new(x, (inside and h.floor or h.ground) + def.size.Y / 2, z) * CFrame.Angles(0, -math.rad(90) * rot, 0)
end

local function updateGhost()
	if not sel or not plot() then
		if ghost then ghost.Parent = nil end
		return
	end
	if not ghost then
		ghost = Instance.new("Part")
		ghost.Anchored = true; ghost.CanCollide = false; ghost.CanQuery = false; ghost.CanTouch = false; ghost.CastShadow = false
		ghost.Material = Enum.Material.ForceField
		local box = Instance.new("SelectionBox")
		box.Adornee = ghost
		box.LineThickness = 0.06
		box.Parent = ghost
		-- arrow shows which way the front faces
		local a = Instance.new("ConeHandleAdornment")
		a.Adornee = ghost
		a.Height = 1.6; a.Radius = 0.6
		a.AlwaysOnTop = true
		a.Parent = ghost
	end
	local def = sel.def
	sel.ok, sel.why = check(def, sel.x, sel.z, sel.rot)
	ghost.Size = Vector3.new(def.size.X, math.max(def.size.Y, 0.4), def.size.Z)
	ghost.CFrame = ghostCf(def, sel.x, sel.z, sel.rot)
	local col = sel.ok and Color3.fromRGB(60, 220, 120) or Color3.fromRGB(240, 70, 70)
	ghost.Color = col
	ghost.Transparency = 0.35
	local box = ghost:FindFirstChildOfClass("SelectionBox")
	if box then box.Color3 = col end
	local cone = ghost:FindFirstChildOfClass("ConeHandleAdornment")
	if cone then
		cone.Color3 = col
		cone.CFrame = CFrame.new(0, 0, -def.size.Z / 2 - 0.4)
	end
	ghost.Parent = Workspace
end

local function setInfo()
	if not info then return end
	local d = State.data
	if sel then
		local def = sel.def
		info.Text = ("%s%s · %s%s"):format(sel.moveUid and "Moving " or "", def.name, sel.moveUid and "free" or Util.money(def.price), sel.ok == false and ("  ⚠ " .. (sel.why or "")) or "")
		info.TextColor3 = sel.ok == false and C.red or C.white
		placeBtn.Visible = true
		placeBtn.Text = isTouch and "✔ Place here" or "Click to place"
	elseif picked then
		info.Text = picked.def.name .. " selected"
		info.TextColor3 = C.white
		placeBtn.Visible = false
	else
		info.Text = ("Pick furniture below, or tap a piece to move / sell it · %d / %d placed"):format(d and d.plot and #d.plot.furniture or 0, plot() and Housing.TIERS[plot().tier].limit or 0)
		info.TextColor3 = C.white
		placeBtn.Visible = false
	end
	panel.Pick.Visible = picked ~= nil and sel == nil
end

local function snap(v: number): number
	local s = grid and Housing.GRID or 0.25
	return math.floor(v / s + 0.5) * s
end

local function pointer(screen: Vector2)
	if not sel then return end
	local lp = localPoint(screen)
	if not lp then return end
	sel.x, sel.z = snap(lp.X), snap(lp.Z)
	updateGhost()
	setInfo()
end

local function clearPick()
	picked = nil
	if pickBox then pickBox.Adornee = nil end
end

local function confirm()
	if not sel then return end
	if not sel.ok then
		Feedback.toast(sel.why or "Can't place here", "bad")
		return
	end
	local ok, msg
	if sel.moveUid then
		ok, msg = Net.call("Housing", "move", sel.moveUid, sel.x, sel.z, sel.rot)
	else
		ok, msg = Net.call("Housing", "place", sel.def.id, sel.x, sel.z, sel.rot)
	end
	if ok then
		Feedback.play("thud", 0.5, 1.4)
		Feedback.good()
		if sel.moveUid then sel = nil; updateGhost() end
	else
		Feedback.toast(msg or "Can't place here", "bad")
	end
	setInfo()
end

local function choose(def)
	clearPick()
	local center = Workspace.CurrentCamera.ViewportSize / 2
	local lp = localPoint(center) or Vector3.zero
	sel = { def = def, rot = 0, x = snap(lp.X), z = snap(lp.Z) }
	updateGhost()
	setInfo()
end

local function fillItems()
	UI.clear(itemRow)
	local d = State.data
	for _, def in ipairs(Housing.FURNITURE) do
		if def.cat == category then
			local can = d and d.money >= def.price
			local b = UI.button(itemRow, "", { Size = UDim2.fromOffset(122, 56), BackgroundColor3 = C.card }, function() choose(def) end)
			UI.label(b, def.name, 13, C.text, F.bold, { Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 18) })
			UI.label(b, Util.money(def.price) .. (def.use and "  ✦" or ""), 12, can and C.greenDark or C.red, F.bold, { Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 0, 16) })
			UI.label(b, def.use and ({ bed = "restores energy", fridge = "stores food", stove = "cooking", shower = "+happiness", tv = "+happiness", computer = "career stats", garage = "vehicle spot",
				repair = "cheap repairs", sit = "seat" })[def.use] or "decor", 10, C.sub, F.med, { Position = UDim2.fromOffset(8, 40), Size = UDim2.new(1, -16, 0, 12) })
		end
	end
end

local function buildUi()
	gui = UI.screen("GoDashBuild", Layers.Interaction)
	gui.Enabled = false
	-- bottom edge of a stage: inside the safe margin, beside a docked phone, and between the touch
	-- controls (UIState.sideReserve). UIState lifts the offer / prompt stack above this panel.
	local stage = Layout.stage(gui)
	panel = UI.panel(stage, { Name = "BuildPanel", BackgroundTransparency = 0.1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, UIState.BUILD_PANEL_H) }, UI.R.lg)
	local function fitPanel()
		-- 720 wide when that is sure to fit, otherwise whatever the stage leaves between the corners
		local reserve = UIState.sideReserve()
		local right = Layout.insets()
		if Layout.canvas.X - right - 2 * Layout.m.margin - 2 * reserve - 120 >= 720 then
			panel.Size = UDim2.fromOffset(720, UIState.BUILD_PANEL_H)
		else
			panel.Size = UDim2.new(1, -2 * reserve, 0, UIState.BUILD_PANEL_H)
		end
	end
	fitPanel()
	UIState.onChange(fitPanel)
	info = UI.label(panel, "", 14, C.white, F.bold, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -330, 0, 24) })
	local tools = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6), Size = UDim2.fromOffset(310, 30), Parent = panel })
	local tl = UI.list(tools, 6, true)
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	UI.button(tools, "⟳ Rotate" .. (isTouch and "" or " [R]"), { Size = UDim2.fromOffset(96, 28), TextSize = 12, BackgroundColor3 = C.blue }, function()
		if sel then sel.rot = (sel.rot + 1) % 4; updateGhost(); setInfo() end
	end)
	gridBtn = UI.button(tools, "Grid: ON", { Size = UDim2.fromOffset(78, 28), TextSize = 12, BackgroundColor3 = Color3.fromRGB(90, 100, 120) }, function()
		grid = not grid
		gridBtn.Text = grid and "Grid: ON" or "Free"
	end)
	UI.button(tools, "Cancel", { Size = UDim2.fromOffset(60, 28), TextSize = 12, BackgroundColor3 = Color3.fromRGB(90, 100, 120) }, function()
		sel = nil; clearPick(); updateGhost(); setInfo()
	end)
	UI.button(tools, "Done", { Size = UDim2.fromOffset(52, 28), TextSize = 12, BackgroundColor3 = C.red }, function() Build.setActive(false) end)

	local tabs = UI.new("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 40), Size = UDim2.new(1, -20, 0, 32), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollBarThickness = 0, ScrollingDirection = Enum.ScrollingDirection.X, Parent = panel })
	UI.list(tabs, 6, true)
	local tabButtons = {}
	for _, cat in ipairs(Housing.CATEGORIES) do
		tabButtons[cat] = UI.button(tabs, cat, { Size = UDim2.fromOffset(98, 28), TextSize = 12, BackgroundColor3 = cat == category and C.green or Color3.fromRGB(60, 66, 76) }, function()
			category = cat
			for c2, b in pairs(tabButtons) do b.BackgroundColor3 = c2 == cat and C.green or Color3.fromRGB(60, 66, 76) end
			fillItems()
		end)
	end
	itemRow = UI.new("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 78), Size = UDim2.new(1, -20, 0, 62), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollBarThickness = 3, ScrollingDirection = Enum.ScrollingDirection.X, Parent = panel })
	UI.list(itemRow, 6, true)
	placeBtn = UI.button(panel, "Click to place", { Position = UDim2.fromOffset(10, 146), Size = UDim2.new(1, -20, 0, 32), TextSize = 14, Visible = false }, function()
		if isTouch then confirm() end
	end)
	local pick = UI.new("Frame", { Name = "Pick", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 146), Size = UDim2.new(1, -20, 0, 32), Visible = false, Parent = panel })
	UI.list(pick, 8, true)
	UI.button(pick, "✥ Move", { Size = UDim2.new(0.5, -4, 1, 0), TextSize = 14, BackgroundColor3 = C.blue }, function()
		if not picked then return end
		local d = State.data
		for _, rec in ipairs(d.plot.furniture) do
			if rec.uid == picked.uid then
				sel = { def = picked.def, rot = rec.rot, x = rec.x, z = rec.z, moveUid = rec.uid }
			end
		end
		clearPick()
		updateGhost(); setInfo()
	end)
	UI.button(pick, "Sell (50% back)", { Size = UDim2.new(0.5, -4, 1, 0), TextSize = 14, BackgroundColor3 = C.red }, function()
		if not picked then return end
		local ok, msg = Net.call("Housing", "remove", picked.uid)
		Feedback.toast(msg or "", ok and "good" or "bad")
		clearPick(); setInfo()
	end)
	pickBox = Instance.new("SelectionBox")
	pickBox.Color3 = C.yellow
	pickBox.LineThickness = 0.08
	pickBox.Parent = Workspace
end

local function tryPick(screen: Vector2)
	local cam = Workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	if not hit then clearPick(); setInfo(); return end
	local model = hit.Instance:FindFirstAncestorWhichIsA("Model")
	while model and not model:HasTag("Furniture") do model = model:FindFirstAncestorWhichIsA("Model") end
	local p = plot()
	if model and p and model:FindFirstAncestor(p.id) then
		picked = { uid = model:GetAttribute("Uid"), def = Housing.ById[model.Name], model = model }
		pickBox.Adornee = model
		Feedback.click()
	else
		clearPick()
	end
	setInfo()
end

function Build.setActive(v: boolean)
	if v == active then return end
	if v and not plot() then
		Feedback.toast("You need your own plot to build", "bad")
		return
	end
	active = v
	gui.Enabled = v
	UIState.set("build", v) -- hides the job card and speedometer, lifts the offer / prompt stack
	Env.forceRoofHidden = v
	sel = nil
	clearPick()
	updateGhost()
	for _, c in ipairs(conns) do c:Disconnect() end
	conns = {}
	if v then
		fillItems()
		setInfo()
		Feedback.toast("🛠 Build mode: pick furniture, then place it on your plot", "good")
		table.insert(conns, UserInputService.InputChanged:Connect(function(input, processed)
			if input.UserInputType == Enum.UserInputType.MouseMovement then pointer(Vector2.new(input.Position.X, input.Position.Y)) end
		end))
		table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.R and sel then
				sel.rot = (sel.rot + 1) % 4; updateGhost(); setInfo()
			elseif input.KeyCode == Enum.KeyCode.G then
				grid = not grid; gridBtn.Text = grid and "Grid: ON" or "Free"
			elseif input.KeyCode == Enum.KeyCode.X then
				sel = nil; clearPick(); updateGhost(); setInfo()
			end
			if processed then return end
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				if sel then pointer(pos); confirm() else tryPick(pos) end
			elseif input.UserInputType == Enum.UserInputType.Touch then
				if sel then pointer(pos) else tryPick(pos) end
			end
		end))
		table.insert(conns, RunService.Heartbeat:Connect(function()
			-- walking away from the plot ends build mode
			local p = plot()
			local char = player.Character
			local r = char and char:FindFirstChild("HumanoidRootPart")
			if not p or not r or (r.Position - p.base.Position).Magnitude > 210 then Build.setActive(false) end
		end))
	end
end

function Build.isActive(): boolean return active end

function Build.start()
	buildUi()
	Phone.onBuild = function() Build.setActive(true) end
	State.onData(function(keys)
		if active and (keys.money or keys.plot) then fillItems(); setInfo() end
	end)
end

return Build
