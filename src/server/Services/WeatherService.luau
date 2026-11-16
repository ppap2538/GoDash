-- Weather state machine. Clients draw it (rain, clouds, thunder); the server uses it for
-- road grip (Workspace "Wet"), job bonuses and crops.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Jobs = require(ReplicatedStorage.Shared.Config.Jobs)

local Weather = {}

local TYPES = {
	Sunny = { weight = 44, rain = 0, min = 150, max = 300 },
	Cloudy = { weight = 24, rain = 0, min = 120, max = 240 },
	Rainy = { weight = 18, rain = 0.5, min = 110, max = 220 },
	HeavyRain = { weight = 9, rain = 0.85, min = 90, max = 170 },
	Storm = { weight = 5, rain = 1, min = 70, max = 140 },
}
local current = "Sunny"
local wet = 0
local rng = Random.new()

function Weather.current(): string return current end
function Weather.rain(): number return TYPES[current].rain end
function Weather.isRaining(): boolean return TYPES[current].rain > 0 end
function Weather.wet(): number return wet end

function Weather.payBonus(): number
	if current == "Storm" then return Jobs.STORM_BONUS end
	if TYPES[current].rain > 0 then return Jobs.RAIN_BONUS end
	return 0
end

local function set(name: string)
	current = name
	Workspace:SetAttribute("Weather", name)
	Workspace:SetAttribute("Rain", TYPES[name].rain)
end

local function pick(): string
	-- rain rarely follows rain directly, so players get dry spells
	local total = 0
	local raining = Weather.isRaining()
	for n, t in pairs(TYPES) do
		if n ~= current then total += (raining and t.rain > 0) and t.weight * 0.3 or t.weight end
	end
	local r = rng:NextNumber() * total
	for n, t in pairs(TYPES) do
		if n ~= current then
			r -= (raining and t.rain > 0) and t.weight * 0.3 or t.weight
			if r <= 0 then return n end
		end
	end
	return "Sunny"
end

function Weather.start()
	set("Sunny")
	Workspace:SetAttribute("Wet", 0)
	task.spawn(function()
		local nextChange = os.clock() + rng:NextNumber(120, 200)
		while true do
			task.wait(2)
			local qa = Workspace:GetAttribute("QaWeather")
			if type(qa) == "string" and TYPES[qa] then
				set(qa)
				Workspace:SetAttribute("QaWeather", nil)
				nextChange = os.clock() + 180
			elseif os.clock() >= nextChange then
				local n = pick()
				set(n)
				nextChange = os.clock() + rng:NextNumber(TYPES[n].min, TYPES[n].max)
			end
			-- roads get wet in ~20 s of rain and dry in ~90 s
			local rain = TYPES[current].rain
			if rain > 0 then wet = math.min(1, wet + 0.1 * (0.5 + rain)) else wet = math.max(0, wet - 0.022) end
			local shown = math.floor(wet * 20 + 0.5) / 20
			if Workspace:GetAttribute("Wet") ~= shown then Workspace:SetAttribute("Wet", shown) end
		end
	end)
end

return Weather
