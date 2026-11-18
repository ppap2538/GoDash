-- Invite friends (2026-11-18 plan, owner: "ทำทั้งหมดที่เสนอมาได้เลย"; the goal is 250 engaged players).
-- The phone's "Invite" app opens Roblox's invite card (client/Invite). A friend who joins through the invite
-- carries the inviter's user id in their join data. If that friend is NEW to GoDash (first join within 15 minutes,
-- no job done yet) they start with ฿NEW_REWARD and the inviter gets ฿INVITER_REWARD (at most DAILY_CAP friends a
-- day, each friend once ever). An inviter in another server, or offline, is paid on their next join from a small
-- DataStore queue. Nothing here can be farmed with alt accounts beyond the daily cap of ฿5,000.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local City = require(script.Parent.CityRemote)

local Service = {}
Service.NEW_REWARD = 500
Service.INVITER_REWARD = 1000
Service.DAILY_CAP = 5
local NEW_WINDOW = 15 * 60

local store
local function getStore()
	if store == nil then
		local ok, ds = pcall(function()
			return DataStoreService:GetDataStore("GoDash_Referrals_v1" .. (RunService:IsStudio() and "_Studio" or ""))
		end)
		store = ok and ds or false
	end
	return store or nil
end

-- pay the inviter for one friend (they are in this server)
local function payInviter(inviter: Player, friendName: string): boolean
	local d = Data.get(inviter)
	if not d then return false end
	Economy.rollDay(d)
	d.daily.invites = d.daily.invites or 0
	if d.daily.invites >= Service.DAILY_CAP then return false end
	d.daily.invites += 1
	d.referrals = (d.referrals or 0) + 1
	Data.touch(inviter, "daily", "referrals")
	Economy.add(inviter, Service.INVITER_REWARD, "invite", false)
	Net.fire(inviter, "Notify", "bigwin", { title = "👥 Friend joined!", text = ("+฿%d · %s"):format(Service.INVITER_REWARD, friendName), icon = "👥" })
	return true
end

local function queueFor(inviterId: number, friendId: number)
	local ds = getStore()
	if not ds then return end
	pcall(function()
		ds:UpdateAsync("q_" .. inviterId, function(old)
			local list = type(old) == "table" and old or {}
			if #list < 40 then table.insert(list, friendId) end
			return list
		end)
	end)
end

-- an inviter joins: friends who came in while they were away
local function claimQueue(player: Player)
	local ds = getStore()
	if not ds then return end
	local got = {}
	pcall(function()
		ds:UpdateAsync("q_" .. player.UserId, function(old)
			got = type(old) == "table" and old or {}
			return {}
		end)
	end)
	local paid = 0
	for _ in ipairs(got) do
		if payInviter(player, "") then paid += 1 end
	end
	if paid > 0 then
		Net.fire(player, "Notify", "toast", { text = ("👥 %d friend(s) joined through your invite while you were away!"):format(paid),
			th = ("👥 เพื่อน %d คนเข้าเกมจากคำชวนของคุณ ระหว่างที่คุณไม่อยู่!"):format(paid), good = true })
	end
end

local function onLoaded(player: Player, d)
	task.spawn(claimQueue, player)
	local ok, join = pcall(function() return player:GetJoinData() end)
	local inviterId = ok and type(join) == "table" and tonumber(join.ReferredByPlayerId) or 0
	if not inviterId or inviterId == 0 or inviterId == player.UserId or d.referredBy then return end
	local new = (os.time() - (d.firstJoin or 0)) < NEW_WINDOW and (d.stats.deliveries or 0) + (d.stats.rides or 0) == 0
	if not new then return end
	d.referredBy = inviterId
	Data.touch(player, "referredBy")
	Economy.add(player, Service.NEW_REWARD, "invited", false)
	task.delay(8, function()
		if player.Parent then
			Net.fire(player, "Notify", "toast", { text = ("👥 A friend invited you: here is ฿%d to start!"):format(Service.NEW_REWARD),
				th = ("👥 เพื่อนชวนมาเล่น รับเงินเริ่มต้น ฿%d!"):format(Service.NEW_REWARD), good = true })
		end
	end)
	local inviter = Players:GetPlayerByUserId(inviterId)
	if inviter and Data.get(inviter) then
		payInviter(inviter, player.DisplayName)
	else
		task.spawn(queueFor, inviterId, player.UserId)
	end
end

function Service.start()
	Data.onLoaded(onLoaded)
	-- client/Invite asked for Roblox's event-alert opt-in once: do not ask by itself again
	City.register("alerts_asked", function(player)
		local d = Data.get(player)
		if not d then return false, "Not ready" end
		d.alertsAsked = true
		Data.touch(player, "alertsAsked")
		return true
	end)
	local _ = Util
end

return Service
