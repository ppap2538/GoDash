-- Layout: one scale, three breakpoints and a set of named screen regions shared by every
-- ScreenGui. Widgets are parented into regions (which stack their children with list layouts)
-- instead of being given hand-tuned pixel positions, so two widgets can never land on top of
-- each other. Everything is recomputed when the viewport changes, never per frame.
--
--   canvas     the screen measured in layout pixels (viewport / scale). 720 high on desktops
--              and tablets, 540 high on short screens (phones in landscape) so touch targets
--              stay finger sized.
--   breakpoint "compact" (short or narrow), "regular", "wide" (ultrawide)
--   stage      a full-screen frame with the safe margin as padding. Its right edge moves in
--              when the phone is docked, so every region re-flows around the phone.
--   regions    TopLeft, TopCenter, TopRight, BottomLeft, BottomCenter, BottomRight, Center
--              (inside a stage) and RightPanel (the phone dock, see Layout.rightPanel).
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Layout = {}

-- (2026-11-17, owner: "some UI is too big and covers the screen": was 720 / 540, so everything is ~10% / ~5% smaller)
Layout.BASE_H = 800
Layout.COMPACT_BASE_H = 570
Layout.MIN_W = 760
Layout.PHONE_W = 340
Layout.PHONE_MAX_H = 620
Layout.PHONE_GAP = 12

-- Per-breakpoint metrics (layout pixels).
--   margin  distance from the safe-area edge      gap   space between stacked widgets
--   colW    width of the top-left column          navW  width of the top-right cluster
--   mapH    minimap height                        hit   minimum touch target
local METRICS = {
	compact = { margin = 12, gap = 6, colW = 232, navW = 150, mapH = 110, hit = 56 },
	regular = { margin = 16, gap = 8, colW = 260, navW = 190, mapH = 150, hit = 56 },
	wide = { margin = 28, gap = 8, colW = 280, navW = 210, mapH = 164, hit = 56 },
}

Layout.isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
Layout.scale = 1
Layout.canvas = Vector2.new(1280, 720)
Layout.breakpoint = "regular"
Layout.short = false -- phone in landscape (or a very short window)
Layout.roomy = true -- wide enough to keep the whole HUD next to a docked phone
Layout.m = METRICS.regular

local listeners = {} :: { () -> () }
local scales = {} :: { UIScale }
local stages = {} :: { { frame: Frame, pad: UIPadding, regions: { [string]: Frame } } }
local docks = {} :: { Frame }
local rightInset, bottomInset = 0, 0
local camConn: RBXScriptConnection? = nil

local REGION_DEF = {
	-- name = { anchor, horizontal?, HorizontalAlignment, VerticalAlignment }
	TopLeft = { Vector2.new(0, 0), false, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top },
	TopCenter = { Vector2.new(0.5, 0), false, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top },
	TopRight = { Vector2.new(1, 0), false, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top },
	BottomLeft = { Vector2.new(0, 1), false, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom },
	BottomCenter = { Vector2.new(0.5, 1), false, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom },
	BottomRight = { Vector2.new(1, 1), true, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom },
	Center = { Vector2.new(0.5, 0.5), false, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center },
}

local function placeRegion(name: string, f: Frame)
	local m = Layout.m
	if name == "TopLeft" then
		f.Position = UDim2.new(0, 0, 0, 0)
		f.Size = UDim2.new(0, m.colW, 1, 0)
	elseif name == "TopCenter" then
		-- the strip between the top-left column and the navigation cluster
		f.Position = UDim2.new(0.5, 0, 0, 0)
		f.Size = UDim2.new(1, -2 * (m.colW + 12), 1, 0)
	elseif name == "TopRight" then
		f.Position = UDim2.new(1, 0, 0, 0)
		f.Size = UDim2.new(0, m.navW, 1, 0)
	elseif name == "BottomLeft" then
		f.Position = UDim2.new(0, 0, 1, 0)
		f.Size = UDim2.new(0, 280, 0.5, 0)
	elseif name == "BottomCenter" then
		f.Position = UDim2.new(0.5, 0, 1, -bottomInset)
		f.Size = UDim2.new(1, 0, 0.9, 0)
	elseif name == "BottomRight" then
		f.Position = UDim2.new(1, 0, 1, 0)
		f.Size = UDim2.new(0, 320, 0, 100)
	else -- Center
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(1, 1)
	end
end

-- Rough height of the top inset (Roblox top bar) in layout px, used only to decide whether a
-- fixed-size panel is sure to fit; real sizes come from scale-based UDim2s, not from this.
local TOP_ALLOWANCE = 70

local function placeDock(dock: Frame)
	local m = Layout.m
	dock.Position = UDim2.new(1, -m.margin, 0.5, 0)
	if Layout.canvas.Y - 2 * m.margin - TOP_ALLOWANCE >= Layout.PHONE_MAX_H then
		dock.Size = UDim2.fromOffset(Layout.PHONE_W, Layout.PHONE_MAX_H) -- tall screen: full-size phone
	else
		dock.Size = UDim2.new(0, Layout.PHONE_W, 1, -2 * m.margin) -- otherwise fill the safe height
	end
