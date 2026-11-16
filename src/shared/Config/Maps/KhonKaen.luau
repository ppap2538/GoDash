-- Khon Kaen city centre at 1:1 scale (1 stud = 0.28 m). The street network, lake, parks and railway
-- come from OpenStreetMap (c) OpenStreetMap contributors, ODbL — see tools/osm_fetch.mjs and
-- tools/osm_to_map.py. Shops and their names are our own; only positions follow the real city.
-- A new province = a new file like this one plus its data folder (see Config/Game.MAP).
-- Axes: +X east, +Z south. Ground is y = 0.
local Data = script.Parent.KhonKaenData
local F = require(Data.Features)

local Map = {}
Map.id = "KhonKaen"
Map.name = "Khon Kaen"
Map.thai = "ขอนแก่น"
Map.bounds = F.bounds
Map.credit = "Map data © OpenStreetMap contributors"

local STUD = 0.28
local function m(x: number, z: number): Vector3 -- metres from the map origin -> studs
	return Vector3.new(x / STUD, 0, z / STUD)
end

-- width = carriageway, walk = sidewalk each side (studs)
Map.roadTypes = {
	highway = { id = 1, width = 44, walk = 7, limit = 90, y = 0.26 },
	main = { id = 2, width = 40, walk = 7, limit = 70, y = 0.24 },
	street = { id = 3, width = 30, walk = 5, limit = 60, y = 0.22 },
	soi = { id = 4, width = 20, walk = 0, limit = 40, y = 0.2 },
}
local TYPE_BY_ID = { "highway", "main", "street", "soi" }

-- Parsed lazily: nodes = { {x, z} }, edges = { {a, b, type, nameIndex, oneway} }
function Map.loadGraph()
	local nodes, edges = {}, {}
	for i = 1, F.nodeChunks do
		for x, z in (require(Data["Nodes" .. i]) :: string):gmatch("(-?%d+),(-?%d+)") do
			table.insert(nodes, { tonumber(x), tonumber(z) })
		end
	end
	for i = 1, F.edgeChunks do
		for a, b, c, n, ow in (require(Data["Edges" .. i]) :: string):gmatch("(%d+),(%d+),(%d+),(%d+),(%d+)") do
			table.insert(edges, { tonumber(a), tonumber(b), TYPE_BY_ID[tonumber(c) :: number], tonumber(n), ow == "1" })
		end
	end
	return nodes, edges, F.names
end

Map.features = F -- water, parks, rails, pois (real positions)

