-- Which light is mine? (2026-11-19, owner: "ไฟแดงยังมั่วๆ อยู่ มันเป็นห้าแยก สับสน ควรจะมีสีหรือเตือน ... ชัดเจนกว่านี้":
-- at five-way junctions you could not tell which of the lights was yours.)
-- While you drive toward a signalled junction on one of its main roads:
--   * a panel at the top centre shows YOUR light (the same colour server/TrafficService fines from),
--     the seconds it has left like a Thai countdown light, and what to do ("stop", "go", "left on red is OK")
--   * your lane's stop line glows in that colour, and a "▼ your light" tag floats over your signal head
--   * coming at a red too fast to stop calmly: the panel flashes and beeps once
-- Nothing shows on a soi that joins a junction (sois have no light and are never fined).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Traffic = require(Shared.Traffic)
local GPS = require(script.Parent.GPS)
local Drive = require(script.Parent.Drive)
local Feedback = require(script.Parent.Feedback)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local UI = require(script.Parent.UI.Kit)

local Assist = {}
local L = Lang.pick
local C, F = UI.C, UI.F
local REACH = 170 -- studs ahead of the junction centre the panel starts showing
local CELL = 512

local COLOURS = {
	red = Color3.fromRGB(255, 52, 40),
	yellow = Color3.fromRGB(255, 196, 30),
	green = Color3.fromRGB(40, 220, 100),
}
local DIM = { red = Color3.fromRGB(70, 22, 20), yellow = Color3.fromRGB(70, 56, 16), green = Color3.fromRGB(16, 60, 30) }

local grid
local function signalsAround(p: Vector3): { any }
	if not grid then
		local graph = GPS.graph()
		if not graph then return {} end
		grid = {}
		for _, s in ipairs((Traffic.signals(graph))) do
			local k = math.floor(s.node.x / CELL) * 4096 + math.floor(s.node.z / CELL)
			grid[k] = grid[k] or {}
			table.insert(grid[k], s)
		end
	end
	local out = {}
	local cx, cz = math.floor(p.X / CELL), math.floor(p.Z / CELL)
	for dx = -1, 1 do
		for dz = -1, 1 do
			local list = grid[(cx + dx) * 4096 + cz + dz]
			if list then for _, s in ipairs(list) do table.insert(out, s) end end
		end
	end
	return out
end

-- The junction ahead and the road you are coming in on (nil when there is none or it is a soi).
local function ahead(pos: Vector3, fwd: Vector3)
	local best, bestD
	for _, s in ipairs(signalsAround(pos)) do
		local dx, dz = s.node.x - pos.X, s.node.z - pos.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < REACH and d > s.node.r + 2 and (dx * fwd.X + dz * fwd.Z) / d > 0.5 and (not best or d < bestD) then
			best, bestD = s, d
		end
	end
	if not best then return nil end
	local n = best.node
	local ax, az = (pos.X - n.x) / bestD, (pos.Z - n.z) / bestD
	local link, dot = nil, -2
	for _, l in ipairs(n.links) do
		local dd = ((l.to.x - n.x) * ax + (l.to.z - n.z) * az) / l.len
		if dd > dot then link, dot = l, dd end
	end
	if not link or dot < 0.8 or link.edge.minor then return nil end
	return best, link, bestD
end

-- the signal model of this approach: the one whose stop line lies out along the road you came in on
local function headFor(nodeId: number, n, ax: number, az: number): Model?
	local best, bestDot = nil, 0.7
	for _, m in ipairs(CollectionService:GetTagged("TrafficSignal")) do
		if m:GetAttribute("Node") == nodeId then
			local line = m:FindFirstChild("StopLine")
			if line and line:IsA("BasePart") then
				local v = Vector3.new(line.Position.X - n.x, 0, line.Position.Z - n.z)
				if v.Magnitude > 1 then
					local dd = (v.X * ax + v.Z * az) / v.Magnitude
					if dd > bestDot then best, bestDot = m, dd end
				end
			end
		end
	end
	return best
end

