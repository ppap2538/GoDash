-- The "what do I do now?" bar. One card at the top of the screen always says the next thing to do
-- in plain words, with an arrow that points at the place to go and its distance, and a button
-- for the action when there is one. It replaces the old step-by-step tutorial: during the first
-- delivery the same card counts the steps ("First steps 2/5").
-- Also marks the player's own vehicle in the world and binds J (go online / offline).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Vehicles = require(Shared.Config.Vehicles)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local UI = require(script.Parent.UI.Kit)
local Layout = require(script.Parent.UI.Core.Layout)
local UIState = require(script.Parent.UI.Core.UIState)
local State = require(script.Parent.State)
local Drive = require(script.Parent.Drive)
local Feedback = require(script.Parent.Feedback)
local HUD = require(script.Parent.HUD)
local Phone = require(script.Parent.Phone)
local GPS = require(script.Parent.GPS)
local Lang = require(script.Parent.Lang)

local Guide = {}
local C, F = UI.C, UI.F
local player = Players.LocalPlayer
local touch = Layout.isTouch
local L = Lang.pick
local refs = {} :: { [string]: any }
local current = nil :: any -- the last computed objective
local myVehicle: Model? = nil

-- 2026-11-18 owner: the card in the middle of the top was big and hid the traffic lights. It now sits in
-- the top-left column under the money/needs panel (HUD.topLeft), as wide as that column: a title row
-- with the arrow, the detail under it, the button under that. Riding: the title row only.
local ROW_H = 46 -- icon + title + arrow
local DETAIL_H = 32
local BUTTON_H = touch and 40 or 34
local SLIM_H = 40
local slim = false

---------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------
local function rootPos(): Vector3?
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return r and (r :: BasePart).Position or nil
end

local function findVehicle(): Model?
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then return nil end
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("Owner") == player.UserId then return m end
	end
	return nil
end

local function pedalled(): boolean
	local def = myVehicle and Vehicles.ById[myVehicle:GetAttribute("VehicleId")]
	return def ~= nil and def.pedal == true
end

local function key(k: string): string
	return touch and "" or (" [" .. k .. "]")
end

local function setOnline(on: boolean)
	Net.send("JobSetOnline", on, State.job and State.job.mode or "food")
	Feedback.click()
end
Guide.setOnline = setOnline

local function nearestPoi(from: Vector3, kind: string)
	local w = State.world
	if not w then return nil end
	local best, bd
	for _, p in ipairs(w.pois) do
		if p.kind == kind then
			local d = (p.pos - from).Magnitude
			if not bd or d < bd then best, bd = p, d end
		end
	end
	return best
end
local function nearestGas(from: Vector3) return nearestPoi(from, "gas") end

local function placeName(t): string
	if not t then return "" end
	if Lang.code == "th" and t.thai and t.thai ~= "" then return t.thai end
	return Lang.t(t.name or "")
end

---------------------------------------------------------------------------------------------------
-- needs: hungry / exhausted. New orders are paused on the server, so the card leads to food:
-- eat from the bag if there is something good in it, otherwise route to the nearest place that
-- sells it and offer one "eat now" button there.
---------------------------------------------------------------------------------------------------
local Items = require(Shared.Config.Items)
local EAT_RANGE = 50 -- the shop accepts 60 studs; a little margin for lag
local routed = nil :: string? -- the place the GPS was pointed at during this dip (once, never fought)
local routedPos = nil :: Vector3?

local function bagMeal(d, want: string): any
	local best, bv = nil, (want == "hunger") and 15 or 12
	for id, n in pairs(d.inventory or {}) do
		local it = Items.ById[id]
		if it and it.kind == "food" and n > 0 and (it[want] or 0) >= bv then best, bv = it, it[want] end
	end
	return best
end

local function nearestFood(from: Vector3, want: string): any
	local w = State.world
	if not w or not w.food then return nil end
	local best, bd
	local minV = want == "hunger" and 20 or 15
	for _, p in ipairs(w.food) do
		local m = p[want]
		if m and m.value >= minV then
			local dd = Util.flatDist(p.pos, from)
			if not bd or dd < bd then best, bd = p, dd end
		end
	end
	return best, bd
end

local function itemName(id: string): string
	local it = Items.ById[id]
	if not it then return id end
	return (Lang.code == "th" and it.thai) or it.name
end

