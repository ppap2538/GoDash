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

return Theme
