-- The bill after an accident (2026-11-18, owner: "hitting people or other cars should cost money").
-- client/Accident reports "ped:<speed>" or "car:<speed>" (studs/s at the hit); the amount grows with
-- the speed and is capped (see below), taken from cash (never below zero), and the City Feed hears about it.
-- Nothing goes to another player (no reason to stand in someone's way on purpose).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Fines = require(script.Parent.FineService)
local City = require(script.Parent.CityRemote)
local Insurance = require(script.Parent.InsuranceService)

local Service = {}
local last = {} :: { [Player]: number }

-- 2026-11-18 owner: "the bill must make sense next to what you earn, or one hit wipes you out and the
-- fun is gone". A delivery pays about ฿60-250 (Config/Jobs), police tickets are ฿100-300, so a bump at
-- walking pace costs about one delivery and the worst crash about three to four. Never more than a
-- quarter of the cash in your pocket (SHARE), so nobody is left broke by one accident.
-- (Was 600 + 28/stud/s up to 4,500 and 400 + 32 up to 5,000 for the first test build.)
Service.PED = { base = 120, perSpeed = 5, cap = 450 } -- hospital bill: ~฿165 at 9 studs/s, ฿450 from ~66
Service.CAR = { base = 80, perSpeed = 5, cap = 600 } -- repair bill: ~฿180 at 20, ~฿355 at 55, ฿600 from ~104
Service.SHARE = 0.25
-- (2026-11-19, viral pack) the fake-injury scammer (client/Accident): someone throws themselves at a slow bike,
-- the CCTV replay shows no hit, and they pay the rider for the trouble. People live only on the clients, so the
-- server can't check it: a small sum, at most SCAM_DAY a real day and one a minute.
Service.SCAM = { min = 80, max = 150 }
Service.SCAM_DAY = 3
local lastScam = {} :: { [Player]: number }
-- (2026-11-20, owner: "อุบัติเหตุบางกรณีที่เราไม่ใช่คนผิดเราต้องได้ค่าเสียหายนะ") another vehicle ran into you
-- (client/Accident theyHitMe: they came at you faster than you at them, or you stood still): their side pays your
-- repair, on the same scale as a bill you would pay. The client decides who hit whom and the server can't check it,
-- so it is capped like the scammer: BYTHEM_DAY a real day, one every 15 s (shared with the bills).
Service.BYTHEM_DAY = 5

local function byThem(player: Player, d, speed: number)
	local Economy = require(script.Parent.EconomyService)
	Economy.rollDay(d)
	local n = tonumber(d.daily.bythem) or 0
	if n >= Service.BYTHEM_DAY then return true, "", { amount = 0, theirs = true } end
	d.daily.bythem = n + 1
	local t = Service.CAR
	local amount = math.min(t.cap, math.floor((t.base + t.perSpeed * math.clamp(speed, 0, 200)) / 10 + 0.5) * 10)
	Economy.add(player, amount, "accident_comp")
	Data.touch(player, "daily")
	return true, "", { amount = amount, theirs = true }
end

local function scam(player: Player, d)
	if os.clock() - (lastScam[player] or -1e9) < 60 then return false, "" end
	lastScam[player] = os.clock()
	local Economy = require(script.Parent.EconomyService)
	Economy.rollDay(d)
	local n = tonumber(d.daily.scams) or 0
	if n >= Service.SCAM_DAY then return true, "", { scam = true, amount = 0 } end
	d.daily.scams = n + 1
	local amount = math.random(Service.SCAM.min // 10, Service.SCAM.max // 10) * 10
	Economy.add(player, amount, "scam_caught")
	Data.touch(player, "daily")
	return true, "", { scam = true, amount = amount }
end

function Service.start()
	game:GetService("Players").PlayerRemoving:Connect(function(p) last[p] = nil; lastScam[p] = nil end)
	City.register("accident", function(player, arg)
		local d = Data.get(player)
		if not d or type(arg) ~= "string" then return false, "" end
		local kind, s = arg:match("^(%a+):(%d+)$")
		local speed = tonumber(s)
		if kind == "scam" and speed then return scam(player, d) end
		if (kind ~= "ped" and kind ~= "car" and kind ~= "bythem") or not speed then return false, "" end
		if os.clock() - (last[player] or -1e9) < 15 then return false, "" end
		last[player] = os.clock()
		if kind == "bythem" then return byThem(player, d, speed) end
		local t = kind == "ped" and Service.PED or Service.CAR
		local amount = math.min(t.cap, math.floor((t.base + t.perSpeed * math.clamp(speed, 0, 200)) / 10 + 0.5) * 10)
		local cash = math.max(0, math.floor(d.money))
		amount = math.min(amount, math.max(math.min(cash, 30), math.floor(cash * Service.SHARE / 10) * 10))
		-- a bad ride also costs a little happiness
		d.happiness = math.max(0, (d.happiness or 50) - (kind == "ped" and 6 or 3))
		Data.touch(player, "happiness")
		-- (2026-11-19, owner: "a cutscene for when they let it go") a light bump at little more than walking
		-- pace: about one in three people let it go. The client plays the scene with "it's fine" instead.
		-- (QaWaive in Studio: always let it go, for recording that scene)
		if (speed < 10 and math.random() < 0.3) or (game:GetService("RunService"):IsStudio() and workspace:GetAttribute("QaWaive")) then
			return true, "", { amount = 0, waived = true }
		end
		-- (2026-11-19) insurance (server/InsuranceService): the insurer pays its share of the bill; fully covered =
		-- nothing counts against your daily limit, and the claim scene brings the surveyor
		local insured = math.floor(amount * Insurance.share(player, "bills") + 0.5)
		if insured >= amount then
			return true, "", { amount = 0, insured = insured }
		end
		-- (2026-11-19) the daily limit (server/FineService): past it the other side lets it go, and the
		-- client plays the same "let it go" scene
		local ok, took, _, n, limit = Fines.charge(player, "bill", amount - insured, kind == "ped" and "accident:ped" or "accident:car")
		if not ok then
			Fines.warn(player, "bill", nil, "", "")
			return true, "", { amount = 0, waived = true }
		end
		return true, "", { amount = took, insured = insured > 0 and insured or nil, n = n, limit = limit }
	end)
end

return Service
