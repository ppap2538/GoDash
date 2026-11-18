-- A lap of Bueng Kaen Nakhon against the clock (server/TimeTrialService). Near the start on a vehicle a chip
-- offers "start"; then arches show the gates (the next one bright, with the GPS pointing to it), a chip runs
-- the clock, and the server's verdict ends it: time, personal best, this week's board on the sign.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local UI = require(script.Parent.UI.Kit)
local Layers = require(script.Parent.UI.Core.Layers)
local Lang = require(script.Parent.Lang)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)
local Drive = require(script.Parent.Drive)
local GPS = require(script.Parent.GPS)

local Trial = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer

local gates = {} :: { { pos: Vector3, dir: Vector3 } }
local armR = 110
local run = nil :: any -- { armed, t0, next }
local arches = {} :: { Model }
local folder: Folder? = nil
local startChip, startBtn, clockChip, clockLabel

local function fmt(s: number): string
	return ("%d:%05.2f"):format(s // 60, s % 60)
end

local function clearArches()
	for _, a in ipairs(arches) do a:Destroy() end
	arches = {}
end

local function arch(i: number): Model
	local g = gates[i]
	local m = Instance.new("Model")
	m.Name = "Gate" .. i
	local across = Vector3.new(-g.dir.Z, 0, g.dir.X)
	local cf = CFrame.lookAt(g.pos, g.pos + across) -- local X runs along the road, Z across it
	local function part(size: Vector3, c: CFrame, name: string?)
		local p = Instance.new("Part")
		p.Name = name or "P"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size = size
		p.CFrame = c
		p.Material = Enum.Material.Neon
		p.Parent = m
		return p
	end
	for _, z in ipairs({ -15, 15 }) do part(Vector3.new(0.8, 12, 0.8), cf * CFrame.new(0, 6, z), "Post") end
	local banner = part(Vector3.new(0.4, 2.6, 31), cf * CFrame.new(0, 12.4, 0), "Banner")
	banner.Material = Enum.Material.SmoothPlastic
	for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 14
		gui.LightInfluence = 0
		gui.MaxDistance = 600
		gui.Parent = banner
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Text = i == 1 and "START · FINISH" or (L("GATE ", "ด่าน ") .. i .. "/" .. #gates)
		t:SetAttribute("NoTranslate", true)
		t.Parent = gui
	end
	m.Parent = folder
	return m
end

local function paint()
	for i, a in ipairs(arches) do
		local nextI = run and run.t0 and run.next or 1
		local isNext = i == nextI
		local passed = run and run.t0 and i ~= 1 and (run.home or i < run.next)
		for _, p in ipairs(a:GetChildren()) do
			if p:IsA("BasePart") then
				p.Transparency = passed and 1 or 0
				if p.Name == "Post" then
					p.Color = isNext and Color3.fromRGB(255, 210, 40) or Color3.fromRGB(230, 236, 240)
				elseif p.Name == "Banner" then
					p.Color = i == 1 and Color3.fromRGB(30, 30, 34) or (isNext and Color3.fromRGB(230, 120, 20) or Color3.fromRGB(40, 110, 80))
				end
			end
		end
		for _, g in ipairs(a:GetDescendants()) do
			if g:IsA("SurfaceGui") then g.Enabled = not passed end
		end
	end
	if run and run.t0 then
		local n = run.next
		GPS.setTarget(gates[n].pos, n == 1 and L("Finish", "เส้นชัย") or (L("Gate ", "ด่าน ") .. n .. "/" .. #gates))
	elseif run then
		GPS.setTarget(gates[1].pos, L("Start line", "เส้นสตาร์ท"))
	end
end

local function stop()
	run = nil
	clearArches()
	GPS.setTarget(nil)
	clockChip.Visible = false
end

local function onNotify(info)
	local e = info and info.event
	if e == "go" and run then
		run.t0 = os.clock()
		run.next = info.next or 2
		Feedback.toast(L("⏱ GO!", "⏱ ไป!"), "good")
		paint()
	elseif e == "gate" and run then
		run.next = info.next or run.next
		run.home = run.next == 1 -- every gate passed: only the finish is left
		Feedback.click()
		paint()
	elseif e == "finish" then
		local secs = (info.cs or 0) / 100
		stop()
		local msg = L("🏁 Lap ", "🏁 ครบรอบ ") .. fmt(secs)
		if info.record then msg ..= L("  ·  NEW BEST!", "  ·  สถิติใหม่!") elseif info.best then msg ..= L("  ·  best ", "  ·  ดีสุด ") .. fmt(info.best / 100) end
		Feedback.toast(msg, "good")
	elseif e == "void" then
		stop()
		Feedback.toast(L("That lap could not be checked", "รอบนี้ตรวจสอบไม่ได้ ไม่นับเวลา"), "bad")
	elseif e == "off" then
		stop()
	end
end

function Trial.start()
	local gui = UI.screen("GoDashTrial", Layers.HUD + 2)
	startChip = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 196), Size = UDim2.fromOffset(330, 44),
		BackgroundColor3 = Color3.fromRGB(24, 28, 36), BackgroundTransparency = 0.1, Visible = false, Parent = gui })
	UI.corner(startChip, 22)
	UI.stroke(startChip, Color3.fromRGB(255, 200, 60), 2)
	local sl = UI.label(startChip, L("⏱ Lake lap: who is fastest?", "⏱ แข่งรอบบึง ใครเร็วสุด?"), 15, C.white, F.bold, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -110, 1, 0) })
	sl:SetAttribute("NoTranslate", true)
	startBtn = UI.button(startChip, L("Start", "เริ่ม"), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(86, 34), TextSize = 15,
		BackgroundColor3 = Color3.fromRGB(230, 120, 20) }, function()
		local ok, msg = Net.call("City", "trial_arm")
		if msg and msg ~= "" then Feedback.toast(msg, ok and "good" or "bad") end
		if ok then
			run = { t0 = nil, next = 1 }
			clearArches()
			for i = 1, #gates do table.insert(arches, arch(i)) end
			paint()
			startChip.Visible = false
		end
	end)
	startBtn:SetAttribute("NoTranslate", true)
	clockChip = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 196), Size = UDim2.fromOffset(260, 40),
		BackgroundColor3 = Color3.fromRGB(24, 28, 36), BackgroundTransparency = 0.1, Visible = false, Parent = gui })
	UI.corner(clockChip, 20)
	clockLabel = UI.label(clockChip, "", 19, C.white, F.black, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	clockLabel:SetAttribute("NoTranslate", true)
	Net.listen("Notify", function(kind, info)
		if kind == "trial" then onNotify(info) end
	end)
	task.spawn(function()
		local f = ReplicatedStorage:WaitForChild("GoDashTrial", 120)
		if not f then return end
		armR = f:GetAttribute("ArmRadius") or armR
		local n = f:GetAttribute("Count") or #f:GetChildren()
		for i = 1, n do
			local c = f:WaitForChild("Gate" .. i, 10)
			if c then gates[i] = { pos = c:GetAttribute("Pos"), dir = c:GetAttribute("Dir") } end
		end
		local fo = Instance.new("Folder")
		fo.Name = "GoDashTrialGates"
		fo.Parent = Workspace
		folder = fo
	end)
	RunService.Heartbeat:Connect(function()
		if #gates == 0 then return end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local driving = Drive.current() ~= nil
		if not run then
			local near = root and driving and Vector3.new(root.Position.X - gates[1].pos.X, 0, root.Position.Z - gates[1].pos.Z).Magnitude < armR
			startChip.Visible = near == true and not State.cutscene
		else
			startChip.Visible = false
			clockChip.Visible = true
			if run.t0 then
				local passedN = run.home and #gates or math.max(1, run.next - 1)
				clockLabel.Text = ("⏱ %s  ·  %s %d/%d"):format(fmt(os.clock() - run.t0), L("gate", "ด่าน"), passedN, #gates)
			else
				clockLabel.Text = L("⏱ Ride through the START line", "⏱ ขี่ผ่านเส้นสตาร์ทได้เลย")
			end
		end
	end)
end

return Trial
