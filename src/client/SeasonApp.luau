-- Phone app "Season" (2026-11-17 Tier-A plan): this season's tier, the free and premium rewards
-- of every tier with Claim buttons, the premium pass, and the titles you have unlocked.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Season = require(Shared.Config.Season)
local Store = require(Shared.Config.Store)
local Items = require(Shared.Config.Items)
local Util = require(Shared.Util)
local UI = require(script.Parent.UI.Kit)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Phone = require(script.Parent.Phone)

local SeasonApp = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local PURPLE = Color3.fromRGB(120, 60, 210)

local function noT(l: Instance)
	l:SetAttribute("NoTranslate", true)
	return l
end

local function rewardText(r): string
	if not r then return "—" end
	local parts = {}
	if r.money then table.insert(parts, Util.money(r.money)) end
	if r.exp then table.insert(parts, r.exp .. " EXP") end
	if r.item and Items.ById[r.item] then table.insert(parts, Lang.t(Items.ById[r.item].name) .. " ×" .. (r.qty or 1)) end
	if r.unlock then
		local c = Season.COSMETICS[r.unlock]
		local kind = c.kind == "glow" and L("underglow ", "ไฟใต้ท้อง ") or (c.kind == "sticker" and L("sticker ", "สติกเกอร์ ") or L("title ", "ฉายา "))
		table.insert(parts, "✨ " .. kind .. (c.thai or c.text or c.name))
	end
	return table.concat(parts, " + ")
end

local function screen()
	local ui = Phone.ui
	local content = ui.content()
	local d = State.data
	if not d then return end
	local id = Season.current()
	local s = (type(d.season) == "table" and d.season.id == id) and d.season or { id = id, xp = 0, premium = false, free = {}, prem = {} }
	local tier = math.floor(s.xp / Season.XP_PER_TIER)
	local left = Season.endsAt(id) - os.time()
	local hero = ui.bigCard(112, PURPLE)
	noT(UI.label(hero, L(("🎟 Season %d"):format(id), ("🎟 ซีซัน %d"):format(id)), 18, C.white, F.black, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 24) }))
	noT(UI.label(hero, L(("Tier %d / %d · ends in %d days"):format(tier, Season.TIERS, math.max(0, math.floor(left / 86400))),
		("ขั้น %d / %d · เหลือ %d วัน"):format(tier, Season.TIERS, math.max(0, math.floor(left / 86400)))), 13, C.white, F.bold, { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 18) }))
	local track, set = UI.bar(hero, Color3.fromRGB(255, 220, 120), 8)
	track.Position = UDim2.fromOffset(14, 58)
	track.Size = UDim2.new(1, -28, 0, 8)
	set((s.xp % Season.XP_PER_TIER) / Season.XP_PER_TIER)
	noT(UI.label(hero, L("XP: jobs, 5 stars, missions, daily reward, Rush Hour", "XP ได้จาก: ส่งงาน, 5 ดาว, ภารกิจ, รางวัลรายวัน, ชั่วโมงเร่งด่วน"), 11, C.white, F.med,
		{ Position = UDim2.fromOffset(14, 70), Size = UDim2.new(1, -28, 0, 16) }))
	if not s.premium then
		noT(UI.button(hero, L("Get Premium", "ซื้อพรีเมียม"), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 86), Size = UDim2.fromOffset(120, 22), TextSize = 12,
			BackgroundColor3 = Color3.fromRGB(255, 200, 60), TextColor3 = C.black }, function()
			MarketplaceService:PromptProductPurchase(player, Store.SEASON_PRODUCT)
		end))
	else
		noT(UI.label(hero, L("⭐ Premium", "⭐ พรีเมียม"), 12, Color3.fromRGB(255, 220, 120), F.black, { Position = UDim2.fromOffset(14, 88), Size = UDim2.new(1, -28, 0, 18) }))
	end

	-- titles you own
	local titles = {}
	for key, c in pairs(Season.COSMETICS) do
		if c.kind == "title" and type(d.unlocks) == "table" and d.unlocks[key] then table.insert(titles, { key = key, c = c }) end
	end
	if #titles > 0 then
		ui.section(L("TITLE OVER YOUR HEAD", "ฉายาเหนือหัว"))
		local rr = ui.row("🏅", L("Your rank", "ยศของคุณ"), nil, (d.title == "" or not d.title) and "✓" or L("Use", "ใช้"), function() if ui.call("City", "title", "") then Phone.refresh() end end, { btnWidth = 54, height = 40 })
		local _ = rr
		for _, t in ipairs(titles) do
			local on = d.title == t.key
			local r2 = ui.row("✨", L(t.c.name, t.c.thai), nil, on and "✓" or L("Use", "ใช้"), function() if ui.call("City", "title", t.key) then Phone.refresh() end end, { btnWidth = 54, height = 40 })
			for _, x in ipairs(r2:GetDescendants()) do if x:IsA("TextLabel") then x:SetAttribute("NoTranslate", true) end end
		end
	end

	ui.section(L("REWARDS", "รางวัล"))
	-- show from the first unclaimed tier a little back, 50 rows is fine on a phone screen list
	for t = 1, Season.TIERS do
		local fr, pr = Season.reward(t, false), Season.reward(t, true)
		local reached = tier >= t
		local card = ui.bigCard(fr and 74 or 54)
		noT(UI.label(card, tostring(t), 18, reached and PURPLE or C.sub, F.black, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 30, 1, 0), TextXAlignment = Enum.TextXAlignment.Center }))
		local function line(y: number, label: string, r, claimedSet, trackKey: string, locked: boolean)
			noT(UI.label(card, label .. rewardText(r), 12, locked and C.sub or C.text, F.bold, { Position = UDim2.fromOffset(46, y), Size = UDim2.new(1, -140, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd }))
			if r then
				local got = claimedSet and claimedSet[tostring(t)]
				local can = reached and not got and not locked
				noT(UI.button(card, got and "✓" or (can and L("Claim", "รับ") or "🔒"), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, y), Size = UDim2.fromOffset(74, 22), TextSize = 12,
					BackgroundColor3 = got and C.green or (can and PURPLE or C.bg), TextColor3 = (got or can) and C.white or C.sub }, function()
					if can and ui.call("City", "season_claim", trackKey .. ":" .. t) then Phone.refresh() end
				end))
			end
		end
		local y = 6
		if fr then line(y, L("Free: ", "ฟรี: "), fr, s.free, "free", false); y += 26 end
		line(y, L("Premium: ", "พรีเมียม: "), pr, s.prem, "prem", not s.premium)
	end
end

function SeasonApp.start()
	Phone.addApp({ id = "season", name = "Season", icon = "🎟", color = PURPLE, badge = function()
		local d = State.data
		if not d or type(d.season) ~= "table" then return false end
		local tier = math.floor((d.season.xp or 0) / Season.XP_PER_TIER)
		for t = 1, tier do
			if Season.reward(t, false) and not (d.season.free or {})[tostring(t)] then return true end
			if d.season.premium and not (d.season.prem or {})[tostring(t)] then return true end
		end
		return false
	end }, screen)
end

return SeasonApp
