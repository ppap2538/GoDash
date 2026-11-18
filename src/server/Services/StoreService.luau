-- Robux purchases, codes, the group bonus, Roblox badges and the name tag over every rider's head
-- (2026-11-17 Tier-A plan).
--   * game passes (Config/Store.PASSES): ownership asked from Roblox on every join, remembered in
--     d.passes, set as player attributes "VIP" / "NeonPro" (VehicleService and the Styling app read them)
--   * developer products: ProcessReceipt grants each purchase once (d.receipts) and saves the
--     profile before telling Roblox it is granted
--   * codes (Config/Store.CODES), one use per rider
--   * name tag: rank or chosen title, display name, ⭐ for VIPs (hidden from its own player)
--   * badges: Store.BADGES ids; 0 = not created yet (the Open Cloud key can't create badges)
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Store = require(Shared.Config.Store)
local Season = require(Shared.Config.Season)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Inventory = require(script.Parent.InventoryService)
local City = require(script.Parent.CityRemote)
local Metrics = require(script.Parent.MetricsService)

local Service = {}
local seasonHook: ((Player, string, any) -> ())? = nil -- SeasonService: grant premium / xp

-- Roblox badge ids (made by the owner on the Creator Dashboard 2026-11-17 with the icons in
-- assets/models/badge_*.png; the Assistant key has no badge-creation scope). 0 = switched off.
Store.BADGES = Store.BADGES or {
	first = 4348908449726051, -- ส่งงานแรก · First Delivery
	ten = 3982518553922882, -- ไรเดอร์ฝึกหัด · 10 Jobs
	hundred = 3766382490414808, -- ไรเดอร์มือโปร · 100 Jobs
	licence = 4034881301631287, -- สอบใบขับขี่ผ่าน · Licensed
	style = 1556449215042011, -- แต่งรถซิ่ง · Styled
}

local function toast(player: Player, en: string, th: string, good: boolean?)
	Net.fire(player, "Notify", "toast", { text = en, th = th, good = good ~= false, bad = good == false })
end

function Service.onSeason(fn) seasonHook = fn end

function Service.isVip(player: Player): boolean return player:GetAttribute("VIP") == true end

-- award a Roblox badge once (when its id is set)
function Service.badge(player: Player, key: string)
	local id = Store.BADGES[key]
	local d = Data.get(player)
	if not d or not id or id == 0 then return end
	d.badges = type(d.badges) == "table" and d.badges or {}
	if d.badges[key] then return end
	task.spawn(function()
		local ok, res = pcall(function() return BadgeService:AwardBadge(player.UserId, id) end)
		if ok and res then
			d.badges[key] = true
			Data.touch(player, "badges")
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- name tag
---------------------------------------------------------------------------------------------------
local function titleOf(player: Player, d): (string, string, Color3)
	local jobs = (d.stats.deliveries or 0) + (d.stats.rides or 0)
	local _, rank = Store.rankFor(jobs)
	local key = d.title
	if type(key) == "string" and key ~= "" and type(d.unlocks) == "table" and d.unlocks[key] and Season.COSMETICS[key] then
		local c = Season.COSMETICS[key]
		return c.name, c.thai, Color3.fromRGB(200, 150, 255)
	end
	return rank.name, rank.thai, rank.color
end

function Service.refreshTag(player: Player)
	local d = Data.get(player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not d or not head then return end
	local en, th, color = titleOf(player, d)
	local bb = head:FindFirstChild("GoDashTag") :: BillboardGui?
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "GoDashTag"
		bb.Size = UDim2.fromOffset(220, 46)
		bb.StudsOffset = Vector3.new(0, 2.6, 0)
		bb.MaxDistance = 70
		bb.LightInfluence = 0
		bb.PlayerToHideFrom = player
		local t = Instance.new("TextLabel")
		t.Name = "Title"
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, 0, 20)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextStrokeTransparency = 0.4
		t.Parent = bb
		local n = Instance.new("TextLabel")
		n.Name = "Who"
		n.BackgroundTransparency = 1
		n.Position = UDim2.fromOffset(0, 20)
		n.Size = UDim2.new(1, 0, 0, 24)
		n.Font = Enum.Font.GothamBlack
		n.TextScaled = true
		n.TextColor3 = Color3.new(1, 1, 1)
		n.TextStrokeTransparency = 0.3
		n.Parent = bb
		bb.Parent = head
	end
	local vip = player:GetAttribute("VIP") == true
	local title = bb:FindFirstChild("Title") :: TextLabel
	title.Text = th .. " · " .. en
	title.TextColor3 = color
	local who = bb:FindFirstChild("Who") :: TextLabel
	who.Text = (vip and "⭐ " or "") .. player.DisplayName .. (vip and " ⭐" or "")
	who.TextColor3 = vip and Color3.fromRGB(255, 214, 90) or Color3.new(1, 1, 1)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
end

---------------------------------------------------------------------------------------------------
-- passes
---------------------------------------------------------------------------------------------------
local function applyPasses(player: Player, d)
	player:SetAttribute("VIP", d.passes.vip == true)
	player:SetAttribute("NeonPro", d.passes.neon == true)
	Service.refreshTag(player)
end

local function checkPasses(player: Player, d)
	d.passes = type(d.passes) == "table" and d.passes or { vip = false, neon = false }
	for key, p in pairs(Store.PASSES) do
		local ok, owns = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, p.id) end)
		if ok then d.passes[key] = owns == true end
	end
	Data.touch(player, "passes")
	applyPasses(player, d)
end

