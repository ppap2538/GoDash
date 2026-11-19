-- Coming back every day (2026-11-17 growth plan):
--   * phone app "Top Riders": this week's three boards from server/LeaderboardService (money earned
--     from jobs, jobs done, five-star jobs), with your own numbers and the time until Monday's reset
--   * the daily reward card pops up by itself once per session when today's reward is waiting
--     (until now it sat in the Missions app and most riders never found it)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Game = require(Shared.Config.Game)
local Util = require(Shared.Util)
local UI = require(script.Parent.UI.Kit)
local Layout = require(script.Parent.UI.Core.Layout)
local Layers = require(script.Parent.UI.Core.Layers)
local UIState = require(script.Parent.UI.Core.UIState)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)
local Phone = require(script.Parent.Phone)

local Board = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(214, 156, 32)

local data: any = nil
local fetchedAt = -1e9
local fetching = false
local tab = "earned"

local function noT(l: Instance)
	l:SetAttribute("NoTranslate", true)
	return l
end

local function fetch()
	if fetching then return end
	fetching = true
	local ok, _, res = Net.call("City", "board")
	fetching = false
	if ok and type(res) == "table" then
		data = res
		fetchedAt = os.clock()
		if Phone.current() == "board" then Phone.refresh() end
	end
end

local function value(stat: string, v: number): string
	if stat == "earned" then return Util.money(v) end
	if stat == "jobs" then return L(Util.num(v) .. " jobs", Util.num(v) .. " งาน") end
	return Util.num(v) .. " ⭐"
end

local function timeLeft(s: number): string
	local days = math.floor(s / 86400)
	local hours = math.floor(s % 86400 / 3600)
	if days > 0 then return L(("%d d %d h"):format(days, hours), ("%d วัน %d ชม."):format(days, hours)) end
	return L(("%d h %d min"):format(hours, math.floor(s % 3600 / 60)), ("%d ชม. %d นาที"):format(hours, math.floor(s % 3600 / 60)))
end

local function screen()
	local ui = Phone.ui
	local content = ui.content()
	if os.clock() - fetchedAt > 30 then task.spawn(fetch) end
	local hero = ui.bigCard(92, GOLD)
	noT(UI.label(hero, L("🏆 Top Riders this week", "🏆 ไรเดอร์ยอดเยี่ยมประจำสัปดาห์"), 17, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) }))
	noT(UI.label(hero, L("Every rider in every server. Starts again on Monday.", "นับทุกคนทุกเซิร์ฟเวอร์ เริ่มใหม่ทุกวันจันทร์"), 12, C.white, F.med,
		{ Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 18) }))
	noT(UI.label(hero, data and (L("Resets in ", "รีเซ็ตใน ") .. timeLeft(data.left or 0)) or L("Loading…", "กำลังโหลด…"), 12, C.white, F.bold,
		{ Position = UDim2.fromOffset(14, 60), Size = UDim2.new(1, -28, 0, 18) }))

	local tabs = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), Parent = content })
	UI.list(tabs, 6, true)
	for _, t in ipairs({ { "earned", L("💰 Money", "💰 รายได้") }, { "jobs", L("📦 Jobs", "📦 งาน") }, { "five", L("⭐ 5 stars", "⭐ 5 ดาว") } }) do
		local sel = tab == t[1]
		noT(UI.button(tabs, t[2], { Size = UDim2.new(1 / 3, -4, 1, 0), TextSize = 13, BackgroundColor3 = sel and GOLD or C.card, TextColor3 = sel and C.white or C.text }, function()
			tab = t[1]
			Phone.refresh()
		end))
	end
	if not data then return end
	local list = data.tops and data.tops[tab] or {}
	local meVal = data.me and data.me[tab] or 0
	local myRank = nil
	for i, e in ipairs(list) do
		if e.id == player.UserId then myRank = i end
	end
	-- you
	local mine = ui.row("🛵", L("You this week", "คุณ สัปดาห์นี้"), myRank and L(("Rank #%d"):format(myRank), ("อันดับ %d"):format(myRank)) or L("Not in the top 10 yet: keep riding!", "ยังไม่ติด 10 อันดับ ขี่ต่อเลย!"), nil, nil,
		{ height = 56 })
	mine.BackgroundColor3 = Color3.fromRGB(255, 246, 220)
	noT(UI.label(mine, value(tab, meVal), 15, C.text, F.black, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0, 120, 1, 0), TextXAlignment = Enum.TextXAlignment.Right }))
	ui.section(L("TOP 10", "10 อันดับแรก"))
	if #list == 0 then
		noT(UI.label(content, L("Nobody yet this week. Be the first!", "สัปดาห์นี้ยังไม่มีใคร เป็นคนแรกเลย!"), 13, C.sub, F.med, { Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center }))
	end
	for i, e in ipairs(list) do
		local medal = ({ "🥇", "🥈", "🥉" })[i] or ("#" .. i)
		local card = ui.row(medal, e.name, nil, nil, nil, { height = 44 })
		if e.id == player.UserId then card.BackgroundColor3 = Color3.fromRGB(226, 246, 232) end
		noT(UI.label(card, value(tab, e.value), 14, C.text, F.black, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0, 120, 1, 0), TextXAlignment = Enum.TextXAlignment.Right }))
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text == e.name then d:SetAttribute("NoTranslate", true) end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- the daily reward card
---------------------------------------------------------------------------------------------------
local shownDaily = false