local function needCard(want: string, d, pos: Vector3?, driving: boolean)
	local hungry = want == "hunger"
	local icon = hungry and "🍜" or "😪"
	local head = hungry and L("You're hungry", "หิวแล้ว") or L("You're exhausted", "เหนื่อยมากแล้ว")
	local paused = L("New orders are paused until you ", "หยุดรับออร์เดอร์ไว้ก่อนจนกว่าจะ") .. (hungry and L("eat.", "กินข้าว") or L("rest.", "ได้พัก"))
	-- something good in the bag: eat it right here
	local meal = bagMeal(d, want)
	if meal then
		return { icon = icon, color = C.orange, warn = true, title = head .. L(": eat from your bag", " · มีของกินในกระเป๋า"),
			detail = paused,
			button = { text = meal.icon .. " " .. L("Eat ", "กิน") .. itemName(meal.id), fn = function()
				local ok, msg = Net.call("Inventory", "eat", meal.id)
				if msg and msg ~= "" then Feedback.toast(msg, ok and "good" or "bad") end
			end } }
	end
	if not pos then return nil end
	local place, dist = nearestFood(pos, want)
	if not place then
		return { icon = icon, color = C.orange, warn = true, title = head,
			detail = hungry and L("Look for a restaurant or market on the map (Phone → Maps).", "หาร้านอาหารหรือตลาดในแผนที่ (มือถือ → แผนที่)")
				or L("Rest on a bench or sala: walk up and press E.", "พักที่ม้านั่งหรือศาลา: เดินไปแล้วกด E") }
	end
	local m = place[want]
	local name = placeName(place)
	if dist <= EAT_RANGE then
		return { icon = icon, color = C.green, title = L("You're at ", "ถึงแล้ว: ") .. name,
			detail = touch and L("Tap the button to buy and eat right away.", "แตะปุ่มเพื่อซื้อแล้วกินทันที")
				or L("Click the button to buy and eat right away.", "คลิกปุ่มเพื่อซื้อแล้วกินทันที"),
			button = { text = (Items.ById[m.id] and Items.ById[m.id].icon or "🍛") .. " " .. L("Eat ", "กิน") .. itemName(m.id) .. " " .. Util.money(m.price), fn = function()
				local ok, msg = Net.call("Shop", "eatnow", place.id, m.id)
				if msg and msg ~= "" then Feedback.toast(msg, ok and "good" or "bad") end
				if ok then Feedback.good() end
			end } }
	end
	-- far away: point the GPS there once per dip (the player can still pick another target). When there
	-- is no target at all any more (a waypoint clears itself 40 studs out, e.g. riding past the shop),
	-- point it there again: the card says "follow the green line", so there must be one (owner,
	-- 2026-11-16: "the green line disappeared").
	if routed ~= place.id or (GPS.target() == nil and dist > 60) then
		routed = place.id
		routedPos = place.pos
		GPS.setTarget(place.pos, name)
	end
	local how = driving and L("Follow the green line.", "ขี่ตามเส้นสีเขียว")
		or (dist < 150 and L("It's close: just walk over.", "อยู่ใกล้แล้ว เดินไปได้เลย"))
		or (myVehicle and L("Get on your vehicle (F) and follow the green line.", "ขึ้นรถ (กด F) แล้วขี่ตามเส้นสีเขียว") or L("Follow the green line.", "เดินตามเส้นสีเขียว"))
	return { icon = icon, color = C.orange, warn = true, target = place.pos,
		title = head .. (hungry and L(": eat at ", " ไปกินที่ ") or L(": coffee at ", " ไปดื่มกาแฟที่ ")) .. name,
		detail = paused .. " · " .. how }
end

---------------------------------------------------------------------------------------------------
-- The first ten minutes (2026-11-19, owner: "เพิ่มตามแนะนำได้เลย"). After the first deliveries, while a new rider
-- waits for the next order, the card suggests the next good thing to try, one at a time:
--   the first motorbike (the third job brings a ฿1,500 starter gift: server/JobService) -> styling it ->
--   Bueng Kaen Nakhon (swan boats, soi dogs, the lake lap) -> clip mode and the replay.
-- A tip goes away once it is done (or its button pressed: City op "onboard"); riders with 14+ jobs see none.
---------------------------------------------------------------------------------------------------
local cheapestBike = math.huge
for _, v in pairs(Vehicles.ById) do
	if v.class == "bike" and not v.pedal and (v.price or 0) > 0 then cheapestBike = math.min(cheapestBike, v.price) end
end

local function seen(d, id: string): boolean
	return type(d.onboard) == "table" and d.onboard[id] == true
end

