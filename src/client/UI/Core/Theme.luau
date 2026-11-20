-- GoDash design tokens. Every colour, font, text size, radius and spacing unit on screen comes
-- from here so the whole UI reads as one system.
local Theme = {}

Theme.C = {
	-- brand
	green = Color3.fromRGB(0, 186, 96),
	greenDark = Color3.fromRGB(0, 140, 74),
	greenSoft = Color3.fromRGB(214, 244, 226),
	-- light surfaces (phone screens, reward card)
	bg = Color3.fromRGB(244, 246, 248),
	card = Color3.fromRGB(255, 255, 255),
	line = Color3.fromRGB(226, 230, 236),
	text = Color3.fromRGB(26, 32, 40),
	sub = Color3.fromRGB(112, 122, 136),
	-- dark glass surfaces (HUD)
	dark = Color3.fromRGB(18, 22, 28),
	glass = Color3.fromRGB(14, 18, 24),
	chip = Color3.fromRGB(62, 68, 78),
	textDim = Color3.fromRGB(196, 203, 212),
	-- signals
	red = Color3.fromRGB(232, 70, 70),
	orange = Color3.fromRGB(244, 150, 40),
	yellow = Color3.fromRGB(250, 196, 40),
	blue = Color3.fromRGB(52, 132, 240),
	purple = Color3.fromRGB(140, 96, 220),
	pink = Color3.fromRGB(240, 110, 160),
	white = Color3.new(1, 1, 1),
	black = Color3.new(0, 0, 0),
}

Theme.F = {
	black = Enum.Font.GothamBlack,
	bold = Enum.Font.GothamBold,
	med = Enum.Font.GothamMedium,
	reg = Enum.Font.Gotham,
}

-- Type scale (px on the layout canvas).
Theme.T = { xs = 10, sm = 12, md = 14, lg = 16, xl = 20, xxl = 26, display = 34 }

-- Corner radii.
Theme.R = { sm = 8, md = 12, lg = 16, pill = 999 }

-- Spacing units.
Theme.S = { xs = 4, sm = 8, md = 12, lg = 16 }

-- Glass panel: dark, slightly see-through, with a thin light edge.
Theme.GLASS_ALPHA = 0.2 -- BackgroundTransparency of a HUD panel
Theme.STROKE_ALPHA = 0.86 -- Transparency of the 1 px white edge
Theme.TRACK_ALPHA = 0.8 -- Transparency of a bar track on glass
Theme.STROKE_W = 1 -- edge thickness of panels
Theme.CUTE = false

-- (2026-11-20, owner: "พวก UX/UI ต่างๆ ก็ขอน่ารักๆ สดใสด้วยนะ เน้นเล่นง่าย") with the toy-brick look
-- (Config/Look.BRICKS) the HUD is candy styled instead of near-black glass: a plum-charcoal panel (indigo for a few hours)
-- with a bold white edge, rounder corners, the rounded Fredoka face for headings and numbers (Thai letters
-- fall back to Roblox's Thai face), slightly bigger text. White text on the panels stays readable.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Look"))
if Look.BRICKS then
	Theme.CUTE = true
	local C = Theme.C
	C.green = Color3.fromRGB(16, 196, 104)
	C.greenDark = Color3.fromRGB(8, 150, 80)
	C.greenSoft = Color3.fromRGB(214, 248, 228)
	C.bg = Color3.fromRGB(246, 245, 255)
	C.line = Color3.fromRGB(228, 226, 246)
	C.text = Color3.fromRGB(40, 36, 72)
	C.sub = Color3.fromRGB(120, 116, 156)
	-- (later the same day, owner: "UI มันสีกลืนกับถนนเกิน": the indigo sat right on the studded road's blue) panels
	-- are a deep plum-charcoal now: darker and far less blue than the road and the sky, still warm, with the white rim
	C.dark = Color3.fromRGB(26, 23, 36)
	C.glass = Color3.fromRGB(38, 33, 50)
	C.chip = Color3.fromRGB(76, 68, 100)
	C.textDim = Color3.fromRGB(226, 222, 238)
	C.red = Color3.fromRGB(255, 92, 102)
	C.orange = Color3.fromRGB(255, 160, 52)
	C.yellow = Color3.fromRGB(255, 206, 60)
	C.blue = Color3.fromRGB(64, 150, 255)
	C.purple = Color3.fromRGB(156, 110, 240)
	C.pink = Color3.fromRGB(255, 120, 180)
	Theme.F.black = Enum.Font.FredokaOne
	Theme.F.bold = Enum.Font.FredokaOne
	Theme.R = { sm = 10, md = 16, lg = 20, pill = 999 }
	Theme.GLASS_ALPHA = 0.06
	Theme.STROKE_ALPHA = 0.15
	Theme.STROKE_W = 2
end

return Theme
