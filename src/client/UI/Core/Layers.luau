-- Stacking order. DisplayOrder for ScreenGuis; Z for elements inside one ScreenGui.
local Layers = {
	HUD = 10, -- status, navigation cluster, job card, speedometer, pedals, phone button
	Navigation = 20, -- the phone (maps, apps)
	Interaction = 30, -- interaction prompt, job offer, build panel
	Notification = 40, -- toasts and banners
	Modal = 50, -- reward card
	Critical = 60, -- reserved: errors, disconnect notices
}

Layers.Z = { base = 1, content = 2, raised = 5, overlay = 10 }

return Layers
