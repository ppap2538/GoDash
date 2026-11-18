-- GoDash dispatcher and job state machine (food delivery + ride-hailing).
--   offline -> online -> offer (accept / decline / timeout) -> to pick-up -> to drop-off -> paid
-- Every step is decided here: the client only says "online", "accept" and "I'm here".
-- A job is removed from the table before it is paid, so a repeated request can never pay twice.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Game = require(Shared.Config.Game)
local Jobs = require(Shared.Config.Jobs)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Metrics = require(script.Parent.MetricsService) -- Roblox Analytics: onboarding funnel
local Board = require(script.Parent.LeaderboardService) -- weekly Top Riders
local StoreCfg = require(Shared.Config.Store) -- ranks
local SeasonCfg = require(Shared.Config.Season)
local StoreSvc = require(script.Parent.StoreService) -- badges, name tag
local SeasonSvc = require(script.Parent.SeasonService)
local Events = require(script.Parent.EventService) -- Rush Hour
local Delivery = require(script.Parent.DeliveryService)
local Passenger = require(script.Parent.PassengerService)
local Civic = require(script.Parent.CivicJobs) -- 2026-11-18: jobs at the real landmarks, with opening hours

local Service = {}
Service.deliverScene = nil :: ((Player, any) -> any?)? -- server/GhostService: a ghost scene instead of the hand-over
local state = {} -- [player] = { online, mode, offer, job, nextAt, declined }
local ctx
local MODES = { food = Delivery, ride = Passenger }
local Twists = require(script.Parent.TwistService) -- customer surprises (wrong pin, late, extra stops...)
local nextId = 0

local function root(player: Player): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position or nil
end

local function public(st)
	local out = { online = st.online, mode = st.mode, paused = st.paused }
	if st.offer then
		local o = st.offer
		out.offer = {
			id = o.id, mode = o.mode, type = o.def.id, name = o.def.name, icon = o.def.icon, pay = o.pay, exp = o.def.exp,
			dist = o.dist, pickup = o.pickup, dropoff = o.dropoff, item = o.item, customer = o.customer,
			expires = o.expires, seconds = Game.OFFER_SECONDS, bonus = o.bonusText, toPickup = o.toPickup,
		}
	end
	if st.job then
		local j = st.job
		out.job = {
			id = j.id, mode = j.mode, type = j.def.id, name = j.def.name, icon = j.def.icon, pay = j.pay, exp = j.def.exp,
			stage = j.stage, pickup = j.pickup, dropoff = j.dropoff, item = j.item, customer = j.customer,
			dist = j.dist, parSeconds = j.parSeconds, pickedAt = j.pickedAt, startedAt = j.startedAt, now = os.time(),
		}
	end
	return out
end

local function push(player: Player)
	local st = state[player]
	if st then Net.fire(player, "JobUpdate", public(st)) end
end

local function toast(player: Player, text: string, bad: boolean?)
	Net.fire(player, "Notify", "toast", { text = text, bad = bad, good = not bad })
end

local function pickType(player: Player, d, module)
	local raining = ctx.weather.isRaining()
	local v = ctx.vehicles.get(player)
	local slow = (not v) or v.def.topSpeed < 40 -- on foot or a bicycle: only short hops make sense
	local pool, total = {}, 0
	local clock = ctx.time.clock()
	for _, def in pairs(module.types) do
		local ok = d.level >= def.level
		if def.rainOnly and not raining then ok = false end
		if def.hours and not Civic.open(def, clock) then ok = false end -- landmark jobs keep their hours
		if def.maxLevel and d.level > def.maxLevel and not slow then ok = false end
		if slow and module.mode == "food" and def.id ~= "nearby" then ok = false end
		if ok then
			local w = def.weight * ((def.rainOnly and raining) and 2 or 1)
			total += w
			table.insert(pool, { def, w })
		end
	end
	if #pool == 0 then return nil end
	local r = ctx.rng:NextNumber() * total
	for _, e in ipairs(pool) do
		r -= e[2]
		if r <= 0 then return e[1] end
	end
	return pool[1][1]
end

