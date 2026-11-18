-- Walking like a person (2026-11-18 realism pass):
--   * no instant full speed: a step or two to get going
--   * sprint with Shift (a "Run" button on touch screens) on a stamina that runs out and comes back;
--     the walk animation already speeds up with the pace
--   * footsteps that sound like the ground: hard road and pavement, soft ground and grass, splashes
--     on a wet road; Roblox's one-size running loop is turned down
--   * landing from a height dips the camera a little
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Feedback = require(script.Parent.Feedback)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)

local OnFoot = {}
local player = Players.LocalPlayer
local rng = Random.new()

local SPRINT = 1.6 -- times walking speed
local START = 0.45 -- share of walking speed on the first step
local RAMP = 0.32 -- seconds to full pace
local DRAIN, REGEN, MIN_START = 16, 20, 25

OnFoot.stamina = 100
local sprintHeld = false
local sprintToggle = false -- touch: the button toggles
local moveT = 0
local stepAcc = 0
local regenWait = 0

local HARD = {
	[Enum.Material.Concrete] = true, [Enum.Material.Asphalt] = true, [Enum.Material.Pavement] = true, [Enum.Material.Slate] = true,
	[Enum.Material.Brick] = true, [Enum.Material.Cobblestone] = true, [Enum.Material.Granite] = true, [Enum.Material.Marble] = true,
	[Enum.Material.SmoothPlastic] = true, [Enum.Material.Plastic] = true, [Enum.Material.Metal] = true, [Enum.Material.DiamondPlate] = true,
	[Enum.Material.CorrodedMetal] = true, [Enum.Material.Basalt] = true, [Enum.Material.Limestone] = true, [Enum.Material.Rock] = true,
	[Enum.Material.CrackedLava] = true, [Enum.Material.Glass] = true, [Enum.Material.Foil] = true, [Enum.Material.Ice] = true,
}
local WOOD = { [Enum.Material.Wood] = true, [Enum.Material.WoodPlanks] = true }

local function playStep(root: BasePart, ids: { string }, volume: number, pitch: number)
	if #ids == 0 then return end
	local s = Instance.new("Sound")
	s.SoundId = ids[rng:NextInteger(1, #ids)]
	s.Volume = volume * rng:NextNumber(0.8, 1.1)
	s.PlaybackSpeed = pitch * rng:NextNumber(0.92, 1.08)
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = 45
	s.SoundGroup = Feedback.sfxGroup
	s.Parent = root
	s:Play()
	task.delay(1.5, function() s:Destroy() end)
end

local function hush(root: Instance)
	-- RbxCharacterSounds' running loop: one sound for every surface; ours replace it
	local function quiet(d: Instance)
		if d:IsA("Sound") and d.Name == "Running" then d.Volume = 0 end
	end
	for _, d in ipairs(root:GetChildren()) do quiet(d) end
	root.ChildAdded:Connect(function(d) task.defer(quiet, d) end)
end

local function character(char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not hum or not root then return end
	hush(root)
	local fallFrom = 0
	hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Freefall then
			fallFrom = root.Position.Y
		elseif new == Enum.HumanoidStateType.Landed then
			local drop = fallFrom - root.Position.Y
			if drop > 4 then
				-- a little dip, then back up
				local k = math.clamp(drop / 14, 0.15, 1)
				hum.CameraOffset = Vector3.new(0, -0.6 * k, 0)
				task.delay(0.12, function()
					for i = 1, 8 do
						if not hum.Parent then return end
						hum.CameraOffset = Vector3.new(0, -0.6 * k * (1 - i / 8), 0)
						task.wait(0.02)
					end
				end)
				local mat = hum.FloorMaterial
				playStep(root, HARD[mat] and Sounds.stepHard or Sounds.stepSoft, 0.55 * k + 0.2, 0.9)
			end
		end
	end)
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not char.Parent then conn:Disconnect() return end
		if hum.SeatPart or State.cutscene then
			moveT = 0
			return
		end
		local moving = hum.MoveDirection.Magnitude > 0.05
		-- hurt from falls (server/HealthService): from 25 a limp, from 50 no running at all
		local injury = player:GetAttribute("Injury") or 0
		local wantSprint = (sprintHeld or sprintToggle) and moving and injury < 50
		local sprinting = false
		if wantSprint and (OnFoot.stamina > 0 and (OnFoot.sprinting or OnFoot.stamina > MIN_START)) then
			sprinting = true
			OnFoot.stamina = math.max(0, OnFoot.stamina - DRAIN * dt)
			regenWait = 0.8
			if OnFoot.stamina <= 0 then sprintToggle = false end
		else
			regenWait -= dt
			if regenWait <= 0 then OnFoot.stamina = math.min(100, OnFoot.stamina + REGEN * dt) end
		end
		OnFoot.sprinting = sprinting
		moveT = moving and math.min(RAMP, moveT + dt) or 0
		local ramp = START + (1 - START) * (moveT / RAMP)
		-- tired riders (energy from the server) don't sprint as fast
		local energy = State.data and State.data.energy or 100
		local tiredMul = energy < 15 and 0.85 or 1
		local base = hum:GetAttribute("BaseWalk") or 16 -- the server lowers it when starving or exhausted
		local limp = injury >= 25 and (1 - math.min(0.35, (injury - 25) / 160 + 0.12)) or 1
		local want = base * ramp * limp * (sprinting and SPRINT * tiredMul or 1)
		if math.abs(hum.WalkSpeed - want) > 0.05 then hum.WalkSpeed = want end

		-- footsteps
		local vel = root.AssemblyLinearVelocity
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local mat = hum.FloorMaterial
		if mat ~= Enum.Material.Air and speed > 2 then
			local stride = sprinting and 3.4 or 2.5
			stepAcc += speed * dt
			if stepAcc >= stride then
				stepAcc = 0
				local wet = (Workspace:GetAttribute("Wet") or 0) > 0.4
				local loud = sprinting and 0.42 or 0.28
				if mat == Enum.Material.Water then
					playStep(root, Sounds.stepWet, loud + 0.1, 1)
				elseif HARD[mat] then
					playStep(root, Sounds.stepHard, loud, 1.35)
					if wet then playStep(root, Sounds.stepWet, loud * 0.7, 1.1) end
				elseif WOOD[mat] then
					playStep(root, Sounds.stepHard, loud, 1.05)
				else
					playStep(root, Sounds.stepSoft, loud * 0.8, 1.3)
					if wet then playStep(root, Sounds.stepWet, loud * 0.5, 1.2) end
				end
			end
		else
			stepAcc = 0
		end
	end)
end

-- The sprint action only exists on foot, so its touch button goes away on a vehicle (Shift is the boost there).
local bound = false
local function bindSprint(on: boolean)
	if on == bound then return end
	bound = on
	if not on then
		ContextActionService:UnbindAction("GoDashSprint")
		sprintHeld, sprintToggle = false, false
		return
	end
	ContextActionService:BindAction("GoDashSprint", function(_, state, input)
		if input.UserInputType == Enum.UserInputType.Touch then
			if state == Enum.UserInputState.Begin then sprintToggle = not sprintToggle end
		else
			sprintHeld = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("GoDashSprint", Lang.pick("Run", "วิ่ง"))
	ContextActionService:SetPosition("GoDashSprint", UDim2.new(1, -170, 1, -150))
end

function OnFoot.start()
	if player.Character then task.spawn(character, player.Character) end
	player.CharacterAdded:Connect(character)
	RunService.Heartbeat:Connect(function()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		bindSprint(hum ~= nil and hum.Health > 0 and hum.SeatPart == nil)
	end)
end

return OnFoot
