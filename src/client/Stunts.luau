-- Stunts on two wheels (2026-11-19, TikTok toys; client/Drive does the riding part):
--   * wheelie: R on a keyboard, or hold the 🔥 button on a touch screen while riding a bike
--   * burnout: handbrake (Space / the handbrake button) + gas standing still, on a motorbike
-- This module shows how long the stunt has lasted, keeps your best (server: City op "stunt_best"), puts the
-- touch button on screen, and draws OTHER riders' stunts: Drive tilts only its own bike, and the vehicle's
-- "Stunt" attribute (server/VehicleService: 1 wheelie, 2 burnout) tells everyone else to tilt / smoke it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = require(script.Parent.UI.Kit)
local Layers = require(script.Parent.UI.Core.Layers)
local Lang = require(script.Parent.Lang)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)
local Drive = require(script.Parent.Drive)

local Stunts = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local chip, chipLabel
local active, startedAt = 0, 0

local function report(kind: number, seconds: number)
	if seconds < 1.5 then return end
	local name = kind == 1 and L("Wheelie", "ยกล้อ") or L("Burnout", "เบิร์นเอาท์")
	local d = State.data
	local stats = d and d.stats or {}
	local best = kind == 1 and (stats.bestWheelie or 0) or (stats.bestBurnout or 0)
	if seconds > best + 0.05 then
		local city = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("City")
		if city then
			task.spawn(function()
				local ok, msg = (city :: RemoteFunction):InvokeServer("stunt_best", ("%s,%.1f"):format(kind == 1 and "w" or "b", seconds))
				if ok and msg and msg ~= "" then Feedback.toast(msg, "good") end
			end)
		end
	else
		Feedback.toast(("🔥 %s %.1f %s"):format(name, seconds, L("s", "วิ")), "good")
	end
end

-- other riders' bikes: tilt the body round the rear axle / smoke the rear wheel
local others = {} :: { [Model]: any }
local function drawOthers(dt: number)
	local mine = Drive.current()
	for _, m in ipairs(CollectionService:GetTagged("GoDashVehicle")) do
		local st = others[m]
		local s = m:GetAttribute("Stunt") or 0
		local seat = m:FindFirstChildWhichIsA("VehicleSeat", true)
		if seat and not seat.Occupant then s = 0 end
		if (mine and mine.model == m) then s = 0 end
		if s ~= 0 or st then
			local chassis = m.PrimaryPart
			local weld = chassis and chassis:FindFirstChild("BodyWeld") :: Weld?
			if not (chassis and weld) then continue end
			if not st then
				local zMax = 2
				for i = 1, 4 do
					local w = m:GetAttribute("Wheel" .. i)
					if typeof(w) == "Vector3" then zMax = math.max(zMax, w.Z) end
				end
				st = { angle = 0, z = zMax, ride = m:GetAttribute("RideHeight") or 2, base = CFrame.new(0, -(m:GetAttribute("OriginY") or 0), 0) }
				others[m] = st
			end
			local want = s == 1 and (0.42 + math.sin(os.clock() * 2.6) * 0.035) or 0
			st.angle += (want - st.angle) * math.min(1, dt * 4)
			weld.C0 = st.base * CFrame.new(0, -st.ride + 0.2, st.z) * CFrame.Angles(st.angle, 0, 0) * CFrame.new(0, st.ride - 0.2, -st.z)
			-- burnout smoke
			if s == 2 and not st.smoke then
				local a = Instance.new("Attachment")
				a.Position = Vector3.new(0, -st.ride + 0.4, st.z)
				a.Parent = chassis
				local e = Instance.new("ParticleEmitter")
				e.Color = ColorSequence.new(Color3.fromRGB(220, 220, 224))
				e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 5) })
				e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
				e.Lifetime = NumberRange.new(1.2, 2)
				e.Speed = NumberRange.new(2, 5)
				e.SpreadAngle = Vector2.new(40, 40)
				e.Acceleration = Vector3.new(0, 2, 0)
				e.Rate = 60
				e.Parent = a
				st.smoke = a
			elseif s ~= 2 and st.smoke then
				st.smoke:Destroy()
				st.smoke = nil
			end
			if s == 0 and st.angle < 0.003 and not st.smoke then
				weld.C0 = st.base
				others[m] = nil
			end
		end
	end
	for m, st in pairs(others) do
		if not m.Parent then
			if st.smoke then st.smoke:Destroy() end
			others[m] = nil
		end
	end
end

function Stunts.start()
	local gui = UI.screen("GoDashStunts", Layers.HUD + 1)
	chip = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 152), Size = UDim2.fromOffset(240, 40),
		BackgroundColor3 = Color3.fromRGB(230, 90, 20), Visible = false, Parent = gui })
	UI.corner(chip, 20)
	UI.stroke(chip, Color3.fromRGB(255, 220, 120), 2)
	chipLabel = UI.label(chip, "", 20, C.white, F.black, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	chipLabel:SetAttribute("NoTranslate", true)
	-- the touch button: hold for a wheelie
	local btn
	if TOUCH then
		btn = UI.new("TextButton", { Text = "🔥\n" .. L("WHEELIE", "ยกล้อ"), Font = F.black, TextSize = 13, TextColor3 = C.white, BackgroundColor3 = Color3.fromRGB(230, 90, 20),
			BackgroundTransparency = 0.3, AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.42, 0), Size = UDim2.fromOffset(64, 64),
			Visible = false, Parent = gui })
		btn:SetAttribute("NoTranslate", true)
		UI.corner(btn, 32)
		btn.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then Drive.touch.wheelie = true end
		end)
		btn.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then Drive.touch.wheelie = false end
		end)
	end
	RunService.Heartbeat:Connect(function(dt)
		local c = Drive.current()
		local s = (c and Drive.info.stunt) or 0
		if btn then
			local onBike = c ~= nil and c.def.class == "bike" and not State.cutscene
			btn.Visible = onBike
			if not onBike then Drive.touch.wheelie = false end
		end
		if s ~= active then
			if active ~= 0 then report(active, os.clock() - startedAt) end
			active = s
			startedAt = os.clock()
		end
		if active ~= 0 and os.clock() - startedAt > 0.6 then
			chip.Visible = true
			chipLabel.Text = ("🔥 %s  %.1f %s"):format(active == 1 and L("WHEELIE", "ยกล้อ") or L("BURNOUT", "เบิร์นเอาท์"), os.clock() - startedAt, L("s", "วิ"))
		else
			chip.Visible = false
		end
		local ok, err = pcall(drawOthers, math.min(dt, 1 / 20))
		if not ok then warn("[Stunts] " .. tostring(err)) end
	end)
end

return Stunts