local function markSeen(id: string)
	task.spawn(function() Net.call("City", "onboard", id) end)
end

local function onboardTip(d, pos: Vector3?)
	local jobs = (d.stats.deliveries or 0) + (d.stats.rides or 0)
	if jobs < 1 or jobs >= 14 then return nil end
	local motorbike = false
	for id in pairs(d.vehicles or {}) do
		local def = Vehicles.ById[id]
		if def and not def.pedal then motorbike = true break end
	end
	if not motorbike then
		if jobs < 3 or (d.money or 0) < cheapestBike then
			return { icon = "🛵", title = L("Your first motorbike is close", "อีกนิดจะได้มอไซคันแรก"),
				detail = jobs < 3 and L(("Finish %d more job%s: a ฿1,500 starter gift is waiting"):format(3 - jobs, 3 - jobs > 1 and "s" or ""),
					("ส่งอีก %d งาน รับของขวัญไรเดอร์ใหม่ ฿1,500"):format(3 - jobs))
					or L(("Save up ฿%d for a motorbike at KK Motors"):format(cheapestBike), ("เก็บเงินให้ถึง ฿%d แล้วไปซื้อมอไซที่ KK Motors"):format(cheapestBike)) }
		end
		local dealer = pos and nearestPoi(pos, "dealer")
		return { icon = "🛵", color = C.green, title = L("Buy your first motorbike!", "ไปซื้อมอไซคันแรกกัน!"),
			detail = L(("You have enough. KK Motors sells one from ฿%d: much faster than pedalling."):format(cheapestBike),
				("เงินพอแล้ว ที่ KK Motors มีมอไซเริ่มต้น ฿%d เร็วกว่าปั่นจักรยานเยอะ"):format(cheapestBike)),
			button = dealer and { text = L("Route to KK Motors", "นำทางไป KK Motors"), fn = function() GPS.setTarget(dealer.pos, placeName(dealer)) end } or nil }
	end
	if not seen(d, "style") then
		return { icon = "🎨", title = L("Make it yours", "แต่งรถให้เป็นของเรา"),
			detail = L("Paint, stickers, underglow, a lucky plate, a funny horn: the Styling app.", "เปลี่ยนสี ติดสติกเกอร์ ไฟใต้ท้อง ป้ายทะเบียนเลขสวย แตรเพลง ในแอปแต่งซิ่ง"),
			button = { text = L("Open Styling", "เปิดแอปแต่งซิ่ง"), fn = function() markSeen("style"); Phone.setOpen(true); Phone.go("styling") end } }
	end
	if jobs >= 6 and not seen(d, "lake") then
		local gates = ReplicatedStorage:FindFirstChild("GoDashTrial")
		local g1 = gates and gates:FindFirstChild("Gate1")
		local lake = g1 and g1:GetAttribute("Pos")
		return { icon = "🦢", title = L("Take a break at Bueng Kaen Nakhon", "แวะพักที่บึงแก่นนคร"),
			detail = L("Pedal a swan boat, adopt a soi dog, race the lake lap.", "ปั่นเรือเป็ด รับเลี้ยงหมาซอย ลองแข่งรอบบึง"),
			button = { text = L("Route to the lake", "นำทางไปบึง"), fn = function()
				markSeen("lake")
				if typeof(lake) == "Vector3" then GPS.setTarget(lake, L("Bueng Kaen Nakhon", "บึงแก่นนคร")) end
			end } }
	end
	if jobs >= 9 and not seen(d, "clip") then
		return { icon = "🎬", title = L("Make a clip", "ถ่ายคลิปเท่ๆ"),
			detail = touch and L("The Clip app frames 9:16 for TikTok; ⏺ records a clip you can share; ⏪ replays your last 10 seconds.", "แอปถ่ายคลิปจัดภาพ 9:16 ลง TikTok ได้เลย ⏺ อัดคลิปแล้วแชร์ได้ ⏪ ดูรีเพลย์ 10 วิล่าสุด")
				or L("B = clip mode 9:16 for TikTok · ⏺ records a clip · L = replay your last 10 seconds", "B = โหมดถ่ายคลิป 9:16 · ⏺ อัดคลิป · L = ดูรีเพลย์ 10 วิล่าสุด"),
			button = { text = L("Try it", "ลองเลย"), fn = function()
				markSeen("clip")
				local ok, Clip = pcall(require, script.Parent.ClipMode)
				if ok and Clip and Clip.open then Clip.open() end
			end } }
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- the objective: what should the player do right now?
--   returns { icon, title, detail, step?, target?, button? = { text, fn }, color?, warn? }
---------------------------------------------------------------------------------------------------
local function compute()
	local d = State.data
	if not d then
		return { icon = "⏳", title = L("Loading your rider profile…", "กำลังโหลดข้อมูลไรเดอร์…"), detail = "" }
	end
	local job = State.job or {}
	local info = Drive.info
	local driving = info.driving == true
	local pos = rootPos()
	local vehName = myVehicle and Lang.t(myVehicle:GetAttribute("VehicleName") or myVehicle.Name) or L("vehicle", "รถ")

	-- a job offer is waiting
	if job.offer then
		return { step = 3, icon = "🔔", color = C.orange, title = L("New order! Take it?", "มีออร์เดอร์ใหม่! รับไหม?"),
			detail = touch and L("The order card is at the bottom. Tap ACCEPT.", "ดูรายละเอียดด้านล่าง แล้วแตะปุ่ม 'รับงาน'")
				or L("The order card is at the bottom. Press Y or click ACCEPT.", "ดูรายละเอียดด้านล่าง แล้วกด Y หรือคลิก 'รับงาน'"),
			button = { text = L("Accept", "รับงาน") .. key("Y"), fn = function() local o = State.job.offer; if o then Net.send("JobRespond", o.id, true) end end } }
	end

	-- a job is running
	if job.job then
		local j = job.job
		local pickup = j.stage == "pickup"
		local ride = j.mode == "ride"
		local t = pickup and j.pickup or j.dropoff
		local dist = pos and Util.flatDist(pos, t.pos) or math.huge
		local close = dist <= Game.INTERACT_RANGE
		local o = { step = pickup and 4 or 5, target = t.pos, icon = pickup and (ride and "🧍" or "🍱") or "📍" }
		if close then
			o.color = C.green
			o.title = pickup and (ride and L("Your passenger is here!", "ถึงจุดรับผู้โดยสารแล้ว!") or L("You're at the restaurant!", "ถึงร้านแล้ว!"))
				or (ride and L("You've arrived!", "ถึงที่หมายแล้ว!") or L("You're at the customer!", "ถึงบ้านลูกค้าแล้ว!"))
			local k = driving and "G" or "E"
			o.detail = touch and L("Tap the green button.", "แตะปุ่มสีเขียว") or L("Press " .. k .. " or click the button.", "กด " .. k .. " หรือคลิกปุ่ม")
			o.button = { text = (pickup and (ride and L("Pick up", "รับผู้โดยสาร") or L("Pick up food", "รับอาหาร")) or (ride and L("Drop off", "ส่งผู้โดยสาร") or L("Deliver", "ส่งอาหาร"))) .. key(k),
				fn = function() Net.send("JobAction") end }
			return o
		end
		if pickup then
			o.title = ride and L("Pick up the passenger: ", "ไปรับผู้โดยสาร: ") .. placeName(t) or L("Collect the food at ", "ไปรับอาหารที่ ") .. placeName(t)
			o.detail = L("Follow the green line on the road. The place has a green light pillar.", "ขี่ตามเส้นสีเขียวบนถนน ร้านมีเสาแสงสีเขียว")
		else
			local who = Lang.t(j.customer or "")
			o.title = ride and L("Take them to ", "ไปส่งที่ ") .. placeName(t) or L("Deliver to ", "ไปส่งให้ ") .. (who ~= "" and who or placeName(t))
			local left = j.pickedAt and (j.parSeconds - (os.time() - j.pickedAt)) or nil
			if left and left < 0 then
				o.warn = true
				o.detail = L("Late by ", "สายแล้ว ") .. Util.duration(-left) .. L(" — the fare goes down. Hurry!", " — ค่าส่งจะลดลง รีบหน่อย!")
			elseif left then
				o.detail = L("Time left ", "เหลือเวลา ") .. Util.duration(left) .. L(" · arrive early for a tip, stop at red lights", " · ส่งไวได้ทิป อย่าฝ่าไฟแดง")
			end
		end
		if not driving and myVehicle and dist > 120 then
			o.detail = L("Get on your vehicle first (F), it's much faster.", "ขึ้นรถก่อน (กด F) จะไปได้เร็วกว่า")
		end
		return o
	end

	-- hurt from falls (server/HealthService): from 80 no new orders until a doctor has seen to it;
	-- from 60 the card suggests the hospital whenever nothing else is going on
	local inj = player:GetAttribute("Injury") or 0
	local hurtCard = nil
	if inj >= 60 and pos then
		local hosp = nearestPoi(pos, "hospital")
		if hosp then
			local dist = Util.flatDist(pos, hosp.pos)
			local must = inj >= 80
			local o = { icon = "🏥", color = C.red, warn = must, target = dist > 30 and hosp.pos or nil,
				title = must and L(("Badly hurt (%d): see a doctor"):format(inj), ("บาดเจ็บหนัก (%d) ต้องไปหาหมอ"):format(inj))
					or L(("Hurt (%d): get it looked at"):format(inj), ("เจ็บพอสมควร (%d) แวะหาหมอ"):format(inj)) }
			if dist <= 30 then
				o.detail = L("Gold card ฿30 + medicine. The queue can be long.", "บัตรทอง ฿30 + ค่ายา คิวอาจจะยาวหน่อย")
				o.button = { text = "🩹 " .. L("Get treated", "รักษาแผล"), fn = function()
					local ok, msg = Net.call("Shop", "heal", "hospital")
					if not ok and msg and msg ~= "" then Feedback.toast(msg, "bad") end
				end }
			else
				if routed ~= "hospital" or (GPS.target() == nil and dist > 60) then
					routed, routedPos = "hospital", hosp.pos
					GPS.setTarget(hosp.pos, placeName(hosp))
				end
				o.detail = (must and L("New orders are paused until you're treated. ", "หยุดรับออร์เดอร์จนกว่าจะรักษา · ") or "")
					.. L("Follow the green line to ", "ไปตามเส้นสีเขียวที่ ") .. placeName(hosp)
			end
			if must then return o end
			hurtCard = o
		end
	end

	-- no job: needs come first (the server holds new orders back until they are met)
	local want = (d.hunger < Game.HUNGRY_AT and "hunger") or (d.energy < Game.TIRED_AT and "energy") or nil
	if want then
		local o = needCard(want, d, pos, driving)
		if o then return o end
	elseif routed and not (routed == "hospital" and inj >= 60) then
		-- fed / rested: drop the route to the restaurant if it is still the GPS target
		local t = State.target
		if t and routedPos and (t.pos - routedPos).Magnitude < 1 then GPS.setTarget(nil) end
		routed, routedPos = nil, nil
	end
	if hurtCard then return hurtCard end

	if not driving then
		if myVehicle then
			local vp = myVehicle:GetPivot().Position
			local dist = pos and Util.flatDist(pos, vp) or 0
			return { step = 1, icon = pedalled() and "🚲" or "🛵", target = dist > 14 and vp or nil,
				title = dist > 14 and (L("Get on your ", "ขึ้น") .. vehName .. L("", "ของคุณ")) or L("Press F to get on", "กด F เพื่อขึ้นรถ"),
				detail = touch and L("Walk to the vehicle with the green tag and tap Drive.", "เดินไปที่รถที่มีป้ายสีเขียว แล้วแตะ 'ขับ'")
					or L("Walk to the vehicle with the green tag and press F.", "เดินไปที่รถที่มีป้ายสีเขียว แล้วกด F") }
		end
		return { step = 1, icon = "🔑", title = L("Bring out your vehicle", "เรียกรถของคุณออกมา"),
			detail = L("Phone → Garage → Bring it to me.", "เปิดมือถือ → โรงรถ → เรียกรถมาหาฉัน"),
			button = { text = L("Open Garage", "เปิดโรงรถ"), fn = function() Phone.setOpen(true); Phone.go("garage") end } }
	end

	-- driving, no job
	if not info.pedal and info.fuelCap and info.fuelCap > 0 and info.fuel / info.fuelCap < 0.15 then
		local gas = pos and nearestGas(pos)
		local t = GPS.target()
		local going = gas and t and not t.job and (t.pos - gas.pos).Magnitude < 5
		return { icon = "⛽", color = C.orange, warn = true, target = going and gas.pos or nil, title = L("Fuel is low!", "น้ำมันใกล้หมด!"),
			detail = going and L("Follow the green line to the fuel station, walk to the pump and press E.", "ขี่ตามเส้นสีเขียวไปปั๊ม แล้วเดินไปที่ตู้กด E")
				or L("Head to the nearest fuel station before you run dry.", "ไปเติมที่ปั๊มใกล้สุดก่อนน้ำมันหมด"),
			button = (not going and gas) and { text = L("Route to fuel", "นำทางไปปั๊ม"), fn = function() GPS.setTarget(gas.pos, gas.name) end } or nil }
	end
	if not job.online then
		return { step = 2, icon = "📲", color = C.green, title = L("Start taking orders", "เริ่มรับงาน"),
			detail = touch and L("Tap the button to go online. Orders will pop up by themselves.", "แตะปุ่มเพื่อเปิดรับงาน แล้วออร์เดอร์จะเด้งขึ้นมาเอง")
				or L("Press J or click the button to go online. Orders pop up by themselves.", "กด J หรือคลิกปุ่มเพื่อเปิดรับงาน แล้วออร์เดอร์จะเด้งขึ้นมาเอง"),
			button = { text = L("▶ Go online", "▶ เริ่มรับงาน") .. key("J"), fn = function() setOnline(true) end } }
	end
	local t = GPS.target()
	if t and not t.job then
		return { icon = "📍", target = t.pos, title = L("Going to ", "กำลังไป ") .. Lang.t(t.name), detail = L("Follow the green line on the road.", "ขี่ตามเส้นสีเขียวบนถนน") }
	end
	-- (2026-11-19) upkeep due (server/VehicleService): overdue engine oil or bald tyres, shown between orders
	if myVehicle and (myVehicle:GetAttribute("OilDue") == true or (myVehicle:GetAttribute("Tread") or 100) < 15) then
		local oil = myVehicle:GetAttribute("OilDue") == true
		local gas = pos and nearestGas(pos)
		return { icon = oil and "🛢" or "🛞", color = C.orange,
			title = oil and L("Engine oil change overdue", "ถึงกำหนดเปลี่ยนน้ำมันเครื่องแล้ว") or L("Your tyres are worn smooth", "ยางหัวโล้นแล้ว ลื่นมาก"),
			detail = oil and L("The engine may cut out. Fuel stations and KK Motors change it (Phone > Garage).", "เครื่องอาจดับกลางทาง เปลี่ยนได้ที่ปั๊มหรือ KK Motors (มือถือ > โรงรถ)")
				or L("Less grip, longer braking. Fuel stations and KK Motors fit new ones.", "เกาะถนนน้อยลง เบรกไกลขึ้น เปลี่ยนได้ที่ปั๊มหรือ KK Motors"),
			button = gas and { text = L("Route to a fuel station", "นำทางไปปั๊ม"), fn = function() GPS.setTarget(gas.pos, gas.name) end } or nil }
	end
	-- (2026-11-19) a new rider between orders: the next thing worth trying
	local tip = onboardTip(d, pos)
	if tip then return tip end
	return { step = 3, icon = "📡", title = L("Looking for an order near you…", "กำลังหาออร์เดอร์ใกล้คุณ…"),
		detail = L("Ride around freely. A new order pops up in a few seconds.", "ขี่เล่นไปรอบๆ ได้เลย ออร์เดอร์ใหม่จะเด้งขึ้นมาในไม่กี่วินาที") }
