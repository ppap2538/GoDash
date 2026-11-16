-- World clock. Lighting.ClockTime replicates; Workspace attributes carry the day and phase.
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Game = require(ReplicatedStorage.Shared.Config.Game)

local Time = {}
local clock = Game.START_CLOCK
local day = 1

function Time.phase(c: number?): string
	local t = c or clock
	if t >= 5.5 and t < 11 then return "Morning" end
	if t >= 11 and t < 16.5 then return "Afternoon" end
	if t >= 16.5 and t < 19 then return "Evening" end
	return "Night"
end

function Time.isNight(): boolean
	return clock >= 18.6 or clock < 5.8
end

function Time.clock(): number return clock end
function Time.day(): number return day end

function Time.start()
	Lighting.ClockTime = clock
	Workspace:SetAttribute("Day", day)
	Workspace:SetAttribute("Phase", Time.phase())
	Workspace:SetAttribute("IsNight", Time.isNight())
	local hoursPerSecond = 24 / Game.DAY_LENGTH
	task.spawn(function()
		while true do
			local dt = task.wait(0.5)
			-- a QA hook: Workspace attribute "QaClock" jumps the clock
			local qa = Workspace:GetAttribute("QaClock")
			if type(qa) == "number" then clock = qa % 24; Workspace:SetAttribute("QaClock", nil) end
			-- nights pass a little faster than days
			local speed = Time.isNight() and 1.5 or 0.85
			clock += dt * hoursPerSecond * speed
			if clock >= 24 then
				clock -= 24
				day += 1
				Workspace:SetAttribute("Day", day)
			end
			Lighting.ClockTime = clock
			local ph = Time.phase()
			if Workspace:GetAttribute("Phase") ~= ph then Workspace:SetAttribute("Phase", ph) end
			local night = Time.isNight()
			if Workspace:GetAttribute("IsNight") ~= night then Workspace:SetAttribute("IsNight", night) end
		end
	end)
end

return Time
