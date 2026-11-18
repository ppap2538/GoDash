-- Rider crews (2026-11-19; Config/Crews). City ops: "crew_join" <id> (once a day), "crew_leave", "crew_board" -> the
-- weekly totals { { id, n } } (cached a minute). d.crew = id, d.crewAt = os.time() of the last change.
-- Members ride in a vest of the crew colour with its name on the back; each delivery adds 1 to the crew's weekly
-- total (OrderedDataStore GoDash_Week<week>_crews, the same week numbers as the other weekly boards).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Crews = require(ReplicatedStorage.Shared.Config.Crews)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Data = require(script.Parent.PlayerDataService)
local City = require(script.Parent.CityRemote)
local Board = require(script.Parent.LeaderboardService)

local Service = {}
local SUFFIX = RunService:IsStudio() and "_Studio" or ""
local cache, cacheAt, cacheWeek = {}, -1e9, -1

local function store(week: number)
	return DataStoreService:GetOrderedDataStore(("GoDash_Week%d_crews%s"):format(week, SUFFIX))
end

-- a member of player's crew made a delivery
function Service.delivered(player: Player)
	local d = Data.get(player)
	local crew = d and type(d.crew) == "string" and Crews.BY_ID[d.crew]
	if not crew then return end
	task.spawn(function()
		pcall(function() store(Board.weekId()):IncrementAsync(crew.id, 1) end)
	end)
end

local function board()
	local week = Board.weekId()
	if week == cacheWeek and os.clock() - cacheAt < 60 then return cache end
	local out = {}
	local ok, pages = pcall(function() return store(week):GetSortedAsync(false, 10) end)
	if ok and pages then
		for _, e in ipairs(pages:GetCurrentPage()) do
			if Crews.BY_ID[e.key] then table.insert(out, { id = e.key, n = e.value }) end
		end
	end
	cache, cacheAt, cacheWeek = out, os.clock(), week
	return out
end

-- the vest: a thin shell round the upper torso in the crew colour, the crew name on the back
local function vestOn(char: Model, crew)
	local torso = char:FindFirstChild("UpperTorso") :: BasePart?
	if not torso then return end
	local old = char:FindFirstChild("GoDashVest")
	if old and old:GetAttribute("Crew") == crew.id then return end
	if old then old:Destroy() end
	local p = Instance.new("Part")
	p.Name = "GoDashVest"
	p.Size = torso.Size + Vector3.new(0.12, -0.15, 0.12)
	p.CFrame = torso.CFrame * CFrame.new(0, 0.05, 0)
	p.Color = crew.color
	p.Material = Enum.Material.Fabric
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
	p:SetAttribute("Crew", crew.id)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = torso, p
	w.Parent = p
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(200, 160)
	sg.LightInfluence = 0.3
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.Text = crew.icon .. "\n" .. crew.th
	t.Parent = sg
	sg:SetAttribute("NoTranslate", true)
	sg.Parent = p
	p.Parent = char
end

function Service.start()
	City.register("crew_join", function(player, arg)
		local d = Data.get(player)
		local crew = type(arg) == "string" and Crews.BY_ID[arg]
		if not d or not crew then return false, "Bad request" end
		if d.crew == crew.id then return false, "You're already in it" end
		if type(d.crewAt) == "number" and os.time() - d.crewAt < Crews.SWITCH_HOURS * 3600 then
			return false, "You can change crew once a day"
		end
		d.crew = crew.id
		d.crewAt = os.time()
		Data.touch(player, "crew", "crewAt")
		return true, ("%s Joined %s"):format(crew.icon, crew.en)
	end)
	City.register("crew_leave", function(player)
		local d = Data.get(player)
		if not d or type(d.crew) ~= "string" then return false, "" end
		d.crew = false
		Data.touch(player, "crew")
		return true, "Left the crew"
	end)
	City.register("crew_board", function(player)
		return true, "", board()
	end)
	-- the vest while riding a two-wheeler or driving (it is what other riders see)
	task.spawn(function()
		while true do
			task.wait(0.7)
			for _, p in ipairs(Players:GetPlayers()) do
				local char = p.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum then
					local d = Data.get(p)
					local crew = d and type(d.crew) == "string" and Crews.BY_ID[d.crew]
					local seat = hum.SeatPart
					local veh = seat and seat:FindFirstAncestorWhichIsA("Model")
					local def = veh and Vehicles.ById[veh:GetAttribute("VehicleId") or ""]
					if crew and def and def.class == "bike" then
						pcall(vestOn, char, crew)
					else
						local old = char:FindFirstChild("GoDashVest")
						if old then old:Destroy() end
					end
				end
			end
		end
	end)
end

return Service
