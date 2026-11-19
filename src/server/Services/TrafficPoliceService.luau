-- Player traffic police (2026-11-19, viral pack; owner: "ทำได้เลยทั้งหมด"). A rider can sign on as a traffic officer
-- (phone app 🚔, City op "police_duty"). While officers are on duty:
--   * a red light, a zebra crossing or riding on the pavement near one (DUTY_RANGE) is not ticketed by the camera:
--     the rider becomes "wanted" for WANTED_SECONDS (player attributes Wanted = reason, WantedUntil = server time;
--     every client shows 🚨 over them) and the officers near are told
--   * an officer who gets within STOP_RANGE presses "pull over" (City op "police_stop" <UserId>): the ticket goes
--     through FineService (the daily limits still apply), the rider gets the pulled-over scene, the officer a
--     bounty when money was really taken (at most BOUNTY_DAY a real day)
--   * get away for the whole minute and it is forgotten
-- Officers can only ever catch real offences: nobody can be ticketed for nothing. An officer on duty takes no
-- delivery orders (JobService), and an officer breaking the rules is ticketed the normal way.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Fines = require(script.Parent.FineService)
local City = require(script.Parent.CityRemote)

local Service = {}
Service.DUTY_RANGE = 260
Service.WANTED_SECONDS = 60
Service.STOP_RANGE = 16
Service.BOUNTY = 100
Service.BOUNTY_DAY = 10
Service.MIN_LEVEL = 2

local onDuty = {} :: { [Player]: { since: number, catches: number } }
local wanted = {} :: { [Player]: { reason: string, amount: number, untilT: number } }

local WHAT = {
	redlight = { "ran a red light", "ฝ่าไฟแดง" },
	zebra = { "didn't stop at a zebra crossing", "ไม่หยุดให้คนข้ามทางม้าลาย" },
	sidewalk = { "rode on the pavement", "ขี่บนทางเท้า" },
}

local function root(p: Player): Vector3?
	local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return r and r.Position or nil
end

local function toast(p: Player, en: string, th: string, good: boolean?)
	Net.fire(p, "Notify", "toast", { text = en, th = th, good = good, bad = not good })
end

local function clearWanted(p: Player)
	wanted[p] = nil
	if p.Parent then
		p:SetAttribute("Wanted", nil)
		p:SetAttribute("WantedUntil", nil)
	end
end

local function setDuty(p: Player, on: boolean)
	if on then
		onDuty[p] = onDuty[p] or { since = os.clock(), catches = 0 }
	else
		onDuty[p] = nil
	end
	p:SetAttribute("PoliceDuty", on or nil)
end

function Service.onDuty(p: Player): boolean
	return onDuty[p] ~= nil
end

function Service.start()
	Players.PlayerRemoving:Connect(function(p) onDuty[p] = nil; wanted[p] = nil end)

	-- the camera ticket becomes a chase when an officer is near
	Fines.policeHook = function(player: Player, amount: number, reason: string): boolean
		if onDuty[player] then return false end
		local pos = root(player)
		if not pos then return false end
		local near = {}
		for o in pairs(onDuty) do
			local op = o ~= player and o.Parent and root(o)
			if op and (op - pos).Magnitude < Service.DUTY_RANGE then table.insert(near, o) end
		end
		if #near == 0 then return false end
		if wanted[player] then return true end -- already wanted: one chase at a time, no second ticket
		local untilT = Workspace:GetServerTimeNow() + Service.WANTED_SECONDS
		wanted[player] = { reason = reason, amount = amount, untilT = untilT }
		player:SetAttribute("Wanted", reason)
		player:SetAttribute("WantedUntil", untilT)
		local w = WHAT[reason] or { reason, reason }
		for _, o in ipairs(near) do
			toast(o, ("🚨 %s %s near you! Catch them within a minute"):format(player.DisplayName, w[1]),
				("🚨 %s %s ใกล้คุณ! ตามจับให้ทันใน 1 นาที"):format(player.DisplayName, w[2]))
		end
		return true
	end

	-- a minute is up: got away
	task.spawn(function()
		while true do
			task.wait(1)
			local now = Workspace:GetServerTimeNow()
			for p, w in pairs(wanted) do
				if now > w.untilT then
					clearWanted(p)
					if p.Parent then toast(p, "😅 You got away from the traffic police... this time", "😅 หนีตำรวจรอด... รอบนี้นะ", true) end
				end
			end
		end
	end)

	City.register("police_duty", function(player)
		local d = Data.get(player)
		if not d then return false, "Not ready" end
		if onDuty[player] then
			setDuty(player, false)
			return true, "Off duty"
		end
		if (d.level or 1) < Service.MIN_LEVEL then return false, "Traffic police opens at level 2" end
		local Jobs = require(script.Parent.JobService)
		if Jobs.isBusy(player) then return false, "Finish your order first" end
		if wanted[player] then return false, "You are wanted yourself!" end
		setDuty(player, true)
		return true, "On duty: catch the riders who break the rules"
	end)

	City.register("police_stop", function(officer, arg)
		if not onDuty[officer] then return false, "You are not on duty" end
		local target = Players:GetPlayerByUserId(tonumber(arg) or 0)
		local w = target and wanted[target]
		if not target or not w then return false, "Nobody to pull over" end
		local a, b = root(officer), root(target)
		if not a or not b or (a - b).Magnitude > Service.STOP_RANGE then return false, "Get closer" end
		clearWanted(target)
		local ok, taken, why, n, limit = Fines.charge(target, "ticket", w.amount, w.reason, true)
		local what = WHAT[w.reason] or { w.reason, w.reason }
		if ok then
			Net.fire(target, "Notify", "scene", { kind = "fine", reason = w.reason, amount = taken, n = n, limit = limit })
			toast(target, ("🚔 Pulled over by officer %s: %s · ฿%d"):format(officer.DisplayName, what[1], taken),
				("🚔 โดนตำรวจ %s เรียกจอด: %s · ฿%d"):format(officer.DisplayName, what[2], taken))
		else
			Fines.warn(target, "ticket", why, "🚔 " .. what[1], "🚔 " .. what[2])
		end
		local st = onDuty[officer]
		st.catches += 1
		-- the bounty: only when money was really taken, and not without end
		local d = Data.get(officer)
		if d and ok and taken > 0 then
			Economy.rollDay(d)
			local got = tonumber(d.daily.bounties) or 0
			if got < Service.BOUNTY_DAY then
				d.daily.bounties = got + 1
				Data.touch(officer, "daily")
				Economy.add(officer, Service.BOUNTY, "police_bounty", true)
				return true, ("Caught! +฿%d"):format(Service.BOUNTY)
			end
			return true, "Caught! (today's bounties are used up)"
		end
		return true, "Caught! (no fine this time: they were let off)"
	end)
end

return Service
