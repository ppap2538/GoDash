-- Current-order card, top-left under the status widget: what the order is, what it pays, which
-- leg you are on, and cancel (second tap within 3 s). Where to go and what to press is the Guide
-- card's job (top centre), so nothing here repeats it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local UIRoot = script.Parent.Parent
local UI = require(UIRoot.Kit)
local Layout = require(UIRoot.Core.Layout)
local UIState = require(UIRoot.Core.UIState)
local State = require(UIRoot.Parent.State)
local Feedback = require(UIRoot.Parent.Feedback)
local Lang = require(UIRoot.Parent.Lang)

local JobCard = {}
local C, F, T = UI.C, UI.F, UI.T
local player = Players.LocalPlayer
local refs = {} :: { [string]: any }
local hudRef: any = nil
local cancelArmed: number? = nil

JobCard.actionAvailable = false -- true while the player is within range of the job target

local touch = Layout.isTouch
local CANCEL = touch and 44 or 28
local H = 8 + math.max(40, CANCEL) + 8

-- Called a few times a second by the HUD. Only works out whether the player is close enough to
-- pick up / deliver (for the E / G keys); the Guide card at the top shows distance, time and the
-- button, so this card no longer repeats them.
function JobCard.update()
	local j = State.job.job
	if not j then
		JobCard.actionAvailable = false
		return
	end
	local target = j.stage == "pickup" and j.pickup.pos or j.dropoff.pos
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	JobCard.actionAvailable = root ~= nil and Util.flatDist(root.Position, target) <= Game.INTERACT_RANGE
end

function JobCard.act()
	Net.send("JobAction")
end

-- The order itself: what, how much, from where to where. Cancel lives here.
local function refresh(job)
	local j = job and job.job
	if j then
		refs.icon.Text = j.icon
		refs.title.Text = Lang.t(j.item) .. "  ·  " .. Util.money(j.pay)
		local from, to = Lang.name(j.pickup), Lang.name(j.dropoff)
		local stage = j.stage == "pickup" and Lang.pick("① collect at ", "① รับที่ ") .. from or Lang.pick("② deliver to ", "② ส่งที่ ") .. to
		refs.sub.Text = Lang.t(j.name) .. " · " .. stage
	else
		cancelArmed = nil
	end
	UIState.set("job", j ~= nil)
	JobCard.update()
end

-- region = the TopLeft region; hud = the HUD facade.
function JobCard.build(region: Frame, order: number, hud: any)
	hudRef = hud
	local card = UI.panel(region, { Name = "Job", LayoutOrder = order, ClipsDescendants = true })
	refs.card = card
	local textW = -(42 + 8 + CANCEL + 6)
	refs.icon = UI.label(card, "🛵", 24, C.white, F.med, { Position = UDim2.fromOffset(6, 8), Size = UDim2.fromOffset(32, 40), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	refs.title = UI.label(card, "", T.md, C.white, F.bold, { Position = UDim2.fromOffset(42, 8), Size = UDim2.new(1, textW, 0, 20) })
	UI.fitText(refs.title, T.md, 10)
	refs.sub = UI.label(card, "", T.sm, C.textDim, F.med, { Position = UDim2.fromOffset(42, 30), Size = UDim2.new(1, textW, 0, 18) })
	UI.fitText(refs.sub, T.sm, 8)
	for _, l in ipairs({ refs.title, refs.sub }) do l:SetAttribute("NoTranslate", true) end
	UI.button(card, "X", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(CANCEL, CANCEL), BackgroundColor3 = C.chip, TextSize = 13 }, function()
		if cancelArmed and os.clock() - cancelArmed < 3 then
			Net.send("JobCancel")
			cancelArmed = nil
		else
			cancelArmed = os.clock()
			Feedback.toast("Tap X again to cancel this job (lowers your rating)")
		end
	end)
	local function size() card.Size = UDim2.fromOffset(Layout.m.colW, H) end
	size()
	Layout.onChange(size)
	UIState.bind("job", card, function() UI.pop(card, 0.94) end)
	State.onJob(refresh)
	Lang.onChange(function() refresh(State.job) end)
	refresh(State.job)
end

return JobCard
