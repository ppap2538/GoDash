-- Rider gear (2026-11-19; Config/Gear): City op "gear_buy" <id> buys an item once and puts it on; "gear_use" <id>
-- switches to an item already owned ("gear_use" "none:<slot>" takes that slot off). d.gear = { owned, bag, helmet }.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Gear = require(ReplicatedStorage.Shared.Config.Gear)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local City = require(script.Parent.CityRemote)

local Service = {}

local function gearOf(d)
	if type(d.gear) ~= "table" then d.gear = {} end
	if type(d.gear.owned) ~= "table" then d.gear.owned = {} end
	return d.gear
end

-- A helmet made of parts, welded to the head: a shell, a visor on the full-face ones, ears on the dog one.
-- Hats and hair are hidden under it (their handles go transparent; the old value is kept and restored after).
local function putOn(char: Model, g)
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head then return end
	local old = char:FindFirstChild("GoDashHelmet")
	if old and old:GetAttribute("Id") == g.id then return end
	if old then old:Destroy() end
	local m = Instance.new("Model")
	m.Name = "GoDashHelmet"
	m:SetAttribute("Id", g.id)
	local hs = head.Size
	local r = math.max(hs.X, hs.Z) * 1.32
	local function part(size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?, mat: Enum.Material?, transp: number?)
		local p = Instance.new("Part")
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.Color = color
		p.Material = mat or (g.shiny and Enum.Material.Foil or Enum.Material.SmoothPlastic)
		p.Transparency = transp or 0
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.CastShadow = false
		p.CFrame = head.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = head, p
		w.Parent = p
		p.Parent = m
		return p
	end
	part(Vector3.new(r, r * (g.shape == "full" and 1.02 or 0.86), r), CFrame.new(0, hs.Y * (g.shape == "full" and 0.12 or 0.22), 0.04), g.color, Enum.PartType.Ball)
	if g.shape == "full" then
		part(Vector3.new(r * 0.78, hs.Y * 0.42, 0.14), CFrame.new(0, hs.Y * 0.08, -r * 0.47), Color3.fromRGB(20, 24, 30), nil, Enum.Material.Glass, 0.25)
	else
		part(Vector3.new(r * 0.8, 0.1, r * 0.26), CFrame.new(0, hs.Y * 0.44, -r * 0.46) * CFrame.Angles(math.rad(-20), 0, 0), g.color) -- the peak (above the eyes)
	end
	if g.ears then
		for _, sx in ipairs({ -1, 1 }) do
			part(Vector3.new(0.22, r * 0.42, r * 0.3), CFrame.new(sx * r * 0.34, hs.Y * 0.62, 0.05) * CFrame.Angles(0, 0, sx * math.rad(-18)), Color3.fromRGB(150, 90, 40))
		end
	end
	for _, a in ipairs(char:GetChildren()) do
		if a:IsA("Accessory") and (a.AccessoryType == Enum.AccessoryType.Hat or a.AccessoryType == Enum.AccessoryType.Hair) then
			local h = a:FindFirstChild("Handle") :: BasePart?
			if h and h:GetAttribute("GoDashHid") == nil then
				h:SetAttribute("GoDashHid", h.Transparency)
				h.Transparency = 1
			end
		end
	end
	m.Parent = char
end

local function takeOff(char: Model)
	local old = char:FindFirstChild("GoDashHelmet")
	if not old then return end
	old:Destroy()
	for _, a in ipairs(char:GetChildren()) do
		local h = a:IsA("Accessory") and a:FindFirstChild("Handle") :: BasePart?
		if h and h:GetAttribute("GoDashHid") ~= nil then
			h.Transparency = h:GetAttribute("GoDashHid")
			h:SetAttribute("GoDashHid", nil)
		end
	end
end

-- the helmet the player wears now (on a motorbike or a bicycle), or nil
function Service.helmetOn(player: Player)
	local d = Data.get(player)
	return d and Gear.worn(d.gear, "helmet") or nil
end

function Service.start()
	-- the helmet goes on when you sit on a bike, comes off when you get off
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, p in ipairs(Players:GetPlayers()) do
				local char = p.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum then
					local seat = hum.SeatPart
					local veh = seat and seat:FindFirstAncestorWhichIsA("Model")
					local def = veh and Vehicles.ById[veh:GetAttribute("VehicleId") or ""]
					local d = Data.get(p)
					local g = def and def.class == "bike" and d and Gear.worn(d.gear, "helmet")
					if g then pcall(putOn, char, g) else pcall(takeOff, char) end
				end
			end
		end
	end)

	City.register("gear_buy", function(player, arg)
		local d = Data.get(player)
		local g = type(arg) == "string" and Gear.BY_ID[arg]
		if not d or not g then return false, "Bad request" end
		local gear = gearOf(d)
		if Gear.owns(gear, g.id) then return false, "You already have it" end
		if not Economy.spend(player, g.price, "gear:" .. g.id) then return false, "Not enough money" end
		gear.owned[g.id] = true
		gear[g.slot] = g.id
		if g.slot == "helmet" then gear.helmetOff = nil end
		Data.touch(player, "gear")
		return true, ("%s %s: bought and in use"):format(g.icon, g.en)
	end)
	City.register("gear_use", function(player, arg)
		local d = Data.get(player)
		if not d or type(arg) ~= "string" then return false, "Bad request" end
		local gear = gearOf(d)
		local slot = arg:match("^none:(%a+)$")
		if slot then
			gear[slot] = nil
			if slot == "helmet" then gear.helmetOff = true end
		else
			local g = Gear.BY_ID[arg]
			if not g or not Gear.owns(gear, g.id) then return false, "Bad request" end
			gear[g.slot] = g.id
			if g.slot == "helmet" then gear.helmetOff = nil end
		end
		Data.touch(player, "gear")
		return true, ""
	end)
end

return Service
