-- Jobs at the real landmarks (2026-11-18, owner: "special jobs at the real places: documents to the
-- Provincial Hall, lunch boxes for the hospital, students to the bus terminal..."). A job type with a
-- `civic` table (Config/Jobs) takes its pick-up and drop-off from here instead of random doors:
--   civic.from = { pois = { kinds } }       the nearest such landmark to the rider
--              | { kitchens = { kinds } }   the nearest open kitchen of those kinds (DeliveryService)
--              | { home = true }            a house near the rider (rides: the passenger's home)
--   civic.to   = { pois = { kinds } }       one of those landmarks (not the pick-up)
--              | { zone = id }              a house or dormitory in that district
--   civic.item, civic.who                   what is carried, who the customer is
-- Returns the same shape as DeliveryService / PassengerService targets, or nil when there is no
-- sensible pair (the dispatcher then offers an ordinary job).
local Civic = {}

local function poisOf(world, kinds)
	local set = {}
	for _, k in ipairs(kinds) do set[k] = true end
	local out = {}
	for id, p in pairs(world.pois) do
		if set[p.kind] and p.door then table.insert(out, { id = id, pos = Vector3.new(p.door.X, 0, p.door.Z), name = p.name, thai = p.thai }) end
	end
	return out
end

local function nearest(list, at: Vector3, except: string?)
	local best, bd
	for _, it in ipairs(list) do
		if it.id ~= except then
			local d = (it.pos - at).Magnitude
			if not bd or d < bd then best, bd = it, d end
		end
	end
	return best, bd
end

-- open kitchens comes from DeliveryService (it knows the opening hours)
function Civic.targets(player: Player, root: Vector3, def, ctx, openKitchens)
	local c = def.civic
	local world = ctx.world
	local rng = ctx.rng
	local pick
	if c.from.pois then
		local d
		pick, d = nearest(poisOf(world, c.from.pois), root)
		if not pick or d > 4500 then return nil end
	elseif c.from.kitchens then
		-- the customer first (the landmark nearest the rider, or a dorm in the district), then an open
		-- kitchen of the right kind near the customer: a short, believable trip, not across the city
		local set = {}
		for _, k in ipairs(c.from.kitchens) do set[k] = true end
		local list = {}
		for _, k in ipairs(openKitchens or {}) do
			if set[k.kind] then table.insert(list, k) end
		end
		local target
		if c.to.pois then
			local t, d = nearest(poisOf(world, c.to.pois), root)
			if not t or d > 6500 then return nil end
			target = t.pos
		else
			target = root
		end
		local best, bd
		for _, k in ipairs(list) do
			local dd = (k.pos - target).Magnitude
			if dd > 450 and dd < 3200 and (k.pos - root).Magnitude < 4500 and (not bd or dd < bd) then best, bd = k, dd end
		end
		pick = best
		if not pick then return nil end
	elseif c.from.home then
		local best, bd
		for _ = 1, 120 do
			local a = world.addresses[rng:NextInteger(1, #world.addresses)]
			local d = (a.pos - root).Magnitude
			if a.kind == "house" and d > 60 and d < 2600 and (not bd or d < bd) then best, bd = a, d end
		end
		if not best then return nil end
		pick = { pos = best.pos, name = "Pick-up point" }
	end
	local drop
	if c.to.pois then
		local list = poisOf(world, c.to.pois)
		local ok = {}
		for _, it in ipairs(list) do
			if it.id ~= pick.id then
				local d = (it.pos - pick.pos).Magnitude
				if d > 350 and d < (def.maxDist or 12000) then table.insert(ok, it) end
			end
		end
		if #ok == 0 then return nil end
		-- the nearer ones come up more often
		table.sort(ok, function(a, b) return (a.pos - pick.pos).Magnitude < (b.pos - pick.pos).Magnitude end)
		drop = ok[math.min(#ok, 1 + math.floor(rng:NextNumber() ^ 2 * #ok))]
	elseif c.to.zone then
		for _ = 1, 200 do
			local a = world.addresses[rng:NextInteger(1, #world.addresses)]
			local dd = (a.pos - pick.pos).Magnitude
			if a.zone == c.to.zone and a.kind == "house" and dd > 350 and dd < (def.maxDist or 9000) then
				drop = { pos = a.pos, name = c.to.name or "Dormitory" }
				break
			end
		end
		if not drop then return nil end
	end
	if not pick or not drop then return nil end
	local who = c.who or { "Khun Somchai" }
	return {
		pickup = { pos = pick.pos, name = pick.name, thai = pick.thai },
		dropoff = { pos = drop.pos, name = drop.name, thai = drop.thai },
		item = c.item or "Order",
		customer = who[rng:NextInteger(1, #who)],
	}
end

-- Is this job type on offer at this hour? (Config/Jobs `hours` = { { from, to }, ... }, game clock)
function Civic.open(def, clock: number): boolean
	if not def.hours then return true end
	for _, w in ipairs(def.hours) do
		if w[1] <= w[2] then
			if clock >= w[1] and clock < w[2] then return true end
		elseif clock >= w[1] or clock < w[2] then
			return true
		end
	end
	return false
end

return Civic