end

---------------------------------------------------------------------------------------------------
-- card
---------------------------------------------------------------------------------------------------
local STEP_NAMES = {
	{ "Get on", "ขึ้นรถ" }, { "Go online", "เปิดรับงาน" }, { "Accept", "รับออร์เดอร์" }, { "Pick up", "รับอาหาร" }, { "Deliver", "ส่งอาหาร" },
}

local function render(o)
	current = o
	refs.icon.Text = o.icon or "🛵"
	refs.title.Text = o.title or ""
	refs.detail.Text = o.detail or ""
	local accent = o.color or C.green
	refs.accent.BackgroundColor3 = accent
	refs.iconBg.BackgroundColor3 = accent
	refs.detail.TextColor3 = o.warn and Color3.fromRGB(255, 190, 150) or C.textDim
	local d = State.data
	local first = d and ((d.stats.deliveries or 0) + (d.stats.rides or 0) == 0)
	if first and o.step then
		refs.tag.Text = L("FIRST STEPS ", "เริ่มต้น ") .. o.step .. "/5 · " .. L(STEP_NAMES[o.step][1], STEP_NAMES[o.step][2])
	else
		refs.tag.Text = L("WHAT TO DO NOW", "ตอนนี้ต้องทำอะไร")
	end
	local hasBtn = o.button ~= nil
	if hasBtn then refs.button.Text = o.button.text end
	refs.compass.Visible = o.target ~= nil
	local textRight = o.target and 50 or 10
	refs.title.Size = UDim2.new(1, -(50 + textRight), 0, 20)
	refs.tag.Size = UDim2.new(1, -(50 + textRight), 0, 12)
	if refs.resize then refs.resize() end
