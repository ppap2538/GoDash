-- Top-left status widget: level badge, money, EXP bar, energy / hunger / happiness bars, with
-- the buff and resting lines stacked underneath. Compact screens get a shorter panel (no EXP
-- text, vitals side by side).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Util = require(Shared.Util)
local UIRoot = script.Parent.Parent
local UI = require(UIRoot.Kit)
local Layout = require(UIRoot.Core.Layout)
local UIState = require(UIRoot.Core.UIState)
local State = require(UIRoot.Parent.State)

local Status = {}
local C, F, T = UI.C, UI.F, UI.T
local player = Players.LocalPlayer
local refs = {} :: { [string]: any }

local NAME_W, VALUE_W = 70, 26

-- One vital: icon, name ("Food"), bar, number. Turns red when low. inverse = the bar shows what is
-- used up (fatigue = 100 - energy): it fills as it gets worse and turns red when high.
local function vital(parent: Instance, icon: string, name: string, color: Color3, inverse: boolean?)
	local row = UI.new("Frame", { BackgroundTransparency = 1, Parent = parent })
	UI.label(row, icon, 11, C.white, F.med, { Size = UDim2.new(0, 16, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	local nameL = UI.label(row, name, 11, C.textDim, F.bold, { Position = UDim2.fromOffset(18, 0), Size = UDim2.new(0, NAME_W - 20, 1, 0) })
	UI.fitText(nameL, 11, 8)
	local track, set = UI.glassBar(row, color, 6)
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, NAME_W, 0.5, 0)
	track.Size = UDim2.new(1, -(NAME_W + VALUE_W + 4), 0, 6)
	local value = UI.label(row, "", 11, C.white, F.black, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, VALUE_W, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.None })
	local function setValue(v: number)
		local low = v < 25
		if inverse then v = 100 - v end
		set(v / 100)
		value.Text = tostring(math.floor(v + 0.5))
		value.TextColor3 = low and C.red or C.white
		nameL.TextColor3 = low and C.red or C.textDim
	end
	return row, setValue
end

local function relayout()
	local m = Layout.m
	local compact = Layout.breakpoint == "compact"
	local w = m.colW
	if compact then
		refs.panel.Size = UDim2.fromOffset(w, 100)
		refs.badge.Position = UDim2.fromOffset(10, 8)
		refs.badge.Size = UDim2.fromOffset(36, 36)
		refs.level.TextSize = 16
		refs.money.Position = UDim2.fromOffset(56, 6)
		refs.money.Size = UDim2.new(1, -66, 0, 22)
		refs.expTrack.Position = UDim2.fromOffset(56, 33)
		refs.expTrack.Size = UDim2.new(1, -66, 0, 5)
		refs.exp.Visible = false
		refs.vitals.Position = UDim2.fromOffset(10, 52)
		refs.vitals.Size = UDim2.new(1, -20, 0, 42)
		for i, row in ipairs(refs.rows) do
			row.Position = UDim2.fromOffset(0, (i - 1) * 14)
			row.Size = UDim2.new(1, 0, 0, 13)
		end
	else
		refs.panel.Size = UDim2.fromOffset(w, 112)
		refs.badge.Position = UDim2.fromOffset(12, 12)
		refs.badge.Size = UDim2.fromOffset(44, 44)
		refs.level.TextSize = 19
		refs.money.Position = UDim2.fromOffset(66, 10)
		refs.money.Size = UDim2.new(1, -78, 0, 24)
		refs.expTrack.Position = UDim2.fromOffset(66, 38)
		refs.expTrack.Size = UDim2.new(1, -78, 0, 6)
		refs.exp.Visible = true
		refs.vitals.Position = UDim2.fromOffset(12, 66)
		refs.vitals.Size = UDim2.new(1, -24, 0, 40)
		for i, row in ipairs(refs.rows) do
			row.Position = UDim2.fromOffset(0, (i - 1) * 14)
			row.Size = UDim2.new(1, 0, 0, 12)
		end
	end
end

local function setLine(label: TextLabel, text: string)
	label.Text = text
	label.Visible = text ~= ""
end

local function refresh(keys)
	local d = State.data
	if not d then return end
	if keys.money and refs.lastMoney and d.money ~= refs.lastMoney then
		local up = d.money > refs.lastMoney
		refs.money.TextColor3 = up and C.green or C.red
		task.delay(0.6, function() refs.money.TextColor3 = C.white end)
	end
	refs.lastMoney = d.money
	refs.money.Text = Util.money(d.money)
	refs.level.Text = tostring(d.level)
	local need = Game.expForLevel(d.level)
	refs.setExp(need > 0 and d.exp / need or 0)
	refs.exp.Text = ("%d / %d EXP"):format(d.exp, need)
	refs.setEnergy(d.energy)
	refs.setHunger(d.hunger)
	refs.setHappy(d.happiness)
	local buffs = {}
	local now = os.time()
	if d.buffs and d.buffs.spicy and d.buffs.spicy > now then table.insert(buffs, "🌶 Tips +12%") end
	if d.buffs and d.buffs.sugar and d.buffs.sugar > now then table.insert(buffs, "🥤 Energy saver") end
	setLine(refs.buffs, table.concat(buffs, "   "))
end

local function refreshResting()
	local rest = player:GetAttribute("Resting")
	setLine(refs.resting, rest and ("😴 " .. tostring(rest) .. "…") or "")
end

-- region = the TopLeft region.
function Status.build(region: Frame)
	local panel = UI.panel(region, { Name = "Status", LayoutOrder = 1 })
	refs.panel = panel
	local badge = UI.new("Frame", { BackgroundColor3 = C.green, Parent = panel })
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	refs.badge = badge
	UI.label(badge, "LV", 9, C.white, F.bold, { Position = UDim2.fromScale(0, 0.12), Size = UDim2.fromScale(1, 0.26), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	refs.level = UI.label(badge, "1", 19, C.white, F.black, { Position = UDim2.fromScale(0, 0.36), Size = UDim2.fromScale(1, 0.52), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	refs.money = UI.label(panel, "฿0", T.xl, C.white, F.black, {})
	UI.fitText(refs.money, T.xl, 12)
	local expTrack, setExp = UI.glassBar(panel, C.yellow, 6)
	refs.expTrack = expTrack
	refs.setExp = setExp
	refs.exp = UI.label(panel, "0 / 100 EXP", T.xs, C.textDim, F.med, { Position = UDim2.fromOffset(66, 47), Size = UDim2.new(1, -78, 0, 12) })
	local vitals = UI.new("Frame", { BackgroundTransparency = 1, Parent = panel })
	refs.vitals = vitals
	local r1, setEnergy = vital(vitals, "😪", "Fatigue", C.orange, true)
	local r2, setHunger = vital(vitals, "🍜", "Food", C.orange)
	local r3, setHappy = vital(vitals, "😊", "Happy", C.pink)
	refs.rows = { r1, r2, r3 }
	refs.setEnergy, refs.setHunger, refs.setHappy = setEnergy, setHunger, setHappy

	-- lines under the panel: only take room while they have something to say
	refs.buffs = UI.label(region, "", T.sm, C.white, F.bold, { Name = "Buffs", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 16), TextStrokeTransparency = 0.5, Visible = false })
	UI.fitText(refs.buffs, T.sm, 9)
	refs.resting = UI.label(region, "", T.md, C.yellow, F.bold, { Name = "Resting", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 18), TextStrokeTransparency = 0.5, Visible = false })

	relayout()
	Layout.onChange(relayout)
	UIState.bind("status", panel)
	State.onData(refresh)
	if State.data then refresh({}) end
	player:GetAttributeChangedSignal("Resting"):Connect(refreshResting)
	refreshResting()
end

return Status
