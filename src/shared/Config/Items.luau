-- Every inventory item: food, cooked meals, seeds, crops and supplies.
-- Icons stay within Unicode 12 emoji (newer ones do not draw in Roblox).
local Items = {}

local LIST = {
	-- street food and drinks -----------------------------------------------------------------------
	{ id = "krapao", name = "Pad Krapao Rice", thai = "ข้าวกะเพรา", icon = "🍛", kind = "food", price = 45, hunger = 46, energy = 8, happy = 4 },
	{ id = "somtam", name = "Som Tam", thai = "ส้มตำ", icon = "🥗", kind = "food", price = 35, hunger = 30, energy = 4, happy = 10,
		buff = { id = "spicy", name = "Spicy Mood", desc = "+12% tips", seconds = 300 } },
	{ id = "moo_ping", name = "Moo Ping & Sticky Rice", thai = "ข้าวเหนียวหมูปิ้ง", icon = "🍢", kind = "food", price = 25, hunger = 28, energy = 5, happy = 5 },
	{ id = "noodles", name = "Boat Noodles", thai = "ก๋วยเตี๋ยว", icon = "🍜", kind = "food", price = 40, hunger = 40, energy = 6, happy = 5 },
	{ id = "chicken_rice", name = "Chicken Rice", thai = "ข้าวมันไก่", icon = "🍚", kind = "food", price = 45, hunger = 48, energy = 6, happy = 4 },
	{ id = "grilled_chicken", name = "Kai Yang", thai = "ไก่ย่าง", icon = "🍗", kind = "food", price = 60, hunger = 58, energy = 8, happy = 8 },
	{ id = "mango_sticky", name = "Mango Sticky Rice", thai = "ข้าวเหนียวมะม่วง", icon = "🥭", kind = "food", price = 50, hunger = 25, energy = 6, happy = 22 },
	{ id = "milk_tea", name = "Thai Milk Tea", thai = "ชานม", icon = "🥤", kind = "food", price = 30, hunger = 8, energy = 18, happy = 10,
		buff = { id = "sugar", name = "Sugar Rush", desc = "-35% energy drain", seconds = 240 } },
	{ id = "energy_drink", name = "Energy Drink", thai = "เครื่องดื่มชูกำลัง", icon = "⚡", kind = "food", price = 20, hunger = 2, energy = 28, happy = 0 },
	{ id = "water", name = "Water", thai = "น้ำเปล่า", icon = "💧", kind = "food", price = 10, hunger = 4, energy = 5, happy = 0 },
	{ id = "coffee", name = "Iced Coffee", thai = "กาแฟเย็น", icon = "☕", kind = "food", price = 35, hunger = 4, energy = 24, happy = 6 },

	-- cooked at home from your own crops -------------------------------------------------------------
	{ id = "home_somtam", name = "Homemade Som Tam", thai = "ส้มตำบ้านเฮา", icon = "🥗", kind = "food", price = 0, sell = 140, hunger = 50, energy = 8, happy = 16, cooked = true,
		buff = { id = "spicy", name = "Spicy Mood", desc = "+12% tips", seconds = 420 } },
	{ id = "grilled_corn", name = "Grilled Corn", thai = "ข้าวโพดปิ้ง", icon = "🌽", kind = "food", price = 0, sell = 95, hunger = 36, energy = 10, happy = 8, cooked = true },
	{ id = "garden_salad", name = "Garden Salad", thai = "สลัดผักสวนครัว", icon = "🥬", kind = "food", price = 0, sell = 110, hunger = 32, energy = 16, happy = 8, cooked = true },
	{ id = "melon_slices", name = "Watermelon Slices", thai = "แตงโมหั่นชิ้น", icon = "🍉", kind = "food", price = 0, sell = 120, hunger = 22, energy = 8, happy = 16, cooked = true },
	{ id = "fried_rice", name = "Chili Fried Rice", thai = "ข้าวผัดพริก", icon = "🍳", kind = "food", price = 0, sell = 150, hunger = 62, energy = 12, happy = 10, cooked = true },

	-- seeds -------------------------------------------------------------------------------------------
	{ id = "seed_lettuce", name = "Lettuce Seeds", thai = "เมล็ดผักกาด", icon = "🌱", kind = "seed", price = 15, crop = "lettuce" },
	{ id = "seed_chili", name = "Chili Seeds", thai = "เมล็ดพริก", icon = "🌱", kind = "seed", price = 20, crop = "chili" },
	{ id = "seed_tomato", name = "Tomato Seeds", thai = "เมล็ดมะเขือเทศ", icon = "🌱", kind = "seed", price = 30, crop = "tomato" },
	{ id = "seed_corn", name = "Corn Seeds", thai = "เมล็ดข้าวโพด", icon = "🌱", kind = "seed", price = 45, crop = "corn" },
	{ id = "seed_rice", name = "Rice Seedlings", thai = "ต้นกล้าข้าว", icon = "🌾", kind = "seed", price = 60, crop = "rice" },
	{ id = "seed_watermelon", name = "Watermelon Seeds", thai = "เมล็ดแตงโม", icon = "🌱", kind = "seed", price = 120, crop = "watermelon" },

	-- produce (sold at the farmers' market at the day's price) ---------------------------------------
	{ id = "lettuce", name = "Lettuce", thai = "ผักกาด", icon = "🥬", kind = "crop", sell = 14 },
	{ id = "chili", name = "Chili", thai = "พริก", icon = "🌶", kind = "crop", sell = 12 },
	{ id = "tomato", name = "Tomato", thai = "มะเขือเทศ", icon = "🍅", kind = "crop", sell = 18 },
	{ id = "corn", name = "Corn", thai = "ข้าวโพด", icon = "🌽", kind = "crop", sell = 30 },
	{ id = "rice", name = "Jasmine Rice", thai = "ข้าวหอมมะลิ", icon = "🌾", kind = "crop", sell = 22 },
	{ id = "watermelon", name = "Watermelon", thai = "แตงโม", icon = "🍉", kind = "crop", sell = 160 },

	-- supplies ------------------------------------------------------------------------------------------
	{ id = "fertilizer", name = "Fertilizer", thai = "ปุ๋ย", icon = "🧪", kind = "supply", price = 25 },
	{ id = "compost", name = "Compost", thai = "ปุ๋ยหมัก", icon = "🍂", kind = "supply", price = 40 },
}

Items.List = LIST
Items.ById = {}
for _, it in ipairs(LIST) do Items.ById[it.id] = it end

-- What each kind of shop stocks.
Items.SHOPS = {
	convenience = { "water", "energy_drink", "milk_tea", "coffee", "moo_ping" },
	market = { "moo_ping", "somtam", "grilled_chicken", "mango_sticky", "noodles", "water" },
	nightmarket = { "moo_ping", "somtam", "krapao", "noodles", "mango_sticky", "milk_tea" },
	cafe = { "coffee", "milk_tea", "water", "mango_sticky" },
	seedshop = { "seed_lettuce", "seed_chili", "seed_tomato", "seed_corn", "seed_rice", "seed_watermelon", "fertilizer", "compost" },
	reststop = { "water", "energy_drink", "moo_ping", "coffee" },
}

-- Kitchen recipes: crops in, a meal out.
Items.RECIPES = {
	{ id = "home_somtam", needs = { chili = 2, tomato = 1 } },
	{ id = "grilled_corn", needs = { corn = 2 } },
	{ id = "garden_salad", needs = { lettuce = 2, tomato = 1 } },
	{ id = "melon_slices", needs = { watermelon = 1 }, makes = 3 },
	{ id = "fried_rice", needs = { rice = 2, chili = 1 } },
}

return Items
