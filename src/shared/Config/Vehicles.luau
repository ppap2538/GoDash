--!strict
-- Every vehicle differs in speed, acceleration, handling, cargo, seats and fuel use.
-- Speeds are studs/second, sizes are studs. `style` picks the body the VehicleFactory builds.
export type Vehicle = {
	pedal: boolean?,
	id: string, name: string, thai: string, class: "bike" | "car", style: string,
	price: number, level: number,
	topSpeed: number, accel: number, brake: number, grip: number, steer: number,
	cargo: number, seats: number, fuelCap: number, fuelUse: number, mass: number,
	len: number, wid: number, height: number, wheelR: number, comfort: number,
	desc: string,
}

local Vehicles = {}

-- (2026-11-17, owner: "every vehicle should go faster": top speed x1.3, acceleration x1.35, brakes x1.15, grip x1.08)
-- (2026-11-19, owner: "ปรับมอไซให้ไวกว่าเดิม เพราะจักรยานไวแล้ว": the engine bikes were hardly quicker than the
-- bicycle; the small ones gained most: Rusty Dream 60->74 km/h and accel 16->27, the others +9..17 % top, +15..40 % accel)
local LIST: { Vehicle } = {
	{ id = "bicycle", name = "Old Bicycle", thai = "จักรยานคู่ใจ", class = "bike", style = "bicycle", pedal = true,
		price = 0, level = 1, topSpeed = 47, accel = 22, brake = 32, grip = 10.5, steer = 36, -- 2026-11-16 owner: "too slow, hard to start" (was 27 / 10)
		cargo = 1, seats = 0, fuelCap = 0, fuelUse = 0, mass = 90, len = 6.4, wid = 1.8, height = 3.4, wheelR = 1.15, comfort = 0.6,
		desc = "Where every rider starts. No fuel, just legs." },
	{ id = "oldmoped", name = "Rusty Dream 100", thai = "มอเตอร์ไซค์มือสอง", class = "bike", style = "oldbike",
		price = 1800, level = 2, topSpeed = 74, accel = 27, brake = 32, grip = 9, steer = 34,
		cargo = 2, seats = 1, fuelCap = 3.5, fuelUse = 0.3, mass = 200, len = 7.0, wid = 2.2, height = 3.4, wheelR = 1.05, comfort = 0.7,
		desc = "Third-hand, smoky and loud, but it has an engine." },
	{ id = "sabai110", name = "Sabai 110", thai = "มอเตอร์ไซค์แม่บ้าน", class = "bike", style = "underbone",
		price = 7500, level = 4, topSpeed = 95, accel = 32, brake = 39, grip = 9.5, steer = 34,
		cargo = 2, seats = 1, fuelCap = 4, fuelUse = 0.22, mass = 220, len = 7.2, wid = 2.2, height = 3.4, wheelR = 1.05, comfort = 0.8,
		desc = "Brand new family bike. Sips fuel, fits any soi." },
	{ id = "zoomer125", name = "Zoomer 125", thai = "สกู๊ตเตอร์", class = "bike", style = "scooter",
		price = 16000, level = 6, topSpeed = 108, accel = 36, brake = 44, grip = 11, steer = 34,
		cargo = 3, seats = 1, fuelCap = 6, fuelUse = 0.26, mass = 250, len = 7.4, wid = 2.4, height = 3.6, wheelR = 0.95, comfort = 1.0,
		desc = "Automatic scooter with a big top box." },
	{ id = "raptor300", name = "Raptor 300", thai = "สปอร์ตไบค์", class = "bike", style = "sport",
		price = 34000, level = 9, topSpeed = 142, accel = 49, brake = 53, grip = 12.5, steer = 30,
		cargo = 2, seats = 1, fuelCap = 11, fuelUse = 0.4, mass = 320, len = 7.8, wid = 2.3, height = 3.6, wheelR = 1.1, comfort = 0.7,
		desc = "Quick sport bike for express orders." },
	{ id = "titan650", name = "Titan 650", thai = "บิ๊กไบค์", class = "bike", style = "bigbike",
		price = 95000, level = 15, topSpeed = 182, accel = 62, brake = 62, grip = 13.5, steer = 28,
		cargo = 3, seats = 1, fuelCap = 15, fuelUse = 0.55, mass = 420, len = 8.4, wid = 2.6, height = 3.9, wheelR = 1.2, comfort = 0.9,
		desc = "Big bike. Fastest way through traffic." },
	{ id = "eco_city", name = "Mira Eco", thai = "อีโคคาร์", class = "car", style = "hatch",
		price = 58000, level = 8, topSpeed = 112, accel = 20, brake = 41, grip = 11, steer = 30,
		cargo = 5, seats = 3, fuelCap = 35, fuelUse = 0.7, mass = 1000, len = 13.5, wid = 6.2, height = 5.4, wheelR = 1.25, comfort = 1.1,
		desc = "Cheap to run. Opens ride-hailing for 3." },
	{ id = "sedan_vios", name = "Viva Sedan", thai = "รถเก๋ง", class = "car", style = "sedan",
		price = 120000, level = 12, topSpeed = 133, accel = 26, brake = 46, grip = 12, steer = 29,
		cargo = 6, seats = 3, fuelCap = 42, fuelUse = 0.85, mass = 1150, len = 15.5, wid = 6.4, height = 5.2, wheelR = 1.3, comfort = 1.3,
		desc = "Comfortable sedan. Passengers tip more." },
	{ id = "pickup_dmax", name = "Kwai Pickup", thai = "รถกระบะ", class = "car", style = "pickup",
		price = 165000, level = 14, topSpeed = 122, accel = 23, brake = 44, grip = 11.5, steer = 28,
		cargo = 12, seats = 1, fuelCap = 60, fuelUse = 1.1, mass = 1500, len = 17.5, wid = 6.8, height = 6.2, wheelR = 1.55, comfort = 1.0,
		desc = "Huge bed for large orders and farm hauls." },
	{ id = "suv_fortune", name = "Fortuna SUV", thai = "รถเอสยูวี", class = "car", style = "suv",
		price = 210000, level = 17, topSpeed = 127, accel = 24, brake = 46, grip = 12, steer = 28,
		cargo = 9, seats = 5, fuelCap = 65, fuelUse = 1.2, mass = 1650, len = 16.5, wid = 6.8, height = 6.6, wheelR = 1.6, comfort = 1.4,
		desc = "Seats 5 and shrugs off rough rural roads." },
	{ id = "lux_e300", name = "Regent E", thai = "รถหรู", class = "car", style = "luxury",
		price = 520000, level = 22, topSpeed = 166, accel = 36, brake = 57, grip = 13.5, steer = 28,
		cargo = 6, seats = 3, fuelCap = 60, fuelUse = 1.3, mass = 1500, len = 16.5, wid = 6.6, height = 5.1, wheelR = 1.4, comfort = 1.9,
		desc = "VIP rides pay the most in this." },
	{ id = "super_gt", name = "Naga GT", thai = "ซูเปอร์คาร์", class = "car", style = "super",
		price = 1500000, level = 30, topSpeed = 218, accel = 59, brake = 74, grip = 15.5, steer = 26,
		cargo = 2, seats = 1, fuelCap = 55, fuelUse = 2.0, mass = 1300, len = 15.5, wid = 6.9, height = 4.2, wheelR = 1.4, comfort = 1.5,
		desc = "The dream. Loud, low and very fast." },
}

