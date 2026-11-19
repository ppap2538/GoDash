-- Phone app "Shop" (2026-11-17 Tier-A plan): game passes, cash packs, the premium season pass and
-- codes. Purchases go through Roblox's own prompt; the server (StoreService) grants them.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Store = require(Shared.Config.Store)
local Net = require(Shared.Net)
local UI = require(script.Parent.UI.Kit)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)
local Phone = require(script.Parent.Phone)

local ShopApp = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local ROBUX = Color3.fromRGB(0, 162, 255)
local prices = {} -- [id] = robux
local codeDraft = ""

local function noT(l: Instance)
	l:SetAttribute("NoTranslate", true)
	return l
end

local function price(id: number, kind: Enum.InfoType): string
	if prices[id] then return "R$ " .. prices[id] end
	prices[id] = "…"
	task.spawn(function()
		local ok, info = pcall(function() return MarketplaceService:GetProductInfo(id, kind) end)
		prices[id] = ok and info and info.PriceInRobux or "?"
		if Phone.current() == "store" then Phone.refresh() end
	end)
	return "R$ …"
end

local function screen()
	local ui = Phone.ui
	local content = ui.content()
	local hero = ui.bigCard(78, ROBUX)
	noT(UI.label(hero, L("🛒 GoDash Shop", "🛒 ร้านค้า GoDash"), 18, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) }))
	noT(UI.label(hero, L("Thank you for supporting the game! Purchases are added at once.", "ขอบคุณที่สนับสนุนเกม! ซื้อแล้วได้ทันที"), 12, C.white, F.med,
		{ Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 34), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }))

	ui.section(L("PASSES (KEEP FOREVER)", "พาส (ได้ถาวร)"))
	for _, key in ipairs({ "vip", "neon" }) do
		local p = Store.PASSES[key]
		local owned = player:GetAttribute(key == "vip" and "VIP" or "NeonPro") == true
		local r = ui.row(p.icon, Lang.code == "th" and p.thai or p.name, Lang.code == "th" and p.descTh or p.desc,
			owned and L("Owned", "มีแล้ว") or price(p.id, Enum.InfoType.GamePass), function()
				if not owned then MarketplaceService:PromptGamePassPurchase(player, p.id) end
			end, { btnWidth = 78, height = 70, btnColor = owned and C.green or ROBUX, disabled = owned })
		for _, x in ipairs(r:GetDescendants()) do if x:IsA("TextLabel") then x:SetAttribute("NoTranslate", true) end end
	end

	ui.section(L("GAME MONEY", "เงินในเกม"))
	for _, id in ipairs(Store.CASH_ORDER) do
		local p = Store.PRODUCTS[id]
		local r = ui.row(p.icon, p.name .. (p.best and L("  · best value", "  · คุ้มสุด") or ""), nil, price(id, Enum.InfoType.Product), function()
			MarketplaceService:PromptProductPurchase(player, id)
		end, { btnWidth = 78, height = 48, btnColor = ROBUX })
		for _, x in ipairs(r:GetDescendants()) do if x:IsA("TextLabel") then x:SetAttribute("NoTranslate", true) end end
	end

	ui.section(L("SEASON", "ซีซัน"))
	local sp = Store.PRODUCTS[Store.SEASON_PRODUCT]
	local r = ui.row(sp.icon, L(sp.name, sp.thai), L("Premium rewards for this season: open the Season app", "รางวัลพรีเมียมของซีซันนี้ ดูในแอปซีซัน"),
		price(Store.SEASON_PRODUCT, Enum.InfoType.Product), function()
			MarketplaceService:PromptProductPurchase(player, Store.SEASON_PRODUCT)
		end, { btnWidth = 78, height = 60, btnColor = ROBUX })
	for _, x in ipairs(r:GetDescendants()) do if x:IsA("TextLabel") then x:SetAttribute("NoTranslate", true) end end

	-- codes
	ui.section(L("REDEEM A CODE", "ใส่โค้ด"))
	local card = ui.bigCard(84)
	local box = Instance.new("TextBox")
	box.PlaceholderText = L("Code from our posts", "โค้ดจากโพสต์ของเกม")
	box.Text = codeDraft
	box.ClearTextOnFocus = false
	box.Font = F.bold
	box.TextSize = 16
	box.TextColor3 = C.text
	box.BackgroundColor3 = C.bg
	box.Position = UDim2.fromOffset(12, 12)
	box.Size = UDim2.new(1, -112, 0, 36)
	box.Parent = card
	box:SetAttribute("NoTranslate", true)
	UI.corner(box, 10)
	box:GetPropertyChangedSignal("Text"):Connect(function() codeDraft = box.Text end)
	noT(UI.button(card, L("Redeem", "รับรางวัล"), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(88, 36), TextSize = 14 }, function()
		if codeDraft == "" then return end
		if ui.call("City", "code", codeDraft) then
			codeDraft = ""
			Phone.refresh()
		end
	end))
	noT(UI.label(card, L("New codes come with updates and in our TikTok / Facebook posts. A creator's code works here too.", "โค้ดใหม่มากับอัปเดตและโพสต์ TikTok / Facebook ของเกม · โค้ดครีเอเตอร์ก็ใส่ช่องนี้ได้"), 11, C.sub, F.med,
		{ Position = UDim2.fromOffset(12, 54), Size = UDim2.new(1, -24, 0, 24), TextWrapped = true }))
end

function ShopApp.start()
	-- id "store": "shop" is the screen of the shops in town (Phone screens.shop)
	Phone.addApp({ id = "store", name = "Shop", icon = "🛒", color = ROBUX }, screen)
	-- passes bought: the server sets the attribute; redraw the shop
	for _, a in ipairs({ "VIP", "NeonPro" }) do
		player:GetAttributeChangedSignal(a):Connect(function()
			if player:GetAttribute(a) then Feedback.good() end
			if Phone.current() == "store" then Phone.refresh() end
		end)
	end
	local _ = Net
end

return ShopApp