local function dailyCard()
	local d = State.data
	if shownDaily or not d or not d.dailyReward then return end
	local day = Util.dayNumber()
	if d.dailyReward.day == day then return end
	shownDaily = true
	local streak = (d.dailyReward.day == day - 1) and (d.dailyReward.streak % #Game.DAILY_REWARDS + 1) or 1
	local gui = UI.screen("GoDashDaily", Layers.Modal + 4)
	local dim = UI.scrim(gui, 0.5)
	local center = Layout.region(Layout.stage(gui), "Center")
	local card = UI.new("Frame", { BackgroundColor3 = C.card, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 290), Parent = center })
	UI.corner(card, 24)
	UI.stroke(card, C.red, 3)
	UIState.set("modal", true)
	local head = UI.new("Frame", { BackgroundColor3 = C.red, Size = UDim2.new(1, 0, 0, 70), Parent = card })
	UI.corner(head, 24)
	UI.new("Frame", { BackgroundColor3 = C.red, Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 24), Parent = head })
	noT(UI.label(head, L("🎁 Daily reward", "🎁 รางวัลประจำวัน"), 24, C.white, F.black, { Position = UDim2.fromOffset(20, 8), Size = UDim2.new(1, -40, 0, 30), ZIndex = 2 }))
	noT(UI.label(head, L(("Day %d of 7 · come back every day for bigger rewards"):format(streak), ("วันที่ %d จาก 7 · เข้าเกมทุกวัน รางวัลยิ่งเยอะ"):format(streak)), 13, C.white, F.bold,
		{ Position = UDim2.fromOffset(20, 40), Size = UDim2.new(1, -40, 0, 20), ZIndex = 2 }))
	local strip = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 86), Size = UDim2.new(1, -32, 0, 84), Parent = card })
	UI.list(strip, 6, true)
	for i, r in ipairs(Game.DAILY_REWARDS) do
		local done = i < streak
		local today = i == streak
		local cell = UI.new("Frame", { BackgroundColor3 = today and C.red or (done and Color3.fromRGB(226, 246, 232) or C.bg), Size = UDim2.new(1 / 7, -6, 1, 0), Parent = strip })
		UI.corner(cell, 12)
		if today then UI.stroke(cell, Color3.fromRGB(255, 200, 80), 3) end
		local fg = today and C.white or C.text
		noT(UI.label(cell, L("Day " .. i, "วัน " .. i), 11, fg, F.bold, { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center }))
		noT(UI.label(cell, done and "✅" or (r.item and "🎁" or (i == 7 and "🏆" or "💰")), 22, fg, F.med, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None }))
		noT(UI.label(cell, "฿" .. Util.num(r.money), 11, fg, F.black, { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center }))
	end
	local function close()
		UI.tween(dim, 0.2, { BackgroundTransparency = 1 })
		UI.tween(card, 0.18, { Position = UDim2.fromScale(0.5, 0.6) })
		task.delay(0.2, function()
			gui:Destroy()
			UIState.set("modal", false)
		end)
	end
	local rw = Game.DAILY_REWARDS[streak]
	noT(UI.button(card, L("Claim ", "รับเลย ") .. Util.money(rw.money) .. (rw.item and L(" + a gift", " + ของขวัญ") or ""),
		{ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -48), Size = UDim2.new(1, -40, 0, 50), TextSize = 19, BackgroundColor3 = C.green }, function()
			local ok, msg = Net.call("Mission", "daily")
			if ok then Feedback.good() elseif msg then Feedback.toast(msg, "bad") end
			close()
		end))
	noT(UI.button(card, L("Later", "ไว้ทีหลัง"), { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(140, 30), TextSize = 13, BackgroundColor3 = C.bg, TextColor3 = C.sub }, close))
	local sc = Instance.new("UIScale")
	sc.Scale = 0.6
	sc.Parent = card
	UI.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

function Board.start()
	Phone.addApp({ id = "board", name = "Top Riders", icon = "🏆", color = GOLD }, screen)
	-- the daily card: a few seconds after joining, once nothing else is on screen
	task.spawn(function()
		task.wait(5)
		for _ = 1, 120 do
			if State.data and not UIState.get("modal") and not State.cutscene then
				dailyCard()
				return
			end
			task.wait(1)
		end
	end)
end

return Board
