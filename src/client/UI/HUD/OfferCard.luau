-- Job-offer popup: bottom-centre, temporary. Shows the fare, both ends of the trip, a countdown
-- bar and Decline / Accept (Y on keyboards). It stacks with the interaction prompt in the
-- bottom-centre region, so the two never overlap.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Jobs = require(Shared.Config.Jobs)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local UIRoot = script.Parent.Parent
local UI = require(UIRoot.Kit)
local Layout = require(UIRoot.Core.Layout)
local UIState = require(UIRoot.Core.UIState)
local State = require(UIRoot.Parent.State)
local Feedback = require(UIRoot.Parent.Feedback)
local Lang = require(UIRoot.Parent.Lang)

local OfferCard = {}
local C, F, T = UI.C, UI.F, UI.T
local refs = {} :: { [string]: any }
local shownId: any = nil
local shownAt = 0

local touch = Layout.isTouch
local WIDTH = 360
local HEAD_H = 44
local BTN_H = touch and 52 or 42
local BTN_Y = 146
local HEIGHT = BTN_Y + BTN_H + 12

function OfferCard.accept()
	local o = State.job.offer
	if o then Net.send("JobRespond", o.id, true) end
end

-- Countdown: called every frame while an offer is up. Writes one property, allocates no tween.
function OfferCard.update()
	local o = State.job.offer
	if o and shownId ~= nil then
		local seconds = (o.seconds and o.seconds > 0) and o.seconds or 1
		refs.timerFill.Size = UDim2.fromScale(math.clamp(1 - (os.clock() - shownAt) / seconds, 0, 1), 1)
	end
end

-- the bonus line is built from parts on the server ("🌧 Rain bonus +25% · 🍱 Lunch rush +15%"): translate each part
local BONUS_TH = {
	["🌙 Night +10%"] = "🌙 กลางคืน +10%", ["💦 Songkran +30%"] = "💦 สงกรานต์ +30%", ["🔥 Rush Hour +50%"] = "🔥 ชั่วโมงเร่งด่วน +50%",
	["🍱 Lunch rush +15%"] = "🍱 ช่วงพักเที่ยง +15%", ["🍛 Dinner rush +15%"] = "🍛 ช่วงมื้อเย็น +15%",
}
local function bonusLine(s: string): string
	if Lang.code ~= "th" or s == "" then return s end
	local out = {}
	for seg in (s .. " · "):gmatch("(.-) · ") do
		local rain = seg:match("^🌧 Rain bonus %+(%d+)%%$")
		table.insert(out, rain and ("🌧 โบนัสฝน +" .. rain .. "%") or BONUS_TH[seg] or seg)
	end
	return table.concat(out, " · ")
end

local function refresh(job)
	local o = job and job.offer
	if o then
		local id = o.id or true
		if shownId ~= id then
			shownId = id
			shownAt = os.clock()
			Feedback.notify()
			refs.timerFill.Size = UDim2.fromScale(1, 1)
			task.defer(function() UI.pop(refs.card, 0.8) end)
		end
		local def = (o.mode == "ride" and Jobs.RIDE or Jobs.FOOD)[o.type]
		local col = def and def.color or C.green
		refs.head.BackgroundColor3 = col
		refs.headFill.BackgroundColor3 = col
		refs.title.Text = o.icon .. "  " .. Lang.t(o.name)
		refs.pay.Text = Util.money(o.pay)
		refs.from.Text = (o.mode == "ride" and "🧍 Pick up: " or "🍱 From: ") .. Lang.name(o.pickup)
		refs.to.Text = "📍 To: " .. Lang.name(o.dropoff)
		if o.regular then
			-- (2026-11-19) a regular customer (Config/Regulars): who, and how many times you've been
			local n = (tonumber(o.regularN) or 0) + 1
			refs.to.Text = "⭐ " .. Lang.pick(("Regular: %s · visit %d"):format(Lang.t(o.customer or ""), n), ("ลูกค้าประจำ: %s · ครั้งที่ %d"):format(Lang.t(o.customer or ""), n))
		end
		refs.info.Text = ("%s trip · %s to pick-up · %s · +%d EXP"):format(Util.dist(o.dist), Util.dist(o.toPickup), o.item, o.exp)
		refs.bonus.Text = bonusLine(o.bonus or "")
	else
		shownId = nil
	end
	UIState.set("offer", o ~= nil)
end

-- region = the BottomCenter region.
function OfferCard.build(region: Frame, order: number)
	local card = UI.panel(region, { Name = "Offer", LayoutOrder = order, Size = UDim2.fromOffset(WIDTH, HEIGHT), BackgroundTransparency = 0.08 })
	refs.card = card
	local head = UI.new("Frame", { BackgroundColor3 = C.green, Size = UDim2.new(1, 0, 0, HEAD_H), Parent = card })
	UI.corner(head, UI.R.lg)
	refs.head = head
	refs.headFill = UI.new("Frame", { BackgroundColor3 = C.green, Position = UDim2.new(0, 0, 1, -UI.R.lg), Size = UDim2.new(1, 0, 0, UI.R.lg), Parent = head })
	refs.title = UI.label(head, "", T.lg, C.white, F.black, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -140, 1, 0), ZIndex = 2 })
	UI.fitText(refs.title, T.lg, 11)
	refs.pay = UI.label(head, "", T.xl, C.white, F.black, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0, 108, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 2 })
	UI.fitText(refs.pay, T.xl, 12)
	refs.from = UI.label(card, "", T.md, C.white, F.bold, { Position = UDim2.fromOffset(14, 52), Size = UDim2.new(1, -28, 0, 18) })
	refs.to = UI.label(card, "", T.md, C.white, F.bold, { Position = UDim2.fromOffset(14, 72), Size = UDim2.new(1, -28, 0, 18) })
	refs.info = UI.label(card, "", T.sm, C.textDim, F.med, { Position = UDim2.fromOffset(14, 94), Size = UDim2.new(1, -28, 0, 16) })
	UI.fitText(refs.info, T.sm, 9)
	refs.bonus = UI.label(card, "", T.sm, C.yellow, F.bold, { Position = UDim2.fromOffset(14, 112), Size = UDim2.new(1, -28, 0, 16) })
	refs.bonus:SetAttribute("NoTranslate", true) -- bonusLine() does it part by part
	UI.fitText(refs.bonus, T.sm, 9)
	local timerTrack, _, timerFill = UI.glassBar(card, C.green, 5)
	timerTrack.Position = UDim2.fromOffset(14, 134)
	timerTrack.Size = UDim2.new(1, -28, 0, 5)
	timerFill.Size = UDim2.fromScale(1, 1)
	refs.timerFill = timerFill
	UI.button(card, "Decline", { Position = UDim2.fromOffset(14, BTN_Y), Size = UDim2.new(0.38, -18, 0, BTN_H), BackgroundColor3 = C.chip, TextColor3 = C.white }, function()
		local o = State.job.offer
		if o then Net.send("JobRespond", o.id, false) end
	end)
	UI.button(card, touch and "ACCEPT" or "ACCEPT  [Y]", { Position = UDim2.new(0.38, 4, 0, BTN_Y), Size = UDim2.new(0.62, -18, 0, BTN_H), TextSize = T.lg }, OfferCard.accept)

	UIState.bind("offer", card)
	State.onJob(refresh)
	refresh(State.job)
end

return OfferCard
