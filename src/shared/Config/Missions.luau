-- Missions listen to gameplay events ("delivery", "distance", ...) counted on the server.
local Missions = {}

-- Career missions: always available, done once, in this order of difficulty.
Missions.CAREER = {
	{ id = "c_first", name = "First Order", desc = "Deliver 1 food order", event = "delivery", goal = 1, money = 150, exp = 40 },
	{ id = "c_deliver5", name = "Getting Started", desc = "Deliver 5 food orders", event = "delivery", goal = 5, money = 400, exp = 120 },
	{ id = "c_drive10", name = "Road Warrior", desc = "Drive 10 km", event = "distance", goal = 10000, money = 500, exp = 150 },
	{ id = "c_ride3", name = "Taxi Time", desc = "Complete 3 passenger rides", event = "ride", goal = 3, money = 450, exp = 140 },
	{ id = "c_plant5", name = "Green Thumb", desc = "Plant 5 crops", event = "plant", goal = 5, money = 300, exp = 100, item = "fertilizer", qty = 3 },
	{ id = "c_harvest", name = "Harvest Day", desc = "Harvest 5 crops", event = "harvest", goal = 5, money = 400, exp = 120, item = "seed_tomato", qty = 4 },
	{ id = "c_vehicle", name = "New Wheels", desc = "Buy a new vehicle", event = "buy_vehicle", goal = 1, money = 800, exp = 200 },
	{ id = "c_plot", name = "Home Owner", desc = "Buy a plot of land", event = "buy_plot", goal = 1, money = 2000, exp = 300 },
	{ id = "c_decor", name = "Interior Designer", desc = "Place 5 pieces of furniture", event = "place_furniture", goal = 5, money = 700, exp = 180 },
	{ id = "c_deliver50", name = "Pro Rider", desc = "Deliver 50 food orders", event = "delivery", goal = 50, money = 3000, exp = 700 },
	{ id = "c_drive100", name = "Isan Explorer", desc = "Drive 100 km", event = "distance", goal = 100000, money = 4000, exp = 900 },
	{ id = "c_upgrade", name = "Tuner", desc = "Buy 3 vehicle upgrades", event = "upgrade", goal = 3, money = 900, exp = 220 },
	{ id = "c_cook", name = "Home Chef", desc = "Cook 3 meals at home", event = "cook", goal = 3, money = 600, exp = 160 },
	{ id = "c_five", name = "Five Star Driver", desc = "Get 10 five-star ratings", event = "five_star", goal = 10, money = 1500, exp = 400 },
}

-- Daily pool: three are picked per player per day.
Missions.DAILY = {
	{ id = "d_deliver3", name = "Lunch Rush", desc = "Deliver 3 food orders", event = "delivery", goal = 3, money = 220, exp = 70 },
	{ id = "d_deliver6", name = "Busy Day", desc = "Deliver 6 food orders", event = "delivery", goal = 6, money = 480, exp = 140 },
	{ id = "d_drive5", name = "Daily Commute", desc = "Drive 5 km", event = "distance", goal = 5000, money = 200, exp = 60 },
	{ id = "d_ride2", name = "Pick Me Up", desc = "Complete 2 passenger rides", event = "ride", goal = 2, money = 260, exp = 80, level = 3 },
	{ id = "d_earn", name = "Payday", desc = "Earn ฿800 from jobs", event = "earn", goal = 800, money = 250, exp = 80 },
	{ id = "d_water", name = "Water the Farm", desc = "Water crops 4 times", event = "water", goal = 4, money = 150, exp = 50 },
	{ id = "d_harvest", name = "Fresh Produce", desc = "Harvest 3 crops", event = "harvest", goal = 3, money = 240, exp = 70 },
	{ id = "d_eat", name = "Stay Fed", desc = "Eat 2 meals", event = "eat", goal = 2, money = 120, exp = 40 },
	{ id = "d_sell", name = "Market Seller", desc = "Sell 10 crops", event = "sell_crop", goal = 10, money = 260, exp = 80 },
	{ id = "d_five", name = "Top Service", desc = "Get 2 five-star ratings", event = "five_star", goal = 2, money = 300, exp = 90 },
}
Missions.DAILY_COUNT = 3

Missions.ById = {}
for _, m in ipairs(Missions.CAREER) do Missions.ById[m.id] = m end
for _, m in ipairs(Missions.DAILY) do Missions.ById[m.id] = m end

return Missions
