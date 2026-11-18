-- "Invite" phone app + event alerts (2026-11-18 plan: 250 engaged players).
--   * Invite: Roblox's own invite card (SocialService). A NEW friend who joins through it starts with ฿500 and you
--     get ฿1,000, up to 5 friends a day (server/ReferralService)
--   * Event alerts: Roblox's opt-in card for experience notifications (Loy Krathong starting, Rush Hour...). Asked
--     once by itself after a good moment (the third finished job, or a krathong floated); the app has a button too.
--     Sending them needs a notification template made by the owner in Creator Dashboard.
local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local UI = require(script.Parent.UI.Kit)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)
local Phone = require(script.Parent.Phone)

local Invite = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local TEAL = Color3.fromRGB(20, 150, 140)

function Invite.prompt()
	local ok, can = pcall(function() return SocialService:CanSendGameInviteAsync(player) end)
	if ok and can then
		pcall(function() SocialService:PromptGameInvite(player) end)
	else
		Feedback.toast(L("Invites are not available on this account", "บัญชีนี้ส่งคำชวนไม่ได้"), "bad")
	end
end

local asked = false
function Invite.askAlerts(force: boolean?)
	if asked and not force then return end
	asked = true
	task.spawn(function()
		local ok, ens = pcall(function() return game:GetService("ExperienceNotificationService") end)
		if not ok or not ens then return end
		local okCan, can = pcall(function() return ens:CanPromptOptInAsync() end)
		if okCan and can then
			pcall(function() ens:PromptOptIn() end)
		elseif force then
			Feedback.toast(L("Alerts are already on, or not available here", "เปิดแจ้งเตือนไว้แล้ว หรืออุปกรณ์นี้ไม่รองรับ"), "good")
		end
		Net.call("City", "alerts_asked", "1")
	end)
end

local function screen()
	local ui = Phone.ui
	local d = State.data
	if not d then return end
	local hero = ui.bigCard(118, TEAL)
	local function noT(l) l:SetAttribute("NoTranslate", true) return l end
	noT(UI.label(hero, L("👥 Ride with friends", "👥 ชวนเพื่อนมาขี่ด้วยกัน"), 18, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) }))
	noT(UI.label(hero, L("A new friend who joins through your invite starts with ฿500, and you get ฿1,000 (up to 5 friends a day).",
		"เพื่อนใหม่ที่เข้าเกมจากคำชวนของคุณ ได้เงินเริ่มต้น ฿500 ส่วนคุณได้ ฿1,000 (วันละไม่เกิน 5 คน)"), 13, C.white, F.med,
		{ Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 40), TextWrapped = true }))
	noT(UI.label(hero, L(("Friends joined so far: %d"):format(d.referrals or 0), ("เพื่อนที่เข้ามาแล้ว: %d คน"):format(d.referrals or 0)), 13, C.white, F.bold,
		{ Position = UDim2.fromOffset(14, 86), Size = UDim2.new(1, -28, 0, 20) }))
	noT(UI.button(ui.content(), L("📨 Invite friends", "📨 ชวนเพื่อน"), { Size = UDim2.new(1, 0, 0, 48), TextSize = 17, BackgroundColor3 = TEAL }, Invite.prompt))
	ui.section(L("EVENT ALERTS", "แจ้งเตือนอีเวนต์"))
	noT(UI.label(ui.content(), L("Get a Roblox alert when Loy Krathong, Rush Hour or a new event starts.",
		"รับแจ้งเตือนจาก Roblox ตอนงานลอยกระทง ชั่วโมงเร่งด่วน หรืออีเวนต์ใหม่เริ่ม"), 13, C.sub, F.med, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 34) }))
	noT(UI.button(ui.content(), L("🔔 Turn on alerts", "🔔 เปิดแจ้งเตือน"), { Size = UDim2.new(1, 0, 0, 44), TextSize = 15, BackgroundColor3 = C.dark }, function()
		Invite.askAlerts(true)
	end))
end

function Invite.start()
	Phone.addApp({ id = "invite", name = "Invite", icon = "👥", color = TEAL }, screen)
	-- ask for alerts once, after a good moment
	asked = State.data ~= nil and State.data.alertsAsked == true
	local jobsAtStart
	task.spawn(function()
		while not State.data do task.wait(1) end
		asked = State.data.alertsAsked == true
		jobsAtStart = (State.data.stats.deliveries or 0) + (State.data.stats.rides or 0)
		while not asked do
			task.wait(5)
			local d = State.data
			local jobs = d and (d.stats.deliveries or 0) + (d.stats.rides or 0) or 0
			local floated = d and d.daily and (d.daily.krathong or 0) > 0
			if (jobs >= 3 and jobs > jobsAtStart) or floated then
				task.wait(4) -- let the reward card settle first
				if not State.cutscene then Invite.askAlerts(false) end
			end
		end
	end)
end

return Invite