local function makeOffer(player: Player, st, d)
	local pos = root(player)
	if not pos then return end
	local mode = st.mode
	if mode == "both" then
		mode = (d.level >= Game.UNLOCKS.ride and ctx.rng:NextNumber() < 0.4) and "ride" or "food"
	end
	if mode == "ride" and d.level < Game.UNLOCKS.ride then mode = "food" end
	local module = MODES[mode]
	local def = pickType(player, d, module)
	if not def then return end
	if not module.canAccept(player, def, ctx) then
		-- don't offer what the player's vehicle can't do; fall back to the basic type
		def = module.types[mode == "food" and "normal" or "ride"]
		if d.level < def.level or not module.canAccept(player, def, ctx) then
			if mode == "ride" then
				local _, why = module.canAccept(player, def, ctx)
				if not st.warned or os.clock() - st.warned > 40 then
					st.warned = os.clock()
					toast(player, "No rides: " .. (why or "vehicle not suitable"), true)
				end
			end
			return
		end
	end
	local t = module.targets(player, pos, def, ctx)
	if not t and def.civic then
		-- no landmark pair that fits (none near, or none open): an ordinary job instead
		def = module.types[mode == "food" and "normal" or "ride"]
		t = module.targets(player, pos, def, ctx)
	end
	if not t then return end
	local dist = ctx.world.graph:distance(t.pickup.pos, t.dropoff.pos)
	local toPickup = (t.pickup.pos - pos).Magnitude
	local pay = def.base + def.perStud * dist
	local bonus = ctx.weather.payBonus()
	local bonusText
	if bonus > 0 then bonusText = ("🌧 Rain bonus +%d%%"):format(bonus * 100) end
	if ctx.time.isNight() then
		bonus += Jobs.NIGHT_BONUS
		bonusText = (bonusText and bonusText .. " · " or "") .. "🌙 Night +10%"
	end
	if (Workspace:GetAttribute("Songkran") or 0) > os.time() then
		bonus += 0.3
		bonusText = (bonusText and bonusText .. " · " or "") .. "💦 Songkran +30%"
	end
	if Events.active() then
		bonus += Events.BONUS
		bonusText = (bonusText and bonusText .. " · " or "") .. "🔥 Rush Hour +50%"
	end
	-- (2026-11-18) everyone orders at lunch and dinner: food pays a little more then
	if mode == "food" then
		local c = ctx.time.clock()
		if c >= 11 and c < 13 then
			bonus += Jobs.MEAL_BONUS
			bonusText = (bonusText and bonusText .. " · " or "") .. "🍱 Lunch rush +15%"
		elseif c >= 17.5 and c < 19.5 then
			bonus += Jobs.MEAL_BONUS
			bonusText = (bonusText and bonusText .. " · " or "") .. "🍛 Dinner rush +15%"
		end
	end
	pay = math.floor(pay * (1 + bonus) + 0.5)
	nextId += 1
	st.offer = {
		id = "J" .. nextId, mode = mode, def = def, module = module, pay = pay, dist = dist, toPickup = toPickup,
		pickup = t.pickup, dropoff = t.dropoff, item = t.item, customer = t.customer,
		expires = os.clock() + Game.OFFER_SECONDS, bonusText = bonusText,
	}
	Net.fire(player, "JobOffer", public(st).offer)
	push(player)
end

local function clearJob(player: Player, st)
	local job = st.job
	if job then
		job.module.cleanup(job, ctx)
		st.job = nil
	end
end

local function accept(player: Player, st)
	local o = st.offer
	if not o then return end
	local d = Data.get(player)
	if not d then return end
	if d.energy <= 3 then
		toast(player, "You're too tired to work. Rest or have a drink first.", true)
		st.offer = nil
		push(player)
		return
	end
	local ok, why = o.module.canAccept(player, o.def, ctx)
	if not ok then
		toast(player, why or "Can't take this job", true)
		st.offer = nil
		push(player)
		return
	end
	st.offer = nil
	Metrics.step(player, "Accepted an order")
	local par = math.floor(o.dist / Jobs.PAR_SPEED * o.def.par + Jobs.PAR_PAD)
	st.job = {
		id = o.id, mode = o.mode, def = o.def, module = o.module, pay = o.pay, dist = o.dist,
		pickup = o.pickup, dropoff = o.dropoff, item = o.item, customer = o.customer,
		stage = "pickup", startedAt = os.time(), startedClock = os.clock(), parSeconds = par,
	}
	o.module.onAccept(player, st.job, ctx)
	Twists.onAccept(player, st.job)
	push(player)
