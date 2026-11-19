-- Customer twists on jobs (owner, 2026-11-17: "Thai society, satire, funny"). Almost half of all jobs
-- get one surprise, the everyday comedy of a rider's life:
--   wrongpin   the pin is on the wrong soi; at the pin the customer calls and sends the real place
--   late       "coming down now!" means a long wait at the door (a ride: the passenger isn't ready)
--   noanswer   the customer doesn't pick up: call again (twice), then the wait
--   addon      food: "can you stop for ice on the way?" yes = a stop at a convenience store (pay ฿20,
--              big tip), no = a sulky customer may knock half a star off
--   influencer ride: "can we stop at that new café for photos?" yes = a café stop and a tip, no = a
--              grumpy review
-- On top: funny reviews and the odd "thank you 🙏" instead of a tip, all posted in the City Feed.
-- JobService calls the hooks; messages go out in both languages (Notify toast { text, th }).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local Economy = require(script.Parent.EconomyService)

local Twists = {}
local ctx
local rng = Random.new()
local CHANCE = 0.45

local function toast(player: Player, en: string, th: string, bad: boolean?)
	Net.fire(player, "Notify", "toast", { text = en, th = th, bad = bad, good = not bad })
end
local function feed(player: Player, key: string, vars: any?)
	Net.fire(player, "Notify", "feed", { key = key, vars = vars })
end
local function who(job): string
	return job.customer or "Customer"
end

local POOL = {
	food = { { "wrongpin", 25 }, { "late", 25 }, { "noanswer", 20 }, { "addon", 30 } },
	ride = { { "late", 30 }, { "wrongpin", 25 }, { "influencer", 45 } },
}

function Twists.init(c) ctx = c end

local function nearestShop(kind: string, from: Vector3)
	local best, bd
	for _, s in ipairs(ctx.world.shops) do
		if s.kind == kind then
			local d = Util.flatDist(s.pos, from)
			if not bd or d < bd then best, bd = s, d end
		end
	end
	return best, bd
end

-- Memos from the customer (2026-11-19, TikTok toys "funny orders"): the notes people really type in the
-- delivery app, a third of the time, shown when the job is taken. Jokes only: nothing changes the job.
local MEMOS = {
	food = {
		{ "Not spicy please. But 20 chillies on the side.", "ไม่เผ็ดนะคะ แต่ขอพริกแยก 20 เม็ด" },
		{ "Don't call when you arrive, just shout the dog's name: Khao Tang.", "ถึงแล้วไม่ต้องโทร ตะโกนเรียกหมาได้เลย ชื่อข้าวตัง" },
		{ "Tell the cook: tastier than yesterday, please.", "ฝากบอกแม่ค้าว่า ขอแบบอร่อยกว่าเมื่อวาน" },
		{ "Don't ring the bell, the baby just fell asleep 🤫", "อย่ากดกริ่งนะ ลูกเพิ่งหลับ 🤫" },
		{ "Three sets of cutlery please. It's just me.", "ขอช้อนส้อม 3 ชุด กินคนเดียวค่ะ" },
		{ "Hang it on the door by the cactus pot (there are 12).", "แขวนไว้หน้าประตู ข้างกระถางกระบองเพชร (มี 12 กระถาง)" },
		{ "Not angry if you're late. Just a little sulky.", "มาช้าไม่โกรธนะ แค่งอนนิดนึง" },
		{ "Call before you arrive. I won't pick up though.", "โทรมาก่อนถึงนะ แต่ไม่รับสายนะ" },
		{ "The third pink house... or the fourth, I forget.", "บ้านสีชมพูหลังที่ 3 ...หรือ 4 จำไม่ได้" },
		{ "Lots of straws please, it's for an art project.", "ขอหลอดเยอะ ๆ จะเอาไปทำงานประดิษฐ์" },
		{ "My cat loves riders. Expect your hand to be licked.", "แมวที่บ้านชอบไรเดอร์ เตรียมโดนเลียมือ" },
		{ "Bring some encouragement too, I have an exam tomorrow.", "ฝากซื้อกำลังใจมาด้วย พรุ่งนี้สอบ" },
	},
	ride = {
		{ "Luk thung music all the way, please.", "ขอเปิดเพลงลูกทุ่งตลอดทางนะ" },
		{ "Three big bags and one chicken.", "มีกระเป๋าใบใหญ่ 3 ใบ กับไก่ 1 ตัว" },
		{ "I'm in a big hurry! Drive slowly though, I'm scared.", "รีบมากกก แต่ขับช้า ๆ นะ กลัว" },
		{ "Going on a first date. Hype me up, please.", "จะไปเดทแรก ช่วยอวยหน่อย" },
		{ "Waiting outside the corner shop... every corner shop in the soi.", "ยืนรอหน้าร้านสะดวกซื้อ...ทุกร้านในซอยเลย" },
	},
}

-- after the job module's own onAccept (the customer already waits at the real door)
function Twists.onAccept(player: Player, job)
	local memos = MEMOS[job.mode]
	if memos and rng:NextNumber() < 0.33 then
		local m = memos[rng:NextInteger(1, #memos)]
		task.delay(1.2, toast, player, "📝 " .. who(job) .. ": " .. m[1], "📝 " .. who(job) .. ": " .. m[2])
	end
	-- QA hook (Studio only): Workspace QaTwist = a twist id ("noanswer", "wrongpin", ...) -> every job gets it
	local qa = game:GetService("RunService"):IsStudio() and workspace:GetAttribute("QaTwist")
	if type(qa) ~= "string" and rng:NextNumber() > CHANCE then return end
	local pool = POOL[job.mode]
	if not pool then return end
	if type(qa) == "string" then pool = { { qa, 1 } } end
	local total = 0
	for _, e in ipairs(pool) do total += e[2] end
	local r = rng:NextNumber() * total
	for _, e in ipairs(pool) do
		r -= e[2]
		if r <= 0 then job.twist = e[1] break end
	end
	job.twist = job.twist or pool[1][1]
	job.tipBonus, job.starAdj, job.twistNotes = 0, 0, {}
	if job.twist == "wrongpin" then
		-- a door 120-260 studs from the real one
		local real = job.dropoff.pos
		for _ = 1, 40 do
			local a = ctx.world.addresses[rng:NextInteger(1, #ctx.world.addresses)]
			local d = Util.flatDist(a.pos, real)
			if d > 120 and d < 260 then
				job.realDrop = job.dropoff
				job.dropoff = { pos = a.pos, name = job.dropoff.name, thai = job.dropoff.thai }
				break
			end
		end
		if not job.realDrop then job.twist = nil end
	end
	-- (2026-11-19, owner: "the customer stands downstairs but won't take it") nobody waits at the door when they
	-- won't pick up, or when the pin is on the wrong soi: they come out when they answer / at the real door
	if (job.twist == "noanswer" or job.twist == "wrongpin") and job.module and job.module.hideCustomer then
		job.module.hideCustomer(job, ctx)
	end
end

-- a choice the client answers (client/Choice); the answer comes back through Twists.choice
local function ask(player: Player, job, en: string, th: string, yesEn: string, yesTh: string, noEn: string, noTh: string)
	job.asked = true
	Net.fire(player, "JobEvent", { id = job.id, icon = job.mode == "ride" and "🧍" or "💬",
		title = { en = (job.mode == "ride" and "Your passenger: " or "Message from ") .. who(job), th = (job.mode == "ride" and "ผู้โดยสาร: " or "ข้อความจาก ") .. who(job) },
		text = { en = en, th = th }, answers = { { en = yesEn, th = yesTh }, { en = noEn, th = noTh } }, seconds = 15 })
end

function Twists.afterPickup(player: Player, job)
	if job.twist ~= "addon" and job.twist ~= "influencer" then return end
	task.delay(rng:NextNumber(5, 10), function()
		if job.cleaned or job.stage ~= "dropoff" or job.asked then return end
		local st = ctx.state[player]
		if not st or st.job ~= job then return end
		if job.twist == "addon" then
			ask(player, job, "Could you grab a bag of ice from a convenience store on the way? 🥺 I'll tip you!",
				"แวะซื้อน้ำแข็งที่ร้านสะดวกซื้อให้หน่อยได้ไหมคะ 🥺 เดี๋ยวทิปให้นะ",
				"Sure!", "ได้เลยครับ", "Sorry, can't", "ขอโทษ ไม่สะดวก")
		else
			ask(player, job, "Can we stop at that new café for a few photos? 📸 Just a minute!",
				"พี่ๆ แวะร้านกาแฟเปิดใหม่แป๊บนึงได้ไหม ขอถ่ายรูปลงไอจี 📸 แป๊บเดียว!",
				"OK, let's stop", "แวะให้ครับ", "I'm in a hurry", "รีบอยู่ครับ")
		end
	end)
end

function Twists.choice(player: Player, jobId: string, yes: boolean)
	local st = ctx.state[player]
	local job = st and st.job
	if not job or job.id ~= jobId or not job.asked or job.answered or job.stage ~= "dropoff" then return end
	job.answered = true
	local here = job.dropoff.pos
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then here = (hrp.Position + job.dropoff.pos) / 2 end
	if yes then
		local shop = nearestShop(job.twist == "addon" and "convenience" or "cafe", here)
		if not shop then return end
		job.extraStop = { back = job.dropoff, cost = job.twist == "addon" and 20 or 0, tip = job.twist == "addon" and 60 or 80 }
		job.dropoff = { pos = shop.pos, name = "🛒 " .. shop.name, thai = "🛒 " .. (shop.thai or shop.name) }
		toast(player, "📍 Route set to " .. shop.name .. ". Stop there first.", "📍 นำทางไป " .. (shop.thai or shop.name) .. " แวะที่นี่ก่อนนะ")
	else
		if rng:NextNumber() < 0.5 then
			job.starAdj -= 0.5
			table.insert(job.twistNotes, job.twist == "addon" and "😤 Customer sulked: you didn't stop" or "😤 Review: 'the rider wouldn't stop for my photos'")
		end
		toast(player, "OK, straight there then.", "โอเค ไปส่งเลย")
	end
	ctx.push(player)
end

local function waitAtDoor(player: Player, job, seconds: number, en: string, th: string): boolean
	if not job.waitUntil then
		job.waitUntil = os.clock() + seconds
		toast(player, en, th)
		Net.fire(player, "Dialogue", { pos = (job.stage == "pickup" and job.pickup.pos or job.dropoff.pos) + Vector3.new(0, 4, 0), name = who(job), text = en, th = th })
		return true
	end
	local left = job.waitUntil - os.clock()
	if left > 0 then
		toast(player, ("⏳ Still waiting... %d s"):format(math.ceil(left)), ("⏳ ยังไม่มา... อีก %d วิ"):format(math.ceil(left)), true)
		return true
	end
	return false
end

-- true = the pick-up is held back this time
function Twists.beforePickup(player: Player, job): boolean
	if job.twist == "late" and job.mode == "ride" then
		if waitAtDoor(player, job, rng:NextInteger(8, 13), "📱 Passenger: 'Coming! Just finishing my make-up!'", "📱 ผู้โดยสาร: 'รอแป๊บนะ ยังแต่งหน้าไม่เสร็จ!'") then return true end
		if not job.waitPaid then
			job.waitPaid = true
			job.tipBonus += 20
			table.insert(job.twistNotes, "⏳ Waited for the passenger +20")
			feed(player, "twist_late", { who = who(job) })
		end
	end
	return false
end

-- true = the drop-off is held back this time (a call, a wait, a new place, an extra stop)
function Twists.beforeDropoff(player: Player, job): boolean
	if job.extraStop then
		local x = job.extraStop
		job.extraStop = nil
		job.dropoff = x.back
		if x.cost > 0 then Economy.spend(player, x.cost, "twist") end
		job.tipBonus += x.tip
		if job.twist == "addon" then
			table.insert(job.twistNotes, ("🧊 Picked up ice for the customer +%d"):format(x.tip))
			toast(player, ("🧊 Bought the ice (−฿%d). Now on to the customer!"):format(x.cost), ("🧊 ซื้อน้ำแข็งแล้ว (−฿%d) ไปส่งลูกค้าต่อเลย!"):format(x.cost))
			feed(player, "twist_addon")
		else
			table.insert(job.twistNotes, ("📸 Photo stop for the passenger +%d"):format(x.tip))
			toast(player, "📸 Click! Click! 48 photos later... off we go!", "📸 แชะ! แชะ! ถ่ายไป 48 รูป... ไปต่อกัน!")
			feed(player, "twist_influencer")
		end
		ctx.push(player)
		return true
	end
	if job.twist == "wrongpin" and job.realDrop then
		job.dropoff = job.realDrop
		job.realDrop = nil
		job.parSeconds += 60
		if job.module and job.module.spawnCustomer then job.module.spawnCustomer(job, ctx) end -- waiting at the real door
		toast(player, "📞 " .. who(job) .. ": 'Oh, not there! I'm one soi over, opposite the tyre shop. Sending the pin again!'",
			"📞 " .. who(job) .. ": 'อ้าว ไม่ใช่ตรงนั้นค่ะ! อยู่อีกซอยนึง ตรงข้ามร้านยาง เดี๋ยวส่งหมุดใหม่ให้นะ'", true)
		feed(player, "twist_wrongpin")
		ctx.push(player)
		return true
	end
	if job.twist == "noanswer" and (job.calls or 0) < 2 then
		job.calls = (job.calls or 0) + 1
		-- (2026-11-19, owner: "a cutscene when the customer doesn't pick up") the call scene: ringing, no answer
		Net.fire(player, "Notify", "scene", { kind = "call", outcome = "noanswer", n = job.calls, name = who(job) })
		return true
	end
	if job.twist == "noanswer" and not job.callAnswered then
		-- the third call: they pick up, and come down to the door a few seconds later
		job.callAnswered = true
		Net.fire(player, "Notify", "scene", { kind = "call", outcome = "answer", name = who(job) })
		task.delay(4, function()
			if job.module and job.module.spawnCustomer and not job.npc then job.module.spawnCustomer(job, ctx) end
		end)
	end
	if (job.twist == "late" and job.mode == "food") or job.twist == "noanswer" then
		if waitAtDoor(player, job, job.twist == "noanswer" and 6 or rng:NextInteger(9, 14),
			"📱 " .. who(job) .. ": 'Coming down now!' (Thai 'now')", "📱 " .. who(job) .. ": 'รอแป๊บนะคะ ลงไปแล้วๆ'") then return true end
		if not job.waitPaid then
			job.waitPaid = true
			job.tipBonus += 20
			table.insert(job.twistNotes, "⏳ 'Sorry for the wait!' +20")
			feed(player, "twist_late", { who = who(job) })
		end
	end
	return false
end

function Twists.adjustStars(job, stars: number): number
	return math.clamp(stars + (job.starAdj or 0), 1, 5)
end

-- the tip after twists; adds notes
function Twists.adjustTip(player: Player, job, tip: number, stars: number, notes: { string }): number
	tip += job.tipBonus or 0
	-- motorbike-taxi turf (server/StreetService): members get a bonus, outsiders lose part of the tip
	if job.mode == "ride" then
		local Street = require(script.Parent.StreetService)
		local stand = Street.winAt(job.pickup.pos)
		if stand then
			if Street.isMember(player) then
				local b = math.floor(tip * 0.15 + 5)
				tip += b
				table.insert(notes, ("🛵 Taxi-stand bonus +%d"):format(b))
			elseif rng:NextNumber() < 0.6 then
				local cut = math.floor(tip * 0.2 + 0.5)
				tip -= cut
				table.insert(notes, ("👀 The stand boss didn't like that pick-up −%d"):format(cut))
				feed(player, "win_warn", { pos = stand.pos })
			end
		end
	end
	for _, n in ipairs(job.twistNotes or {}) do table.insert(notes, n) end
	if tip > 0 and tip <= 30 and stars >= 4 and rng:NextNumber() < 0.08 then
		table.insert(notes, "🙏 Tip: 'thank you!' (no money)")
		feed(player, "thanks_tip")
		return 0
	end
	return tip
end

-- after the pay slip: a review in the City Feed now and then
function Twists.afterComplete(player: Player, job, stars: number)
	if stars >= 4.6 and rng:NextNumber() < 0.35 then
		feed(player, "review_good", { who = who(job) })
	elseif stars < 3 and rng:NextNumber() < 0.6 then
		feed(player, "review_bad", { who = who(job) })
	end
end

return Twists
