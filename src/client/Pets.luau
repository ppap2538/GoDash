-- Adopted dogs (2026-11-19, Config/Pets, server/PetService). Every client draws every rider's dog: the
-- player attribute "Pet" = "<look>|<name index>" ("" = it stays home).
--   * on foot it trots along a little behind you and to the side, bounding when you run
--   * on a bicycle, a Sabai-style underbone or the old moped it sits in a wicker basket in front of the
--     handlebars, the way Thai riders carry their dogs; on a scooter it stands on the floorboard; on a sport
--     bike or big bike it lies on the tank; in a car it is inside, so it is not drawn
-- Drawn only within SHOW studs of the camera.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local Vehicles = require(Shared.Config.Vehicles)
local Lang = require(script.Parent.Lang)

local PetsClient = {}
local SHOW = 300
local SCALE = 0.95 -- a little smaller than the strays (1.5), so it fits a basket

-- where the dog sits on each kind of bike, in the seat's frame (-Z = forward)
local SPOT = {
	bicycle = { at = CFrame.new(0, 0.55, -2.75), basket = true },
	oldbike = { at = CFrame.new(0, 0.55, -2.55), basket = true },
	underbone = { at = CFrame.new(0, 0.55, -2.55), basket = true },
	scooter = { at = CFrame.new(0, -0.95, -1.25) },
	sport = { at = CFrame.new(0, 0.35, -1.25) },
	bigbike = { at = CFrame.new(0, 0.4, -1.3) },
}

local template: Model? = nil
local drawn = {} :: { [Player]: any }

local function makeDog(look: number, nameIx: number): any
	local m: Model
	if template then
		m = template:Clone()
		m:ScaleTo(SCALE)
	else
		m = Instance.new("Model")
		local body = Instance.new("Part")
		body.Size = Vector3.new(0.8, 0.8, 1.7)
		body.Parent = m
		m.PrimaryPart = body
		local head = Instance.new("Part")
		head.Size = Vector3.new(0.7, 0.7, 0.7)
		head.CFrame = CFrame.new(0, 0.5, -1)
		head.Parent = m
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = true, false, false, false, true
			if not template then d.Color = Pets.COATS[(look - 1) % #Pets.COATS + 1] end
		end
	end
	local size = m:GetExtentsSize()
	-- a red collar so it reads as somebody's dog, not a stray
	local tag = Instance.new("BillboardGui")
	tag.Name = "PetName"
	tag.Size = UDim2.fromOffset(130, 24)
	tag.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 0.9, 0)
	tag.MaxDistance = 70
	tag.LightInfluence = 0
	tag.Adornee = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 236, 200)
	t.TextStrokeTransparency = 0.4
	local n = Pets.NAMES[nameIx] or Pets.NAMES[1]
	t.Text = "🐶 " .. Lang.pick(n.en, n.th)
	t:SetAttribute("NoTranslate", true)
	t.Parent = tag
	tag.Parent = m
	-- the wicker basket, shown on bikes that carry the dog in front
	local basket = Instance.new("Part")
	basket.Name = "PetBasket"
	basket.Size = Vector3.new(1.5, 0.9, 1.3)
	basket.Color = Color3.fromRGB(176, 132, 78)
	basket.Material = Enum.Material.WoodPlanks
	basket.Anchored, basket.CanCollide, basket.CanQuery, basket.CanTouch = true, false, false, false
	basket.Transparency = 1
	basket.Parent = m
	return { model = m, h = size.Y, basket = basket, pos = nil, look = Vector3.new(0, 0, -1), phase = 0, key = look .. "|" .. nameIx }
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function ground(p: Vector3, ignore: { Instance }): number
	rayParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), rayParams)
	return hit and hit.Position.Y or (p.Y - 3)
end

local function step(dt: number, holder: Folder)
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for _, plr in ipairs(Players:GetPlayers()) do
		local spec = plr:GetAttribute("Pet")
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local st = drawn[plr]
		local look, nameIx = string.match(type(spec) == "string" and spec or "", "^(%d+)|(%d+)$")
		local want = root ~= nil and look ~= nil and (root.Position - camPos).Magnitude < SHOW
		if st and (not want or st.key ~= (look .. "|" .. nameIx)) then
			st.model:Destroy()
			drawn[plr] = nil
			st = nil
		end
		if want and root and hum then
			if not st then
				st = makeDog(tonumber(look) :: number, tonumber(nameIx) :: number)
				st.model.Parent = holder
				drawn[plr] = st
			end
			local seat = hum.SeatPart
			local model = seat and seat.Parent
			local def = (model and seat:IsA("VehicleSeat") and model:HasTag("GoDashVehicle")) and Vehicles.ById[model:GetAttribute("VehicleId")] or nil
			local spot = def and def.class == "bike" and SPOT[def.style] or nil
			if seat and not spot then
				-- in a car (or a seat we have no spot for): the dog is inside, out of sight
				st.model.Parent = nil
				st.pos = nil
			else
				st.model.Parent = holder
				if spot then
					local cf = seat.CFrame * spot.at
					st.basket.Transparency = spot.basket and 0 or 1
					-- (sits down in the basket: a play test had it perched on top)
				local body = cf * CFrame.new(0, st.h / 2 - (spot.basket and 0.3 or 0), 0)
					st.model:PivotTo(body)
					if spot.basket then st.basket.CFrame = cf * CFrame.new(0, 0.25, 0) end
					st.pos = nil
				else
					st.basket.Transparency = 1
					-- trot behind and to the right of the owner
					local fwd = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
					if fwd.Magnitude < 0.05 then fwd = Vector3.new(0, 0, -1) end
					fwd = fwd.Unit
					local right = Vector3.new(-fwd.Z, 0, fwd.X)
					local goal = root.Position - fwd * 3.2 + right * 2.2
					local before = st.pos or goal
					local far = (goal - before).Magnitude
					st.pos = far > 40 and goal or before:Lerp(goal, math.clamp(dt * (far > 6 and 6 or 3), 0, 1))
					local move = st.pos - before
					local speed = Vector3.new(move.X, 0, move.Z).Magnitude / math.max(dt, 1e-3)
					if speed > 1 then st.look = st.look:Lerp(Vector3.new(move.X, 0, move.Z).Unit, math.clamp(dt * 8, 0, 1)) end
					if st.look.Magnitude < 0.01 then st.look = fwd end
					st.phase += dt * (speed > 3 and 14 or 0)
					local hop = speed > 3 and math.abs(math.sin(st.phase)) * 0.35 or 0
					local y = ground(st.pos, { char, holder }) + st.h / 2 + hop
					local p = Vector3.new(st.pos.X, y, st.pos.Z)
					st.model:PivotTo(CFrame.lookAt(p, p + st.look.Unit))
				end
			end
		end
	end
	for plr, st in pairs(drawn) do
		if not plr.Parent then
			st.model:Destroy()
			drawn[plr] = nil
		end
	end
end

function PetsClient.start()
	local store = ReplicatedStorage:FindFirstChild("GoDashModels")
	local t = store and store:FindFirstChild("Dog1")
	template = (t and t:IsA("Model")) and t or nil
	local holder = Instance.new("Folder")
	holder.Name = "GoDashPets"
	holder.Parent = Workspace
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(step, math.min(dt, 1 / 20), holder)
		if not ok then warn("[Pets] " .. tostring(err)) end
	end)
end

return PetsClient
