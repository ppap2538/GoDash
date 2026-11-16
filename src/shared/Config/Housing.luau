-- Land tiers and the furniture catalogue. `shape` picks the model the FurnitureFactory builds,
-- `use` is what the piece really does when a player uses it.
local Housing = {}

-- size = lot (x, z); house = shell footprint (x, z) and wall height
Housing.TIERS = {
	small = { id = "small", name = "Small Plot", thai = "ที่ดินเล็ก", price = 25000, level = 3, size = Vector2.new(44, 44), house = Vector3.new(26, 11, 22), limit = 30 },
	medium = { id = "medium", name = "Medium Plot", thai = "ที่ดินกลาง", price = 70000, level = 7, size = Vector2.new(58, 58), house = Vector3.new(34, 12, 28), limit = 45 },
	large = { id = "large", name = "Large Plot", thai = "ที่ดินใหญ่", price = 180000, level = 12, size = Vector2.new(74, 74), house = Vector3.new(44, 13, 34), limit = 60 },
	premium = { id = "premium", name = "Premium Plot", thai = "ที่ดินพรีเมียม", price = 450000, level = 18, size = Vector2.new(90, 90), house = Vector3.new(54, 14, 40), limit = 80 },
	riverside = { id = "riverside", name = "Riverside Plot", thai = "ที่ดินริมน้ำ", price = 900000, level = 24, size = Vector2.new(92, 100), house = Vector3.new(56, 15, 44), limit = 100 },
}
Housing.TIER_ORDER = { "small", "medium", "large", "premium", "riverside" }

Housing.CATEGORIES = { "Living Room", "Bedroom", "Kitchen", "Bathroom", "Garage", "Garden", "Decoration" }