end

-- Convoy (2026-11-19, "ขบวนไรเดอร์": riding with friends pays). Other riders who are working (a job on
-- the go, or one finished in the last CONVOY_RECENT seconds) within CONVOY_RANGE studs when you finish
-- add CONVOY_EACH of the pay to your tip each, up to CONVOY_MAX riders. Counted for each of them too.
local CONVOY_RANGE, CONVOY_RECENT, CONVOY_EACH, CONVOY_MAX = 160, 150, 0.12, 3
local lastDone = {} :: { [Player]: number }
local function convoyMates(player: Player): number
	local me = root(player)
	if not me then return 0 end
	local n = 0
	for p, st in pairs(state) do
		if p ~= player and p.Parent and (st.job or os.clock() - (lastDone[p] or -1e9) < CONVOY_RECENT) then
			local r = root(p)
			if r and (r - me).Magnitude < CONVOY_RANGE then n += 1 end
		end
	end
	return math.min(n, CONVOY_MAX)
end

local function complete(player: Player, st)
	local job = st.job
	local d = Data.get(player)
	if not job or not d then return end
	-- take the job out of the table first: nothing after this line can run twice for the same job
	st.job = nil
	local elapsed = os.clock() - job.pickedClock
	local v = ctx.vehicles.get(player)
	local tele = ctx.vehicles.telemetry(player) or { harsh = 0, crashes = 0, dist = 0, top = 0 }
	-- sanity: nobody covers the route faster than the fastest car flat out
	local fastest = math.max(v and v.stats.topSpeed * 1.5 or 60, 60)
	-- (Studio only: QaFastJobs lets a test teleport through a job and still see the pay slip)
	if elapsed < job.dist / fastest * 0.6 and not (RunService:IsStudio() and Workspace:GetAttribute("QaFastJobs")) then
		warn(("[Job] %s finished %s impossibly fast (%.1fs for %d studs); not paid"):format(player.Name, job.id, elapsed, job.dist))
		job.module.cleanup(job, ctx)
		toast(player, "Delivery could not be verified.", true)
		push(player)
		return
	end
	local ratio = elapsed / math.max(10, job.parSeconds)
	local timeScore = math.clamp(1.6 - ratio, 0, 1)
	local comfort = v and v.stats.comfort or 0.8
	local smoothPenalty = job.mode == "ride" and 0.1 or (job.def.fragile and 0.14 or 0.05)
	local smooth = math.clamp(1 - tele.harsh * smoothPenalty / comfort, 0, 1)
	local safety = math.clamp(1 - tele.crashes * (job.def.fragile and 0.5 or 0.34) - (tele.red or 0) * 0.25, 0, 1)
	local stars = Jobs.stars(timeScore, smooth, safety, job.def.strict)
	stars = Twists.adjustStars(job, stars)

	local pay = job.pay
	local notes = {}
	if d.energy < 10 then
		pay = math.floor(pay * Game.TIRED_PAY_MULT)
		table.insert(notes, "😪 Tired −20%")
	end
	-- late deliveries are docked; quick ones earn a speed bonus on top of the tip
	local bonus = 0
	if ratio > 2.2 then
		pay = math.floor(pay * 0.6)
		table.insert(notes, "⏰ Very late −40%")
	elseif ratio > 1.5 then
		pay = math.floor(pay * 0.8)
		table.insert(notes, "⏰ Late −20%")
	elseif ratio < 0.7 and tele.crashes == 0 then
		bonus = math.floor(pay * 0.15 + 0.5)
		table.insert(notes, "⚡ Fast delivery bonus +" .. bonus)
	end
	if (tele.red or 0) > 0 then table.insert(notes, ("🚦 %d red light%s on this trip"):format(tele.red, tele.red > 1 and "s" or "")) end
	-- (2026-11-19, the food-spill meter: client/Spill shows each jolt as it happens) an order that arrived exactly
	-- as packed earns a small thank-you; jolts are named on the slip (they already cost stars, so the tip)
	if tele.harsh == 0 and tele.crashes == 0 then
		local care = math.floor(pay * 0.06 + 0.5)
		bonus += care
		table.insert(notes, job.mode == "ride" and ("🙂 Smooth ride bonus +" .. care) or ("🍜 Not a drop spilled +" .. care))
	elseif tele.harsh > 0 then
		table.insert(notes, (job.mode == "ride" and "🤢 Rough ride: %d jolts" or "🍜 Spilled a little: %d jolts"):format(tele.harsh))
	end
	local tipK = math.clamp((stars - 3) / 2, 0, 1)
	local tipMult = 1
	if ctx.lifestyle.hasBuff(player, "spicy") then tipMult += 0.12 end
	if d.happiness >= 70 then tipMult += 0.08 elseif d.happiness < 25 then tipMult -= 0.2 end
	local rankBefore, rankDef = StoreCfg.rankFor((d.stats.deliveries or 0) + (d.stats.rides or 0))
	tipMult += rankDef.tip -- riders with a higher rank get better tips
	if job.mode == "ride" then tipMult *= math.clamp(comfort, 0.6, 2) end
	local tip = math.floor(pay * job.def.tipMax * tipK * tipMult + 0.5)
	local exp = math.floor(job.def.exp * (0.4 + stars / 5 * 0.8) + 0.5)

	tip += bonus
	local mates = convoyMates(player)
	if mates > 0 then
		local extra = math.floor(pay * CONVOY_EACH * mates + 0.5)
		tip += extra
		table.insert(notes, ("🛵🛵 Convoy x%d +%d"):format(mates + 1, extra))
	end
	lastDone[player] = os.clock()
	tip = Twists.adjustTip(player, job, tip, stars, notes)
	Economy.add(player, pay + tip, "job:" .. job.def.id, true)
	Economy.addExp(player, exp)
	Economy.rollDay(d)
	d.daily.jobs += 1
	d.stats[job.module.stat] += 1
	local n = math.min(d.ratingCount, 40)
	d.rating = math.floor(((d.rating * n + stars) / (n + 1)) * 100 + 0.5) / 100
	d.ratingCount += 1
	if stars >= 4.8 then
		d.stats.fiveStars += 1
		ctx.missions.progress(player, "five_star", 1)
	end
	ctx.lifestyle.add(player, -Game.ENERGY_PER_JOB, nil, stars >= 4.5 and 3 or (stars < 3 and -4 or 0))
	Data.touch(player, "stats", "rating", "ratingCount", "daily")
	-- the customer's review (2026-11-18, owner: a history of reviews, how many stars lately, what they
	-- said, what to improve). Tags say why; client/Reviews turns them into the customer's words.
	do
		local tags = {}
		if ratio > 2.2 then table.insert(tags, "verylate") elseif ratio > 1.5 then table.insert(tags, "late") elseif ratio < 0.7 then table.insert(tags, "fast") end
		if smooth < 0.6 then
			table.insert(tags, job.mode == "ride" and "rough" or (job.def.fragile and "spilled" or "bumpy"))
		elseif job.mode == "ride" and smooth >= 0.95 and comfort >= 1 then
			table.insert(tags, "comfy")
		end
		if tele.crashes > 0 then table.insert(tags, "crash") end
		if (tele.red or 0) > 0 then table.insert(tags, "redlight") end
		if job.mode ~= "ride" and ratio < 1 and smooth >= 0.9 and #tags < 2 then table.insert(tags, "hot") end
		if #tags == 0 then table.insert(tags, stars >= 4.5 and "great" or "ok") end
		d.reviews = type(d.reviews) == "table" and d.reviews or {}
		table.insert(d.reviews, 1, { t = os.time(), s = math.floor(stars * 10 + 0.5) / 10, m = job.mode, who = job.customer or "", tip = tip,
			tags = tags, seed = ctx.rng:NextInteger(1, 9999) })
		while #d.reviews > 30 do table.remove(d.reviews) end
		Data.touch(player, "reviews")
	end
	local jobsNow = (d.stats.deliveries or 0) + (d.stats.rides or 0)
	Metrics.jobDone(player, jobsNow)
	Board.job(player, pay + tip, stars)
	-- Tier-A plan: season XP, Rush Hour race, badges, rank-up
	SeasonSvc.addXp(player, SeasonCfg.XP.job + (stars >= 4.8 and SeasonCfg.XP.fiveStar or 0))
	Events.job(player)
	-- the first ten minutes (2026-11-19, owner: "เพิ่มตามแนะนำ"): the third finished job brings a starter gift toward
	-- the first motorbike (once per profile; riders who were past three jobs already never cross it again)
	if jobsNow == 3 and not (type(d.onboard) == "table" and d.onboard.gift) then
		d.onboard = type(d.onboard) == "table" and d.onboard or {}
		d.onboard.gift = true
		Economy.add(player, 1500, "starter_gift", true)
		Data.touch(player, "onboard")
		task.delay(3, function()
			Net.fire(player, "Notify", "bigwin", { title = "Starter gift!", text = "฿1,500 toward your first motorbike · KK Motors", icon = "🎁" })
		end)
	end
	if jobsNow >= 1 then StoreSvc.badge(player, "first") end
	if jobsNow >= 10 then StoreSvc.badge(player, "ten") end
	if jobsNow >= 100 then StoreSvc.badge(player, "hundred") end
	local rankAfter, newRank = StoreCfg.rankFor(jobsNow)
	if rankAfter > rankBefore then
		StoreSvc.refreshTag(player)
		Net.fire(player, "Notify", "bigwin", { title = "Rank up!", text = newRank.thai .. " · " .. newRank.name, icon = "🏅" })
		if rankAfter == StoreCfg.COMPANY.unlockRank then
			toast(player, "🏢 You can open your own rider company now: Company app on the phone")
		end
	end
	ctx.missions.progress(player, job.module.event, 1)
	ctx.missions.progress(player, "earn", pay + tip)

	job.module.onDropoff(player, job, stars, ctx)
	Net.fire(player, "Reward", {
		title = job.mode == "ride" and "Ride complete!" or "Order delivered!",
		money = pay, tip = tip, exp = exp, stars = stars, job = true,
		detail = { time = timeScore, smooth = smooth, safety = safety, seconds = math.floor(elapsed), par = job.parSeconds },
		notes = notes,
	})
	Twists.afterComplete(player, job, stars)
	st.nextAt = os.clock() + ctx.rng:NextNumber(5, 10)
	push(player)
