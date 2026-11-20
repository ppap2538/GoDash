-- Cute UI skin for the screens that do not use the UI kit (2026-11-20, owner: "UX/UI ขอน่ารักๆ สดใส เน้นเล่นง่าย"
-- ... "ทำต่อให้จบเลย"). UI/Core/Theme already restyles everything built with UI/Kit; about twenty older screens
-- (cutscene cards, the licence test, the phone's own pages, ghosts, fines, ...) pick their own fonts and
-- near-black panels. Rather than edit each one, this watches PlayerGui and, only with Theme.CUTE:
--   * heavy Gotham faces (Black / Bold / Semibold) become the rounded Fredoka face (Thai falls back by itself);
--   * near-black panel backgrounds become the HUD's candy indigo (darker ones the darker indigo).
-- Full-width frames are left alone: scrims, letterbox bars and photo/replay frames are meant to be dark.
-- A frame or label can opt out with the attribute KeepSkin = true.
local Players = game:GetService("Players")
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Core"):WaitForChild("Theme"))

local CuteSkin = {}

local HEAVY = { [Enum.Font.GothamBlack] = true, [Enum.Font.GothamBold] = true, [Enum.Font.GothamSemibold] = true }

-- (2026-11-20, owner: "Font ก็ไม่สวยบางเกิน") Roblox draws every Thai letter with one fallback face, Noto Sans Thai
-- REGULAR (content/fonts has no other Thai file), whatever face or weight a label asks for, so Thai always came out
-- thin. A 1 px text outline in the text's own colour makes every letter heavier, Thai included. Labels that already
-- have an outline of their own (TextStroke) keep it; the outline fades with the text.
-- (first try, 70 % opaque on every label, turned small text into blobs: "486 / 1868 EXP", "ลงรถ [E]". Now only
-- text from 15 px up, and lighter: 15-17 px 25 % opaque, 18 px and up 45 %.)
local function weightFor(t: any): number
	local px = t.TextScaled and t.AbsoluteSize.Y * 0.8 or t.TextSize
	if px >= 18 then return 0.55 end
	if px >= 15 then return 0.75 end
	return 1
end
local function heavier(t: any)
	if t.TextStrokeTransparency < 1 or t:GetAttribute("CuteWeight") then return end
	if weightFor(t) >= 1 then return end
	t:SetAttribute("CuteWeight", true)
	local function sync()
		t.TextStrokeColor3 = t.TextColor3
		t.TextStrokeTransparency = math.max(weightFor(t), t.TextTransparency)
	end
	sync()
	t:GetPropertyChangedSignal("TextColor3"):Connect(sync)
	t:GetPropertyChangedSignal("TextTransparency"):Connect(sync)
end

local function skin(d: Instance)
	if not d:IsA("GuiObject") or d:GetAttribute("KeepSkin") then return end
	if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
		if HEAVY[d.Font] then d.Font = Enum.Font.FredokaOne end
		heavier(d)
	end
	if d.BackgroundTransparency < 0.9 and d.Size.X.Scale < 0.99 then
		local c = d.BackgroundColor3
		local m = math.max(c.R, c.G, c.B)
		if m < 0.17 and math.abs(c.R - c.G) < 0.05 and math.abs(c.G - c.B) < 0.08 then
			d.BackgroundColor3 = m < 0.09 and Theme.C.dark or Theme.C.glass
		end
	end
end

function CuteSkin.start()
	if not Theme.CUTE then return end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, d in ipairs(pg:GetDescendants()) do skin(d) end
	pg.DescendantAdded:Connect(function(d)
		-- (deferred: builders often set the colour after parenting)
		task.defer(skin, d)
	end)
end

return CuteSkin
