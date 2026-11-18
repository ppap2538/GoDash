-- Ghosts on night deliveries (2026-11-18, owner: Thai riders who deliver to lonely, dark places meet ghosts and then
-- tell it on a ghost radio show; "ขอเป็นคัทซีนด้วย"). Spooky, never gory: a figure in white, lights flicker, the
-- money turns into leaves, she is gone. Players can turn ghost scenes off (Phone > Settings).
--   * ghost customer: a food delivery late at night (21:00-04:30) to a lonely place (Map.landUse suburb / rural)
--     may play the "ghost" scene instead of the normal hand-over (client/Ghosts). The job is paid as usual, plus
--     ฿SCARE_PAY "ค่าขวัญเสีย". At most once per in-game night, and not twice within 6 real minutes.
--   * roadside figure: the client spots a dark rural road and shows a figure under a tree; it reports "ghost_seen"
--     (rate-limited the same way) for ฿SCARE_PAY / 2
--   * after either: the rider may call our own show "วิทยุคืนหลอน 13.13" (not the real "The Ghost Radio"): City op
--     "ghost_radio" pays season XP + ฿RADIO_PAY once per encounter and posts it on everyone's City Feed.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Map = require(Shared.Config.Maps.KhonKaen)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local SeasonService = require(script.Parent.SeasonService)
local Time = require(script.Parent.TimeService)
local City = require(script.Parent.CityRemote)
local Jobs = require(script.Parent.JobService)

local Service = {}
Service.SCARE_PAY = 60
Service.RADIO_PAY = 100
Service.RADIO_XP = 20
local GAP = 6 * 60

local st = {} :: { [Player]: { night: number, at: number, pending: { variant: string, place: string }? } }
Players.PlayerRemoving:Connect(function(p) st[p] = nil end)
local graph = nil

-- the street the story happened on (Thai name), for the radio and the City Feed
local function placeName(pos: Vector3): string
	if not graph then return "" end
	local RoadGraph = require(Shared.RoadGraph)
	local best, bestD
	for _, e in ipairs(graph:edgesNear(pos, 90)) do
		local nm = (e.thai ~= "" and e.thai) or e.name
		if nm ~= "" then
			local _, _, _, d2 = RoadGraph.project(e, pos.X, pos.Z)
			if not bestD or d2 < bestD then best, bestD = nm, d2 end
		end
	end
	return best or ""
end

local function lateNight(): boolean
	local c = Lighting.ClockTime
	return c >= 21 or c < 4.5
end

local function lonely(pos: Vector3): boolean
	local ok, use = pcall(Map.landUse, pos.X, pos.Z)
	return ok and (use == "suburb" or use == "rural")
end

local function allowed(player: Player): boolean
	local d = Data.get(player)
	if not d or (d.settings and d.settings.ghosts == false) then return false end
	local s = st[player]
	local night = Time.day() -- one ghost per in-game night: the night of day N
	if s and (s.night == night or os.clock() - s.at < GAP) then return false end
	return true
end

local function mark(player: Player, variant: string, place: string)
	st[player] = { night = Time.day(), at = os.clock(), pending = { variant = variant, place = place } }
end

-- JobService asks before the hand-over scene of a food delivery
local function deliverScene(player: Player, job)
	if RunService:IsStudio() and Workspace:GetAttribute("QaGhost") then
		Workspace:SetAttribute("QaGhost", nil)
	elseif not (lateNight() and lonely(job.dropoff.pos) and allowed(player)) then
		return nil
	else
		local c = Lighting.ClockTime
		local chance = (c >= 23 or c < 2) and 0.55 or 0.38 -- the small hours are the worst
		if math.random() > chance then return nil end
	end
	local place = placeName(job.dropoff.pos)
	mark(player, "customer", place)
	task.delay(9, function()
		if player.Parent then
			Economy.add(player, Service.SCARE_PAY, "ghost", false)
			Net.fire(player, "Notify", "toast", { text = ("👻 +฿%d for the fright (the app paid the order in full)"):format(Service.SCARE_PAY),
				th = ("👻 +฿%d ค่าขวัญเสีย (แอปโอนค่าส่งให้ครบแล้วนะ)"):format(Service.SCARE_PAY), good = true })
		end
	end)
	return { kind = "ghost", variant = "customer", pos = job.dropoff.pos, name = job.customer, place = place }
end

function Service.start(world)
	graph = world and world.graph
	Jobs.deliverScene = deliverScene
	-- the roadside figure (client/Ghosts decides where; the server only checks it is fair and pays)
	City.register("ghost_seen", function(player, arg)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local qa = RunService:IsStudio() and Workspace:GetAttribute("QaGhostOk") == true -- Studio: accept a test sighting anywhere
		if not root or not (qa or (lateNight() and lonely(root.Position) and allowed(player))) then return false, "" end
		local _ = arg
		mark(player, "roadside", placeName(root.Position))
		Economy.add(player, Service.SCARE_PAY // 2, "ghost", false)
		return true
	end)
	-- the call-in to the radio show
	City.register("ghost_radio", function(player)
		local s = st[player]
		local p = s and s.pending
		if not p then return false, "Nothing to tell" end
		s.pending = nil
		Economy.add(player, Service.RADIO_PAY, "ghost_radio", false)
		SeasonService.addXp(player, Service.RADIO_XP)
		local place = p.place ~= "" and p.place or "ชานเมือง"
		Net.fireAll("Notify", "feed", { key = "ghost_radio", vars = { name = player.DisplayName, place = place }, me = false })
		return true, nil, { variant = p.variant, place = place }
	end)
end

return Service
