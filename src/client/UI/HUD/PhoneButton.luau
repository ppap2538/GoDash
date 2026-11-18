-- Phone button with its own small ONLINE / OFFLINE chip (never touching the button).
--   keyboard / mouse: bottom-right corner, chip above the button, "M" key badge.
--   touch: under the navigation cluster (Roblox's jump button owns the bottom-right corner),
--          chip to the left of the button.
local UIRoot = script.Parent.Parent
local UI = require(UIRoot.Kit)
local Layout = require(UIRoot.Core.Layout)
local UIState = require(UIRoot.Core.UIState)
local State = require(UIRoot.Parent.State)
local Lang = require(UIRoot.Parent.Lang)
local Net = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Net)

local PhoneButton = {}
local C, F = UI.C, UI.F
local refs = {} :: { [string]: any }

local BTN = 60
local CHIP_W, CHIP_H = 112, 26

local function refresh(job)
	local on = job and job.online == true
	local paused = on and job.paused ~= nil -- hungry / exhausted: the server holds orders back
	refs.chipText.Text = paused and (job.paused == "hungry" and Lang.pick("Paused: hungry", "พักงาน: หิว")
		or job.paused == "hurt" and Lang.pick("Paused: hurt", "พักงาน: บาดเจ็บ") or Lang.pick("Paused: tired", "พักงาน: เหนื่อย"))
		or on and Lang.pick("Taking orders", "รับงานอยู่") or (Lang.pick("Go online", "เริ่มรับงาน") .. (Layout.isTouch and "" or " [J]"))
	refs.chipText.TextColor3 = on and C.white or C.textDim
	refs.dot.BackgroundColor3 = paused and C.orange or on and C.green or Color3.fromRGB(150, 158, 170)
	refs.button.BackgroundColor3 = on and C.green or C.dark
end

-- region: BottomRight (keyboard) or TopRight (touch). onPress: called on tap.
function PhoneButton.build(region: Frame, order: number, onPress: () -> ())
	local touch = Layout.isTouch
	local root = UI.new("Frame", { Name = "PhoneButton", BackgroundTransparency = 1, LayoutOrder = order, Parent = region })
	root.Size = touch and UDim2.fromOffset(CHIP_W + 8 + BTN, BTN) or UDim2.fromOffset(CHIP_W, BTN + 8 + CHIP_H)
	refs.root = root

	local chip = UI.panel(root, { Name = "Online", Size = UDim2.fromOffset(CHIP_W, CHIP_H) }, CHIP_H / 2)
	if touch then
		chip.AnchorPoint = Vector2.new(0, 0.5)
		chip.Position = UDim2.fromScale(0, 0.5)
	else
		chip.AnchorPoint = Vector2.new(1, 0)
		chip.Position = UDim2.fromScale(1, 0)
	end
	local dot = UI.new("Frame", { BackgroundColor3 = C.green, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.fromOffset(6, 6), Parent = chip })
	UI.corner(dot, 3)
	refs.dot = dot
	refs.chipText = UI.label(chip, "", 11, C.textDim, F.bold, { Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -26, 1, 0), TextTruncate = Enum.TextTruncate.None })
	refs.chipText:SetAttribute("NoTranslate", true)
	UI.fitText(refs.chipText, 11, 8)
	-- the chip is the on / off switch
	local hit = UI.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = chip })
	hit.MouseButton1Click:Connect(function()
		if UI.clickSound then UI.clickSound() end
		Net.send("JobSetOnline", not (State.job and State.job.online), State.job and State.job.mode or "food")
	end)

	local button = UI.button(root, "📱", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(BTN, BTN), TextSize = 28, BackgroundColor3 = C.dark }, onPress)
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then corner.CornerRadius = UDim.new(1, 0) end
	UI.stroke(button, C.white, 1.5, 0.55)
	refs.button = button

	if not touch then
		local key = UI.new("Frame", { BackgroundColor3 = C.glass, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(1, -BTN - 6, 1, -BTN + 14), Size = UDim2.fromOffset(18, 18), ZIndex = UI.Layers.Z.raised, Parent = root })
		UI.corner(key, 5)
		UI.stroke(key, C.white, 1, 0.6)
		UI.label(key, "M", 10, C.white, F.bold, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, ZIndex = UI.Layers.Z.raised })
	end

	UIState.bind("phoneButton", root)
	State.onJob(refresh)
	Lang.onChange(function() refresh(State.job) end)
	refresh(State.job)
end

return PhoneButton