Housing.FURNITURE = {
	-- Living room
	{ id = "sofa", name = "Sofa", cat = "Living Room", price = 1800, size = Vector3.new(8, 3.2, 3.6), shape = "sofa", use = "sit" },
	{ id = "armchair", name = "Armchair", cat = "Living Room", price = 900, size = Vector3.new(4, 3.2, 3.6), shape = "sofa", use = "sit" },
	{ id = "coffee_table", name = "Coffee Table", cat = "Living Room", price = 600, size = Vector3.new(5, 1.6, 3), shape = "table" },
	{ id = "tv", name = "TV & Stand", cat = "Living Room", price = 4200, size = Vector3.new(8, 5.4, 2), shape = "tv", use = "tv" },
	{ id = "bookshelf", name = "Bookshelf", cat = "Living Room", price = 1400, size = Vector3.new(5, 7.5, 1.6), shape = "shelf" },
	{ id = "computer", name = "Computer Desk", cat = "Living Room", price = 6500, size = Vector3.new(6, 4.6, 3), shape = "pc", use = "computer" },
	-- Bedroom
	{ id = "bed_single", name = "Single Bed", cat = "Bedroom", price = 1500, size = Vector3.new(4.6, 2.6, 8.4), shape = "bed", use = "bed", power = 1 },
	{ id = "bed_double", name = "Double Bed", cat = "Bedroom", price = 4800, size = Vector3.new(7.6, 2.8, 8.6), shape = "bed", use = "bed", power = 1.6 },
	{ id = "wardrobe", name = "Wardrobe", cat = "Bedroom", price = 2200, size = Vector3.new(5.5, 8, 2.4), shape = "wardrobe" },
	{ id = "nightstand", name = "Nightstand & Lamp", cat = "Bedroom", price = 700, size = Vector3.new(2.4, 4.6, 2.4), shape = "lamp_table" },
	-- Kitchen
	{ id = "fridge", name = "Refrigerator", cat = "Kitchen", price = 5200, size = Vector3.new(3.6, 7.6, 3.2), shape = "fridge", use = "fridge" },
	{ id = "stove", name = "Kitchen Stove", cat = "Kitchen", price = 3800, size = Vector3.new(6, 3.8, 2.8), shape = "stove", use = "stove" },
	{ id = "kitchen_counter", name = "Counter & Sink", cat = "Kitchen", price = 1900, size = Vector3.new(6, 3.8, 2.8), shape = "counter" },
	{ id = "dining_table", name = "Dining Table", cat = "Kitchen", price = 1600, size = Vector3.new(7, 3.2, 4.4), shape = "table" },
	{ id = "dining_chair", name = "Dining Chair", cat = "Kitchen", price = 350, size = Vector3.new(2.2, 4, 2.2), shape = "chair", use = "sit" },
	-- Bathroom
	{ id = "shower", name = "Shower", cat = "Bathroom", price = 3200, size = Vector3.new(4.4, 8.4, 4.4), shape = "shower", use = "shower" },
	{ id = "toilet", name = "Toilet", cat = "Bathroom", price = 1100, size = Vector3.new(2.4, 3.4, 3.4), shape = "toilet" },
	{ id = "bath_sink", name = "Sink & Mirror", cat = "Bathroom", price = 950, size = Vector3.new(3.4, 6.6, 2), shape = "sink" },
	{ id = "washer", name = "Washing Machine", cat = "Bathroom", price = 3900, size = Vector3.new(3, 3.8, 3), shape = "washer" },
	-- Garage
	{ id = "garage_pad", name = "Garage Pad", cat = "Garage", price = 5000, size = Vector3.new(11, 0.4, 20), shape = "garage", use = "garage" },
	{ id = "tool_bench", name = "Tool Bench", cat = "Garage", price = 2600, size = Vector3.new(7, 4.4, 2.8), shape = "bench_tools", use = "repair" },
	{ id = "tire_rack", name = "Tire Rack", cat = "Garage", price = 800, size = Vector3.new(4, 5, 2), shape = "shelf" },
	-- Garden
	{ id = "garden_bench", name = "Garden Bench", cat = "Garden", price = 650, size = Vector3.new(6, 3, 2.4), shape = "bench", use = "sit" },
	{ id = "palm", name = "Palm Tree", cat = "Garden", price = 900, size = Vector3.new(4, 16, 4), shape = "palm" },
	{ id = "flowerbed", name = "Flower Bed", cat = "Garden", price = 450, size = Vector3.new(6, 1.6, 3), shape = "flowers" },
	{ id = "spirit_house", name = "Spirit House", cat = "Garden", price = 2400, size = Vector3.new(3, 7, 3), shape = "spirit" },
	{ id = "fence", name = "Wooden Fence", cat = "Garden", price = 120, size = Vector3.new(8, 3, 0.6), shape = "fence" },
	{ id = "lamp_post", name = "Garden Lamp", cat = "Garden", price = 700, size = Vector3.new(1.4, 8, 1.4), shape = "lamp_post" },
	-- Decoration
	{ id = "rug", name = "Woven Rug", cat = "Decoration", price = 500, size = Vector3.new(8, 0.2, 6), shape = "rug" },
	{ id = "plant_pot", name = "Potted Plant", cat = "Decoration", price = 300, size = Vector3.new(2, 4.4, 2), shape = "plant" },
	{ id = "floor_lamp", name = "Floor Lamp", cat = "Decoration", price = 650, size = Vector3.new(1.6, 7, 1.6), shape = "floor_lamp" },
	{ id = "painting", name = "Framed Art", cat = "Decoration", price = 800, size = Vector3.new(4, 3, 0.4), shape = "painting" },
	{ id = "fan", name = "Standing Fan", cat = "Decoration", price = 550, size = Vector3.new(2, 5.6, 2), shape = "fan" },
}

Housing.ById = {}
for _, f in ipairs(Housing.FURNITURE) do Housing.ById[f.id] = f end

Housing.GRID = 2 -- studs
Housing.REFUND = 0.5

-- Footprint (x, z) of a piece after a quarter-turn rotation.
function Housing.footprint(def, rot: number): (number, number)
	if rot % 2 == 1 then return def.size.Z, def.size.X end
	return def.size.X, def.size.Z
end

return Housing
