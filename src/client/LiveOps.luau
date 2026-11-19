-- Live game bits (2026-11-17 Tier-A plan):
--   * Rush Hour chip at the top of the screen while Workspace "RushUntil" is in the future
--   * "What's new" card, once per Config/News.VERSION (after the daily reward card)
--   * Neon Pro rainbow underglow: every "Style_Glow" part marked Rainbow cycles its colour and pulses
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local News = require(Shared.Config.News)
local Net = require(Shared.Net)
local UI = require(script.Parent.UI.Kit)
local Layout = require(script.Parent.UI.Core.Layout)
local Layers = require(script.Parent.UI.Core.Layers)
local UIState = require(script.Parent.UI.Core.UIState)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)

local LiveOps = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer

local function noT(l: Instance)
	l:SetAttribute("NoTranslate", true)
	return l
end

---------------------------------------------------------------------------------------------------
-- Rush Hour chip
---------------------------------------------------------------------------------------------------
local function rushChip()
	local gui = UI.screen("GoDashRush", Layers.HUD + 2)
	local chip = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(230, 70, 30), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 114),
		Size = UDim2.fromOffset(380, 34), Visible = false, Parent = gui })
	UI.corner(chip, 17)
	UI.stroke(chip, Color3.fromRGB(255, 210, 120), 2)
	local label = noT(UI.label(chip, "", 15, C.white, F.black, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center }))
	task.spawn(function()
		while true do
			local untilT = Workspace:GetAttribute("RushUntil") or 0
			local left = untilT - os.time()
			if left > 0 and not State.cutscene then
				chip.Visible = true
				local mine = player:GetAttribute("RushJobs") or 0
				label.Text = L(("🔥 RUSH HOUR · pay +50%% · %d:%02d · you: %d jobs"):format(left // 60, left % 60, mine),
					("🔥 ชั่วโมงเร่งด่วน · ค่าส่ง +50%% · %d:%02d · คุณ %d งาน"):format(left // 60, left % 60, mine))
			else
				chip.Visible = false
			end
			task.wait(1)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- What's new
---------------------------------------------------------------------------------------------------
local function newsCard()
	local gui = UI.screen("GoDashNews", Layers.Modal + 3)
	local dim = UI.scrim(gui, 0.5)
	local center = Layout.region(Layout.stage(gui), "Center")
	local h = 120 + #News.LINES * 46
	local card = UI.new("Frame", { BackgroundColor3 = C.card, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, h), Parent = center })
	UI.corner(card, 24)
	UI.stroke(card, C.green, 3)
	UIState.set("modal", true)
	noT(UI.label(card, L("✨ What's new in GoDash", "✨ มีอะไรใหม่ใน GoDash"), 22, C.text, F.black, { Position = UDim2.fromOffset(20, 16), Size = UDim2.new(1, -40, 0, 30) }))
	for i, line in ipairs(News.LINES) do
		local row = UI.new("Frame", { BackgroundColor3 = C.bg, Position = UDim2.fromOffset(16, 52 + (i - 1) * 46), Size = UDim2.new(1, -32, 0, 40), Parent = card })
		UI.corner(row, 12)
		noT(UI.label(row, line.icon, 20, C.text, F.med, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0, 30, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None }))
		noT(UI.label(row, L(line.en, line.th), 13, C.text, F.bold, { Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -52, 1, 0), TextWrapped = true }))
	end
	local function close()
		UI.tween(dim, 0.2, { BackgroundTransparency = 1 })
		task.delay(0.2, function()
			gui:Destroy()
			UIState.set("modal", false)
		end)
		task.spawn(function() Net.call("City", "news_seen", News.VERSION) end)
	end
	noT(UI.button(card, L("Let's ride!", "ไปขี่กันเลย!"), { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -40, 0, 44), TextSize = 17 }, close))
end

---------------------------------------------------------------------------------------------------
-- rainbow underglow (Neon Pro)
---------------------------------------------------------------------------------------------------
local function rainbow()
	local strips = {} :: { BasePart }
	task.spawn(function()
		while true do
			local list = {}
			local folder = Workspace:FindFirstChild("Vehicles")
			if folder then
				for _, d in ipairs(folder:GetDescendants()) do
					if d.Name == "Style_Glow" and d:IsA("BasePart") and d:GetAttribute("Rainbow") then table.insert(list, d) end
				end
			end
			strips = list
			task.wait(2)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if #strips == 0 then return end
		local t = os.clock()
		local c = Color3.fromHSV((t * 0.18) % 1, 0.85, 1)
		local pulse = 2.2 + 1.6 * math.sin(t * 5)
		for _, p in ipairs(strips) do
			if p.Parent then
				p.Color = c
				local l = p:FindFirstChildOfClass("SurfaceLight")
				if l then l.Color = c; l.Brightness = pulse end
			end
		end
	end)
end

function LiveOps.start()
	rushChip()
	rainbow()
	-- the news card waits for the welcome / daily cards to be closed
	task.spawn(function()
		task.wait(9)
		for _ = 1, 240 do
			local d = State.data
			if d and d.settings and d.settings.langChosen and not UIState.get("modal") and not State.cutscene then
				if d.seenNews ~= News.VERSION then
					local jobs = (d.stats.deliveries or 0) + (d.stats.rides or 0)
					if jobs == 0 then
						-- a brand-new rider has just had the welcome card: no "what's new" on top of it
						task.spawn(function() Net.call("City", "news_seen", News.VERSION) end)
					else
						newsCard()
					end
				end
				return
			end
			task.wait(1)
		end
	end)
end

return LiveOps