end

local function action(player: Player)
	local st = state[player]
	local job = st and st.job
	local pos = root(player)
	if not job or not pos then return end
	if job.stage == "pickup" then
		if Util.flatDist(pos, job.pickup.pos) > Game.INTERACT_RANGE + 6 then return toast(player, "Get closer to the pick-up point", true) end
		local ok, why = job.module.canPickup(player, job, ctx)
		if not ok then return toast(player, why or "Can't pick up yet", true) end
		if Twists.beforePickup(player, job) then return end
		job.stage = "dropoff"
		job.pickedAt = os.time()
		job.pickedClock = os.clock()
		ctx.vehicles.resetTelemetry(player)
		job.module.onPickup(player, job, ctx)
		Metrics.step(player, "Picked up")
		if job.mode == "food" then Net.fire(player, "Notify", "scene", { kind = "pickup", pos = job.pickup.pos, name = job.pickup.name }) end
		Twists.afterPickup(player, job)
		push(player)
	elseif job.stage == "dropoff" then
		if Util.flatDist(pos, job.dropoff.pos) > Game.INTERACT_RANGE + 6 then return toast(player, "Get closer to the drop-off point", true) end
		local ok, why = job.module.canDropoff(player, job, ctx)
		if not ok then return toast(player, why or "Can't finish yet", true) end
		if Twists.beforeDropoff(player, job) then return end
		if job.mode == "food" then
			-- (2026-11-18) late at night in a lonely place the customer may be... not a customer (server/GhostService)
			local ghost = Service.deliverScene and Service.deliverScene(player, job)
			Net.fire(player, "Notify", "scene", ghost or { kind = "deliver", pos = job.dropoff.pos, name = job.customer })
		end
		if job.module.alight then job.module.alight(player, job, ctx) end
		complete(player, st)
	end