end

local function signature(o): string
	return table.concat({ o.icon or "", o.title or "", o.detail or "", o.button and o.button.text or "", o.target and "t" or "", tostring(o.step), o.warn and "w" or "" }, "|")
end

local function buildCard(parent: Instance)
	local card = UI.panel(parent, { Name = "Guide", LayoutOrder = 20, Size = UDim2.new(1, 0, 0, ROW_H), BackgroundTransparency = 0.15, ClipsDescendants = true }, 14)
	refs.card = card
	refs.accent = UI.new("Frame", { BackgroundColor3 = C.green, Size = UDim2.new(0, 4, 1, -16), Position = UDim2.fromOffset(0, 8), Parent = card })
	UI.corner(refs.accent, 2)
	local iconBg = UI.new("Frame", { BackgroundColor3 = C.green, Position = UDim2.fromOffset(10, 7), Size = UDim2.fromOffset(32, 32), Parent = card })
	UI.corner(iconBg, 16)
	refs.iconBg = iconBg
	refs.icon = UI.label(iconBg, "🛵", 17, C.white, F.med, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	refs.tag = UI.label(card, "", 10, C.green, F.bold, { Position = UDim2.fromOffset(50, 5), Size = UDim2.new(1, -60, 0, 12) })
	refs.title = UI.label(card, "", 15, C.white, F.black, { Position = UDim2.fromOffset(50, 17), Size = UDim2.new(1, -60, 0, 20) })
	UI.fitText(refs.title, 15, 10)
	refs.detail = UI.label(card, "", 12, C.textDim, F.med, { Position = UDim2.fromOffset(12, ROW_H - 2), Size = UDim2.new(1, -22, 0, DETAIL_H), TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd })
	-- arrow + distance to the target, at the right of the title row
	local compass = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 3), Size = UDim2.fromOffset(44, 42), Visible = false, Parent = card })
	refs.compass = compass
	local ring = UI.new("Frame", { BackgroundColor3 = C.white, BackgroundTransparency = 0.88, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(28, 28), Parent = compass })
	UI.corner(ring, 14)
	UI.stroke(ring, C.green, 2, 0.2)
	refs.arrow = UI.label(ring, "▲", 16, C.green, F.black, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24),
		TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	refs.dist = UI.label(compass, "", 11, C.white, F.black, { Position = UDim2.fromOffset(0, 29), Size = UDim2.new(1, 0, 0, 13), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	refs.button = UI.button(card, "", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -7), Size = UDim2.new(1, -20, 0, BUTTON_H - 6), TextSize = 14, Visible = false }, function()
		if current and current.button then current.button.fn() end
	end)
	UI.fitText(refs.button, 14, 10)
	for _, l in ipairs({ refs.icon, refs.tag, refs.title, refs.detail, refs.dist, refs.button, refs.arrow }) do l:SetAttribute("NoTranslate", true) end
	-- (2026-11-20, owner: "UI ... มันเยอะเกินเหตุ") while riding, a plain "go to X" card is hidden: the turn card at the
	-- top and the minimap already lead the way. A warning or a button still shows it.
	refs.applyVis = function()
		card.Visible = not UIState.get("build") and not UIState.get("modal") and not refs.ridingHidden
	end
	UIState.onChange(refs.applyVis)
	-- the height follows what is shown: title row, detail line(s), button
	local function size()
		local o = current
		local hasDetail = not slim and o ~= nil and (o.detail or "") ~= ""
		local hasBtn = not slim and o ~= nil and o.button ~= nil
		refs.detail.Visible = hasDetail
		refs.button.Visible = hasBtn
		local h = slim and SLIM_H or (ROW_H + (hasDetail and DETAIL_H or 0) + (hasBtn and BUTTON_H or 0))
		card.Size = UDim2.new(1, 0, 0, h)
	end
	refs.resize = size
	size()
	Layout.onChange(size)
