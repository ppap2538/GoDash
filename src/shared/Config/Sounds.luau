-- Audio ids. Loops come from the Roblox-licensed "ProSoundEffects" catalogue (free for every
-- experience); short UI sounds are built from sounds that ship with the engine, so nothing here
-- depends on a third-party upload. Set an id to 0 to silence it.
local function id(n: number): string
	return n == 0 and "" or ("rbxassetid://" .. n)
end

return {
	-- loops
	engineBike = id(9112787518), -- small 4-stroke engine, constant
	engineCar = id(9112734376), -- car interior, steady driving
	rain = id(9112854469),
	birds = id(9112831284),
	birdsCity = id(9112835068),
	traffic = id(9112784190),
	trafficNight = id(9112819963),
	skid = id(9119186275),
	-- engine built-ins
	tick = "rbxasset://sounds/volume_slider.ogg",
	thud = "rbxasset://sounds/action_jump_land.mp3",
	boom = "rbxasset://sounds/impact_explosion_03.mp3",
	splash = "rbxasset://sounds/impact_water.mp3",
}