---------------------------------------------------------------------------------------------------
-- receipts
---------------------------------------------------------------------------------------------------
local function grant(player: Player, d, product): boolean
	if product.kind == "cash" then
		Economy.add(player, product.amount, "robux:cash")
		toast(player, ("💰 +฿%s added. Thank you!"):format(tostring(product.amount)), ("💰 ได้รับเงิน ฿%s แล้ว ขอบคุณที่สนับสนุน!"):format(tostring(product.amount)))
		return true
	elseif product.kind == "season" then
		if seasonHook then seasonHook(player, "premium", nil) end
		toast(player, "🎟 Premium Season Pass unlocked!", "🎟 ปลดล็อก Season Pass พรีเมียมแล้ว!")
		return true
	end
	return false
end

local function processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local d = Data.get(player)
	if not d then return Enum.ProductPurchaseDecision.NotProcessedYet end
	d.receipts = type(d.receipts) == "table" and d.receipts or {}
	local pid = tostring(info.PurchaseId)
	if table.find(d.receipts, pid) then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local product = Store.PRODUCTS[info.ProductId]
	if not product then
		warn("[Store] unknown product " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(grant, player, d, product)
	if not ok or not granted then
		warn("[Store] grant failed: " .. tostring(granted))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(d.receipts, pid)
	while #d.receipts > 100 do table.remove(d.receipts, 1) end
	Data.touch(player, "receipts")
	-- save now: Roblox is only told "granted" once the purchase is on disk
	if not Data.save(player) then return Enum.ProductPurchaseDecision.NotProcessedYet end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------------------------------------------
-- codes
---------------------------------------------------------------------------------------------------
local function dateNumber(s: string): number
	local y, m, dd = s:match("^(%d+)%-(%d+)%-(%d+)$")
	return tonumber(y or 0) * 10000 + tonumber(m or 0) * 100 + tonumber(dd or 0)
end

-- Owner-only codes (server side only, so they never reach a client): the owner types them in the same
-- code box to set up a clip, e.g. open Loy Krathong early on this server for a teaser. Anyone else
-- gets "That code doesn't exist", the same as a wrong code.
local OWNER_ID = 11934070066
local ownerCodes = {} :: { [string]: (Player) -> (boolean, string) }
function Service.isOwner(player: Player): boolean
	return player.UserId == OWNER_ID or (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId and game.CreatorId > 0)
end
function Service.ownerCode(code: string, fn: (Player) -> (boolean, string))
	ownerCodes[code:upper()] = fn
end

local function redeem(player: Player, raw: string?)
	local d = Data.get(player)
	if not d or type(raw) ~= "string" then return false, "Bad request" end
	local code = raw:gsub("%s", ""):upper()
	if ownerCodes[code] and Service.isOwner(player) then
		return ownerCodes[code](player)
	end
	local def = Store.CODES[code]
	if not def then return false, "That code doesn't exist" end
	local today = tonumber(os.date("!%Y%m%d", os.time() + 7 * 3600))
	if def.ends and today > dateNumber(def.ends) then return false, "That code has expired" end
	d.codes = type(d.codes) == "table" and d.codes or {}
	if d.codes[code] then return false, "You already used that code" end
	d.codes[code] = os.time()
	Data.touch(player, "codes")
	if def.money then Economy.add(player, def.money, "code:" .. code) end
	if def.item and Items.ById[def.item] then Inventory.add(player, def.item, def.qty or 1) end
	if def.seasonXp and seasonHook then seasonHook(player, "xp", def.seasonXp) end
	Metrics.event(player, "Code " .. code)
	Net.fire(player, "Reward", { title = "Code " .. code, money = def.money, item = def.item and Items.ById[def.item] and Items.ById[def.item].name, qty = def.qty })
	return true, "Code redeemed!"
end

function Service.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then return end
		local d = Data.get(player)
		if not d then return end
		for key, p in pairs(Store.PASSES) do
			if p.id == passId then
				d.passes[key] = true
				Data.touch(player, "passes")
				applyPasses(player, d)
				toast(player, "🎉 " .. p.name .. " is yours! Thank you", "🎉 ได้รับ " .. p.thai .. " แล้ว ขอบคุณที่สนับสนุน!")
			end
		end
	end)
	Data.onLoaded(function(player, d)
		applyPasses(player, d) -- the remembered state at once, then ask Roblox
		task.spawn(checkPasses, player, d)
		if Store.GROUP_ID > 0 then
			task.spawn(function()
				local ok, inGroup = pcall(function() return player:IsInGroup(Store.GROUP_ID) end)
				player:SetAttribute("InGroup", ok and inGroup == true)
			end)
		end
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("Head", 10)
			task.wait(0.5)
			Service.refreshTag(player)
		end)
		if player.Character then task.delay(1, Service.refreshTag, player) end
	end)
	City.register("code", redeem)
	City.register("news_seen", function(player, version)
		local d = Data.get(player)
		if not d or type(version) ~= "string" or #version > 20 then return false, "" end
		d.seenNews = version
		Data.touch(player, "seenNews")
		return true, ""
	end)
	City.register("title", function(player, key)
		local d = Data.get(player)
		if not d then return false, "Not ready" end
		key = key or ""
		if key ~= "" and not (type(d.unlocks) == "table" and d.unlocks[key] and Season.COSMETICS[key] and Season.COSMETICS[key].kind == "title") then
			return false, "You haven't unlocked that title"
		end
		d.title = key
		Data.touch(player, "title")
		Service.refreshTag(player)
		return true, "Title changed"
	end)
end

return Service
