-- Chase camera while driving (2026-11-18 realism pass, owner: "as real as possible").
-- Replaces Roblox's follow camera on a vehicle:
--   * swings round behind the vehicle with a little lag (a spring, never a snap), faster at speed
--   * looks ahead along the road, pulls back and rises as speed builds, leans with a motorbike
--   * bumps from the suspension and a light shake at high speed come through the chassis
--   * never ends up inside a wall: it slides in front of whatever is between it and the vehicle
--   * look around: right mouse drag / touch drag / right stick; it settles back behind you; the
--     mouse wheel zooms (kept for the session)
-- First person (V), cutscenes and photo mode keep their own cameras.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Drive = require(script.Parent.Drive)
local State = require(script.Parent.State)
local UIState = require(script.Parent.UI.Core.UIState)

local ChaseCam = {}
local player = Players.LocalPlayer
local TAU = math.pi * 2

local active = false
local yaw = 0 -- the heading the camera follows (radians, Roblox yaw: look = (-sin, 0, -cos))
local orbitYaw, orbitPitch = 0, 0 -- look-around offsets
local zoom = 1
local lastLook = 0
local dragging = false
local stick = Vector2.zero
local focusY: number? = nil
local bump, bumpV = 0, 0 -- a damped spring the suspension kicks
local lastVY = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function angleDiff(a: number, b: number): number
	return ((a - b + math.pi) % TAU) - math.pi
end

local function wanted(): boolean
	return Drive.current() ~= nil and player.CameraMode ~= Enum.CameraMode.LockFirstPerson
		and not State.cutscene and not UIState.get("modal")
end

local function update(dt: number)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local c = Drive.current()
	if not wanted() then
		if active then
			active = false
			-- hand the camera back unless a cutscene or the photo mode has it now
			if not State.cutscene and not UIState.get("modal") then cam.CameraType = Enum.CameraType.Custom end
		end
		return
	end
	local chassis = c.chassis
	if not chassis or not chassis.Parent then return end
	dt = math.min(dt, 1 / 20)
	local cf = chassis.CFrame
	local flatLook = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if flatLook.Magnitude < 0.05 then flatLook = Vector3.new(0, 0, -1) end
	flatLook = flatLook.Unit
	local vel = chassis.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local speed = flatVel.Magnitude
	local def = c.def
	local bike = def.class == "bike"
	local top = (c.stats and c.stats.topSpeed) or def.topSpeed or 60
	local rev = math.clamp(speed / math.max(top, 1), 0, 1.2)

	if not active then
		active = true
		-- start where the old camera was looking, so getting on is not a jump cut
		local look = cam.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
		orbitYaw, orbitPitch = 0, 0
		focusY = nil
		rayParams.FilterDescendantsInstances = { c.model, player.Character, Workspace:FindFirstChild("Vehicles"),
			Workspace:FindFirstChild("GoDashLocalTraffic"), Workspace:FindFirstChild("GoDashPedestrians"), Workspace:FindFirstChild("NPCs") }
	end
	cam.CameraType = Enum.CameraType.Scriptable

	-- follow the heading with a lag that shortens at speed
	local targetYaw = math.atan2(-flatLook.X, -flatLook.Z)
	local follow = 2.6 + math.min(speed, 90) * 0.045
	yaw += angleDiff(targetYaw, yaw) * math.min(1, dt * follow)

	-- look-around input settles back after a moment
	if stick.Magnitude > 0.15 then
		orbitYaw -= stick.X * dt * 2.4
		orbitPitch = math.clamp(orbitPitch + stick.Y * dt * 6, -2, 9)
		lastLook = os.clock()
	end
	if not dragging and os.clock() - lastLook > 1.4 then
		local k = math.min(1, dt * 2.2)
		orbitYaw -= angleDiff(orbitYaw, 0) * k
		orbitPitch -= orbitPitch * k
	end

	-- suspension: a vertical kick (landing, potholes, kerbs) drives a damped spring
	local dvy = vel.Y - lastVY
	lastVY = vel.Y
	if math.abs(dvy) > 2.5 then bumpV += math.clamp(-dvy * 0.05, -1.5, 1.5) end
	bumpV += (-bump * 120 - bumpV * 14) * dt
	bump += bumpV * dt

	-- distance and height grow with speed
	local size = bike and 9.2 or (8.5 + (def.len or 14) * 0.42)
	local dist = (size + math.min(speed, 140) * 0.05) * zoom
	local height = (bike and 3.2 or ((def.height or 5) * 0.62 + 1.4)) + math.min(speed, 140) * 0.012 + orbitPitch
	local camYaw = yaw + orbitYaw
	local back = Vector3.new(math.sin(camYaw), 0, math.cos(camYaw))

	-- focus point: above the vehicle, a little ahead along its motion; vertical smoothed so the
	-- picture doesn't jitter with every bump (the spring above brings the bump back in, softly)
	local fy = chassis.Position.Y + (bike and 2.6 or ((def.height or 5) * 0.45 + 0.6))
	focusY = focusY and (focusY + (fy - focusY) * math.min(1, dt * 9)) or fy
	local ahead = flatVel * 0.12
	local focus = Vector3.new(chassis.Position.X, focusY, chassis.Position.Z) + ahead
	local eye = focus + back * dist + Vector3.new(0, height - 0.4, 0)

	-- don't end up inside a building
	local dir = eye - focus
	local hit = Workspace:Raycast(focus, dir, rayParams)
	if hit then eye = focus + dir.Unit * math.max(1.5, hit.Distance - 0.8) end

	local lookAt = focus + flatLook * (3 + math.min(speed, 80) * 0.06) - Vector3.new(0, 0.6, 0)
	local camCf = CFrame.lookAt(eye + Vector3.new(0, bump * 0.35, 0), lookAt)
	-- lean with a motorbike, a little
	if bike and c.lean then camCf *= CFrame.Angles(0, 0, c.lean * 0.28) end
	-- a light shake when it's really fast
	if rev > 0.75 then
		local a = (rev - 0.75) * 0.025
		local t = os.clock()
		camCf *= CFrame.Angles(math.noise(t * 9, 1) * a, math.noise(t * 9, 2) * a, 0)
	end
	cam.CFrame = camCf
	cam.Focus = CFrame.new(focus)
end

function ChaseCam.start()
	RunService:BindToRenderStep("GoDashChaseCam", Enum.RenderPriority.Camera.Value, update)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and active then dragging = true end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = false
			lastLook = os.clock()
		end
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then stick = Vector2.zero end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if not active then return end
		local ty = input.UserInputType
		if ty == Enum.UserInputType.MouseMovement and dragging then
			orbitYaw -= input.Delta.X * 0.007
			orbitPitch = math.clamp(orbitPitch + input.Delta.Y * 0.03, -2, 9)
			lastLook = os.clock()
		elseif ty == Enum.UserInputType.MouseWheel and not processed then
			zoom = math.clamp(zoom - input.Position.Z * 0.08, 0.55, 1.9)
		elseif ty == Enum.UserInputType.Touch and not processed then
			orbitYaw -= input.Delta.X * 0.006
			orbitPitch = math.clamp(orbitPitch + input.Delta.Y * 0.025, -2, 9)
			lastLook = os.clock()
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
end

return ChaseCam
