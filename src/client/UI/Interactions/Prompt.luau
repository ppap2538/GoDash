-- Contextual interaction prompt. Replaces Roblox's default ProximityPrompt bubbles with compact
-- rows near bottom-centre:  [E]  <ActionText>  /  <ObjectText> smaller below. On touch the row is
-- a tappable button. Only prompts the engine reports as shown are drawn (at most one per key),
-- keyboard keys keep working natively, and a thin bar shows hold progress.
--
-- Prompts are created on the server (and by Peds on the client) and stream in and out, so every
-- ProximityPrompt under Workspace is switched to the Custom style as it appears.
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local UIRoot = script.Parent.Parent
local UI = require(UIRoot.Kit)
local Layout = require(UIRoot.Core.Layout)
local UIState = require(UIRoot.Core.UIState)

local Prompt = {}
local C, F, T = UI.C, UI.F, UI.T

local MAX_ROWS = 3
local WIDTH = 300
local ROW_H = Layout.isTouch and 60 or 52
local ROW_GAP = 6

type Entry = { prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType, conns: { RBXScriptConnection } }
local shown = {} :: { Entry }
local rows = {} :: { any }
local container: Frame

local function restyle(inst: Instance)
	if inst:IsA("ProximityPrompt") and inst.Style ~= Enum.ProximityPromptStyle.Custom then
		inst.Style = Enum.ProximityPromptStyle.Custom
	end
	-- prompts meant for one player ("Drive" on your own vehicle) or for everyone else ("Ride along")
	-- (server/VehicleService); Enabled set here is local to this client
	if inst:IsA("ProximityPrompt") then
		local me = game:GetService("Players").LocalPlayer.UserId
		local only, notFor = inst:GetAttribute("ForUser"), inst:GetAttribute("NotForUser")
		if (only ~= nil and only ~= me) or (notFor ~= nil and notFor == me) then
			inst.Enabled = false
			if not inst:GetAttribute("HiddenHook") then
				inst:SetAttribute("HiddenHook", true)
				-- the server toggles Enabled (seat taken / free) and that replicates: keep it hidden here
				inst:GetPropertyChangedSignal("Enabled"):Connect(function()
					if inst.Enabled then inst.Enabled = false end
				end)
			end
		end
	end
end

local function keyText(e: Entry): string
	if e.inputType == Enum.ProximityPromptInputType.Gamepad then
		return (e.prompt.GamepadKeyCode.Name:gsub("^Button", ""))
	end
	local code = e.prompt.KeyboardKeyCode
	local ok, s = pcall(function() return UserInputService:GetStringForKeyCode(code) end)
	if ok and s and s ~= "" then return s end
	return code.Name
end

local function stopHold(row: any)
	if row.tween then
		row.tween:Cancel()
		row.tween = nil
	end
	row.fill.Size = UDim2.fromScale(0, 1)
end