-- Gameplay districts (first match wins).
Map.zones = {
	{ id = "mittraphap", name = "Mittraphap Strip", thai = "ย่านมิตรภาพ", x1 = -99999, z1 = -99999, x2 = -1500, z2 = 99999 },
	{ id = "lakeside", name = "Bueng Kaen Nakhon", thai = "ย่านบึงแก่นนคร", x1 = 900, z1 = 1100, x2 = 99999, z2 = 99999 },
	{ id = "north", name = "Pracha Samoson", thai = "ย่านประชาสโมสร", x1 = -1500, z1 = -99999, x2 = 99999, z2 = -4600 },
	{ id = "downtown", name = "City Center", thai = "ใจกลางเมือง", x1 = -1500, z1 = -4600, x2 = 99999, z2 = 1100 },
	{ id = "south", name = "South Side", thai = "ย่านเมืองใต้", x1 = -99999, z1 = -99999, x2 = 99999, z2 = 99999 },
}
function Map.zoneAt(x: number, z: number)
	for _, zn in ipairs(Map.zones) do
		if x >= zn.x1 and x <= zn.x2 and z >= zn.z1 and z <= zn.z2 then return zn end
	end
	return Map.zones[#Map.zones]
end

Map.center = m(300, -900) -- downtown core (Si Chan / Na Mueang)
Map.coreRadius = 3400 -- towers and dense shophouses inside this distance of the centre
Map.heroRadius = 1200 -- fully detailed facades, street props and parked vehicles inside this distance
Map.liteRadius = 2400 -- lighter detailed facades on main streets out to this distance

-- Hand-designed places, dropped on free land beside the road nearest to `at` (real-world spots).
-- w = width along the street, d = depth.
Map.pois = {
	{ id = "hub", kind = "hub", name = "GoDash Rider Hub", thai = "ศูนย์ไรเดอร์ GoDash", at = m(290, -1020), w = 64, d = 70 },
	{ id = "mall", kind = "mall", name = "KK Plaza", thai = "เคเค พลาซ่า", at = m(-560, -1180), w = 300, d = 220 },
	{ id = "station", kind = "station", name = "Khon Kaen Railway Station", thai = "สถานีรถไฟขอนแก่น", at = m(-540, -470), w = 150, d = 80 },
	{ id = "hospital", kind = "hospital", name = "Khon Kaen Hospital", thai = "โรงพยาบาลขอนแก่น", at = m(-700, -1430), w = 200, d = 130 },
	{ id = "bus", kind = "bus", name = "Bus Terminal", thai = "สถานีขนส่ง (บขส.)", at = m(240, -1880), w = 190, d = 120 },
	{ id = "nightmarket", kind = "nightmarket", name = "Ruen Rom Night Market", thai = "ตลาดโต้รุ่ง รื่นรมย์", at = m(350, -345), w = 100, d = 90 },
	{ id = "police", kind = "police", name = "Police Station", thai = "สถานีตำรวจ", at = m(535, -680), w = 100, d = 70 },
	{ id = "freshmarket", kind = "market", name = "Bang Lamphu Fresh Market", thai = "ตลาดสดบางลำภู", at = m(370, -715), w = 120, d = 96 },
	{ id = "dealer", kind = "dealer", name = "KK Motors", thai = "เคเค มอเตอร์ส", at = m(-1020, 150), w = 130, d = 80 },
	{ id = "homestore", kind = "homestore", name = "Baan Suay Home", thai = "บ้านสวย โฮม", at = m(-960, -760), w = 120, d = 76 },
	{ id = "stupa", kind = "stupa", name = "Kaen Nakhon Stupa", thai = "พระธาตุแก่นนคร", at = m(450, 1560), w = 110, d = 110 },
	{ id = "reststop", kind = "reststop", name = "Lakeside Sala", thai = "ศาลาริมบึง", at = m(420, 900), w = 60, d = 72 },
	{ id = "agri", kind = "agri", name = "Farmers' Market", thai = "ตลาดเกษตร", at = m(-350, 1250), w = 124, d = 90 },
	{ id = "seedshop", kind = "seedshop", name = "Isan Seed Shop", thai = "ร้านเมล็ดพันธุ์อีสาน", at = m(-300, 1300), w = 44, d = 46 },
	{ id = "farm", kind = "farm", name = "Community Farm", thai = "แปลงเกษตรชุมชน", at = m(-380, 1400), w = 460, d = 132 },
}
Map.gasStations = 4 -- placed on real fuel-station positions, spread across the city
Map.gasSize = { w = 72, d = 76 }

-- Land for sale: each group is laid along streets around its centre.
Map.plotGroups = {
	{ tier = "small", count = 8, at = m(820, -420) },
	{ tier = "medium", count = 6, at = m(880, -120) },
	{ tier = "large", count = 4, at = m(-200, 420) },
	{ tier = "premium", count = 3, at = m(260, 1150) },
	{ tier = "riverside", count = 3, at = m(1080, 950) },
}
Map.farmBeds = { cols = 6, rows = 2, w = 64, d = 46 }

-- Our own partner shops are placed on street-front lots nearest real restaurant / shop positions.
Map.restaurantCount = 34
Map.convenienceCount = 14
Map.cafeCount = 8
Map.restaurantNames = {
	{ "Krapao Fai Luk", "กะเพราไฟลุก", { "krapao", "chicken_rice", "water" } },
	{ "Som Tam Zaap Nua", "ส้มตำแซ่บนัว", { "somtam", "grilled_chicken", "moo_ping" } },
	{ "Hia Tong Boat Noodles", "ก๋วยเตี๋ยวเรือเฮียตง", { "noodles", "water" } },
	{ "Pratu Mueang Chicken Rice", "ข้าวมันไก่ประตูเมือง", { "chicken_rice", "noodles", "water" } },
	{ "Kai Yang Suan Kwang", "ไก่ย่างสวนกวาง", { "grilled_chicken", "somtam", "moo_ping" } },
	{ "Mae Sri Desserts", "ขนมหวานแม่ศรี", { "mango_sticky", "milk_tea" } },
	{ "Bubble Tea Bar", "ชานมไข่มุก", { "milk_tea", "coffee" } },
	{ "Moo Ping Pa Daeng", "หมูปิ้งป้าแดง", { "moo_ping", "water" } },
	{ "Lakeside Isan Kitchen", "ครัวอีสานริมบึง", { "somtam", "grilled_chicken", "krapao" } },
	{ "Krapao Express", "กะเพราด่วน", { "krapao", "water" } },
	{ "Isan BBQ House", "ปิ้งย่างอีสาน", { "grilled_chicken", "moo_ping", "somtam" } },
	{ "Morning Jok", "โจ๊กเช้า", { "chicken_rice", "coffee" } },
	{ "Mu Ban Kitchen", "ครัวหมู่บ้าน", { "krapao", "noodles", "water" } },
	{ "Ban Kok Som Tam", "ส้มตำบ้านโคก", { "somtam", "grilled_chicken" } },
	{ "Jae Noi Noodles", "ก๋วยเตี๋ยวเจ๊น้อย", { "noodles", "moo_ping" } },
	{ "Khao Niao Mamuang Yai", "ข้าวเหนียวมะม่วงยาย", { "mango_sticky", "milk_tea", "water" } },
	{ "Tam Sua Saep", "ตำซั่วแซ่บ", { "somtam", "moo_ping", "water" } },
}

return Map