end

function Service.isBusy(player: Player): boolean
	local st = state[player]
	return st ~= nil and st.job ~= nil
end

function Service.start(world, deps)
	ctx = {
		world = world, rng = Random.new(), weather = deps.weather, time = deps.time, vehicles = deps.vehicles,
		npc = deps.npc, missions = deps.missions, lifestyle = deps.lifestyle,
	}
	Twists.init({ world = world, state = state, push = push, npc = deps.npc })

	local function ensure(player: Player)
		if not state[player] then state[player] = { online = false, mode = "food", nextAt = 0 } end
		return state[player]
	end
	Players.PlayerRemoving:Connect(function(p)
		local st = state[p]
		if st then clearJob(p, st) end
		state[p] = nil
		lastDone[p] = nil
	end)

	Net.on("JobSetOnline", { "boolean", "string?" }, function(player, online, mode)
		local st = ensure(player)
		local d = Data.get(player)
		if not d then return end
		if mode == "food" or mode == "ride" or mode == "both" then
			if (mode == "ride" or mode == "both") and d.level < Game.UNLOCKS.ride then
				toast(player, "Ride-hailing unlocks at level " .. Game.UNLOCKS.ride, true)
				mode = "food"
			end
			st.mode = mode
		end
		st.online = online
		if online then
			Metrics.step(player, "Went online")
			st.nextAt = os.clock() + ctx.rng:NextNumber(3, 6)
		else
			st.offer = nil
		end
		push(player)
	end, 3)

	Net.on("JobRespond", { "string", "boolean" }, function(player, id, ok)
		local st = ensure(player)
		if not st.offer or st.offer.id ~= id then return end
		if os.clock() > st.offer.expires then st.offer = nil; push(player); return end
		if ok then
			accept(player, st)
		else
			st.offer = nil
			st.nextAt = os.clock() + ctx.rng:NextNumber(4, 8)
			push(player)
		end
	end, 3)

	Net.on("JobAction", {}, function(player) action(player) end, 2)
	Net.on("JobChoice", { "string", "boolean" }, function(player, id, yes) Twists.choice(player, id, yes) end, 2)

	Net.on("JobCancel", {}, function(player)
		local st = ensure(player)
		if not st.job then return end
		clearJob(player, st)
		local d = Data.get(player)
		if d then
			d.rating = math.max(1, math.floor((d.rating - 0.1) * 100 + 0.5) / 100)
			Data.touch(player, "rating")
		end
		st.nextAt = os.clock() + 12
		toast(player, "Job cancelled. Your rating dropped a little.", true)
		push(player)
	end, 1)

	Net.on("ClientReady", {}, function(player) ensure(player); push(player) end, 1)

	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, st in pairs(state) do
				local d = Data.get(player)
				if d then
					if st.offer and now > st.offer.expires then
						st.offer = nil
						st.nextAt = now + ctx.rng:NextNumber(4, 8)
						push(player)
					end
					-- hungry or exhausted: no new orders until the player has eaten / rested (a job
					-- already under way carries on)
					-- (2026-11-18: and badly hurt from falls: see a doctor first, server/HealthService)
					local need = ctx.lifestyle.need(player) or (require(script.Parent.HealthService).blocked(player) and "hurt" or nil)
					if need ~= st.paused then
						st.paused = need
						if need then
							st.offer = nil
						else
							st.nextAt = math.min(st.nextAt or 0, now + 2)
						end
						push(player)
					end
					if st.online and not st.paused and not st.offer and not st.job and now >= (st.nextAt or 0) then
						st.nextAt = now + 6
						local ok, err = pcall(makeOffer, player, st, d)
						if not ok then warn("[Job] offer failed: " .. tostring(err)) end
					end
					if st.job and st.job.module.tick then
						local ok, err = pcall(st.job.module.tick, player, st.job, ctx)
						if not ok then warn("[Job] tick failed: " .. tostring(err)) end
					end
				end
			end
		end
	end)
end

return Service