Vehicles.List = LIST
Vehicles.ById = {} :: { [string]: Vehicle }
for _, v in ipairs(LIST) do Vehicles.ById[v.id] = v end

-- Upgrades change real driving numbers (see computeStats).
Vehicles.UPGRADES = {
	{ id = "engine", name = "Engine", icon = "🔧", desc = "+7% top speed, +10% acceleration per level" },
	{ id = "tires", name = "Tires", icon = "⭕", desc = "+9% grip per level, much better in rain" },
	{ id = "suspension", name = "Suspension", icon = "🔩", desc = "Smoother ride, less crash damage" },
	{ id = "brakes", name = "Brakes", icon = "🛑", desc = "+15% braking per level" },
	{ id = "eco", name = "Fuel Efficiency", icon = "⛽", desc = "-12% fuel use per level" },
	{ id = "handling", name = "Handling", icon = "🎯", desc = "+8% steering response per level" },
}
Vehicles.MAX_UPGRADE = 3

Vehicles.COLORS = {
	{ name = "GoDash Green", color = Color3.fromRGB(28, 168, 84) },
	{ name = "Pearl White", color = Color3.fromRGB(235, 236, 238) },
	{ name = "Midnight", color = Color3.fromRGB(34, 38, 46) },
	{ name = "Chili Red", color = Color3.fromRGB(196, 44, 40) },
	{ name = "Mekong Blue", color = Color3.fromRGB(40, 104, 196) },
	{ name = "Mango", color = Color3.fromRGB(240, 172, 40) },
	{ name = "Orchid", color = Color3.fromRGB(150, 90, 190) },
	{ name = "Silver", color = Color3.fromRGB(150, 156, 164) },
}
Vehicles.PAINT_PRICE = 250

