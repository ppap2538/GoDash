-- Street life drawn on the client from the shared server clock: traffic-light colours and the
-- AI vehicles' movement. Everyone sees the same thing because both are functions of server time.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Traffic = require(Shared.Traffic)
local GPS = require(script.Parent.GPS)

local Street = {}

local LAMP = {
	red = { Color3.fromRGB(255, 50, 40), 1 }, yellow = { Color3.fromRGB(255, 200, 40), 2 }, green = { Color3.fromRGB(60, 230, 110), 3 },
}
local OFF = { Color3.fromRGB(90, 30, 28), Color3.fromRGB(100, 84, 30), Color3.fromRGB(30, 84, 44) }

local function paintSignal(model: Instance, t: number)
	local node, group = model:GetAttribute("Node"), model:GetAttribute("Group")
	if type(node) ~= "number" or type(group) ~= "number" then return end
	local col = Traffic.colour(node, group, t)
	if model:GetAttribute("Shown") == col then return end
	model:SetAttribute("Shown", col)
	local on = LAMP[col]
	for i = 1, 3 do
		local lamp = model:FindFirstChild("Lamp" .. i)
		if lamp and lamp:IsA("BasePart") then
			local lit = on[2] == i
			lamp.Material = lit and Enum.Material.Neon or Enum.Material.SmoothPlastic
			lamp.Color = lit and on[1] or OFF[i]
		end
	end
end

-- AI vehicles ------------------------------------------------------------------------------------
local cars = {} -- [model] = { pts, cum, total, speed, offset, y, seg }

local function prepare(model: Instance)
	if not model:IsA("Model") then return end
	local graph = GPS.graph()
	local path = model:GetAttribute("Path")
	if not graph or type(path) ~= "string" then return end
	local pts, cum, total = {}, { 0 }, 0
	for id in path:gmatch("%d+") do
		local n = graph.nodes[tonumber(id) :: number]
		if n then table.insert(pts, Vector3.new(n.x, 0, n.z)) end
	end
	if #pts < 2 then return end
	for i = 2, #pts do
		total += (pts[i] - pts[i - 1]).Magnitude
		cum[i] = total
	end
	cars[model] = { pts = pts, cum = cum, total = total, speed = model:GetAttribute("Speed") or 40, offset = model:GetAttribute("Offset") or 0,
		y = model:GetAttribute("Y") or 2.5, seg = 1 }
	model.Destroying:Connect(function() cars[model] = nil end)
end

local function moveCars(t: number, camPos: Vector3)
	for model, c in pairs(cars) do
		-- there and back along the route (triangle wave), keeping left of the centre line
		local s = (c.speed * t + c.offset) % (c.total * 2)
		local forward = s <= c.total
		if not forward then s = c.total * 2 - s end
		local i = c.seg
		if i > #c.pts - 1 then i = #c.pts - 1 end
		while i > 1 and c.cum[i] > s do i -= 1 end
		while i < #c.pts - 1 and c.cum[i + 1] < s do i += 1 end
		c.seg = i
		local a, b = c.pts[i], c.pts[i + 1]
		local len = c.cum[i + 1] - c.cum[i]
		local k = len > 0 and (s - c.cum[i]) / len or 0
		local pos = a:Lerp(b, k)
		if (pos - camPos).Magnitude < 1600 then
			local dir = (b - a).Unit * (forward and 1 or -1)
			local left = Vector3.new(dir.Z, 0, -dir.X)
			-- ease the heading through corners instead of snapping
			local look = c.look and c.look:Lerp(dir, 0.18) or dir
			if look.Magnitude < 0.01 then look = dir end
			c.look = look.Unit
			local p = pos + left * 7 + Vector3.new(0, c.y, 0)
			model:PivotTo(CFrame.lookAt(p, p + c.look))
		end
	end
end

function Street.start()
	for _, m in ipairs(CollectionService:GetTagged("TrafficCar")) do prepare(m) end
	CollectionService:GetInstanceAddedSignal("TrafficCar"):Connect(function(m) task.defer(prepare, m) end)
	CollectionService:GetInstanceAddedSignal("TrafficSignal"):Connect(function(m) m:SetAttribute("Shown", nil) end)

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		local t = Workspace:GetServerTimeNow()
		local cam = Workspace.CurrentCamera
		if cam then moveCars(t, cam.CFrame.Position) end
		acc += dt
		if acc > 0.25 then
			acc = 0
			for _, m in ipairs(CollectionService:GetTagged("TrafficSignal")) do paintSignal(m, t) end
		end
	end)
end

return Street
