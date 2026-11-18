-- Audio ids. Loops come from the Roblox-licensed "ProSoundEffects" catalogue (free for every
-- experience); short UI sounds are built from sounds that ship with the engine, so nothing here
-- depends on a third-party upload. Set an id to 0 to silence it.
local function id(n: number): string
	return n == 0 and "" or ("rbxassetid://" .. n)
end

return {
	-- loops
	engineBike = id(9112787518), -- "Go Kart Engine Constant 2": twin-cylinder 4-stroke, made to loop
	engineCar = id(9112734376), -- "1969 Chevrolet Chevelle Convertible 2": interior, long slow constant first
	engineBikeRegion = NumberRange.new(8, 22) :: NumberRange?, -- its steadiest part (measured 2026-11-17: -24..-26 dB, even tone)
	engineCarRegion = NumberRange.new(1, 13) :: NumberRange?, -- the steady cruise at the start (measured: -19..-21 dB); later it stops
	-- vehicle detail (ProSoundEffects, Roblox licence; added 2026-11-17 for client/EngineSound)
	roadCar = id(9112886237), -- "Tire Constant 1": rumbling tyres, airy whine, loop
	wind = id(9113286969), -- "Barstow Wind Light Blustery Low Howl 2"
	brakeSqueal = id(9125390563), -- "Bicycle Brake Squeal Short Shrieks Sudden Stop" (also sold for motorcycles)
	carDoor = id(9113205539), -- "Audi Car Door Movement Opening Closing 5"
	bell = id(9125390319), -- "Bicycle Bell Ringing"
	bikePedal = id(9113429966), -- "Bicycle Pedal 1"
	-- the crash cutscene (client/Cutscene "crash")
	bodyHit = id(9114849164), -- "Human Body Impact on Vehicle 3"
	bodyFall = id(9113480915), -- "Body Fall Thud 2": impact, thud, slide
	bodyFall2 = id(9113470802), -- "Body Fall Heavy Rustle 2": on concrete
	-- Thai street life (2026-11-17): ProSoundEffects one-shots and DistrokidOfficial music, both Roblox-licensed
	whistle = id(9125776474), -- "Police Whistle Long Short Various Versions 2": municipal officers
	phoneRing = id(9113752436), -- "Cell Phone Ring Tone 2": the finance company calling
	puddle = id(9125703162), -- "Mud Puddle Splash Shallow Water Impacts": floods, Songkran
	-- footsteps (client/OnFoot, 2026-11-18; ProSoundEffects has few plain human steps, so these are
	-- short foley hits played quietly with a random pitch)
	stepHard = { id(9114523345), id(9114523358), id(9114523629) }, -- "Foot Stomp 3/4/7" (hard floor)
	stepSoft = { id(9118686853), id(9118688024), id(9118687440) }, -- "Rocks Dirt Impacts In Ground 30/45/40" (muted thuds)
	stepWet = { id(9117942768), id(9117943121), id(9117943083) }, -- "Puddle Impact Small Footsteps 1/2/3"
	molam = id(98783707574864), -- "Molam Electric Funk Patrol" (DistrokidOfficial): the party truck
	songkranMusic = id(94214933774362), -- "Songkran Thai Dance" (DistrokidOfficial)
	-- places that sound like themselves (client/Ambience, 2026-11-18; ProSoundEffects, Roblox licence)
	marketDay = id(9112758136), -- "City Ambience 3": exterior market, traffic, food stand, chopping, vendors (loop)
	nightMarket = id(9112887235), -- "Tokyo Fish Market 1": side street, motorcycles, walla, less busy (loop)
	schoolYard = id(9114800838), -- "High School 2": exterior playground walla
	schoolBell = id(9116919685), -- "Middle School Background 2": calm exterior, long bell at the end
	lakeWater = id(9120572579), -- "Water Lap Small Waves 2": lake shore
	frogs = id(9112808138), -- "Jungle Frogs 3": night, chirping, insects (loop)
	crickets = id(9112762417), -- "Crickets And Cicadas 3": night, suburbs, rural (loop)
	farmMorning = id(9114370190), -- "Farm Animals Dog Barking Rooster Crows 2"
	stadiumCrowd = id(9119562636), -- "Stadium Crowd 2": cheering, applause, whistle
	cafeWalla = id(9118150889), -- "Resort Walla 1": outdoor cafe, light conversation, glasses
	rain = id(9112854469),
	birds = id(9112831284),
	birdsCity = id(9112835068),
	traffic = id(9112784190),
	trafficNight = id(9112819963),
	skid = id(9119186275),
	-- crashes and traffic (ProSoundEffects one-shots, same Roblox licence; added 2026-11-16)
	crashMetal = id(9116546358), -- Metal Crash 3
	crashMetal2 = id(9116546593), -- Metal Crash 4
	glass = id(9114031948), -- Debris Glass 4
	bump = id(9126155907), -- Vehicle Bottom Out Undercarriage Scrape Bump
	horn = id(9114402335), -- Car Honking Dual Air Horns 4 (short)
	-- soi dogs: "Coyotes Gruff Barking 8 / 13 (SFX)", Pro Sound Effects (same Roblox licence). A
	-- synthesised bark of our own is kept as a spare in assets/sfx (tools/make_bark.py).
	dogBark = id(9113955372),
	dogBark2 = id(9113956187),
	-- riding sounds, round 2 (2026-11-19, owner: "เสียงประกอบระหว่างขับ ตอนเลี้ยว ตอนเบรก ตอนล้ม"); all ProSoundEffects
	turnSignal = id(9112941573), -- "1963 Porsche 1": interior turn signal clicks (one click: turnSignalRegion)
	turnSignalRegion = NumberRange.new(6.47, 6.66) :: NumberRange?, -- measured 2026-11-19: the loudest single click
	engineStart = id(9114778476), -- "Harley Davidson 2": starter, catch, a rev (engineStartRegion)
	engineStartRegion = NumberRange.new(1.9, 4.0) :: NumberRange?, -- measured: silent until 2.0, catches ~2.1, revs ~3.1
	scrape = id(9116816823), -- "Metal Scrape Dragging Drain Pipe Concrete 4": a bike on its side, grinding on the road
	slosh = id(9120580913), -- "Water Sloshes Jostling Plastic Trash Can 3": the soup in the box (played small and high)
	passBy = id(9114240232), -- "Electric Car Pass By Airy Whirring Whine 16": a near miss
	rough = id(9112886781), -- "Tires Cobblestones 1": rolling on a rough surface (loop)
	grunt = id(9120417581), -- "Video Game Effects 23": a short "oof" (thrown off)
	grunt2 = id(9120417632), -- "Video Game Effects 25"
	plasticHit = id(9117451064), -- "Plastic Cooler 1": the delivery box knocking, plastic panels
	-- engine built-ins
	tick = "rbxasset://sounds/volume_slider.ogg",
	thud = "rbxasset://sounds/action_jump_land.mp3",
	boom = "rbxasset://sounds/impact_explosion_03.mp3",
	splash = "rbxasset://sounds/impact_water.mp3",
}
