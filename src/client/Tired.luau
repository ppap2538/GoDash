-- "You are tired: go home and sleep" pop-up (owner, 2026-11-16). When the fatigue bar passes a
-- threshold a card comes up once, with one-tap navigation to a bed, a free rest spot or a coffee.
-- It never interrupts a scene, a pay slip or the phone, and it re-arms only after a real rest.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Housing = require(Shared.Config.Housing)
local UI = require(script.Parent.UI.Kit)
local Layout = require(script.Parent.UI.Core.Layout)
local UIState = require(script.Parent.UI.Core.UIState)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local GPS = require(script.Parent.GPS)
local Feedback = require(script.Parent.Feedback)

local Tired = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local TIRED, EXHAUSTED, REARM = 30, 12, 45 -- energy left (fatigue = 100 - energy)
local stage = 0 -- 0 = rested, 1 = "tired" shown, 2 = "exhausted" shown
local center
local open = false
local closeCard: (() -> ())? = nil -- closes the card that is up, if any

local function rootPos(): Vector3?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return r and r.Position or nil
end

-- Where to rest: your own house if you have one, else the nearest free bench / sala.
local function restSpot(from: Vector3): (Vector3?, string, boolean)
	local plot = State.plot
	if plot and plot.base then return plot.base.Position, L("Home", "บ้านของฉัน"), true end
	local best, bd, name
	for _, p in ipairs(State.world and State.world.pois or {}) do
		if p.kind == "hub" or p.kind == "reststop" then
			local d = Util.flatDist(p.pos, from)
			if not bd or d < bd then best, bd, name = p.pos, d, (Lang.code == "th" and p.thai and p.thai ~= "") and p.thai or p.name end
		end
	end
	return best, name or "", false
end

-- The nearest plot of land nobody owns yet, and what it costs (a home of your own has a bed).
local function landForSale(from: Vector3): (Vector3?, string)
	local best, bd, tier
	for _, p in ipairs(State.world and State.world.plots or {}) do
		if not p.owned then
			local d = Util.flatDist(p.pos, from)
			if not bd or d < bd then best, bd, tier = p.pos, d, Housing.TIERS[p.tier] end
		end
	end
	if not best then return nil, "" end
	return best, tier and (((Lang.code == "th" and tier.thai) or tier.name) .. " " .. Util.money(tier.price)) or ""
end

local function coffee(from: Vector3): (Vector3?, string)
	local best, bd, name
	for _, p in ipairs(State.world and State.world.food or {}) do
		if p.energy and p.energy.value >= 15 then
			local d = Util.flatDist(p.pos, from)
			if not bd or d < bd then best, bd, name = p.pos, d, (Lang.code == "th" and p.thai and p.thai ~= "") and p.thai or p.name end
		end
	end
	return best, name or ""
end

local function show(exhausted: boolean): boolean
	local pos = rootPos()
	if not pos or not center or open then return false end -- e.g. the character has not spawned yet: try again
	open = true
	UIState.set("modal", true)
	local card = UI.new("Frame", { Name = "Tired", BackgroundColor3 = C.card, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(340, 100), AutomaticSize = Enum.AutomaticSize.Y, Parent = center })
	UI.corner(card, 22)
	UI.stroke(card, exhausted and C.red or C.orange, 3)
	UI.pad(card, 20, 18, 20, 18)
	UI.list(card, 8, false, Enum.HorizontalAlignment.Center)
	UI.label(card, "😪", 34, C.text, F.black, { TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 40) })
	UI.label(card, exhausted and L("You're exhausted!", "เหนื่อยมากแล้ว!") or L("You're getting tired", "เริ่มเหนื่อยแล้ว"), 21, C.text, F.black,
		{ TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 28) })
	UI.label(card, exhausted and L("New orders are paused and you earn 20% less. Go and sleep.", "หยุดรับออร์เดอร์แล้ว และรายได้ลด 20% กลับไปนอนพักก่อนนะ")
		or L("Sleep or take a break before you run out of strength.", "กลับไปนอนหรือพักสักหน่อย ก่อนจะหมดแรง"), 14, C.sub, F.med,
		{ TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Size = UDim2.new(1, 0, 0, 40) })
	local sc = Instance.new("UIScale"); sc.Scale = 0.5; sc.Parent = card
	UI.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	local function close()
		if not open then return end
		open = false
		closeCard = nil
		UI.tween(sc, 0.18, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.2, function()
			card:Destroy()
			UIState.set("modal", false)
		end)
	end
	closeCard = close
	local function choice(text: string, color: Color3, fn: (() -> ())?)
		local b = UI.button(card, text, { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = color, TextSize = 16, TextColor3 = color == C.bg and C.text or C.white }, function()
			if fn then fn() end
			close()
		end)
		UI.pad(b, 10, 0, 10, 0)
		UI.fitText(b, 16, 10) -- long place names shrink instead of running off the button
	end
	local rest, restName, home = restSpot(pos)
	if rest then
		local dist = Lang.t(Util.dist(Util.flatDist(pos, rest)))
		choice((home and L("🛏 Go home and sleep", "🛏 กลับบ้านไปนอน") or (L("🪑 Rest at ", "🪑 ไปพักที่ ") .. restName)) .. " · " .. dist, C.green, function()
			GPS.setTarget(rest, restName)
			Feedback.toast(L("Follow the arrows to rest.", "ขี่ตามลูกศรไปพักได้เลย"), "good")
		end)
	end
	if not home then
		-- no home yet: offer the way to one (owner, 2026-11-16: "there must be a way to buy a house too")
		local land, what = landForSale(pos)
		if land then
			choice(L("🏠 Buy a home: ", "🏠 ซื้อบ้านของตัวเอง: ") .. what .. " · " .. Lang.t(Util.dist(Util.flatDist(pos, land))), C.purple or C.orange, function()
				GPS.setTarget(land, L("Land for sale", "ที่ดินขาย"))
				Feedback.toast(L("Follow the arrows to the plot, then press E at the sign.", "ขี่ตามลูกศรไปที่แปลง แล้วกด E ที่ป้ายขาย"), "good")
			end)
		end
	end
	local cup, cupName = coffee(pos)
	if cup then
		choice(L("☕ A drink at ", "☕ แวะดื่มที่ ") .. cupName .. " · " .. Lang.t(Util.dist(Util.flatDist(pos, cup))), C.blue, function()
			GPS.setTarget(cup, cupName)
		end)
	end
	choice(L("Later", "ไว้ทีหลัง"), C.bg, nil)
	Feedback.notify()
	return true
end

function Tired.start()
	local gui = UI.screen("GoDashTired", 60)
	center = Layout.region(Layout.stage(gui), "Center")
	task.spawn(function()
		while true do
			task.wait(1.5)
			local d = State.data
			local e = d and d.energy
			if type(e) == "number" then
				local resting = player:GetAttribute("Resting") ~= nil
				-- the advice is out of date once the player is resting or has their strength back
				if open and closeCard and (resting or e >= REARM) then closeCard() end
				if e >= REARM then
					stage = 0
				elseif not open and not resting and not State.cutscene and not UIState.get("modal") then
					if e <= EXHAUSTED and stage < 2 then
						if show(true) then stage = 2 end
					elseif e <= TIRED and stage < 1 then
						if show(false) then stage = 1 end
					end
				end
			end
		end
	end)
end

return Tired
