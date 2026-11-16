-- Top-right navigation cluster: clock + weather pill, the minimap holder (GPS draws into it) and
-- the current road / district line. Nothing else lives in this corner.
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local UIRoot = script.Parent.Parent
local UI = require(UIRoot.Kit)
local Layout = require(UIRoot.Core.Layout)
local UIState = require(UIRoot.Core.UIState)

local Nav = {}
local C, F, T = UI.C, UI.F, UI.T
local refs = {} :: { [string]: any }
local lastMins = -1
local hudRef: any = nil

local WEATHER_ICON = { Sunny = "☀️", Cloudy = "⛅", Rainy = "🌧", HeavyRain = "🌧", Storm = "⛈" }
local GAP = 6
local ROAD_H = 18

local function relayout()
	local m = Layout.m
	local compact = Layout.breakpoint == "compact"
	local w = m.navW
	local pillH = compact and 34 or 40
	refs.root.Size = UDim2.fromOffset(w, pillH + GAP + m.mapH + GAP + ROAD_H)
	refs.pill.Size = UDim2.fromOffset(w, pillH)
	refs.clock.TextSize = compact and 16 or 18
	refs.phase.Visible = not compact
	if compact then
		refs.weather.AnchorPoint = Vector2.new(1, 0)
		refs.weather.Position = UDim2.new(1, -10, 0, 0)
	else
		refs.weather.AnchorPoint = Vector2.new(0, 0)
		refs.weather.Position = UDim2.fromOffset(70, 0)
	end
	refs.map.Size = UDim2.fromOffset(w, m.mapH)
	refs.road.Size = UDim2.fromOffset(w, ROAD_H)
	if hudRef then hudRef.mapSize = Vector2.new(w, m.mapH) end
end

local function refreshWeather()
	refs.weather.Text = WEATHER_ICON[Workspace:GetAttribute("Weather") or "Sunny"] or "☀️"
	refs.phase.Text = tostring(Workspace:GetAttribute("Phase") or "")
end

-- Cheap enough for a frame loop: the text only changes once per game minute.
function Nav.update()
	local mins = math.floor(Lighting.ClockTime * 60)
	if mins ~= lastMins then
		lastMins = mins
		refs.clock.Text = ("%02d:%02d"):format(math.floor(mins / 60) % 24, mins % 60)
	end
end

function Nav.setRoad(name: string)
	if refs.road then refs.road.Text = name end
end

-- region = the TopRight region; hud = the HUD facade (gets mapHolder and mapSize).
function Nav.build(region: Frame, hud: any)
	hudRef = hud
	local root = UI.new("Frame", { Name = "Nav", BackgroundTransparency = 1, LayoutOrder = 1, Parent = region })
	UI.list(root, GAP, false, Enum.HorizontalAlignment.Right)
	refs.root = root

	local pill = UI.panel(root, { Name = "Clock", LayoutOrder = 1 }, 18)
	refs.pill = pill
	refs.clock = UI.label(pill, "07:30", 18, C.white, F.black, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 56, 1, 0), TextTruncate = Enum.TextTruncate.None })
	refs.weather = UI.label(pill, "☀️", 17, C.white, F.med, { Position = UDim2.fromOffset(70, 0), Size = UDim2.new(0, 28, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	refs.phase = UI.label(pill, "Morning", T.sm, C.textDim, F.med, { Position = UDim2.fromOffset(102, 0), Size = UDim2.new(1, -112, 1, 0) })
	UI.fitText(refs.phase, T.sm, 9)

	local map = UI.new("Frame", { Name = "Minimap", BackgroundColor3 = Color3.fromRGB(34, 40, 48), LayoutOrder = 2, ClipsDescendants = true, Parent = root })
	UI.corner(map, UI.R.lg)
	UI.stroke(map, C.white, 1, 0.7)
	refs.map = map
	hud.mapHolder = map

	refs.road = UI.label(root, "", T.sm, C.white, F.bold, { Name = "Road", LayoutOrder = 3, TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.5 })
	UI.fitText(refs.road, T.sm, 9)

	relayout()
	Layout.onChange(relayout)
	UIState.bind("nav", root)
	Workspace:GetAttributeChangedSignal("Weather"):Connect(refreshWeather)
	Workspace:GetAttributeChangedSignal("Phase"):Connect(refreshWeather)
	refreshWeather()
	Nav.update()
end

return Nav
