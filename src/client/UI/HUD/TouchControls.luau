-- Touch driving controls (phones and tablets). Steering lives in the bottom-left corner with the
-- exit / lights / signal row above it; gas, brake and handbrake live in the bottom-right corner.
-- Every target is at least 56 layout px. The buttons write Drive.touch, exactly as before; when
-- the controls hide (leaving the vehicle, phone opened) every input is released so nothing sticks.
--
-- 2026-11-18 (owner: "on the phone the vehicle is very hard to control"): steering was two on/off
-- buttons, so every touch was full lock and riders zig-zagged; and Roblox's own thumbstick stayed
-- live under them, a second set of controls fighting the first. Now:
--   * one steering pad: put your thumb on it and slide; how far from the middle you are is how hard
--     you turn (a gentle nudge near the middle, full lock at the ends), and it centres when you let go
--   * Roblox's touch thumbstick and jump button are hidden while you drive and come back on foot
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local UIRoot = script.Parent.Parent
local UI = require(UIRoot.Kit)
local UIState = require(UIRoot.Core.UIState)
local Drive = require(UIRoot.Parent.Drive)
local State = require(UIRoot.Parent.State)

local Touch = {}
local C, F = UI.C, UI.F

local IDLE_ALPHA = 0.3
local PAD_W, PAD_H = 210, 92
local SMALL = 56
local GAP = 10
local DEAD = 0.07 -- share of the half-width that does nothing (a resting thumb)

