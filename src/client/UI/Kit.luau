-- GoDash UI kit: one theme, glass panels, rounded cards, pressable buttons, tweens. Everything on
-- screen is built from these helpers so the look stays consistent. Tokens live in Core/Theme,
-- screen regions and breakpoints in Core/Layout, stacking in Core/Layers, visibility rules in
-- Core/UIState.
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Theme = require(script.Parent.Core.Theme)
local Layout = require(script.Parent.Core.Layout)
local Layers = require(script.Parent.Core.Layers)

local UI = {}

UI.Theme = Theme
UI.Layout = Layout
UI.Layers = Layers
UI.C = Theme.C
UI.F = Theme.F
UI.T = Theme.T
UI.R = Theme.R
UI.S = Theme.S

UI.clickSound = nil :: (() -> ())? -- set by Feedback

function UI.new(class: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(class)
	if class == "Frame" or class == "TextLabel" or class == "TextButton" or class == "ImageLabel" or class == "ScrollingFrame" or class == "TextBox" then
		(inst :: any).BorderSizePixel = 0
	end
	if props then
		local parent = props.Parent
		for k, v in pairs(props) do
			if k ~= "Parent" then (inst :: any)[k] = v end
		end
		if children then
			for _, c in ipairs(children) do c.Parent = inst end
		end
		if parent then inst.Parent = parent end
	elseif children then
		for _, c in ipairs(children) do c.Parent = inst end
	end
	return inst
end

function UI.corner(inst: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12)
	c.Parent = inst
	return c
end

function UI.stroke(inst: Instance, color: Color3?, thickness: number?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or UI.C.line
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

function UI.pad(inst: Instance, l: number, t: number?, r: number?, b: number?)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, l)
	p.PaddingTop = UDim.new(0, t or l)
	p.PaddingRight = UDim.new(0, r or l)
	p.PaddingBottom = UDim.new(0, b or t or l)
	p.Parent = inst
	return p
end

function UI.list(inst: Instance, gap: number?, horizontal: boolean?, align: Enum.HorizontalAlignment?)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap or 8)
	l.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = align or Enum.HorizontalAlignment.Left
	l.VerticalAlignment = horizontal and Enum.VerticalAlignment.Center or Enum.VerticalAlignment.Top
	l.Parent = inst
	return l
end

function UI.tween(inst: Instance, t: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

-- Text. size = text size in px; props override anything.
function UI.label(parent: Instance?, text: string, size: number?, color: Color3?, font: Enum.Font?, props: { [string]: any }?): TextLabel
	local l = UI.new("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextSize = size or 14, TextColor3 = color or UI.C.text, Font = font or UI.F.med,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, Size = UDim2.new(1, 0, 0, (size or 14) + 6),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if props then
		for k, v in pairs(props) do (l :: any)[k] = v end
	end
	l.Parent = parent
	return l
end

-- Let a one-line label shrink (down to minSize) instead of clipping when its text is too long.
function UI.fitText(label: TextLabel | TextButton, maxSize: number?, minSize: number?)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize or label.TextSize
	c.MinTextSize = minSize or 9
	c.Parent = label
	label.TextScaled = true
	return label
end

function UI.card(parent: Instance?, props: { [string]: any }?): Frame
	local f = UI.new("Frame", { BackgroundColor3 = UI.C.card, Size = UDim2.new(1, 0, 0, 60) })
	UI.corner(f, 14)
	if props then
		for k, v in pairs(props) do (f :: any)[k] = v end
	end
	f.Parent = parent
	return f
end

-- HUD surface: dark translucent glass with a 1 px light edge.
function UI.panel(parent: Instance?, props: { [string]: any }?, radius: number?): Frame
	local f = UI.new("Frame", { BackgroundColor3 = UI.C.glass, BackgroundTransparency = Theme.GLASS_ALPHA })
	UI.corner(f, radius or Theme.R.lg)
	UI.stroke(f, UI.C.white, 1, Theme.STROKE_ALPHA)
	if props then
		for k, v in pairs(props) do (f :: any)[k] = v end
	end
	f.Parent = parent
	return f
end

-- Pressable button with a quick scale bounce.
function UI.button(parent: Instance?, text: string, props: { [string]: any }?, onClick: (() -> ())?): TextButton
	local b = UI.new("TextButton", {
		Text = text, Font = UI.F.bold, TextSize = 15, TextColor3 = UI.C.white, BackgroundColor3 = UI.C.green,
		AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 42),
	})
	UI.corner(b, 12)
	if props then
		for k, v in pairs(props) do (b :: any)[k] = v end
	end
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.MouseButton1Down:Connect(function() UI.tween(scale, 0.07, { Scale = 0.94 }) end)
	local function up() UI.tween(scale, 0.16, { Scale = 1 }, Enum.EasingStyle.Back) end
	b.MouseButton1Up:Connect(up)
	b.MouseLeave:Connect(up)
	b.MouseButton1Click:Connect(function()
		if UI.clickSound then UI.clickSound() end
		if onClick then onClick() end
	end)
	b.Parent = parent
	return b
end

-- Thin progress bar. Returns the track, a tweened setter (0..1) and the fill frame (set its Size
-- directly for values that change every frame). The setter ignores repeats of the same value, so
-- it is safe to call from a frame loop.
function UI.bar(parent: Instance?, color: Color3, height: number?): (Frame, (number) -> (), Frame)
	local track = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.82, Size = UDim2.new(1, 0, 0, height or 8) })
	UI.corner(track, 99)
	local fill = UI.new("Frame", { BackgroundColor3 = color, Size = UDim2.fromScale(0.5, 1), Parent = track })
	UI.corner(fill, 99)
	track.Parent = parent
	local last = -1
	return track, function(v: number)
		if v ~= v then v = 0 end
		v = math.clamp(v, 0, 1)
		if math.abs(v - last) < 0.004 then return end
		last = v
		UI.tween(fill, 0.25, { Size = UDim2.fromScale(v, 1) })
	end, fill
end

-- A bar track styled for glass panels.
function UI.glassBar(parent: Instance?, color: Color3, height: number?): (Frame, (number) -> (), Frame)
	local track, set, fill = UI.bar(parent, color, height)
	track.BackgroundColor3 = UI.C.white
	track.BackgroundTransparency = Theme.TRACK_ALPHA
	return track, set, fill
end

function UI.scroll(parent: Instance?, props: { [string]: any }?): ScrollingFrame
	local s = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3, ScrollBarImageColor3 = UI.C.sub, ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	})
	if props then
		for k, v in pairs(props) do (s :: any)[k] = v end
	end
	s.Parent = parent
	return s
end

-- A ScreenGui on the shared layout canvas (see Core/Layout): scaled to the viewport, kept clear
-- of Roblox's top bar and of device cut-outs. order = a Core/Layers value.
function UI.screen(name: string, order: number?): (ScreenGui, UIScale)
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = order or Layers.HUD
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	Layout.fitScale(scale)
	gui.Parent = pg
	return gui, scale
end

-- Quick "appear" bounce for a widget that owns a UIScale named Pop (made on first use).
function UI.pop(inst: Instance, from: number?)
	local sc: any = inst:FindFirstChild("Pop")
	if not sc then
		sc = Instance.new("UIScale")
		sc.Name = "Pop"
		sc.Parent = inst
	end
	sc.Scale = from or 0.9
	UI.tween(sc, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
end

function UI.clear(inst: Instance, keep: { string }?)
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("GuiObject") and not (keep and table.find(keep, c.Name)) then c:Destroy() end
	end
end

return UI
