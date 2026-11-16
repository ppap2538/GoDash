-- HUD facade. The widgets live in UI/HUD/* and UI/Interactions/*, are placed in the named screen
-- regions of UI/Core/Layout and are shown / hidden by UI/Core/UIState. This module wires them
-- together, runs the one light frame loop and keeps the API the other controllers use:
--   HUD.onPhone (set by Phone), HUD.gps (set by GPS), HUD.mapHolder, HUD.mapSize, HUD.setRoad, HUD.start
--
-- Regions:
--   TopLeft       status widget, buff / resting lines, current-job card
--   TopRight      clock + weather, minimap, road line (+ phone button on touch)
--   BottomRight   speedometer, phone button (keyboard / mouse)
--   BottomCenter  interaction prompt, drive key hint, job offer (+ speedometer on touch)
--   corners       touch pedals (only in a vehicle, only on touch)
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local UIRoot = script.Parent.UI
local UI = require(UIRoot.Kit)
local Layout = require(UIRoot.Core.Layout)
local Layers = require(UIRoot.Core.Layers)
local UIState = require(UIRoot.Core.UIState)
local StatusWidget = require(UIRoot.HUD.StatusWidget)
local NavWidget = require(UIRoot.HUD.NavWidget)
local JobCard = require(UIRoot.HUD.JobCard)
local OfferCard = require(UIRoot.HUD.OfferCard)
local Speedometer = require(UIRoot.HUD.Speedometer)
local TouchControls = require(UIRoot.HUD.TouchControls)
local PhoneButton = require(UIRoot.HUD.PhoneButton)
local Controls = require(UIRoot.HUD.Controls)
local Prompt = require(UIRoot.Interactions.Prompt)
local State = require(script.Parent.State)
local Drive = require(script.Parent.Drive)

local HUD = {}
HUD.onPhone = nil :: (() -> ())? -- set by Phone
HUD.gps = nil :: any -- set by GPS: { distance, name }
HUD.mapHolder = nil :: Frame? -- the minimap frame GPS draws into
HUD.mapSize = Vector2.new(190, 150) -- its size in layout px (changes with the breakpoint)

local isTouch = Layout.isTouch
local wasDriving = false
local hintStamp = 0
local jobClock = 0

local function pressPhone()
	if HUD.onPhone then HUD.onPhone() end
end

local function build()
	local hudGui = UI.screen("GoDashHUD", Layers.HUD)
	local stage = Layout.stage(hudGui)
	local topLeft = Layout.region(stage, "TopLeft")
	local topRight = Layout.region(stage, "TopRight")
	local bottomRight = Layout.region(stage, "BottomRight")
	local bottomLeft = Layout.region(stage, "BottomLeft")

	local interactGui = UI.screen("GoDashInteract", Layers.Interaction)
	local bottomCenter = Layout.region(Layout.stage(interactGui), "BottomCenter")

	-- top-left column
	StatusWidget.build(topLeft) -- layout orders 1..3
	JobCard.build(topLeft, 4, HUD)

	-- top-right cluster
	NavWidget.build(topRight, HUD)

	-- speedometer + phone button: their slots depend on the input device
	if isTouch then
		PhoneButton.build(topRight, 2, pressPhone)
		TouchControls.build(stage)
	else
		Speedometer.build(bottomRight, 1)
		PhoneButton.build(bottomRight, 2, pressPhone)
		Controls.build(bottomLeft) -- key help (the Guide card at the top says what to do)
	end

	-- bottom-centre stack, top to bottom: prompt, key hint, offer, (touch) speedometer
	Prompt.build(bottomCenter, 1)
	OfferCard.build(bottomCenter, 3)
	if isTouch then Speedometer.build(bottomCenter, 9) end
end

local function frame(dt: number)
	local info = Drive.info
	local driving = info.driving == true
	if driving ~= wasDriving then
		wasDriving = driving
		hintStamp += 1
		UIState.set("driving", driving)
		if driving and not isTouch then
			local stamp = hintStamp
			UIState.set("hint", true)
			task.delay(12, function()
				if hintStamp == stamp then UIState.set("hint", false) end
			end)
		else
			UIState.set("hint", false)
		end
	end
	if driving then Speedometer.update(info) end
	NavWidget.update()
	OfferCard.update()
	jobClock += dt
	if jobClock >= 0.1 then
		jobClock = 0
		JobCard.update()
	end
end

function HUD.setRoad(name: string)
	NavWidget.setRoad(name)
end

function HUD.start()
	build()
	RunService.RenderStepped:Connect(frame)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.M then
			pressPhone()
		elseif input.KeyCode == Enum.KeyCode.E and State.job.job and JobCard.actionAvailable and not Drive.info.driving then
			Net.send("JobAction")
		elseif input.KeyCode == Enum.KeyCode.G and State.job.job and JobCard.actionAvailable then
			Net.send("JobAction")
		elseif input.KeyCode == Enum.KeyCode.Y and State.job.offer then
			Net.send("JobRespond", State.job.offer.id, true)
		end
	end)
end

return HUD
