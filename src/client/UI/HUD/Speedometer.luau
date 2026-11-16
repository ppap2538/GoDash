-- Speedometer: km/h, light / signal / wet icons, fuel bar (bicycle when the vehicle is pedalled)
-- and condition bar. Has its own slot: bottom-right beside the phone button on keyboards, the
-- base of the bottom-centre stack on touch (the corners belong to the pedals there).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local UIRoot = script.Parent.Parent
local UI = require(UIRoot.Kit)
local UIState = require(UIRoot.Core.UIState)

local Speedo = {}
local C, F, T = UI.C, UI.F, UI.T
local refs = {} :: { [string]: any }
local lastKmh, lastIcons, lastPedal = -1, nil :: string?, nil :: boolean?

-- info = Drive.info. Called every frame while driving; only writes properties that changed.
function Speedo.update(info: any)
	local kmh = math.floor(info.speed * Game.KMH + 0.5)
	if kmh ~= lastKmh then
		lastKmh = kmh
		refs.speed.Text = tostring(kmh)
	end
	local pedal = info.pedal == true
	if pedal ~= lastPedal then
		lastPedal = pedal
		refs.fuelIcon.Text = pedal and "🚲" or "⛽"
	end
	if pedal then
		refs.setFuel(1)
	else
		refs.setFuel(info.fuelCap > 0 and info.fuel / info.fuelCap or 0)
	end
	refs.setCond(info.condition / 100)
	local sig = info.signal
	local icons = (info.lights and "💡" or "") .. (sig == -1 and "◁" or sig == 1 and "▷" or sig == 2 and "◁▷" or "") .. ((info.wet or 0) > 0.3 and "💧" or "")
	if icons ~= lastIcons then
		lastIcons = icons
		refs.icons.Text = icons
	end
end

function Speedo.build(region: Frame, order: number)
	local panel = UI.panel(region, { Name = "Speedo", LayoutOrder = order, Size = UDim2.fromOffset(172, 74) })
	refs.panel = panel
	refs.speed = UI.label(panel, "0", T.display, C.white, F.black, { Position = UDim2.fromOffset(10, 4), Size = UDim2.fromOffset(84, 40), TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.None })
	refs.icons = UI.label(panel, "", T.sm, C.white, F.med, { Position = UDim2.fromOffset(100, 6), Size = UDim2.fromOffset(64, 16), TextTruncate = Enum.TextTruncate.None })
	UI.label(panel, "km/h", T.sm, C.textDim, F.bold, { Position = UDim2.fromOffset(100, 22), Size = UDim2.fromOffset(60, 16) })
	refs.fuelIcon = UI.label(panel, "⛽", 11, C.white, F.med, { Position = UDim2.fromOffset(10, 44), Size = UDim2.fromOffset(20, 16), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	local fuelTrack, setFuel = UI.glassBar(panel, C.green, 6)
	fuelTrack.Position = UDim2.fromOffset(34, 49)
	fuelTrack.Size = UDim2.new(1, -46, 0, 6)
	refs.setFuel = setFuel
	UI.label(panel, "🔧", 9, C.white, F.med, { Position = UDim2.fromOffset(10, 56), Size = UDim2.fromOffset(20, 14), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	local condTrack, setCond = UI.glassBar(panel, C.blue, 4)
	condTrack.Position = UDim2.fromOffset(34, 61)
	condTrack.Size = UDim2.new(1, -46, 0, 4)
	refs.setCond = setCond
	UIState.bind("speedo", panel, function() UI.pop(panel, 0.92) end)
end

return Speedo
