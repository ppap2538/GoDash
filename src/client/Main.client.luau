-- GoDash: Thai Driver Life — client entry. Starts each controller; one failing never stops the rest.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Remotes")

-- UI/Core (Theme, Layout, Layers, UIState) and the HUD widgets under UI/ are plain modules: they
-- are required and built by HUD, so they need no entry here.
local order = { "State", "Lang", "Feedback", "Drive", "HUD", "GPS", "Phone", "Env", "Build", "Peds", "Street", "Dogs", "Radio", "Guide", "Welcome" }
local started = {}
for _, name in ipairs(order) do
	local ok, err = xpcall(function()
		local module = require(script.Parent:WaitForChild(name))
		module.start()
	end, function(e) return debug.traceback(tostring(e), 2) end)
	if ok then table.insert(started, name) else warn(("[GoDash] client %s failed to start:\n%s"):format(name, tostring(err))) end
end
print("[GoDash] client ready: " .. table.concat(started, ", "))
