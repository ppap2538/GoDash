-- In-game radio. Every track comes from the Roblox Creator Store music libraries published by
-- "APMOfficial" (APM Music) and "DistrokidOfficial", both licensed by Roblox for use in experiences.
-- External links such as YouTube cannot be played in Roblox, so stations are playlists of asset ids.
-- The first station plays by itself after joining (client/Radio, settings.bgm); added 2026-11-16 when
-- the owner asked for upbeat background music so the game never gets boring.
local function id(n: number): string
	return "rbxassetid://" .. n
end

return {
	{ id = "beat", name = "GoDash Beat", thai = "คลื่นมันส์ขับรถ", icon = "🔥", tracks = {
		{ "Going Places", id(1847680839) }, { "Sunrise Workout", id(1837324500) }, { "Stepping Up", id(1837324424) }, { "Happy Song", id(1843404009) },
		{ "Bright Start", id(1847680891) }, { "Out And About", id(1847681510) }, { "Cheerful Happy Pop", id(1836135091) }, { "J Funk", id(1839982803) },
		{ "Whole Wide World", id(1843523073) }, { "Bright Heart House", id(104439502290763) }, { "Afterglow Beats", id(102939937272472) },
		{ "Euphoric Twirl Union", id(120828665667679) }, { "Happy Pop Air", id(114278404994638) }, { "Fizzy Radiance", id(104479515204878) },
		{ "Thailand Electronic Synthwave", id(85080568671547) },
	} },
	{ id = "chill", name = "Chill FM", thai = "คลื่นชิล", icon = "🌙", tracks = {
		{ "Morning", id(140722099430139) }, { "Time", id(140658234151287) }, { "Deadlines", id(140628387917926) }, { "Pastel Corner Life", id(89402602954424) },
	} },
	{ id = "drive", name = "Drive Hits", thai = "เพลงขับรถ", icon = "🚗", tracks = {
		{ "The Boundless", id(136107385141806) }, { "Emerge from the Soil", id(78767231495413) }, { "Magnificent and Brilliant", id(116455260596269) },
	} },
	{ id = "acoustic", name = "Acoustic Cafe", thai = "อะคูสติกคาเฟ่", icon = "🎸", tracks = {
		{ "Quiet Guitar Near the Window", id(121258493858244) }, { "Background Guitar", id(122624027580555) }, { "Gentle Picking", id(98910420877236) },
		{ "Gentle Guitar", id(122218030522196) },
	} },
}
