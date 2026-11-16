-- In-game radio. Every track comes from the Roblox Creator Store music library published by
-- "DistrokidOfficial" (licensed by Roblox for use in experiences). External links such as
-- YouTube cannot be played in Roblox, so stations are playlists of these asset ids.
local function id(n: number): string
	return "rbxassetid://" .. n
end

return {
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
