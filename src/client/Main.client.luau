-- GoDash: Thai Driver Life — client entry. Starts each controller; one failing never stops the rest.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Remotes")

-- UI/Core (Theme, Layout, Layers, UIState) and the HUD widgets under UI/ are plain modules: they
-- are required and built by HUD, so they need no entry here.
-- 2026-11-18 realism pass: ChaseCam + DriveFx follow Drive; OnFoot = walk/run/footsteps; Accident needs Peds,
-- Street and Cutscene, so it comes after them
-- 2026-11-18 whole-tambon pass: Backdrop = the far city outline, Ambience = places that sound like themselves
-- 2026-11-19 SignalAssist = "your light" panel, lane stop-line glow and red-light warning at junctions
local order = { "Perf", "State", "Lang", "Feedback", "Crash", "Drive", "ChaseCam", "DriveFx", "OnFoot", "Rider", "HUD", "GPS", "AutoDrive", "Phone", "Choice", "Feed", "Board", "Reviews", "Styling", "PhotoMode", "ShopApp", "SeasonApp", "CompanyApp", "LiveOps", "Env", "Backdrop", "Ambience", "Build", "Peds", "Street", "SignalAssist", "Dogs", "Radio", "Guide", "Welcome", "Cutscene", "Accident", "SpeedBumps", "StreetLife", "Finance", "License", "Tired", "Qa" }
local started = {}
for _, name in ipairs(order) do
	local ok, err = xpcall(function()
		local module = require(script.Parent:WaitForChild(name))
		module.start()
	end, function(e) return debug.traceback(tostring(e), 2) end)
	if ok then table.insert(started, name) else warn(("[GoDash] client %s failed to start:\n%s"):format(name, tostring(err))) end
end
print("[GoDash] client ready: " .. table.concat(started, ", "))