-- stage = the HUD stage (corners are already inside the safe margin).
function Touch.build(stage: Frame)
	local root = UI.new("Frame", { Name = "Pedals", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = stage })
	local t = Drive.touch
	local holds = {} :: { { button: GuiObject, release: () -> () } }

	local function hold(parent: Instance, text: string, pos: UDim2, size: UDim2, color: Color3, textSize: number, onDown: () -> (), onUp: () -> ())
		local b = UI.new("TextButton", { Text = text, Font = F.black, TextSize = textSize, TextColor3 = C.white, BackgroundColor3 = color, BackgroundTransparency = IDLE_ALPHA,
			AutoButtonColor = false, Position = pos, Size = size, Parent = parent })
		UI.corner(b, UI.R.lg)
		UI.stroke(b, C.white, 1, 0.6)
		b.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
				b.BackgroundTransparency = 0
				onDown()
			end
		end)
		b.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
				b.BackgroundTransparency = IDLE_ALPHA
				onUp()
			end
		end)
		table.insert(holds, { button = b, release = onUp })
		return b
	end

	-- 2026-11-18 (owner: still hard on the phone): the pad no longer has to be hit exactly. Put a thumb anywhere on the
	-- lower-left part of the screen and the pad jumps under it; sliding from where you touched steers. The pad shows
	-- where the zone is while idle. Buttons drawn above the zone (EXIT, lights, signals) still take their own taps.
	local zone = UI.new("TextButton", { Name = "SteerZone", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(0.42, 0.6), Parent = root })
	-- left corner: the steering pad, with the small buttons in a row above
	local left = UI.new("Frame", { Name = "Left", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(math.max(PAD_W, SMALL * 4 + 8 * 3 + 8), PAD_H + GAP + SMALL), Parent = root })
	local PAD_HOME = UDim2.new(0, 0, 1, -PAD_H)
	local pad = UI.new("Frame", { Name = "SteerPad", BackgroundColor3 = C.dark, BackgroundTransparency = IDLE_ALPHA,
		Position = PAD_HOME, Size = UDim2.fromOffset(PAD_W, PAD_H), Parent = left })
	UI.corner(pad, PAD_H // 2)
	UI.stroke(pad, C.white, 1, 0.6)
	for _, s in ipairs({ { "◀", 0 }, { "▶", 1 } }) do
		UI.label(pad, s[1], 22, C.white, F.black, { AnchorPoint = Vector2.new(s[2], 0.5), Position = UDim2.new(s[2], s[2] == 0 and 14 or -14, 0.5, 0),
			Size = UDim2.fromOffset(28, 28), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.25 })
	end
	UI.new("Frame", { BackgroundColor3 = C.white, BackgroundTransparency = 0.7, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, PAD_H - 30), Parent = pad })
	local knob = UI.new("Frame", { Name = "Knob", BackgroundColor3 = C.white, BackgroundTransparency = 0.15, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(PAD_H - 26, PAD_H - 26), Parent = pad })
	UI.corner(knob, (PAD_H - 26) // 2)
	local steerInput: InputObject? = nil
	local originX = 0
	local function steerAt(x: number)
		local half = pad.AbsoluteSize.X / 2
		local k = math.clamp((x - originX) / (half * 0.86), -1, 1)
		if math.abs(k) < DEAD then k = 0 else k = (k - DEAD * math.sign(k)) / (1 - DEAD) end
		-- a little curve: fine control near the middle, full lock still at the end
		t.steer = math.sign(k) * math.abs(k) ^ 1.35
		local s = math.max(0.1, pad.AbsoluteSize.X / PAD_W) -- screen px per layout px
		knob.Position = UDim2.new(0.5, k * (half / s - (PAD_H - 26) / 2 - 4), 0.5, 0)
	end
	local function steerRelease()
		steerInput = nil
		t.steer = 0
		pad.BackgroundTransparency = IDLE_ALPHA
		pad.Position = PAD_HOME
		knob.Position = UDim2.fromScale(0.5, 0.5)
	end
	zone.InputBegan:Connect(function(i)
		if steerInput then return end
		if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
			steerInput = i
			originX = i.Position.X
			-- the pad jumps under the thumb (layout px inside the Left frame)
			local s = math.max(0.1, pad.AbsoluteSize.X / PAD_W)
			pad.Position = UDim2.fromOffset((i.Position.X - left.AbsolutePosition.X) / s - PAD_W / 2, (i.Position.Y - left.AbsolutePosition.Y) / s - PAD_H / 2)
			pad.BackgroundTransparency = 0.1
			steerAt(i.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if steerInput and (i == steerInput or (i.UserInputType == Enum.UserInputType.MouseMovement and steerInput.UserInputType == Enum.UserInputType.MouseButton1)) then
			steerAt(i.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if steerInput and (i == steerInput or (i.UserInputType == Enum.UserInputType.MouseButton1 and steerInput.UserInputType == Enum.UserInputType.MouseButton1)) then
			steerRelease()
		end
	end)
	table.insert(holds, { button = pad, release = steerRelease })

	local small = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, SMALL), Parent = left })
	UI.list(small, 8, true)
	UI.button(small, "EXIT", { Size = UDim2.fromOffset(SMALL + 8, SMALL), BackgroundColor3 = C.chip, TextSize = 13, LayoutOrder = 1 }, function() Drive.leave() end)
	UI.button(small, "💡", { Size = UDim2.fromOffset(SMALL, SMALL), BackgroundColor3 = C.chip, TextSize = 20, LayoutOrder = 2 }, function() Drive.toggleLights() end)
	UI.button(small, "◁", { Size = UDim2.fromOffset(SMALL, SMALL), BackgroundColor3 = C.chip, TextSize = 18, LayoutOrder = 3 }, function() Drive.setSignal(Drive.info.signal == -1 and 0 or -1) end)
	UI.button(small, "▷", { Size = UDim2.fromOffset(SMALL, SMALL), BackgroundColor3 = C.chip, TextSize = 18, LayoutOrder = 4 }, function() Drive.setSignal(Drive.info.signal == 1 and 0 or 1) end)

	-- right corner: brake, gas, handbrake above the brake
	local GAS, BRAKE_H, HAND = 100, 84, 60
	local right = UI.new("Frame", { Name = "Right", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(GAS * 2 + GAP, BRAKE_H + GAP + HAND), Parent = root })
	local gas, brk = false, false
	local function throttleSync() t.throttle = (gas and 1 or 0) - (brk and 1 or 0) end
	-- "auto gas" (Phone > Settings, 2026-11-18): a tap on GAS starts cruising, BRAKE stops it; the button stays lit
	local function autoGasOn(): boolean
		local d = State.data
		return d ~= nil and d.settings ~= nil and d.settings.autoGas == true
	end
	local gasBtn
	gasBtn = hold(right, "GAS", UDim2.new(1, -GAS, 1, -GAS), UDim2.fromOffset(GAS, GAS), C.green, 18, function()
		gas = true
		if autoGasOn() then Drive.autoGas = true end
		throttleSync()
	end, function()
		gas = false
		throttleSync()
	end)
	hold(right, "BRAKE", UDim2.new(0, 0, 1, -BRAKE_H), UDim2.fromOffset(GAS, BRAKE_H), C.red, 15, function()
		brk = true
		Drive.autoGas = false
		throttleSync()
	end, function() brk = false; throttleSync() end)
	task.spawn(function()
		while root.Parent do
			task.wait(0.2)
			if Drive.autoGas and not gas then
				gasBtn.Text = "AUTO"
				gasBtn.BackgroundTransparency = 0.05
			elseif gasBtn.Text ~= "GAS" then
				gasBtn.Text = "GAS"
				if not gas then gasBtn.BackgroundTransparency = IDLE_ALPHA end
			end
		end
	end)
	hold(right, "P", UDim2.new(0, 0, 0, 0), UDim2.fromOffset(HAND, HAND), C.orange, 24, function() t.handbrake = true end, function() t.handbrake = false end)

	local function releaseAll()
		for _, h in ipairs(holds) do
			h.button.BackgroundTransparency = IDLE_ALPHA
			h.release()
		end
		t.throttle = 0
		t.steer = 0
		t.handbrake = false
		Drive.autoGas = false
	end
	UIState.bind("touch", root, nil, releaseAll)
	-- Roblox's own thumbstick and jump button only on foot: in a vehicle these pedals are the controls
	local function sync()
		local driving = root.Visible or UIState.get("driving") == true
		pcall(function()
			if GuiService.TouchControlsEnabled == driving then GuiService.TouchControlsEnabled = not driving end
		end)
	end
	root:GetPropertyChangedSignal("Visible"):Connect(sync)
	UIState.onChange(sync)
	sync()
	return root
end

return Touch