end

---------------------------------------------------------------------------------------------------
-- tag over the player's own vehicle
---------------------------------------------------------------------------------------------------
local function buildVehicleTag()
	local bb = Instance.new("BillboardGui")
	bb.Name = "GoDashMyVehicle"
	bb.Size = UDim2.fromOffset(170, 52)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 500
	bb.ResetOnSpawn = false
	bb.Enabled = false
	local card = UI.new("Frame", { BackgroundColor3 = C.green, Size = UDim2.new(1, 0, 0, 40), Parent = bb })
	UI.corner(card, 14)
	UI.stroke(card, C.white, 2)
	local title = UI.label(card, "", 15, C.white, F.black, { Size = UDim2.new(1, -10, 0, 20), Position = UDim2.fromOffset(5, 2), TextXAlignment = Enum.TextXAlignment.Center })
	local sub = UI.label(card, "", 12, C.white, F.bold, { Size = UDim2.new(1, -10, 0, 16), Position = UDim2.fromOffset(5, 21), TextXAlignment = Enum.TextXAlignment.Center })
	title:SetAttribute("NoTranslate", true)
	sub:SetAttribute("NoTranslate", true)
	local tip = UI.label(bb, "▼", 16, C.green, F.black, { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4 })
	tip:SetAttribute("NoTranslate", true)
	bb.Parent = player:WaitForChild("PlayerGui")
	refs.tagGui, refs.tagTitle, refs.tagSub = bb, title, sub