end

local function compute(): boolean
	local cam = Workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(1280, 720)
	if v.X < 2 or v.Y < 2 then return false end
	local short = v.Y < 560
	local base = short and Layout.COMPACT_BASE_H or Layout.BASE_H
	local scale = math.clamp(math.min(v.Y / base, v.X / Layout.MIN_W), 0.5, 2.4)
	local cx, cy = v.X / scale, v.Y / scale
	local bp = "regular"
	if short or cx < 1000 then
		bp = "compact"
	elseif cx >= 1600 then
		bp = "wide"
	end
	local roomy = (not short) and cx >= 1136
	local changed = math.abs(scale - Layout.scale) > 1e-4 or bp ~= Layout.breakpoint or roomy ~= Layout.roomy
		or math.abs(cx - Layout.canvas.X) > 0.5 or math.abs(cy - Layout.canvas.Y) > 0.5
	Layout.scale = scale
	Layout.canvas = Vector2.new(cx, cy)
	Layout.breakpoint = bp
	Layout.short = short
	Layout.roomy = roomy
	Layout.m = METRICS[bp]
	return changed
end

local function applyAll()
	local m = Layout.m
	for _, s in ipairs(scales) do s.Scale = Layout.scale end
	for _, st in ipairs(stages) do
		local u = UDim.new(0, m.margin)
		st.pad.PaddingLeft = u; st.pad.PaddingRight = u; st.pad.PaddingTop = u; st.pad.PaddingBottom = u
		for name, f in pairs(st.regions) do placeRegion(name, f) end
	end
	for _, d in ipairs(docks) do placeDock(d) end
end

local function refresh()
	if not compute() then return end
	applyAll()
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn)
		if not ok then warn("[Layout] listener error: " .. tostring(err)) end
	end
end

local function watchCamera()
	if camConn then camConn:Disconnect(); camConn = nil end
	local cam = Workspace.CurrentCamera
	if cam then camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh) end
	refresh()
end

-- Called after the breakpoint, scale or canvas size changed.
function Layout.onChange(fn: () -> ())
	table.insert(listeners, fn)
end

-- Pick a value for the current breakpoint: Layout.pick({ compact = a, regular = b, wide = c }).
function Layout.pick(t: { [string]: any }): any
	local v = t[Layout.breakpoint]
	if v == nil then v = t.regular end
	return v
end

-- Keep a UIScale on the shared canvas scale.
function Layout.fitScale(scale: UIScale)
	scale.Scale = Layout.scale
	table.insert(scales, scale)
end

-- A full-size frame with the safe margin; regions live inside it.
function Layout.stage(gui: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = "Stage"
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, -rightInset, 1, 0)
	local pad = Instance.new("UIPadding")
	local u = UDim.new(0, Layout.m.margin)
	pad.PaddingLeft = u; pad.PaddingRight = u; pad.PaddingTop = u; pad.PaddingBottom = u
	pad.Parent = f
	f.Parent = gui
	table.insert(stages, { frame = f, pad = pad, regions = {} })
	return f
end

-- A named region inside a stage. Children are stacked by a list layout (LayoutOrder decides the
-- order; invisible children take no room), so widgets in one region can never overlap.
function Layout.region(stage: Frame, name: string): Frame
	local def = REGION_DEF[name]
	assert(def, "unknown region " .. tostring(name))
	local rec
	for _, st in ipairs(stages) do
		if st.frame == stage then rec = st end
	end
	assert(rec, "Layout.region needs a frame made by Layout.stage")
	if rec.regions[name] then return rec.regions[name] end
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.AnchorPoint = def[1]
	if name ~= "Center" then
		local l = Instance.new("UIListLayout")
		l.FillDirection = def[2] and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.HorizontalAlignment = def[3]
		l.VerticalAlignment = def[4]
		l.Padding = UDim.new(0, def[2] and 12 or 8)
		l.Parent = f
	end
	placeRegion(name, f)
	f.Parent = stage
	rec.regions[name] = f
	return f
end

-- The phone dock: right edge, vertically centred, as tall as the screen allows (about 620 max).
function Layout.rightPanel(gui: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = "RightPanel"
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(1, 0.5)
	placeDock(f)
	f.Parent = gui
	table.insert(docks, f)
	return f
end

-- right: room kept free on the right for the docked phone. bottom: room kept free under the
-- bottom-centre region (build panel). Decided by UIState.
function Layout.setInsets(right: number, bottom: number)
	if right ~= rightInset then
		rightInset = right
		local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, st in ipairs(stages) do
			TweenService:Create(st.frame, info, { Size = UDim2.new(1, -right, 1, 0) }):Play()
		end
	end
	if bottom ~= bottomInset then
		bottomInset = bottom
		for _, st in ipairs(stages) do
			local f = st.regions.BottomCenter
			if f then placeRegion("BottomCenter", f) end
		end
	end
end

function Layout.insets(): (number, number)
	return rightInset, bottomInset
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
compute()
watchCamera()

return Layout
