-- Touch driving controls (phones and tablets). Steering lives in the bottom-left corner with the
-- exit / lights / signal row above it; gas, brake and handbrake live in the bottom-right corner.
-- Every target is at least 56 layout px. The buttons write Drive.touch, exactly as before; when
-- the controls hide (leaving the vehicle, phone opened) every input is released so nothing sticks.
local UIRoot = script.Parent.Parent
local UI = require(UIRoot.Kit)
local UIState = require(UIRoot.Core.UIState)
local Drive = require(UIRoot.Parent.Drive)

local Touch = {}
local C, F = UI.C, UI.F

local IDLE_ALPHA = 0.3
local STEER = 88
local SMALL = 56
local GAP = 10

-- stage = the HUD stage (corners are already inside the safe margin).
function Touch.build(stage: Frame)
	local root = UI.new("Frame", { Name = "Pedals", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = stage })
	local t = Drive.touch
	local holds = {} :: { { button: TextButton, release: () -> () } }

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

	-- left corner: steering, with the small buttons in a row above
	local left = UI.new("Frame", { Name = "Left", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(SMALL * 4 + 8 * 3 + 8, STEER + GAP + SMALL), Parent = root })
	local steerL, steerR = false, false
	local function steerSync() t.steer = (steerR and 1 or 0) - (steerL and 1 or 0) end
	hold(left, "◀", UDim2.new(0, 0, 1, -STEER), UDim2.fromOffset(STEER, STEER), C.dark, 26, function() steerL = true; steerSync() end, function() steerL = false; steerSync() end)
	hold(left, "▶", UDim2.new(0, STEER + GAP, 1, -STEER), UDim2.fromOffset(STEER, STEER), C.dark, 26, function() steerR = true; steerSync() end, function() steerR = false; steerSync() end)
	local small = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, SMALL), Parent = left })
	UI.list(small, 8, true)
	UI.button(small, "EXIT", { Size = UDim2.fromOffset(SMALL + 8, SMALL), BackgroundColor3 = C.chip, TextSize = 13, LayoutOrder = 1 }, function() Drive.leave() end)
	UI.button(small, "💡", { Size = UDim2.fromOffset(SMALL, SMALL), BackgroundColor3 = C.chip, TextSize = 20, LayoutOrder = 2 }, function() Drive.toggleLights() end)
	UI.button(small, "◁", { Size = UDim2.fromOffset(SMALL, SMALL), BackgroundColor3 = C.chip, TextSize = 18, LayoutOrder = 3 }, function() Drive.setSignal(Drive.info.signal == -1 and 0 or -1) end)
	UI.button(small, "▷", { Size = UDim2.fromOffset(SMALL, SMALL), BackgroundColor3 = C.chip, TextSize = 18, LayoutOrder = 4 }, function() Drive.setSignal(Drive.info.signal == 1 and 0 or 1) end)

	-- right corner: brake, gas, handbrake above the brake
	local GAS, BRAKE_H, HAND = 96, 80, 60
	local right = UI.new("Frame", { Name = "Right", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(GAS * 2 + GAP, BRAKE_H + GAP + HAND), Parent = root })
	local gas, brk = false, false
	local function throttleSync() t.throttle = (gas and 1 or 0) - (brk and 1 or 0) end
	hold(right, "GAS", UDim2.new(1, -GAS, 1, -GAS), UDim2.fromOffset(GAS, GAS), C.green, 18, function() gas = true; throttleSync() end, function() gas = false; throttleSync() end)
	hold(right, "BRAKE", UDim2.new(0, 0, 1, -BRAKE_H), UDim2.fromOffset(GAS, BRAKE_H), C.red, 15, function() brk = true; throttleSync() end, function() brk = false; throttleSync() end)
	hold(right, "P", UDim2.new(0, 0, 0, 0), UDim2.fromOffset(HAND, HAND), C.orange, 24, function() t.handbrake = true end, function() t.handbrake = false end)

	local function releaseAll()
		for _, h in ipairs(holds) do
			h.button.BackgroundTransparency = IDLE_ALPHA
			h.release()
		end
		t.throttle = 0
		t.steer = 0
		t.handbrake = false
	end
	UIState.bind("touch", root, nil, releaseAll)
	return root
end

return Touch
