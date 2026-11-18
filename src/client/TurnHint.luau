-- Turn-by-turn directions (2026-11-19, OVERHAUL §19 batch 2: "อีก 50 ม. เลี้ยวซ้าย").
-- While a GPS route is on and you ride, a card at the top says the next turn, how far it is and the road
-- you turn into, the way a navigation app does; it lights up in the last 40 m. Only real junctions count
-- (a node of the road graph with three or more roads), so a bending road never says "turn".
local Players = game:GetService("Players")
local UI = require(script.Parent.UI.Kit)
local Lang = require(script.Parent.Lang)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)
local Drive = require(script.Parent.Drive)
local GPS = require(script.Parent.GPS)

local Turn = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local STUD_M = 0.28 -- one stud is 28 cm in this city
local TURN_DEG = 32 -- smaller changes of heading at a junction are "keep going"
local BASE = 14 -- studs back / ahead along the route to read the direction at a vertex

local nodeAt = {} :: { [number]: any } -- rounded position -> graph node
local function key(p: Vector3): number return math.floor(p.X * 2 + 0.5) * 1000003 + math.floor(p.Z * 2 + 0.5) end

local card, arrow, title, sub, stroke

local function build()
	card = UI.new("Frame", { Name = "TurnHint", LayoutOrder = -6, Size = UDim2.fromOffset(300, 58), BackgroundColor3 = Color3.fromRGB(18, 92, 64),
		BackgroundTransparency = 0.08, Visible = false, Parent = Feedback.top })
	UI.corner(card, 14)
	stroke = UI.stroke(card, Color3.fromRGB(255, 255, 255), 2, 0.6)
	arrow = UI.label(card, "", 34, C.white, F.black, { Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(50, 50), TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None })
	title = UI.label(card, "", 20, C.white, F.black, { Position = UDim2.fromOffset(62, 5), Size = UDim2.new(1, -70, 0, 26) })
	sub = UI.label(card, "", 13, Color3.fromRGB(214, 240, 226), F.bold, { Position = UDim2.fromOffset(62, 32), Size = UDim2.new(1, -70, 0, 20) })
	for _, l in ipairs({ arrow, title, sub }) do l:SetAttribute("NoTranslate", true) end
end

local function meters(studs: number): string
	local m = studs * STUD_M
	if m >= 1000 then return L(("%.1f km"):format(m / 1000), ("%.1f กม."):format(m / 1000)) end
	local step = m >= 200 and 50 or 10
	m = math.max(step, math.floor(m / step + 0.5) * step)
	return L(("%d m"):format(m), ("%d ม."):format(m))
end

-- the point `d` studs along the route from vertex i (d > 0 ahead, d < 0 back)
local function along(path: { Vector3 }, i: number, d: number): Vector3
	local p = path[i]
	local step = d > 0 and 1 or -1
	local left = math.abs(d)
	local j = i
	while true do
		local k = j + step
		if k < 1 or k > #path then return path[j] end
		local seg = (path[k] - path[j]).Magnitude
		if seg >= left then return path[j]:Lerp(path[k], left / math.max(seg, 1e-3)) end
		left -= seg
		j = k
	end
	return p
end

-- the next turn on the route from pos: distance (studs), signed angle (deg, + = right), road name; or nil
local function nextTurn(path: { Vector3 }, pos: Vector3): (number?, number?, string?, boolean?)
	-- where on the route we are: the closest segment among the first ones
	local bestI, bestD, bestT = 1, math.huge, 0
	for i = 1, math.min(#path - 1, 40) do
		local a, b = path[i], path[i + 1]
		local ab = b - a
		local len2 = ab:Dot(ab)
		local t = len2 > 0 and math.clamp((Vector3.new(pos.X, 0, pos.Z) - a):Dot(ab) / len2, 0, 1) or 0
		local q = a + ab * t
		local d = (Vector3.new(pos.X, 0, pos.Z) - q).Magnitude
		if d < bestD then bestI, bestD, bestT = i, d, t end
	end
	local dist = (path[bestI + 1] - path[bestI]).Magnitude * (1 - bestT)
	local graph = GPS.graph and GPS.graph()
	for i = bestI + 1, #path - 1 do
		local v = path[i]
		local node = nodeAt[key(v)]
		if node and #node.links >= 3 then
			local inDir = v - along(path, i, -BASE)
			local outDir = along(path, i, BASE) - v
			if inDir.Magnitude > 1 and outDir.Magnitude > 1 then
				inDir, outDir = inDir.Unit, outDir.Unit
				local cross = inDir.X * outDir.Z - inDir.Z * outDir.X -- > 0: right (X right, Z toward the viewer)
				local ang = math.deg(math.acos(math.clamp(inDir:Dot(outDir), -1, 1))) * (cross >= 0 and 1 or -1)
				if math.abs(ang) >= TURN_DEG then
					local name = ""
					if graph then
						local e = graph:nearest(v + outDir * 10)
						name = e and Lang.name(e) or ""
					end
					return dist, ang, name, false
				end
			end
		end
		dist += (path[i + 1] - v).Magnitude
	end
	return dist, nil, nil, true -- no more turns: the destination
end

local function update()
	local path = GPS.path
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (path and #path >= 2 and root and Drive.current() and not State.cutscene) then
		card.Visible = false
		return
	end
	local dist, ang, name, arrive = nextTurn(path, root.Position)
	if not dist then
		card.Visible = false
		return
	end
	card.Visible = true
	local close = dist < 40 / STUD_M -- the last 40 m
	if arrive then
		arrow.Text = "🏁"
		title.Text = L("Arriving in ", "ถึงที่หมายในอีก ") .. meters(dist)
		sub.Text = Lang.t(GPS.name or "")
	else
		local a = ang :: number
		local right = a > 0
		local word
		if math.abs(a) > 150 then
			arrow.Text, word = "↩️", L("make a U-turn", "กลับรถ")
		elseif math.abs(a) < 60 then
			arrow.Text, word = right and "↗️" or "↖️", right and L("bear right", "เบี่ยงขวา") or L("bear left", "เบี่ยงซ้าย")
		else
			arrow.Text, word = right and "➡️" or "⬅️", right and L("turn right", "เลี้ยวขวา") or L("turn left", "เลี้ยวซ้าย")
		end
		title.Text = (close and "" or L("In ", "อีก ")) .. (close and word or (meters(dist) .. " " .. word))
		sub.Text = (name and name ~= "") and (L("into ", "เข้า ") .. name) or ""
	end
	card.BackgroundColor3 = close and Color3.fromRGB(230, 140, 20) or Color3.fromRGB(18, 92, 64)
	stroke.Transparency = close and 0 or 0.6
end

function Turn.start()
	build()
	task.spawn(function()
		-- the road graph is GPS's; index its nodes by position once it is there
		while not (GPS.graph and GPS.graph()) do task.wait(1) end
		for _, n in ipairs(GPS.graph().nodes) do nodeAt[key(n.pos)] = n end
		while true do
			local ok, err = pcall(update)
			if not ok then warn("[TurnHint] " .. tostring(err)) end
			task.wait(0.25)
		end
	end)
end

return Turn
