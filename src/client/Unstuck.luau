-- "Stuck? Back to the road" (2026-11-19, owner: "เจอปัญหารถบัคออกไม่ได้" with a screenshot of a scooter wedged in a
-- walled yard under a tree). When your vehicle can't get anywhere, a button offers to put it, with you on it, on
-- the nearest road, facing along it:
--   * you hold the throttle (or auto gas is on) and it hasn't moved for STUCK_SECONDS, or
--   * it has stood off the road (a yard, a car park, a field) for OFF_SECONDS
-- The move is done here (the driver's client owns the vehicle; a server move would unseat the rider), at most once
-- every COOLDOWN seconds, only to the nearest road, so it can't be used to jump across town. Phone > Garage >
-- "Bring it to me" stays as the other way out.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UI = require(script.Parent.UI.Kit)
local Layers = require(script.Parent.UI.Core.Layers)
local Lang = require(script.Parent.Lang)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)
local Drive = require(script.Parent.Drive)
local GPS = require(script.Parent.GPS)

local Unstuck = {}
local L = Lang.pick
local player = Players.LocalPlayer
local STUCK_SECONDS, OFF_SECONDS, COOLDOWN, MAX_JUMP = 2.5, 4, 20, 260
local gui: ScreenGui
local btn: TextButton
local stuckFor, offFor = 0, 0
local lastUse = -1e9

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function moveToRoad()
	local c = Drive.current()
	if not c or not c.chassis or not c.chassis.Parent or State.cutscene then return end
	if os.clock() - lastUse < COOLDOWN then
		Feedback.toast(L("🛟 Wait a moment before moving it again", "🛟 รอสักครู่ก่อนย้ายรถอีกครั้งนะ"), "bad")
		return
	end
	local graph = GPS.graph()
	if not graph then return end
	local e, p, _, dist = graph:nearest(c.chassis.Position)
	if not e or dist > MAX_JUMP then
		Feedback.toast(L("🛟 No road near here: Phone > Garage > Bring it to me", "🛟 แถวนี้ไม่มีถนนใกล้ๆ: มือถือ > โรงรถ > เรียกรถมาหา"), "bad")
		return
	end
	lastUse = os.clock()
	-- along the road, the way the vehicle was more or less pointing, in the left lane (Thailand drives on the left)
	local dir = Vector3.new(e.dx, 0, e.dz)
	local look = Vector3.new(c.chassis.CFrame.LookVector.X, 0, c.chassis.CFrame.LookVector.Z)
	if look:Dot(dir) < 0 then dir = -dir end
	local left = Vector3.new(dir.Z, 0, -dir.X)
	local width = (e.def and e.def.width) or 16
	local pos = p + left * math.clamp(width / 4, 2.2, 8)
	params.FilterDescendantsInstances = { c.model, player.Character, Workspace:FindFirstChild("GoDashLocalTraffic"), Workspace:FindFirstChild("GoDashPedestrians") }
	local hit = Workspace:Raycast(pos + Vector3.new(0, 40, 0), Vector3.new(0, -90, 0), params)
	local y = (hit and hit.Position.Y or 0) + (c.model:GetAttribute("RideHeight") or 2) + 0.4
	local want = CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(pos.X, y, pos.Z) + dir)
	c.model:PivotTo(want * c.model:GetPivot():ToObjectSpace(c.chassis.CFrame):Inverse())
	c.chassis.AssemblyLinearVelocity = Vector3.zero
	c.chassis.AssemblyAngularVelocity = Vector3.zero
	stuckFor, offFor = 0, 0
	btn.Visible = false
	Feedback.toast(L("🛟 Back on the road!", "🛟 ย้ายรถกลับมาที่ถนนแล้ว!"), "good")
end

function Unstuck.start()
	gui = UI.screen("GoDashUnstuck", Layers.Interaction + 1)
	btn = UI.button(gui, L("🛟 Stuck? Back to the road", "🛟 รถติด? ย้ายไปที่ถนน"), {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150), Size = UDim2.fromOffset(270, 46),
		TextSize = 16, BackgroundColor3 = Color3.fromRGB(230, 110, 30), Visible = false,
	}, moveToRoad)
	btn:SetAttribute("NoTranslate", true)
	local acc, roadAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then return end
		local step = acc
		acc = 0
		local c = Drive.current()
		if not c or not c.chassis or not c.chassis.Parent or State.cutscene then
			stuckFor, offFor = 0, 0
			btn.Visible = false
			return
		end
		local v = c.chassis.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local t = Drive.touch or {}
		local qa = c.model:GetAttribute("QaThrottle") -- (Studio tests drive with this attribute)
		local pressing = math.abs(c.seat.ThrottleFloat) > 0.3 or math.abs(t.throttle or 0) > 0.3 or Drive.autoGas == true
			or (Drive.info and Drive.info.auto == true) or (type(qa) == "number" and math.abs(qa) > 0.3)
		if pressing and speed < 2.5 then stuckFor += step else stuckFor = math.max(0, stuckFor - step * 2) end
		-- off the road? (checked once a second)
		roadAcc += step
		if roadAcc >= 1 then
			roadAcc = 0
			local graph = GPS.graph()
			local e, _, _, dist = graph and graph:nearest(c.chassis.Position)
			local half = e and ((e.def and e.def.width or 16) / 2 + 9) or 1e9
			if e and dist > half and speed < 6 then offFor += 1 else offFor = 0 end
		end
		local show = stuckFor >= STUCK_SECONDS or offFor >= OFF_SECONDS
		if speed > 9 then show = false end
		btn.Visible = show and os.clock() - lastUse > 3
	end)
end

return Unstuck