-- Styling ("แต่งซิ่ง", 2026-11-17 growth plan): looks only, no driving numbers. Bought in the phone's
-- Styling app; going back to "none" / the standard horn is free. owned.style = { glow, plate, sticker, horn }.
Vehicles.STYLE_PRICES = { glow = 1500, plate = 800, sticker = 500, horn = 300, exhaust = 800 }
Vehicles.GLOWS = {
	{ name = "Neon Green", thai = "เขียวนีออน", color = Color3.fromRGB(40, 255, 120) },
	{ name = "Ice Blue", thai = "ฟ้าน้ำแข็ง", color = Color3.fromRGB(60, 190, 255) },
	{ name = "Hot Pink", thai = "ชมพูช็อก", color = Color3.fromRGB(255, 60, 180) },
	{ name = "Purple", thai = "ม่วง", color = Color3.fromRGB(160, 80, 255) },
	{ name = "Red", thai = "แดง", color = Color3.fromRGB(255, 50, 50) },
	{ name = "Orange", thai = "ส้ม", color = Color3.fromRGB(255, 140, 30) },
	{ name = "White", thai = "ขาว", color = Color3.fromRGB(240, 246, 255) },
	{ name = "Gold", thai = "ทอง", color = Color3.fromRGB(255, 200, 60) },
	-- special ones: need = a game pass ("vip" / "neon") or a season unlock key (Config/Season.COSMETICS)
	{ name = "VIP Gold", thai = "ทอง VIP", color = Color3.fromRGB(255, 215, 90), need = "vip" },
	{ name = "Rainbow", thai = "สายรุ้ง", color = Color3.fromRGB(255, 255, 255), need = "neon", rainbow = true },
	{ name = "Sunset", thai = "สีพระอาทิตย์ตก", color = Color3.fromRGB(255, 120, 80), need = "glow_sunset" },
	{ name = "Mint", thai = "สีมิ้นต์", color = Color3.fromRGB(120, 255, 210), need = "glow_mint" },
}
-- stickers on the sides of the delivery bag (bikes) / above the number plate (cars). Made-up slogans only.
Vehicles.STICKERS = {
	{ icon = "🔥", text = "ซิ่ง", color = Color3.fromRGB(230, 50, 40) },
	{ icon = "⚡", text = "สายส่ง", color = Color3.fromRGB(250, 190, 20) },
	{ icon = "🌸", text = "ขอนแก่น", color = Color3.fromRGB(240, 110, 170) },
	{ icon = "🛵", text = "ทางใครทางมัน", color = Color3.fromRGB(40, 120, 220) },
	{ icon = "❤", text = "รักแม่", color = Color3.fromRGB(220, 40, 80) },
	{ icon = "🎶", text = "อีสานบ้านเฮา", color = Color3.fromRGB(130, 70, 200) },
	{ icon = "😎", text = "ไม่ซิ่งไม่หล่อ", color = Color3.fromRGB(30, 30, 36) },
	{ icon = "🍜", text = "หิวตลอด", color = Color3.fromRGB(240, 120, 30) },
	{ icon = "🏆", text = "ซีซัน 1", color = Color3.fromRGB(150, 70, 230), need = "sticker_s1" },
	{ icon = "👑", text = "ตำนานไรเดอร์", color = Color3.fromRGB(200, 150, 20), need = "sticker_legend" },
}
-- exhaust note (EngineSound reads the "Exhaust" attribute): 1 stock, 2 racing pipe, 3 quiet
Vehicles.EXHAUSTS = {
	{ name = "Stock", thai = "ท่อเดิม" },
	{ name = "Racing pipe", thai = "ท่อซิ่ง" },
	{ name = "Quiet", thai = "ท่อเงียบ" },
}
Vehicles.HORNS = {
	{ name = "Standard", thai = "มาตรฐาน", pitch = 1 },
	{ name = "Deep", thai = "เสียงทุ้ม", pitch = 0.72 },
	{ name = "Air horn", thai = "แตรลม", air = true, pitch = 1 },
	{ name = "Beep beep", thai = "ปิ๊ดๆ", pitch = 1.55 },
	{ name = "Bell", thai = "กระดิ่ง", bell = true, pitch = 1 },
	-- 2026-11-19 (TikTok toys: more horns)
	{ name = "Tuk-tuk", thai = "ตุ๊กตุ๊ก", pitch = 1.9 },
	{ name = "Little tune", thai = "แตรเพลง", pitch = 1 },
}
Vehicles.PLATE_MAX = 8 -- characters on a custom plate (Thai letters, A-Z, digits, space, dash)
-- The plate everyone gets until they buy their own: two Thai letters and a number from the user id.
local PLATE_LETTERS = { "กข", "กง", "ขค", "ฆม", "งษ", "จฉ", "ชณ", "ฐฒ", "ทน", "บผ", "พภ", "มย", "รล", "วศ", "สห", "อฮ" }
function Vehicles.defaultPlate(userId: number): string
	local n = math.abs(userId)
	return PLATE_LETTERS[n % #PLATE_LETTERS + 1] .. " " .. tostring(1000 + math.floor(n / 16) % 9000)
end
-- Custom plates are picked, not typed (2026-11-19, for opening the game to all ages: players never type
-- text others see): a word from this list and a number 1-999 ("ซิ่ง 99"). Plates bought before stay.
Vehicles.PLATE_WORDS = {
	"ซิ่ง", "แซ่บ", "เท่", "ไว", "เฮง", "รวย", "ปัง", "ชิล", "หล่อ", "สวย", "GO", "KK", "FAST", "RIDE", "ISAN", "COOL",
}
for _, l in ipairs(PLATE_LETTERS) do table.insert(Vehicles.PLATE_WORDS, l) end
Vehicles.PLATE_LUCKY = { 9, 99, 168, 555, 789, 999 }
function Vehicles.plateText(word: number, num: number): string?
	local w = Vehicles.PLATE_WORDS[word]
	if not w or num ~= math.floor(num) or num < 1 or num > 999 then return nil end
	return w .. " " .. tostring(num)
end

function Vehicles.upgradePrice(v: Vehicle, upgradeId: string, nextLevel: number): number
	local base = math.max(v.price, 3000)
	local k = upgradeId == "engine" and 0.09 or 0.06
	return math.floor(base * k * nextLevel / 10 + 0.5) * 10
end

export type Owned = { engine: number, tires: number, suspension: number, brakes: number, eco: number, handling: number,
	color: number, fuel: number, condition: number }

function Vehicles.newOwned(v: Vehicle): Owned
	return { engine = 0, tires = 0, suspension = 0, brakes = 0, eco = 0, handling = 0, color = 1, fuel = v.fuelCap, condition = 100, tread = 100, oil = 0 }
end

-- Upkeep (2026-11-19, owner: "ทำตามที่แนะนำ": tyres wear, the engine oil needs changing). tread 100 = new tyres, worn
-- down by distance (100 per TREAD_LIFE studs); oil = studs since the last oil change, due after OIL_INTERVAL. Worn
-- tyres hold the road less (dry and wet); overdue oil costs speed and the engine may cut out now and then (client/Drive).
-- Changed at KK Motors, a fuel station or home (server/VehicleService "oil" / "tyres"); insurance does not pay upkeep.
Vehicles.TREAD_LIFE = 300000 -- about 2-3 hours of riding
Vehicles.OIL_INTERVAL = 150000 -- about 1-1.5 hours of riding
function Vehicles.upkeepPrice(v: Vehicle, what: string): number
	local car = v.class == "car"
	if what == "oil" then return car and 450 or 120 end
	return car and 1600 or 350 -- a set of tyres
end

-- The numbers the driving code actually uses.
function Vehicles.computeStats(v: Vehicle, o: any)
	local e, t, s, b, eco, h = o.engine or 0, o.tires or 0, o.suspension or 0, o.brakes or 0, o.eco or 0, o.handling or 0
	local cond = math.clamp((o.condition or 100) / 100, 0, 1)
	local wear = 0.75 + 0.25 * cond -- a worn vehicle is slower
	local tread = math.clamp((o.tread or 100) / 100, 0, 1)
	local oilDue = o.oilDue == true or (o.oil or 0) > Vehicles.OIL_INTERVAL
	if oilDue then wear *= 0.93 end
	return {
		topSpeed = v.topSpeed * (1 + 0.07 * e) * wear,
		accel = v.accel * (1 + 0.10 * e) * wear,
		brake = v.brake * (1 + 0.15 * b),
		grip = v.grip * (1 + 0.09 * t) * (0.8 + 0.2 * tread),
		wetGrip = (0.62 + 0.11 * t) * (0.7 + 0.3 * tread), -- multiplier used when the road is wet
		steer = v.steer,
		steerRate = 3.2 * (1 + 0.08 * h),
		springDamp = 1 + 0.2 * s,
		crashResist = 1 + 0.35 * s,
		comfort = v.comfort * (1 + 0.12 * s),
		fuelUse = v.fuelUse * 0.25 * (1 - 0.12 * eco), -- litres per 1000 studs (280 m)
	}
end

return Vehicles
