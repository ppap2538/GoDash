-- Draws the soi dogs. The server owns where each dog is (ReplicatedStorage.GoDashDogs); this
-- script shows a model for the dogs near the camera, eases it along, makes it bound when it runs
-- and pops a bark bubble over it while it chases someone.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Lang = require(script.Parent.Lang)
local Sounds = require(ReplicatedStorage:WaitForChild("Shared").Config.Sounds)
local Pets = require(ReplicatedStorage:WaitForChild("Shared").Config.Pets)
local Feedback = require(script.Parent.Feedback)
local Choice = require(script.Parent.Choice)
local State = require(script.Parent.State)
local adoptPrompt -- defined below build(); used when a dog model is made

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

-- Adopt a soi dog (2026-11-19, Config/Pets, server/PetService): walk up to one, hold E, pay for the vaccines
-- and a collar, pick its name. Riders who already have a dog, or sit on a vehicle, get no prompt.
local busy = false
local function adopt(cfg: Instance)
	if busy then return end
	busy = true
	local L = Lang.pick
	local a = Choice.ask({ icon = "🐶", title = L("Adopt this soi dog?", "รับน้องหมาซอยไปเลี้ยงไหม?"),
		text = L(("Vaccines and a collar: ฿%d. It follows you on foot and rides in front of you on a bike."):format(Pets.PRICE),
			("ค่าวัคซีน + ปลอกคอ ฿%d น้องจะเดินตามคุณ และนั่งหน้ารถไปด้วยเวลาขี่มอไซ"):format(Pets.PRICE)),
		answers = { { L("Adopt", "รับเลี้ยง") }, { L("Not now", "ไว้ก่อน") } } })
	if a == 1 then
		-- three names to pick from (no typed names)
		local pool = {}
		for i = 1, #Pets.NAMES do table.insert(pool, i) end
		local picks = {}
		for _ = 1, 3 do table.insert(picks, table.remove(pool, math.random(1, #pool))) end
		local answers = {}
		for _, i in ipairs(picks) do table.insert(answers, { "🐶 " .. L(Pets.NAMES[i].en, Pets.NAMES[i].th) }) end
		local n = Choice.ask({ icon = "🏷", title = L("Name your dog", "ตั้งชื่อน้อง"), text = L("Pick one", "เลือกชื่อที่ชอบ"), answers = answers })
		if n then
			local city = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("City")
			if city then
				local ok, msg = (city :: RemoteFunction):InvokeServer("adopt", ("%d,%d"):format(cfg:GetAttribute("Id") or 0, picks[n]))
				if msg and msg ~= "" then Feedback.toast(msg, ok and "good" or "bad") end
			end
		end
	end
	busy = false
end

function adoptPrompt(model: Model, cfg: Instance)
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not root then return end
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = Lang.pick("Adopt", "รับเลี้ยง")
	pp.ObjectText = Lang.pick("Soi dog", "หมาซอย")
	pp.HoldDuration = 0.4
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp:SetAttribute("NoTranslate", true)
	pp.Parent = root
	pp.Triggered:Connect(function() task.spawn(adopt, cfg) end)
	-- only for riders on foot without a dog yet
	task.spawn(function()
		while pp.Parent do
			local char = Players.LocalPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local d = State.data
			pp.Enabled = hum ~= nil and hum.SeatPart == nil and d ~= nil and type(d.pet) ~= "table" and cfg:GetAttribute("State") ~= "chase"
			task.wait(0.5)
		end
	end)
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
					if cfg:GetAttribute("State") == "gone" then
						-- adopted by someone (server/PetService); a new stray turns up later
						if shown[cfg] then shown[cfg].model:Destroy(); shown[cfg] = nil end
					elseif typeof(pos) == "Vector3" then
						local dist = (pos - camPos).Magnitude
						if not shown[cfg] and dist < SHOW then
							local model, h = build(template, cfg:GetAttribute("Look") or 1)
							adoptPrompt(model, cfg)
							model.Parent = holder
							shown[cfg] = { model = model, height = h, pos = pos, look = Vector3.new(0, 0, -1), phase = 0, voice = 0.8 + math.random() * 0.5 }
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
					-- out loud too, when the bark sound is set (Config/Sounds.dogBark): a dog that is chasing
					-- barks again and again, a resting dog gives the odd bark when someone comes near
					if Sounds.dogBark ~= "" then
						local now = os.clock()
						local dist = (d.pos - camPos).Magnitude
						local due = state == "chase" and 0.9 or ((dist < 90) and 7 or math.huge)
						if now - (d.barkedAt or (now - math.random() * 6)) > due then
							d.barkedAt = now + math.random() * (state == "chase" and 0.4 or 5)
							local root = d.model.PrimaryPart or d.model:FindFirstChildWhichIsA("BasePart", true)
							if root then
								local s = Instance.new("Sound")
								s.SoundId = (Sounds.dogBark2 ~= "" and math.random() < 0.5) and Sounds.dogBark2 or Sounds.dogBark
								s.Volume = state == "chase" and 0.7 or 0.4
								s.PlaybackSpeed = (d.voice or 1) * (0.94 + math.random() * 0.12)
								s.RollOffMinDistance = 12
								s.RollOffMaxDistance = 220
								s.SoundGroup = Feedback.sfxGroup
								s.Parent = root
								s:Play()
								s.Ended:Once(function() s:Destroy() end)
							end
						end
					end
				end
			end
		end)
	end)
end

return Dogs