-- UI ----------------------------------------------------------------------------------------------
local panel, lampDots, countLabel, titleLabel, subLabel, stroke
local function build(parent: Instance)
	panel = UI.new("Frame", { Name = "MyLight", LayoutOrder = -5, Size = UDim2.fromOffset(300, 62), BackgroundColor3 = Color3.fromRGB(16, 18, 24),
		BackgroundTransparency = 0.12, Visible = false, Parent = parent })
	UI.corner(panel, 14)
	stroke = UI.stroke(panel, COLOURS.red, 2.5, 0)
	-- the light itself: three lamps in a black housing, like the real head
	local housing = UI.new("Frame", { Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(122, 48), BackgroundColor3 = Color3.fromRGB(6, 6, 8), Parent = panel })
	UI.corner(housing, 12)
	UI.stroke(housing, Color3.fromRGB(240, 190, 40), 2, 0)
	lampDots = {}
	for i, key in ipairs({ "red", "yellow", "green" }) do
		local dot = UI.new("Frame", { Position = UDim2.fromOffset(6 + (i - 1) * 39, 5), Size = UDim2.fromOffset(38, 38), BackgroundColor3 = DIM[key], Parent = housing })
		UI.corner(dot, 19)
		lampDots[key] = dot
	end
	countLabel = UI.label(panel, "", 30, C.white, F.black, { Position = UDim2.fromOffset(136, 4), Size = UDim2.fromOffset(46, 54),
		TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	UI.label(panel, L("YOUR LIGHT", "ไฟของคุณ"), 10, Color3.fromRGB(240, 190, 40), F.bold, { Position = UDim2.fromOffset(184, 3), Size = UDim2.new(1, -190, 0, 13) })
	titleLabel = UI.label(panel, "", 17, C.white, F.black, { Position = UDim2.fromOffset(184, 15), Size = UDim2.new(1, -190, 0, 22) })
	subLabel = UI.label(panel, "", 12, C.white, F.med, { Position = UDim2.fromOffset(184, 38), Size = UDim2.new(1, -190, 0, 18) })
end

-- world cues -------------------------------------------------------------------------------------
local glow: BasePart? = nil
local tag: BillboardGui? = nil
local tagText: TextLabel? = nil
local function clearWorld()
	if glow then glow.Parent = nil end
	if tag then tag.Adornee = nil; tag.Enabled = false end
end
local function makeWorld()
	local p = Instance.new("Part")
	p.Name = "MyLaneStop"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 0.15
	glow = p
	local b = Instance.new("BillboardGui")
	b.Name = "MyLightTag"
	b.Size = UDim2.fromOffset(132, 34)
	b.StudsOffset = Vector3.new(0, -4.4, 0) -- under the head: above it, it runs off the top of the screen up close
	b.AlwaysOnTop = true
	b.MaxDistance = 260
	b.LightInfluence = 0
	b.Enabled = false
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	t.BackgroundTransparency = 0.15
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Font = F.black
	t.TextScaled = true
	t.Parent = b
	UI.corner(t, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6); pad.PaddingTop = UDim.new(0, 3); pad.PaddingBottom = UDim.new(0, 3)
	pad.Parent = t
	b.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	tag, tagText = b, t
end

-- loop --------------------------------------------------------------------------------------------
local current = { node = nil :: number?, head = nil :: Model?, warned = false, shown = "" }

local function run()
	local tries = 0
	while not Feedback.top and tries < 100 do task.wait(0.1); tries += 1 end
	if not Feedback.top then return end
	build(Feedback.top)
	makeWorld()
	local acc, flash = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		flash += dt
		if acc < 0.1 then return end
		acc = 0
		local c = Drive.current()
		if not c or not c.chassis or State.cutscene then
			if panel.Visible then panel.Visible = false; clearWorld() end
			current.node = nil
			return
		end
		local cf = c.chassis.CFrame
		local fwd = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		local vel = c.chassis.AssemblyLinearVelocity
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		-- the chassis may face the way it moves or the other way: trust the movement when moving
		if speed > 3 then fwd = Vector3.new(vel.X, 0, vel.Z) end
		if fwd.Magnitude < 0.01 then return end
		fwd = fwd.Unit
		local pos = cf.Position
		local sig, link, d = ahead(pos, fwd)
		if not sig then
			if panel.Visible then panel.Visible = false; clearWorld() end
			current.node = nil
			return
		end
		local n = sig.node
		local group = sig.groups[link.edge]
		local col, _, left = Traffic.timing(n.id, group, Workspace:GetServerTimeNow())
		if current.node ~= n.id then
			current.node = n.id
			current.warned = false
			local ax, az = (pos.X - n.x) / d, (pos.Z - n.z) / d
			current.head = headFor(n.id, n, ax, az)
			if not panel.Visible then panel.Visible = true; UI.pop(panel, 0.85) end
		end
		-- the panel
		local colour = COLOURS[col]
		for key, dot in pairs(lampDots) do dot.BackgroundColor3 = key == col and COLOURS[key] or DIM[key] end
		countLabel.Text = tostring(math.max(1, math.ceil(left)))
		countLabel.TextColor3 = colour
		stroke.Color = colour
		local toLine = d - n.r - 3 -- the line the red-light check uses
		local tLine = toLine / math.max(speed, 1)
		local stopDist = speed * speed / (2 * 34) + speed * 0.4
		local danger = speed > 10 and toLine < stopDist + 18 and (col == "red" or (col == "yellow" and tLine > left))
		local title, sub
		local moving = speed > 6 -- the timing advice only means something on the move
		local metres = math.floor(math.max(0, toLine) * 0.28 / 5 + 0.5) * 5
		local away = L(("Junction in %d m"):format(metres), ("ถึงแยกใน %d ม."):format(metres))
		if col == "red" then
			title = danger and L("🛑 RED: BRAKE!", "🛑 ไฟแดง เบรก!") or L("RED: stop", "ไฟแดง หยุดรอ")
			sub = L("⬅️ Turning left on red is OK", "⬅️ เลี้ยวซ้ายผ่านตลอดได้")
		elseif col == "yellow" then
			title = danger and L("🛑 YELLOW: stop", "🛑 ไฟเหลือง หยุด!") or L("YELLOW: slow down", "ไฟเหลือง ชะลอ")
			sub = not moving and L("Wait for green", "รอไฟเขียว")
				or (tLine <= left and L("You can still make it", "ยังผ่านทัน") or L("Red is coming: stop at the line", "จะแดงแล้ว หยุดก่อนเส้น"))
		else
			title = L("GREEN: go", "ไฟเขียว ไปได้")
			sub = (moving and left + Traffic.YELLOW < tLine) and L("Turns red before you get there", "ไปไม่ทันเขียว เตรียมหยุด") or away
		end
		titleLabel.Text = title
		titleLabel.TextColor3 = colour
		subLabel.Text = sub
		if danger then
			-- flash, and one beep for this junction
			local on = math.floor(flash * 6) % 2 == 0
			panel.BackgroundColor3 = on and Color3.fromRGB(150, 20, 16) or Color3.fromRGB(16, 18, 24)
			if not current.warned then
				current.warned = true
				Feedback.play("tick", 0.9, 0.5, 0)
				task.delay(0.16, function() Feedback.play("tick", 0.9, 0.5, 0) end)
			end
		else
			panel.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
		end
		-- the stop line of your lane, in your light's colour
		local head = current.head
		if head and not head.Parent then head = nil; current.head = nil end
		if not head then current.head = headFor(n.id, n, (pos.X - n.x) / d, (pos.Z - n.z) / d); head = current.head end
		local line = head and head:FindFirstChild("StopLine")
		if glow and line and line:IsA("BasePart") then
			local w = line.Size.X + 2
			glow.Size = Vector3.new(math.max(2, w / 2 - 1.2), 0.08, 1.8)
			-- the line's look points away from the junction: arriving, your (left) lane is its +X half
			glow.CFrame = line.CFrame * CFrame.new(w / 4, 0.05, 0)
			glow.Color = colour
			if glow.Parent ~= Workspace then glow.Parent = Workspace end
		elseif glow then
			glow.Parent = nil
		end
		-- the tag over your signal head
		local lamp = head and head:FindFirstChild("Lamp2")
		if tag and tagText and lamp and lamp:IsA("BasePart") then
			tag.Adornee = lamp
			tag.Enabled = true
			tagText.Text = L("▲ YOUR LIGHT ", "▲ ไฟของคุณ ") .. tostring(math.max(1, math.ceil(left)))
			tagText.TextColor3 = colour
		elseif tag then
			tag.Enabled = false
		end
	end)
end

function Assist.start()
	task.spawn(run) -- never hold up the controllers started after this one
end

return Assist
