-- Pedalling a swan boat (server/BoatService). While you sit in a swan's seat this client owns the boat's
-- physics and steers it: the VehicleSeat's Throttle / Steer (W/S/A/D, or Roblox's thumbstick on a phone)
-- become a speed and a heading. The LinearVelocity also holds the hull at the water surface with a gentle
-- bob; the AlignOrientation keeps it level and turns it. A swan is slow: walking pace and a bit.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)

local Boats = {}
local player = Players.LocalPlayer
local TOP, BACK = 11, 4 -- studs per second
local TURN = 0.9 -- radians per second at full steer, a little less at a standstill

local cur = nil :: any

function Boats.start()
	RunService.Heartbeat:Connect(function(dt)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		if not (seat and seat.Name == "SwanSeat" and seat:IsA("VehicleSeat")) then
			cur = nil
			return
		end
		local boat = seat.Parent
		local hull = boat and boat:FindFirstChild("Hull") :: BasePart?
		local lv = hull and hull:FindFirstChildOfClass("LinearVelocity")
		local ao = hull and hull:FindFirstChildOfClass("AlignOrientation")
		if not (hull and lv and ao) then return end
		if not cur or cur.boat ~= boat then
			local look = hull.CFrame.LookVector
			cur = { boat = boat, yaw = math.atan2(-look.X, -look.Z), speed = 0, t = 0 }
			Feedback.toast(Lang.pick("🦢 W/S pedal · A/D steer · Space gets off", "🦢 W/S ปั่น · A/D เลี้ยว · Space ลงเรือ"), "good")
		end
		cur.t += dt
		local want = seat.ThrottleFloat >= 0 and seat.ThrottleFloat * TOP or seat.ThrottleFloat * BACK
		cur.speed += (want - cur.speed) * math.min(1, dt * 1.2) -- a pedal boat picks up speed slowly
		cur.yaw -= seat.SteerFloat * TURN * (0.45 + 0.55 * math.min(1, math.abs(cur.speed) / 6)) * dt
		local fwd = Vector3.new(-math.sin(cur.yaw), 0, -math.cos(cur.yaw))
		local waterY = boat:GetAttribute("WaterY") or 1.2
		local targetY = waterY - 0.2 + math.sin(cur.t * 1.6) * 0.06
		lv.VectorVelocity = fwd * cur.speed + Vector3.new(0, (targetY - hull.Position.Y) * 6, 0)
		ao.CFrame = CFrame.Angles(0, cur.yaw, 0) * CFrame.Angles(0, 0, -seat.SteerFloat * math.rad(3))
	end)
end

return Boats
