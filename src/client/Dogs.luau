-- Draws the soi dogs. The server owns where each dog is (ReplicatedStorage.GoDashDogs); this
-- script shows a model for the dogs near the camera, eases it along, makes it bound when it runs
-- and pops a bark bubble over it while it chases someone.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lang = require(script.Parent.Lang)

local Dogs = {}
local SHOW, HIDE = 420, 520
local SCALE = 1.5
local FACE = CFrame.new() -- the mesh already faces -Z (Roblox forward)
local COATS = {
	Color3.fromRGB(196, 150, 96), Color3.fromRGB(70, 60, 54), Color3.fromRGB(226, 214, 196), Color3.fromRGB(150, 104, 66),
}

local function fallback(): Model
	local m = Instance.new("Model")
	local function part(size: Vector3, cf: CFrame)
		local p = Instance.new("Part")
		p.Size, p.CFrame, p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = size, cf, true, false, false, false
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = m
		return p
	end
	m.PrimaryPart = part(Vector3.new(1.1, 1.1, 2.6), CFrame.new(0, 1.5, 0))
	part(Vector3.new(0.9, 0.9, 1), CFrame.new(0, 2.2, -1.5))
	for _, o in ipairs({ { -0.35, -1 }, { 0.35, -1 }, { -0.35, 1 }, { 0.35, 1 } }) do
		part(Vector3.new(0.3, 1, 0.3), CFrame.new(o[1], 0.5, o[2]))
	end
	return m
end

local function build(template: Model?, look: number): (Model, number)
	local m
	if template then
		m = template:Clone()
		m:ScaleTo(SCALE)
	else
		m = fallback()
	end
	local size = m:GetExtentsSize()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
			if not template then d.Color = COATS[(look - 1) % #COATS + 1] end
		end
	end
	local bark = Instance.new("BillboardGui")
	bark.Name = "Bark"
	bark.Size = UDim2.fromOffset(120, 34)
	bark.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 1.6, 0)
	bark.AlwaysOnTop = true
	bark.MaxDistance = 220
	bark.Enabled = false
	bark.Adornee = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	t.BackgroundTransparency = 0.1
	t.Font = Enum.Font.GothamBlack
	t.TextSize = 18
	t.TextColor3 = Color3.fromRGB(200, 40, 30)
	t.Text = Lang.pick("Woof! Woof!", "โฮ่ง! โฮ่ง!")
	t.Parent = bark
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 12)
	c.Parent = t
	bark.Parent = m
	return m, size.Y
end

function Dogs.start()
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("GoDashDogs", 60)
		if not folder then return end
		local store = ReplicatedStorage:FindFirstChild("GoDashModels")
		local template = store and store:FindFirstChild("Dog1")
		if template and not template:IsA("Model") then template = nil end
		local holder = Instance.new("Folder")
		holder.Name = "GoDashDogs"
		holder.Parent = Workspace

		local shown = {} -- [cfg] = { model, height, pos, look, phase }
		local acc = 0
		RunService.RenderStepped:Connect(function(dt)
			local cam = Workspace.CurrentCamera
			if not cam then return end
			local camPos = cam.CFrame.Position
			acc += dt
			if acc > 0.5 then
				acc = 0
				for _, cfg in ipairs(folder:GetChildren()) do
					local pos = cfg:GetAttribute("Pos")
					if typeof(pos) == "Vector3" then
						local dist = (pos - camPos).Magnitude
						if not shown[cfg] and dist < SHOW then
							local model, h = build(template, cfg:GetAttribute("Look") or 1)
							model.Parent = holder
							shown[cfg] = { model = model, height = h, pos = pos, look = Vector3.new(0, 0, -1), phase = 0 }
						elseif shown[cfg] and dist > HIDE then
							shown[cfg].model:Destroy()
							shown[cfg] = nil
						end
					end
				end
			end
			for cfg, d in pairs(shown) do
				local target = cfg:GetAttribute("Pos")
				local state = cfg:GetAttribute("State")
				if typeof(target) == "Vector3" then
					local before = d.pos
					d.pos = d.pos:Lerp(target, math.clamp(dt * 9, 0, 1))
					local move = d.pos - before
					local speed = move.Magnitude / math.max(dt, 1e-3)
					if speed > 1.5 then d.look = d.look:Lerp(move.Unit, math.clamp(dt * 10, 0, 1)) end
					if d.look.Magnitude < 0.01 then d.look = Vector3.new(0, 0, -1) end
					local running = speed > 4
					d.phase += dt * (running and 15 or 0)
					local hop = running and math.abs(math.sin(d.phase)) * 0.55 or 0
					local pitch = running and math.sin(d.phase * 2) * 0.16 or 0
					-- an idle dog sits with its front raised a little
					if not running and state == "idle" then pitch = 0.08 end
					local p = d.pos + Vector3.new(0, d.height / 2 + hop, 0)
					d.model:PivotTo(CFrame.lookAt(p, p + d.look.Unit) * FACE * CFrame.Angles(pitch, 0, 0))
					local bark = d.model:FindFirstChild("Bark")
					if bark then bark.Enabled = state == "chase" and (os.clock() * 3) % 1 < 0.7 end
				end
			end
		end)
	end)
end

return Dogs