end

local function updateVehicleTag()
	local bb = refs.tagGui
	if not bb then return end
	local show = myVehicle ~= nil and not Drive.info.driving and myVehicle.PrimaryPart ~= nil
	bb.Enabled = show
	if show then
		bb.Adornee = myVehicle.PrimaryPart
		refs.tagTitle.Text = (pedalled() and "🚲 " or "🛵 ") .. L("Your vehicle", "รถของคุณ")
		refs.tagSub.Text = touch and L("Walk up and tap Drive", "เดินไปแล้วแตะ 'ขับ'") or L("Walk up and press F", "เดินไปแล้วกด F")
	end
end

---------------------------------------------------------------------------------------------------
function Guide.start()
	buildCard(HUD.topLeft or Feedback.top) -- under the money/needs panel, out of the way of the road ahead
	buildVehicleTag()

	-- J: go online / offline (keyboard)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.J and State.data then
			local on = State.job and State.job.online
			setOnline(not on)
		end
	end)

	local last = ""
	local acc = 1
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			myVehicle = findVehicle()
			local ok, o = pcall(compute)
			if ok and o then
				-- riding: the card slims to its title (plus the compass or a smaller button; J still works)
				local wantSlim = Drive.info.driving == true and (Drive.info.speed or 0) > 10 and not o.warn
				local hide = wantSlim and o.button == nil
				if hide ~= (refs.ridingHidden == true) then
					refs.ridingHidden = hide
					if refs.applyVis then refs.applyVis() end
				end
				if wantSlim ~= slim and refs.resize then
					slim = wantSlim
					refs.tag.Visible = not slim
					refs.title.Position = UDim2.fromOffset(50, slim and 10 or 17)
					refs.iconBg.Position = UDim2.fromOffset(10, slim and 5 or 7)
					refs.iconBg.Size = slim and UDim2.fromOffset(30, 30) or UDim2.fromOffset(32, 32)
					refs.compass.Position = UDim2.new(1, -6, 0, slim and 0 or 3)
					refs.card.BackgroundTransparency = slim and 0.3 or 0.15
					refs.resize()
				end
				local sig = signature(o)
				if sig ~= last then
					local stepChanged = current and current.step ~= o.step
					last = sig
					render(o)
					if stepChanged then UI.pop(refs.card, 0.94) end
				else
					current = o -- keep the target and button callbacks fresh
				end
			elseif not ok then
				warn("[Guide] " .. tostring(o))
			end
			updateVehicleTag()
		end
		-- arrow: direction of the target relative to where the camera looks
		local o = current
		local cam = Workspace.CurrentCamera
		local pos = rootPos()
		if o and o.target and cam and pos and refs.compass.Visible then
			local look = cam.CFrame.LookVector
			local fwd = Vector3.new(look.X, 0, look.Z)
			local to = Vector3.new(o.target.X - pos.X, 0, o.target.Z - pos.Z)
			if fwd.Magnitude > 0.01 and to.Magnitude > 0.01 then
				fwd, to = fwd.Unit, to.Unit
				local ang = math.atan2(fwd.X * to.Z - fwd.Z * to.X, fwd.X * to.X + fwd.Z * to.Z)
				refs.arrow.Rotation = math.deg(ang)
			end
			local g = GPS.target()
			local byRoad = g and GPS.path and (g.pos - o.target).Magnitude < 3 and GPS.distance > 0
			refs.dist.Text = Lang.t(Util.dist(byRoad and GPS.distance or Util.flatDist(pos, o.target)))
		end
	end)
	Lang.onChange(function() last = "" end)
end

return Guide
