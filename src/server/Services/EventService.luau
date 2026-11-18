-- Rush Hour (2026-11-17 Tier-A plan): at the start of every hour (UTC, so every server at once) the
-- city gets 10 busy minutes. Job pay +50 % (JobService reads Workspace "RushUntil"), every job adds
-- to a race in this server, and when it ends the top three riders get prizes and season XP.
-- Studio hook: Workspace attribute QaRush = true starts a 2-minute rush now.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Season = require(Shared.Config.Season)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local SeasonService = require(script.Parent.SeasonService)

local Service = {}
Service.LENGTH = 10 * 60
Service.BONUS = 0.5
local PRIZES = { 3000, 2000, 1000 }

local counts = {} :: { [Player]: number }
local running = false

function Service.active(): boolean
	return (Workspace:GetAttribute("RushUntil") or 0) > os.time()
end

-- a finished job during Rush Hour
function Service.job(player: Player)
	if not Service.active() then return end
	counts[player] = (counts[player] or 0) + 1
	player:SetAttribute("RushJobs", counts[player])
	SeasonService.addXp(player, Season.XP.rush)
end

local function run(seconds: number)
	if running then return end
	running = true
	counts = {}
	for _, p in ipairs(Players:GetPlayers()) do p:SetAttribute("RushJobs", 0) end
	Workspace:SetAttribute("RushUntil", os.time() + seconds)
	Net.fireAll("Notify", "toast", { text = "🔥 RUSH HOUR! Pay +50% for 10 minutes: the most jobs in this server wins a prize",
		th = "🔥 ชั่วโมงเร่งด่วน! ค่าส่ง +50% 10 นาที ใครส่งได้มากสุดในเซิร์ฟรับรางวัล", good = true })
	task.wait(seconds)
	Workspace:SetAttribute("RushUntil", nil)
	local list = {}
	for p, n in pairs(counts) do
		if p.Parent and n > 0 then table.insert(list, { p = p, n = n }) end
	end
	table.sort(list, function(a, b) return a.n > b.n end)
	local names = {}
	for i = 1, math.min(3, #list) do
		local e = list[i]
		Economy.add(e.p, PRIZES[i], "rush", true)
		SeasonService.addXp(e.p, 60 - i * 10)
		Net.fire(e.p, "Notify", "bigwin", { title = ("Rush Hour #%d!"):format(i), text = ("+฿%d"):format(PRIZES[i]), icon = ({ "🥇", "🥈", "🥉" })[i] })
		table.insert(names, ({ "🥇", "🥈", "🥉" })[i] .. " " .. e.p.DisplayName .. " (" .. e.n .. ")")
	end
	if #names > 0 then
		Net.fireAll("Notify", "toast", { text = "🏁 Rush Hour over: " .. table.concat(names, "  "), th = "🏁 หมดชั่วโมงเร่งด่วน: " .. table.concat(names, "  "), good = true })
	end
	for _, p in ipairs(Players:GetPlayers()) do p:SetAttribute("RushJobs", nil) end
	running = false
end

function Service.start()
	Players.PlayerRemoving:Connect(function(p) counts[p] = nil end)
	task.spawn(function()
		while true do
			local t = os.time()
			local into = t % 3600
			if into < Service.LENGTH and not running then
				task.spawn(run, Service.LENGTH - into) -- joined in the middle of one: the rest of it
			end
			task.wait(15)
		end
	end)
	if RunService:IsStudio() then
		Workspace:GetAttributeChangedSignal("QaRush"):Connect(function()
			if Workspace:GetAttribute("QaRush") then
				Workspace:SetAttribute("QaRush", nil)
				task.spawn(run, 120)
			end
		end)
	end
end

return Service
