-- GoDash dispatcher and job state machine (food delivery + ride-hailing).
--   offline -> online -> offer (accept / decline / timeout) -> to pick-up -> to drop-off -> paid
-- Every step is decided here: the client only says "online", "accept" and "I'm here".
-- A job is removed from the table before it is paid, so a repeated request can never pay twice.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Game = require(Shared.Config.Game)
local Jobs = require(Shared.Config.Jobs)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Delivery = require(script.Parent.DeliveryService)
local Passenger = require(script.Parent.PassengerService)

local Service = {}
local state = {} -- [player] = { online, mode, offer, job, nextAt, declined }
local ctx
local MODES = { food = Delivery, ride = Passenger }
local nextId = 0

local function root(player: Player): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position or nil
end

local function public(st)
	local out = { online = st.online, mode = st.mode }
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
	for _, def in pairs(module.types) do
		local ok = d.level >= def.level
		if def.rainOnly and not raining then ok = false end
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
	local par = math.floor(o.dist / Jobs.PAR_SPEED * o.def.par + Jobs.PAR_PAD)
	st.job = {
		id = o.id, mode = o.mode, def = o.def, module = o.module, pay = o.pay, dist = o.dist,
		pickup = o.pickup, dropoff = o.dropoff, item = o.item, customer = o.customer,
		stage = "pickup", startedAt = os.time(), startedClock = os.clock(), parSeconds = par,
	}
	o.module.onAccept(player, st.job, ctx)
	push(player)
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
	if elapsed < job.dist / fastest * 0.6 then
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
	local tipK = math.clamp((stars - 3) / 2, 0, 1)
	local tipMult = 1
	if ctx.lifestyle.hasBuff(player, "spicy") then tipMult += 0.12 end
	if d.happiness >= 70 then tipMult += 0.08 elseif d.happiness < 25 then tipMult -= 0.2 end
	if job.mode == "ride" then tipMult *= math.clamp(comfort, 0.6, 2) end
	local tip = math.floor(pay * job.def.tipMax * tipK * tipMult + 0.5)
	local exp = math.floor(job.def.exp * (0.4 + stars / 5 * 0.8) + 0.5)

	tip += bonus
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
	ctx.missions.progress(player, job.module.event, 1)
	ctx.missions.progress(player, "earn", pay + tip)

	job.module.onDropoff(player, job, stars, ctx)
	Net.fire(player, "Reward", {
		title = job.mode == "ride" and "Ride complete!" or "Order delivered!",
		money = pay, tip = tip, exp = exp, stars = stars, job = true,
		detail = { time = timeScore, smooth = smooth, safety = safety, seconds = math.floor(elapsed), par = job.parSeconds },
		notes = notes,
	})
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
		job.stage = "dropoff"
		job.pickedAt = os.time()
		job.pickedClock = os.clock()
		ctx.vehicles.resetTelemetry(player)
		job.module.onPickup(player, job, ctx)
		push(player)
	elseif job.stage == "dropoff" then
		if Util.flatDist(pos, job.dropoff.pos) > Game.INTERACT_RANGE + 6 then return toast(player, "Get closer to the drop-off point", true) end
		local ok, why = job.module.canDropoff(player, job, ctx)
		if not ok then return toast(player, why or "Can't finish yet", true) end
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

	local function ensure(player: Player)
		if not state[player] then state[player] = { online = false, mode = "food", nextAt = 0 } end
		return state[player]
	end
	Players.PlayerRemoving:Connect(function(p)
		local st = state[p]
		if st then clearJob(p, st) end
		state[p] = nil
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
					if st.online and not st.offer and not st.job and now >= (st.nextAt or 0) then
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