local function render()
	local n = math.min(#shown, MAX_ROWS)
	for i = 1, MAX_ROWS do
		local row = rows[i]
		local e = shown[i]
		if e then
			local p = e.prompt
			local tap = Layout.isTouch or e.inputType == Enum.ProximityPromptInputType.Touch
			if row.prompt ~= p then
				-- the row now shows another prompt: let go of the old one
				if row.held and row.prompt then row.prompt:InputHoldEnd() end
				row.held = false
				stopHold(row)
			end
			row.prompt = p
			row.key.Text = tap and "TAP" or keyText(e)
			row.key.TextSize = tap and 10 or 15
			row.cap.BackgroundColor3 = tap and C.green or C.white
			row.cap.BackgroundTransparency = tap and 0 or 0.88
			local object = p.ObjectText
			row.action.Text = p.ActionText ~= "" and p.ActionText or "Interact"
			row.object.Text = object
			row.object.Visible = object ~= ""
			row.action.Position = UDim2.new(0, 56, 0.5, object ~= "" and -19 or -10)
			row.track.Visible = p.HoldDuration > 0
			row.button.Visible = true
		else
			if row.held and row.prompt then row.prompt:InputHoldEnd() end
			row.held = false
			row.prompt = nil
			stopHold(row)
			row.button.Visible = false
		end
	end
	container.Size = UDim2.fromOffset(WIDTH, math.max(n, 1) * (ROW_H + ROW_GAP) - ROW_GAP)
	UIState.set("prompts", n > 0)
end

local function rowFor(p: ProximityPrompt): any
	for i = 1, MAX_ROWS do
		if rows[i].prompt == p then return rows[i] end
	end
	return nil
end

local function remove(p: ProximityPrompt)
	for i = #shown, 1, -1 do
		if shown[i].prompt == p then
			for _, c in ipairs(shown[i].conns) do c:Disconnect() end
			table.remove(shown, i)
		end
	end
end

local function onShown(p: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	restyle(p)
	remove(p)
	local e: Entry = { prompt = p, inputType = inputType, conns = {} }
	table.insert(e.conns, p:GetPropertyChangedSignal("ActionText"):Connect(render))
	table.insert(e.conns, p:GetPropertyChangedSignal("ObjectText"):Connect(render))
	table.insert(e.conns, p.PromptButtonHoldBegan:Connect(function()
		local row = rowFor(p)
		if not row or p.HoldDuration <= 0 then return end
		stopHold(row)
		row.tween = TweenService:Create(row.fill, TweenInfo.new(p.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
		row.tween:Play()
	end))
	table.insert(e.conns, p.PromptButtonHoldEnded:Connect(function()
		local row = rowFor(p)
		if row then stopHold(row) end
	end))
	table.insert(shown, e)
	render()
end

local function onHidden(p: ProximityPrompt)
	remove(p)
	render()
end

local function buildRow(index: number)
	local row = {} :: any
	local button = UI.new("TextButton", { Name = "Row" .. index, Text = "", AutoButtonColor = false, BackgroundColor3 = C.glass, BackgroundTransparency = UI.Theme.GLASS_ALPHA,
		LayoutOrder = index, Size = UDim2.new(1, 0, 0, ROW_H), Visible = false, Parent = container })
	UI.corner(button, UI.R.md)
	UI.stroke(button, C.white, 1, UI.Theme.STROKE_ALPHA)
	row.button = button
	local cap = UI.new("Frame", { BackgroundColor3 = C.white, BackgroundTransparency = 0.88, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(36, 36), Parent = button })
	UI.corner(cap, UI.R.sm)
	UI.stroke(cap, C.white, 1, 0.6)
	row.cap = cap
	row.key = UI.label(cap, "E", 15, C.white, F.black, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	row.action = UI.label(button, "", 15, C.white, F.bold, { Position = UDim2.new(0, 56, 0.5, -19), Size = UDim2.new(1, -68, 0, 20) })
	UI.fitText(row.action, 15, 10)
	row.object = UI.label(button, "", T.sm, C.textDim, F.med, { Position = UDim2.new(0, 56, 0.5, 2), Size = UDim2.new(1, -68, 0, 16) })
	UI.fitText(row.object, T.sm, 9)
	local track = UI.new("Frame", { BackgroundColor3 = C.white, BackgroundTransparency = 0.8, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -4), Size = UDim2.new(1, -24, 0, 3), Visible = false, Parent = button })
	UI.corner(track, 2)
	row.track = track
	row.fill = UI.new("Frame", { BackgroundColor3 = C.green, Size = UDim2.fromScale(0, 1), Parent = track })
	UI.corner(row.fill, 2)
	row.held = false

	-- tap / click: the same hold the key would do
	button.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.Touch and i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		local p = row.prompt
		if not p or row.held then return end
		row.held = true
		button.BackgroundTransparency = 0.05
		p:InputHoldBegin()
	end)
	button.InputEnded:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.Touch and i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		button.BackgroundTransparency = UI.Theme.GLASS_ALPHA
		if row.held then
			row.held = false
			if row.prompt then row.prompt:InputHoldEnd() end
		end
	end)
	rows[index] = row
end

-- region = the BottomCenter region.
function Prompt.build(region: Frame, order: number)
	container = UI.new("Frame", { Name = "Prompts", BackgroundTransparency = 1, LayoutOrder = order, Size = UDim2.fromOffset(WIDTH, ROW_H), Parent = region })
	UI.list(container, ROW_GAP, false, Enum.HorizontalAlignment.Center)
	for i = 1, MAX_ROWS do buildRow(i) end
	UIState.bind("prompt", container, function() UI.pop(container, 0.94) end)

	ProximityPromptService.PromptShown:Connect(onShown)
	ProximityPromptService.PromptHidden:Connect(onHidden)

	-- no prompts behind the phone or a reward card: hidden prompts cannot be triggered either
	UIState.onChange(function()
		local enabled = not UIState.get("phone") and not UIState.get("modal")
		if ProximityPromptService.Enabled ~= enabled then
			ProximityPromptService.Enabled = enabled
			if not enabled and #shown > 0 then
				while #shown > 0 do remove(shown[1].prompt) end
				render()
			end
		end
	end)

	-- restyle every prompt, now and as the world streams in
	Workspace.DescendantAdded:Connect(restyle)
	task.spawn(function()
		for _, d in ipairs(Workspace:GetDescendants()) do restyle(d) end
	end)
end

return Prompt
